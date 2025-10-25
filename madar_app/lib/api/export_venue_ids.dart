// dart run bin/export_venue_ids.dart --key YOUR_API_KEY
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

enum VenueCategory { malls, stadiums, airports }

const double riyadhLat = 24.7136;
const double riyadhLng = 46.6753;

final curated = <VenueCategory, List<String>>{
  VenueCategory.airports: ['King Khalid International Airport'],
  VenueCategory.stadiums: [
    'King Fahd Stadium',
    'KINGDOM ARENA',
    'Al -Awwal Park',
    'Prince Faisal Bin Fahd Stadium',
  ],
  VenueCategory.malls: [
    'Solitaire', // display name; we’ll query "Solitaire Mall Riyadh" under the hood
    'VIA Riyadh',
    'Cenomi Al Nakheel Mall',
    'Cenomi The View Mall',
    'Riyadh Gallery Mall',
    'Granada Mall',
    'Riyadh Park',
    'Panorama Mall',
    'Hayat Mall',
    'Roshn Front - Shopping Area',
  ],
};

Uri gUri(String path, Map<String, String> q) =>
    Uri.https('maps.googleapis.com', path, q);

Future<String?> _findPlaceIdStrict({
  required String text,
  required VenueCategory cat,
  required String apiKey,
}) async {
  final uri = gUri('/maps/api/place/findplacefromtext/json', {
    'input': text,
    'inputtype': 'textquery',
    'fields': 'place_id,name,types,geometry',
    'locationbias': 'circle:20000@$riyadhLat,$riyadhLng',
    'region': 'sa',
    'language': 'en',
    'key': apiKey,
  });
  final r = await http.get(uri);
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (j['status'] != 'OK') return null;

  final cand = (j['candidates'] as List).cast<Map<String, dynamic>>();
  if (cand.isEmpty) return null;

  int score(Map<String, dynamic> c) {
    final types = ((c['types'] as List?)?.cast<String>() ?? [])
        .map((e) => e.toLowerCase())
        .toSet();
    int s = 0;
    if (cat == VenueCategory.malls && types.contains('shopping_mall')) s += 100;
    if (cat == VenueCategory.stadiums && types.contains('stadium')) s += 100;
    if (cat == VenueCategory.airports && types.contains('airport')) s += 100;
    return s;
  }

  cand.sort((b, a) => score(a) - score(b));
  return cand.first['place_id'] as String?;
}

Future<Map<String, dynamic>?> _details({
  required String placeId,
  required String apiKey,
}) async {
  final uri = gUri('/maps/api/place/details/json', {
    'place_id': placeId,
    'fields': 'name,formatted_address,types,geometry',
    'key': apiKey,
  });
  final r = await http.get(uri);
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (j['status'] != 'OK') return null;
  return j['result'] as Map<String, dynamic>;
}

Future<List<Map<String, dynamic>>> _textSearchMall({
  required String query,
  required String apiKey,
}) async {
  final uri = gUri('/maps/api/place/textsearch/json', {
    'query': query,
    'type': 'shopping_mall',
    'region': 'sa',
    'language': 'en',
    'key': apiKey,
  });
  final r = await http.get(uri);
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (j['status'] != 'OK' && j['status'] != 'ZERO_RESULTS') return [];
  return (j['results'] as List).cast<Map<String, dynamic>>();
}

Future<List<Map<String, dynamic>>> _nearbyMallsWithKeyword({
  required String keyword,
  required String apiKey,
}) async {
  final uri = gUri('/maps/api/place/nearbysearch/json', {
    'location': '$riyadhLat,$riyadhLng',
    'radius': '50000',
    'type': 'shopping_mall',
    'keyword': keyword,
    'region': 'sa',
    'language': 'en',
    'key': apiKey,
  });
  final r = await http.get(uri);
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (j['status'] != 'OK' && j['status'] != 'ZERO_RESULTS') return [];
  return (j['results'] as List).cast<Map<String, dynamic>>();
}

Future<String?> _findMallPlaceId({
  required String text,
  required String apiKey,
}) async {
  // Special: avoid the café—query explicitly for the mall
  final queryForMall = (text.trim().toLowerCase() == 'solitaire')
      ? 'Solitaire Mall Riyadh'
      : '$text Riyadh mall';

  // 1) Text Search (mall-only)
  final ts = await _textSearchMall(query: queryForMall, apiKey: apiKey);
  String? pickFrom(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return null;

    // HARD FILTER: malls only
    final mallsOnly = list.where((m) {
      final types = ((m['types'] as List?)?.cast<String>() ?? [])
          .map((e) => e.toLowerCase())
          .toSet();
      return types.contains('shopping_mall');
    }).toList();

    if (mallsOnly.isEmpty) return null;

    int score(Map<String, dynamic> m) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      int s = 0;
      if (name.contains('solitaire')) s += 50;
      if (name.contains('mall')) s += 20;
      if (name.contains('riyadh')) s += 10;
      return s;
    }

    mallsOnly.sort((b, a) => score(a) - score(b));
    return mallsOnly.first['place_id'] as String?;
  }

  String? pid = pickFrom(ts);
  if (pid != null) return pid;

  // 2) Nearby (mall-only) fallback
  final near = await _nearbyMallsWithKeyword(keyword: text, apiKey: apiKey);
  pid = pickFrom(near);
  if (pid != null) return pid;

  // 3) Find Place (generic) + verify via Details that it’s a shopping_mall
  final strict = await _findPlaceIdStrict(
    text: queryForMall,
    cat: VenueCategory.malls,
    apiKey: apiKey,
  );
  if (strict == null) return null;

  final det = await _details(placeId: strict, apiKey: apiKey);
  final types = ((det?['types'] as List?)?.cast<String>() ?? [])
      .map((e) => e.toLowerCase())
      .toSet();
  if (!types.contains('shopping_mall')) {
    return null; // reject cafés/other types
  }
  return strict;
}

String? _readKey(List<String> args) {
  final i = args.indexOf('--key');
  if (i != -1 && i + 1 < args.length) return args[i + 1];
  final env = Platform.environment['GOOGLE_API_KEY'];
  if (env != null && env.isNotEmpty) return env;
  return null;
}

Future<void> main(List<String> args) async {
  final apiKey = _readKey(args);
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'Usage: dart run bin/export_venue_ids.dart --key YOUR_API_KEY',
    );
    exit(2);
  }

  final out = <Map<String, String>>[];

  Future<void> resolveGroup(VenueCategory cat) async {
    for (final name in curated[cat]!) {
      String? pid;
      if (cat == VenueCategory.malls) {
        pid = await _findMallPlaceId(text: name, apiKey: apiKey);
      } else {
        pid = await _findPlaceIdStrict(text: name, cat: cat, apiKey: apiKey);
      }
      stdout.writeln('${cat.name} | $name → ${pid ?? "NOT_FOUND"}');
      out.add({
        'name': name,
        'category': cat.name,
        'place_id': pid ?? 'NOT_FOUND',
      });
    }
  }

  await resolveGroup(VenueCategory.malls);
  await resolveGroup(VenueCategory.stadiums);
  await resolveGroup(VenueCategory.airports);

  stdout.writeln('\n=== JSON ===');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
