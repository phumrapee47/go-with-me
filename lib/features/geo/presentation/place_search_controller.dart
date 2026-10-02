import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/error/app_failure.dart';
import '../domain/geo_services.dart';

enum PlaceSearchStatus { idle, typing, loading, results, empty, rateLimited, unavailable }

/// Debounced place search (Nominatim policy: never per keystroke).
/// - starts only for >= [minChars] characters and after [debounce] of silence
///   (default 800 ms), or immediately via [searchNow] (keyboard "search");
/// - a newer query invalidates older in-flight ones, so late answers to stale
///   text are dropped.
class PlaceSearchController extends ChangeNotifier {
  PlaceSearchController(
    this._geo, {
    this.debounce = const Duration(milliseconds: 800),
    this.minChars = 3,
  });

  final GeocodingService _geo;
  final Duration debounce;
  final int minChars;

  PlaceSearchStatus status = PlaceSearchStatus.idle;
  List<PlaceSuggestion> results = const [];
  Timer? _timer;
  int _gen = 0;
  bool _disposed = false;

  void onQueryChanged(String q) {
    _timer?.cancel();
    final gen = ++_gen;
    final text = q.trim();
    if (text.length < minChars) {
      results = const [];
      _set(PlaceSearchStatus.idle);
      return;
    }
    _set(PlaceSearchStatus.typing);
    _timer = Timer(debounce, () => _run(text, gen));
  }

  /// Search button on the keyboard: skip the debounce, keep the min length.
  Future<void> searchNow(String q) {
    _timer?.cancel();
    final gen = ++_gen;
    final text = q.trim();
    if (text.length < minChars) {
      results = const [];
      _set(PlaceSearchStatus.idle);
      return Future.value();
    }
    return _run(text, gen);
  }

  void clear() {
    _timer?.cancel();
    _gen++;
    results = const [];
    _set(PlaceSearchStatus.idle);
  }

  Future<void> _run(String text, int gen) async {
    _set(PlaceSearchStatus.loading);
    try {
      final r = await _geo.search(text);
      if (gen != _gen) return; // stale
      results = _dedup(r);
      _set(results.isEmpty ? PlaceSearchStatus.empty : PlaceSearchStatus.results);
    } on AppFailure catch (e) {
      if (gen != _gen) return;
      results = const [];
      _set(e.code == FailureCode.rateLimited
          ? PlaceSearchStatus.rateLimited
          : PlaceSearchStatus.unavailable);
    }
  }

  /// Dedup results by label+point (Nominatim has no stable id in
  /// [PlaceSuggestion]). Keeps the first occurrence and preserves order.
  static List<PlaceSuggestion> _dedup(List<PlaceSuggestion> r) {
    final seen = <String>{};
    final out = <PlaceSuggestion>[];
    for (final s in r) {
      final key = '${s.label}|${s.point.latitude}|${s.point.longitude}';
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  void _set(PlaceSearchStatus s) {
    status = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
