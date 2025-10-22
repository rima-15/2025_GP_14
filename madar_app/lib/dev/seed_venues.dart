// lib/dev/seed_venues.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VenueSeeder {
  final _fire = FirebaseFirestore.instance;
  final String apiKey;

  VenueSeeder(this.apiKey);

  Future<void> run() async {
    if (!kDebugMode) throw Exception('VenueSeeder should run in debug only');
    if (apiKey.isEmpty) throw Exception('GOOGLE_API_KEY missing');

    // Curated list (doc id == place_id)
    final base = <Map<String, dynamic>>[
      {
        "name": "Solitaire",
        "category": "malls",
        "place_id": "ChIJcYTQDwDjLj4RZEiboV6gZzM",
      },
      {
        "name": "Cenomi U Walk",
        "category": "malls",
        "place_id": "ChIJeWqVbWPiLj4Rlgc6LjYA2ao",
      },
      {
        "name": "VIA Riyadh",
        "category": "malls",
        "place_id": "ChIJn7nBtyUdLz4R-65OmmUX_Wk",
      },
      {
        "name": "Cenomi Al Nakheel Mall",
        "category": "malls",
        "place_id": "ChIJ44YnxoT9Lj4RS0PXSCpX91I",
      },
      {
        "name": "Cenomi The View Mall",
        "category": "malls",
        "place_id": "ChIJIR-8mrUDLz4R3qmMxNlzR0c",
      },
      {
        "name": "Granada Mall",
        "category": "malls",
        "place_id": "ChIJ01wMi-r9Lj4RhAAXga0t3ss",
      },
      {
        "name": "Riyadh Park",
        "category": "malls",
        "place_id": "ChIJX7F44cXjLj4RW_nD7YWl_64",
      },
      {
        "name": "Panorama Mall",
        "category": "malls",
        "place_id": "ChIJCTtUIM0cLz4R-WS8dfXQ5Aw",
      },
      {
        "name": "Hayat Mall",
        "category": "malls",
        "place_id": "ChIJ7yITIqYCLz4RHVwnXdurblI",
      },
      {
        "name": "Roshn Front - Shopping Area",
        "category": "malls",
        "place_id": "ChIJrVtg__X7Lj4RtLz4nFSoYR4",
      },
      {
        "name": "King Fahd Stadium",
        "category": "stadiums",
        "place_id": "ChIJn1sbaOUFLz4RV0bZTYEWSd4",
      },
      {
        "name": "KINGDOM ARENA",
        "category": "stadiums",
        "place_id": "ChIJOYblxq_jLj4RComs6FLLxZY",
      },
      {
        "name": "Al -Awwal Park",
        "category": "stadiums",
        "place_id": "ChIJmwZs_yTjLj4Rv52NvQWhc3o",
      },
      {
        "name": "Prince Faisal Bin Fahd Stadium",
        "category": "stadiums",
        "place_id": "ChIJSY5rZyUELz4RVF5VTmreiVI",
      },
      {
        "name": "King Khalid International Airport",
        "category": "airports",
        "place_id": "ChIJ2-1ZHvnwLj4R1RcTUX978us",
      },
    ];

    for (final v in base) {
      final placeId = v['place_id'] as String;
      final name = v['name'] as String;
      final category = v['category'] as String;

      if (kDebugMode) print('→ Seeding $name ($placeId) [$category]');
      try {
        final det = await _getDetails(placeId);
        if (det == null) {
          if (kDebugMode) print('   Details NOT_FOUND for $name');
          continue;
        }

        final loc =
            (det['geometry']?['location'] ?? {}) as Map<String, dynamic>;
        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        final address = det['formatted_address'] as String? ?? '';

        // Description from editorial_summary, else address
        final editorial =
            (det['editorial_summary'] as Map<String, dynamic>?)?['overview']
                as String?;
        final description = (editorial != null && editorial.trim().isNotEmpty)
            ? editorial.trim()
            : address;

        // Write minimal schema (doc id == placeId)
        final data = <String, dynamic>{
          'venueName': name,
          'venueType': category,
          'venueDescription': description,
          'venueAddress': address,
          'latitude': lat, // number
          'longitude': lng, // number
        };

        await _fire
            .collection('venues')
            .doc(placeId)
            .set(data, SetOptions(merge: true));
        if (kDebugMode) print('   Saved ✓ $name');
      } catch (e, st) {
        if (kDebugMode) {
          print('   ERROR while seeding $name: $e');
          print(st);
        }
      }
    }
  }

  /// Google Places Details (no photos requested)
  Future<Map<String, dynamic>?> _getDetails(String placeId) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'name,formatted_address,geometry,editorial_summary',
        'language': 'en', // or 'ar'
        'key': apiKey,
      },
    );
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final status = j['status'] as String? ?? 'NO_STATUS';
      if (status != 'OK') {
        if (kDebugMode)
          print('   Places DETAILS status=$status err=${j['error_message']}');
        return null;
      }
      return j['result'] as Map<String, dynamic>?;
    } on Exception catch (e) {
      if (kDebugMode) print('   Places request failed: $e');
      return null;
    }
  }
}
