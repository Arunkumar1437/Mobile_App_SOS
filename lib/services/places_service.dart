import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place.dart';

class PlacesException implements Exception {
  PlacesException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Looks up nearby places from OpenStreetMap through the free Overpass API.
/// No API key is needed. Please keep request volume modest (fair-use policy).
class PlacesService {
  // Public mirrors are often slow or down, so they are raced: each one starts
  // [_stagger] after the previous (or at once when the previous one fails)
  // and the first good answer wins.
  static const _endpoints = [
    'https://overpass.openstreetmap.fr/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
  static const _stagger = Duration(seconds: 2);
  static const _requestTimeout = Duration(seconds: 20);
  static const _userAgent = 'AKSOS/1.0 (Flutter emergency helper app)';
  static const _cacheFor = Duration(minutes: 10);

  // A saved list is shown instantly (and then refreshed) if it was fetched
  // this close to where the user is now, and not too long ago.
  static const _savedWithinMeters = 500;
  static const _savedFor = Duration(days: 7);

  // One shared client keeps connections open, which saves the TLS handshake
  // (about 0.3 s) on every search after the first.
  static final http.Client _client = http.Client();

  static final Map<String, _CacheEntry> _cache = {};
  static final Map<PlaceCategory, _Snapshot> _snapshots = {};

  static Future<List<Place>> search(
    PlaceCategory category,
    double lat,
    double lon, {
    bool forceRefresh = false,
  }) async {
    final key =
        '${category.name}:${lat.toStringAsFixed(3)}:${lon.toStringAsFixed(3)}';
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.time) < _cacheFor) {
      return cached.places;
    }

    final places = await _query(category, lat, lon);
    final now = DateTime.now();
    _cache[key] = _CacheEntry(places, now);
    unawaited(_save(category, _Snapshot(lat, lon, places, now)));
    return places;
  }

  /// The last result for [category] if it was fetched near ([lat], [lon]),
  /// with distances recalculated from there. Lets the UI show something
  /// immediately while [search] runs; null if there is nothing usable.
  static Future<List<Place>?> lastKnown(
    PlaceCategory category,
    double lat,
    double lon,
  ) async {
    var snap = _snapshots[category];
    if (snap == null) {
      final loaded = await _load(category);
      if (loaded != null) snap = _snapshots[category] ??= loaded;
    }
    if (snap == null ||
        DateTime.now().difference(snap.time) > _savedFor ||
        Geolocator.distanceBetween(lat, lon, snap.lat, snap.lon) >
            _savedWithinMeters) {
      return null;
    }
    final places = [
      for (final p in snap.places)
        p.withDistance(Geolocator.distanceBetween(lat, lon, p.lat, p.lon)),
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return places;
  }

  static String _snapshotKey(PlaceCategory c) => 'nearby_${c.name}';

  static Future<void> _save(PlaceCategory c, _Snapshot s) async {
    _snapshots[c] = s;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_snapshotKey(c), jsonEncode(s.toJson()));
    } catch (_) {
      // Saving is only a speed-up.
    }
  }

  static Future<_Snapshot?> _load(PlaceCategory c) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_snapshotKey(c));
      if (raw == null) return null;
      return _Snapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>, c);
    } catch (_) {
      return null;
    }
  }

  static String _filter(PlaceCategory c, String around) {
    switch (c) {
      case PlaceCategory.police:
        return 'nwr["amenity"="police"]($around);';
      case PlaceCategory.railway:
        // Mainline train stations and halts; leave out metro / monorail.
        return 'nwr["railway"~"^(station|halt)\$"]'
            '["station"!~"subway|light_rail|monorail"]($around);';
      case PlaceCategory.airport:
        // Only airports with an IATA code (i.e. commercial airports).
        return 'nwr["aeroway"="aerodrome"]["iata"]($around);';
      case PlaceCategory.hospital:
        return 'nwr["amenity"="hospital"]($around);';
      case PlaceCategory.fire:
        return 'nwr["amenity"="fire_station"]($around);';
      case PlaceCategory.bus:
        return 'nwr["amenity"="bus_station"]($around);';
      case PlaceCategory.pharmacy:
        return 'nwr["amenity"="pharmacy"]($around);';
    }
  }

  static Future<List<Place>> _query(
    PlaceCategory category,
    double lat,
    double lon,
  ) async {
    final around = 'around:$searchRadiusMeters,$lat,$lon';
    // No output cap: Overpass returns arbitrary elements, not the nearest, so
    // a cap could drop the closest places in dense areas.
    final query =
        '[out:json][timeout:25];(${_filter(category, around)});out tags center;';
    return _parse(await _fetch(query), category, lat, lon);
  }

  /// Sends [query] to the mirrors and returns the first good answer. Waiting
  /// for each slow mirror to fail in turn can take minutes, which left the
  /// Nearby list empty.
  static Future<Map<String, dynamic>> _fetch(String query) {
    final done = Completer<Map<String, dynamic>>();
    var next = 0;
    var failed = 0;
    Object? lastError;
    Timer? timer;
    late void Function() startNext;

    Future<void> attempt(String endpoint) async {
      try {
        final res = await _client
            .post(
              Uri.parse(endpoint),
              headers: {'User-Agent': _userAgent},
              body: {'data': query},
            )
            .timeout(_requestTimeout);
        if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        // A busy server can answer 200 with an error remark and no results.
        if ('${data['remark']}'.contains('runtime error')) throw 'server busy';
        if (!done.isCompleted) done.complete(data);
      } catch (e) {
        lastError = e is TimeoutException ? 'timed out' : e;
        if (++failed == _endpoints.length && !done.isCompleted) {
          done.completeError(PlacesException(
            'Could not load nearby places. Check your internet connection and try again. ($lastError)',
          ));
        } else {
          // Don't wait out the stagger for a mirror that has already failed.
          startNext();
        }
      }
    }

    startNext = () {
      if (done.isCompleted || next >= _endpoints.length) {
        timer?.cancel();
        return;
      }
      unawaited(attempt(_endpoints[next++]));
    };

    startNext();
    timer = Timer.periodic(_stagger, (_) => startNext());
    return done.future.whenComplete(() => timer?.cancel());
  }

  static List<Place> _parse(
    Map<String, dynamic> data,
    PlaceCategory category,
    double lat,
    double lon,
  ) {
    final elements = (data['elements'] as List?) ?? const [];
    final seen = <String>{};
    final places = <Place>[];

    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};

      var pLat = (e['lat'] as num?)?.toDouble();
      var pLon = (e['lon'] as num?)?.toDouble();
      if (pLat == null || pLon == null) {
        final center = e['center'] as Map?;
        pLat = (center?['lat'] as num?)?.toDouble();
        pLon = (center?['lon'] as num?)?.toDouble();
      }
      if (pLat == null || pLon == null) continue;

      final name = _str(tags['name:en']) ??
          _str(tags['name']) ??
          'Unnamed ${category.label}';

      // The same station is often mapped as a node and a building; keep one.
      final dedupeKey =
          '${name.toLowerCase()}|${pLat.toStringAsFixed(3)}|${pLon.toStringAsFixed(3)}';
      if (!seen.add(dedupeKey)) continue;

      places.add(Place(
        id: '${e['type']}/${e['id']}',
        name: name,
        category: category,
        lat: pLat,
        lon: pLon,
        distanceMeters: Geolocator.distanceBetween(lat, lon, pLat, pLon),
        phone: _firstPhone(tags),
        address: _address(tags),
        extra: _extra(category, tags),
      ));
    }

    places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return places.take(100).toList();
  }

  static String? _str(dynamic v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  static String? _firstPhone(Map<String, dynamic> t) {
    for (final k in const [
      'phone',
      'contact:phone',
      'emergency:phone',
      'contact:mobile',
      'mobile',
    ]) {
      final v = _str(t[k]);
      if (v != null) return v.split(RegExp(r'[;,/]')).first.trim();
    }
    return null;
  }

  static String? _address(Map<String, dynamic> t) {
    final full = _str(t['addr:full']);
    if (full != null) return full;
    final street = [_str(t['addr:housenumber']), _str(t['addr:street'])]
        .whereType<String>()
        .join(' ');
    final parts = [
      if (street.isNotEmpty) street,
      _str(t['addr:suburb']),
      _str(t['addr:city']) ?? _str(t['addr:district']),
      _str(t['addr:postcode']),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String? _extra(PlaceCategory c, Map<String, dynamic> t) {
    switch (c) {
      case PlaceCategory.airport:
        final iata = _str(t['iata']);
        return iata == null ? null : 'IATA: $iata';
      case PlaceCategory.railway:
        final code = _str(t['railway:ref']) ?? _str(t['ref']);
        return code == null ? null : 'Station code: $code';
      case PlaceCategory.hospital:
        return _str(t['emergency']) == 'yes' ? '24x7 emergency' : null;
      case PlaceCategory.pharmacy:
        return _str(t['opening_hours']);
      default:
        return _str(t['operator']);
    }
  }
}

class _CacheEntry {
  _CacheEntry(this.places, this.time);
  final List<Place> places;
  final DateTime time;
}

/// The latest result for one category, kept in memory and saved on the device
/// so the next launch can show it before the network answers.
class _Snapshot {
  _Snapshot(this.lat, this.lon, this.places, this.time);

  /// Where the search was made from; [Place.distanceMeters] is relative to it.
  final double lat;
  final double lon;
  final List<Place> places;
  final DateTime time;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'time': time.millisecondsSinceEpoch,
        'places': [
          for (final p in places)
            {
              'id': p.id,
              'name': p.name,
              'lat': p.lat,
              'lon': p.lon,
              'distance': p.distanceMeters,
              'phone': p.phone,
              'address': p.address,
              'extra': p.extra,
            },
        ],
      };

  factory _Snapshot.fromJson(Map<String, dynamic> j, PlaceCategory c) =>
      _Snapshot(
        (j['lat'] as num).toDouble(),
        (j['lon'] as num).toDouble(),
        [
          for (final raw in j['places'] as List)
            Place(
              id: raw['id'] as String,
              name: raw['name'] as String,
              category: c,
              lat: (raw['lat'] as num).toDouble(),
              lon: (raw['lon'] as num).toDouble(),
              distanceMeters: (raw['distance'] as num).toDouble(),
              phone: raw['phone'] as String?,
              address: raw['address'] as String?,
              extra: raw['extra'] as String?,
            ),
        ],
        DateTime.fromMillisecondsSinceEpoch(j['time'] as int),
      );
}
