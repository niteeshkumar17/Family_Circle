import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../config/theme_config.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Dio _dio = Dio();
  bool _isChecking = false;

  /// Checks for updates and prompts the user if one is available
  Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateMsg = false}) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      // 1. Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 2. Fetch latest version info from Firestore
      final doc = await _firestore.collection('app_config').doc('version').get();
      if (!doc.exists) {
        _isChecking = false;
        return;
      }

      final data = doc.data()!;
      final latestVersion = data['latestVersion'] as String?;
      final downloadUrl = data['downloadUrl'] as String?;
      final isRequired = data['isRequired'] as bool? ?? false;
      final releaseNotes = data['releaseNotes'] as String? ?? 'A new version is available with bug fixes and improvements.';

      if (latestVersion == null || downloadUrl == null) {
        _isChecking = false;
        return;
      }

      // 3. Compare versions (simple string comparison for now)
      if (_isUpdateAvailable(currentVersion, latestVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, latestVersion, downloadUrl, isRequired, releaseNotes);
        }
      } else if (showNoUpdateMsg && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App is up to date.')),
        );
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// Simple version comparison (e.g., 1.0.0 vs 1.0.1)
  bool _isUpdateAvailable(String current, String latest) {
    try {
      final v1 = current.split('.').map(int.parse).toList();
      final v2 = latest.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        if (v2[i] > v1[i]) return true;
        if (v2[i] < v1[i]) return false;
      }
    } catch (e) {
      // Fallback to simple string comparison if format is non-standard
      return latest.compareTo(current) > 0;
    }
    return false;
  }

  void _showUpdateDialog(
    BuildContext context, 
    String latestVersion, 
    String downloadUrl, 
    bool isRequired,
    String releaseNotes,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !isRequired,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Update Available (v$latestVersion)', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                releaseNotes,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text(
                'The update will download in the background and prompt you to install when ready.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
          actions: [
            if (!isRequired)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later', style: TextStyle(color: Colors.white54)),
              ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _downloadAndInstall(context, downloadUrl, latestVersion);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              child: const Text('Update Now', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAndInstall(BuildContext context, String url, String version) async {
    try {
      // 1. Prepare file path
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/update_v$version.apk';
      
      // Check if file already exists
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading update in background...'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 3. Download APK
      await _dio.download(
        url,
        savePath,
      );

      // 4. Trigger Install
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download complete! Starting installer...'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }

      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
        debugPrint('Failed to open APK: ${result.message}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start installer: ${result.message}'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }

    } catch (e) {
      debugPrint('Download error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download update: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }
}
