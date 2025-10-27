// Backfills phone + website for existing venue documents (docId == place_id).

import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VenueContactSeeder {
  final FirebaseFirestore _fire;
  final String apiKey;

  /// If true, we only write the field when it is missing/empty.
  /// If false, we overwrite with the latest from Google.
  final bool onlyIfMissing;

  /// Add a small delay (ms) between calls to be nice to the API.
  final int perCallDelayMs;

  VenueContactSeeder(
    this.apiKey, {
    FirebaseFirestore? firestore,
    this.onlyIfMissing = true,
    this.perCallDelayMs = 250, // ~4 calls/sec
  }) : _fire = firestore ?? FirebaseFirestore.instance;

  Future<void> runOnceForCollection(String collectionPath) async {
    if (!kDebugMode) {
      throw Exception('VenueContactSeeder should run in debug builds only.');
    }
    if (apiKey.isEmpty) {
      throw Exception('GOOGLE_API_KEY missing.');
    }

    final snap = await _fire.collection(collectionPath).get();
    if (kDebugMode) print('Found ${snap.docs.length} venues to check.');

    WriteBatch batch = _fire.batch();
    int pending = 0, written = 0, skipped = 0, errors = 0;

    for (final doc in snap.docs) {
      final placeId = doc.id.trim();
      if (placeId.isEmpty) {
        if (kDebugMode) print(' - Skip: empty doc id');
        continue;
      }

      // Check existing values
      final existingPhone = (doc.data()['venuePhone'] ?? '').toString().trim();
      final existingWeb = (doc.data()['venueWebsite'] ?? '').toString().trim();

      if (onlyIfMissing && existingPhone.isNotEmpty && existingWeb.isNotEmpty) {
        skipped++;
        continue;
      }

      try {
        final details = await _getContacts(placeId);
        if (details == null) {
          if (kDebugMode) print(' - $placeId: details NOT_FOUND');
          continue;
        }

        final phoneLocal =
            (details['formatted_phone_number'] as String?)?.trim() ?? '';
        final phoneIntl =
            (details['international_phone_number'] as String?)?.trim() ?? '';
        final website = (details['website'] as String?)?.trim() ?? '';

        // Choose the best phone to store (prefer international if present).
        final chosenPhone = phoneIntl.isNotEmpty ? phoneIntl : phoneLocal;

        // Build update map respecting onlyIfMissing.
        final update = <String, dynamic>{};
        if (!onlyIfMissing || existingPhone.isEmpty) {
          if (chosenPhone.isNotEmpty) update['venuePhone'] = chosenPhone;
        }
        if (!onlyIfMissing || existingWeb.isEmpty) {
          if (website.isNotEmpty) update['venueWebsite'] = website;
        }

        if (update.isNotEmpty) {
          batch.set(doc.reference, update, SetOptions(merge: true));
          pending++;
          written++;
        } else {
          skipped++;
        }
      } catch (e) {
        errors++;
        if (kDebugMode) print(' - $placeId: ERROR $e');
      }

      // Gentle pacing + periodic commits
      if (perCallDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: perCallDelayMs));
      }
      if (pending >= 400) {
        await batch.commit();
        if (kDebugMode) print('Committed 400 updates…');
        batch = _fire.batch();
        pending = 0;
      }
    }

    if (pending > 0) {
      await batch.commit();
    }

    if (kDebugMode) {
      print('Done. written=$written skipped=$skipped errors=$errors');
    }
  }

  /// Minimal Places Details request for phone + website
  Future<Map<String, dynamic>?> _getContacts(String placeId) async {
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': placeId,
          'fields':
              // Keep it small; only what we need
              'formatted_phone_number,international_phone_number,website',
          'language': 'en',
          'key': apiKey,
        });

    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['status'] != 'OK') {
        if (kDebugMode) {
          print('   DETAILS status=${j['status']} err=${j['error_message']}');
        }
        return null;
      }
      return j['result'] as Map<String, dynamic>?;
    } on Exception catch (e) {
      if (kDebugMode) print('   Places request failed: $e');
      return null;
    }
  }
}
