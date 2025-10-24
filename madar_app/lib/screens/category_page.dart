import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'directions_page.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/services.dart' show rootBundle;

const kGreen = Color(0xFF787E65);

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
      backgroundColor: const Color(0xFFF8F8F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.categoryName,
          style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // 🔍 شريط البحث
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.10),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search in ${widget.categoryName}...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),

          // 🔹 عرض القائمة
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('places')
                  .where('venue_ID', isEqualTo: widget.venueId)
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

                return ListView.builder(
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

  Widget _placeCard(Map<String, dynamic> data, String originalId) {
    final name = data['placeName'] ?? '';
    final desc = data['placeDescription'] ?? '';
    final img = data['placeImage'] ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {},
        child: Row(
          children: [
            // 🖼 صورة المكان
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img.isEmpty
                  ? Container(
                      width: 100,
                      height: 100,
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.image_not_supported,
                        color: Colors.grey,
                      ),
                    )
                  : FutureBuilder<String?>(
                      future: _getDownloadUrl(img),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return Container(
                            width: 100,
                            height: 100,
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
                            width: 100,
                            height: 100,
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                            ),
                          );
                        }
                        return Image.network(
                          snap.data!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
            ),

            // 📄 محتوى الكارد
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 8),

                    // ⭐ التقييم
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
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              r.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
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

            // 🧭 زر الاتجاهات
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                icon: const Icon(Icons.north_east, color: kGreen, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DirectionsPage(placeName: name),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
