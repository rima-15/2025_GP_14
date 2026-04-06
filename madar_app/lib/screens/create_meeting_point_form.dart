import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:madar_app/nav/navmesh.dart';
import 'package:madar_app/screens/navigation_flow_complete.dart'
    show SetYourLocationDialog;
import 'package:madar_app/screens/AR_page.dart';
import 'package:madar_app/screens/meeting_point_draft_storage.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

// ── DEV FLAG ──────────────────────────────────────────────────────────────────
/// Set to true so the full wizard can be tested even outside a real venue.
const bool forceVenueForTesting = true;
const String _kTestVenueName = 'Solitaire';
const String _kTestVenueId = 'ChIJcYTQDwDjLj4RZEiboV6gZzM';
const String _kFallbackMapVenueId = 'ChIJcYTQDwDjLj4RZEiboV6gZzM';

/// Geofence radius in metres – user must be this close to a venue centre.
const double _kVenueGeofenceMeters = 150;

class MeetingPointParticipant {
  const MeetingPointParticipant({
    required this.userId,
    required this.name,
    required this.phone,
    required this.status,
    this.respondedAt,
    this.updatedAt,
    this.arrivalStatus = 'on_the_way',
    this.arrivedAt,
    this.estimatedArrivalMinutes = 3,
    this.locationUpdatedAt,
  });

  final String userId;
  final String name;
  final String phone;
  final String status; // pending | accepted | declined
  final DateTime? respondedAt;
  final DateTime? updatedAt;

  // ── Arrival tracking (populated when meeting status becomes 'active') ──────
  final String arrivalStatus; // on_the_way | arrived | cancelled
  final DateTime? arrivedAt;
  final int estimatedArrivalMinutes; // 1-5 (random)
  final DateTime? locationUpdatedAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
  bool get isCancelledParticipation => status == 'cancelled';

  bool get isOnTheWay => arrivalStatus == 'on_the_way';
  bool get isArrived => arrivalStatus == 'arrived';
  bool get isCancelledArrival => arrivalStatus == 'cancelled';

  MeetingPointParticipant copyWith({
    String? status,
    DateTime? respondedAt,
    DateTime? updatedAt,
    String? arrivalStatus,
    DateTime? arrivedAt,
    int? estimatedArrivalMinutes,
    DateTime? locationUpdatedAt,
  }) {
    return MeetingPointParticipant(
      userId: userId,
      name: name,
      phone: phone,
      status: status ?? this.status,
      respondedAt: respondedAt ?? this.respondedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      arrivalStatus: arrivalStatus ?? this.arrivalStatus,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      estimatedArrivalMinutes:
          estimatedArrivalMinutes ?? this.estimatedArrivalMinutes,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'phone': phone,
      'status': status,
      'respondedAt': respondedAt == null
          ? null
          : Timestamp.fromDate(respondedAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'arrivalStatus': arrivalStatus,
      'arrivedAt': arrivedAt == null ? null : Timestamp.fromDate(arrivedAt!),
      'estimatedArrivalMinutes': estimatedArrivalMinutes,
      'locationUpdatedAt': locationUpdatedAt == null
          ? null
          : Timestamp.fromDate(locationUpdatedAt!),
    };
  }

  static MeetingPointParticipant? fromMap(Map<String, dynamic> raw) {
    final userId = (raw['userId'] ?? '').toString().trim();
    if (userId.isEmpty) return null;
    final statusRaw = (raw['status'] ?? 'pending').toString().trim();
    var status = 'pending';
    switch (statusRaw) {
      case 'accepted':
        status = 'accepted';
        break;
      case 'declined':
        status = 'declined';
        break;
      case 'cancelled':
        status = 'cancelled';
        break;
      default:
        status = 'pending';
    }
    final arrivalStatusRaw = (raw['arrivalStatus'] ?? 'on_the_way')
        .toString()
        .trim();
    final arrivalStatus =
        const {'on_the_way', 'arrived', 'cancelled'}.contains(arrivalStatusRaw)
        ? arrivalStatusRaw
        : 'on_the_way';
    final estMins = raw['estimatedArrivalMinutes'];
    return MeetingPointParticipant(
      userId: userId,
      name: (raw['name'] ?? '').toString(),
      phone: (raw['phone'] ?? '').toString(),
      status: status,
      respondedAt: _meetingPointAsDateTime(raw['respondedAt']),
      updatedAt: _meetingPointAsDateTime(raw['updatedAt']),
      arrivalStatus: arrivalStatus,
      arrivedAt: _meetingPointAsDateTime(raw['arrivedAt']),
      estimatedArrivalMinutes: (estMins is num)
          ? estMins.toInt().clamp(1, 5)
          : 3,
      locationUpdatedAt: _meetingPointAsDateTime(raw['locationUpdatedAt']),
    );
  }
}

class MeetingPointRecord {
  const MeetingPointRecord({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.hostPhone,
    required this.venueId,
    required this.venueName,
    required this.placeCategories,
    required this.hostLocation,
    required this.hostStep,
    required this.status,
    required this.participants,
    required this.participantUserIds,
    this.createdAt,
    this.updatedAt,
    this.waitDeadline,
    this.suggestDeadline,
    this.confirmedAt,
    this.suggestedPoint = '',
    this.suggestedCandidates = const [],
    this.suggestionsComputed = false,
    this.hostArrivalStatus = 'on_the_way',
    this.hostArrivedAt,
    this.hostEstimatedMinutes = 3,
    this.hostLocationUpdatedAt,
    this.expiresAt,
  });

  final String id;
  final String hostId;
  final String hostName;
  final String hostPhone;
  final String venueId;
  final String venueName;
  final List<String> placeCategories;
  final Map<String, dynamic>? hostLocation;
  final int hostStep;
  final String status;
  final List<MeetingPointParticipant> participants;
  final List<String> participantUserIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? waitDeadline;
  final DateTime? suggestDeadline;

  // ── Arrival tracking (populated when status becomes 'active') ─────────────
  final DateTime? confirmedAt;
  final String suggestedPoint;
  final List<Map<String, dynamic>> suggestedCandidates;
  final bool suggestionsComputed;
  final String hostArrivalStatus; // on_the_way | arrived | cancelled
  final DateTime? hostArrivedAt;
  final int hostEstimatedMinutes; // 1-5 (random)
  final DateTime? hostLocationUpdatedAt;
  final DateTime? expiresAt;

  /// Derived from status: the meeting is in setup phase when status == 'pending'.
  bool get isActive => status.trim().toLowerCase() == 'pending';

  /// Meeting confirmed — everyone heading to venue.
  bool get isConfirmed => status.trim().toLowerCase() == 'active';

  /// Sub-state: host is waiting for invitees to respond.
  bool get isWaitingParticipants =>
      isActive && participants.any((p) => p.isPending);

  /// Sub-state: all invitees responded, host must confirm.
  bool get isWaitingHostConfirmation =>
      isActive && participants.every((p) => !p.isPending);

  bool isHost(String uid) => uid == hostId;

  MeetingPointParticipant? participantFor(String uid) {
    for (final p in participants) {
      if (p.userId == uid) return p;
    }
    return null;
  }

  int get invitedCount => participants.length;
  int get acceptedCount => participants.where((p) => p.isAccepted).length;
  int get pendingCount => participants.where((p) => p.isPending).length;
  int get declinedCount => participants
      .where((p) => p.isDeclined || p.isCancelledParticipation)
      .length;

  DateTime? get activeDeadline {
    if (hostStep == 4) return waitDeadline;
    if (hostStep == 5) return suggestDeadline;
    return null;
  }

  static MeetingPointRecord? fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final hostId = (data['hostId'] ?? '').toString().trim();
    if (hostId.isEmpty) return null;

    final participantsRaw = data['participants'];
    final participants = (participantsRaw is List)
        ? participantsRaw
              .whereType<Map>()
              .map(
                (e) => MeetingPointParticipant.fromMap(
                  Map<String, dynamic>.from(e),
                ),
              )
              .whereType<MeetingPointParticipant>()
              .toList()
        : <MeetingPointParticipant>[];

    // Support both old field name (memberUserIds) and new (participantUserIds).
    final membersRaw = data['participantUserIds'] ?? data['memberUserIds'];
    final members = (membersRaw is List)
        ? membersRaw
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final placeCategoriesRaw = data['placeCategories'];
    final placeCategories = (placeCategoriesRaw is List)
        ? placeCategoriesRaw
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final hostStepRaw = data['hostStep'];
    final hostStep = (hostStepRaw is num) ? hostStepRaw.toInt() : 4;

    final suggestedPoint = (data['suggestedPoint'] ?? '').toString();
    final suggestionsComputed = data['suggestionsComputed'] == true;
    final suggestedCandidatesRaw = data['suggestedCandidates'];
    final suggestedCandidates = (suggestedCandidatesRaw is List)
        ? suggestedCandidatesRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    return MeetingPointRecord(
      id: doc.id,
      hostId: hostId,
      hostName: (data['hostName'] ?? '').toString(),
      hostPhone: (data['hostPhone'] ?? '').toString(),
      venueId: (data['venueId'] ?? '').toString(),
      venueName: (data['venueName'] ?? '').toString(),
      placeCategories: placeCategories,
      hostLocation: data['hostLocation'] is Map
          ? Map<String, dynamic>.from(data['hostLocation'] as Map)
          : null,
      hostStep: hostStep.clamp(1, 5).toInt(),
      status: (data['status'] ?? '').toString(),
      participants: participants,
      participantUserIds: members,
      createdAt: _meetingPointAsDateTime(data['createdAt']),
      updatedAt: _meetingPointAsDateTime(data['updatedAt']),
      waitDeadline: _meetingPointAsDateTime(data['waitDeadline']),
      suggestDeadline: _meetingPointAsDateTime(data['suggestDeadline']),
      confirmedAt: _meetingPointAsDateTime(data['confirmedAt']),
      suggestedPoint: suggestedPoint,
      suggestedCandidates: suggestedCandidates,
      suggestionsComputed: suggestionsComputed,
      hostArrivalStatus: (data['hostArrivalStatus'] ?? 'on_the_way').toString(),
      hostArrivedAt: _meetingPointAsDateTime(data['hostArrivedAt']),
      hostEstimatedMinutes: (data['hostEstimatedMinutes'] is num)
          ? (data['hostEstimatedMinutes'] as num).toInt().clamp(1, 5)
          : 3,
      hostLocationUpdatedAt: _meetingPointAsDateTime(
        data['hostLocationUpdatedAt'],
      ),
      expiresAt: _meetingPointAsDateTime(data['expiresAt']),
    );
  }
}

class MeetingPointService {
  static const String collectionName = 'meetingPoints';

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collectionName);

  static const Duration _kSuggestDuration = Duration(minutes: 5);

  // ── Server-clock calibration ───────────────────────────────────────────────
  // Estimated offset: serverTime − localTime. Updated from every live
  // Firestore snapshot so all deadline maths use a consistent clock.
  static Duration _serverClockOffset = Duration.zero;

  /// Estimated current server time. Use this instead of [DateTime.now()]
  /// for every deadline computation and display so devices with skewed
  /// local clocks (e.g. emulators) still show consistent countdowns.
  static DateTime get serverNow => DateTime.now().add(_serverClockOffset);

  /// Call with the `updatedAt` server timestamp from any live Firestore
  /// snapshot to keep the estimated offset accurate.
  ///
  /// Only accepts timestamps that are close to the current local time.
  /// A large difference (> 5 min) means the snapshot came from an old/stale
  /// document, not from a live write — using such a timestamp would corrupt
  /// the offset and make every deadline appear to be in the past or future.
  static void calibrateFromServerTime(DateTime serverTimestamp) {
    final candidate = serverTimestamp.difference(DateTime.now());
    // Real server–client clock skew is typically < 30 s.  If the candidate
    // offset is larger than 30 seconds the timestamp is from an old document
    // (e.g. a meeting updated a few minutes ago), not a live write.
    if (candidate.abs() <= const Duration(seconds: 30)) {
      _serverClockOffset = candidate;
    }
  }

  static bool _isFullyDeclinedActive(MeetingPointRecord meeting) {
    if (!meeting.isActive) return false;
    if (meeting.participants.isEmpty) return false;
    return meeting.acceptedCount == 0 &&
        meeting.pendingCount == 0 &&
        meeting.declinedCount == meeting.invitedCount;
  }

  static bool _isMeetingBlockingForUser(
    MeetingPointRecord meeting,
    String uid,
  ) {
    // ── Arrival phase (status == 'active') ────────────────────────────────
    if (meeting.isConfirmed) {
      if (meeting.hostId == uid) {
        return meeting.hostArrivalStatus != 'cancelled';
      }
      final me = meeting.participantFor(uid);
      return me != null && me.isAccepted && me.arrivalStatus != 'cancelled';
    }

    // ── Setup phase (status == 'pending') ─────────────────────────────────
    if (!meeting.isActive) return false;
    if (_isFullyDeclinedActive(meeting)) return false;
    if (meeting.hostId == uid) return true;
    final me = meeting.participantFor(uid);
    if (me == null) return false;
    if (me.isDeclined) return false;
    // A pending invitee whose response window has closed should no longer
    // see the invitation on the track page. This covers two cases:
    // 1. The 2-min wait timer expired naturally.
    // 2. The host clicked Proceed early (hostStep jumped to 5 while
    //    waitDeadline was still in the future).
    if (me.isPending && meeting.hostStep >= 5) return false;
    if (me.isPending &&
        meeting.waitDeadline != null &&
        !meeting.waitDeadline!.isAfter(MeetingPointService.serverNow)) {
      return false;
    }
    return true;
  }

  static Stream<MeetingPointRecord?> watchActiveForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return Stream.value(null);

    return _col.where('participantUserIds', arrayContains: uid).snapshots().map(
      (snap) {
        final meetings = snap.docs
            .map(MeetingPointRecord.fromDoc)
            .whereType<MeetingPointRecord>()
            .toList();

        // Calibrate server clock only from ACTIVE/CONFIRMED meetings whose
        // timestamps are fresh. Old cancelled meetings have stale updatedAt
        // values that would corrupt _serverClockOffset.
        if (!snap.metadata.isFromCache) {
          final anchor = meetings
              .where((m) => m.isActive || m.isConfirmed)
              .map((m) => m.updatedAt ?? m.createdAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (best, t) => best == null || t.isAfter(best) ? t : best,
              );
          if (anchor != null) calibrateFromServerTime(anchor);
        }

        meetings.sort((a, b) {
          final at = a.updatedAt ?? a.createdAt ?? DateTime(1970);
          final bt = b.updatedAt ?? b.createdAt ?? DateTime(1970);
          return bt.compareTo(at);
        });

        final active = meetings
            .where((m) => _isMeetingBlockingForUser(m, uid))
            .toList();
        return active.isEmpty ? null : active.first;
      },
    );
  }

  /// Like [watchActiveForCurrentUser] but returns ALL blocking meetings for the
  /// current user, ordered newest-first. Used to show pending invitations as
  /// expandable tiles alongside the active (host/accepted) card.
  static Stream<List<MeetingPointRecord>> watchAllBlockingForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return Stream.value([]);

    return _col.where('participantUserIds', arrayContains: uid).snapshots().map((
      snap,
    ) {
      final meetings = snap.docs
          .map(MeetingPointRecord.fromDoc)
          .whereType<MeetingPointRecord>()
          .toList();

      // Same calibration as watchActiveForCurrentUser: only use fresh
      // ACTIVE/CONFIRMED meetings to avoid stale cancelled-meeting timestamps.
      if (!snap.metadata.isFromCache) {
        final anchor = meetings
            .where((m) => m.isActive || m.isConfirmed)
            .map((m) => m.updatedAt ?? m.createdAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (best, t) => best == null || t.isAfter(best) ? t : best,
            );
        if (anchor != null) calibrateFromServerTime(anchor);
      }

      meetings.sort((a, b) {
        final at = a.updatedAt ?? a.createdAt ?? DateTime(1970);
        final bt = b.updatedAt ?? b.createdAt ?? DateTime(1970);
        return bt.compareTo(at);
      });

      return meetings.where((m) => _isMeetingBlockingForUser(m, uid)).toList();
    });
  }

  /// Keep the meeting point flow consistent even when the host closes the form.
  ///
  /// This runs client-side (from Track page) and performs only safe transitions:
  /// - Step 4 expired: cancel if nobody accepted; otherwise move to step 5.
  /// - Step 5 expired: auto-accept (same as your current form behavior).
  /// - All declined: cancel (host or invitee can do this; rules allow it).
  static Future<void> maybeMaintain(MeetingPointRecord meeting) async {
    if (!meeting.isActive) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;

    final now = MeetingPointService.serverNow;

    // If everyone declined, end it (prevents ghost active meetings).
    final allDeclined =
        meeting.participants.isNotEmpty &&
        meeting.participants.every((p) => p.isDeclined);
    if (allDeclined) {
      try {
        await _col.doc(meeting.id).update({
          'status': 'cancelled',
          'cancellationReason': 'all_participants_declined',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await _markPendingNotificationsCancelled(meeting);
      } catch (_) {}
      return;
    }

    // Step 5: all previously-accepted participants cancelled their participation.
    // Nobody is left — cancel the meeting so the host isn't stuck at step 5.
    if (meeting.hostStep >= 5 &&
        meeting.participants.isNotEmpty &&
        !meeting.participants.any((p) => p.isAccepted)) {
      try {
        await _col.doc(meeting.id).update({
          'status': 'cancelled',
          'cancellationReason': 'all_participants_left',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      return;
    }

    // Early advance: all participants responded + at least one accepted.
    // No need to wait for the timer — advance to step 5 immediately.
    // Any signed-in user can trigger this write so it works even when the
    // host is offline (write will fail silently for non-host users due to
    // Firestore rules, but will succeed as soon as the host's device is live).
    if (meeting.hostStep == 4 &&
        meeting.participants.isNotEmpty &&
        meeting.pendingCount == 0 &&
        meeting.acceptedCount > 0) {
      try {
        await _col.doc(meeting.id).update({
          'hostStep': 5,
          'suggestDeadline': Timestamp.fromDate(now.add(_kSuggestDuration)),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      return;
    }

    // Timed transitions: any signed-in user can trigger them so the flow
    // continues even when the host has the app closed / logged out.
    if (meeting.hostStep == 4 && meeting.waitDeadline != null) {
      if (!meeting.waitDeadline!.isAfter(now)) {
        if (meeting.acceptedCount <= 0) {
          final anyCancelledParticipation = meeting.participants.any(
            (p) => p.isCancelledParticipation,
          );
          try {
            await _col.doc(meeting.id).update({
              'status': 'cancelled',
              'cancellationReason': anyCancelledParticipation
                  ? 'all_participants_left'
                  : 'all_participants_declined',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            await _markPendingNotificationsExpired(meeting);
          } catch (_) {}
        } else {
          try {
            await _col.doc(meeting.id).update({
              'hostStep': 5,
              // status stays 'pending'; sub-state derived from hostStep + participants
              'suggestDeadline': Timestamp.fromDate(now.add(_kSuggestDuration)),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }
      }
      return;
    }

    if (meeting.hostStep == 5 && meeting.suggestDeadline != null) {
      if (!meeting.suggestDeadline!.isAfter(now)) {
        try {
          await markHostDecision(meetingPointId: meeting.id, accepted: true);
        } catch (_) {}
      }
      return;
    }
  }

  static Future<void> _markPendingNotificationsCancelled(
    MeetingPointRecord meeting,
  ) async {
    final pendingIds = meeting.participants
        .where((p) => p.isPending)
        .map((p) => p.userId)
        .toSet();
    if (pendingIds.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (final uid in pendingIds) {
        final snap = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .where('type', isEqualTo: 'meetingPointRequest')
            .get();
        for (final doc in snap.docs) {
          final payload = doc.data()['data'] as Map<String, dynamic>? ?? {};
          final docRequestId =
              (payload['meetingPointId'] ?? payload['requestId'] ?? '')
                  .toString();
          if (docRequestId != meeting.id) continue;
          batch.update(doc.reference, {
            'requestStatus': 'cancelled',
            'requiresAction': false,
            'actionTaken': true,
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {}
  }

  static Future<void> _markPendingNotificationsExpired(
    MeetingPointRecord meeting,
  ) async {
    final pendingIds = meeting.participants
        .where((p) => p.isPending)
        .map((p) => p.userId)
        .toSet();
    if (pendingIds.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (final uid in pendingIds) {
        final snap = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .where('type', isEqualTo: 'meetingPointRequest')
            .get();
        for (final doc in snap.docs) {
          final payload = doc.data()['data'] as Map<String, dynamic>? ?? {};
          final docRequestId =
              (payload['meetingPointId'] ?? payload['requestId'] ?? '')
                  .toString();
          if (docRequestId != meeting.id) continue;
          batch.update(doc.reference, {
            'requestStatus': 'expired',
            'requiresAction': false,
            'actionTaken': true,
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {}
  }

  static Future<MeetingPointRecord?> getById(String meetingPointId) async {
    final id = meetingPointId.trim();
    if (id.isEmpty) return null;
    final doc = await _col.doc(id).get();
    return MeetingPointRecord.fromDoc(doc);
  }

  static Future<MeetingPointRecord?> getActiveHostedByCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return null;

    final snap = await _col.where('hostId', isEqualTo: uid).get();
    final items = snap.docs
        .map(MeetingPointRecord.fromDoc)
        .whereType<MeetingPointRecord>()
        .where((m) => m.isActive)
        .toList();
    if (items.isEmpty) return null;
    items.sort((a, b) {
      final at = a.updatedAt ?? a.createdAt ?? DateTime(1970);
      final bt = b.updatedAt ?? b.createdAt ?? DateTime(1970);
      return bt.compareTo(at);
    });
    for (final meeting in items) {
      if (_isFullyDeclinedActive(meeting)) {
        try {
          await _col.doc(meeting.id).update({
            'status': 'cancelled',
            'cancellationReason': 'all_participants_declined',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
        continue;
      }
      return meeting;
    }
    return null;
  }

  static Future<MeetingPointRecord?> getBlockingMeetingForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return null;

    final snap = await _col
        .where('participantUserIds', arrayContains: uid)
        .get();
    final meetings = snap.docs
        .map(MeetingPointRecord.fromDoc)
        .whereType<MeetingPointRecord>()
        .toList();
    if (meetings.isEmpty) return null;

    meetings.sort((a, b) {
      final at = a.updatedAt ?? a.createdAt ?? DateTime(1970);
      final bt = b.updatedAt ?? b.createdAt ?? DateTime(1970);
      return bt.compareTo(at);
    });

    for (final meeting in meetings) {
      if (_isFullyDeclinedActive(meeting) && meeting.hostId == uid) {
        try {
          await _col.doc(meeting.id).update({
            'status': 'cancelled',
            'cancellationReason': 'all_participants_declined',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
        continue;
      }
      if (_isMeetingBlockingForUser(meeting, uid)) return meeting;
    }
    return null;
  }

  static Future<(String, DateTime)> createMeetingPoint({
    required String hostId,
    required String hostName,
    required String hostPhone,
    required String venueId,
    required String venueName,
    required List<String> placeCategories,
    required Map<String, dynamic>? hostLocation,
    required List<MeetingPointParticipant> participants,
    required Duration waitDuration,
  }) async {
    final docRef = _col.doc();
    final invitedUserIds = participants.map((p) => p.userId).toSet().toList();
    final participantUserIds = <String>{hostId, ...invitedUserIds}.toList();

    final batch = FirebaseFirestore.instance.batch();
    batch.set(docRef, {
      'hostId': hostId,
      'hostName': hostName,
      'hostPhone': hostPhone,
      'venueId': venueId,
      'venueName': venueName,
      'placeCategories': placeCategories,
      'hostLocation': hostLocation,
      'hostStep': 4,
      'status': 'pending',
      'participants': participants.map((p) => p.toMap()).toList(),
      'invitedUserIds': invitedUserIds,
      'participantUserIds': participantUserIds,
      // waitDeadline is NOT set here — it is computed from the confirmed
      // server-side createdAt after the commit so that all devices (host and
      // participants) share the exact same Firestore-server-time-based deadline
      // regardless of their local clock.
      'waitDurationSeconds': waitDuration.inSeconds,
      'waitDeadline': null,
      'suggestDeadline': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Read back the confirmed server timestamp for createdAt, then write the
    // final waitDeadline = createdAt + waitDuration.  This ensures every
    // client sees a deadline anchored to Firestore server time.
    final snap = await docRef.get();
    final serverCreatedAt = (snap.data()?['createdAt'] as Timestamp?)?.toDate();
    if (serverCreatedAt != null) {
      final deadline = serverCreatedAt.add(waitDuration);
      await docRef.update({
        'waitDeadline': Timestamp.fromDate(deadline),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return (docRef.id, deadline);
    }

    // Fallback: server timestamp not yet available in cache, use local time.
    final fallback = DateTime.now().add(waitDuration);
    await docRef.update({
      'waitDeadline': Timestamp.fromDate(fallback),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return (docRef.id, fallback);
  }

  static Future<void> updateHostProgress({
    required String meetingPointId,
    required int hostStep,
    List<MeetingPointParticipant>? participants,
    DateTime? waitDeadline,
    DateTime? suggestDeadline,
    String? status,
  }) async {
    final payload = <String, dynamic>{
      'hostStep': hostStep.clamp(1, 5),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (participants != null) {
      payload['participants'] = participants.map((p) => p.toMap()).toList();
    }
    if (waitDeadline != null) {
      payload['waitDeadline'] = Timestamp.fromDate(waitDeadline);
    }
    if (suggestDeadline != null) {
      payload['suggestDeadline'] = Timestamp.fromDate(suggestDeadline);
    }
    if (status != null) payload['status'] = status;

    await _col.doc(meetingPointId).update(payload);
  }

  static Future<void> markHostDecision({
    required String meetingPointId,
    required bool accepted,
  }) async {
    if (!accepted) {
      await _col.doc(meetingPointId).update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
        'hostStep': 5,
        'cancellationReason': 'host_rejected_suggestion',
      });
      return;
    }

    // Fetch current meeting to initialize per-participant arrival data.
    final doc = await _col.doc(meetingPointId).get();
    final meeting = MeetingPointRecord.fromDoc(doc);
    if (meeting == null) return;

    final rng = math.Random();
    final hostMins = rng.nextInt(5) + 1;
    final now = DateTime.now();

    // Initialize arrivalStatus + random estimatedArrivalMinutes for all
    // participants who accepted the invitation.
    final updatedParticipants = meeting.participants.map((p) {
      if (!p.isAccepted) return p;
      return p.copyWith(
        arrivalStatus: 'on_the_way',
        estimatedArrivalMinutes: rng.nextInt(5) + 1,
        locationUpdatedAt: now,
      );
    }).toList();

    // Write an initial expiresAt using the random estimatedArrivalMinutes as a
    // guaranteed safety baseline — this ensures auto-expiry always works even if
    // the host device never completes navmesh path calculation.
    // The host device will overwrite this with a more accurate real-path-based
    // value once _maybeWriteExpiresAtFromRealEtas() runs.
    final acceptedETAs = updatedParticipants
        .where((p) => p.isAccepted)
        .map((p) => p.estimatedArrivalMinutes);
    final allETAs = [hostMins, ...acceptedETAs];
    final largestMins = allETAs.reduce(math.max);
    final rawSession = Duration(minutes: largestMins * 3);
    const kMinSession = Duration(minutes: 10);
    final sessionDuration = rawSession < kMinSession ? kMinSession : rawSession;
    final expiresAt = now.add(sessionDuration);

    await _col.doc(meetingPointId).update({
      'status': 'active',
      'hostStep': 5,
      'updatedAt': FieldValue.serverTimestamp(),
      'confirmedAt': FieldValue.serverTimestamp(),
      'hostArrivalStatus': 'on_the_way',
      'hostEstimatedMinutes': hostMins,
      'hostArrivedAt': null,
      'hostLocationUpdatedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'participants': updatedParticipants.map((p) => p.toMap()).toList(),
    });
  }

  /// Writes the session expiry timestamp once real path ETAs are available.
  /// Called from the host device after navmesh path calculation completes.
  static Future<void> updateExpiresAt(
    String meetingId,
    DateTime expiresAt,
  ) async {
    await _col.doc(meetingId).update({
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reconciles a confirmed (arrival-phase) meeting that may be stuck due to
  /// old app code that didn't write meeting-level status transitions.
  /// Safe to call repeatedly — only writes to Firestore when a change is needed.
  static Future<void> reconcileArrivalPhase(MeetingPointRecord meeting) async {
    if (!meeting.isConfirmed) return;

    // Session time limit: auto-terminate if expiresAt has passed.
    // Uses 'terminated' (not 'cancelled') so history shows this as a system
    // action, never as "You cancelled this request".
    if (meeting.expiresAt != null &&
        !meeting.expiresAt!.isAfter(MeetingPointService.serverNow)) {
      try {
        await _col.doc(meeting.id).update({
          'status': 'terminated',
          'cancellationReason': 'Auto-closed after time limit',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      return;
    }

    final hostActive = meeting.hostArrivalStatus != 'cancelled';
    final activeParticipants = meeting.participants
        .where((p) => p.isAccepted && !p.isCancelledArrival)
        .toList();
    final totalActive = (hostActive ? 1 : 0) + activeParticipants.length;

    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    bool needsUpdate = false;

    if (totalActive < 2) {
      payload['status'] = 'cancelled';
      payload['cancellationReason'] = 'all_participants_left';
      needsUpdate = true;
    } else {
      final hostDone = !hostActive || meeting.hostArrivalStatus == 'arrived';
      final allActiveArrived =
          hostDone && activeParticipants.every((p) => p.isArrived);
      if (allActiveArrived) {
        payload['status'] = 'completed';
        needsUpdate = true;
      }
    }

    if (!needsUpdate) return;
    try {
      await _col.doc(meeting.id).update(payload);
    } catch (_) {}
  }

  /// Cancel the entire meeting for all participants (host only action).
  static Future<void> cancelMeetingForAll(String meetingPointId) async {
    MeetingPointRecord? meeting;
    try {
      final doc = await _col.doc(meetingPointId).get();
      meeting = MeetingPointRecord.fromDoc(doc);
    } catch (_) {}

    final payload = <String, dynamic>{
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
      'cancellationReason': 'host_cancelled',
    };

    await _col.doc(meetingPointId).update(payload);

    if (meeting != null) {
      try {
        await _markPendingNotificationsCancelled(meeting);
      } catch (_) {}
    }
  }

  /// Update a participant's (or host's) arrival status during the confirmed phase.
  /// Also auto-transitions the meeting to 'completed' when all active participants
  /// have arrived, or to 'cancelled' (with reason 'all_participants_left') when
  /// fewer than two active participants remain.
  static Future<void> updateArrivalStatus({
    required String meetingPointId,
    required bool isHost,
    required String userId,
    required String arrivalStatus, // 'on_the_way' | 'arrived' | 'cancelled'
    DateTime? arrivedAt,
  }) async {
    // Always read the full document so we can evaluate meeting-level transitions.
    final doc = await _col.doc(meetingPointId).get();
    final meeting = MeetingPointRecord.fromDoc(doc);
    if (meeting == null) return;

    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // ── Compute new arrival states ─────────────────────────────────────────
    String newHostArrivalStatus = meeting.hostArrivalStatus;
    List<MeetingPointParticipant> newParticipants =
        List<MeetingPointParticipant>.from(meeting.participants);

    if (isHost) {
      newHostArrivalStatus = arrivalStatus;
      payload['hostArrivalStatus'] = arrivalStatus;
      payload['hostArrivedAt'] = arrivedAt == null
          ? null
          : Timestamp.fromDate(arrivedAt);
    } else {
      final idx = newParticipants.indexWhere((p) => p.userId == userId);
      if (idx < 0) return;
      newParticipants[idx] = newParticipants[idx].copyWith(
        arrivalStatus: arrivalStatus,
        arrivedAt: arrivedAt,
      );
      payload['participants'] = newParticipants.map((p) => p.toMap()).toList();
    }

    // ── Meeting-level status transitions (only during arrival phase) ──────
    if (meeting.isConfirmed) {
      // "Active" = host or accepted participant who hasn't cancelled their arrival.
      final hostActive = newHostArrivalStatus != 'cancelled';
      final activeParticipants = newParticipants
          .where((p) => p.isAccepted && !p.isCancelledArrival)
          .toList();
      final totalActive = (hostActive ? 1 : 0) + activeParticipants.length;

      if (totalActive < 2) {
        // Not enough people left — auto-cancel the meeting.
        payload['status'] = 'cancelled';
        payload['cancellationReason'] = 'all_participants_left';
      } else {
        // Complete when every *active* person has arrived.
        // If the host cancelled ("cancel for me") they are not active,
        // so we don't require them to arrive.
        final hostDone = !hostActive || newHostArrivalStatus == 'arrived';
        final allActiveArrived =
            hostDone && activeParticipants.every((p) => p.isArrived);
        if (allActiveArrived) {
          payload['status'] = 'completed';
        }
      }
    }

    await _col.doc(meetingPointId).update(payload);
  }

  static Future<void> respondToInvitation({
    required String meetingPointId,
    required bool accepted,
    bool cancelParticipation = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;

    final ref = _col.doc(meetingPointId);
    final doc = await ref.get();
    final meeting = MeetingPointRecord.fromDoc(doc);
    if (meeting == null) return;

    final index = meeting.participants.indexWhere((p) => p.userId == uid);
    if (index < 0) return;

    final now = DateTime.now();
    final treatCancelAsDeclined =
        cancelParticipation && meeting.hostStep >= 5 && !meeting.isConfirmed;
    final newStatus = accepted
        ? 'accepted'
        : (treatCancelAsDeclined
              ? 'declined'
              : (cancelParticipation ? 'cancelled' : 'declined'));
    final updatedParticipants = List<MeetingPointParticipant>.from(
      meeting.participants,
    );
    updatedParticipants[index] = updatedParticipants[index].copyWith(
      status: newStatus,
      respondedAt: now,
      updatedAt: now,
    );

    final payload = <String, dynamic>{
      'participants': updatedParticipants.map((p) => p.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final noPendingLeft = updatedParticipants.every((p) => !p.isPending);
    final anyAccepted = updatedParticipants.any((p) => p.isAccepted);
    final anyCancelledParticipation = updatedParticipants.any(
      (p) => p.isCancelledParticipation,
    );

    // Cancel immediately when no invitee is still deciding and nobody accepted.
    // Covers: all declined, all cancelled participation, or a mix of both.
    // At step 4: only fires once every invitee has given their answer.
    // At step 5: invitees should have all responded already (no pending left).
    if (noPendingLeft && !anyAccepted) {
      payload['status'] = 'cancelled';
      payload['cancellationReason'] = anyCancelledParticipation
          ? 'all_participants_left'
          : 'all_participants_declined';
    }

    // Edge case at step 5: some invitees may still be 'pending' (invitation
    // expired mid-flow) yet no accepted participants remain — cancel now.
    if (!payload.containsKey('status') &&
        cancelParticipation &&
        meeting.hostStep >= 5 &&
        !anyAccepted) {
      payload['status'] = 'cancelled';
      payload['cancellationReason'] = meeting.isConfirmed
          ? 'all_participants_left'
          : 'all_participants_declined';
    }

    // Auto-advance to step 5 when every invitee has responded and at least
    // one accepted — host no longer needs to manually tap "Proceed", and the
    // transition works even if the host is offline.
    if (!payload.containsKey('status') &&
        noPendingLeft &&
        anyAccepted &&
        meeting.hostStep == 4) {
      payload['hostStep'] = 5;
      payload['suggestDeadline'] = Timestamp.fromDate(
        MeetingPointService.serverNow.add(_kSuggestDuration),
      );
    }

    try {
      await ref.update(payload);
    } catch (_) {
      await ref.update({
        'participants': updatedParticipants.map((p) => p.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}

DateTime? _meetingPointAsDateTime(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

// ── Entry point ───────────────────────────────────────────────────────────────

class CreateMeetingPointForm extends StatefulWidget {
  const CreateMeetingPointForm({
    super.key,
    this.resumeDraft = false,
    this.meetingPointId,
    this.autoAdvanceToStep5 = false,
  });

  final bool resumeDraft;
  final String? meetingPointId;

  /// When true and the restored meeting is at step 4, automatically advance
  /// to step 5 (skipping the manual Proceed tap inside the form).
  final bool autoAdvanceToStep5;

  @override
  State<CreateMeetingPointForm> createState() => _CreateMeetingPointFormState();
}

class _CreateMeetingPointFormState extends State<CreateMeetingPointForm> {
  // ── Wizard state ─────────────────────────────────────────────────────────
  int _step = 1; // 1-5

  // ── Step 1: Venue ─────────────────────────────────────────────────────────
  bool _loadingVenue = true;
  String? _venueId;
  String? _venueName;
  String? _venueError;

  // ── Step 1: Friends ───────────────────────────────────────────────────────
  final TextEditingController _phoneCtrl = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
  bool _isPhoneFocused = false;
  bool _isAddingPhone = false;
  bool _phoneValid = true;
  String? _phoneError;

  final List<_Friend> _selectedFriends = [];

  /// Active tracked friends inside the same venue.
  List<_Friend> _activeVenueFriends = [];
  bool _loadingActiveVenueFriends = false;

  // ── Step 1: Place Type ───────────────────────────────────────────────────
  final List<String> _allPlaceCategories = [
    'Any',
    'Café',
    'Restaurant',
    'Shop',
    'Gates',
  ];
  final Set<String> _selectedPlaceCategories = {'Any'};

  // ── Step 2: Location ──────────────────────────────────────────────────────
  _HostLocation? _hostLocation;
  String? _mapVenueIdForLocation;
  Map<String, double>? _step2InitialUserPinGltf;
  String? _step2InitialFloorLabel;
  int _step2MapVersion = 0;

  // ── Step 4: Participants ──────────────────────────────────────────────────
  /// Simulated participant list built from _selectedFriends at step 4 entry.
  List<_Participant> _participants = [];

  /// Step-4 2-minute countdown.
  Timer? _waitTimer;
  int _waitSecondsLeft = 120; // 2 min
  DateTime?
  _pendingWaitDeadline; // deadline computed once before the Firestore commit

  /// Proceed button unlock delay (5 s) before checking real acceptance.
  bool _proceedUnlocked = false;
  Timer? _proceedTimer;
  DateTime? _proceedUnlockAt;
  DateTime? _waitDeadline;

  /// Delay before auto-advancing to step 5 so the host can see accepted state.
  static const Duration _kAutoAdvanceDelay = Duration(seconds: 2);
  Timer? _autoAdvanceTimer;

  // ── Step 5: Suggested meeting point ──────────────────────────────────────
  /// 5-minute timer for host to accept/reject.
  Timer? _suggestTimer;
  int _suggestSecondsLeft = 300; // 5 min
  DateTime? _suggestDeadline;
  String _suggestedPointName = '';
  List<Map<String, dynamic>> _suggestedCandidates = [];
  bool _suggestionsComputed = false;
  Map<String, int> _step5DistMap = {};
  bool _step5DistComputing = false;

  /// Persists across widget rebuilds for the lifetime of the app process.
  static final Map<String, Map<String, int>> _distCache = {};

  // ── Cached current user ───────────────────────────────────────────────────
  String? _myPhone;
  String? _myName;
  bool _shouldManageDraft = false;
  bool _allowDisposeDraftSave = true;
  bool _closeHandled = false;
  bool _isInitializing = false;
  bool _isSendingInvites = false;
  String? _meetingPointId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meetingPointSub;

  // ─── In-session state persistence (steps 1–3) ────────────────────────────
  static bool _hasSavedEarlyState = false;
  static String? _memEarlyUserId;
  static List<_Friend> _memEarlyFriends = [];
  static Set<String> _memEarlyCategories = {'Any'};
  static _HostLocation? _memEarlyHostLocation;
  static String? _memEarlyVenueId;
  static int _memEarlyStep = 1;

  void _saveEarlyStepsToMemory() {
    if (_step >= 4) return;
    _hasSavedEarlyState = true;
    _memEarlyUserId = FirebaseAuth.instance.currentUser?.uid;
    _memEarlyFriends = List.from(_selectedFriends);
    _memEarlyCategories = Set.from(_selectedPlaceCategories);
    _memEarlyHostLocation = _hostLocation;
    _memEarlyVenueId = _venueId;
    _memEarlyStep = _step;
  }

  /// Called after venue detection completes. Restores friends/categories always;
  /// restores location and step only if the detected venue matches the saved one.
  void _tryRestoreEarlyState() {
    if (!_hasSavedEarlyState || _shouldManageDraft || _step >= 4) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != _memEarlyUserId) {
      _clearEarlyMemory();
      return;
    }
    if (_memEarlyFriends.isNotEmpty) {
      _selectedFriends
        ..clear()
        ..addAll(_memEarlyFriends);
    }
    if (_memEarlyCategories.isNotEmpty) {
      _selectedPlaceCategories
        ..clear()
        ..addAll(_memEarlyCategories);
    }
    // Only restore location and step if user is still in same venue
    if (_venueId != null && _venueId == _memEarlyVenueId) {
      if (_memEarlyHostLocation != null) _hostLocation = _memEarlyHostLocation;
      if (_memEarlyStep > 1) _step = _memEarlyStep;
    }
  }

  static void _clearEarlyMemory() {
    _hasSavedEarlyState = false;
    _memEarlyUserId = null;
    _memEarlyFriends = [];
    _memEarlyCategories = {'Any'};
    _memEarlyHostLocation = null;
    _memEarlyVenueId = null;
    _memEarlyStep = 1;
  }
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Suppress the background popup while this form is open.
    MeetingPointPopupGuard.suppress = true;
    _phoneFocus.addListener(() {
      setState(() => _isPhoneFocused = _phoneFocus.hasFocus);
    });
    _prepareStep2MapVenueId();
    _loadSavedStep2Location();
    _loadCurrentUser();
    _loadAndResolveVenue();
    _meetingPointId = widget.meetingPointId?.trim();
    if (_meetingPointId != null && _meetingPointId!.isNotEmpty) {
      _isInitializing = true;
      _shouldManageDraft = true;
      _restoreFromMeetingPoint(_meetingPointId!)
          .then((_) {
            if (mounted && widget.autoAdvanceToStep5 && _step == 4) {
              _goNext(); // cancels step-4 timers, inits step-5, sets _step = 5
            }
          })
          .whenComplete(() {
            if (mounted) setState(() => _isInitializing = false);
          });
    } else if (widget.resumeDraft) {
      _isInitializing = true;
      _shouldManageDraft = true;
      _restoreMeetingProgress().whenComplete(() {
        if (mounted) setState(() => _isInitializing = false);
      });
    }
  }

  @override
  void dispose() {
    // Restore popup guard when the form closes.
    MeetingPointPopupGuard.suppress = false;
    _saveEarlyStepsToMemory();
    if (_allowDisposeDraftSave && _shouldManageDraft) {
      unawaited(_persistDraftIfNeeded());
    }
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    _waitTimer?.cancel();
    _proceedTimer?.cancel();
    _suggestTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _meetingPointSub?.cancel();
    super.dispose();
  }

  // ─── Venue detection ──────────────────────────────────────────────────────

  Future<void> _loadAndResolveVenue() async {
    setState(() {
      _loadingVenue = true;
      _venueError = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('venues')
          .orderBy('venueName')
          .get();

      final venues = snap.docs
          .map((d) {
            final data = d.data();
            return _VenueOption(
              id: d.id,
              name: (data['venueName'] ?? '').toString(),
              lat: (data['latitude'] as num?)?.toDouble(),
              lng: (data['longitude'] as num?)?.toDouble(),
            );
          })
          .where((v) => v.name.isNotEmpty)
          .toList();

      final pos = await _getPositionOrNull();
      final matched = pos == null ? null : _matchVenue(venues, pos);

      if (matched != null) {
        // User is inside a real venue.
        _venueId = matched.id;
        _venueName = matched.name;
      } else if (forceVenueForTesting && venues.isNotEmpty) {
        // DEV override: prefer a stable 24h test venue.
        _VenueOption? testVenue;
        if (_kTestVenueId.trim().isNotEmpty) {
          for (final v in venues) {
            if (v.id == _kTestVenueId) {
              testVenue = v;
              break;
            }
          }
        }
        if (testVenue == null) {
          final expected = _kTestVenueName.toLowerCase();
          for (final v in venues) {
            final name = v.name.toLowerCase();
            if (name == expected || name.contains(expected)) {
              testVenue = v;
              break;
            }
          }
        }
        testVenue ??= venues.first;
        _venueId = testVenue.id;
        _venueName = testVenue.name; // no "(DEV)" label shown to user
      } else {
        _venueError =
            'You must be inside a supported venue to create a meeting point.';
      }

      if (!mounted) return;
      setState(() {
        _loadingVenue = false;
        _tryRestoreEarlyState();
      });
      _prepareStep2MapVenueId();

      // Load active venue friends after venue is known.
      if (_venueId != null) _loadActiveVenueFriends();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingVenue = false;
        _venueError = 'Could not detect venue. Please try again.';
        _tryRestoreEarlyState();
      });
      _prepareStep2MapVenueId();
    }
  }

  Future<Position?> _getPositionOrNull() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever)
        return null;
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  _VenueOption? _matchVenue(List<_VenueOption> venues, Position pos) {
    _VenueOption? best;
    var bestDist = double.infinity;
    for (final v in venues) {
      if (v.lat == null || v.lng == null) continue;
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        v.lat!,
        v.lng!,
      );
      if (d <= _kVenueGeofenceMeters && d < bestDist) {
        best = v;
        bestDist = d;
      }
    }
    return best;
  }

  bool get _isVenueValid => _venueId != null;

  // ─── Current user ─────────────────────────────────────────────────────────

  Future<void> _loadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        _myPhone = (data['phone'] ?? '').toString();
        _myName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
      }
    } catch (_) {}
  }

  // ─── Active venue friends ─────────────────────────────────────────────────

  Future<void> _loadActiveVenueFriends() async {
    if (_venueId == null) return;
    setState(() => _loadingActiveVenueFriends = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Fetch accepted track requests that are currently active for this venue
      // where I am the sender (I am tracking them).
      final sentSnap = await FirebaseFirestore.instance
          .collection('trackRequests')
          .where('senderId', isEqualTo: user.uid)
          .where('venueId', isEqualTo: _venueId)
          .where('status', isEqualTo: 'accepted')
          .limit(40)
          .get();

      final now = DateTime.now();
      final byPhone = <String, _Friend>{};

      for (final doc in sentSnap.docs) {
        final d = doc.data();
        final start = (d['startAt'] as Timestamp?)?.toDate();
        final end = (d['endAt'] as Timestamp?)?.toDate();
        if (start == null || end == null) continue;
        if (now.isBefore(start) || now.isAfter(end)) continue;
        final phone = d['receiverPhone']?.toString() ?? '';
        final receiverId = (d['receiverId'] ?? '').toString().trim();
        if (phone.isEmpty) continue;
        final name = (d['receiverName']?.toString().trim().isNotEmpty == true)
            ? d['receiverName'].toString().trim()
            : phone;
        byPhone.putIfAbsent(
          phone,
          () => _Friend(
            id: receiverId,
            name: name,
            phone: phone,
            isFavorite: false,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _activeVenueFriends = byPhone.values.toList();
        _loadingActiveVenueFriends = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingActiveVenueFriends = false);
    }
  }

  List<_Friend> get _remainingActiveVenueFriends => _activeVenueFriends
      .where((f) => !_selectedFriends.any((s) => s.phone == f.phone))
      .toList();

  // ─── Friend management ────────────────────────────────────────────────────

  void _addFriend(_Friend friend) {
    if (_selectedFriends.any((f) => f.phone == friend.phone)) return;
    setState(() {
      _selectedFriends.add(friend);
    });
  }

  void _removeFriend(_Friend friend) {
    setState(() {
      _selectedFriends.removeWhere((f) => f.phone == friend.phone);
    });
  }

  bool get _canAddPhone {
    final phone = _phoneCtrl.text.trim();
    return phone.length == 9 && RegExp(r'^\d{9}$').hasMatch(phone);
  }

  Future<void> _addFriendByPhone() async {
    if (_isAddingPhone) return;

    if (!_canAddPhone) {
      setState(() {
        _phoneValid = false;
        _phoneError = 'Enter 9 digits';
      });
      return;
    }

    final raw = _phoneCtrl.text.trim();
    final phone = '+966$raw';

    if (_selectedFriends.any((f) => f.phone == phone)) {
      setState(() {
        _phoneValid = false;
        _phoneError = 'Friend already added';
      });
      return;
    }

    if (_myPhone != null && _myPhone == phone) {
      setState(() {
        _phoneValid = false;
        _phoneError = "You can't add yourself";
      });
      return;
    }

    setState(() => _isAddingPhone = true);

    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (!mounted) return;

      if (q.docs.isEmpty) {
        _phoneFocus.unfocus();
        setState(() {
          _isAddingPhone = false;
          _phoneCtrl.clear();
          _phoneValid = true;
          _phoneError = null;
        });
        _showInviteToMadarDialog(phone);
        return;
      }

      final data = q.docs.first.data();
      final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
          .trim();

      setState(() {
        _isAddingPhone = false;
        _phoneValid = true;
        _phoneError = null;
        _selectedFriends.add(
          _Friend(
            id: q.docs.first.id,
            name: name.isEmpty ? phone : name,
            phone: phone,
            isFavorite: false,
          ),
        );
        _phoneCtrl.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAddingPhone = false;
        _phoneValid = false;
        _phoneError = 'Could not verify. Try again.';
      });
    }
  }

  static const String _inviteMessage =
      "Hey! I'm using Madar for location sharing.\n"
      "Join me using this invite link:\n"
      "https://madar.app/invite";

  void _showInviteToMadarDialog(String phone) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogPadding = screenWidth < 360 ? 20.0 : 28.0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: EdgeInsets.all(dialogPadding),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.kGreen.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_add_rounded,
                          size: 42,
                          color: AppColors.kGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Invite to Madar?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.kGreen,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "This person isn't on Madar yet.\nInvite them to start sharing location.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _shareInvite(phone);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Send Invite',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: Icon(Icons.close, size: 22, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareInvite(String _phone) async {
    try {
      await Share.share(_inviteMessage, subject: 'Invite to Madar');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open share. Link copied instead.'),
            backgroundColor: AppColors.kGreen,
          ),
        );
        Clipboard.setData(const ClipboardData(text: _inviteMessage));
      }
    }
  }

  static String _normalizePhone(String raw) {
    var phone = raw.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
    if (phone.startsWith('+966')) phone = phone.substring(4);
    if (phone.startsWith('966')) phone = phone.substring(3);
    if (phone.startsWith('05') && phone.length >= 9) phone = phone.substring(2);
    phone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.length >= 9) phone = phone.substring(phone.length - 9);
    return phone.length == 9 ? '+966$phone' : '';
  }

  Future<void> _pickContact() async {
    _phoneFocus.unfocus();

    try {
      final allowed = await FlutterContacts.requestPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacts permission is required.')),
        );
        return;
      }

      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final items = <_ContactItem>[];
      final seen = <String>{};

      for (final c in contacts) {
        if (c.phones.isEmpty) continue;
        final name = c.displayName.trim().isEmpty ? 'Unknown' : c.displayName;
        for (final p in c.phones) {
          final normalized = _normalizePhone(p.number);
          if (normalized.isEmpty || !seen.add(normalized)) continue;
          items.add(_ContactItem(name: name, phone: normalized));
        }
      }

      items.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid contacts found.')),
        );
        return;
      }

      final selectedPhone = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => SelectContactPage(
            contacts: items,
            inDbStatus: const <String, bool>{},
            onInvite: _shareInvite,
          ),
        ),
      );

      if (!mounted || selectedPhone == null) return;
      final local = selectedPhone.startsWith('+966')
          ? selectedPhone.substring(4)
          : selectedPhone;

      setState(() {
        _phoneCtrl.text = local;
        _phoneCtrl.selection = TextSelection.collapsed(offset: local.length);
        _phoneValid = true;
        _phoneError = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load contacts. Try again.')),
      );
    }
  }

  Future<void> _showFavoritesList() async {
    final selected = await showModalBottomSheet<List<_Friend>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FavoriteListSheet(
        alreadySelectedPhones: _selectedFriends.map((f) => f.phone).toSet(),
      ),
    );
    if (selected == null || selected.isEmpty) return;
    for (final f in selected) {
      _addFriend(f);
    }
  }

  bool get _isResumableDraftStep => _step == 4 || _step == 5;

  Future<void> _handleExitRequested() async {
    await _persistDraftIfNeeded();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _restoreMeetingProgress() async {
    final restoredLocal = await _restoreDraftIfAvailable();
    if (restoredLocal) return;

    final activeHostMeeting =
        await MeetingPointService.getActiveHostedByCurrentUser();
    if (!mounted || activeHostMeeting == null) return;
    await _restoreFromMeetingPoint(activeHostMeeting.id);
  }

  Future<bool> _restoreDraftIfAvailable() async {
    final snap = await MeetingPointDraftStorage.loadForCurrentUser();
    if (snap == null || !mounted) return false;
    if (snap.step < 4 || snap.step > 5) return false;

    final restoredFriends = snap.selectedFriends
        .map(_friendFromDraft)
        .whereType<_Friend>()
        .toList();
    final restoredParticipants = snap.participants
        .map(_participantFromDraft)
        .whereType<_Participant>()
        .toList();

    final restoredPlaceCategories = snap.placeCategories.toSet();
    if (restoredPlaceCategories.isEmpty) restoredPlaceCategories.add('Any');

    final host = _hostLocationFromDraft(snap.hostLocationRaw);
    final restoredWaitLeft = _intFromDynamic(snap.data['waitSecondsLeft'], 600);
    final restoredSuggestLeft = _intFromDynamic(
      snap.data['suggestSecondsLeft'],
      300,
    );
    final restoredMeetingPointId = (snap.data['meetingPointId'] ?? '')
        .toString()
        .trim();

    setState(() {
      _meetingPointId = restoredMeetingPointId.isEmpty
          ? _meetingPointId
          : restoredMeetingPointId;
      _step = snap.step;
      _venueId = snap.venueId;
      _venueName = snap.venueName ?? _venueName;

      _selectedFriends
        ..clear()
        ..addAll(restoredFriends);
      _selectedPlaceCategories
        ..clear()
        ..addAll(restoredPlaceCategories);

      if (host != null) {
        _hostLocation = host;
      }

      _participants = restoredParticipants.isEmpty
          ? restoredFriends
                .map(
                  (f) => _Participant(
                    friend: f,
                    status: _ParticipantStatus.pending,
                  ),
                )
                .toList()
          : restoredParticipants;

      _waitSecondsLeft = restoredWaitLeft.clamp(0, 120).toInt();
      _suggestSecondsLeft = restoredSuggestLeft.clamp(0, 300).toInt();
      _proceedUnlocked = _boolFromDynamic(snap.data['proceedUnlocked'], true);
      _waitDeadline = _dateFromEpoch(snap.data['waitDeadlineMs']);
      _suggestDeadline = _dateFromEpoch(snap.data['suggestDeadlineMs']);
      _proceedUnlockAt = _dateFromEpoch(snap.data['proceedUnlockAtMs']);
    });

    if (_step == 4) {
      _startProceedUnlockTimer();
      _startStep4WaitCountdown();
    } else if (_step == 5) {
      _startStep5SuggestCountdown();
    }
    if (_meetingPointId != null && _meetingPointId!.isNotEmpty) {
      _startMeetingSubscription(_meetingPointId!);
    }
    return true;
  }

  Future<void> _restoreFromMeetingPoint(String meetingPointId) async {
    final meeting = await MeetingPointService.getById(meetingPointId);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (!mounted || meeting == null || myUid == null) return;
    if (!meeting.isHost(myUid)) return;

    _meetingPointId = meeting.id;
    _shouldManageDraft = true;

    final restoredFriends = meeting.participants
        .map(
          (p) => _Friend(
            id: p.userId,
            name: p.name.trim().isEmpty ? p.phone : p.name,
            phone: p.phone,
            isFavorite: false,
          ),
        )
        .toList();

    final restoredParticipants = meeting.participants
        .map(_participantFromCloud)
        .toList();

    final waitLeft = meeting.waitDeadline == null
        ? _waitSecondsLeft
        : meeting.waitDeadline!
              .difference(MeetingPointService.serverNow)
              .inSeconds
              .clamp(0, 600);
    final suggestLeft = meeting.suggestDeadline == null
        ? _suggestSecondsLeft
        : meeting.suggestDeadline!
              .difference(MeetingPointService.serverNow)
              .inSeconds
              .clamp(0, 300);

    setState(() {
      _step = meeting.hostStep.clamp(1, 5).toInt();
      _venueId = meeting.venueId.isEmpty ? _venueId : meeting.venueId;
      _venueName = meeting.venueName.isEmpty ? _venueName : meeting.venueName;
      _selectedFriends
        ..clear()
        ..addAll(restoredFriends);
      _selectedPlaceCategories
        ..clear()
        ..addAll(
          meeting.placeCategories.isEmpty ? {'Any'} : meeting.placeCategories,
        );
      _hostLocation =
          _hostLocationFromCloud(meeting.hostLocation) ?? _hostLocation;
      _participants = restoredParticipants;
      _waitDeadline = meeting.waitDeadline;
      _suggestDeadline = meeting.suggestDeadline;
      _waitSecondsLeft = waitLeft.toInt();
      _suggestSecondsLeft = suggestLeft.toInt();
      _proceedUnlocked = true;
      _suggestedPointName = meeting.suggestedPoint;
      _suggestedCandidates = meeting.suggestedCandidates;
      _suggestionsComputed = meeting.suggestionsComputed;
    });

    if (_step == 4) {
      _startStep4WaitCountdown();
    } else if (_step == 5) {
      _startStep5SuggestCountdown();
      final mid = _meetingPointId;
      if (mid != null && _distCache.containsKey(mid)) {
        // Already computed in a previous session — show instantly.
        _step5DistMap = Map.of(_distCache[mid]!);
      } else if (_suggestionsComputed) {
        unawaited(_computeStep5Distances());
      }
    }

    _startMeetingSubscription(meeting.id);
  }

  void _startMeetingSubscription(String meetingPointId) {
    _meetingPointSub?.cancel();
    _meetingPointSub = FirebaseFirestore.instance
        .collection(MeetingPointService.collectionName)
        .doc(meetingPointId)
        .snapshots()
        .listen((doc) {
          final meeting = MeetingPointRecord.fromDoc(doc);
          if (!mounted || meeting == null) return;
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null || !meeting.isHost(uid)) return;

          // Calibrate server clock from live snapshot.
          if (!doc.metadata.isFromCache && meeting.updatedAt != null) {
            MeetingPointService.calibrateFromServerTime(meeting.updatedAt!);
          }

          // If the meeting was cancelled (all declined, timer expired with no
          // accepts, or host rejected), close the form immediately.
          if (!meeting.isActive && !meeting.isConfirmed) {
            unawaited(
              _completeAndClose(
                success: false,
                message: 'Meeting point was cancelled.',
              ),
            );
            return;
          }

          final participants = meeting.participants
              .map(_participantFromCloud)
              .toList();
          final nextStep = meeting.hostStep.clamp(1, 5).toInt();
          final waitLeft = meeting.waitDeadline == null
              ? _waitSecondsLeft
              : meeting.waitDeadline!
                    .difference(MeetingPointService.serverNow)
                    .inSeconds
                    .clamp(0, 120);
          final suggestLeft = meeting.suggestDeadline == null
              ? _suggestSecondsLeft
              : meeting.suggestDeadline!
                    .difference(MeetingPointService.serverNow)
                    .inSeconds
                    .clamp(0, 300);

          // Never let a stale cached snapshot downgrade a step we've already
          // advanced past locally (e.g. auto-advance race with Firestore cache).
          final prevStep = _step;
          final effectiveStep = nextStep >= _step ? nextStep : _step;
          final prevWaitDeadline = _waitDeadline;
          final prevSuggestDeadline = _suggestDeadline;
          setState(() {
            _participants = participants;
            _waitDeadline = meeting.waitDeadline;
            _suggestDeadline = meeting.suggestDeadline;
            _waitSecondsLeft = waitLeft.toInt();
            _suggestSecondsLeft = suggestLeft.toInt();
            _step = effectiveStep;
            _suggestedPointName = meeting.suggestedPoint;
            _suggestedCandidates = meeting.suggestedCandidates;
            _suggestionsComputed = meeting.suggestionsComputed;
          });

          // Compute client-side distances whenever step 5 has suggestions
          // but no distances yet (covers first delivery and any retry case).
          if (_step == 5 &&
              _suggestionsComputed &&
              _step5DistMap.isEmpty &&
              !_step5DistComputing) {
            unawaited(_computeStep5Distances());
          }

          // If Firestore advanced us from step 4 → 5 (e.g. the last participant
          // accepted and their device wrote hostStep=5 via respondToInvitation),
          // cancel the local wait-phase timers so they don't fire
          // _onWaitTimerExpired and reset the step-5 countdown.
          if (prevStep == 4 && _step >= 5) {
            _waitTimer?.cancel();
            _proceedTimer?.cancel();
          }

          // Only restart countdowns when the deadline itself changed (e.g.
          // step transition) — NOT on every participant accept/decline update.
          if (_step == 4 &&
              meeting.waitDeadline != null &&
              meeting.waitDeadline != prevWaitDeadline) {
            _startStep4WaitCountdown();
          } else if (_step == 5 &&
              meeting.suggestDeadline != null &&
              meeting.suggestDeadline != prevSuggestDeadline) {
            _startStep5SuggestCountdown();
          }

          // Auto-advance after a short delay so the host can see who accepted.
          final shouldAutoAdvance =
              _step == 4 &&
              _participants.isNotEmpty &&
              _participants.every(
                (p) => p.status != _ParticipantStatus.pending,
              ) &&
              _participants.any((p) => p.status == _ParticipantStatus.accepted);
          if (shouldAutoAdvance) {
            _scheduleAutoAdvance();
          } else {
            _autoAdvanceTimer?.cancel();
            _autoAdvanceTimer = null;
          }
        });
  }

  void _scheduleAutoAdvance() {
    if (_autoAdvanceTimer != null) return;
    _autoAdvanceTimer = Timer(_kAutoAdvanceDelay, () {
      _autoAdvanceTimer = null;
      if (!mounted) return;
      final shouldAdvance =
          _step == 4 &&
          _participants.isNotEmpty &&
          _participants.every((p) => p.status != _ParticipantStatus.pending) &&
          _participants.any((p) => p.status == _ParticipantStatus.accepted);
      if (shouldAdvance) {
        _goNext();
      }
    });
  }

  Future<void> _persistDraftIfNeeded() async {
    if (!_shouldManageDraft || !_isResumableDraftStep) return;
    final payload = <String, dynamic>{
      'step': _step,
      'meetingPointId': _meetingPointId,
      'venueId': _venueId,
      'venueName': _venueName,
      'placeCategories': _selectedPlaceCategories.toList(),
      'hostLocation': _hostLocation?.toMap(),
      'selectedFriends': _selectedFriends.map(_friendToDraft).toList(),
      'participants': _participants.map(_participantToDraft).toList(),
      'waitSecondsLeft': _waitSecondsLeft,
      'suggestSecondsLeft': _suggestSecondsLeft,
      'proceedUnlocked': _proceedUnlocked,
      'waitDeadlineMs': _waitDeadline?.millisecondsSinceEpoch,
      'suggestDeadlineMs': _suggestDeadline?.millisecondsSinceEpoch,
      'proceedUnlockAtMs': _proceedUnlockAt?.millisecondsSinceEpoch,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await MeetingPointDraftStorage.saveForCurrentUser(payload);
    await _syncMeetingPointProgress();
  }

  Future<void> _clearManagedDraft() async {
    if (!_shouldManageDraft) return;
    await MeetingPointDraftStorage.clearForCurrentUser();
  }

  Future<void> _syncMeetingPointProgress({String? status}) async {
    final id = _meetingPointId;
    if (id == null || id.trim().isEmpty) return;
    try {
      await MeetingPointService.updateHostProgress(
        meetingPointId: id,
        hostStep: _step,
        participants: _participants.map(_participantToCloud).toList(),
        waitDeadline: _step == 4 ? _waitDeadline : null,
        suggestDeadline: _step == 5 ? _suggestDeadline : null,
        status: status,
      );
    } catch (e) {
      debugPrint('Failed to sync meeting point progress: $e');
    }
  }

  Future<void> _completeAndClose({
    required bool success,
    required String message,
  }) async {
    if (_closeHandled) return;
    _closeHandled = true;
    _allowDisposeDraftSave = false;
    await _clearManagedDraft();
    if (success) _clearEarlyMemory();
    if (!mounted) return;
    Navigator.pop(context);
    if (success) {
      SnackbarHelper.showSuccess(context, message);
    } else {
      SnackbarHelper.showError(context, message);
    }
  }

  void _startProceedUnlockTimer() {
    _proceedTimer?.cancel();
    if (_proceedUnlocked) return;

    final unlockAt = _proceedUnlockAt;
    if (unlockAt == null) {
      setState(() => _proceedUnlocked = true);
      return;
    }

    final remaining = unlockAt.difference(DateTime.now());
    if (remaining.inMilliseconds <= 0) {
      if (mounted) setState(() => _proceedUnlocked = true);
      return;
    }

    _proceedTimer = Timer(remaining, () {
      if (!mounted) return;
      setState(() => _proceedUnlocked = true);
      unawaited(_persistDraftIfNeeded());
    });
  }

  void _startStep4WaitCountdown() {
    _waitTimer?.cancel();
    _waitDeadline ??= MeetingPointService.serverNow.add(
      Duration(seconds: _waitSecondsLeft),
    );

    void onTick() {
      if (!mounted) return;
      final left = _waitDeadline!
          .difference(MeetingPointService.serverNow)
          .inSeconds;
      if (left <= 0) {
        _waitTimer?.cancel();
        setState(() => _waitSecondsLeft = 0);
        _onWaitTimerExpired();
        return;
      }
      setState(() => _waitSecondsLeft = left);
    }

    onTick();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) => onTick());
  }

  void _startStep5SuggestCountdown() {
    _suggestTimer?.cancel();
    _suggestDeadline ??= MeetingPointService.serverNow.add(
      Duration(seconds: _suggestSecondsLeft),
    );

    void onTick() {
      if (!mounted) return;
      final left = _suggestDeadline!
          .difference(MeetingPointService.serverNow)
          .inSeconds;
      if (left <= 0) {
        _suggestTimer?.cancel();
        setState(() => _suggestSecondsLeft = 0);
        _acceptSuggestedMeetingPoint();
        return;
      }
      setState(() => _suggestSecondsLeft = left);
    }

    onTick();
    _suggestTimer = Timer.periodic(const Duration(seconds: 1), (_) => onTick());
  }

  // ── Step-5 client-side distance computation (same algorithm as path_overview) ─

  /// Converts navmesh floor number string ("0","1") to the asset file label
  /// ("GF","F1") used in navmesh_<label>.json.  Handles both numeric and label
  /// inputs so it works whatever format Firestore stored the floor in.
  static String _s5FNumToLabel(String fNum) {
    switch (fNum) {
      case '0':
        return 'GF';
      case '1':
        return 'F1';
      case '2':
        return 'F2';
      default:
        // Already a label (e.g. "GF", "F1") — return as-is.
        return fNum;
    }
  }

  static String _s5FloorToFNum(String label) {
    final up = label.toUpperCase().trim();
    if (up == 'G' || up == 'GF' || up.contains('GROUND')) return '0';
    final n = up.replaceAll(RegExp(r'[^0-9]'), '');
    return n.isEmpty ? label : n;
  }

  static double? _s5ToDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double _s5PathLen(List<List<double>> pts) {
    double sum = 0;
    for (int i = 1; i < pts.length; i++) {
      final dx = pts[i][0] - pts[i - 1][0];
      final dy = pts[i][1] - pts[i - 1][1];
      sum += math.sqrt(dx * dx + dy * dy);
    }
    return sum;
  }

  static String? _s5EpFNum(Map ep) {
    if (ep['floorNumber'] != null) return ep['floorNumber'].toString();
    if (ep['f_number'] != null) return ep['f_number'].toString();
    final floor = ep['floor']?.toString();
    if (floor != null) {
      if (int.tryParse(floor) != null) return floor;
      return _s5FloorToFNum(floor);
    }
    final lbl = ep['floorLabel'] ?? ep['floor_label'] ?? ep['label'];
    if (lbl != null) return _s5FloorToFNum(lbl.toString());
    return null;
  }

  Future<void> _computeStep5Distances() async {
    if (_step5DistComputing) return;
    if (_suggestedCandidates.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    if (mounted) setState(() => _step5DistComputing = true);

    final raw = _suggestedCandidates.first;
    final entranceMap = raw['entrance'];
    if (entranceMap is! Map) {
      if (mounted) setState(() => _step5DistComputing = false);
      return;
    }

    final entX = _s5ToDouble(entranceMap['x']) ?? 0.0;
    final entY = _s5ToDouble(entranceMap['y']) ?? 0.0;
    final entZ = _s5ToDouble(entranceMap['z']) ?? 0.0;
    final entFloorRaw = (entranceMap['floor'] ?? '').toString().trim();
    if (entFloorRaw.isEmpty) {
      if (mounted) setState(() => _step5DistComputing = false);
      return;
    }
    // Normalise: "0" → "GF", "1" → "F1", so navmesh asset loads correctly.
    final entFNum = _s5FloorToFNum(entFloorRaw);
    final entNavLabel = _s5FNumToLabel(entFNum);

    // All users to compute for: host + accepted participants.
    final accepted = _participants.where(
      (p) => p.status == _ParticipantStatus.accepted,
    );
    final allUserIds = [uid, ...accepted.map((p) => p.friend.id)];

    // Fetch each user's Blender position from Firestore.
    final db = FirebaseFirestore.instance;
    final Map<String, Map<String, dynamic>> positions = {};
    for (final userId in allUserIds) {
      try {
        final doc = await db.collection('users').doc(userId).get();
        final data = doc.data() ?? {};
        final bp =
            ((data['location'] as Map?)?['blenderPosition'] as Map?) ?? {};
        final x = _s5ToDouble(bp['x']);
        final y = _s5ToDouble(bp['y']);
        final z = _s5ToDouble(bp['z']);
        final floor = (bp['floor'] ?? '').toString().trim();
        if (x != null && y != null && z != null && floor.isNotEmpty) {
          positions[userId] = {'x': x, 'y': y, 'z': z, 'floor': floor};
        }
      } catch (_) {}
    }

    // Cache loaded navmeshes by asset label ("GF", "F1", …).
    final Map<String, NavMesh> nmCache = {};
    Future<NavMesh?> getNm(String navLabel) async {
      if (nmCache.containsKey(navLabel)) return nmCache[navLabel];
      try {
        final nm = await NavMesh.loadAsset(
          'assets/nav_cor/navmesh_$navLabel.json',
        );
        nmCache[navLabel] = nm;
        return nm;
      } catch (_) {
        return null;
      }
    }

    // Load connectors (needed only for cross-floor paths).
    List<dynamic> connectorList = const [];
    try {
      final connRaw = await rootBundle.loadString(
        'assets/connectors/connectors_merged_local.json',
      );
      final decoded = jsonDecode(connRaw);
      connectorList = (decoded is List)
          ? decoded
          : (decoded is Map && decoded['connectors'] is List)
          ? decoded['connectors'] as List
          : const [];
    } catch (_) {}

    const double unitToMeters = 69.32;
    final Map<String, int> result = {};

    for (final userId in allUserIds) {
      final pos = positions[userId];
      if (pos == null) continue;

      final userFloorRaw = pos['floor'] as String;
      final userFNum = _s5FloorToFNum(userFloorRaw);
      final userNavLabel = _s5FNumToLabel(userFNum);
      final userPt = [
        pos['x'] as double,
        pos['y'] as double,
        pos['z'] as double,
      ];
      final entPt = [entX, entY, entZ];

      double? rawDist;

      if (userFNum == entFNum) {
        // Same floor — direct funneled path.
        final nm = await getNm(entNavLabel);
        if (nm != null) {
          final pts = nm.findPathFunnelBlenderXY(start: userPt, goal: entPt);
          rawDist = _s5PathLen(pts);
        }
      } else {
        // Cross-floor — find best connector between the two floors.
        double best = double.infinity;
        for (final c in connectorList) {
          if (c is! Map) continue;
          final endpoints = c['endpoints'] ?? c['floors'] ?? c['nodes'];
          if (endpoints is! List) continue;

          Map? epA, epB;
          for (final ep in endpoints) {
            if (ep is! Map) continue;
            final f = _s5EpFNum(ep);
            if (f == userFNum) epA = ep;
            if (f == entFNum) epB = ep;
          }
          if (epA == null || epB == null) continue;

          (double?, double?, double?) epXYZ(Map ep) {
            final posMap = ep['position'] is Map ? ep['position'] as Map : null;
            return (
              _s5ToDouble(posMap?['x'] ?? ep['x']),
              _s5ToDouble(posMap?['y'] ?? ep['y']),
              _s5ToDouble(posMap?['z'] ?? ep['z']),
            );
          }

          final (ax, ay, az) = epXYZ(epA);
          final (bx, by, bz) = epXYZ(epB);
          if (ax == null ||
              ay == null ||
              az == null ||
              bx == null ||
              by == null ||
              bz == null) {
            continue;
          }

          final nmA = await getNm(userNavLabel);
          final nmB = await getNm(entNavLabel);
          if (nmA == null || nmB == null) continue;

          final ptsA = nmA.findPathFunnelBlenderXY(
            start: userPt,
            goal: [ax, ay, az],
          );
          final ptsB = nmB.findPathFunnelBlenderXY(
            start: [bx, by, bz],
            goal: entPt,
          );
          final total = _s5PathLen(ptsA) + _s5PathLen(ptsB);
          if (total < best) best = total;
        }
        if (best.isFinite) rawDist = best;
      }

      if (rawDist != null) {
        result[userId] = (rawDist * unitToMeters).round();
      }
    }

    if (mounted) {
      final mid = _meetingPointId;
      if (mid != null) _distCache[mid] = result;
      setState(() {
        _step5DistMap = result;
        _step5DistComputing = false;
      });
    }
  }

  DateTime? _dateFromEpoch(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  int _intFromDynamic(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  bool _boolFromDynamic(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase().trim();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return fallback;
  }

  Map<String, dynamic> _friendToDraft(_Friend f) {
    return {
      'id': f.id,
      'name': f.name,
      'phone': f.phone,
      'isFavorite': f.isFavorite,
    };
  }

  _Friend? _friendFromDraft(Map<String, dynamic> raw) {
    final phone = (raw['phone'] ?? '').toString().trim();
    if (phone.isEmpty) return null;
    return _Friend(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString().trim().isEmpty
          ? phone
          : raw['name'].toString(),
      phone: phone,
      isFavorite: _boolFromDynamic(raw['isFavorite'], false),
    );
  }

  Map<String, dynamic> _participantToDraft(_Participant p) {
    return {'friend': _friendToDraft(p.friend), 'status': p.status.name};
  }

  _Participant? _participantFromDraft(Map<String, dynamic> raw) {
    final friendRaw = raw['friend'];
    if (friendRaw is! Map) return null;
    final friend = _friendFromDraft(Map<String, dynamic>.from(friendRaw));
    if (friend == null) return null;

    final status = _statusFromDraft((raw['status'] ?? '').toString());
    return _Participant(friend: friend, status: status);
  }

  MeetingPointParticipant _participantToCloud(_Participant p) {
    return MeetingPointParticipant(
      userId: p.friend.id,
      name: p.friend.name,
      phone: p.friend.phone,
      status: p.status.name,
    );
  }

  _Participant _participantFromCloud(MeetingPointParticipant p) {
    return _Participant(
      friend: _Friend(
        id: p.userId,
        name: p.name.trim().isEmpty ? p.phone : p.name,
        phone: p.phone,
        isFavorite: false,
      ),
      status: _statusFromDraft(p.status),
    );
  }

  _ParticipantStatus _statusFromDraft(String raw) {
    switch (raw) {
      case 'accepted':
        return _ParticipantStatus.accepted;
      case 'declined':
        return _ParticipantStatus.declined;
      default:
        return _ParticipantStatus.pending;
    }
  }

  _HostLocation? _hostLocationFromDraft(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final lat = (map['latitude'] as num?)?.toDouble();
    final lng = (map['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return _HostLocation(
      latitude: lat,
      longitude: lng,
      label: (map['label'] ?? 'Set location').toString(),
    );
  }

  _HostLocation? _hostLocationFromCloud(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final lat = (raw['latitude'] as num?)?.toDouble();
    final lng = (raw['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return _HostLocation(
      latitude: lat,
      longitude: lng,
      label: (raw['label'] ?? 'Set location').toString(),
    );
  }

  // ─── Step navigation ──────────────────────────────────────────────────────

  void _goNext() {
    if (_step == 3) {
      // Step 3 → 4 is handled exclusively by _sendInvitesAndAdvance.
      // _goNext should never be called for step 3 from the UI.
      return;
    } else if (_step == 4) {
      // Step 4 → 5: cancel wait timer, start suggestion timer.
      // Increment _step FIRST so _syncMeetingPointProgress writes hostStep:5.
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = null;
      _waitTimer?.cancel();
      _proceedTimer?.cancel();
      _step = 5;
      _initStep5();
      setState(() {});
    } else {
      // Steps 1 → 2 and 2 → 3: simple increment.
      setState(() => _step++);
    }
    unawaited(_persistDraftIfNeeded());
  }

  void _goBack() {
    if (_step == 4) {
      _waitTimer?.cancel();
      _proceedTimer?.cancel();
    }
    if (_step == 5) {
      _suggestTimer?.cancel();
    }
    setState(() => _step--);
    unawaited(_persistDraftIfNeeded());
  }

  void _initStep4() {
    _shouldManageDraft = true;

    if (_participants.isEmpty) {
      // Build participant list from selected friends.
      _participants = _selectedFriends
          .map(
            (f) => _Participant(friend: f, status: _ParticipantStatus.pending),
          )
          .toList();
    }

    // 2-minute countdown.  Use the deadline that was already committed to
    // Firestore so the local timer and the Firestore field are identical.
    _waitSecondsLeft = 120;
    _waitDeadline =
        _pendingWaitDeadline ??
        MeetingPointService.serverNow.add(const Duration(minutes: 2));
    _pendingWaitDeadline = null; // consumed
    _startStep4WaitCountdown();

    // Unlock "Proceed" after 5 seconds (UI demo).
    _proceedUnlocked = false;
    _proceedUnlockAt = MeetingPointService.serverNow.add(
      const Duration(seconds: 5),
    );
    _startProceedUnlockTimer();

    if (_meetingPointId != null) {
      _startMeetingSubscription(_meetingPointId!);
      // status stays 'pending' — sub-state derived from hostStep + participants
      unawaited(_syncMeetingPointProgress(status: 'pending'));
    }
    unawaited(_persistDraftIfNeeded());
  }

  void _onWaitTimerExpired() {
    _waitTimer?.cancel();

    final anyAccepted = _participants.any(
      (p) => p.status == _ParticipantStatus.accepted,
    );
    if (!anyAccepted) {
      // No one accepted → cancel meeting point.
      unawaited(_syncMeetingPointProgress(status: 'cancelled'));
      if (mounted) {
        unawaited(
          _completeAndClose(
            success: false,
            message: 'Meeting point cancelled – no participants accepted.',
          ),
        );
      }
    } else {
      // At least one accepted → advance to step 5.
      // Set _step FIRST so _syncMeetingPointProgress writes hostStep:5.
      _step = 5;
      _initStep5();
      if (mounted) setState(() {});
      // status stays 'pending'; hostStep=5 signals waiting_host_confirmation sub-state
      unawaited(_persistDraftIfNeeded());
    }
  }

  void _initStep5() {
    _suggestSecondsLeft = 300;
    _suggestDeadline = MeetingPointService.serverNow.add(
      const Duration(minutes: 5),
    );
    _suggestedPointName = '';
    _suggestedCandidates = [];
    _suggestionsComputed = false;
    _startStep5SuggestCountdown();
    // status stays 'pending'; hostStep=5 signals waiting_host_confirmation sub-state
    unawaited(_syncMeetingPointProgress());
    unawaited(_persistDraftIfNeeded());
  }

  void _acceptSuggestedMeetingPoint() {
    _suggestTimer?.cancel();
    if (_meetingPointId != null) {
      unawaited(
        MeetingPointService.markHostDecision(
          meetingPointId: _meetingPointId!,
          accepted: true,
        ),
      );
    }
    unawaited(
      _completeAndClose(success: true, message: 'Meeting point accepted!'),
    );
  }

  Future<void> _rejectSuggestedMeetingPoint() async {
    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Reject Meeting Point',
      message:
          'Are you sure you want to reject this meeting point? The meeting will be cancelled for all participants.',
      cancelText: 'Keep',
      confirmText: 'Reject',
    );
    if (confirmed != true) return;
    _suggestTimer?.cancel();
    if (_meetingPointId != null) {
      unawaited(
        MeetingPointService.markHostDecision(
          meetingPointId: _meetingPointId!,
          accepted: false,
        ),
      );
    }
    unawaited(
      _completeAndClose(success: false, message: 'Meeting point rejected.'),
    );
  }

  // ─── Step-level gate conditions ───────────────────────────────────────────

  bool get _step1CanNext => _isVenueValid && _selectedFriends.isNotEmpty;
  bool get _step2CanNext => _hostLocation != null;

  /// Proceed is enabled if: unlock timer fired AND at least one accepted + location set.
  bool get _step4CanProceed {
    if (!_proceedUnlocked) return false;
    return _participants.any((p) => p.status == _ParticipantStatus.accepted);
  }

  // ─── Firestore meeting point creation ─────────────────────────────────────

  Future<void> _sendInvites() async {
    final host = FirebaseAuth.instance.currentUser;
    if (host == null) {
      throw Exception('You must be signed in to create a meeting point.');
    }
    if (_venueId == null || _venueName == null || _hostLocation == null) {
      throw Exception(
        'Please complete venue and location before sending invites.',
      );
    }

    try {
      final blockingMeeting =
          await MeetingPointService.getBlockingMeetingForCurrentUser();
      if (blockingMeeting != null && blockingMeeting.isActive) {
        if (blockingMeeting.hostId == host.uid) {
          throw Exception('You already have an active meeting point.');
        }
        final me = blockingMeeting.participantFor(host.uid);
        if (me != null && me.isAccepted) {
          throw Exception('You already have an active meeting point.');
        }
      }
    } on FirebaseException catch (e) {
      // Some rule setups reject the pre-check query. Do not block invite sending
      // when this guard cannot be evaluated server-side.
      debugPrint('Meeting pre-check skipped due Firestore rules: ${e.code}');
    }

    final participants = <MeetingPointParticipant>[];
    final unresolvedFriends = <String>[];
    for (final friend in _selectedFriends) {
      var userId = friend.id.trim();
      if (userId.isEmpty) {
        userId = await _resolveUserIdByPhone(friend.phone);
      }
      if (userId.isEmpty) {
        unresolvedFriends.add(
          friend.name.isNotEmpty ? friend.name : friend.phone,
        );
        continue;
      }
      participants.add(
        MeetingPointParticipant(
          userId: userId,
          name: friend.name,
          phone: friend.phone,
          status: 'pending',
        ),
      );
    }

    if (participants.isEmpty) {
      throw Exception(
        'Select at least one registered friend before sending invites.',
      );
    }
    if (unresolvedFriends.isNotEmpty) {
      throw Exception(
        'Some selected friends are not registered users: ${unresolvedFriends.join(', ')}.',
      );
    }

    final hostName = (_myName ?? '').trim().isNotEmpty
        ? _myName!.trim()
        : (host.displayName ?? '').trim();

    // createMeetingPoint now returns the server-time-based deadline alongside
    // the document ID.  We use it as _pendingWaitDeadline so the local timer
    // is anchored to the same Firestore server timestamp that every participant
    // also reads — eliminating host/participant clock disagreements.
    final (
      meetingPointId,
      serverDeadline,
    ) = await MeetingPointService.createMeetingPoint(
      hostId: host.uid,
      hostName: hostName.isNotEmpty ? hostName : 'Host',
      hostPhone: (_myPhone ?? '').trim(),
      venueId: _venueId!,
      venueName: _venueName!,
      placeCategories: _selectedPlaceCategories.toList(),
      hostLocation: _hostLocation?.toMap(),
      participants: participants,
      waitDuration: const Duration(minutes: 2),
    );
    _pendingWaitDeadline = serverDeadline;

    _meetingPointId = meetingPointId;

    _selectedFriends
      ..clear()
      ..addAll(
        participants
            .map(
              (p) => _Friend(
                id: p.userId,
                name: p.name,
                phone: p.phone,
                isFavorite: false,
              ),
            )
            .toList(),
      );
    _participants = participants
        .map(
          (p) => _Participant(
            friend: _Friend(
              id: p.userId,
              name: p.name,
              phone: p.phone,
              isFavorite: false,
            ),
            status: _statusFromDraft(p.status),
          ),
        )
        .toList();
    _startMeetingSubscription(meetingPointId);
  }

  Future<String> _resolveUserIdByPhone(String phone) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return '';
    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: normalized)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return '';
      return q.docs.first.id;
    } catch (_) {
      return '';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _handleExitRequested();
        return false;
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Drag handle
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  _buildHeader(),
                  _buildProgressBar(),
                  if (_step == 5)
                    Expanded(child: _buildStepBody())
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        child: _buildStepBody(),
                      ),
                    ),
                  if (_step == 5) _buildStep5FixedButtons(),
                  _buildFooter(),
                ],
              ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    const subtitles = [
      'Select friends and where to meet',
      'Set your location',
      'Review & send',
      'Waiting for participants',
      'Confirm suggested meeting point',
    ];

    // Timer badge shown on steps 4 and 5 (same rows as subtitle — mirrors
    // non-host "View details" sheet where timer sits next to the step label).
    String? timerLabel;
    if (_step == 4) {
      final mm = (_waitSecondsLeft ~/ 60).toString().padLeft(2, '0');
      final ss = (_waitSecondsLeft % 60).toString().padLeft(2, '0');
      timerLabel = '$mm:$ss';
    } else if (_step == 5) {
      final mm = (_suggestSecondsLeft ~/ 60).toString().padLeft(2, '0');
      final ss = (_suggestSecondsLeft % 60).toString().padLeft(2, '0');
      timerLabel = '$mm:$ss';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.people_outline,
              color: AppColors.kGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create Meeting Point',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                // Subtitle row: step description + timer badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        subtitles[_step - 1],
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ),
                    if (timerLabel != null) ...[
                      const SizedBox(width: 8),
                      MeetingTimerBadge(label: timerLabel),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_step - 1) / 5,
              minHeight: 3,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(AppColors.kGreen),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Step $_step of 5',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // ── Step body dispatcher ──────────────────────────────────────────────────

  Widget _buildStepBody() {
    switch (_step) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      case 4:
        return _buildStep4();
      case 5:
        return _buildStep5();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 – Venue · Friends · Place Type
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    final inputsEnabled = _isVenueValid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Venue field (read-only, auto-detected) ──────────────────────────
        _sectionLabel('Venue'),
        const SizedBox(height: 10),
        _venueReadOnlyField(),
        if (_venueError != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.kError,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _venueError!,
                  style: TextStyle(fontSize: 13, color: AppColors.kError),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // ── Friends section (disabled when no venue) ────────────────────────
        AbsorbPointer(
          absorbing: !inputsEnabled,
          child: Opacity(
            opacity: inputsEnabled ? 1.0 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Select Friends to Meet'),
                const SizedBox(height: 14),

                // Phone + Add + Favorites row
                _buildPhoneInputRow(),
                const SizedBox(height: 6),
                SizedBox(
                  height: 18,
                  child: (!_phoneValid && _phoneError != null)
                      ? Text(
                          _phoneError!,
                          style: const TextStyle(
                            color: AppColors.kError,
                            fontSize: 13,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 14),

                // Active tracked friends at venue
                _buildActiveVenueFriendsList(),

                // Selected friends list
                if (_selectedFriends.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Selected friends',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._selectedFriends.map(_buildSelectedFriendRow),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedFriends.length} friend${_selectedFriends.length == 1 ? '' : 's'} selected',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Place type (chips) ────────────────────────────────────
                _sectionLabel('Select Where to Meet Your Friends'),
                const SizedBox(height: 12),
                _buildPlaceTypeChips(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _venueReadOnlyField() {
    final venueLabel =
        _venueName ??
        (_loadingVenue ? 'Detecting venue...' : 'No venue detected');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _venueError != null ? AppColors.kError : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.place_outlined, color: AppColors.kGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              venueLabel,
              style: TextStyle(
                fontSize: 15,
                // Normal weight so it reads as non-editable
                fontWeight: FontWeight.w400,
                color: _venueName != null ? Colors.black54 : Colors.grey[500],
              ),
            ),
          ),
          // Subtle lock to indicate read-only without being obtrusive
          Icon(Icons.lock_outline, size: 15, color: Colors.grey[400]),
        ],
      ),
    );
  }

  Widget _buildPhoneInputRow() {
    final canTapAdd = _canAddPhone;

    return Row(
      children: [
        // Phone field
        Expanded(
          child: TextField(
            controller: _phoneCtrl,
            focusNode: _phoneFocus,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (_) => setState(() {
              _phoneValid = true;
              _phoneError = null;
            }),
            decoration: InputDecoration(
              hintText: _isPhoneFocused ? 'Enter 9 digits' : 'Phone number',
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontWeight: FontWeight.w400,
              ),
              prefix: (_isPhoneFocused || _phoneCtrl.text.isNotEmpty)
                  ? Text(
                      '+966 ',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    )
                  : null,
              suffixIcon: _isPhoneFocused
                  ? IconButton(
                      icon: const Icon(Icons.contacts, color: AppColors.kGreen),
                      onPressed: _pickContact,
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _phoneValid ? Colors.grey.shade300 : AppColors.kError,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _phoneValid ? AppColors.kGreen : AppColors.kError,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Add button
        GestureDetector(
          onTap: canTapAdd ? _addFriendByPhone : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: canTapAdd ? AppColors.kGreen : Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Add',
              style: TextStyle(
                color: canTapAdd ? Colors.white : Colors.grey[500],
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Favorites heart button
        IconButton(
          onPressed: _showFavoritesList,
          icon: const Icon(
            Icons.favorite_border,
            color: AppColors.kGreen,
            size: 28,
          ),
          padding: const EdgeInsets.all(12),
          style: IconButton.styleFrom(
            backgroundColor: Colors.grey[100],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveVenueFriendsList() {
    final name = _venueName ?? 'venue';
    final remaining = _remainingActiveVenueFriends;

    if (_activeVenueFriends.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label: "Active tracked friends at [venue]"
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.groups_2_outlined, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Active tracked friends at $name',
                softWrap: true,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingActiveVenueFriends && remaining.isEmpty)
          const SizedBox.shrink()
        else if (remaining.isEmpty)
          Center(
            child: Text(
              'All Active tracked friends added.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
            ),
          )
        else
          ...remaining.map((friend) => _buildActiveVenueFriendRow(friend)),
      ],
    );
  }

  Widget _buildActiveVenueFriendRow(_Friend friend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  friend.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // Heart icon
          Icon(
            friend.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 22,
            color: friend.isFavorite ? Colors.red : Colors.grey[400],
          ),
          const SizedBox(width: 10),

          // Add button (no background, text-only)
          GestureDetector(
            onTap: () => _addFriend(friend),
            child: const Text(
              'Add',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedFriendRow(_Friend friend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  friend.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // Heart icon
          Icon(
            friend.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 22,
            color: friend.isFavorite ? Colors.red : Colors.grey[400],
          ),
          const SizedBox(width: 8),

          // Green checkmark / remove indicator
          GestureDetector(
            onTap: () => _removeFriend(friend),
            child: const Icon(
              Icons.check_circle,
              color: AppColors.kGreen,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceTypeChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _allPlaceCategories.map((type) {
        final selected = _selectedPlaceCategories.contains(type);
        return GestureDetector(
          onTap: () {
            setState(() {
              _togglePlaceType(type);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.kGreen.withOpacity(0.13)
                  : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.kGreen : Colors.grey.shade400,
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  type,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected ? AppColors.kGreen : Colors.black87,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.close, size: 14, color: AppColors.kGreen),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _togglePlaceType(String type) {
    const any = 'Any';

    // "Any" must be exclusive.
    if (type == any) {
      _selectedPlaceCategories
        ..clear()
        ..add(any);
      return;
    }

    // Choosing any specific type should always unselect "Any".
    _selectedPlaceCategories.remove(any);

    if (_selectedPlaceCategories.contains(type)) {
      _selectedPlaceCategories.remove(type);
    } else {
      _selectedPlaceCategories.add(type);
    }

    // Keep at least one selected.
    if (_selectedPlaceCategories.isEmpty) {
      _selectedPlaceCategories.add(any);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 – Set My Location
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    final mapVenueId = _mapVenueIdForLocation;
    final hintText = _hostLocation != null
        ? 'Location selected. Tap again to move it.'
        : 'Tap on the 3D map to place your pin.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Set My Location'),
        const SizedBox(height: 8),
        Text(hintText, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 12),

        if (mapVenueId == null)
          Container(
            height: 400,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const CircularProgressIndicator(color: AppColors.kGreen),
          )
        else
          SizedBox(
            height: 400,
            child: SetYourLocationDialog(
              key: ValueKey(
                'meeting_step2_map_${mapVenueId}_$_step2MapVersion',
              ),
              shopName: _venueName ?? 'Meeting Point',
              shopId: mapVenueId,
              venueId: mapVenueId,
              returnResultOnly: true,
              initialUserPinGltf: _step2InitialUserPinGltf,
              initialFloorLabel: _step2InitialFloorLabel,
              embeddedMode: true,
              onLocationPicked: (result) {
                final g = result['gltf'];
                final floorLabel = (result['floorLabel'] ?? '').toString();
                if (g is Map) {
                  final x = (g['x'] as num?)?.toDouble();
                  final y = (g['y'] as num?)?.toDouble();
                  final z = (g['z'] as num?)?.toDouble();
                  if (x != null && y != null && z != null) {
                    setState(() {
                      _step2InitialUserPinGltf = {'x': x, 'y': y, 'z': z};
                      _step2InitialFloorLabel = floorLabel;
                    });
                  }
                }
                _applyHostLocationFromSetLocationResult(
                  result,
                  fallback: 'Pinned location',
                );
              },
            ),
          ),

        const SizedBox(height: 12),
        PrimaryButton(
          text: 'Scan With Camera',
          icon: Icons.camera_alt_outlined,
          onPressed: _scanWithCamera,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  DateTime? _toUtcDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toUtc();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    }
    if (v is String) return DateTime.tryParse(v)?.toUtc();
    return null;
  }

  Map<String, double> _blenderToGltf(Map<String, double> b) {
    // Blender (Z up) -> glTF (Y up)
    return {'x': b['x'] ?? 0, 'y': (b['z'] ?? 0), 'z': -(b['y'] ?? 0)};
  }

  Future<void> _loadSavedStep2Location() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDocRef = await _resolveUserDocRef(user);
      final doc = await userDocRef.get();
      final data = doc.data();
      if (data == null) return;

      final location = data['location'];
      if (location is! Map) return;

      final updatedAt = _toUtcDate(location['updatedAt']);
      if (updatedAt != null) {
        final oneHourAgo = DateTime.now().toUtc().subtract(
          const Duration(hours: 1),
        );
        if (updatedAt.isBefore(oneHourAgo)) return;
      }

      final bp = location['blenderPosition'];
      if (bp is! Map) return;

      final x = (bp['x'] as num?)?.toDouble();
      final y = (bp['y'] as num?)?.toDouble();
      final z = (bp['z'] as num?)?.toDouble();
      final floorRaw = bp['floor'];
      if (x == null || y == null || z == null) return;

      final floorLabel = floorRaw == null ? '' : floorRaw.toString();
      final blenderRaw = {'x': x, 'y': y, 'z': z};

      NavMesh? nav;
      try {
        nav = await NavMesh.loadAsset('assets/nav_cor/navmesh_GF.json');
      } catch (_) {
        nav = null;
      }

      final blender = (nav == null)
          ? blenderRaw
          : nav.snapBlenderPoint(blenderRaw);
      final gltf = _blenderToGltf(blender);

      if (!mounted) return;
      if (_hostLocation != null) return;

      setState(() {
        _step2InitialUserPinGltf = gltf;
        _step2InitialFloorLabel = floorLabel;
        _step2MapVersion++;
        _hostLocation = _HostLocation(
          latitude: blender['x'] ?? x,
          longitude: blender['z'] ?? z,
          label: floorLabel.isNotEmpty
              ? 'Current location ($floorLabel)'
              : 'Current location',
        );
      });
    } catch (_) {}
  }

  Future<void> _scanWithCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera permission required. Please enable in Settings.',
            ),
          ),
        );
        openAppSettings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required.')),
        );
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
      return;
    }

    final scanStartUtc = DateTime.now().toUtc();
    final userDocRef = await _resolveUserDocRef(user);

    DateTime? toUtcDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate().toUtc();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
      if (v is num) {
        return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
      }
      if (v is String) return DateTime.tryParse(v)?.toUtc();
      return null;
    }

    NavMesh? nav;
    try {
      nav = await NavMesh.loadAsset('assets/nav_cor/navmesh_GF.json');
    } catch (_) {
      nav = null;
    }

    bool didReturn = false;
    late final StreamSubscription sub;

    sub = userDocRef.snapshots().listen((snap) async {
      if (didReturn) return;

      final data = snap.data();
      if (data == null) return;

      final loc = data['location'];
      if (loc is! Map) return;

      final updatedAtUtc = toUtcDate(loc['updatedAt']);
      if (updatedAtUtc == null || !updatedAtUtc.isAfter(scanStartUtc)) return;

      final bp = loc['blenderPosition'];
      if (bp is! Map) return;

      final x = (bp['x'] as num?)?.toDouble();
      final y = (bp['y'] as num?)?.toDouble();
      final z = (bp['z'] as num?)?.toDouble();
      final floor = bp['floor'];

      if (x == null || y == null || z == null) return;

      var snapped = <String, double>{'x': x, 'y': y, 'z': z};
      if (nav != null) {
        try {
          snapped = nav.snapBlenderPoint(snapped);
        } catch (_) {}
      }

      didReturn = true;

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      await sub.cancel();
      if (!mounted) return;

      final snappedGltf = <String, double>{
        'x': snapped['x'] ?? x,
        'y': snapped['y'] ?? y,
        'z': snapped['z'] ?? z,
      };

      final floorLabelFromScan = floor == null ? '' : floor.toString();
      setState(() {
        _step2InitialUserPinGltf = snappedGltf;
        _step2InitialFloorLabel = floorLabelFromScan;
        _step2MapVersion++;
      });

      await _applyHostLocationFromSetLocationResult({
        'gltf': snappedGltf,
        'blender': snapped,
        'floorLabel': floorLabelFromScan,
      }, fallback: 'Camera scan');
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UnityCameraPage(isScanOnly: true),
      ),
    );

    if (!didReturn) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
  }

  Future<void> _applyHostLocationFromSetLocationResult(
    Map<String, dynamic> result, {
    required String fallback,
  }) async {
    final blender = result['blender'];
    final gltf = result['gltf'];
    final floorLabel = (result['floorLabel'] ?? '').toString().trim();

    double? x;
    double? z;

    if (blender is Map) {
      x = (blender['x'] as num?)?.toDouble();
      z = (blender['z'] as num?)?.toDouble();
    }

    if ((x == null || z == null) && gltf is Map) {
      x ??= (gltf['x'] as num?)?.toDouble();
      z ??= (gltf['z'] as num?)?.toDouble();
    }

    if (x == null || z == null) {
      final pos = await _getPositionOrNull();
      x = pos?.latitude;
      z = pos?.longitude;
    }

    if (x == null || z == null || !mounted) return;

    final label = floorLabel.isNotEmpty
        ? 'Current location ($floorLabel)'
        : fallback;
    setState(() {
      _hostLocation = _HostLocation(latitude: x!, longitude: z!, label: label);
    });

    // Persist the picked location to users/{doc}.location.blenderPosition
    // so suggestions can use the latest saved location.
    await _saveUserLocationFromResult(result);
  }

  Map<String, double>? _extractBlenderFromResult(Map<String, dynamic> result) {
    final blender = result['blender'];
    if (blender is Map) {
      final x = (blender['x'] as num?)?.toDouble();
      final y = (blender['y'] as num?)?.toDouble();
      final z = (blender['z'] as num?)?.toDouble();
      if (x != null && y != null && z != null) {
        return {'x': x, 'y': y, 'z': z};
      }
    }

    final gltf = result['gltf'];
    if (gltf is Map) {
      final x = (gltf['x'] as num?)?.toDouble();
      final y = (gltf['y'] as num?)?.toDouble();
      final z = (gltf['z'] as num?)?.toDouble();
      if (x != null && y != null && z != null) {
        // glTF (Y up) -> Blender (Z up)
        return {'x': x, 'y': -z, 'z': y};
      }
    }

    return null;
  }

  Future<void> _saveUserLocationFromResult(Map<String, dynamic> result) async {
    final blender = _extractBlenderFromResult(result);
    if (blender == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final floorLabel = (result['floorLabel'] ?? '').toString().trim();
    final floorValue = floorLabel.isNotEmpty
        ? floorLabel
        : (_step2InitialFloorLabel ?? '');

    try {
      final userDocRef = await _resolveUserDocRef(user);
      await userDocRef.update({
        'location.blenderPosition': {
          'x': blender['x'],
          'y': blender['y'],
          'z': blender['z'],
          'floor': floorValue,
        },
        'location.updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Failed to save user location from meeting form: $e');
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> _resolveUserDocRef(
    User user,
  ) async {
    final users = FirebaseFirestore.instance.collection('users');

    final email = user.email;
    if (email != null && email.isNotEmpty) {
      final snap = await users.where('email', isEqualTo: email).limit(1).get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.reference;
      }
    }

    final phone = user.phoneNumber;
    if (phone != null && phone.isNotEmpty) {
      final snap = await users.where('phone', isEqualTo: phone).limit(1).get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.reference;
      }
    }

    return users.doc(user.uid);
  }

  Future<String> _resolveMapVenueId() async {
    Future<bool> hasMap(String id) async {
      if (id.trim().isEmpty) return false;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('venues')
            .doc(id.trim())
            .get(const GetOptions(source: Source.serverAndCache));
        final data = doc.data();
        return data != null &&
            data['map'] is List &&
            (data['map'] as List).isNotEmpty;
      } catch (_) {
        return false;
      }
    }

    if (_venueId != null && await hasMap(_venueId!)) {
      return _venueId!;
    }

    if (await hasMap(_kFallbackMapVenueId)) {
      return _kFallbackMapVenueId;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('venues')
          .limit(50)
          .get(const GetOptions(source: Source.serverAndCache));
      for (final d in snap.docs) {
        final data = d.data();
        if (data['map'] is List && (data['map'] as List).isNotEmpty) {
          return d.id;
        }
      }
    } catch (_) {}

    return (_venueId ?? _kFallbackMapVenueId).trim();
  }

  Future<void> _prepareStep2MapVenueId() async {
    final resolved = await _resolveMapVenueId();
    if (!mounted) return;
    if (_mapVenueIdForLocation != resolved) {
      setState(() {
        _mapVenueIdForLocation = resolved;
        _step2MapVersion++;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3 – Summary + Send Invites
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Summary'),
        const SizedBox(height: 16),

        // Green left-border summary card (no filled background)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Green vertical line
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: AppColors.kGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryRow('Venue', _venueName ?? '—'),
                    const SizedBox(height: 10),
                    _summaryRow(
                      'Where to meet',
                      _selectedPlaceCategories.join(', '),
                    ),
                    const SizedBox(height: 10),
                    _summaryRow(
                      'My location',
                      _hostLocation != null
                          ? 'Current location set'
                          : 'Not set',
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Invited friends',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._selectedFriends.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person,
                                size: 15,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${f.name} · ${f.phone}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            '$label:',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendInvitesAndAdvance() async {
    if (_isSendingInvites) return;
    setState(() => _isSendingInvites = true);
    try {
      await _sendInvites();
      if (!mounted) return;
      _initStep4();
      setState(() {
        _step = 4;
        _isSendingInvites = false;
      });
      unawaited(_persistDraftIfNeeded());
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSendingInvites = false);
      SnackbarHelper.showError(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 – Waiting for participants (10-min timer)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Waiting for participants'),
        const SizedBox(height: 16),

        // Participant rows
        ..._participants.map(_buildParticipantRow),

        const SizedBox(height: 7),

        // Hint text
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Note: you can proceed with participants who accepted, or cancel the meeting point for all.',
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildParticipantRow(_Participant p) {
    final statusText = p.status == _ParticipantStatus.accepted
        ? 'Accepted'
        : p.status == _ParticipantStatus.declined
        ? 'Declined'
        : 'Pending';

    final statusColor = p.status == _ParticipantStatus.accepted
        ? AppColors.kGreen
        : p.status == _ParticipantStatus.declined
        ? AppColors.kError
        : Colors.orange[600]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.friend.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  p.friend.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // Heart
          Icon(
            p.friend.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 22,
            color: p.friend.isFavorite ? Colors.red : Colors.grey[400],
          ),
          const SizedBox(width: 10),

          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 5 – Accept or Reject Suggested Meeting Point
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep5() {
    final hasSuggestion = _suggestedPointName.trim().isNotEmpty;
    final showEmpty = !hasSuggestion && _suggestionsComputed;
    final primaryName = hasSuggestion
        ? _suggestedPointName.trim()
        : (showEmpty ? 'No suitable meeting point found' : 'Calculating...');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Big pin icon centred
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.kGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.place, color: AppColors.kGreen, size: 52),
          ),
          const SizedBox(height: 20),

          const Text(
            'The most suitable meeting point is',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Text(
            '"$primaryName"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: hasSuggestion ? Colors.black87 : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          if (hasSuggestion)
            Text(
              'If you don\'t decide, it will be auto-accepted when the timer runs out.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          if (showEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Try different categories or make sure everyone\'s location is available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],

          const SizedBox(height: 24),

          // ── Participants with distances ────────────────────────────────────
          Expanded(child: _buildStep5ParticipantList()),
        ],
      ),
    );
  }

  Widget _buildStep5FixedButtons() {
    final hasSuggestion = _suggestedPointName.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: hasSuggestion ? _acceptSuggestedMeetingPoint : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            text: 'Reject',
            onPressed: hasSuggestion ? _rejectSuggestedMeetingPoint : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStep5ParticipantList() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Use client-side funneled distances (same algorithm as path_overview).
    final Map<String, int> distMap = _step5DistMap;

    String formatTime(int meters) {
      final secs = meters / 1.4;
      if (secs < 60) return '~1 min';
      return '~${(secs / 60).ceil()} min';
    }

    // Accepted non-host participants + those who declined during step 5.
    final accepted = _participants
        .where((p) => p.status == _ParticipantStatus.accepted)
        .toList();
    final declined = _participants
        .where((p) => p.status == _ParticipantStatus.declined)
        .toList();

    if (accepted.isEmpty && uid.isEmpty) return const SizedBox.shrink();

    final isComputing = _step5DistComputing;

    Widget participantTile({
      required String name,
      required String phone,
      required bool isHost,
      required bool isDeclined,
      int? distMeters,
    }) {
      final statusColor = isDeclined ? AppColors.kError : AppColors.kGreen;
      final statusText = isDeclined ? 'Declined' : 'Accepted';

      // Time label: shown inline with name, or a tiny spinner while computing.
      Widget? timeWidget;
      if (!isDeclined) {
        if (distMeters != null) {
          timeWidget = Text(
            formatTime(distMeters),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          );
        } else if (isComputing) {
          timeWidget = SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.grey[400],
            ),
          );
        }
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, color: Colors.grey[600], size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + time on the same row
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isHost ? 'Me (Host)' : name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (timeWidget != null) ...[
                        const SizedBox(width: 6),
                        timeWidget,
                      ],
                    ],
                  ),
                  // Phone below name (skip for host)
                  if (!isHost && phone.isNotEmpty)
                    Text(
                      phone,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isHost)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Build the flat tile list.
    final tiles = <Widget>[
      if (uid.isNotEmpty)
        participantTile(
          name: _myName ?? '',
          phone: '',
          isHost: true,
          isDeclined: false,
          distMeters: distMap[uid],
        ),
      ...accepted.map(
        (p) => participantTile(
          name: p.friend.name,
          phone: p.friend.phone,
          isHost: false,
          isDeclined: false,
          distMeters: distMap[p.friend.id],
        ),
      ),
      ...declined.map(
        (p) => participantTile(
          name: p.friend.name,
          phone: p.friend.phone,
          isHost: false,
          isDeclined: true,
          distMeters: null,
        ),
      ),
    ];

    // ≤2 tiles: natural height (no scroll, no fixed box).
    // 3+ tiles: capped at ~2.4 tiles tall with a visible scrollbar.
    const double tileHeight = 76; // name + phone + margin
    final isScrollable = tiles.length > 2;

    final listWidget = isScrollable
        ? Scrollbar(
            thumbVisibility: true,
            radius: const Radius.circular(4),
            child: SizedBox(
              height: tileHeight * 2.4,
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                children: tiles,
              ),
            ),
          )
        : Column(children: tiles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Participants',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            if (isScrollable) ...[
              const SizedBox(width: 6),
              Icon(Icons.expand_more, size: 14, color: Colors.grey[400]),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
          child: listWidget,
        ),
      ],
    );
  }

  Widget _buildSuggestedCandidateTile(Map<String, dynamic> raw, int index) {
    final name = (raw['placeName'] ?? '').toString().trim();
    final entrance = raw['entrance'] is Map ? raw['entrance'] as Map : null;
    final floor = entrance?['floor']?.toString().trim() ?? '';
    final rank = index + 1;
    if (name.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.kGreen.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.kGreen,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (floor.isNotEmpty)
                  Text(
                    'Floor: $floor',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Footer actions
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    // Step 5 manages its own CTAs inside the body; no bottom footer.
    if (_step == 5) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Back button (shown from step 2 onwards, except step 4)
          if (_step > 1 && _step != 4) ...[
            Expanded(
              child: SecondaryButton(text: 'Back', onPressed: _goBack),
            ),
            const SizedBox(width: 12),
          ],

          // Next / Proceed button
          Expanded(
            flex: _step > 1 && _step != 4 ? 2 : 1,
            child: _buildPrimaryFooterButton(),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelMeetingPointFromForm() async {
    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Cancel Meeting Point',
      message:
          'Are you sure you want to cancel this meeting point for all participants?',
      cancelText: 'Keep',
      confirmText: 'Cancel Meeting',
    );
    if (confirmed != true) return;
    _waitTimer?.cancel();
    unawaited(_syncMeetingPointProgress(status: 'cancelled'));
    await _completeAndClose(
      success: false,
      message: 'Meeting point cancelled.',
    );
  }

  Widget _buildPrimaryFooterButton() {
    // Step 4: "Proceed" above, "Cancel" below
    if (_step == 4) {
      final enabled = _step4CanProceed;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: enabled ? _goNext : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: enabled ? AppColors.kGreen : Colors.grey[300],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Proceed',
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.grey[500],
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: SecondaryButton(
              text: 'Cancel',
              onPressed: _cancelMeetingPointFromForm,
            ),
          ),
        ],
      );
    }

    // Step 3: "Send Invites"
    if (_step == 3) {
      return PrimaryButton(
        text: 'Send Invites',
        isLoading: _isSendingInvites,
        onPressed: _sendInvitesAndAdvance,
      );
    }

    // Steps 1 and 2: "Next"
    final enabled = _step == 1 ? _step1CanNext : _step2CanNext;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? _goNext : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? AppColors.kGreen : Colors.grey[300],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Next',
          style: TextStyle(
            color: enabled ? Colors.white : Colors.grey[500],
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FAVORITES LIST SHEET  (matches exact pattern from TrackRequestDialog)
// ═════════════════════════════════════════════════════════════════════════════

class _FavoriteListSheet extends StatefulWidget {
  const _FavoriteListSheet({required this.alreadySelectedPhones});
  final Set<String> alreadySelectedPhones;

  @override
  State<_FavoriteListSheet> createState() => _FavoriteListSheetState();
}

class _FavoriteListSheetState extends State<_FavoriteListSheet> {
  final _searchCtrl = TextEditingController();

  // Stub favorites – replace with real Firestore query.
  final List<_Friend> _allFavorites = [
    _Friend(
      id: '1',
      name: 'Mona Saleh',
      phone: '+966557225235',
      isFavorite: true,
    ),
    _Friend(
      id: '2',
      name: 'ar saeed',
      phone: '+966334333333',
      isFavorite: true,
    ),
    _Friend(id: '3', name: 'Ameera', phone: '+966503347974', isFavorite: true),
    _Friend(id: '4', name: 'Amjad', phone: '+966503347973', isFavorite: true),
  ];

  late List<_Friend> _filtered;
  final List<_Friend> _picked = [];

  @override
  void initState() {
    super.initState();
    _filtered = _allFavorites
        .where((f) => !widget.alreadySelectedPhones.contains(f.phone))
        .toList();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allFavorites
          .where((f) => !widget.alreadySelectedPhones.contains(f.phone))
          .where((f) => f.name.toLowerCase().contains(q) || f.phone.contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const Expanded(
                  child: Text(
                    'Favorite list',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, _picked),
                  child: Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _picked.isEmpty
                          ? Colors.grey[400]
                          : AppColors.kGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              cursorColor: AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 0.5),
              itemBuilder: (ctx, i) {
                final f = _filtered[i];
                final selected = _picked.contains(f);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      color: Colors.grey[600],
                      size: 22,
                    ),
                  ),
                  title: Text(
                    f.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    f.phone,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  trailing: GestureDetector(
                    onTap: () => setState(() {
                      selected ? _picked.remove(f) : _picked.add(f);
                    }),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.kGreen : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? AppColors.kGreen
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                  onTap: () => setState(() {
                    selected ? _picked.remove(f) : _picked.add(f);
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class _ContactItem {
  const _ContactItem({required this.name, required this.phone});

  final String name;
  final String phone;
}

class SelectContactPage extends StatefulWidget {
  final List<_ContactItem> contacts;
  final Map<String, bool> inDbStatus;
  final void Function(String phone) onInvite;

  const SelectContactPage({
    super.key,
    required this.contacts,
    required this.inDbStatus,
    required this.onInvite,
  });

  @override
  State<SelectContactPage> createState() => _SelectContactPageState();
}

class _SelectContactPageState extends State<SelectContactPage> {
  final _searchController = TextEditingController();
  late Map<String, bool> _localInDbStatus;
  bool _isCheckingDb = false;

  @override
  void initState() {
    super.initState();
    _localInDbStatus = Map.from(widget.inDbStatus);
    _searchController.addListener(() => setState(() {}));
    _checkRemainingContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkRemainingContacts() async {
    if (_isCheckingDb) return;
    _isCheckingDb = true;

    final toCheck = widget.contacts
        .where((c) => !_localInDbStatus.containsKey(c.phone))
        .toList();

    if (toCheck.isEmpty) {
      _isCheckingDb = false;
      return;
    }

    const batchSize = 10;
    for (var i = 0; i < toCheck.length; i += batchSize) {
      if (!mounted) return;
      final batch = toCheck.skip(i).take(batchSize).toList();

      await Future.wait(
        batch.map((item) async {
          try {
            final query = await FirebaseFirestore.instance
                .collection('users')
                .where('phone', isEqualTo: item.phone)
                .limit(1)
                .get();
            if (mounted) {
              setState(() {
                _localInDbStatus[item.phone] = query.docs.isNotEmpty;
              });
            }
          } catch (_) {
            if (mounted) {
              setState(() {
                _localInDbStatus[item.phone] = false;
              });
            }
          }
        }),
      );
    }

    _isCheckingDb = false;
  }

  List<_ContactItem> get _filteredItems {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return widget.contacts;
    return widget.contacts
        .where((i) => i.name.toLowerCase().contains(q) || i.phone.contains(q))
        .toList();
  }

  Map<String, List<_ContactItem>> get _grouped {
    final map = <String, List<_ContactItem>>{};
    for (final i in _filteredItems) {
      final letter = i.name.isNotEmpty ? i.name[0].toUpperCase() : '#';
      map.putIfAbsent(letter, () => []).add(i);
    }
    return map;
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF4CAF50),
      Color(0xFF2196F3),
      Color(0xFF9C27B0),
      Color(0xFF009688),
      Color(0xFFE91E63),
      Color(0xFFFF5722),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _initial(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final a = parts[0].isNotEmpty ? parts[0][0] : '';
      final b = parts[1].isNotEmpty ? parts[1][0] : '';
      return (a + b).toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final keys = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Select a contact',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              cursorColor: AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: widget.contacts.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.kGreen),
                  )
                : keys.isEmpty
                ? Center(
                    child: Text(
                      'No contacts',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: keys.fold<int>(
                          0,
                          (sum, k) => sum + 1 + grouped[k]!.length,
                        ),
                        itemBuilder: (context, index) {
                          int total = 0;
                          for (final k in keys) {
                            final list = grouped[k]!;
                            if (index == total) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 4,
                                ),
                                child: Text(
                                  k,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              );
                            }
                            total += 1;
                            final rowIndex = index - total;
                            if (rowIndex < list.length) {
                              final item = list[rowIndex];
                              final inDb = _localInDbStatus[item.phone];
                              final loading = !_localInDbStatus.containsKey(
                                item.phone,
                              );
                              return _ContactRow(
                                name: item.name,
                                phone: item.phone,
                                avatarColor: _avatarColor(item.name),
                                initial: _initial(item.name),
                                inDb: inDb,
                                loading: loading,
                                onInvite: () => widget.onInvite(item.phone),
                                onTap: () {
                                  if (inDb == true) {
                                    Navigator.pop(context, item.phone);
                                  }
                                },
                              );
                            }
                            total += list.length;
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      Positioned(
                        right: 4,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'
                                  .split('')
                                  .map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 1,
                                      ),
                                      child: Text(
                                        c,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String name;
  final String phone;
  final Color avatarColor;
  final String initial;
  final bool? inDb;
  final bool loading;
  final VoidCallback onInvite;
  final VoidCallback onTap;

  const _ContactRow({
    required this.name,
    required this.phone,
    required this.avatarColor,
    required this.initial,
    required this.inDb,
    required this.loading,
    required this.onInvite,
    required this.onTap,
  });

  String get _displayPhone {
    if (phone.startsWith('+966') && phone.length == 13) {
      final digits = phone.substring(4);
      return '+966 ${digits.substring(0, 2)} ${digits.substring(2, 5)} ${digits.substring(5)}';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final showInvite = inDb == false && !loading;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        _displayPhone,
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      ),
      trailing: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.kGreen,
              ),
            )
          : showInvite
          ? OutlinedButton(
              onPressed: onInvite,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.kGreen,
                side: const BorderSide(color: AppColors.kGreen),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Invite'),
            )
          : null,
      onTap: inDb == true ? onTap : null,
    );
  }
}
// MODELS
// ═════════════════════════════════════════════════════════════════════════════

class _VenueOption {
  const _VenueOption({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
  });
  final String id;
  final String name;
  final double? lat;
  final double? lng;
}

class _Friend {
  const _Friend({
    required this.id,
    required this.name,
    required this.phone,
    this.isFavorite = false,
  });
  final String id;
  final String name;
  final String phone;
  final bool isFavorite;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Friend &&
          runtimeType == other.runtimeType &&
          phone == other.phone;

  @override
  int get hashCode => phone.hashCode;
}

class _HostLocation {
  const _HostLocation({
    required this.latitude,
    required this.longitude,
    this.label = 'Set location',
  });
  final double latitude;
  final double longitude;
  final String label;

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'label': label,
  };
}

enum _ParticipantStatus { pending, accepted, declined }

class _Participant {
  const _Participant({required this.friend, required this.status});
  final _Friend friend;
  final _ParticipantStatus status;

  _Participant copyWith({_ParticipantStatus? status}) {
    return _Participant(friend: friend, status: status ?? this.status);
  }
}
