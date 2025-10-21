import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:madar_app/screens/venue_page.dart';

// ADDED: Firestore + Storage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;

//Debuging
import 'package:flutter/foundation.dart'; // kDebugMode

// ADDED: on-device HTTP image cache with placeholders/error widgets
import 'package:cached_network_image/cached_network_image.dart';

/// ------------------ Categories & curated names ------------------

const double _riyadhLat = 24.7136;
const double _riyadhLng = 46.6753;

/// ------------------ Screen ------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  // firebase storage
  final storage.FirebaseStorage _coversStorage =
      storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      );
  final Color activeColor = const Color(0xFF787E65);
  final List<String> filters = const ['All', 'Malls', 'Stadiums', 'Airports'];

  int selectedFilterIndex = 0;
  String _query = '';

  bool _loading = true;
  String? _error;

  // NOTE: live list rendered after local filtering
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

  // Simple in-memory cache for resolved {storage path -> downloadURL}
  final Map<String, String> _imageCache = {};

  // ADDED: Cache Firestore results per tab so we don’t re-fetch on tab switch
  // keys: 'All' | 'Malls' | 'Stadiums' | 'Airports'
  final Map<String, List<VenueData>> _tabCache = {};

  // ADDED: cache for ratings already fetched (placeId -> rating)
  final Map<String, double> _ratingCache = {};

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

      await _ensureTabLoaded(); // will serve from cache if present
      _applyLocalFilterAndSort(); // render
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _venues = [];
      });
    }
  }

  /// Ensures the current tab’s data exists in cache. Fetches ONCE per tab.
  Future<void> _ensureTabLoaded() async {
    final tab = filters[selectedFilterIndex];
    if (_tabCache.containsKey(tab)) return; // already have it

    await _loadTab(tab); // fetch Firestore once
  }

  /// Fetch Firestore for a tab and populate cache (no Storage awaits here)
  Future<void> _loadTab(String tab) async {
    final myToken = ++_loadToken;
    if (_isLoadingNow) return;
    _isLoadingNow = true;

    try {
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

      final items = <VenueData>[];

      // 2) Build items from Firestore ONLY (no Storage awaits here)
      for (final doc in snap.docs) {
        final d = doc.data();

        final String? name = (d['name'] as String?)?.trim();
        final String? address = (d['address'] as String?)?.trim();
        final String? description = (d['description'] as String?)?.trim();
        final String? categoryStr = (d['category'] as String?)?.trim();
        final String? explicitPlaceId = (d['placeId'] as String?)?.trim();

        final loc = (d['location'] as Map<String, dynamic>?) ?? const {};
        final double? lat = (loc['lat'] as num?)?.toDouble();
        final double? lng = (loc['lng'] as num?)?.toDouble();

        final String? coverPath = (d['coverPath'] as String?);
        final String? thumbPath = (d['thumbPath'] as String?);

        // prefer doc.placeId (DB is source of truth)
        final String? placeId = explicitPlaceId;

        // distance (for sort; null -> far away)
        double? dist;
        if (lat != null && lng != null) {
          dist = Geolocator.distanceBetween(baseLat, baseLng, lat, lng);
        } else {
          dist = 1e12;
        }

        // re-use cached rating if we already fetched it
        final double? rating = (placeId != null) ? _ratingCache[placeId] : null;

        items.add(
          VenueData(
            placeId: placeId,
            name: name,
            address: address,
            description: description, // keep, passed to VenuePage
            lat: lat,
            lng: lng,
            rating: rating ?? 0, // temp — updated asynchronously
            coverPath: coverPath,
            thumbPath: thumbPath,
            category: categoryStr,
            distanceMeters: dist,
          ),
        );
      }

      // 3) sort by distance once
      items.sort(
        (a, b) =>
            (a.distanceMeters ?? 1e12).compareTo(b.distanceMeters ?? 1e12),
      );

      // 4) cache for the tab; show immediately
      if (mounted && myToken == _loadToken) {
        _tabCache[tab] = items;
        setState(() {
          _loading = false;
        });
      }

      // 5) fetch ONLY ratings in background (skip if cached)
      _kickOffRatings(items);

      // 6) pre-resolve & warm cover URLs (thumb or cover)
      _prefetchCoverUrls(items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } finally {
      _isLoadingNow = false;
    }
  }

  // Kick off ratings fetch in the background (non-blocking)
  Future<void> _kickOffRatings(List<VenueData> items) async {
    if (_svc.apiKey.isEmpty) return; // no key → skip quietly
    for (final v in items) {
      final pid = v.placeId;
      if (pid == null || pid.isEmpty) continue;
      if (_ratingCache.containsKey(pid)) continue; // already have
      _fetchRating(v);
    }
  }

  // Warm the in-memory + disk image cache without blocking UI
  Future<void> _prefetchCoverUrls(List<VenueData> items) async {
    for (final v in items) {
      final p = (v.thumbPath?.isNotEmpty == true) ? v.thumbPath : v.coverPath;
      if (p == null || p.isEmpty) continue;
      if (_imageCache.containsKey(p)) continue;

      try {
        final ref = _coversStorage.ref(p);
        final url = await ref.getDownloadURL().timeout(
          const Duration(seconds: 8),
        );
        _imageCache[p] = url;

        // Warm image bytes cache
        // ignore: unused_result
        CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      } catch (_) {
        // ignore; card will still try lazily on demand
      }
    }
  }

  // Fetch a single rating with a tight timeout, then update state & cache
  Future<void> _fetchRating(VenueData v) async {
    try {
      final details = await _svc
          .details(v.placeId!)
          .timeout(const Duration(seconds: 6));
      if (details == null) return;
      final r = (details['rating'] ?? 0).toDouble();

      _ratingCache[v.placeId!] = r;

      if (!mounted) return;

      // update whatever tab list contains this venue (minimal repaint)
      final tab = filters[selectedFilterIndex];
      final list = _tabCache[tab];
      if (list != null) {
        for (final it in list) {
          if (it.placeId == v.placeId) {
            it.rating = r;
            break;
          }
        }
      }
      _applyLocalFilterAndSort(); // refresh visible list
    } catch (_) {}
  }

  // Apply local search (by NAME ONLY) + keep already-computed distance order
  void _applyLocalFilterAndSort() {
    final tab = filters[selectedFilterIndex];
    final base = _tabCache[tab] ?? [];
    List<VenueData> out = base;

    if (_query.isNotEmpty) {
      final ql = _query.toLowerCase();
      out = base
          .where((v) => (v.name ?? '').toLowerCase().contains(ql))
          .toList();
    }

    setState(() {
      _venues = out;
    });
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
        onChanged: (q) {
          _query = q;
          _applyLocalFilterAndSort(); // local only (name-based)
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
              await _ensureTabLoaded(); // fetch once; otherwise cached
              _applyLocalFilterAndSort();
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

  void _openVenue(VenueData v) async {
    if (v.placeId == null) return;

    // Pass pre-resolved image URL so VenuePage shows instantly (no re-resolve)
    final String? path = (v.thumbPath?.isNotEmpty == true)
        ? v.thumbPath
        : v.coverPath;
    String? coverUrl = (path != null) ? _imageCache[path] : null;

    // If somehow not warmed yet, resolve once now (short timeout)
    if (coverUrl == null && path != null && path.isNotEmpty) {
      try {
        final ref = _coversStorage.ref(path);
        coverUrl = await ref.getDownloadURL().timeout(
          const Duration(seconds: 5),
        );
        _imageCache[path] = coverUrl!;
      } catch (_) {}
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenuePage(
          placeId: v.placeId!,
          name: v.name ?? '',
          description: v.description ?? '',
          dbAddress: v.address,
          coverPath: v.coverPath,
          // ADDED: hand-off the final URL (faster first paint)
          initialCoverUrl: coverUrl,
        ),
      ),
    );
  }

  // Lazy image resolver for each card (prefers small thumb if present)
  Future<String?> _imageUrlFor(VenueData v) async {
    final String? storagePath = (v.thumbPath?.isNotEmpty == true)
        ? v.thumbPath
        : v.coverPath;

    if (storagePath == null || storagePath.isEmpty) {
      if (kDebugMode) debugPrint('COVER: ${v.name} has no coverPath.');
      return null;
    }

    final cached = _imageCache[storagePath];
    if (cached != null) {
      return cached;
    }

    Future<String?> _try(Duration t) async {
      final ref = _coversStorage.ref(storagePath);
      final url = await ref.getDownloadURL().timeout(t);
      _imageCache[storagePath] = url;

      // Warm bytes
      // ignore: unused_result
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      return url;
    }

    try {
      return await _try(const Duration(seconds: 5));
    } catch (_) {
      try {
        return await _try(const Duration(seconds: 3));
      } catch (_) {
        return null;
      }
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
                    final url = snap.data;
                    // Show steady loader first (no “no image” flash)
                    if (url == null || url.isEmpty) {
                      return Container(
                        color: Colors.grey[200],
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[200],
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.broken_image,
                          size: 40,
                          color: Colors.grey,
                        ),
                      ),
                      fadeInDuration: const Duration(milliseconds: 120),
                      memCacheWidth: 300,
                      memCacheHeight: 300,
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
  final String? description; // ADDED (DB text used in VenuePage)
  final double? lat;
  final double? lng;
  double? rating; // <- mutable so background rating can update

  final String? coverPath; // Storage path (lazy-resolved)
  final String? thumbPath; // optional small image for lists (faster)

  final String? category;

  double? distanceMeters;

  VenueData({
    this.placeId,
    this.name,
    this.address,
    this.description,
    this.lat,
    this.lng,
    this.rating,
    this.coverPath,
    this.thumbPath,
    this.category,
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
