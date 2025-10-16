import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

enum VenueCategory { malls, stadiums, airports }

const double riyadhLat = 24.7136;
const double riyadhLng = 46.6753;

final curated = <VenueCategory, List<String>>{
  VenueCategory.airports: [
    'King Khalid International Airport',
  ],
  VenueCategory.stadiums: [
    'King Fahd Stadium',
    'KINGDOM ARENA',
    'Al -Awwal Park',
    'Prince Faisal Bin Fahd Stadium',
  ],
  VenueCategory.malls: [
    'Solitaire',
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
  final strict = await _findPlaceIdStrict(text: text, cat: VenueCategory.malls, apiKey: apiKey);
  if (strict != null) return strict;

  final near = await _nearbyMallsWithKeyword(keyword: text, apiKey: apiKey);
  if (near.isEmpty) return null;

  int score(String n) {
    n = n.toLowerCase();
    int s = 0;
    if (n.contains('solitaire')) s += 50;
    if (n.contains('mall')) s += 20;
    if (n.contains('riyadh')) s += 10;
    return s;
  }

  near.sort((b, a) => score((a['name'] ?? '').toString()) - score((b['name'] ?? '').toString()));
  return near.first['place_id'] as String?;
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
    stderr.writeln('Usage: dart run bin/export_venue_ids.dart --key YOUR_API_KEY');
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
