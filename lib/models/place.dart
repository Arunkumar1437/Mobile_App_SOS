import 'package:flutter/material.dart';

/// How far around the user every nearby search looks.
const int searchRadiusMeters = 10000;

/// The kinds of places the app can look up nearby.
enum PlaceCategory {
  police('Police', Icons.local_police, Color(0xFF1565C0)),
  railway('Railway', Icons.train, Color(0xFF6A1B9A)),
  airport('Airport', Icons.flight, Color(0xFF00838F)),
  hospital('Hospital', Icons.local_hospital, Color(0xFFC62828)),
  fire('Fire Station', Icons.fire_truck, Color(0xFFEF6C00)),
  bus('Bus Stand', Icons.directions_bus, Color(0xFF2E7D32)),
  pharmacy('Pharmacy', Icons.local_pharmacy, Color(0xFFAD1457));

  const PlaceCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lon,
    required this.distanceMeters,
    this.phone,
    this.address,
    this.extra,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final double lat;
  final double lon;
  final double distanceMeters;

  /// First phone number listed on OpenStreetMap, if any.
  final String? phone;
  final String? address;

  /// Short extra info, e.g. airport IATA code or railway station code.
  final String? extra;

  String get distanceLabel => formatDistance(distanceMeters);

  Place withDistance(double meters) => Place(
        id: id,
        name: name,
        category: category,
        lat: lat,
        lon: lon,
        distanceMeters: meters,
        phone: phone,
        address: address,
        extra: extra,
      );
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}
