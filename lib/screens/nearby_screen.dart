import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../services/sos_service.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  PlaceCategory _category = PlaceCategory.police;
  List<Place> _places = [];
  Position? _position;
  bool _loading = false;
  String _status = '';
  String? _notice;
  String? _error;
  bool _showMap = false;

  String get _radiusLabel => formatDistance(searchRadiusMeters.toDouble());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final category = _category;
    // The user may switch category while this is still loading.
    bool current() => mounted && category == _category;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _status = 'Getting your location…';
    });
    try {
      // Start from the last known position so a list can appear before the GPS
      // has settled; _refine corrects it if the phone has moved since.
      final quick = await LocationService.quick();
      final pos = quick ?? await LocationService.getCurrent();
      if (quick != null && !force) {
        final saved = await PlacesService.lastKnown(
            category, pos.latitude, pos.longitude);
        if (saved != null && current()) {
          setState(() {
            _position = pos;
            _places = saved;
          });
        }
      }
      if (current()) {
        setState(() => _status =
            'Finding ${category.label.toLowerCase()} within $_radiusLabel…');
      }
      final places = await PlacesService.search(
        category,
        pos.latitude,
        pos.longitude,
        forceRefresh: force,
      );
      if (!current()) return;
      setState(() {
        _position = pos;
        _places = places;
        _loading = false;
      });
      if (quick != null) unawaited(_refine(category, pos));
    } catch (e) {
      if (current()) {
        setState(() {
          if (_places.isEmpty) {
            _error = e.toString();
          } else {
            _notice = 'Showing saved results. $e';
          }
        });
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  /// Gets a real GPS fix after the list was built from a last known position,
  /// and searches again if the phone is somewhere else.
  Future<void> _refine(PlaceCategory category, Position from) async {
    try {
      final pos = await LocationService.getCurrent();
      final moved = Geolocator.distanceBetween(
          from.latitude, from.longitude, pos.latitude, pos.longitude);
      if (moved < 300) return;
      final places =
          await PlacesService.search(category, pos.latitude, pos.longitude);
      if (!mounted || category != _category) return;
      setState(() {
        _position = pos;
        _places = places;
      });
    } on LocationException catch (e) {
      if (mounted && category == _category) {
        setState(() => _notice =
            'Showing places near your last known location. ${e.message}');
      }
    } catch (_) {
      // Keep the list we already have.
    }
  }

  void _select(PlaceCategory c) {
    if (c == _category) return;
    setState(() {
      _category = c;
      _places = [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby'),
        actions: [
          IconButton(
            tooltip: _showMap ? 'Show list' : 'Show map',
            icon: Icon(_showMap ? Icons.list : Icons.map),
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _load(force: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final c in PlaceCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(c.icon, size: 18),
                      label: Text(c.label),
                      selected: c == _category,
                      onSelected: (_) => _select(c),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_notice != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _notice!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onTertiaryContainer),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _places.isEmpty) {
      return _Message(
        icon: Icons.cloud_off,
        text: _error!,
        action: FilledButton(
          onPressed: () => _load(force: true),
          child: const Text('Try again'),
        ),
      );
    }
    if (_loading && _places.isEmpty) {
      return _Message(icon: _category.icon, text: _status);
    }
    if (!_loading && _places.isEmpty && _position != null) {
      return _Message(
        icon: _category.icon,
        text: 'No ${_category.label.toLowerCase()} found within '
            '$_radiusLabel on OpenStreetMap. For emergencies call 112.',
      );
    }
    if (_showMap && _position != null) return _buildMap();
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _places.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) => _PlaceTile(
          place: _places[i],
          onTap: () => _showDetails(_places[i]),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final me = LatLng(_position!.latitude, _position!.longitude);
    final shown = _places.take(30).toList();
    final fitPoints = [me, ...shown.take(8).map((p) => LatLng(p.lat, p.lon))];

    return FlutterMap(
      key: ValueKey('${_category.name}-${_places.length}'),
      options: MapOptions(
        initialCenter: me,
        initialZoom: 13,
        initialCameraFit: fitPoints.length > 1
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(fitPoints),
                padding: const EdgeInsets.all(48),
              )
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.suraksha_sos',
        ),
        MarkerLayer(
          markers: [
            for (final p in shown)
              Marker(
                point: LatLng(p.lat, p.lon),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => _showDetails(p),
                  child: CircleAvatar(
                    backgroundColor: p.category.color,
                    foregroundColor: Colors.white,
                    child: Icon(p.category.icon, size: 20),
                  ),
                ),
              ),
            Marker(
              point: me,
              width: 26,
              height: 26,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(blurRadius: 6, color: Colors.black26)
                  ],
                ),
              ),
            ),
          ],
        ),
        const Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: ColoredBox(
              color: Colors.white70,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 11, color: Colors.black87)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showDetails(Place p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: p.category.color,
                  foregroundColor: Colors.white,
                  child: Icon(p.category.icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p.name,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ]),
              const SizedBox(height: 12),
              _detail(Icons.straighten, '${p.distanceLabel} away (straight line)'),
              if (p.address != null) _detail(Icons.place, p.address!),
              if (p.phone != null) _detail(Icons.phone, p.phone!),
              if (p.extra != null) _detail(Icons.info_outline, p.extra!),
              if (p.phone == null)
                _detail(Icons.info_outline,
                    'No phone number listed on OpenStreetMap.'),
              const SizedBox(height: 16),
              Row(children: [
                if (p.phone != null) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => SosService.call(p.phone!),
                      icon: const Icon(Icons.call),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => SosService.directions(p.lat, p.lon),
                    icon: const Icon(Icons.directions),
                    label: const Text('Directions'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final lines = [
      if (p.address != null) p.address!,
      if (p.extra != null) p.extra!,
    ];
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: p.category.color,
        foregroundColor: Colors.white,
        child: Icon(p.category.icon),
      ),
      title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [p.distanceLabel, ...lines].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.phone != null)
            IconButton(
              tooltip: 'Call',
              icon: const Icon(Icons.call),
              onPressed: () => SosService.call(p.phone!),
            ),
          IconButton(
            tooltip: 'Directions',
            icon: const Icon(Icons.directions),
            onPressed: () => SosService.directions(p.lat, p.lon),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
