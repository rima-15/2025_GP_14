import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:madar_app/screens/venue_page.dart';

// ADDED: Firestore + Storage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;

/// ------------------ Categories & curated names ------------------

enum VenueCategory { malls, stadiums, airports }

const double _riyadhLat = 24.7136;
const double _riyadhLng = 46.6753;

/// ONLY these venues will be shown, grouped by tabs.
const Map<VenueCategory, List<String>> _curatedNames = {
  VenueCategory.airports: ['King Khalid International Airport'],
  VenueCategory.stadiums: [
    'King Fahd Stadium',
    'KINGDOM ARENA',
    'Al -Awwal Park', // keep exactly this (not Gate 11)
    'Prince Faisal Bin Fahd Stadium',
  ],
  VenueCategory.malls: [
    'Solitaire',
    'VIA Riyadh',
    'Cenomi Al Nakheel Mall',
    'Cenomi The View Mall',
    'Riyadh Gallery Mall',
    'Granada Mall',
    'Riyadh Park',
    'Panorama Mall',
    'Hayat Mall',
    'Roshn Front - Shopping Area',
  ],
};

/// OPTIONALLY pin correct Google place_ids here once you confirm them.
const Map<String, String> _knownPlaceIds = {
  // Example:
  // 'Solitaire': 'ChIJxxxxxxxxxxxxxxx',
};

/// ------------------ Screen ------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final Color activeColor = const Color(0xFF787E65);
  final List<String> filters = const ['All', 'Malls', 'Stadiums', 'Airports'];

  int selectedFilterIndex = 0;
  String _query = '';

  bool _loading = true;
  String? _error;
  List<VenueData> _venues = [];

  // Location (fallback Riyadh center)
  double baseLat = _riyadhLat, baseLng = _riyadhLng;

  // Places service
  late final _PlacesSvc _svc = _PlacesSvc(
    dotenv.maybeGet('GOOGLE_API_KEY') ?? '',
  );

  // Concurrency guard
  int _loadToken = 0;
  bool _isLoadingNow = false;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // get device location (fallback Riyadh)
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (enabled &&
            perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final p = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          baseLat = p.latitude;
          baseLng = p.longitude;
        }
      } catch (_) {}

      await _loadVenues();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _venues = [];
      });
    }
  }

  // Kick off ratings fetch in the background (non-blocking)
  Future<void> _kickOffRatings(List<VenueData> items) async {
    if (_svc.apiKey.isEmpty) return; // no key → skip quietly
    for (final v in items) {
      if (v.placeId == null || v.placeId!.isEmpty) continue;
      _fetchRating(v);
    }
  }

  // Fetch a single rating with a tight timeout, then update state
  Future<void> _fetchRating(VenueData v) async {
    try {
      final details = await _svc
          .details(v.placeId!)
          .timeout(const Duration(seconds: 6));
      if (details == null) return;
      final r = (details['rating'] ?? 0).toDouble();

      if (!mounted) return;
      setState(() {
        v.rating = r; // only rating (no reviews)
      });
    } catch (_) {}
  }

  // DO NOT call Storage here (keeps UI fast).
  // This is a cheap, synchronous pick from doc fields.
  String? _cheapPrimaryUrl(Map<String, dynamic> d) {
    final coverUrl = (d['coverUrl'] as String?)?.trim();
    if (coverUrl != null && coverUrl.isNotEmpty) return coverUrl;

    final photoUrlGoogle = (d['photoUrl_google'] as String?)?.trim();
    if (photoUrlGoogle != null && photoUrlGoogle.isNotEmpty) {
      return photoUrlGoogle;
    }

    final legacy = (d['photoUrl'] as String?)?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;

    return null;
  }

  Future<void> _loadVenues() async {
    final myToken = ++_loadToken;
    if (_isLoadingNow) return;
    _isLoadingNow = true;

    try {
      final tab = filters[selectedFilterIndex];

      // 1) read from Firestore
      final col = FirebaseFirestore.instance.collection('venues');

      Query<Map<String, dynamic>> q = col;
      if (tab == 'Malls') {
        q = q.where('category', isEqualTo: 'malls');
      } else if (tab == 'Stadiums') {
        q = q.where('category', isEqualTo: 'stadiums');
      } else if (tab == 'Airports') {
        q = q.where('category', isEqualTo: 'airports');
      }

      final snap = await q.get();
      debugPrint('venues fetched: ${snap.docs.length} (tab=$tab)');

      var items = <VenueData>[];

      // 2) Build items from Firestore ONLY (no Storage awaits here)
      for (final doc in snap.docs) {
        final d = doc.data();

        final String? name = (d['name'] as String?)?.trim();
        final String? address = (d['address'] as String?)?.trim();
        final String? categoryStr = (d['category'] as String?)?.trim();
        final String? explicitPlaceId = (d['placeId'] as String?)?.trim();

        final loc = (d['location'] as Map<String, dynamic>?) ?? const {};
        final double? lat = (loc['lat'] as num?)?.toDouble();
        final double? lng = (loc['lng'] as num?)?.toDouble();

        final VenueCategory cat = () {
          if (categoryStr == 'stadiums') return VenueCategory.stadiums;
          if (categoryStr == 'airports') return VenueCategory.airports;
          return VenueCategory.malls;
        }();

        // keep coverPath as-is (for lazy image fetch in card)
        final String? coverPath = (d['coverPath'] as String?)?.trim();

        // quick URL if any (will be used until coverPath resolves)
        final String? cheapUrl = _cheapPrimaryUrl(d);

        // prefer doc.placeId; fallback to pinned map if needed
        String? placeId = explicitPlaceId;
        if ((placeId == null || placeId.isEmpty) && name != null) {
          placeId = _knownPlaceIds[name];
        }

        items.add(
          VenueData(
            placeId: placeId,
            name: name,
            address: address,
            lat: lat,
            lng: lng,
            rating: 0, // temp — updated asynchronously
            photoUrl: cheapUrl, // quick URL shown immediately
            coverPath: coverPath, // try downloadURL lazily in card
            category: cat,
          ),
        );
      }

      // 3) local search filter
      if (_query.isNotEmpty) {
        final ql = _query.toLowerCase();
        items = items
            .where(
              (v) =>
                  (v.name ?? '').toLowerCase().contains(ql) ||
                  (v.address ?? '').toLowerCase().contains(ql),
            )
            .toList();
      }

      // 4) sort by distance
      for (final v in items) {
        if (v.lat != null && v.lng != null) {
          v.distanceMeters = Geolocator.distanceBetween(
            baseLat,
            baseLng,
            v.lat!,
            v.lng!,
          );
        } else {
          v.distanceMeters = 1e12;
        }
      }
      items.sort(
        (a, b) =>
            (a.distanceMeters ?? 1e12).compareTo(b.distanceMeters ?? 1e12),
      );

      // 5) show list immediately
      if (mounted && myToken == _loadToken) {
        setState(() {
          _venues = items;
          _loading = false;
        });
      }

      // 6) fetch ONLY ratings in background
      _kickOffRatings(items);
    } catch (e) {
      if (mounted && myToken == _loadToken) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _venues = [];
        });
      }
    } finally {
      _isLoadingNow = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildFilterTabs(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildVenueList(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (q) async {
          setState(() => _query = q);
          await _loadVenues();
        },
        decoration: const InputDecoration(
          hintText: 'Search for a venue ...',
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      height: 35,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final isSelected = selectedFilterIndex == index;
          return GestureDetector(
            onTap: () async {
              setState(() => selectedFilterIndex = index);
              await _loadVenues();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.grey[200],
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Text(
                  filters[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVenueList() {
    if (_venues.isEmpty) {
      return const Center(child: Text('No items.'));
    }
    return ListView.builder(
      itemCount: _venues.length,
      itemBuilder: (context, index) => _buildVenueCard(_venues[index]),
    );
  }

  void _openVenue(VenueData v) {
    if (v.placeId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenuePage(
          placeId: v.placeId!,
          name: v.name ?? '',
          image: v.photoUrl,
          description: v.address ?? '',
          // eventBased: v.category == VenueCategory.stadiums, // enable if your VenuePage has this param
        ),
      ),
    );
  }

  // Lazy image resolver for each card:
  // - First use v.photoUrl if already present (coverUrl/photoUrl_google/photoUrl)
  // - Else, try to resolve coverPath → downloadURL with short timeout
  Future<String?> _imageUrlFor(VenueData v) async {
    if (v.photoUrl != null && v.photoUrl!.isNotEmpty) return v.photoUrl;
    if (v.coverPath == null || v.coverPath!.isEmpty) return null;

    try {
      final ref = storage.FirebaseStorage.instance.ref(v.coverPath!);
      final url = await ref.getDownloadURL().timeout(
        const Duration(seconds: 3),
      ); // short timeout
      // cache for later paints
      v.photoUrl = url;
      return url;
    } catch (_) {
      return null; // fallback handled by widget
    }
  }

  Widget _buildVenueCard(VenueData v) {
    final distanceText = (v.distanceMeters ?? 0) < 1000
        ? '${(v.distanceMeters ?? 0).round()} m'
        : '${((v.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km';

    return InkWell(
      onTap: () => _openVenue(v),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 100,
                height: 100,
                child: FutureBuilder<String?>(
                  future: _imageUrlFor(v),
                  builder: (context, snap) {
                    final url = snap.data ?? v.photoUrl;
                    if (url == null || url.isEmpty) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.location_city,
                          size: 40,
                          color: Colors.grey,
                        ),
                      );
                    }
                    return Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.broken_image,
                          size: 40,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.name ?? 'Unnamed',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v.address ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber[700], size: 18),
                        const SizedBox(width: 4),
                        Text(
                          (v.rating ?? 0).toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          distanceText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------ Data model ------------------

class VenueData {
  final String? placeId;
  final String? name;
  final String? address;
  final double? lat;
  final double? lng;
  double? rating; // <- mutable so background rating can update
  String? photoUrl; // may be set later (cached)
  final String? coverPath; // Storage path (lazy-resolved)
  final VenueCategory category;

  double? distanceMeters;

  VenueData({
    this.placeId,
    this.name,
    this.address,
    this.lat,
    this.lng,
    this.rating,
    this.photoUrl,
    this.coverPath,
    required this.category,
    this.distanceMeters,
  });
}

/// ------------------ Places service ------------------

class _PlacesSvc {
  final String apiKey;
  _PlacesSvc(this.apiKey);

  Uri _uri(String path, Map<String, String> q) =>
      Uri.https('maps.googleapis.com', path, {...q, 'key': apiKey});

  /// Details (only rating) — used only to fetch rating quickly
  Future<Map<String, dynamic>?> details(String placeId) async {
    if (apiKey.isEmpty) return null;
    final uri = _uri('/maps/api/place/details/json', {
      'place_id': placeId,
      'fields': ['rating', 'user_ratings_total'].join(','),
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['status'] != 'OK') return null;
    return j['result'] as Map<String, dynamic>;
  }
}
