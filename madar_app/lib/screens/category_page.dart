import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'directions_page.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/services.dart' show rootBundle;

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

class _CategoryPageState extends State<CategoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, double?> _ratingCache = {};

  late String _apiKey;
  String _query = '';

  // ✅ الدالة الصحيحة لجلب رابط الصورة من Firebase Storage
  Future<String?> _getDownloadUrl(String path) async {
    try {
      final ref = storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      ).ref(path);

      final url = await ref.getDownloadURL();
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
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<double?> _getLiveRating(String docId) async {
    final bool isSolitaire = widget.venueId == "ChIJcYTQDwDjLj4RZEiboV6gZzM";
    Uri uri;

    if (isSolitaire) {
      // ✅ نقرأ المركز من ملف solitaire.json
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
            'keyword': docId, // نبحث بالـ Document ID
            'key': _apiKey,
          },
        );
      } catch (e) {
        debugPrint("⚠️ Error loading solitaire.json: $e");
        return null;
      }
    } else {
      // ✅ باقي الفنيوز نجيب الـ lat/lng من Firestore
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

    // ✅ الطلب من Google API
    final r = await http.get(uri);
    if (r.statusCode != 200) return null;

    final j = json.decode(r.body);
    if (j['status'] != 'OK') return null;

    final results = j['results'] as List?;
    if (results == null || results.isEmpty) return null;

    return (results.first['rating'] ?? 0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
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

          // 🔹 عرض القائمة على شكل Grid
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
                  .orderBy('placeName')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Something went wrong. Please try again later.',
                      style: TextStyle(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No places found.'));
                }

                final filteredDocs = docs.where((doc) {
                  if (_query.trim().isEmpty) return true;
                  final data = doc.data();
                  final name = (data['placeName'] ?? '')
                      .toString()
                      .toLowerCase();
                  final q = _query.toLowerCase();
                  return name.contains(q);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('No results found.'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75, // Adjusted for better content fit
                  ),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, i) =>
                      _placeCard(filteredDocs[i].data(), filteredDocs[i].id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🔍 Search bar - exact style from home page
  Widget _buildSearchBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
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

  Widget _placeCard(Map<String, dynamic> data, String originalId) {
    final name = data['placeName'] ?? '';
    final desc = data['placeDescription'] ?? '';
    final img = data['placeImage'] ?? '';

    return Container(
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
            // 🖼 صورة المكان - Square aspect ratio
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
                  : FutureBuilder<String?>(
                      future: _getDownloadUrl(img),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.grey[200],
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          );
                        }
                        if (!snap.hasData ||
                            snap.data == null ||
                            snap.data!.isEmpty) {
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
                        return Image.network(
                          snap.data!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
            ),

            // 📄 محتوى الكارد
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
                        // 🧭 Navigation arrow button
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DirectionsPage(placeName: name),
                              ),
                            );
                          },
                          child: const Icon(
                            Icons.north_east,
                            color: kGreen,
                            size: 20,
                          ),
                        ),
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

                    // ⭐ التقييم - Green star + number
                    FutureBuilder<double?>(
                      future: _ratingCache[originalId] != null
                          ? Future.value(_ratingCache[originalId])
                          : _getLiveRating(originalId).then((r) {
                              _ratingCache[originalId] = r;
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
    );
  }
}
