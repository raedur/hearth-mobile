import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/geofence_service.dart';

class GeofenceMapScreen extends StatefulWidget {
  final List<GeofenceLocation> existing;

  const GeofenceMapScreen({super.key, required this.existing});

  @override
  State<GeofenceMapScreen> createState() => _GeofenceMapScreenState();
}

class _GeofenceMapScreenState extends State<GeofenceMapScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();

  LatLng? _selectedPoint;
  double _radiusMeters = 200;
  bool _loadingLocation = true;
  bool _searching = false;
  LatLng _initialCenter = const LatLng(-34.9285, 138.6007); // Adelaide default

  @override
  void initState() {
    super.initState();
    _goToCurrentLocation();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _goToCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _loadingLocation = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _initialCenter = ll;
        _loadingLocation = false;
      });
      _mapController.move(ll, 15);
    } catch (_) {
      setState(() => _loadingLocation = false);
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(queryParameters: {'q': query, 'format': 'json', 'limit': '1'});
      final res = await http.get(uri, headers: {'User-Agent': 'HearthApp/1.0'});
      if (res.statusCode == 200) {
        final results = jsonDecode(res.body) as List;
        if (results.isNotEmpty) {
          final lat = double.parse(results[0]['lat'] as String);
          final lon = double.parse(results[0]['lon'] as String);
          final ll = LatLng(lat, lon);
          setState(() => _selectedPoint = ll);
          _mapController.move(ll, 16);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No results found')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search failed — check your connection')));
      }
    } finally {
      setState(() => _searching = false);
    }
  }

  void _onTap(TapPosition _, LatLng point) {
    setState(() => _selectedPoint = point);
  }

  Future<void> _confirm() async {
    if (_selectedPoint == null) return;
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: 'e.g. Shops'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, nameController.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final location = GeofenceLocation(
      name: name,
      lat: _selectedPoint!.latitude,
      lng: _selectedPoint!.longitude,
      radiusMeters: _radiusMeters,
    );
    Navigator.pop(context, location);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose location')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search address...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchAddress(),
                  ),
                ),
                const SizedBox(width: 8),
                _searching
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(onPressed: _searchAddress, icon: const Icon(Icons.search)),
              ],
            ),
          ),
          Expanded(
            child: _loadingLocation
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _initialCenter,
                      initialZoom: 15,
                      onTap: _onTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'au.id.craig.hearth_app',
                      ),
                      // Existing geofences shown as blue circles
                      CircleLayer(
                        circles: widget.existing
                            .map((loc) => CircleMarker(
                                  point: LatLng(loc.lat, loc.lng),
                                  radius: loc.radiusMeters,
                                  useRadiusInMeter: true,
                                  color: Colors.blue.withValues(alpha: 0.15),
                                  borderColor: Colors.blue.withValues(alpha: 0.6),
                                  borderStrokeWidth: 1.5,
                                ))
                            .toList(),
                      ),
                      // Existing geofences — name labels
                      MarkerLayer(
                        markers: widget.existing
                            .map((loc) => Marker(
                                  point: LatLng(loc.lat, loc.lng),
                                  width: 120,
                                  height: 30,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.blue, width: 0.5),
                                    ),
                                    child: Text(loc.name,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: Colors.blue)),
                                  ),
                                ))
                            .toList(),
                      ),
                      // Selected point — radius circle + marker
                      if (_selectedPoint != null) ...[
                        CircleLayer(circles: [
                          CircleMarker(
                            point: _selectedPoint!,
                            radius: _radiusMeters,
                            useRadiusInMeter: true,
                            color: Colors.deepOrange.withValues(alpha: 0.15),
                            borderColor: Colors.deepOrange,
                            borderStrokeWidth: 2,
                          ),
                        ]),
                        MarkerLayer(markers: [
                          Marker(
                            point: _selectedPoint!,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Colors.deepOrange, size: 40),
                          ),
                        ]),
                      ],
                    ],
                  ),
          ),
          // Radius slider + confirm
          if (_selectedPoint != null)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Radius'),
                      Expanded(
                        child: Slider(
                          min: 100,
                          max: 1000,
                          divisions: 18,
                          value: _radiusMeters,
                          label: '${_radiusMeters.round()} m',
                          onChanged: (v) => setState(() => _radiusMeters = v),
                        ),
                      ),
                      SizedBox(width: 48, child: Text('${_radiusMeters.round()} m', textAlign: TextAlign.end)),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check),
                      label: const Text('Add geofence'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedPoint == null && !_loadingLocation
          ? FloatingActionButton.small(
              onPressed: () {
                _mapController.move(_initialCenter, 15);
              },
              child: const Icon(Icons.my_location),
            )
          : null,
    );
  }
}
