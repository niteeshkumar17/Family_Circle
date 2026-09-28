import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../services/background_service.dart';
import '../../../services/device_optimization_service.dart';

/// Walks the user through the vendor settings that decide whether location
/// sharing keeps working once the screen is off.
///
/// Every permission can be granted and the app can still be force stopped by a
/// manufacturer's cleaner, so this screen exists to make that invisible layer
/// visible: it reports what is already correct, deep links straight into the
/// screens that are not, and shows whether the tracker has published recently.
class BackgroundSetupScreen extends StatefulWidget {
  const BackgroundSetupScreen({super.key});

  @override
  State<BackgroundSetupScreen> createState() => _BackgroundSetupScreenState();
}

class _BackgroundSetupScreenState extends State<BackgroundSetupScreen>
    with WidgetsBindingObserver {
  static const _accent = Color(0xFF4ECDC4);
  static const _warning = Color(0xFFFFE66D);
  static const _danger = Color(0xFFFF6B6B);

  final _optimization = DeviceOptimizationService();

  DeviceInfo _device = DeviceInfo.unknown;
  List<String> _steps = const [];
  bool _batteryExempt = false;
  bool _hasVendorScreen = false;
  bool _visitedVendorScreen = false;
  bool _locationServiceEnabled = true;
  BackgroundServiceDiagnostics? _diagnostics;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user leaves for a system settings screen and comes back; re-read so
    // the checklist reflects what they just changed.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final device = await _optimization.getDeviceInfo();
    final steps = await _optimization.getManualSteps();
    final exempt = await _optimization.isIgnoringBatteryOptimizations();
    final vendor = await _optimization.hasAutoStartSettings();
    final diagnostics = await BackgroundLocationService().getDiagnostics();
    final locationOn = await LocationPermissionHelper.isLocationServiceEnabled();

    if (!mounted) return;
    setState(() {
      _device = device;
      _steps = steps;
      _batteryExempt = exempt;
      _hasVendorScreen = vendor;
      _locationServiceEnabled = locationOn;
      _diagnostics = diagnostics;
      _loading = false;
    });
  }

  String get _deviceLabel {
    if (_device.manufacturer == 'unknown') return 'your phone';
    final name = _device.manufacturer[0].toUpperCase() +
        _device.manufacturer.substring(1);
    return 'your $name';
  }

  String get _deviceLabelSentenceCase =>
      _deviceLabel[0].toUpperCase() + _deviceLabel.substring(1);

  Future<void> _requestBatteryExemption() async {
    await _optimization.requestIgnoreBatteryOptimizations();
    await _refresh();
  }

  Future<void> _openVendorScreen() async {
    final opened = await _optimization.openAutoStartSettings();
    if (!mounted) return;
    if (opened) {
      setState(() => _visitedVendorScreen = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open that screen automatically. Look for "Battery" or '
            '"Auto start" in your phone settings.',
          ),
        ),
      );
      await _optimization.openAppDetailsSettings();
    }
  }

  Future<void> _finish() async {
    await _optimization.markSetupCompleted();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        // Opaque, otherwise the list scrolls through the title.
        backgroundColor: const Color(0xFF0D0D0D),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Background updates'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _buildIntro(),
                  const SizedBox(height: 24),
                  if (!_locationServiceEnabled) ...[
                    _buildLocationOffBanner(),
                    const SizedBox(height: 16),
                  ],
                  _buildBatteryStep(),
                  const SizedBox(height: 16),
                  if (_hasVendorScreen) ...[
                    _buildVendorStep(),
                    const SizedBox(height: 16),
                  ],
                  _buildHealthCard(),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _finish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      // A minimum rather than a fixed height, so a large
                      // system font scale grows the button instead of
                      // clipping the label.
                      minimumSize: const Size.fromHeight(54),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 250.ms),
            ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Keep sharing when the app is closed',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'To save battery, $_deviceLabel can shut Flockar down while you are '
          'not looking at it. When that happens your family sees an old '
          'location until you open the app again. These two settings stop it.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// Location switched off at the OS level beats every other setting on this
  /// screen, so it is called out above them rather than left to surface as a
  /// failed GPS call in the health card.
  Widget _buildLocationOffBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _danger.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _danger.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_off_rounded, color: _danger, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Location is switched off',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your family cannot see where you are until this is back on. '
            'Nothing else on this screen will help while it is off.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.75), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          _ActionButton(
            label: 'Turn on location',
            color: _danger,
            onPressed: () async {
              await LocationPermissionHelper.openLocationSettings();
              await _refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStep() {
    return _StepCard(
      index: 1,
      title: 'Unrestricted battery usage',
      done: _batteryExempt,
      accent: _accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _batteryExempt
                ? 'Flockar is allowed to run in the background.'
                : 'Android is currently allowed to pause Flockar to save power.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4),
          ),
          if (!_batteryExempt) ...[
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Allow',
              color: _accent,
              onPressed: _requestBatteryExemption,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVendorStep() {
    return _StepCard(
      index: 2,
      // The OS gives no way to read these vendor flags back, so this step is
      // only ever marked as visited, never as verified.
      title: _device.manufacturer == 'samsung'
          ? 'Never sleeping apps'
          : 'Auto start settings',
      done: _visitedVendorScreen,
      accent: _warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_deviceLabelSentenceCase has its own power manager that '
            'overrides the setting above. Open it and:',
            style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          ..._steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: _warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      step,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionButton(
            label: _visitedVendorScreen ? 'Open again' : 'Open settings',
            color: _warning,
            onPressed: _openVendorScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard() {
    final diagnostics = _diagnostics;
    final lastPush = diagnostics?.lastPush;
    final healthy = diagnostics?.isHealthy ?? false;
    final problem = healthy ? null : diagnostics?.problem;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (healthy ? _accent : _warning).withOpacity(0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              healthy
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: healthy ? _accent : _warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !healthy
                      ? 'Not sharing right now'
                      : (diagnostics?.isResting ?? false)
                          ? 'Sharing on, saving battery'
                          : 'Sharing is live',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lastPush == null
                      ? 'No location sent yet.'
                      : 'Last update ${_relative(lastPush)}.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                if (problem != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    problem,
                    style: TextStyle(
                      color: _warning.withOpacity(0.9),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              BackgroundLocationService().forceUpdate();
              await Future<void>.delayed(const Duration(seconds: 2));
              await _refresh();
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.done,
    required this.accent,
    required this.child,
  });

  final int index;
  final String title;
  final bool done;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? accent : accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.black)
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          elevation: 0,
          // A fixed height clipped the label in half on phones running a
          // large display or font size, so let the padding set the height.
          minimumSize: const Size(0, 42),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}
