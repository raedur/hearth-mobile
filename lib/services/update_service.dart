import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _githubRepo = 'raedur/hearth-mobile';

  Future<UpdateInfo?> check(String currentVersion, int currentBuildNumber) async {
    try {
      final info = await _checkGitHub();
      if (info == null) return null;
      if (info.buildNumber <= currentBuildNumber && info.version == currentVersion) return null;

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

  Future<UpdateInfo?> _checkGitHub() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String? ?? '';
      final assets = data['assets'] as List? ?? [];

      final buildMatch = RegExp(r'\+(\d+)$').firstMatch(tag) ?? RegExp(r'(\d+)$').firstMatch(tag);
      final buildNumber = buildMatch != null ? int.parse(buildMatch.group(1)!) : 0;
      final versionMatch = RegExp(r'v?(\d+\.\d+\.\d+)').firstMatch(tag);
      final version = versionMatch != null ? versionMatch.group(1)! : tag;

      final apk = assets.cast<Map<String, dynamic>>().where(
        (a) => (a['name'] as String? ?? '').endsWith('.apk'),
      ).firstOrNull;

      return UpdateInfo(
        version: version,
        buildNumber: buildNumber,
        downloadUrl: apk?['browser_download_url'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
