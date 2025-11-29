import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'directions_page.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/services.dart' show rootBundle;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:madar_app/screens/unity_page.dart';
import 'package:permission_handler/permission_handler.dart';

const kGreen = Color(0xFF777D63);

class CategoryPage extends StatefulWidget {
  final String categoryName;
  final String venueId;
  final String categoryId;

  const CategoryPage({
    super.key,
    required this.categoryName,
    required this.venueId,
    required this.categoryId,
  });

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // ✅ Keep state alive when navigating away

  final TextEditingController _searchCtrl = TextEditingController();

  // ✅ Static caches persist across navigation (keyed by category)
  static final Map<String, Map<String, double?>> _staticRatingCache = {};
  static final Map<String, Map<String, String>> _staticImageUrlCache = {};

  // ✅ Get instance caches for this category
  Map<String, double?> get _ratingCache {
    final key = '${widget.venueId}_${widget.categoryId}';
    return _staticRatingCache.putIfAbsent(key, () => {});
  }

  Map<String, String> get _imageUrlCache {
    final key = '${widget.venueId}_${widget.categoryId}';
    return _staticImageUrlCache.putIfAbsent(key, () => {});
  }

  late String _apiKey;
  String _query = '';

  // Firebase Storage
  Future<String?> _getDownloadUrl(String path) async {
    // ✅ Check cache first
    if (_imageUrlCache.containsKey(path)) {
      return _imageUrlCache[path];
    }

    try {
      final ref = storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      ).ref(path);

      final url = await ref.getDownloadURL();
      // ✅ Cache the URL
      _imageUrlCache[path] = url;
      return url;
    } catch (e) {
      debugPrint('⚠️ Image load error: $e');
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _apiKey = dotenv.maybeGet('GOOGLE_API_KEY') ?? '';
  }

  @override
  void dispose() {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    _searchCtrl.dispose();

    super.dispose();
  }

  Future<double?> _getLiveRating(String docId) async {
    final bool isSolitaire = widget.venueId == "ChIJcYTQDwDjLj4RZEiboV6gZzM";
    Uri uri;

    if (isSolitaire) {
      //solitaire.json
      try {
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
            'keyword': docId, //  Document ID
            'key': _apiKey,
          },
        );
      } catch (e) {
        debugPrint("⚠️ Error loading solitaire.json: $e");
        return null;
      }
    } else {
      // Firestore
      final venueSnap = await FirebaseFirestore.instance
          .collection('venues')
          .doc(widget.venueId)
          .get();

      if (!venueSnap.exists) return null;
      final lat = venueSnap.data()?['latitude'];
      final lng = venueSnap.data()?['longitude'];

      if (lat == null || lng == null) return null;

      uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        {
          'location': '$lat,$lng',
          'radius': '150',
          'keyword': docId,
          'key': _apiKey,
        },
      );
    }

    // Google API
    final r = await http.get(uri);
    if (r.statusCode != 200) return null;

    final j = json.decode(r.body);
    if (j['status'] != 'OK') return null;

    final results = j['results'] as List?;
    if (results == null || results.isEmpty) return null;

    return (results.first['rating'] ?? 0).toDouble();
  }

  // NEW: Validate if place has world position for AR navigation
  Future<bool> _hasWorldPosition(String placeId) async {
    try {
      debugPrint("🔍 [FLUTTER] Checking world position for placeId: $placeId");

      final doc = await FirebaseFirestore.instance
          .collection('places')
          .doc(placeId)
          .get();

      if (!doc.exists) {
        debugPrint("⚠️ [FLUTTER] Place document does not exist: $placeId");
        return false;
      }

      final data = doc.data();
      if (data == null) {
        debugPrint("⚠️ [FLUTTER] Place data is null: $placeId");
        return false;
      }

      // NEW: Check for world_position field (adjust field name based on your Firebase structure)
      final hasPosition =
          data.containsKey('worldPosition') && data['worldPosition'] != null;

      debugPrint("📍 [FLUTTER] World position check result:");
      debugPrint("   PlaceID: $placeId");
      debugPrint("   Has world_position: $hasPosition");

      if (hasPosition) {
        debugPrint("   Position data: ${data['worldPosition']}");
      }

      return hasPosition;
    } catch (e) {
      debugPrint("❌ [FLUTTER] Error checking world position: $e");
      return false;
    }
  }

  // ✅ Enhanced AR not supported dialog with vibrant design
  void _showNoPositionDialog(String placeName) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✨ Cute illustration/icon with Madar colors
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.15), // Light green background
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.location_off_rounded,
                      size: 42,
                      color: kGreen, // Madar green
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 📌 Title
                const Text(
                  'AR Not Supported',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: kGreen, // Madar green
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                // 📝 Description
                Text(
                  'This place doesn\'t support AR navigation yet. Please check back later!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 24),

                // ✅ "Got it" button with Madar green
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen, // Madar green
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // UPDATED: Open navigation AR with validation and placeId passing
  Future<void> _openNavigationAR(String placeId, String placeName) async {
    debugPrint("═══════════════════════════════════════════════════");
    debugPrint("🧭 [FLUTTER] Navigation requested");
    debugPrint("   Place: $placeName");
    debugPrint("   PlaceID: $placeId");
    debugPrint("═══════════════════════════════════════════════════");

    // NEW: Validate world position before proceeding
    final hasPosition = await _hasWorldPosition(placeId);

    if (!hasPosition) {
      debugPrint(
        "⚠️ [FLUTTER] Place does not have world position - blocking navigation",
      );

      if (!mounted) return;

      // NEW FIX: Show dialog instead of SnackBar
      _showNoPositionDialog(placeName);
      return;
    }

    debugPrint(
      "✅ [FLUTTER] World position validated - proceeding with camera permission",
    );

    // Request camera permission
    final status = await Permission.camera.request();

    if (status.isGranted) {
      debugPrint("✅ [FLUTTER] Camera permission granted");
      debugPrint("🚀 [FLUTTER] Opening Unity in NAVIGATION mode");
      debugPrint("   Passing PlaceID: $placeId");

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UnityCameraPage(
            isNavigation: true,
            placeId: placeId, // NEW: Pass the placeId
          ),
        ),
      );
    } else if (status.isPermanentlyDenied) {
      debugPrint("⚠️ [FLUTTER] Camera permission permanently denied");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is permanently denied. Please enable it from Settings.',
          ),
        ),
      );
      openAppSettings();
    } else {
      debugPrint("⚠️ [FLUTTER] Camera permission denied");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to use AR.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: kGreen, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          widget.categoryName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: kGreen,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // 🔍 Search bar - below header
          _buildSearchBar(),

          const SizedBox(height: 12),

          // Grid
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('places')
                  .where(
                    'venue_ID',
                    isEqualTo: widget.venueId == 'ChIJcYTQDwDjLj4RZEiboV6gZzM'
                        ? 'ChIJcYTQDwDjLj4RZEiboV6gZzM'
                        : widget.venueId,
                  )
                  .where('category_IDs', arrayContains: widget.categoryId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: kGreen),
                  );
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No places found in this category.'),
                  );
                }

                // Client-side filtering
                final allDocs = snapshot.data!.docs;
                // ✅ Exclude AR_ POIs (they are AR-only and shouldn't show in category pages)
                final nonArDocs = allDocs
                    .where((doc) => !doc.id.startsWith('AR_'))
                    .toList();
                final filtered = _query.trim().isEmpty
                    ? nonArDocs
                    : nonArDocs.where((doc) {
                        final name = (doc.data()['placeName'] as String? ?? '')
                            .toLowerCase();
                        final q = _query.toLowerCase();
                        return name.contains(q);
                      }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No matching places found.'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data();
                    final originalId = doc.id;

                    // UPDATED: Pass both placeId and placeName to the card
                    return _placeCard(
                      data,
                      originalId,
                      data['placeName'] ?? 'Unknown',
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300, width: 1),
    ),
    child: Row(
      children: [
        Icon(Icons.search, color: Colors.grey.shade600, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search in ${widget.categoryName}',
              hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ],
    ),
  );

  // NEW FIX: Entire card is now tappable
  Widget _placeCard(
    Map<String, dynamic> data,
    String placeId,
    String placeName,
  ) {
    final name = data['placeName'] ?? '';
    final desc = data['placeDescription'] ?? '';
    final img = data['placeImage'] ?? '';

    return InkWell(
      // NEW FIX: Make entire card tappable
      onTap: () {
        debugPrint("🔘 [FLUTTER] Card tapped: $placeName");
        _openNavigationAR(placeId, placeName);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Square aspect ratio
              Expanded(
                flex: 5,
                child: img.isEmpty
                    ? Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.image_not_supported,
                          color: Colors.grey,
                          size: 32,
                        ),
                      )
                    : _buildPlaceImage(img),
              ),

              //
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Place name with navigation arrow (visual indicator only)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color.fromARGB(255, 44, 44, 44),
                              ),
                            ),
                          ),
                          // 🧭 Navigation arrow (visual indicator - card handles tap)
                          const Icon(Icons.north_east, color: kGreen, size: 20),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Description - flexible to prevent overflow
                      Flexible(
                        child: Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.3,
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // - Green star + number
                      if (widget.categoryName.toLowerCase() != 'services')
                        FutureBuilder<double?>(
                          future: _ratingCache[placeId] != null
                              ? Future.value(_ratingCache[placeId])
                              : _getLiveRating(placeId).then((r) {
                                  _ratingCache[placeId] = r;
                                  return r;
                                }),
                          builder: (context, snap) {
                            if (!snap.hasData) return const SizedBox.shrink();
                            final r = snap.data ?? 0.0;
                            if (r == 0.0) return const SizedBox.shrink();
                            return Row(
                              children: [
                                const Icon(Icons.star, color: kGreen, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  r.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Build place image with caching - prevents reload on scroll
  Widget _buildPlaceImage(String imgPath) {
    // Check if we already have the URL cached
    if (_imageUrlCache.containsKey(imgPath)) {
      return CachedNetworkImage(
        imageUrl: _imageUrlCache[imgPath]!,
        cacheKey: imgPath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[200]),
        errorWidget: (context, url, error) => Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey[200],
          child: const Icon(
            Icons.image_not_supported,
            color: Colors.grey,
            size: 32,
          ),
        ),
      );
    }

    // Not cached yet - load once and cache
    return FutureBuilder<String?>(
      future: _getDownloadUrl(imgPath),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey[200],
            alignment: Alignment.center,
            child: FutureBuilder(
              future: Future.delayed(const Duration(milliseconds: 500)),
              builder: (context, delaySnap) {
                if (delaySnap.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                return CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kGreen,
                  backgroundColor: kGreen.withOpacity(0.2),
                );
              },
            ),
          );
        }
        if (!snap.hasData || snap.data == null || snap.data!.isEmpty) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey[200],
            child: const Icon(
              Icons.image_not_supported,
              color: Colors.grey,
              size: 32,
            ),
          );
        }
        // URL loaded - now display with CachedNetworkImage
        return CachedNetworkImage(
          imageUrl: snap.data!,
          cacheKey: imgPath,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey[200]),
          errorWidget: (context, url, error) => Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey[200],
            child: const Icon(
              Icons.image_not_supported,
              color: Colors.grey,
              size: 32,
            ),
          ),
        );
      },
    );
  }
}
