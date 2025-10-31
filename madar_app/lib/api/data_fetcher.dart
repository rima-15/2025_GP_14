import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../screens/venue_page.dart';
import 'package:flutter/services.dart' show rootBundle;

class DataFetcher extends StatefulWidget {
  final String venueId;
  final String venueName;
  final double? lat;
  final double? lng;
  final String? dbAddress;
  final String? description;
  final List<String> imagePaths;
  final String? initialCoverUrl;

  const DataFetcher({
    super.key,
    required this.venueId,
    required this.venueName,
    this.lat,
    this.lng,
    this.dbAddress,
    this.description,
    this.imagePaths = const [],
    this.initialCoverUrl,
  });

  @override
  State<DataFetcher> createState() => _DataFetcherState();
}

class _DataFetcherState extends State<DataFetcher> {
  final FirebaseFirestore _fire = FirebaseFirestore.instance;
  late final String _apiKey;
  bool _loading = true;
  String? _error;

  static const String solitaireId = "ChIJcYTQDwDjLj4RZEiboV6gZzM";

  @override
  void initState() {
    super.initState();
    _apiKey = dotenv.maybeGet('GOOGLE_API_KEY') ?? '';
    _fetchAndStore();
  }

  Future<void> _fetchAndStore() async {
    debugPrint('DataFetcher started for ${widget.venueName}');
    try {
      final exists = await _fire
          .collection('places')
          .where('venue_ID', isEqualTo: widget.venueId)
          .limit(1)
          .get();

      if (exists.docs.isNotEmpty) {
        _openVenuePage();
        return;
      }

      if (widget.venueId == solitaireId) {
        await _fetchFromJson(); // solitaire from json
      } else {
        await _fetchFromNearby(); // Other venues from lang-lat
      }

      setState(() => _loading = false);
      _openVenuePage();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // for solitaire only
  Future<void> _fetchFromJson() async {
    final jsonStr = await rootBundle.loadString('assets/venues/solitaire.json');
    final data = json.decode(jsonStr);
    final List places = data['places'] ?? [];
    final centerLat = data['center']?['lat'];
    final centerLng = data['center']?['lng'];

    for (final name in places) {
      if (name.toString().trim().isEmpty) continue;
      final docRef = _fire.collection('places').doc(name);
      final exists = await docRef.get();
      if (exists.exists) continue;

      //by name
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        {
          'location': '$centerLat,$centerLng',
          'radius': '150',
          'keyword': name,
          'key': _apiKey,
        },
      );

      final res = await http.get(uri);
      final body = json.decode(res.body);
      if (body['status'] != 'OK') continue;
      final results = body['results'] as List?;
      if (results == null || results.isEmpty) continue;

      final details = await _placeDetails(results.first['place_id']);
      final photoRef = details['photos']?[0]?['photo_reference'];
      final photoUrl = photoRef != null ? _photoUrl(photoRef) : null;

      await docRef.set({
        'placeName': details['name'] ?? name,
        'placeDescription':
            details['editorial_summary']?['overview'] ?? 'No description',
        'placeImage': photoUrl,
        'venue_ID': widget.venueId,
        'category_IDs': ['unassigned'], //
        'address': details['formatted_address'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  //other venues
  Future<void> _fetchFromNearby() async {
    if (widget.lat == null || widget.lng == null) return;

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/nearbysearch/json',
      {
        'location': '${widget.lat},${widget.lng}',
        'radius': '150',
        'key': _apiKey,
      },
    );

    final r = await http.get(uri);
    final body = json.decode(r.body);

    if (body['status'] != 'OK') return;
    final List results = body['results'] ?? [];

    for (final p in results) {
      final name = p['name'];
      if (name == null) continue;

      final docRef = _fire.collection('places').doc(name);
      final exists = await docRef.get();
      if (exists.exists) continue;

      final details = await _placeDetails(p['place_id']);
      final photoRef = details['photos']?[0]?['photo_reference'];
      final photoUrl = photoRef != null ? _photoUrl(photoRef) : null;

      await docRef.set({
        'placeName': details['name'] ?? name,
        'placeDescription':
            details['editorial_summary']?['overview'] ?? 'No description',
        'placeImage': photoUrl,
        'venue_ID': widget.venueId,
        'category_IDs': ['unassigned'], //
        'address': details['formatted_address'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<Map<String, dynamic>?> _textSearch(String query) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/textsearch/json',
      {'query': query, 'key': _apiKey},
    );
    final r = await http.get(uri);
    if (r.statusCode != 200) return null;
    final jsonBody = json.decode(r.body);
    if (jsonBody['status'] != 'OK') return null;
    return (jsonBody['results'] as List).first;
  }

  Future<Map<String, dynamic>> _placeDetails(String placeId) async {
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': placeId,
          'fields': 'name,photos,formatted_address,editorial_summary',
          'key': _apiKey,
        });
    final r = await http.get(uri);
    final jsonBody = json.decode(r.body);
    if (jsonBody['status'] != 'OK') return {};
    return jsonBody['result'] ?? {};
  }

  String _photoUrl(String ref) =>
      'https://maps.googleapis.com/maps/api/place/photo?maxwidth=700&photo_reference=$ref&key=$_apiKey';

  void _openVenuePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => VenuePage(
          placeId: widget.venueId,
          name: widget.venueName,
          description: widget.description ?? '',
          dbAddress: widget.dbAddress,
          imagePaths: widget.imagePaths,
          initialCoverUrl: widget.initialCoverUrl,
          lat: widget.lat,
          lng: widget.lng,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preparing Venue...')),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Text(_error ?? 'Done'),
      ),
    );
  }
}
