import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/geo/geo.dart';
import '../../geo/domain/location_service.dart';
import '../domain/live_location.dart';

class SupabaseLiveLocationRepository implements LiveLocationRepository {
  SupabaseLiveLocationRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Result<void>> push(String tripId, LocationFix fix) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      // No auto retry: append-only, and an old fix is worthless.
      await _client.from('trip_locations').insert({
        'trip_id': tripId,
        'user_id': uid,
        'location': pointEwkt(fix.point),
        if (fix.accuracyM != null) 'accuracy_m': fix.accuracyM,
      });
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<PartnerLocation?>> partnerLocation(String matchId) async {
    try {
      final res = await _client.rpc('get_partner_live_location', params: {'p_match_id': matchId});
      if (res is! List || res.isEmpty || res.first is! Map) return const Ok(null);
      final r = res.first as Map;
      final lat = r['lat'];
      final lng = r['lng'];
      final at = DateTime.tryParse('${r['recorded_at']}');
      if (lat is! num || lng is! num || at == null) return const Ok(null);
      return Ok(PartnerLocation(point: LatLng(lat.toDouble(), lng.toDouble()), recordedAt: at.toLocal()));
    } catch (e) {
      return Err(mapError(e));
    }
  }
}
