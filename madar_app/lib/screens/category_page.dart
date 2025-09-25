import 'package:flutter/material.dart';
import 'directions_page.dart';

const kGreen = Color(0xFF787E65);

class CategoryPage
    extends StatefulWidget {
  final String categoryName;
  const CategoryPage({
    super.key,
    required this.categoryName,
  });

  @override
  State<CategoryPage> createState() =>
      _CategoryPageState();
}

class _CategoryPageState
    extends State<CategoryPage> {
  final TextEditingController
  _searchCtrl = TextEditingController();
  String _query = '';

  final List<ShopItem>
  _allShops = const [
    ShopItem(
      name: '1886',
      description:
          'Streetwear brand rooted in cultural pride, authenticity, and bold self-expression.',
      imagePath: 'images/1886.png',
    ),
    ShopItem(
      name: 'Sephora',
      description:
          'Global beauty retailer for cosmetics, skincare, and fragrances.',
      imagePath: 'images/sephora.png',
    ),
  ];

  List<ShopItem> get _filtered {
    if (_query.trim().isEmpty)
      return _allShops;
    final q = _query.toLowerCase();
    return _allShops.where((s) {
      return s.name
              .toLowerCase()
              .contains(q) ||
          s.description
              .toLowerCase()
              .contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF8F8F3,
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: kGreen,
          ),
          onPressed: () =>
              Navigator.pop(context),
        ),
        title: Text(
          widget.categoryName,
          style: const TextStyle(
            color: kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            margin:
                const EdgeInsets.all(
                  16,
                ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey
                      .withOpacity(
                        0.10,
                      ),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(
                    0,
                    2,
                  ),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) =>
                  setState(
                    () => _query = v,
                  ),
              decoration: InputDecoration(
                hintText:
                    'Search in ${widget.categoryName}...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.grey,
                ),
                border:
                    InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
              ),
            ),
          ),

          Expanded(
            child: ListView.builder(
              itemCount:
                  _filtered.length,
              itemBuilder:
                  (context, i) =>
                      _shopCard(
                        _filtered[i],
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shopCard(ShopItem s) {
    return Container(
      margin:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(12),
        onTap: () {},
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                    8,
                  ),
              child: Image.asset(
                s.imagePath,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),

            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                      12,
                    ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w600,
                        color: Colors
                            .black87,
                      ),
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    Text(
                      s.description,
                      maxLines: 2,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          const TextStyle(
                            color: Colors
                                .black54,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.only(
                    right: 6,
                  ),
              child: IconButton(
                icon: const Icon(
                  Icons.north_east,
                  color: kGreen,
                  size: 20,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DirectionsPage(
                            placeName:
                                s.name,
                          ),
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

// --------- Model ---------
class ShopItem {
  final String name;
  final String description;
  final String imagePath;

  const ShopItem({
    required this.name,
    required this.description,
    required this.imagePath,
  });
}
