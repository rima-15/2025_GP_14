import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ----------------------------------------------------------------------------
// Place Rating Service - Caches place ratings in Firestore (weekly refresh)
// ----------------------------------------------------------------------------

/// Refresh rating if older than 7 days
const int _kCacheMaxAgeDays = 7;

class PlaceRatingService {
  final FirebaseFirestore _db;
  final String _apiKey;

  // In-memory cache to avoid repeated reads within same session
  static final Map<String, double?> _memoryCache = {};
  static final Map<String, DateTime> _memoryCacheTime = {};

  PlaceRatingService([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance,
        _apiKey = dotenv.maybeGet('GOOGLE_API_KEY') ?? '';

  /// Get cached rating for a place from Firestore, refreshing if stale
  /// Returns null if no rating available
  Future<double?> getCachedRating(String placeId, String venueId) async {
    if (placeId.isEmpty) return null;

    // Check in-memory cache first (valid for 5 minutes)
    if (_memoryCache.containsKey(placeId)) {
      final cachedTime = _memoryCacheTime[placeId];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime).inMinutes < 5) {
        return _memoryCache[placeId];
      }
    }

    try {
      // Read from Firestore places collection
      final docRef = _db.collection('places').doc(placeId);
      final snap = await docRef.get();

      if (!snap.exists) return null;

      final data = snap.data();
      if (data == null) return null;

      // Check if we have a cached rating
      final cachedRating = (data['rating'] is num)
          ? (data['rating'] as num).toDouble()
          : null;
      final lastUpdated = data['ratingLastUpdated'];

      DateTime? lastUpdateTime;
      if (lastUpdated is Timestamp) {
        lastUpdateTime = lastUpdated.toDate();
      } else if (lastUpdated is String) {
        lastUpdateTime = DateTime.tryParse(lastUpdated);
      }

      // Check if cache is fresh (within 7 days)
      final isFresh = lastUpdateTime != null &&
          DateTime.now().difference(lastUpdateTime).inDays < _kCacheMaxAgeDays;

      if (cachedRating != null && isFresh) {
        // Cache is fresh, return it
        _memoryCache[placeId] = cachedRating;
        _memoryCacheTime[placeId] = DateTime.now();
        return cachedRating;
      }

      // Cache is stale or missing - fetch from Google API
      final freshRating = await _fetchRatingFromApi(placeId, venueId);

      if (freshRating != null) {
        // Update Firestore with merge (only update rating fields)
        await docRef.set({
          'rating': freshRating,
          'ratingLastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        _memoryCache[placeId] = freshRating;
        _memoryCacheTime[placeId] = DateTime.now();
        return freshRating;
      }

      // If API fetch failed but we have old cached rating, return it
      if (cachedRating != null) {
        _memoryCache[placeId] = cachedRating;
        _memoryCacheTime[placeId] = DateTime.now();
        return cachedRating;
      }

      return null;
    } catch (e) {
      debugPrint('PlaceRatingService error for $placeId: $e');
      // Return memory cached value if available
      return _memoryCache[placeId];
    }
  }

  /// Fetch rating from Google Places API
  Future<double?> _fetchRatingFromApi(String placeId, String venueId) async {
    if (_apiKey.isEmpty) return null;

    try {
      final bool isSolitaire = venueId == "ChIJcYTQDwDjLj4RZEiboV6gZzM";
      Uri uri;

      if (isSolitaire) {
        // Load coordinates from solitaire.json
        final jsonStr = await rootBundle.loadString(
          'assets/venues/solitaire.json',
        );
        final data = json.decode(jsonStr);
        final lat = data['center']['lat'];
        final lng = data['center']['lng'];

        uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/nearbysearch/json',
          {
            'location': '$lat,$lng',
            'radius': '150',
            'keyword': placeId,
            'key': _apiKey,
          },
        );
      } else {
        // Get venue coordinates from Firestore
        final venueSnap = await _db.collection('venues').doc(venueId).get();

        if (!venueSnap.exists) return null;
        final venueData = venueSnap.data();
        final lat = venueData?['latitude'];
        final lng = venueData?['longitude'];

        if (lat == null || lng == null) return null;

        uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/nearbysearch/json',
          {
            'location': '$lat,$lng',
            'radius': '150',
            'keyword': placeId,
            'key': _apiKey,
          },
        );
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final j = json.decode(response.body);
      if (j['status'] != 'OK') return null;

      final results = j['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final rating = results.first['rating'];
      return rating != null ? (rating as num).toDouble() : null;
    } catch (e) {
      debugPrint('API fetch error for $placeId: $e');
      return null;
    }
  }

  /// Clear in-memory cache (useful for testing or force refresh)
  static void clearMemoryCache() {
    _memoryCache.clear();
    _memoryCacheTime.clear();
  }
}

