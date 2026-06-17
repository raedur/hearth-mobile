import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'storage_keys.dart';

class WifiTrigger {
  final String ssid;
  final String message;

  const WifiTrigger({required this.ssid, required this.message});
}

class WifiService {
  static final WifiService _instance = WifiService._internal();
  factory WifiService() => _instance;
  WifiService._internal();

  final _info = NetworkInfo();
  final _api = ApiService();
  String? _lastFiredSsid;

  Future<List<WifiTrigger>> loadTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kPrefWifiTriggers) ?? [];
    return raw.map((s) {
      final idx = s.indexOf('|');
      return WifiTrigger(ssid: s.substring(0, idx), message: s.substring(idx + 1));
    }).toList();
  }

  Future<void> saveTriggers(List<WifiTrigger> triggers) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = triggers.map((t) => '${t.ssid}|${t.message}').toList();
    await prefs.setStringList(kPrefWifiTriggers, raw);
  }

  Future<void> checkCurrentNetwork() async {
    String? ssid;
    try {
      ssid = await _info.getWifiName();
    } catch (_) {
      return;
    }
    if (ssid == null) {
      _lastFiredSsid = null;
      return;
    }
    // Strip surrounding quotes Android sometimes adds
    ssid = ssid.replaceAll('"', '');

    if (ssid == _lastFiredSsid) return;

    final triggers = await loadTriggers();
    for (final trigger in triggers) {
      if (trigger.ssid == ssid) {
        _lastFiredSsid = ssid;
        try {
          await _api.capture(trigger.message);
        } catch (_) {}
        break;
      }
    }
  }
}
