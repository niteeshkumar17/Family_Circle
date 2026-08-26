import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'background_service.dart';

/// Revives the location tracker after the operating system kills it.
///
/// The foreground service survives Doze and the battery-optimisation allowlist,
/// but not a vendor cleaner: MIUI's "OneKeyClean" and Samsung's app sleep both
/// SIGKILL the process while the service is running, and Android does not
/// restart it afterwards. `autoStartOnBoot` only covers reboots, so without a
/// second mechanism the app stays dark until the user opens it by hand — which
/// is exactly how a device ends up reporting a twelve hour old position.
///
/// Two independent triggers call [reviveIfNeeded]:
///
/// * a periodic WorkManager job, which lives in the system's JobScheduler
///   database and therefore outlives the app process, and
/// * a high priority FCM data message from the server when it notices a member
///   has gone stale.
///
/// Both are allowed to start a location foreground service from the background:
/// the app holds a battery-optimisation exemption, and a high priority message
/// additionally grants a temporary allowlist window.
class TrackerWatchdog {
  static const _tag = 'TrackerWatchdog:';
  static const _uniqueName = 'flockar-tracker-watchdog';
  static const _taskName = 'reviveTracker';

  /// WorkManager will not schedule anything tighter than this.
  static const _period = Duration(minutes: 15);

  /// A tracker that has not published within this window is treated as stuck
  /// even if its service object still exists.
  static const _staleAfter = Duration(minutes: 12);

  /// How long to wait for a nudged service to actually publish. The forced fix
  /// inside the service times out at 20s, so this has to outlast that.
  static const _verifyTimeout = Duration(seconds: 30);
  static const _verifyPollInterval = Duration(seconds: 3);

  static const lastRunKey = 'bg_watchdog_last_run';
  static const lastReviveKey = 'bg_watchdog_last_revive';
  static const reviveCountKey = 'bg_watchdog_revive_count';

  /// Why the most recent run could not repair the tracker, or absent when the
  /// last run succeeded.
  static const lastFailureKey = 'bg_watchdog_last_failure';

  /// Registers the WorkManager callback. Must run in `main()` before any task
  /// is scheduled.
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().initialize(
        trackerWatchdogDispatcher,
        isInDebugMode: false,
      );
    } catch (e) {
      debugPrint('TrackerWatchdog.initialize failed: $e');
    }
  }

  /// Starts the periodic check. Safe to call repeatedly; an existing schedule
  /// is kept rather than restarted, so the timer is not pushed back on every
  /// app launch.
  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        frequency: _period,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        initialDelay: _period,
        // Deliberately unconstrained: a dead tracker must be restarted even on
        // a low battery or an offline device, where it matters most.
        constraints: Constraints(networkType: NetworkType.not_required),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('TrackerWatchdog.schedule failed: $e');
    }
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(_uniqueName);
    } catch (e) {
      debugPrint('TrackerWatchdog.cancel failed: $e');
    }
  }

  /// Restarts the tracker when it is dead, or nudges it when it is alive but
  /// has stopped publishing. Returns true when something was repaired.
  ///
  /// Runs in whichever isolate calls it, so all state is read back from
  /// [SharedPreferences] rather than from memory.
  static Future<bool> reviveIfNeeded({required String trigger}) async {
    try {
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {}

    debugPrint('$_tag fired ($trigger)');

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.setString(lastRunKey,
          '${DateTime.now().toIso8601String()} ($trigger)');
    } catch (e) {
      debugPrint('$_tag prefs unavailable: $e');
    }

    // Nothing to revive when signed out or not yet in a nest; starting the
    // service then would only show a notification with no one to publish to.
    final userId = prefs?.getString(BgPrefsKeys.userId) ?? '';
    final familyIds = prefs?.getString(BgPrefsKeys.familyIds) ?? '';
    if (userId.isEmpty || familyIds.trim().isEmpty) {
      debugPrint('$_tag no user or nest configured, nothing to revive');
      return false;
    }

    if (!await LocationPermissionHelper.hasAllPermissions()) {
      debugPrint('$_tag location permission missing, skipping');
      await _recordFailure(prefs, 'permission_missing',
          'Flockar no longer has permission to read your location.');
      return false;
    }

    // Nothing downstream can succeed with the OS location toggle off, and the
    // only symptom otherwise is a GPS call that throws every fifteen minutes.
    if (!await LocationPermissionHelper.isLocationServiceEnabled()) {
      debugPrint('$_tag location services disabled, cannot revive');
      await _recordFailure(prefs, 'location_services_disabled',
          'The location service on the device is disabled.');
      return false;
    }

    final service = BackgroundLocationService();
    var repaired = false;
    String? failure;

    try {
      final running = await service.isRunning();
      final lastPushRaw = prefs?.getString(BgPrefsKeys.lastPush);
      debugPrint('$_tag service running=$running lastPush=$lastPushRaw');

      if (!running) {
        repaired = await service.start();
        debugPrint('$_tag start() returned $repaired');
        if (repaired) {
          // Publish immediately rather than waiting out the first interval.
          service.forceUpdate();
        } else {
          failure = 'The tracker service refused to start.';
        }
      } else if (_isStale(lastPushRaw)) {
        // Alive but silent, usually a GPS subscription the OS quietly dropped.
        debugPrint('$_tag service alive but stale, forcing an update');
        service.forceUpdate();

        // forceUpdate is fire and forget, so the nudge has to be confirmed
        // against a real publish. Assuming it worked is how a tracker stuck
        // behind a dead GPS used to report a revival every fifteen minutes
        // while its last known position stayed half an hour old.
        repaired = await _awaitFreshPush(prefs, DateTime.tryParse(lastPushRaw ?? ''));
        debugPrint('$_tag nudge ${repaired ? 'produced' : 'did not produce'} '
            'a fresh fix');
        if (!repaired) {
          failure = 'The tracker is running but could not get a location fix.';
        }
      } else {
        debugPrint('$_tag tracker healthy, nothing to do');
      }
    } catch (e) {
      debugPrint('$_tag revive failed: $e');
      await _recordFailure(prefs, 'revive_threw', e.toString());
      return false;
    }

    if (repaired) {
      try {
        await prefs?.setString(lastReviveKey,
            '${DateTime.now().toIso8601String()} ($trigger)');
        await prefs?.setInt(
            reviveCountKey, (prefs.getInt(reviveCountKey) ?? 0) + 1);
        await prefs?.remove(lastFailureKey);
      } catch (_) {}
      debugPrint('$_tag tracker revived by $trigger');
    } else if (failure != null) {
      await _recordFailure(prefs, 'revive_failed', failure);
    }

    return repaired;
  }

  /// Waits for the service to publish, returning true once
  /// [BgPrefsKeys.lastPush] moves past [before].
  static Future<bool> _awaitFreshPush(
    SharedPreferences? prefs,
    DateTime? before,
  ) async {
    if (prefs == null) return false;
    final deadline = DateTime.now().add(_verifyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_verifyPollInterval);
      try {
        await prefs.reload();
      } catch (_) {
        return false;
      }
      final push =
          DateTime.tryParse(prefs.getString(BgPrefsKeys.lastPush) ?? '');
      if (push != null && (before == null || push.isAfter(before))) return true;
    }
    return false;
  }

  /// Records why a run could not repair the tracker. Written to the same key
  /// the service uses so the settings screen renders it without extra
  /// plumbing.
  static Future<void> _recordFailure(
    SharedPreferences? prefs,
    String status,
    String detail,
  ) async {
    final stamp = '${DateTime.now().toIso8601String()} $status: $detail';
    try {
      await prefs?.setString(lastFailureKey, stamp);
      await prefs?.setString(BgPrefsKeys.lastError, stamp);
    } catch (_) {}
  }

  static bool _isStale(String? lastPushIso) {
    if (lastPushIso == null) return true;
    final lastPush = DateTime.tryParse(lastPushIso);
    if (lastPush == null) return true;
    return DateTime.now().difference(lastPush) > _staleAfter;
  }
}

/// WorkManager entry point. Must be a top level function so its callback handle
/// stays valid across process death.
@pragma('vm:entry-point')
void trackerWatchdogDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await TrackerWatchdog.reviveIfNeeded(trigger: 'workmanager');
    // Always report success: a failure would make WorkManager back off and
    // retry on its own schedule, competing with the periodic job.
    return true;
  });
}
