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
          widget.name,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (widget.image != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          widget.image!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (widget.image != null) const SizedBox(height: 16),

                    // Description (clamped ~2.5 lines -> use maxLines: 3 with ellipsis)
                    if (_summary != null && _summary!.isNotEmpty)
                      Text(
                        _summary!,
                        style: const TextStyle(fontSize: 16, height: 1.15),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                    if (_address != null && _address!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _address!,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],

                    const SizedBox(height: 16),
                    _buildHoursCard(),
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
