import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../services/auth_service.dart';
import '../services/geofence_service.dart';
import '../services/wifi_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onSignedOut;

  const SettingsScreen({super.key, required this.onSignedOut});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  final _geofence = GeofenceService();
  final _wifi = WifiService();

  List<GeofenceLocation> _geofences = [];
  List<WifiTrigger> _wifiTriggers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final geofences = await _geofence.loadLocations();
    final triggers = await _wifi.loadTriggers();
    setState(() {
      _geofences = geofences;
      _wifiTriggers = triggers;
    });
  }

  Future<void> _signOut() async {
    await _auth.clearTokens();
    widget.onSignedOut();
  }

  Future<void> _addGeofence() async {
    final name = await _showTextDialog(context, 'Location name', 'e.g. Shops');
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Background location needed'),
          content: const Text(
            'Hearth fires location triggers when you arrive somewhere — even when the app is closed.\n\n'
            'Tap "Allow while using the app" on the next screen, then we\'ll walk you through enabling background access.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied')));
      return;
    }
    // Android 10+: background location requires a second step in app Settings
    if (permission == LocationPermission.whileInUse && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('One more step'),
          content: const Text(
            'To trigger when the app is closed, tap "Open Settings" then change location to "Allow all the time".',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }

    if (!mounted) return;
    final pos = await Geolocator.getCurrentPosition();
    final updated = [..._geofences, GeofenceLocation(name: name, lat: pos.latitude, lng: pos.longitude)];
    await _geofence.saveLocations(updated);
    setState(() => _geofences = updated);

    if (Platform.isAndroid && mounted) {
      await _promptBatteryOptimization();
    }
  }

  static const _batteryChannel = MethodChannel('au.id.craig.hearth_app/battery');

  Future<void> _promptBatteryOptimization() async {
    try {
      final isIgnoring = await _batteryChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
      if (isIgnoring || !mounted) return;

      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disable battery optimization'),
          content: const Text(
            'Android may block location triggers to save battery. '
            'Tap "Allow" on the next screen so Hearth can notify you when you arrive somewhere.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (proceed == true) {
        await _batteryChannel.invokeMethod('requestIgnoreBatteryOptimizations');
      }
    } catch (_) {}
  }

  Future<void> _removeGeofence(GeofenceLocation loc) async {
    final updated = _geofences.where((l) => l != loc).toList();
    await _geofence.saveLocations(updated);
    setState(() => _geofences = updated);
  }

  Future<void> _addWifiTrigger() async {
    // SSID read requires location permission on Android 8.1+
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission needed to detect current WiFi network')));
      return;
    }

    String? detectedSsid;
    try {
      final raw = await NetworkInfo().getWifiName();
      detectedSsid = raw?.replaceAll('"', '');
    } catch (_) {}
    if (!mounted) return;

    final String? ssid;
    if (detectedSsid != null && detectedSsid.isNotEmpty) {
      // Pre-fill with current network, let user confirm or change
      ssid = await _showTextDialog(context, 'WiFi network', detectedSsid, prefill: detectedSsid);
    } else {
      ssid = await _showTextDialog(context, 'WiFi network name (SSID)', 'e.g. HomeWifi');
    }
    if (ssid == null || ssid.isEmpty) return;
    if (!mounted) return;

    final message = await _showTextDialog(context, 'Message to send on connect', 'e.g. Ryan is home');
    if (message == null || message.isEmpty) return;

    final updated = [..._wifiTriggers, WifiTrigger(ssid: ssid, message: message)];
    await _wifi.saveTriggers(updated);
    setState(() => _wifiTriggers = updated);
  }

  Future<void> _removeWifiTrigger(WifiTrigger trigger) async {
    final updated = _wifiTriggers.where((t) => t != trigger).toList();
    await _wifi.saveTriggers(updated);
    setState(() => _wifiTriggers = updated);
  }

  Future<String?> _showTextDialog(BuildContext context, String title, String hint, {String? prefill}) async {
    final controller = TextEditingController(text: prefill);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('GPS locations', style: Theme.of(context).textTheme.titleMedium),
            IconButton(onPressed: _addGeofence, icon: const Icon(Icons.add)),
          ],
        ),
        if (_geofences.isEmpty) const Text('No locations configured', style: TextStyle(color: Colors.grey)),
        ..._geofences.map(
          (loc) => ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(loc.name),
            subtitle: Text('${loc.lat.toStringAsFixed(4)}, ${loc.lng.toStringAsFixed(4)}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeGeofence(loc),
            ),
          ),
        ),
        if (Platform.isAndroid) ...[
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('WiFi triggers', style: Theme.of(context).textTheme.titleMedium),
              IconButton(onPressed: _addWifiTrigger, icon: const Icon(Icons.add)),
            ],
          ),
          if (_wifiTriggers.isEmpty) const Text('No WiFi triggers configured', style: TextStyle(color: Colors.grey)),
          ..._wifiTriggers.map(
            (trigger) => ListTile(
              leading: const Icon(Icons.wifi),
              title: Text(trigger.ssid),
              subtitle: Text(trigger.message),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeWifiTrigger(trigger),
              ),
            ),
          ),
        ],
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: _signOut,
        ),
      ],
    );
  }
}
