import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ----------------------------------------------------------------------------
// Venue Cache Service - Caches Google Places data to reduce API calls
// ----------------------------------------------------------------------------

// Refresh rating if older than 7 days
const int _kCacheMaxAgeDays = 30;

// Type alias for the fetcher function
typedef PlaceDetailsFetcher =
    Future<Map<String, dynamic>> Function(String placeId);

/// Venue metadata from Google Places
class VenueMeta {
  final double? rating;
  final Map<String, dynamic>? openingHours;
  final int? utcOffset;
  final List<String>? types;
  final String? businessStatus;
  final DateTime? lastUpdated;

  VenueMeta({
    this.rating,
    this.openingHours,
    this.utcOffset,
    this.types,
    this.businessStatus,
    this.lastUpdated,
  });

  factory VenueMeta.fromMap(Map<String, dynamic> m) => VenueMeta(
    rating: (m['rating'] is num) ? (m['rating'] as num).toDouble() : null,
    openingHours: (m['openingHours'] is Map)
        ? Map<String, dynamic>.from(m['openingHours'] as Map)
        : null,
    utcOffset: (m['utcOffset'] is num) ? (m['utcOffset'] as num).toInt() : null,
    types: (m['types'] is List) ? (m['types'] as List).cast<String>() : null,
    businessStatus: (m['businessStatus'] as String?),
    lastUpdated: m['lastUpdated'] is Timestamp
        ? (m['lastUpdated'] as Timestamp).toDate()
        : null,
  );
}

// ---------- Default Google Places Fetcher ----------

Future<Map<String, dynamic>> defaultPlacesDetailsFetcher(String placeId) async {
  final key = dotenv.maybeGet('GOOGLE_API_KEY') ?? '';
  if (key.isEmpty) {
    throw Exception('Missing GOOGLE_API_KEY in .env');
  }
  final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
    'place_id': placeId,
    'fields': [
      'rating',
      'opening_hours',
      'current_opening_hours',
      'utc_offset',
      'types',
      'business_status',
    ].join(','),
    'key': key,
  });
  final r = await http.get(uri).timeout(const Duration(seconds: 10));
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  return j;
}

// ---------- Cache Service ----------

class VenueCacheService {
  final FirebaseFirestore _db;
  final PlaceDetailsFetcher _fetcher;

  /// fetcher is optional; defaults to the internal Google fetcher
  VenueCacheService(this._db, [PlaceDetailsFetcher? fetcher])
    : _fetcher = fetcher ?? defaultPlacesDetailsFetcher;

  DocumentReference<Map<String, dynamic>> _doc(String placeId) => _db
      .collection('venues')
      .doc(placeId)
      .collection('cache')
      .doc('googlePlaces');

  /// Get venue metadata, using cache if fresh, otherwise fetching from Google
  Future<VenueMeta> getMonthlyMeta(String placeId) async {
    // Read cache
    final snap = await _doc(placeId).get();
    final data = snap.data();
    if (data != null) {
      final ts = data['lastUpdated'] is Timestamp
          ? (data['lastUpdated'] as Timestamp).toDate()
          : null;
      if (ts != null &&
          DateTime.now().difference(ts).inDays < _kCacheMaxAgeDays) {
        // Use cached value if it's newer than 7 days
        return VenueMeta.fromMap(data);
      }
    }

    // Stale or missing - fetch from Google Places
    final j = await _fetcher(placeId);
    final result = (j['result'] as Map<String, dynamic>?) ?? {};

    final double? rating = (result['rating'] is num)
        ? (result['rating'] as num).toDouble()
        : null;

    final Map<String, dynamic>? opening =
        (result['current_opening_hours'] as Map<String, dynamic>?) ??
        (result['opening_hours'] as Map<String, dynamic>?);

    final int? utcOffset = (result['utc_offset'] is num)
        ? (result['utc_offset'] as num).toInt()
        : null;

    final List<String>? types = (result['types'] is List)
        ? (result['types'] as List).cast<String>()
        : null;

    final String? businessStatus = result['business_status'] as String?;

    final toStore = <String, dynamic>{
      'rating': rating,
      'openingHours': opening,
      'utcOffset': utcOffset,
      'types': types,
      'businessStatus': businessStatus,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    await _doc(
      placeId,
    ).set(toStore, SetOptions(merge: true)).catchError((_) {});

    return VenueMeta(
      rating: rating,
      openingHours: opening == null ? null : Map<String, dynamic>.from(opening),
      utcOffset: utcOffset,
      types: types,
      businessStatus: businessStatus,
      lastUpdated: DateTime.now(),
    );
  }
}
