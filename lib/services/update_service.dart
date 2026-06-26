import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;

  const UpdateInfo({required this.version, required this.buildNumber, required this.downloadUrl});
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const _kDismissedBuild = 'hearth_dismissed_update_build';
  static const _bundleId = 'au.id.craig.hearth_app';

  Future<UpdateInfo?> check(String currentVersion, int currentBuildNumber) async {
    try {
      // Try server endpoint first (works for private repos)
      var info = await _checkServer();

      // Fallback: App Store on iOS, Play Store on Android
      info ??= Platform.isIOS ? await _checkAppStore(currentVersion) : null;

      if (info == null) return null;
      if (info.buildNumber <= currentBuildNumber && info.version == currentVersion) return null;

      // Don't re-prompt if user dismissed this build
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getInt(_kDismissedBuild) ?? 0;
      if (info.buildNumber > 0 && info.buildNumber <= dismissed) return null;

      return info;
    } catch (e) {
      debugPrint('UpdateService: check failed: $e');
      return null;
    }
  }

  Future<void> dismiss(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDismissedBuild, buildNumber);
  }

  Future<UpdateInfo?> _checkServer() async {
    final baseUrl = ApiService.baseUrl;
    if (baseUrl == null) return null;

    try {
      final res = await http.get(Uri.parse('$baseUrl/api/app-version'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return UpdateInfo(
        version: data['version'] as String? ?? '',
        buildNumber: (data['buildNumber'] as num?)?.toInt() ?? 0,
        downloadUrl: data['downloadUrl'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<UpdateInfo?> _checkAppStore(String currentVersion) async {
    try {
      final res = await http.get(
        Uri.parse('https://itunes.apple.com/lookup?bundleId=$_bundleId'),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final latest = results[0] as Map<String, dynamic>;
      final storeVersion = latest['version'] as String? ?? '';
      if (storeVersion == currentVersion) return null;

      final trackId = latest['trackId'] as num?;
      final storeUrl = trackId != null
          ? 'https://apps.apple.com/app/id$trackId'
          : '';

      return UpdateInfo(version: storeVersion, buildNumber: 0, downloadUrl: storeUrl);
    } catch (_) {
      return null;
    }
  }
}
