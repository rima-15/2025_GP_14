import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Venue details page
class VenuePage extends StatefulWidget {
  final String placeId;       // required
  final String name;          // required
  final String? image;        // optional cover
  final String? description;  // optional (fallback if API has no summary/address)

  const VenuePage({
    super.key,
    required this.placeId,
    required this.name,
    this.image,
    this.description,
  });

  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage> {
  bool _loading = true;
  String? _error;

  // Data from Place Details
  String? _address;
  String? _summary; // prefer editorial summary if available; else address/prop desc
  bool? _openNow;
  List<String> _weekdayText = const []; // e.g., ["Monday: 9:00 AM – 10:00 PM", ...]

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final key = dotenv.maybeGet('GOOGLE_API_KEY') ?? '';
      if (key.isEmpty) {
        throw Exception('Missing GOOGLE_API_KEY in .env');
      }

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': widget.placeId,
          // Essentials-only fields (no Pro). editorial_summary may return when available;
          // if it’s absent, we’ll fallback to address/prop description.
          'fields': [
            'formatted_address',
            'opening_hours',
            'editorial_summary', // if not returned, that’s fine
            'website',
            'name',
          ].join(','),
          'key': key,
        },
      );

      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      final j = jsonDecode(r.body) as Map<String, dynamic>;

      if (j['status'] != 'OK') {
        throw Exception('Details error: ${j['status']} ${j['error_message'] ?? ''}');
      }

      final res = (j['result'] as Map<String, dynamic>?) ?? {};
      final opening = (res['opening_hours'] as Map<String, dynamic>?) ?? {};

      final editorial = (res['editorial_summary'] as Map<String, dynamic>?)?['overview'] as String?;
      final addr = res['formatted_address'] as String?;

      setState(() {
        _address = addr;
        // Pick best available description
        _summary = editorial?.trim().isNotEmpty == true
            ? editorial!.trim()
            : (widget.description?.trim().isNotEmpty == true
                ? widget.description!.trim()
                : (addr ?? ''));
        _openNow = opening['open_now'] as bool?;
        _weekdayText = (opening['weekday_text'] as List?)?.cast<String>() ?? const [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
          // أوقات العمل
          Card(
            margin:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
            ),
            color: Colors
                .white, // نخلي الخلفية بيضاء وواضحة
            shadowColor: Colors.black
                .withOpacity(0.05),
            elevation: 3,
            child: Theme(
              data: Theme.of(context)
                  .copyWith(
                    dividerColor: Colors
                        .transparent, // نخفي الخط اللي يفصل
                    splashColor: Colors
                        .transparent,
                    highlightColor:
                        Colors
                            .transparent,
                  ),
              child: ExpansionTile(
                leading: const Icon(
                  Icons.schedule,
                  color:
                      kGreen, // نفس لون الثيم الأخضر
                ),
                title: const Text(
                  "Open · 10 AM – 12 AM",
                  style: TextStyle(
                    fontWeight:
                        FontWeight.w600,
                    color:
                        Colors.black87,
                  ),
                ),
                iconColor: kGreen,
                collapsedIconColor:
                    kGreen,
                childrenPadding:
                    const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                children: const [
                  ListTile(
                    dense: true,
                    visualDensity:
                        VisualDensity(
                          vertical: -3,
                        ),
                    title: Text(
                      "Sun – Wed",
                      style: TextStyle(
                        color: Colors
                            .black87,
                      ),
                    ),
                    trailing: Text(
                      "10 AM – 12 AM",
                      style: TextStyle(
                        color: Colors
                            .black54,
                      ),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    visualDensity:
                        VisualDensity(
                          vertical: -3,
                        ),
                    title: Text(
                      "Thu – Fri",
                      style: TextStyle(
                        color: Colors
                            .black87,
                      ),
                    ),
                    trailing: Text(
                      "10 AM – 1 AM",
                      style: TextStyle(
                        color: Colors
                            .black54,
                      ),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    visualDensity:
                        VisualDensity(
                          vertical: -3,
                        ),
                    title: Text(
                      "Sat",
                      style: TextStyle(
                        color: Colors
                            .black87,
                      ),
                    ),
                    trailing: Text(
                      "10 AM – 12 AM",
                      style: TextStyle(
                        color: Colors
                            .black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

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

  Widget _buildHoursCard() {
    final todayIndex = DateTime.now().weekday % 7; // 1=Mon..7=Sun -> 0..6
    String? todayLine;
    if (_weekdayText.isNotEmpty && todayIndex < _weekdayText.length) {
      todayLine = _weekdayText[todayIndex];
    }

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, size: 20),
                const SizedBox(width: 8),
                const Text('Opening hours', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_openNow != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _openNow! ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _openNow! ? 'Open now' : 'Closed',
                      style: TextStyle(
                        color: _openNow! ? Colors.green[800] : Colors.red[800],
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (todayLine != null) ...[
              Text(
                todayLine,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
            ],

            if (_weekdayText.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _weekdayText.asMap().entries.map((e) {
                  final isToday = e.key == todayIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 13,
                        color: isToday ? Colors.black87 : Colors.grey[700],
                        fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              )
            else
              const Text(
                'Hours not available.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
