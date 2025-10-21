// lib/dev/seed_venues.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart' as storage;

/// Looks for a cover in Firebase Storage:
/// images/Venues_Cover/<PLACE_ID>_cover.(webp|jpg|jpeg|png)
Future<String?> _findCoverPathFor(String placeId) async {
  final exts = ['webp'];
  for (final ext in exts) {
    final path = 'images/Venues_Cover/${placeId}_cover.$ext';
    try {
      await storage.FirebaseStorage.instance.ref(path).getMetadata();
      return path; // found one
    } on storage.FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        // try next ext
      } else {
        rethrow; // other storage errors should surface
      }
    }
  }
  return null;
}

class VenueSeeder {
  final _fire = FirebaseFirestore.instance;
  final String apiKey;

  VenueSeeder(this.apiKey);

  Future<void> run() async {
    if (!kDebugMode) {
      throw Exception('VenueSeeder should run in debug only');
    }
    if (apiKey.isEmpty) {
      throw Exception('GOOGLE_API_KEY missing');
    }

    // Curated list
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
        "name": "Riyadh Gallery Mall",
        "category": "malls",
        "place_id": "ChIJxV1QKqTiLj4RH234vVwTgi8",
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
        final address = det['formatted_address'] as String? ?? '';

        // Google photo (fallback)
        final photos =
            (det['photos'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        String photoUrlGoogle = '';
        if (photos.isNotEmpty) {
          final ref = photos.first['photo_reference'];
          if (ref != null) photoUrlGoogle = _photoUrl(ref);
        }

        // Description from editorial_summary, else fall back to address
        final editorial =
            (det['editorial_summary'] as Map<String, dynamic>?)?['overview']
                as String?;
        final description = (editorial != null && editorial.trim().isNotEmpty)
            ? editorial.trim()
            : address;

        // Optional cover in Storage
        final coverPath = await _findCoverPathFor(placeId);
        if (kDebugMode) {
          print(
            coverPath == null
                ? '   No cover in Storage'
                : '   Cover found: $coverPath',
          );
        }

        // Single write with merge
        await _fire.collection('venues').doc(placeId).set({
          'name': name,
          'placeId': placeId,
          'category': category, // malls | stadiums | airports
          'description': description,
          'address': address,
          'location': {
            'lat': (loc['lat'] as num?)?.toDouble(),
            'lng': (loc['lng'] as num?)?.toDouble(),
          },
          'photoUrl_google': photoUrlGoogle, // Google Places fallback
          'coverPath': coverPath, // Storage path if present
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (kDebugMode) print('   Saved ✓ $name');
      } catch (e, st) {
        if (kDebugMode) {
          print('   ERROR while seeding $name: $e');
          print(st);
        }
      }
    }
  }

  /// Google Places Details with a timeout and clear error logs.
  Future<Map<String, dynamic>?> _getDetails(String placeId) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'name,formatted_address,geometry,photos,editorial_summary',
        'language': 'en', // use 'ar' if you want Arabic editorial text
        'key': apiKey,
      },
    );
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final status = j['status'] as String? ?? 'NO_STATUS';
      if (status != 'OK') {
        if (kDebugMode) {
          print('   Places DETAILS status=$status err=${j['error_message']}');
        }
        return null;
      }
      return j['result'] as Map<String, dynamic>?;
    } on Exception catch (e) {
      if (kDebugMode) print('   Places request failed: $e');
      return null;
    }
  }

  String _photoUrl(String ref) =>
      'https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photo_reference=$ref&key=$apiKey';
}
