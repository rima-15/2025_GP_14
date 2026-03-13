import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MeetingPointDraftSnapshot {
  MeetingPointDraftSnapshot(this.data);

  final Map<String, dynamic> data;

  int get step {
    final raw = data['step'];
    if (raw is int) return raw.clamp(1, 5).toInt();
    if (raw is num) return raw.toInt().clamp(1, 5).toInt();
    return 1;
  }

  String? get venueId => _asString(data['venueId']);
  String? get venueName => _asString(data['venueName']);

  List<String> get placeCategories {
    final raw = data['placeCategories'] ?? data['placeTypes'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // Backward-compat alias for older code/keys.
  List<String> get placeTypes => placeCategories;

  Map<String, dynamic>? get hostLocationRaw {
    final raw = data['hostLocation'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  List<Map<String, dynamic>> get selectedFriends {
    final raw = data['selectedFriends'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> get participants {
    final raw = data['participants'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  int get invitedCount => selectedFriends.length;

  int get acceptedCount =>
      participants.where((p) => _asString(p['status']) == 'accepted').length;

  int get declinedCount =>
      participants.where((p) => _asString(p['status']) == 'declined').length;

  int get pendingCount =>
      participants.where((p) => _asString(p['status']) == 'pending').length;

  int get completedSteps => (step - 1).clamp(0, 5).toInt();

  double get completedProgress => completedSteps / 5;

  String get currentStepLabel {
    switch (step) {
      case 4:
        return 'Waiting for participants';
      case 5:
        return 'Suggested meeting point';
      default:
        return 'Create meeting point';
    }
  }

  String get completedStepsLabel {
    if (completedSteps <= 0) return 'No completed steps yet';
    if (completedSteps == 1) return 'Completed step: 1';
    return 'Completed steps: 1-$completedSteps';
  }

  static String? _asString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return text;
  }
}

class MeetingPointDraftStorage {
  static const String _storageKeyPrefix = 'meeting_point_draft_v1_';

  static Future<String?> _storageKeyForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return null;
    return '$_storageKeyPrefix$uid';
  }

  static Future<void> saveForCurrentUser(Map<String, dynamic> payload) async {
    final key = await _storageKeyForCurrentUser();
    if (key == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(payload));
  }

  static Future<MeetingPointDraftSnapshot?> loadForCurrentUser() async {
    final key = await _storageKeyForCurrentUser();
    if (key == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.remove(key);
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final stepRaw = map['step'];
      final step = (stepRaw is num) ? stepRaw.toInt() : 1;
      if (step < 4 || step > 5) {
        await prefs.remove(key);
        return null;
      }
      return MeetingPointDraftSnapshot(map);
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  static Future<void> clearForCurrentUser() async {
    final key = await _storageKeyForCurrentUser();
    if (key == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
