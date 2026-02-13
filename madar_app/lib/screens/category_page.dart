import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/api/place_rating_service.dart';
import 'navigation_flow_complete.dart';
// ----------------------------------------------------------------------------
// Category Page - Shows places within a specific category
// ----------------------------------------------------------------------------

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
  bool get wantKeepAlive => true;

  final TextEditingController _searchCtrl = TextEditingController();

  // Static caches persist across navigation (keyed by category)
  static final Map<String, Map<String, double?>> _staticRatingCache = {};
  static final Map<String, Map<String, String>> _staticImageUrlCache = {};

  // Instance caches for this category
  Map<String, double?> get _ratingCache {
    final key = '${widget.venueId}_${widget.categoryId}';
    return _staticRatingCache.putIfAbsent(key, () => {});
  }

  Map<String, String> get _imageUrlCache {
    final key = '${widget.venueId}_${widget.categoryId}';
    return _staticImageUrlCache.putIfAbsent(key, () => {});
  }

  // Rating service for cached ratings
  late final PlaceRatingService _ratingService;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ratingService = PlaceRatingService();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- Firebase Storage ----------

  Future<String?> _getDownloadUrl(String path) async {
    // Check cache first
    if (_imageUrlCache.containsKey(path)) {
      return _imageUrlCache[path];
    }

    try {
      final ref = storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      ).ref(path);

      final url = await ref.getDownloadURL();
      // Cache the URL
      _imageUrlCache[path] = url;
      return url;
    } catch (e) {
      debugPrint('Image load error: $e');
      return null;
    }
  }

  // ---------- Cached Rating ----------

  /// Get rating from Firestore cache (refreshes weekly from API if stale)
  Future<double?> _getCachedRating(String placeId) async {
    // Check local memory cache first
    if (_ratingCache.containsKey(placeId)) {
      return _ratingCache[placeId];
    }

    // Use the rating service which reads from Firestore and refreshes weekly
    final rating = await _ratingService.getCachedRating(
      placeId,
      widget.venueId,
    );

    // Store in local memory cache
    _ratingCache[placeId] = rating;
    return rating;
  }

  // ---------- AR Navigation ----------

  // Check if place has world position for AR navigation
  Future<bool> _hasWorldPosition(String placeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('places')
          .doc(placeId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      // Check for world_position field
      return data.containsKey('worldPosition') && data['worldPosition'] != null;
    } catch (e) {
      debugPrint("Error checking world position: $e");
      return false;
    }
  }

  // Show dialog when AR is not supported for this place
  void _showNoPositionDialog(String placeName) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogPadding = screenWidth < 360 ? 20.0 : 28.0;

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
            padding: EdgeInsets.all(dialogPadding),
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
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.location_off_rounded,
                      size: 42,
                      color: kGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'AR Not Supported',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: kGreen,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                // Description
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

                // Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
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

  Future<void> _openNavigationFlow(
  String placeId,
  String placeName,
  String? poiMaterial,
  String floorSrc,
) async {
    final hasPosition = await _hasWorldPosition(placeId);
    if (!hasPosition) {
      if (!mounted) return;
      _showNoPositionDialog(placeName);
      return;
    }
    if (!mounted) return;

    var material = (poiMaterial ?? '').trim();
if (material.isEmpty) {
  material = 'POIMAT_${placeName.trim()}';
}

// If your DB stores mesh names like "POI_StoreName", convert to POIMAT_
if (material.toUpperCase().startsWith('POI_')) {
  material = 'POIMAT_${material.substring(4)}';
}


    debugPrint(
      '🧾 Category selected: name="$placeName" -> material="$material"',
    );

    if (material == null || material.isEmpty) {
      debugPrint('❌ No material field found in Firestore for "$placeName"');
      return;
    }

    showNavigationDialog(
  context,
  placeName,
  placeId,
  destinationPoiMaterial: material,
  floorSrc: floorSrc,
);


}

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Responsive values
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 16.0;
    final gridSpacing = screenWidth < 360 ? 10.0 : 12.0;
    final crossAxisCount = screenWidth > 600 ? 3 : 2;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
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

          // Search bar
          _buildSearchBar(horizontalPadding),

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
                // Exclude AR_ POIs (they are AR-only and shouldn't show in category pages)
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
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: gridSpacing,
                    mainAxisSpacing: gridSpacing,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data();
                    final originalId = doc.id;

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

  // ---------- UI Builders ----------

  Widget _buildSearchBar(double horizontalPadding) => Container(
    margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
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

  // Place card - entire card is tappable
  Widget _placeCard(
    Map<String, dynamic> data,
    String placeId,
    String placeName,
  ) {
    final name = data['placeName'] ?? '';
    final desc = data['placeDescription'] ?? '';
    final img = data['placeImage'] ?? '';
    final poiMaterial =
        (data['poiMaterial'] ?? data['material'] ?? data['poiMat'])
            ?.toString()
            .trim();
    final floorToken = (data['floorSrc'] ?? data['floor'] ?? data['level']);
    // If floor is missing, pass empty string so PathOverview can auto-detect the floor
    // from the merged POI JSON (GF/F1) instead of forcing GF.
    final floorSrc = floorToken == null ? '' : floorToken.toString().trim();

    return InkWell(
      onTap: () => _openNavigationFlow(placeId, placeName, poiMaterial, floorSrc),

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
              // Image
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

              // Info section
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Place name with navigation arrow
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
                          const Icon(Icons.north_east, color: kGreen, size: 20),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Description
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

                      // Rating (except for services category) - Now uses cached rating
                      if (widget.categoryName.toLowerCase() != 'services')
                        FutureBuilder<double?>(
                          future: _getCachedRating(placeId),
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

  // Build place image with caching - prevents reload on scroll
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
