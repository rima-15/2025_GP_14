import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ---- types ----
typedef PlaceDetailsFetcher =
    Future<Map<String, dynamic>> Function(String placeId);

// Optional: expand later if you store more fields
class VenueMeta {
  final double? rating;
  final Map<String, dynamic>? openingHours;
  final DateTime? lastUpdated;
  VenueMeta({this.rating, this.openingHours, this.lastUpdated});

  factory VenueMeta.fromMap(Map<String, dynamic> m) => VenueMeta(
    rating: (m['rating'] is num) ? (m['rating'] as num).toDouble() : null,
    openingHours: (m['openingHours'] is Map)
        ? Map<String, dynamic>.from(m['openingHours'] as Map)
        : null,
    lastUpdated: m['lastUpdated'] is Timestamp
        ? (m['lastUpdated'] as Timestamp).toDate()
        : null,
  );
}

// ---- default Google fetcher kept INSIDE the service file ----
Future<Map<String, dynamic>> defaultPlacesDetailsFetcher(String placeId) async {
  final key = dotenv.maybeGet('GOOGLE_API_KEY') ?? '';
  if (key.isEmpty) {
    throw Exception('Missing GOOGLE_API_KEY in .env');
  }
  final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
    'place_id': placeId,
    'fields':
        'rating,opening_hours,current_opening_hours,utc_offset,types,business_status',
    'key': key,
  });
  final r = await http.get(uri).timeout(const Duration(seconds: 10));
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  return j; // we'll read j['result'] below
}

class VenueCacheService {
  final FirebaseFirestore _db;
  final PlaceDetailsFetcher _fetcher;

  // 👇 fetcher is optional; defaults to the internal Google fetcher
  VenueCacheService(this._db, [PlaceDetailsFetcher? fetcher])
    : _fetcher = fetcher ?? defaultPlacesDetailsFetcher;

  DocumentReference<Map<String, dynamic>> _doc(String placeId) => _db
      .collection('venues')
      .doc(placeId)
      .collection('cache')
      .doc('googlePlaces');

  Future<VenueMeta> getMonthlyMeta(String placeId) async {
    // 1) read cache
    final snap = await _doc(placeId).get();
    final data = snap.data();
    if (data != null) {
      final ts = data['lastUpdated'] is Timestamp
          ? (data['lastUpdated'] as Timestamp).toDate()
          : null;
      if (ts != null && DateTime.now().difference(ts).inDays < 30) {
        return VenueMeta.fromMap(data);
      }
    }

    // 2) stale → fetch once
    final j = await _fetcher(placeId);
    final result = (j['result'] as Map<String, dynamic>?) ?? {};

    final double? rating = (result['rating'] is num)
        ? (result['rating'] as num).toDouble()
        : null;

    final Map<String, dynamic>? opening =
        (result['current_opening_hours'] as Map<String, dynamic>?) ??
        (result['opening_hours'] as Map<String, dynamic>?);

    final toStore = <String, dynamic>{
      'rating': rating,
      'openingHours': opening,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    await _doc(
      placeId,
    ).set(toStore, SetOptions(merge: true)).catchError((_) {});
    return VenueMeta(
      rating: rating,
      openingHours: opening == null ? null : Map<String, dynamic>.from(opening),
      lastUpdated: DateTime.now(),
    );
  }
}
