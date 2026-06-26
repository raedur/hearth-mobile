import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jwt_utils.dart';
import 'storage_keys.dart';
import 'trigger_notifications.dart';

// ---- Top-level callback — fires in background isolate via GeofencingClient ----

@pragma('vm:entry-point')
Future<void> onGeofenceEvent(GeofenceCallbackParams params) async {
  if (params.event != GeofenceEvent.enter) return;

  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final baseUrl = await storage.read(key: kKeyBaseUrl);
  var token = await storage.read(key: kKeyAccessToken);
  final refreshToken = await storage.read(key: kKeyRefreshToken);

  if (baseUrl == null || token == null) return;

  if (jwtExpired(token)) {
    if (refreshToken == null) {
      await showTriggerAuthFailedNotification();
      return;
    }
    token = await _refreshTokenInIsolate(storage, baseUrl, refreshToken);
    if (token == null) {
      await showTriggerAuthFailedNotification();
      return;
    }
  }

  final memberName = jwtClaim(token, 'name') ?? 'Someone';

  for (final geofence in params.geofences) {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/capture'),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: jsonEncode({'text': '$memberName is at ${geofence.id}'}),
      );
    } catch (_) {}
  }
}

// ---- Service class (main isolate) ------------------------------------------

class GeofenceLocation {
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;

  const GeofenceLocation({
    required this.name,
    required this.lat,
    required this.lng,
    this.radiusMeters = 200,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'radiusMeters': radiusMeters,
  };

  factory GeofenceLocation.fromJson(Map<String, dynamic> json) => GeofenceLocation(
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 200,
  );
}

class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  Future<List<GeofenceLocation>> loadLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPrefGeofences);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      return list.map((e) => GeofenceLocation.fromJson(e as Map<String, dynamic>)).toList();
    }
    // Migrate legacy pipe-delimited format
    final legacy = prefs.getStringList(kPrefGeofences);
    if (legacy != null && legacy.isNotEmpty) {
      final locations = legacy.map((s) {
        final parts = s.split('|');
        return GeofenceLocation(name: parts[0], lat: double.parse(parts[1]), lng: double.parse(parts[2]));
      }).toList();
      await _saveToPrefs(prefs, locations);
      return locations;
    }
    return [];
  }

  Future<void> saveLocations(List<GeofenceLocation> locations) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveToPrefs(prefs, locations);
    await _syncWithOs(locations);
  }

  Future<void> _saveToPrefs(SharedPreferences prefs, List<GeofenceLocation> locations) async {
    // Remove legacy StringList key if present, store as JSON string
    await prefs.remove(kPrefGeofences);
    await prefs.setString(kPrefGeofences, jsonEncode(locations.map((l) => l.toJson()).toList()));
  }

  Future<void> reRegisterAfterReboot() async {
    try {
      final locations = await loadLocations();
      if (locations.isNotEmpty) {
        await _syncWithOs(locations);
      }
    } catch (e) {
      debugPrint('GeofenceService: reRegister failed: $e');
    }
  }

  Future<void> _syncWithOs(List<GeofenceLocation> locations) async {
    try {
      await NativeGeofenceManager.instance.removeAllGeofences();
    } catch (e) {
      debugPrint('GeofenceService: removeAll failed: $e');
    }

    for (final loc in locations) {
      try {
        debugPrint('GeofenceService: registering "${loc.name}" at ${loc.lat},${loc.lng}');
        await NativeGeofenceManager.instance.createGeofence(
          Geofence(
            id: loc.name,
            location: Location(latitude: loc.lat, longitude: loc.lng),
            radiusMeters: loc.radiusMeters,
            triggers: {GeofenceEvent.enter},
            iosSettings: const IosGeofenceSettings(initialTrigger: false),
            androidSettings: const AndroidGeofenceSettings(
              initialTriggers: {GeofenceEvent.enter},
              notificationResponsiveness: Duration(seconds: 30),
            ),
          ),
          onGeofenceEvent,
        );
        debugPrint('GeofenceService: "${loc.name}" registered OK');
      } catch (e) {
        debugPrint('GeofenceService: "${loc.name}" FAILED: $e');
      }
    }
  }
}

// ---- Refresh helper for background isolate ---------------------------------
// Cannot use AuthService (different isolate, no shared singleton state).

Future<String?> _refreshTokenInIsolate(
  FlutterSecureStorage storage,
  String baseUrl,
  String refreshToken,
) async {
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/api/refresh'),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final newToken = data['token'] as String;
    await storage.write(key: kKeyAccessToken, value: newToken);
    await storage.write(key: kKeyRefreshToken, value: data['refreshToken'] as String);
    return newToken;
  } catch (_) {
    return null;
  }
}
