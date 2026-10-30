import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationFix { none, turnOnGps, openAppSettings }

class LocationException implements Exception {
  LocationException(this.message, {this.fix = LocationFix.none});

  final String message;
  final LocationFix fix;

  @override
  String toString() => message;
}

class LocationService {
  /// Most recent position, shared across screens so SOS can fall back to it.
  static Position? lastPosition;

  static Future<Position>? _pending;

  /// Concurrent callers (SOS and Nearby both ask at launch) share one fix.
  static Future<Position> getCurrent() =>
      _pending ??= _fix().whenComplete(() => _pending = null);

  /// The best position available instantly: this session's last fix, else the
  /// phone's last known one. Null if there is neither, or no permission yet.
  static Future<Position?> quick() async {
    if (lastPosition != null) return lastPosition;
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  static Future<Position> _fix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException(
        'Location (GPS) is turned off. Switch it on so help can find you.',
        fix: LocationFix.turnOnGps,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationException(
        'Location permission was denied. Allow it to share your location in an SOS.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        'Location permission is blocked. Allow it in the app settings.',
        fix: LocationFix.openAppSettings,
      );
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      lastPosition = pos;
      return pos;
    } on TimeoutException {
      // Indoors or weak GPS: fall back to the last fix the phone knows.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        lastPosition = last;
        return last;
      }
      if (lastPosition != null) return lastPosition!;
      throw LocationException(
        'Could not get a GPS fix. Move near a window or outdoors and try again.',
      );
    }
  }

  static Future<void> applyFix(LocationFix fix) async {
    switch (fix) {
      case LocationFix.turnOnGps:
        await Geolocator.openLocationSettings();
      case LocationFix.openAppSettings:
        await Geolocator.openAppSettings();
      case LocationFix.none:
        break;
    }
  }
}
