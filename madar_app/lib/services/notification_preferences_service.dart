import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationPreferences {
  static const fieldName = 'notificationPreferences';

  final bool allowNotifications;
  final bool allNotifications;
  final bool trackingRequests;
  final bool trackingUpdates;
  final bool meetingPointInvitations;
  final bool meetingPointUpdates;
  final bool refreshLocationRequests;

  const NotificationPreferences({
    required this.allowNotifications,
    required this.allNotifications,
    required this.trackingRequests,
    required this.trackingUpdates,
    required this.meetingPointInvitations,
    required this.meetingPointUpdates,
    required this.refreshLocationRequests,
  });

  factory NotificationPreferences.defaults() {
    return const NotificationPreferences(
      allowNotifications: true,
      allNotifications: true,
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
      allNotifications: false,
      trackingRequests: false,
      trackingUpdates: false,
      meetingPointInvitations: false,
      meetingPointUpdates: false,
      refreshLocationRequests: false,
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
    final explicitAll = readOptional('allNotifications');

    final anyCategoryEnabled =
        trackingRequests ||
        trackingUpdates ||
        meetingPointInvitations ||
        meetingPointUpdates ||
        refreshLocationRequests;

    final allowNotifications =
        explicitAllow ?? explicitAll ?? anyCategoryEnabled;

    if (!allowNotifications) {
      return NotificationPreferences.disabled();
    }

    final allNotifications =
        explicitAll ??
        (trackingRequests &&
            trackingUpdates &&
            meetingPointInvitations &&
            meetingPointUpdates &&
            refreshLocationRequests);

    if (allNotifications) {
      trackingRequests = true;
      trackingUpdates = true;
      meetingPointInvitations = true;
      meetingPointUpdates = true;
      refreshLocationRequests = true;
    }

    return NotificationPreferences(
      allowNotifications: true,
      allNotifications: allNotifications,
      trackingRequests: trackingRequests,
      trackingUpdates: trackingUpdates,
      meetingPointInvitations: meetingPointInvitations,
      meetingPointUpdates: meetingPointUpdates,
      refreshLocationRequests: refreshLocationRequests,
    );
  }

  NotificationPreferences copyWith({
    bool? allowNotifications,
    bool? allNotifications,
    bool? trackingRequests,
    bool? trackingUpdates,
    bool? meetingPointInvitations,
    bool? meetingPointUpdates,
    bool? refreshLocationRequests,
  }) {
    return NotificationPreferences(
      allowNotifications: allowNotifications ?? this.allowNotifications,
      allNotifications: allNotifications ?? this.allNotifications,
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

  bool get everyCategoryEnabled =>
      trackingRequests &&
      trackingUpdates &&
      meetingPointInvitations &&
      meetingPointUpdates &&
      refreshLocationRequests;

  NotificationPreferences syncMasterSwitches() {
    if (!anyCategoryEnabled) {
      return NotificationPreferences.disabled();
    }

    return copyWith(
      allowNotifications: true,
      allNotifications: everyCategoryEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'allowNotifications': allowNotifications,
      'allNotifications': allNotifications,
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
    await _users.doc(uid).set({
      NotificationPreferences.fieldName: prefs.toMap(),
    }, SetOptions(merge: true));
  }
}
