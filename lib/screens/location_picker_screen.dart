import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationPickerResult {
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;

  const LocationPickerResult({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
  });
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  LatLng? _selectedPoint;
  double _radiusMeters = 200;
  bool _locatingUser = false;

  static const _defaultCenter = LatLng(-33.8688, 151.2093); // Sydney
  static const _defaultZoom = 14.0;

  void _onTap(TapPosition _, LatLng point) {
    setState(() => _selectedPoint = point);
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _locatingUser = true);
    try {
      final pos = await Geolocator.getCurrentPosition();
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() => _selectedPoint = point);
      _mapController.move(point, 16);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
      }
    } finally {
      if (mounted) setState(() => _locatingUser = false);
    }
  }

  Future<void> _confirm() async {
    if (_selectedPoint == null) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Shops'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    Navigator.pop(
      context,
      LocationPickerResult(
        name: name,
        lat: _selectedPoint!.latitude,
        lng: _selectedPoint!.longitude,
        radiusMeters: _radiusMeters,
      ),
    );
  }

  String _radiusLabel(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick location'),
        actions: [
          TextButton(
            onPressed: _selectedPoint != null ? _confirm : null,
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: _defaultZoom,
                onTap: _onTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'au.id.craig.hearth_app',
                ),
                if (_selectedPoint != null) ...[
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _selectedPoint!,
                        radius: _radiusMeters,
                        useRadiusInMeter: true,
                        color: Colors.deepOrange.withAlpha(40),
                        borderColor: Colors.deepOrange,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedPoint!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.deepOrange,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Radius: ${_radiusLabel(_radiusMeters)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Slider(
                  value: _radiusMeters,
                  min: 50,
                  max: 2000,
                  divisions: 39,
                  label: _radiusLabel(_radiusMeters),
                  onChanged: (v) => setState(() => _radiusMeters = v),
                ),
                if (_selectedPoint != null)
                  Text(
                    '${_selectedPoint!.latitude.toStringAsFixed(5)}, '
                    '${_selectedPoint!.longitude.toStringAsFixed(5)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _locatingUser ? null : _goToCurrentLocation,
        child: _locatingUser
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }
}
