import 'package:flutter/material.dart';

/// DB enum `travel_mode`. One mode per trip (PM decision P-7).
enum TravelMode {
  walk('walk', 'เดินเท้า', Icons.directions_walk, 'foot', 4.5),
  transit('transit', 'รถสาธารณะ', Icons.directions_bus, 'driving', 20),
  car('car', 'รถส่วนตัว', Icons.directions_car, 'driving', 30),
  taxi('taxi', 'แท็กซี่/แอปเรียกรถ', Icons.local_taxi, 'driving', 30);

  const TravelMode(this.db, this.label, this.icon, this.osrmProfile, this.avgKmh);

  final String db;
  final String label;
  final IconData icon;

  /// transit/car/taxi are approximated by road routing (requirements).
  final String osrmProfile;
  final double avgKmh;

  static TravelMode? fromDb(Object? v) {
    for (final m in values) {
      if (m.db == v) return m;
    }
    return null;
  }
}
