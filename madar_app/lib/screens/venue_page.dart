import 'package:flutter/material.dart';
import 'category_page.dart';

const kGreen = Color(0xFF787E65);

class VenuePage
    extends StatelessWidget {
  final String name;
  final String image;
  final String description;

  const VenuePage({
    super.key,
    required this.name,
    required this.image,
    required this.description,
  });

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
          name,
          style: const TextStyle(
            color: kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          bottom: 24,
        ),
        children: [
          // صورة المكان
          Image.asset(
            image,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),

          // الوصف
          Padding(
            padding:
                const EdgeInsets.all(
                  16,
                ),
            child: Text(
              description,
              style: const TextStyle(
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),

          // أوقات العمل
          Card(
            margin:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
            child: ExpansionTile(
              leading: const Icon(
                Icons.schedule,
                color: Colors.black87,
              ),
              title: const Text(
                "Open · 10 AM – 12 AM",
                style: TextStyle(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              children: const [
                ListTile(
                  title: Text(
                    "Sun – Wed",
                  ),
                  trailing: Text(
                    "10 AM – 12 AM",
                  ),
                ),
                ListTile(
                  title: Text(
                    "Thu – Fri",
                  ),
                  trailing: Text(
                    "10 AM – 1 AM",
                  ),
                ),
                ListTile(
                  title: Text("Sat"),
                  trailing: Text(
                    "10 AM – 12 AM",
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // الخريطة (Placeholder)
          const Padding(
            padding:
                EdgeInsets.symmetric(
                  horizontal: 16,
                ),
            child: Text(
              "Floor Map",
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.all(
                  16,
                ),
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: const Color(
                  0xFFEDEFE3,
                ),
                borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
              ),
              child: const Center(
                child: Icon(
                  Icons.map_outlined,
                  size: 48,
                  color: Colors.black45,
                ),
              ),
            ),
          ),

          // كاتيجوريز
          const Padding(
            padding:
                EdgeInsets.symmetric(
                  horizontal: 16,
                ),
            child: Text(
              "Explore Categories",
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets.all(
                    16,
                  ),
              children: [
                _categoryCard(
                  context,
                  "Shops",
                  "120 places",
                  "images/Shops.png",
                ),
                const SizedBox(
                  width: 12,
                ),
                _categoryCard(
                  context,
                  "Cafes",
                  "25 places",
                  "images/Cafes.jpg",
                ),
                const SizedBox(
                  width: 12,
                ),
                _categoryCard(
                  context,
                  "Restaurants",
                  "40 places",
                  "images/restaurants.jpeg",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _categoryCard(
    BuildContext context,
    String title,
    String subtitle,
    String image,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CategoryPage(
                  categoryName: title,
                ),
          ),
        );
      },
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(
                0,
                3,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(
                    top:
                        Radius.circular(
                          14,
                        ),
                  ),
              child: Image.asset(
                image,
                height: 100,
                width: 140,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.all(
                    8,
                  ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                  ),
                  Text(
                    subtitle,
                    style:
                        const TextStyle(
                          color: Colors
                              .black54,
                          fontSize: 12,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
