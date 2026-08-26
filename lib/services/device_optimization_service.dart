import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How aggressively a manufacturer's skin interferes with background work.
enum OemRestrictionLevel {
  /// Stock-like behaviour: the Doze exemption is enough.
  none,

  /// Has an extra vendor screen worth visiting, but kills are uncommon.
  moderate,

  /// Known to force stop exempted foreground services (MIUI, One UI, ColorOS,
  /// Funtouch, EMUI). Location sharing is unreliable until the user opts out.
  aggressive,
}

class DeviceInfo {
  final String manufacturer;
  final String brand;
  final String model;
  final int sdkInt;

  const DeviceInfo({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.sdkInt,
  });

  static const unknown = DeviceInfo(
    manufacturer: 'unknown',
    brand: 'unknown',
    model: 'unknown',
    sdkInt: 0,
  );
}

/// Bridges to the vendor power-management screens that decide whether the
/// location service is allowed to keep running.
///
/// Android's own battery-optimisation allowlist is necessary but not
/// sufficient: on several skins a separate "auto start" or "sleeping apps"
/// list overrides it, which is why an app can hold every permission, sit on
/// the Doze allowlist, and still be killed mid-session.
class DeviceOptimizationService {
  static final DeviceOptimizationService _instance =
      DeviceOptimizationService._internal();
  factory DeviceOptimizationService() => _instance;
  DeviceOptimizationService._internal();

  static const _channel = MethodChannel('flockar/device_optimization');

  /// Set once the user has been walked through the setup screen, so it is not
  /// shown again on every launch.
  static const _setupCompletedKey = 'background_setup_completed';

  DeviceInfo? _cachedInfo;

  Future<DeviceInfo> getDeviceInfo() async {
    if (!Platform.isAndroid) return DeviceInfo.unknown;
    if (_cachedInfo != null) return _cachedInfo!;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
      if (raw == null) return DeviceInfo.unknown;
      return _cachedInfo = DeviceInfo(
        manufacturer: (raw['manufacturer'] as String? ?? 'unknown').toLowerCase(),
        brand: (raw['brand'] as String? ?? 'unknown').toLowerCase(),
        model: raw['model'] as String? ?? 'unknown',
        sdkInt: raw['sdkInt'] as int? ?? 0,
      );
    } on PlatformException catch (e) {
      debugPrint('DeviceOptimizationService.getDeviceInfo failed: $e');
      return DeviceInfo.unknown;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('isIgnoringBatteryOptimizations failed: $e');
      return false;
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('requestIgnoreBatteryOptimizations failed: $e');
      return false;
    }
  }

  /// Whether this firmware exposes an auto-start / protected-apps screen.
  Future<bool> hasAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAutoStartSettings') ?? false;
    } on PlatformException catch (e) {
      debugPrint('hasAutoStartSettings failed: $e');
      return false;
    }
  }

  Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAutoStartSettings') ?? false;
    } on PlatformException catch (e) {
      debugPrint('openAutoStartSettings failed: $e');
      return false;
    }
  }

  Future<bool> openAppDetailsSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppDetailsSettings') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('openAppDetailsSettings failed: $e');
      return false;
    }
  }

  Future<OemRestrictionLevel> getRestrictionLevel() async {
    if (!Platform.isAndroid) return OemRestrictionLevel.none;
    final info = await getDeviceInfo();
    return restrictionLevelFor(info.manufacturer);
  }

  @visibleForTesting
  static OemRestrictionLevel restrictionLevelFor(String manufacturer) {
    switch (manufacturer.toLowerCase()) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
      case 'samsung':
      case 'huawei':
      case 'honor':
      case 'oppo':
      case 'realme':
      case 'vivo':
      case 'iqoo':
      case 'oneplus':
      case 'meizu':
      case 'blackview':
        return OemRestrictionLevel.aggressive;
      case 'asus':
      case 'lenovo':
      case 'letv':
      case 'nokia':
      case 'sony':
        return OemRestrictionLevel.moderate;
      default:
        return OemRestrictionLevel.none;
    }
  }

  /// Human-readable steps for the current device, used by the setup screen.
  Future<List<String>> getManualSteps() async {
    final info = await getDeviceInfo();
    switch (info.manufacturer) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return const [
          'Turn on Autostart for Flockar.',
          'Set Battery saver to "No restrictions".',
          'Open Recents, pull the Flockar card down and tap the lock icon so '
              'the memory cleaner skips it.',
        ];
      case 'samsung':
        return const [
          'Add Flockar to "Never sleeping apps" under Battery.',
          'Turn off "Put unused apps to sleep".',
          'Set Flockar\'s battery usage to "Unrestricted".',
        ];
      case 'huawei':
      case 'honor':
        return const [
          'Set Flockar to "Manage manually" in App launch.',
          'Enable Auto-launch, Secondary launch and Run in background.',
        ];
      case 'oppo':
      case 'realme':
        return const [
          'Allow Auto-startup for Flockar.',
          'Set Battery optimisation to "Don\'t optimise".',
          'Turn on "Allow background running".',
        ];
      case 'vivo':
      case 'iqoo':
        return const [
          'Allow high background power consumption for Flockar.',
          'Turn on Auto-start.',
        ];
      case 'oneplus':
        return const [
          'Set Battery optimisation to "Don\'t optimise".',
          'Turn off "Advanced optimisation" / Deep optimisation.',
        ];
      default:
        return const [
          'Allow Flockar to run in the background.',
          'Exclude Flockar from battery optimisation.',
        ];
    }
  }

  Future<bool> isSetupCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupCompletedKey) ?? false;
  }

  Future<void> markSetupCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupCompletedKey, true);
  }

  /// Whether the settings entry should carry a warning badge: the Doze
  /// exemption is missing, or an aggressive skin has never been configured.
  Future<bool> shouldPromptSetup() async {
    if (!Platform.isAndroid) return false;
    if (!await isIgnoringBatteryOptimizations()) return true;
    if (await isSetupCompleted()) return false;
    return await getRestrictionLevel() == OemRestrictionLevel.aggressive;
  }

  /// Whether to open the setup screen unprompted.
  ///
  /// Unlike [shouldPromptSetup] this always defers to [isSetupCompleted], so a
  /// user who has been through the flow is never interrupted again even if
  /// they chose not to change anything.
  Future<bool> shouldAutoPrompt() async {
    if (!Platform.isAndroid) return false;
    if (await isSetupCompleted()) return false;
    if (!await isIgnoringBatteryOptimizations()) return true;
    return await getRestrictionLevel() == OemRestrictionLevel.aggressive;
  }
}
