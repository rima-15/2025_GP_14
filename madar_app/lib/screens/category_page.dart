import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'directions_page.dart'; // تأكد من استيراد صفحة التوجيهات

const kGreen = Color(0xFF787E65);

class CategoryPage extends StatefulWidget {
  final String categoryName;
  final String venueId;
  final String categoryId; // 👈 أضف هذا

  const CategoryPage({
    super.key,
    required this.categoryName,
    required this.venueId,
    required this.categoryId, // 👈
  });

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, double?> _ratingCache = {};

  late String _apiKey;
  String _query = '';

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

  Future<double?> _getLiveRating(String placeName) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/textsearch/json',
      {'query': placeName, 'key': _apiKey},
    );
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
          // Search Bar - تم إضافته من النسخة القديمة
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

          // List with Firebase Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('places')
                  .where('venue_ID', isEqualTo: widget.venueId)
                  .where('category_ID', isEqualTo: widget.categoryId)
                  .orderBy('placeName') // 🔹 يرتب أبجدياً
                  .snapshots(),

              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  //return Center(child: Text('Error: ${snapshot.error}'));
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

                // تطبيق الفلترة بناء على البحث
                final filteredDocs = docs.where((doc) {
                  if (_query.trim().isEmpty) return true;
                  final data = doc.data();
                  final name = (data['placeName'] ?? '')
                      .toString()
                      .toLowerCase();
                  final q = _query.toLowerCase();
                  return name.contains(q); // 🔹 يبحث فقط بالاسم
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('No results found.'));
                }

                return ListView.builder(
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, i) =>
                      _placeCard(filteredDocs[i].data()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeCard(Map<String, dynamic> data) {
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
      // InkWell للضغط - تم إضافته من النسخة القديمة
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // يمكنك إضافة Navigation لصفحة تفاصيل المكان هنا
          // Navigator.push(context, MaterialPageRoute(builder: (_) => PlaceDetailsPage(...)));
        },
        child: Row(
          children: [
            // صورة المكان
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
                  : Image.network(
                      img,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 100,
                          height: 100,
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
            ),

            // محتوى الكارد
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اسم المكان
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

                    // الوصف
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 8),

                    // التقييم - المميزة الجديدة
                    FutureBuilder<double?>(
                      future: _ratingCache[name] != null
                          ? Future.value(_ratingCache[name])
                          : _getLiveRating(name).then((r) {
                              _ratingCache[name] = r;
                              return r;
                            }),

                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const SizedBox.shrink();
                        }
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

            // زر التوجيهات - تم إضافته من النسخة القديمة
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
