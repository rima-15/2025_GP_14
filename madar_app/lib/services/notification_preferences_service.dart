import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationPreferences {
  static const fieldName = 'notificationPreferences';

  final bool allowNotifications;
  final bool trackingRequests;
  final bool trackingUpdates;
  final bool meetingPointInvitations;
  final bool meetingPointUpdates;
  final bool refreshLocationRequests;

  const NotificationPreferences({
    required this.allowNotifications,
    required this.trackingRequests,
    required this.trackingUpdates,
    required this.meetingPointInvitations,
    required this.meetingPointUpdates,
    required this.refreshLocationRequests,
  });

  factory NotificationPreferences.defaults() {
    return const NotificationPreferences(
      allowNotifications: true,
      trackingRequests: true,
      trackingUpdates: true,
      meetingPointInvitations: true,
      meetingPointUpdates: true,
      refreshLocationRequests: true,
    );
  }

  factory NotificationPreferences.disabled() {
    return const NotificationPreferences(
      allowNotifications: false,
      trackingRequests: true,
      trackingUpdates: true,
      meetingPointInvitations: true,
      meetingPointUpdates: true,
      refreshLocationRequests: true,
    );
  }

  factory NotificationPreferences.fromMap(Map<String, dynamic>? map) {
    bool read(String key) {
      final value = map?[key];
      return value is bool ? value : true;
    }

    bool? readOptional(String key) {
      final value = map?[key];
      return value is bool ? value : null;
    }

    var trackingRequests = read('trackingRequests');
    var trackingUpdates = read('trackingUpdates');
    var meetingPointInvitations = read('meetingPointInvitations');
    var meetingPointUpdates = read('meetingPointUpdates');
    var refreshLocationRequests = read('refreshLocationRequests');

    final explicitAllow = readOptional('allowNotifications');
    final legacyAllNotifications = readOptional('allNotifications');

    final anyCategoryEnabled =
        trackingRequests ||
        trackingUpdates ||
        meetingPointInvitations ||
        meetingPointUpdates ||
        refreshLocationRequests;

    final allowNotifications =
        explicitAllow ?? legacyAllNotifications ?? anyCategoryEnabled;

    if (legacyAllNotifications == true) {
      trackingRequests = true;
      trackingUpdates = true;
      meetingPointInvitations = true;
      meetingPointUpdates = true;
      refreshLocationRequests = true;
    }

    return NotificationPreferences(
      allowNotifications: allowNotifications,
      trackingRequests: trackingRequests,
      trackingUpdates: trackingUpdates,
      meetingPointInvitations: meetingPointInvitations,
      meetingPointUpdates: meetingPointUpdates,
      refreshLocationRequests: refreshLocationRequests,
    );
  }

  NotificationPreferences copyWith({
    bool? allowNotifications,
    bool? trackingRequests,
    bool? trackingUpdates,
    bool? meetingPointInvitations,
    bool? meetingPointUpdates,
    bool? refreshLocationRequests,
  }) {
    return NotificationPreferences(
      allowNotifications: allowNotifications ?? this.allowNotifications,
      trackingRequests: trackingRequests ?? this.trackingRequests,
      trackingUpdates: trackingUpdates ?? this.trackingUpdates,
      meetingPointInvitations:
          meetingPointInvitations ?? this.meetingPointInvitations,
      meetingPointUpdates: meetingPointUpdates ?? this.meetingPointUpdates,
      refreshLocationRequests:
          refreshLocationRequests ?? this.refreshLocationRequests,
    );
  }

  bool get anyCategoryEnabled =>
      trackingRequests ||
      trackingUpdates ||
      meetingPointInvitations ||
      meetingPointUpdates ||
      refreshLocationRequests;

  NotificationPreferences disableInApp() {
    return copyWith(allowNotifications: false);
  }

  NotificationPreferences enableInApp() {
    if (anyCategoryEnabled) {
      return copyWith(allowNotifications: true);
    }
    return NotificationPreferences.defaults();
  }

  NotificationPreferences syncMasterSwitches() {
    if (!anyCategoryEnabled) {
      return disableInApp();
    }

    return copyWith(allowNotifications: true);
  }

  Map<String, dynamic> toMap() {
    return {
      'allowNotifications': allowNotifications,
      'trackingRequests': trackingRequests,
      'trackingUpdates': trackingUpdates,
      'meetingPointInvitations': meetingPointInvitations,
      'meetingPointUpdates': meetingPointUpdates,
      'refreshLocationRequests': refreshLocationRequests,
    };
  }
}

class NotificationPreferencesService {
  static final CollectionReference<Map<String, dynamic>> _users =
      FirebaseFirestore.instance.collection('users');

  static Future<NotificationPreferences> load(String uid) async {
    final doc = await _users.doc(uid).get();
    final rawPrefs = doc.data()?[NotificationPreferences.fieldName];
    final prefsMap = rawPrefs is Map<String, dynamic>
        ? rawPrefs
        : rawPrefs is Map
        ? Map<String, dynamic>.from(rawPrefs)
        : null;

    return NotificationPreferences.fromMap(prefsMap);
  }

  static Future<void> save(String uid, NotificationPreferences prefs) async {
    final data = {NotificationPreferences.fieldName: prefs.toMap()};

    try {
      await _users.doc(uid).update(data);
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
      await _users.doc(uid).set(data, SetOptions(merge: true));
    }
  }

  static Future<NotificationPreferences> disableInAppNotifications(
    String uid,
  ) async {
    final current = await load(uid);
    if (!current.allowNotifications) return current;

    final next = current.disableInApp();
    await save(uid, next);
    return next;
  }
}
