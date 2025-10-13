import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:madar_app/screens/venue_page.dart';

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
/// When present, we use the ID directly and skip fuzzy matching.
const Map<String, String> _knownPlaceIds = {
  // Stadiums (examples; fill in real IDs when you resolve them)
  // 'Al -Awwal Park': 'ChIJxxxxxxxxxxxxxxx',
  // 'KINGDOM ARENA': 'ChIJxxxxxxxxxxxxxxx',
  // 'King Fahd Stadium': 'ChIJxxxxxxxxxxxxxxx',
  // 'Prince Faisal Bin Fahd Stadium': 'ChIJxxxxxxxxxxxxxxx',

  // Airport
  // 'King Khalid International Airport': 'ChIJxxxxxxxxxxxxxxx',

  // Malls
  // 'Solitaire': 'ChIJxxxxxxxxxxxxxxx',
  // 'VIA Riyadh': 'ChIJxxxxxxxxxxxxxxx',
  // 'Cenomi Al Nakheel Mall': 'ChIJxxxxxxxxxxxxxxx',
  // 'Cenomi The View Mall': 'ChIJxxxxxxxxxxxxxxx',
  // 'Riyadh Gallery Mall': 'ChIJxxxxxxxxxxxxxxx',
  // 'Granada Mall': 'ChIJxxxxxxxxxxxxxxx',
  // 'Riyadh Park': 'ChIJxxxxxxxxxxxxxxx',
  // 'Panorama Mall': 'ChIJxxxxxxxxxxxxxxx',
  // 'Hayat Mall': 'ChIJxxxxxxxxxxxxxxx',
  // 'Roshn Front - Shopping Area': 'ChIJxxxxxxxxxxxxxxx',
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
      if (_svc.apiKey.isEmpty) {
        throw Exception('Missing GOOGLE_API_KEY in .env');
      }

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

  Future<void> _loadVenues() async {
    final myToken = ++_loadToken;
    if (_isLoadingNow) return;
    _isLoadingNow = true;

    try {
      final tab = filters[selectedFilterIndex];

      // helper: resolve a list of names under a category into VenueData
      Future<List<VenueData>> resolveList(
        VenueCategory cat,
        List<String> names,
      ) async {
        final futures = names.map((name) async {
          // 1) use pinned ID if available
          final pinned = _knownPlaceIds[name];
          final pid = (pinned != null && pinned.isNotEmpty)
              ? pinned
              : await _svc.findPlaceIdStrict(
                  name,
                  expectCategory: cat,
                  biasLat: _riyadhLat,
                  biasLng: _riyadhLng,
                );
          if (pid == null) return null;

          // 2) details (essentials)
          final d = await _svc.details(pid);
          if (d == null) return null;

          final loc =
              (d['geometry']?['location'] ?? {}) as Map<String, dynamic>;
          final photos = (d['photos'] as List?)?.cast<Map<String, dynamic>>();
          final photoRef = (photos != null && photos.isNotEmpty)
              ? photos.first['photo_reference'] as String?
              : null;

          return VenueData(
            placeId: pid,
            name: d['name'] as String?,
            address: d['formatted_address'] as String?,
            lat: (loc['lat'] as num?)?.toDouble(),
            lng: (loc['lng'] as num?)?.toDouble(),
            rating: (d['rating'] ?? 0).toDouble(),
            reviews: d['user_ratings_total'] as int? ?? 0,
            photoUrl: photoRef == null ? null : _svc.photoUrl(photoRef),
            category: cat,
          );
        }).toList();

        final results = await Future.wait(futures);
        return results.whereType<VenueData>().toList();
      }

      // decide which categories to load
      List<Future<List<VenueData>>> tasks;
      if (tab == 'All') {
        tasks = [
          resolveList(VenueCategory.malls, _curatedNames[VenueCategory.malls]!),
          resolveList(
            VenueCategory.stadiums,
            _curatedNames[VenueCategory.stadiums]!,
          ),
          resolveList(
            VenueCategory.airports,
            _curatedNames[VenueCategory.airports]!,
          ),
        ];
      } else if (tab == 'Malls') {
        tasks = [
          resolveList(VenueCategory.malls, _curatedNames[VenueCategory.malls]!),
        ];
      } else if (tab == 'Stadiums') {
        tasks = [
          resolveList(
            VenueCategory.stadiums,
            _curatedNames[VenueCategory.stadiums]!,
          ),
        ];
      } else {
        tasks = [
          resolveList(
            VenueCategory.airports,
            _curatedNames[VenueCategory.airports]!,
          ),
        ];
      }

      final groups = await Future.wait(tasks);
      var items = <VenueData>[for (final g in groups) ...g];

      // text filter (local)
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        items = items
            .where(
              (v) =>
                  (v.name ?? '').toLowerCase().contains(q) ||
                  (v.address ?? '').toLowerCase().contains(q),
            )
            .toList();
      }

      // distance + sort (local)
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

      if (mounted && myToken == _loadToken) {
        setState(() {
          _venues = items;
          _loading = false;
        });
      }
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
          image: v.photoUrl, // null -> placeholder in VenuePage
          description: v.address ?? '',
        ),
      ),
    );
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
              child: v.photoUrl == null
                  ? Container(
                      width: 100,
                      height: 100,
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.location_city,
                        size: 40,
                        color: Colors.grey,
                      ),
                    )
                  : Image.network(
                      v.photoUrl!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
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
  final double? rating;
  final int? reviews;
  final String? photoUrl;
  final VenueCategory category;

  double? distanceMeters;

  VenueData({
    this.placeId,
    this.name,
    this.address,
    this.lat,
    this.lng,
    this.rating,
    this.reviews,
    this.photoUrl,
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

  /// Stricter Find Place: tight Riyadh bias, fetch types, prefer expected category.
  Future<String?> findPlaceIdStrict(
    String text, {
    VenueCategory? expectCategory,
    double biasLat = _riyadhLat,
    double biasLng = _riyadhLng,
  }) async {
    final uri = _uri('/maps/api/place/findplacefromtext/json', {
      'input': text,
      'inputtype': 'textquery',
      'fields': 'place_id,name,types,geometry',
      'locationbias': 'circle:20000@$biasLat,$biasLng', // tighten around Riyadh
      'region': 'sa',
      'language': 'en',
    });

    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['status'] != 'OK') return null;

    final candidates = (j['candidates'] as List).cast<Map<String, dynamic>>();
    if (candidates.isEmpty) return null;

    int score(Map<String, dynamic> c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final types = ((c['types'] as List?)?.cast<String>() ?? const [])
          .map((e) => e.toLowerCase())
          .toSet();
      int s = 0;
      // prefer expected google type
      if (expectCategory == VenueCategory.stadiums && types.contains('stadium'))
        s += 100;
      if (expectCategory == VenueCategory.airports && types.contains('airport'))
        s += 100;
      if (expectCategory == VenueCategory.malls &&
          types.contains('shopping_mall'))
        s += 100;
      // Name tokens to help disambiguate common cases
      if (name.contains('awwal')) s += 10;
      if (name.contains('kingdom arena')) s += 10;
      if (name.contains('king fahd')) s += 10;
      if (name.contains('riyadh park')) s += 5;
      return s;
    }

    candidates.sort((b, a) => score(a) - score(b));
    return candidates.first['place_id'] as String?;
  }

  /// Details (Essentials fields only)
  Future<Map<String, dynamic>?> details(String placeId) async {
    final uri = _uri('/maps/api/place/details/json', {
      'place_id': placeId,
      'fields': [
        'name',
        'formatted_address',
        'geometry',
        'rating',
        'user_ratings_total',
        'opening_hours',
        'photos',
        'website',
      ].join(','),
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['status'] != 'OK') return null;
    return j['result'] as Map<String, dynamic>;
  }

  String photoUrl(String photoRef) =>
      'https://maps.googleapis.com/maps/api/place/photo?maxwidth=600&photo_reference=$photoRef&key=$apiKey';
}
