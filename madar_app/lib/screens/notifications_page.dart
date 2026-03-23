import 'dart:async';
import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/gestures.dart'; // Required for TapGestureRecognizer
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:madar_app/services/notification_service.dart';
import 'package:madar_app/screens/navigation_flow_complete.dart';
import 'package:madar_app/screens/create_meeting_point_form.dart';

// ----------------------------------------------------------------------------
// Notifications Page
// ----------------------------------------------------------------------------

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Mock notifications data
  /*final List<NotificationItem> _notifications = [
    // Track Request with full details

    // Location Refresh
    NotificationItem(
      id: '5',
      type: NotificationType.locationRefresh,
      title: 'Location Refresh',
      message: 'Sara Ali asked to refresh your location',
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      isRead: false,
      senderName: 'Sara Ali',
    ),
    // Navigate Request
    NotificationItem(
      id: '6',
      type: NotificationType.navigateRequest,
      title: 'Navigation Request',
      message: 'Sara Ali asked to navigate to you',
      timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      isRead: true,
      senderName: 'Sara Ali',
    ),
    // Meeting Point Request
    NotificationItem(
      id: '7',
      type: NotificationType.meetingPointRequest,
      title: 'Meeting Point Invitation',
      message: 'Ali Mohammed invited you to join a meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
      isRead: false,
      senderName: 'Ali Mohammed',
    ),
    // Meeting Location Refresh
    NotificationItem(
      id: '8',
      type: NotificationType.meetingLocationRefresh,
      title: 'Location Refresh',
      message: 'Sara Ali asked to refresh your location at meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
      isRead: true,
      senderName: 'Sara Ali',
    ),
    // Meeting Point Confirmation (Active)
    NotificationItem(
      id: '9',
      type: NotificationType.meetingPointConfirmation,
      title: 'Meeting Point Suggestion',
      message: 'Is the suggested meeting point good to continue?',
      timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      isRead: false,
      autoAcceptTime: DateTime.now().add(const Duration(minutes: 2)),
    ),
    // All Arrived
    NotificationItem(
      id: '10',
      type: NotificationType.allArrived,
      title: 'Everyone Arrived',
      message: 'All participants have arrived at the meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
      isRead: true,
    ),
    // Participant Cancelled
    NotificationItem(
      id: '11',
      type: NotificationType.participantCancelled,
      title: 'Participant Cancelled',
      message: 'Mohammed cancelled participating in the meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 40)),
      isRead: false,
      senderName: 'Mohammed',
    ),
    // Participant Accepted
    NotificationItem(
      id: '12',
      type: NotificationType.participantAccepted,
      title: 'Participant Joined',
      message: 'Adel accepted participating in this meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
      isRead: true,
      senderName: 'Adel',
    ),
    // Participant Rejected
    NotificationItem(
      id: '13',
      type: NotificationType.participantRejected,
      title: 'Invitation Declined',
      message: 'Adel declined participating in this meeting point',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      isRead: true,
      senderName: 'Adel',
    ),
  ];*/

  bool _showAll = false;
  final List<String> _respondedNotifications = [];
  final Map<String, double> _notificationOffsets = {};
  Timer? _uiRefreshTimer;
  Timer? _tickTimer;
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  bool _freezeReadUI = true; // Keep true while the page is open
  bool _initialFreezeReady = false;
  Map<String, bool> _frozenReadMap = {};
  bool _isRefreshing = false;
  bool _exitReadTriggered = false;
  bool _autoMarkRunning = false;
  final Set<String> _expiredActionDocIdsThisVisit = {};

  // Cache across page opens (app still alive)
  static List<NotificationItem> _cachedMerged = [];
  static bool _cacheReady = false;
  static String? _cacheUserId;
  final Map<String, bool> _localReadOverride =
      {}; // For items that should disappear immediately
  final Map<String, String> _localStatusOverride = {};

  // Read or Unread notifications
  @override
  void initState() {
    super.initState();
    _ensureCacheUser();
    _initialFreezeReady = false;

    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _tick.value++;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onOpenNotificationsPage();
    });
  }

  @override
  void dispose() {
    unawaited(_markReadOnExit());
    _uiRefreshTimer?.cancel();
    _tickTimer?.cancel();
    _tick.dispose();
    super.dispose();
  }

  void _ensureCacheUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_cacheUserId != uid) {
      _cacheUserId = uid;
      _cacheReady = false;
      _cachedMerged = [];
    }
  }

  Future<void> _markReadOnExit() async {
    if (_exitReadTriggered) return;
    _exitReadTriggered = true;
    await _markAllNotificationsAsRead();
    await _markExpiredActionsAsReadOnExit();
  }

  Future<void> _onOpenNotificationsPage() async {
    await _freezeCurrentReadMap(); // 1) Freeze current state (before update)
    await _markAllNotificationsAsRead(); // 2) Update Firestore (UI stays the same)
    await NotificationService.clearAllSystemNotifications(); // 3) Clear badge
  }

  Future<void> _freezeCurrentReadMap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .get();

    final Map<String, bool> map = {};

    for (final doc in snap.docs) {
      final data = doc.data();
      final requestId = data['data']?['requestId'];
      final isRead = data['isRead'] ?? false;
      if (requestId != null) map[requestId] = isRead;
    }

    if (!mounted) return;
    setState(() {
      _frozenReadMap = map;
      _freezeReadUI = true;
      _initialFreezeReady = true;
    });
  }

  Future<void> _markAllNotificationsAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = FirebaseFirestore.instance.batch();

    final unreadSnap = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in unreadSnap.docs) {
      final data = doc.data();

      final requiresAction = (data['requiresAction'] == true);
      final type = data['type'];
      final senderId = data['data']?['senderId'];
      final currentUid = user.uid;

      // trackStarted:
      // Auto-read only if I am the sender
      if (type == 'trackStarted' && senderId == currentUid) {
        batch.update(doc.reference, {'isRead': true});
        continue;
      }

      // Other notifications that require action
      if (requiresAction) continue;

      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  Future<void> _refreshNotifications() async {
    if (_isRefreshing) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isRefreshing = true);

    try {
      // Mark non-action notifications as read on pull-to-refresh
      await _markAllNotificationsAsRead();

      final results = await Future.wait([
        _notificationDocMap().first,
        _notificationsReadMap().first,
        _incomingTrackRequestsStream().first,
        _meetingPointRequestsStream().first,
        _senderResponsesStream().first,
        _trackStartedStream().first,
        _trackTerminatedStream().first,
        _trackCompletedStream().first,
        _trackCancelledStream().first,
        _locationRefreshStream().first,
      ]);

      final notifDocMap = results[0] as Map<String, String>;
      final readMap = results[1] as Map<String, bool>;
      final incomingTrack = results[2] as List<NotificationItem>;
      final meetingPointRequests = results[3] as List<NotificationItem>;
      final senderResponses = results[4] as List<NotificationItem>;
      final trackStarted = results[5] as List<NotificationItem>;
      final trackTerminated = results[6] as List<NotificationItem>;
      final trackCompleted = results[7] as List<NotificationItem>;
      final trackCancelled = results[8] as List<NotificationItem>;
      final locationRefresh = results[9] as List<NotificationItem>;

      final merged = _mergeNotifications(
        incomingTrack: incomingTrack,
        meetingPointRequests: meetingPointRequests,
        senderResponses: senderResponses,
        trackStarted: trackStarted,
        trackTerminated: trackTerminated,
        trackCompleted: trackCompleted,
        trackCancelled: trackCancelled,
        locationRefresh: locationRefresh,
        notifDocMap: notifDocMap,
      );

      _cachedMerged = merged;
      _cacheReady = true;
      _cacheUserId = user.uid;

      if (mounted) {
        final updatedReadMap = Map<String, bool>.from(readMap);
        for (final n in merged) {
          if (!n.requiresAction) {
            updatedReadMap[n.id] = true;
          }
        }
        setState(() {
          _isRefreshing = false;
          _frozenReadMap = updatedReadMap;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  //dot of notification
  Stream<Map<String, bool>> _notificationsReadMap() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snap) {
          final Map<String, bool> result = {};

          for (final doc in snap.docs) {
            final data = doc.data();

            final key = data['data']?['requestId']; // ? Same as notif.id
            final isRead = data['isRead'] ?? false;

            if (key != null) {
              result[key] = isRead;
            }
          }
          return result;
        });
  }

  Stream<Map<String, String>> _notificationDocMap() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final Map<String, String> map = {};
          for (final d in snap.docs) {
            final requestId = d.data()['data']?['requestId'];
            if (requestId != null) {
              map[requestId] = d.id; // 🔥 requestId → notificationDocId
            }
          }
          return map;
        });
  }

  Stream<List<NotificationItem>> _incomingTrackRequestsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('trackRequests')
        .where('receiverId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();

            final createdAt =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final startAt = (d['startAt'] as Timestamp?)?.toDate();
            final endAt = (d['endAt'] as Timestamp?)?.toDate();

            final dateStr = startAt != null
                ? DateFormat('EEE, MMM d').format(startAt)
                : '';
            final startStr = startAt != null
                ? DateFormat('h:mm a').format(startAt)
                : '';
            final endStr = endAt != null
                ? DateFormat('h:mm a').format(endAt)
                : '';

            final status = (d['status'] ?? 'pending').toString();
            final wasResponded = d['respondedAt'] != null;
            final isTimeExpired =
                endAt != null && DateTime.now().isAfter(endAt);
            final displayStatus =
                (status == 'completed' ||
                    status == 'terminated' ||
                    (status == 'cancelled' && wasResponded))
                ? 'accepted'
                : status;

            String? actionLabel;
            bool isExpired =
                displayStatus == 'expired' ||
                (status == 'pending' && isTimeExpired);
            if (displayStatus == 'accepted') actionLabel = 'Accepted';
            if (displayStatus == 'declined') actionLabel = 'Declined';
            if (displayStatus == 'cancelled') actionLabel = 'Cancelled';

            return NotificationItem(
              id: doc.id,

              type: NotificationType.trackRequest,
              title: 'Track Request',
              message: '',
              timestamp: createdAt,
              isRead: false,
              requiresAction: status == 'pending' && !isTimeExpired,
              isExpired: isExpired,
              requestStatus: status,
              endAt: endAt,
              senderName: (d['senderName'] ?? '').toString(),
              senderPhone: (d['senderPhone'] ?? '').toString(),
              venueName: (d['venueName'] ?? '').toString(),
              date: dateStr,
              startTime: startStr,
              endTime: endStr,
              actionLabel: actionLabel,
            );
          }).toList();
        });
  }

  Stream<List<NotificationItem>> _meetingPointRequestsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('type', isEqualTo: 'meetingPointRequest')
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();
            final ts =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final data = d['data'] as Map<String, dynamic>? ?? {};
            final meetingPointId =
                (data['meetingPointId'] ?? data['requestId'] ?? doc.id)
                    .toString();
            final requestStatus =
                (d['requestStatus'] ?? data['requestStatus'] ?? 'pending')
                    .toString()
                    .toLowerCase();
            final waitDeadline = (data['waitDeadline'] as Timestamp?)?.toDate();
            final isExpired =
                waitDeadline != null &&
                DateTime.now().isAfter(waitDeadline) &&
                requestStatus == 'pending';
            final requiresActionRaw =
                d['requiresAction'] ?? (requestStatus == 'pending');

            String? actionLabel;
            if (requestStatus == 'accepted') actionLabel = 'Accepted';
            if (requestStatus == 'declined') actionLabel = 'Declined';

            return NotificationItem(
              id: meetingPointId,
              notificationDocId: doc.id,
              type: NotificationType.meetingPointRequest,
              title: (d['title'] ?? 'Meeting Point Request').toString(),
              message: (d['body'] ?? '').toString(),
              timestamp: ts,
              isRead: d['isRead'] ?? false,
              actionTaken: d['actionTaken'] == true,
              requiresAction:
                  requiresActionRaw == true &&
                  !isExpired &&
                  actionLabel == null &&
                  requestStatus == 'pending',
              isExpired: isExpired,
              requestStatus: requestStatus,
              endAt: waitDeadline,
              senderId: (data['senderId'] ?? '').toString(),
              senderName: (data['senderName'] ?? '').toString(),
              senderPhone: (data['senderPhone'] ?? '').toString(),
              venueName: (data['venueName'] ?? '').toString(),
              actionLabel: actionLabel,
            );
          }).toList();
        });
  }

  Stream<List<NotificationItem>> _senderResponsesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('type', whereIn: ['trackAccepted', 'trackRejected'])
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();
            final ts =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final typeStr = (d['type'] ?? '').toString();
            final titleStr = (d['title'] ?? '').toString();

            return NotificationItem(
              id: d['data']?['requestId'] ?? doc.id,
              notificationDocId: doc.id,
              type: typeStr == 'trackAccepted'
                  ? NotificationType.trackAccepted
                  : NotificationType.trackRejected,
              title: titleStr.isNotEmpty
                  ? titleStr
                  : (typeStr == 'trackAccepted'
                        ? 'Track Request Accepted'
                        : 'Track Request Declined'),
              message: (d['body'] ?? '').toString(),
              timestamp: ts,
              isRead: d['isRead'] ?? false,
            );
          }).toList();
        });
  }

  Stream<List<NotificationItem>> _trackStartedStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('type', isEqualTo: 'trackStarted')
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();

            final ts =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

            return NotificationItem(
              id: d['data']?['requestId'],
              notificationDocId: doc.id,
              trackRequestId: d['data']?['trackRequestId'],
              type: NotificationType.trackStarted,
              title: d['title'] ?? 'Tracking Started',
              message: d['body'] ?? '',
              timestamp: ts,
              isRead: d['isRead'] ?? false,
              endAt: (d['data']?['endAt'] as Timestamp?)?.toDate(), // 🔥
              requiresAction: d['requiresAction'] == true, // 🔥
              actionTaken: d['actionTaken'] == true,
            );
          }).toList();
        });
  }

  Stream<List<NotificationItem>> _trackTerminatedStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('type', isEqualTo: 'trackTerminated')
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();

            final ts =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

            return NotificationItem(
              id: d['data']?['requestId'],
              notificationDocId: doc.id,
              trackRequestId: d['data']?['trackRequestId'],
              type: NotificationType.trackTerminated,
              title: d['title'] ?? 'Tracking Request Terminated',
              message: d['body'] ?? '',
              timestamp: ts,
              isRead: d['isRead'] ?? false,
              requiresAction: d['requiresAction'] == true,
            );
          }).toList();
        });
  }

  Stream<List<NotificationItem>> _trackCompletedStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('type', isEqualTo: 'trackCompleted')
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();

            final ts =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

            return NotificationItem(
              id: d['data']?['requestId'],
              notificationDocId: doc.id,
              trackRequestId: d['data']?['trackRequestId'],
              type: NotificationType.trackCompleted,
              title: d['title'] ?? 'Tracking Completed',
              message: d['body'] ?? '',
              timestamp: ts,
              isRead: d['isRead'] ?? false,
              requiresAction: d['requiresAction'] == true,
            );
          }).toList();
        });
  }

  Stream<List<NotificationItem>> _trackCancelledStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('type', isEqualTo: 'trackCancelled')
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();

            final ts =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

            return NotificationItem(
              id: d['data']?['requestId'],
              notificationDocId: doc.id,
              trackRequestId: d['data']?['trackRequestId'],
              type: NotificationType.trackCancelled,
              title: d['title'] ?? 'Tracking Request Cancelled',
              message: d['body'] ?? '',
              timestamp: ts,
              isRead: d['isRead'] ?? false,
              requiresAction: d['requiresAction'] == true,
            );
          }).toList();
        });
  }

  Stream<List<NotificationItem>> _locationRefreshStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('type', isEqualTo: 'locationRefresh')
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();
            final ts =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

            return NotificationItem(
              id: d['data']?['requestId'],
              notificationDocId: doc.id,
              trackRequestId: d['data']?['trackRequestId'],
              senderId: (d['data']?['senderId'] ?? '').toString(),
              isSystem: d['data']?['system'] == true || d['system'] == true,
              type: NotificationType.locationRefresh,
              title: d['title'] ?? 'Refresh Location Request',
              message: d['body'] ?? '',
              timestamp: ts,
              isRead: d['isRead'] ?? false,
              requiresAction: d['requiresAction'] == true,
              actionTaken: d['actionTaken'] == true,
              endAt: (d['data']?['endAt'] as Timestamp?)?.toDate(),
              senderName: d['data']?['senderName'],
              senderPhone: d['data']?['senderPhone'],
            );
          }).toList();
        });
  }

  /*List<NotificationItem> get _visibleNotifications {
    if (_showAll) return _notifications;
    return _notifications.take(5).toList();
  }
*/
  /*void _deleteNotification(NotificationItem notification) {
    setState(() {
      _notifications.remove(notification);
      _notificationOffsets.remove(notification.id);
    });
  }*/

  /* void _clearAllNotifications() async {
    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Clear All Notifications',
      message: 'Are you sure you want to clear all notifications?',
      confirmText: 'Clear All',
    );

    if (confirmed == true) {
      setState(() {
        _notifications.clear();
        _notificationOffsets.clear();
      });
    }
  }*/

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _markReadOnExit();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
            onPressed: () async {
              await _markReadOnExit();
              if (mounted) Navigator.pop(context);
            },
          ),
          title: const Text(
            'Notifications',
            style: TextStyle(
              color: AppColors.kGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.grey[300]),
          ),
        ),

        body: StreamBuilder<Map<String, String>>(
          stream: _notificationDocMap(), // 🔥 NEW
          builder: (context, docMapSnap) {
            final notifDocMap = docMapSnap.data ?? {};

            return StreamBuilder<Map<String, bool>>(
              stream: _notificationsReadMap(),
              builder: (context, notifSnap) {
                final readMap = notifSnap.data ?? _frozenReadMap;

                return StreamBuilder<List<NotificationItem>>(
                  stream: _incomingTrackRequestsStream(),
                  builder: (context, incomingSnap) {
                    final incomingTrack = incomingSnap.data ?? [];

                    return StreamBuilder<List<NotificationItem>>(
                      stream: _meetingPointRequestsStream(),
                      builder: (context, meetingSnap) {
                        final meetingPointRequests = meetingSnap.data ?? [];

                        return StreamBuilder<List<NotificationItem>>(
                          stream: _senderResponsesStream(),
                          builder: (context, senderSnap) {
                            final senderResponses = senderSnap.data ?? [];

                            return StreamBuilder<List<NotificationItem>>(
                              stream: _trackStartedStream(),
                              builder: (context, trackStartedSnap) {
                                final trackStarted =
                                    trackStartedSnap.data ?? [];

                                return StreamBuilder<List<NotificationItem>>(
                                  stream: _trackTerminatedStream(),
                                  builder: (context, trackTerminatedSnap) {
                                    final trackTerminated =
                                        trackTerminatedSnap.data ?? [];

                                    return StreamBuilder<
                                      List<NotificationItem>
                                    >(
                                      stream: _trackCompletedStream(),
                                      builder: (context, trackCompletedSnap) {
                                        final trackCompleted =
                                            trackCompletedSnap.data ?? [];

                                        return StreamBuilder<
                                          List<NotificationItem>
                                        >(
                                          stream: _trackCancelledStream(),
                                          builder: (context, trackCancelledSnap) {
                                            final trackCancelled =
                                                trackCancelledSnap.data ?? [];

                                            return StreamBuilder<
                                              List<NotificationItem>
                                            >(
                                              stream: _locationRefreshStream(),
                                              builder: (context, locationRefreshSnap) {
                                                final locationRefresh =
                                                    locationRefreshSnap.data ??
                                                    [];

                                                final hasAllData =
                                                    docMapSnap.hasData &&
                                                    notifSnap.hasData &&
                                                    incomingSnap.hasData &&
                                                    meetingSnap.hasData &&
                                                    senderSnap.hasData &&
                                                    trackStartedSnap.hasData &&
                                                    trackTerminatedSnap
                                                        .hasData &&
                                                    trackCompletedSnap
                                                        .hasData &&
                                                    trackCancelledSnap
                                                        .hasData &&
                                                    locationRefreshSnap.hasData;

                                                if (!hasAllData) {
                                                  if (_cacheReady &&
                                                      _initialFreezeReady) {
                                                    _applyDerivedStateForCache(
                                                      _cachedMerged,
                                                    );
                                                    return _buildNotificationsList(
                                                      merged: _cachedMerged,
                                                      readMap: readMap,
                                                    );
                                                  }
                                                  return _buildInitialLoader();
                                                }

                                                final merged =
                                                    _mergeNotifications(
                                                      incomingTrack:
                                                          incomingTrack,
                                                      meetingPointRequests:
                                                          meetingPointRequests,
                                                      senderResponses:
                                                          senderResponses,
                                                      trackStarted:
                                                          trackStarted,
                                                      trackTerminated:
                                                          trackTerminated,
                                                      trackCompleted:
                                                          trackCompleted,
                                                      trackCancelled:
                                                          trackCancelled,
                                                      locationRefresh:
                                                          locationRefresh,
                                                      notifDocMap: notifDocMap,
                                                    );

                                                _cachedMerged = merged;
                                                _cacheReady = true;

                                                return _buildNotificationsList(
                                                  merged: merged,
                                                  readMap: readMap,
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildInitialLoader() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.kGreen),
    );
  }

  List<NotificationItem> _mergeNotifications({
    required List<NotificationItem> incomingTrack,
    required List<NotificationItem> meetingPointRequests,
    required List<NotificationItem> senderResponses,
    required List<NotificationItem> trackStarted,
    required List<NotificationItem> trackTerminated,
    required List<NotificationItem> trackCompleted,
    required List<NotificationItem> trackCancelled,
    required List<NotificationItem> locationRefresh,
    required Map<String, String> notifDocMap,
  }) {
    final merged = [
      ...incomingTrack,
      ...meetingPointRequests,
      ...senderResponses,
      ...trackStarted,
      ...trackTerminated,
      ...trackCompleted,
      ...trackCancelled,
      ...locationRefresh,
    ].where((n) => notifDocMap.containsKey(n.id)).toList();

    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Inject notificationDocId
    for (final n in merged) {
      n.notificationDocId = notifDocMap[n.id];
      if (n.notificationDocId == null) {
        n.isRead = true;
      }
    }

    return merged;
  }

  void _applyDerivedStateForCache(List<NotificationItem> merged) {
    final now = DateTime.now();
    for (final n in merged) {
      if (n.type == NotificationType.trackRequest) {
        final status = (n.requestStatus ?? '').toLowerCase().trim();
        if (status == 'expired') {
          n.isExpired = true;
          continue;
        }
        if (status == 'pending' && n.endAt != null) {
          n.isExpired = now.isAfter(n.endAt!);
        }
      }
      if (n.type == NotificationType.meetingPointRequest) {
        final status = (n.requestStatus ?? '').toLowerCase().trim();
        if (status == 'expired') {
          n.isExpired = true;
          continue;
        }
        if (status == 'pending' && n.endAt != null) {
          n.isExpired = now.isAfter(n.endAt!);
        }
      }
    }
  }

  Map<String, String> _buildTrackRequestStatusMap(
    List<NotificationItem> merged,
  ) {
    final map = <String, String>{};
    for (final n in merged) {
      if (n.type == NotificationType.trackRequest) {
        map[n.id] = n.requestStatus ?? '';
      }
    }
    return map;
  }

  Widget _buildNotificationsList({
    required List<NotificationItem> merged,
    required Map<String, bool> readMap,
  }) {
    final now = DateTime.now();
    for (final n in merged) {
      if (n.type == NotificationType.trackRequest) {
        final status = (n.requestStatus ?? '').toLowerCase().trim();
        if (status == 'pending' && n.endAt != null) {
          n.isExpired = now.isAfter(n.endAt!);
        }
      }
      if (n.type == NotificationType.meetingPointRequest) {
        final status = (n.requestStatus ?? '').toLowerCase().trim();
        if (status == 'pending' && n.endAt != null) {
          n.isExpired = now.isAfter(n.endAt!);
        }
      }
    }

    final trackRequestStatusById = _buildTrackRequestStatusMap(merged);
    unawaited(_collectExpiredActionsForExit(merged, trackRequestStatusById));
    final visible = _showAll ? merged : merged.take(5).toList();
    for (final n in visible) {
      final overrideStatus = _localStatusOverride[n.id];
      if (overrideStatus != null &&
          (n.actionLabel == null || n.actionLabel!.isEmpty)) {
        n.actionLabel = overrideStatus == 'accepted' ? 'Accepted' : 'Declined';
      }
    }

    if (merged.isEmpty) {
      return RefreshIndicator(
        color: AppColors.kGreen,
        backgroundColor: Colors.white,
        onRefresh: _refreshNotifications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [const SizedBox(height: 120), _buildEmptyState()],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.kGreen,
      backgroundColor: Colors.white,
      onRefresh: _refreshNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 1, 10, 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [],
            ),
          ),
          ...visible.map((notif) {
            final override =
                _localReadOverride[notif.id] ??
                (notif.actionTaken ? true : null);

            notif.isRead =
                override ??
                (_freezeReadUI
                    ? (_frozenReadMap[notif.id] ?? notif.isRead)
                    : (readMap[notif.id] ?? notif.isRead));

            return _buildNotificationItem(
              notif,
              trackRequestStatusById: trackRequestStatusById,
            );
          }),
          if (!_showAll && merged.length > 5)
            Padding(
              padding: const EdgeInsets.all(5),
              child: TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: const Text(
                  'View All Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.kGreen,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  bool _isActionExpired(
    NotificationItem notification,
    Map<String, String> trackRequestStatusById,
  ) {
    if (notification.type == NotificationType.trackRequest) {
      final status = (notification.requestStatus ?? '').toLowerCase();
      final notPending = status.isNotEmpty && status != 'pending';
      return notification.isExpired || notPending;
    }

    if (notification.type == NotificationType.meetingPointRequest) {
      final status = (notification.requestStatus ?? '').toLowerCase();
      final notPending = status.isNotEmpty && status != 'pending';
      return notification.isExpired || notPending;
    }

    if (notification.type == NotificationType.trackStarted ||
        notification.type == NotificationType.locationRefresh) {
      final status = notification.trackRequestId == null
          ? null
          : trackRequestStatusById[notification.trackRequestId!];
      final endedByStatus =
          status == 'terminated' ||
          status == 'completed' ||
          status == 'cancelled' ||
          status == 'declined' ||
          status == 'expired';
      final endedByTime =
          notification.endAt != null &&
          DateTime.now().isAfter(notification.endAt!);
      return endedByStatus || endedByTime;
    }

    return false;
  }

  Future<void> _collectExpiredActionsForExit(
    List<NotificationItem> merged,
    Map<String, String> trackRequestStatusById,
  ) async {
    if (_autoMarkRunning) return;
    _autoMarkRunning = true;

    try {
      for (final n in merged) {
        final isActionType =
            n.type == NotificationType.trackRequest ||
            n.type == NotificationType.meetingPointRequest ||
            ((n.type == NotificationType.trackStarted ||
                    n.type == NotificationType.locationRefresh) &&
                n.requiresAction);
        if (!isActionType) continue;
        if (!_isActionExpired(n, trackRequestStatusById)) continue;
        final docId = n.notificationDocId;
        if (docId == null || docId.isEmpty) continue;
        _expiredActionDocIdsThisVisit.add(docId);
      }
    } finally {
      _autoMarkRunning = false;
    }
  }

  Future<void> _markExpiredActionsAsReadOnExit() async {
    if (_expiredActionDocIdsThisVisit.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final docId in _expiredActionDocIdsThisVisit) {
      batch.update(
        FirebaseFirestore.instance.collection('notifications').doc(docId),
        {'isRead': true},
      );
    }

    await batch.commit();
  }

  // ---------- Empty State ----------

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Notification Item ----------

  Widget _buildNotificationItem(
    NotificationItem notification, {
    required Map<String, String> trackRequestStatusById,
  }) {
    final currentOffset = _notificationOffsets[notification.id] ?? 0.0;
    final deleteButtonWidth = 70.0;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          final newOffset = currentOffset + details.delta.dx;
          _notificationOffsets[notification.id] = newOffset.clamp(
            -deleteButtonWidth,
            0.0,
          );
        });
      },
      onHorizontalDragEnd: (details) {
        setState(() {
          if (currentOffset < -deleteButtonWidth / 2) {
            _notificationOffsets[notification.id] = -deleteButtonWidth;
          } else {
            _notificationOffsets[notification.id] = 0.0;
          }
        });
      },
      child: Stack(
        children: [
          // Delete Button (background)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: deleteButtonWidth,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.kError,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      // Store the current swipe state before showing dialog
                      final wasSwiped = currentOffset != 0.0;

                      // Show confirmation dialog immediately
                      final confirmed = await _showDeleteConfirmation(
                        notification,
                      );

                      if (confirmed && notification.notificationDocId != null) {
                        await FirebaseFirestore.instance
                            .collection('notifications')
                            .doc(notification.notificationDocId!)
                            .delete();
                      } else {
                        // Only reset if it was swiped and user cancelled
                        if (wasSwiped && mounted) {
                          setState(() {
                            _notificationOffsets[notification.id] = 0.0;
                          });
                        }
                      }
                    },
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Main notification content (can be swiped) - WITH UNREAD INDICATOR
          AnimatedContainer(
            duration: const Duration(milliseconds: 100), // FASTER ANIMATION
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(
              _notificationOffsets[notification.id] ?? 0.0,
              0,
              0,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Stack(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _onNotificationTap(notification),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Row
                          Row(
                            children: [
                              // Circular Icon
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _getNotificationColor(
                                    notification.type,
                                  ).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: _buildNotificationIcon(
                                  notification.type,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Title and Time
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            notification.title,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        // Status Labels (Expired, Accepted, or Declined)
                                        if (notification.isExpired ||
                                            notification.actionLabel != null)
                                          _notificationStatusBadge(
                                            notification.isExpired
                                                ? 'expired'
                                                : (notification.actionLabel ??
                                                          '')
                                                      .toLowerCase(),
                                          ),
                                      ],
                                    ),

                                    const SizedBox(height: 2),
                                    Text(
                                      _formatTimestamp(notification.timestamp),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Message for Track Request: only "First name last name (phone) is asking to track your location"
                          if (notification.type ==
                              NotificationType.trackRequest) ...[
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                  height: 1.4,
                                ),
                                children: [
                                  TextSpan(
                                    text: notification.senderName ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        ' (${notification.senderPhone ?? ""}) ',
                                  ),
                                  const TextSpan(
                                    text: 'is asking to track your location',
                                  ),
                                ],
                              ),
                            ),
                          ] else if (notification.type ==
                              NotificationType.meetingPointRequest) ...[
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                  height: 1.4,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        (notification.senderName ?? '')
                                            .trim()
                                            .isNotEmpty
                                        ? notification.senderName!.trim()
                                        : 'Someone',
                                  ),
                                  const TextSpan(
                                    text:
                                        ' invites you to a shared meeting point',
                                  ),
                                ],
                              ),
                            ),
                          ] else if (notification.type ==
                                  NotificationType.trackRejected ||
                              notification.type ==
                                  NotificationType.trackAccepted) ...[
                            // Short: First Last (phone) accepted/declined your request
                            Text(
                              notification.message.trim().isNotEmpty
                                  ? notification.message.trim()
                                  : _formatAcceptDeclineMessage(notification),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                height: 1.4,
                              ),
                            ),
                          ] else ...[
                            // STYLE 3: All other simple notifications
                            Text(
                              notification.message,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (notification.type ==
                                  NotificationType.trackStarted &&
                              notification.requiresAction) ...[
                            const SizedBox(height: 12),

                            Builder(
                              builder: (_) {
                                final trackStatus =
                                    notification.trackRequestId == null
                                    ? null
                                    : trackRequestStatusById[notification
                                          .trackRequestId!];
                                final isTerminated =
                                    trackStatus == 'terminated';
                                final isCompleted = trackStatus == 'completed';
                                final expired =
                                    (notification.endAt != null &&
                                        DateTime.now().isAfter(
                                          notification.endAt!,
                                        )) ||
                                    isTerminated ||
                                    isCompleted;
                                final actionTaken = notification.actionTaken;
                                final disabled = expired || actionTaken;

                                return AbsorbPointer(
                                  absorbing: disabled,
                                  child: OutlinedButton(
                                    onPressed: disabled
                                        ? null
                                        : () async {
                                            // mark read
                                            if (notification
                                                    .notificationDocId !=
                                                null) {
                                              await FirebaseFirestore.instance
                                                  .collection('notifications')
                                                  .doc(
                                                    notification
                                                        .notificationDocId!,
                                                  )
                                                  .update({'isRead': true});
                                            }

                                            setState(() {
                                              notification.isRead = true;
                                              _localReadOverride[notification
                                                      .id] =
                                                  true;
                                            });

                                            await _openSetLocationForTracking(
                                              notification,
                                            );
                                          },
                                    style: ButtonStyle(
                                      minimumSize:
                                          MaterialStateProperty.all<Size>(
                                            const Size(double.infinity, 45),
                                          ),
                                      padding:
                                          MaterialStateProperty.all<EdgeInsets>(
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                          ),
                                      backgroundColor:
                                          MaterialStateProperty.resolveWith<
                                            Color
                                          >((states) {
                                            if (states.contains(
                                              MaterialState.disabled,
                                            )) {
                                              return Colors.grey[300]!;
                                            }
                                            return AppColors.kGreen;
                                          }),
                                      foregroundColor:
                                          MaterialStateProperty.resolveWith<
                                            Color
                                          >((states) {
                                            if (states.contains(
                                              MaterialState.disabled,
                                            )) {
                                              return Colors.grey[600]!;
                                            }
                                            return Colors.white;
                                          }),
                                      side:
                                          MaterialStateProperty.resolveWith<
                                            BorderSide
                                          >((states) {
                                            if (states.contains(
                                              MaterialState.disabled,
                                            )) {
                                              return BorderSide.none;
                                            }
                                            return BorderSide(
                                              color: AppColors.kGreen,
                                              width: 0,
                                            );
                                          }),
                                      shape: MaterialStateProperty.all(
                                        RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 22,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Set My Location',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          if (notification.type ==
                                  NotificationType.locationRefresh &&
                              notification.requiresAction) ...[
                            const SizedBox(height: 12),

                            Builder(
                              builder: (_) {
                                final trackStatus =
                                    notification.trackRequestId == null
                                    ? null
                                    : trackRequestStatusById[notification
                                          .trackRequestId!];
                                final isTerminated =
                                    trackStatus == 'terminated';
                                final isCompleted = trackStatus == 'completed';
                                final expired =
                                    (notification.endAt != null &&
                                        DateTime.now().isAfter(
                                          notification.endAt!,
                                        )) ||
                                    isTerminated ||
                                    isCompleted;
                                final actionTaken = notification.actionTaken;
                                final disabled = expired || actionTaken;

                                return AbsorbPointer(
                                  absorbing: disabled,
                                  child: OutlinedButton(
                                    onPressed: disabled
                                        ? null
                                        : () async {
                                            await _openSetLocationForTracking(
                                              notification,
                                              dialogTitle:
                                                  'Refresh My Location',
                                              dialogSubtitle:
                                                  'Choose how to refresh your location.',
                                            );
                                          },
                                    style: ButtonStyle(
                                      minimumSize:
                                          MaterialStateProperty.all<Size>(
                                            const Size(double.infinity, 45),
                                          ),
                                      padding:
                                          MaterialStateProperty.all<EdgeInsets>(
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                          ),
                                      backgroundColor:
                                          MaterialStateProperty.resolveWith<
                                            Color
                                          >((states) {
                                            if (states.contains(
                                              MaterialState.disabled,
                                            )) {
                                              return Colors.grey[300]!;
                                            }
                                            return AppColors.kGreen;
                                          }),
                                      foregroundColor:
                                          MaterialStateProperty.resolveWith<
                                            Color
                                          >((states) {
                                            if (states.contains(
                                              MaterialState.disabled,
                                            )) {
                                              return Colors.grey[600]!;
                                            }
                                            return Colors.white;
                                          }),
                                      side:
                                          MaterialStateProperty.resolveWith<
                                            BorderSide
                                          >((states) {
                                            if (states.contains(
                                              MaterialState.disabled,
                                            )) {
                                              return BorderSide.none;
                                            }
                                            return BorderSide(
                                              color: AppColors.kGreen,
                                              width: 0,
                                            );
                                          }),
                                      shape: MaterialStateProperty.all(
                                        RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 22,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Refresh My Location',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],

                          // Auto-accept timer
                          if (notification.autoAcceptTime != null &&
                              notification.autoAcceptTime!.isAfter(
                                DateTime.now(),
                              )) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 16,
                                    color: Colors.orange[700],
                                  ),
                                  const SizedBox(width: 6),
                                  ValueListenableBuilder<int>(
                                    valueListenable: _tick,
                                    builder: (context, _, __) {
                                      return Text(
                                        'Auto-accept in ${_getTimeRemaining(notification.autoAcceptTime!)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.orange[700],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Action Buttons
                          if (notification.actionLabel == null &&
                              _shouldShowActions(notification)) ...[
                            const SizedBox(height: 14),
                            _buildActionButtons(notification),
                          ] else if (_shouldShowActions(notification)) ...[
                            const SizedBox(height: 14),
                            _buildActionButtons(notification),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // GREEN UNREAD BAR (LEFT)
                if (!notification.isRead)
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: AppColors.kGreen,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                // Unread indicator - INSIDE the white container
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Action Buttons (Minimal Style) ----------

  Widget _buildActionButtons(NotificationItem notification) {
    switch (notification.type) {
      case NotificationType.trackRequest:
        if (!notification.isExpired) {
          return Row(
            children: [
              // Decline Button
              InkWell(
                onTap: () => _handleReject(notification),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 18, color: Colors.grey[700]),
                      const SizedBox(width: 6),
                      Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Accept Button
              InkWell(
                onTap: () => _handleAccept(notification),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 18, color: AppColors.kGreen),
                      SizedBox(width: 6),
                      Text(
                        'Accept',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.kGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        break;

      case NotificationType.navigateRequest:
      case NotificationType.meetingLocationRefresh:
        return InkWell(
          onTap: () => _openCameraForScan(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
                  color: AppColors.kGreen,
                ),
                SizedBox(width: 6),
                Text(
                  'Scan Surrounding',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.kGreen,
                  ),
                ),
              ],
            ),
          ),
        );

      case NotificationType.meetingPointRequest:
        return Row(
          children: [
            InkWell(
              onTap: () => _handleDeclineMeetingPointRequest(notification),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 18, color: Colors.grey[700]),
                    const SizedBox(width: 6),
                    Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _handleAcceptMeetingPointRequest(notification),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 18, color: AppColors.kGreen),
                    SizedBox(width: 6),
                    Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.kGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

      case NotificationType.meetingPointConfirmation:
        if (notification.autoAcceptTime != null &&
            notification.autoAcceptTime!.isAfter(DateTime.now())) {
          return Row(
            children: [
              InkWell(
                onTap: () => _handleReject(notification),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 18, color: Colors.grey[700]),
                      const SizedBox(width: 6),
                      Text(
                        'Reject',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _handleAccept(notification),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 18, color: AppColors.kGreen),
                      SizedBox(width: 6),
                      Text(
                        'Accept',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.kGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        break;

      default:
        break;
    }

    return const SizedBox.shrink();
  }

  // ---------- Delete Confirmation ----------

  Future<bool> _showDeleteConfirmation(NotificationItem notification) async {
    return await ConfirmationDialog.showDeleteConfirmation(
          context,
          title: 'Delete Notification',
          message: 'Are you sure you want to delete this notification?',
          confirmText: 'Delete',
        ) ??
        false;
  }

  // ---------- Helper Functions ----------

  bool _shouldShowActions(NotificationItem notification) {
    if (notification.actionTaken == true) {
      return false;
    }

    // Hide if already has a label or in responded list
    if (notification.actionLabel != null ||
        _respondedNotifications.contains(notification.id)) {
      return false;
    }

    // Don't show actions for expired track requests
    if (notification.type == NotificationType.trackRequest &&
        notification.isExpired) {
      return false;
    }

    // Don't show actions for expired meeting point requests
    if (notification.type == NotificationType.meetingPointRequest &&
        notification.isExpired) {
      return false;
    }

    if (notification.type == NotificationType.meetingPointRequest) {
      final status = (notification.requestStatus ?? '').toLowerCase();
      if (status.isNotEmpty && status != 'pending') {
        return false;
      }
    }

    // Don't show actions for expired meeting confirmations
    if (notification.type == NotificationType.meetingPointConfirmation &&
        (notification.autoAcceptTime == null ||
            notification.autoAcceptTime!.isBefore(DateTime.now()))) {
      return false;
    }

    // Show actions for these types
    return [
      NotificationType.trackRequest,
      NotificationType.navigateRequest,
      NotificationType.meetingPointRequest,
      NotificationType.meetingLocationRefresh,
      NotificationType.meetingPointConfirmation,
    ].contains(notification.type);
  }

  Widget _buildNotificationIcon(NotificationType type) {
    final color = _getNotificationColor(type);
    if (type == NotificationType.trackTerminated) {
      return Stack(
        alignment: Alignment.center,
        children: [
          // Icon(Icons.location_on, color: Colors.grey[400]!, size: 20),
          Icon(Icons.block, color: AppColors.kError.withOpacity(0.8), size: 22),
        ],
      );
    }

    return Icon(_getNotificationIcon(type), color: color, size: 20);
  }

  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.trackRequest:
        return Icons.my_location_outlined;
      case NotificationType.trackAccepted:
        return Icons.check_circle_outline;
      case NotificationType.trackRejected:
        return Icons.cancel_outlined;
      case NotificationType.trackStarted: //started
        return Icons.play_circle_outline;
      case NotificationType.trackCompleted:
        return Icons.check_circle_outline;
      case NotificationType.trackTerminated:
        return Icons.block;
      case NotificationType.trackCancelled:
        return Icons.cancel_outlined;

      case NotificationType.locationRefresh:
        return Icons.refresh;
      case NotificationType.navigateRequest:
        return Icons.navigation_outlined;
      case NotificationType.meetingPointRequest:
        return Icons.people_outline;
      case NotificationType.meetingPointConfirmation:
        return Icons.place_outlined;
      case NotificationType.meetingLocationRefresh:
        return Icons.refresh;
      case NotificationType.allArrived:
        return Icons.check_circle_outline;
      case NotificationType.participantCancelled:
        return Icons.cancel_outlined;
      case NotificationType.participantAccepted:
        return Icons.person_add_outlined;
      case NotificationType.participantRejected:
        return Icons.person_remove_outlined;
    }
  }

  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.trackAccepted:
      case NotificationType.participantAccepted:
      case NotificationType.trackStarted:
      case NotificationType.trackCompleted:
      case NotificationType.allArrived:
        return AppColors.kGreen;
      case NotificationType.trackRejected:
      case NotificationType.trackTerminated:
      case NotificationType.participantRejected:
      case NotificationType.participantCancelled:
        return AppColors.kError;
      case NotificationType.trackCancelled:
        return AppColors.kError;
      default:
        return AppColors.kGreen;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  String _getTimeRemaining(DateTime expiryTime) {
    final now = DateTime.now();
    final difference = expiryTime.difference(now);

    if (difference.isNegative) return '0m';

    if (difference.inMinutes < 1) {
      return '${difference.inSeconds}s';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    }
  }

  String _formatAcceptDeclineMessage(NotificationItem notification) {
    final name = notification.senderName?.isNotEmpty == true
        ? notification.senderName!
        : 'Someone';
    final phone = notification.senderPhone?.isNotEmpty == true
        ? ' (${notification.senderPhone})'
        : '';
    final action = notification.type == NotificationType.trackRejected
        ? 'declined'
        : 'accepted';
    return '$name$phone $action your request.';
  }

  bool _isSystemLocationRefresh(NotificationItem notification) {
    if (notification.isSystem) return true;
    final senderId = notification.senderId?.trim() ?? '';
    final hasSenderName = notification.senderName?.trim().isNotEmpty == true;
    final hasSenderPhone = notification.senderPhone?.trim().isNotEmpty == true;
    if (senderId.toLowerCase() == 'system') return true;
    if (senderId.isEmpty) {
      return !hasSenderName && !hasSenderPhone;
    }
    return false;
  }

  /// Navigate to source: track-related notification → Track page or History page
  /// based on the current request status.
  void _onNotificationTap(NotificationItem notification) async {
    setState(() {
      _localReadOverride[notification.id] = true;
      notification.isRead = true;
    });

    unawaited(_markNotificationAsReadByRequestId(notification.id));

    // System location refresh should not navigate on card tap.
    if (notification.type == NotificationType.locationRefresh &&
        _isSystemLocationRefresh(notification)) {
      return;
    }

    if (notification.type == NotificationType.meetingPointRequest) {
      final meeting = await _fetchMeetingPointForNotification(notification);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final status = (meeting?.status ?? '').toString().trim().toLowerCase();
      final isExpired =
          notification.isExpired ||
          (notification.endAt != null &&
              DateTime.now().isAfter(notification.endAt!));
      final isHost = uid != null && meeting?.isHost(uid) == true;
      // Pending (setup) and Active (confirmed) should open Track page.
      final isTrackStatus =
          status.isEmpty || status == 'pending' || status == 'active';
      // Use meeting status as the source of truth when available.
      final shouldOpenHistory = isExpired || !isTrackStatus;

      if (!mounted) return;
      if (meeting == null) {
        // Fallback: if meeting doc is missing, send to history.
        Navigator.pop(context, {
          'page': 'history',
          'meetingPointId': notification.id,
          'historyMainTabIndex': 1,
          'meetingFilterIndex': isHost ? 0 : 1,
        });
      } else if (shouldOpenHistory) {
        Navigator.pop(context, {
          'page': 'history',
          'meetingPointId': meeting.id,
          'historyMainTabIndex': 1,
          'meetingFilterIndex': isHost ? 0 : 1,
        });
      } else {
        Navigator.pop(context, {
          'page': 'track',
          'meetingPointId': notification.id,
          'openMeetingTab': true,
        });
      }
      return;
    }

    final hasTrackRequestId =
        notification.trackRequestId != null &&
        notification.trackRequestId!.trim().isNotEmpty;
    String requestId = notification.id;

    // Fallback filter by type
    int? filterIndex;
    switch (notification.type) {
      case NotificationType.trackRequest:
      case NotificationType.trackCancelled:
      case NotificationType.locationRefresh:
        filterIndex = 0; // Received
        break;
      case NotificationType.trackAccepted:
      case NotificationType.trackRejected:
      case NotificationType.trackStarted:
      case NotificationType.trackTerminated:
      case NotificationType.trackCompleted:
        filterIndex = 1; // Sent
        break;
      default:
        break;
    }

    // Decide destination based on real request status (cache-first)
    const historyStatuses = [
      'declined',
      'expired',
      'terminated',
      'completed',
      'cancelled',
    ];

    if (notification.type == NotificationType.trackRequest) {
      final rawStatus = (notification.requestStatus ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final endedByTime =
          notification.endAt != null &&
          DateTime.now().isAfter(notification.endAt!);
      final isHistory =
          historyStatuses.contains(rawStatus) ||
          notification.isExpired ||
          endedByTime;

      if (!mounted) return;
      Navigator.pop(context, {
        'page': isHistory ? 'history' : 'track',
        'tab': isHistory ? null : 2,
        'expandRequestId': notification.id,
        'filterIndex': filterIndex,
      });
      return;
    }

    final candidateIds = <String>[];
    if (hasTrackRequestId) {
      candidateIds.add(notification.trackRequestId!.trim());
    }
    candidateIds.add(notification.id);

    if (notification.notificationDocId != null) {
      final idsFromNotifDoc = await _fetchTrackRequestIdsFromNotificationDoc(
        notification.notificationDocId!,
      );
      for (final id in idsFromNotifDoc) {
        if (id.isNotEmpty && !candidateIds.contains(id)) {
          candidateIds.add(id);
        }
      }
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    Map<String, dynamic>? requestData;
    for (final id in candidateIds) {
      if (id.trim().isEmpty) continue;
      final lookup = await _lookupTrackRequestByAnyId(id);
      if (lookup != null) {
        requestId = lookup.id;
        requestData = lookup.data;
        break;
      }
    }

    if (requestData == null && candidateIds.isNotEmpty) {
      requestId = candidateIds.first;
    }

    if (uid != null && requestData != null) {
      final senderId = (requestData['senderId'] ?? '').toString().trim();
      final receiverId = (requestData['receiverId'] ?? '').toString().trim();
      if (senderId == uid) {
        filterIndex = 1; // Sent
      } else if (receiverId == uid) {
        filterIndex = 0; // Received
      }
    }

    if (filterIndex == null) return;

    final rawStatus =
        (requestData?['status'] ?? notification.requestStatus ?? '')
            .toString()
            .toLowerCase()
            .trim();
    final endedByTime =
        notification.endAt != null &&
        DateTime.now().isAfter(notification.endAt!);

    bool isHistory =
        notification.type == NotificationType.trackRejected ||
        notification.type == NotificationType.trackTerminated ||
        notification.type == NotificationType.trackCompleted ||
        notification.type == NotificationType.trackCancelled;

    if (rawStatus.isNotEmpty) {
      isHistory = isHistory || historyStatuses.contains(rawStatus);
    }
    if (!isHistory && (notification.isExpired || endedByTime)) {
      isHistory = true;
    }

    if (!mounted) return;

    Navigator.pop(context, {
      'page': isHistory ? 'history' : 'track',
      'tab': isHistory ? null : 2,
      'expandRequestId': requestId,
      'filterIndex': filterIndex,
    });
  }

  Future<Map<String, dynamic>?> _fetchTrackRequestDataCacheFirst(
    String requestId,
  ) async {
    try {
      final cached = await FirebaseFirestore.instance
          .collection('trackRequests')
          .doc(requestId)
          .get(const GetOptions(source: Source.cache));
      if (cached.data() != null) return cached.data();
    } catch (_) {}

    try {
      final doc = await FirebaseFirestore.instance
          .collection('trackRequests')
          .doc(requestId)
          .get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<_TrackRequestLookupResult?> _lookupTrackRequestByAnyId(
    String id,
  ) async {
    // 1) direct doc id (cache then server)
    final doc = await _fetchTrackRequestDataCacheFirst(id);
    if (doc != null) {
      return _TrackRequestLookupResult(id: id, data: doc);
    }

    // 2) by batchId
    final byBatch = await _fetchTrackRequestByFieldCacheFirst(
      field: 'batchId',
      value: id,
    );
    if (byBatch != null) return byBatch;

    // 3) by refreshRequestId (used in some flows)
    final byRefresh = await _fetchTrackRequestByFieldCacheFirst(
      field: 'refreshRequestId',
      value: id,
    );
    if (byRefresh != null) return byRefresh;

    return null;
  }

  Future<_TrackRequestLookupResult?> _fetchTrackRequestByFieldCacheFirst({
    required String field,
    required String value,
  }) async {
    try {
      final cached = await FirebaseFirestore.instance
          .collection('trackRequests')
          .where(field, isEqualTo: value)
          .limit(1)
          .get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        final d = cached.docs.first;
        return _TrackRequestLookupResult(id: d.id, data: d.data());
      }
    } catch (_) {}

    try {
      final snap = await FirebaseFirestore.instance
          .collection('trackRequests')
          .where(field, isEqualTo: value)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first;
        return _TrackRequestLookupResult(id: d.id, data: d.data());
      }
    } catch (_) {}

    return null;
  }

  Future<List<String>> _fetchTrackRequestIdsFromNotificationDoc(
    String notificationDocId,
  ) async {
    final ids = <String>[];
    void addId(dynamic value) {
      final id = value?.toString().trim() ?? '';
      if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }

    try {
      final cached = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationDocId)
          .get(const GetOptions(source: Source.cache));
      final data = cached.data();
      final inner = data?['data'] as Map<String, dynamic>?;
      addId(inner?['trackRequestId']);
      addId(inner?['requestId']);
      addId(inner?['batchId']);
      if (ids.isNotEmpty) return ids;
    } catch (_) {}

    try {
      final doc = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationDocId)
          .get();
      final data = doc.data();
      final inner = data?['data'] as Map<String, dynamic>?;
      addId(inner?['trackRequestId']);
      addId(inner?['requestId']);
      addId(inner?['batchId']);
      if (ids.isNotEmpty) return ids;
    } catch (_) {}

    return ids;
  }

  Future<void> _markNotificationAsReadByRequestId(String requestId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final q = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('data.requestId', isEqualTo: requestId)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return; // No notification linked to this request

    await q.docs.first.reference.update({'isRead': true});
  }

  /// Date only: strip day name if present (e.g. "Tue, Jan 31" -> "Jan 31").
  String _dateOnly(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    final comma = dateStr.indexOf(', ');
    return comma >= 0 ? dateStr.substring(comma + 2).trim() : dateStr;
  }

  static const TextStyle _acceptDialogLineStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Colors.black87,
  );

  Widget _acceptDialogLine(String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Text(value, style: _acceptDialogLineStyle);
  }

  /// Shows Accept Track Request dialog: "Are you sure..." + details with vertical green line (same as Request design).
  Future<bool> _showAcceptTrackRequestDialog(
    NotificationItem notification,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Accept Track Request',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to accept this tracking request?',
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 16),
              // Details with vertical green line (same as track page request design)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: AppColors.kGreen,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _acceptDialogLine(
                            notification.senderName != null &&
                                    notification.senderName!.isNotEmpty
                                ? (notification.senderPhone != null &&
                                          notification.senderPhone!.isNotEmpty
                                      ? '${notification.senderName} (${notification.senderPhone})'
                                      : notification.senderName!)
                                : null,
                          ),
                          if (notification.date != null &&
                              notification.startTime != null &&
                              notification.endTime != null) ...[
                            const SizedBox(height: 8),
                            _acceptDialogLine(
                              _dateOnly(notification.date) +
                                  ', ${notification.startTime} - ${notification.endTime}',
                            ),
                          ],
                          if (notification.venueName != null &&
                              notification.venueName!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _acceptDialogLine(notification.venueName),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.kGreen,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Accept',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
    return result ?? false;
  }

  // ---------- Action Handlers ----------

  void _handleAccept(NotificationItem notification) async {
    final confirmed = await _showAcceptTrackRequestDialog(notification);

    if (confirmed && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('trackRequests')
            .doc(notification.id)
            .update({
              'status': 'accepted',
              'respondedAt': FieldValue.serverTimestamp(),
              'startNotified': false,
              'startNotifiedUsers': [], // ? Add this line
            });

        await _markNotificationAsReadByRequestId(notification.id);

        setState(() {
          notification.actionLabel = "Accepted";
          notification.isRead = true;

          _localReadOverride[notification.id] = true; // ?? This is important

          _respondedNotifications.add(notification.id);
        });
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to accept: $e')));
      }
    }
  }

  void _handleReject(NotificationItem notification) async {
    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Decline Request',
      message: 'Are you sure you want to decline this request?',
      confirmText: 'Decline',
    );

    if (confirmed && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('trackRequests')
            .doc(notification.id)
            .update({
              'status': 'declined',
              'respondedAt': FieldValue.serverTimestamp(),
            });
        await _markNotificationAsReadByRequestId(notification.id);

        setState(() {
          notification.actionLabel = "Declined";
          notification.isRead = true;

          _localReadOverride[notification.id] = true; // 🔥

          _respondedNotifications.add(notification.id);
        });
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to decline: $e')));
      }
    }
  }

  Future<void> _handleAcceptMeetingPointRequest(
    NotificationItem notification,
  ) async {
    if (notification.isExpired) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This invitation has expired.')),
      );
      return;
    }

    final meeting = await _fetchMeetingPointForNotification(notification);
    if (meeting == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meeting point not found.')));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final me = meeting.participantFor(uid);
    if (me == null || me.isDeclined) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are not invited to this meeting.')),
      );
      return;
    }
    if (!me.isPending) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation already handled.')),
      );
      return;
    }

    final blocking =
        await MeetingPointService.getBlockingMeetingForCurrentUser();
    if (blocking != null && blocking.id != meeting.id) {
      if (!mounted) return;
      final proceed = await _showMeetingPointConflictDialog();
      if (!mounted || proceed != true) return;

      try {
        if (blocking.isHost(uid)) {
          await MeetingPointService.markHostDecision(
            meetingPointId: blocking.id,
            accepted: false,
          );
        } else {
          await MeetingPointService.respondToInvitation(
            meetingPointId: blocking.id,
            accepted: false,
          );
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final navChoice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildMeetingAcceptLocationChoiceSheet(ctx),
    );
    if (!mounted || navChoice == null) return;

    final locationResult = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetYourLocationDialog(
        shopName: meeting.venueName.isEmpty
            ? 'Meeting Point'
            : meeting.venueName,
        shopId: meeting.id,
        returnResultOnly: true,
        venueId: meeting.venueId.isEmpty ? null : meeting.venueId,
        headerTitle: 'Set your location',
      ),
    );
    if (!mounted || locationResult == null) return;

    try {
      await MeetingPointService.respondToInvitation(
        meetingPointId: meeting.id,
        accepted: true,
      );
      if (!mounted) return;
      SnackbarHelper.showSuccess(context, 'Invitation accepted.');
      await _updateMeetingPointNotificationStatus(notification, 'accepted');
      setState(() {
        notification.actionLabel = 'Accepted';
        notification.isRead = true;
        _localStatusOverride[notification.id] = 'accepted';
        _localReadOverride[notification.id] = true;
        _respondedNotifications.add(notification.id);
      });
    } catch (_) {
      if (!mounted) return;
      SnackbarHelper.showError(
        context,
        'Failed to accept invitation. Please try again.',
      );
    }
  }

  Future<void> _handleDeclineMeetingPointRequest(
    NotificationItem notification,
  ) async {
    if (notification.isExpired) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This invitation has expired.')),
      );
      return;
    }

    final meeting = await _fetchMeetingPointForNotification(notification);
    if (meeting == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meeting point not found.')));
      return;
    }

    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Decline Invitation',
      message:
          'Are you sure you want to decline this meeting point invitation?',
      confirmText: 'Decline',
    );
    if (confirmed != true) return;

    try {
      await MeetingPointService.respondToInvitation(
        meetingPointId: meeting.id,
        accepted: false,
      );
      if (!mounted) return;
      SnackbarHelper.showSuccess(context, 'Invitation declined.');
      await _updateMeetingPointNotificationStatus(notification, 'declined');
      setState(() {
        notification.actionLabel = 'Declined';
        notification.isRead = true;
        _localStatusOverride[notification.id] = 'declined';
        _localReadOverride[notification.id] = true;
        _respondedNotifications.add(notification.id);
      });
    } catch (_) {
      if (!mounted) return;
      SnackbarHelper.showError(
        context,
        'Failed to decline invitation. Please try again.',
      );
    }
  }

  Future<MeetingPointRecord?> _fetchMeetingPointForNotification(
    NotificationItem notification,
  ) async {
    final meetingPointId = notification.id.trim();
    if (meetingPointId.isEmpty) return null;
    try {
      return await MeetingPointService.getById(meetingPointId);
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _showMeetingPointConflictDialog() async {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Already in a Meeting Point',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: const Text(
          'You\'re already part of an active meeting point. '
          'Would you like to leave it and accept this new invitation instead?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Undo',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.kGreen,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Proceed',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Widget _buildMeetingAcceptLocationChoiceSheet(BuildContext ctx) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set your current location',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.kGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'As step 1, set your location to find suitable meeting point for all participants',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SecondaryButton(
              text: 'Pin on Map',
              icon: Icons.location_on_outlined,
              onPressed: () => Navigator.pop(ctx, 'map'),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: PrimaryButton(
              text: 'Scan With Camera',
              icon: Icons.camera_alt_outlined,
              onPressed: () => Navigator.pop(ctx, 'camera'),
            ),
          ),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 35),
        ],
      ),
    );
  }

  Future<void> _updateMeetingPointNotificationStatus(
    NotificationItem notification,
    String status,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final requestId = notification.id.trim();
    if (requestId.isEmpty) return;

    final updates = {'isRead': true, 'actionTaken': true};

    try {
      final batch = FirebaseFirestore.instance.batch();
      int matched = 0;

      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: 'meetingPointRequest')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final payload = data['data'] as Map<String, dynamic>? ?? {};
        final docRequestId =
            (payload['requestId'] ?? payload['meetingPointId'] ?? '')
                .toString();
        if (docRequestId != requestId) continue;
        batch.update(doc.reference, updates);
        matched++;
      }

      if (matched == 0) {
        final docId = notification.notificationDocId;
        if (docId != null && docId.trim().isNotEmpty) {
          batch.update(
            FirebaseFirestore.instance.collection('notifications').doc(docId),
            updates,
          );
          matched = 1;
        }
      }

      if (matched > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Failed to update meeting notification: $e');
    }
  }

  Future<void> _openCameraForScan(BuildContext context) async {
    final status = await Permission.camera.request();

    if (!context.mounted) return;

    if (status.isGranted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const UnityCameraPage(isNavigation: false),
        ),
      );
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is permanently denied. Please enable it from Settings.',
          ),
        ),
      );
      openAppSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required for AR scanning.'),
        ),
      );
    }
  }

  Future<void> _openSetLocationForTracking(
    NotificationItem notification, {
    String? dialogTitle,
    String? dialogSubtitle,
  }) async {
    final trackRequestId = notification.trackRequestId;
    if (trackRequestId == null || trackRequestId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking request not found.')),
      );
      return;
    }

    String venueId = '';
    String venueName = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('trackRequests')
          .doc(trackRequestId)
          .get();
      final data = doc.data();
      if (data != null) {
        venueId = (data['venueId'] ?? '').toString().trim();
        venueName = (data['venueName'] ?? '').toString().trim();
      }
    } catch (e) {
      debugPrint('Failed to load track request for location dialog: $e');
    }

    if (!mounted) return;

    final effectiveTitle =
        (dialogTitle != null && dialogTitle.trim().isNotEmpty)
        ? dialogTitle.trim()
        : 'Set My Location';
    final effectiveSubtitle =
        (dialogSubtitle != null && dialogSubtitle.trim().isNotEmpty)
        ? dialogSubtitle.trim()
        : 'Choose how to set your location.';

    showNavigationDialog(
      context,
      venueName.isNotEmpty ? venueName : 'Set Location',
      trackRequestId,
      returnResultOnly: true,
      dialogTitle: effectiveTitle,
      dialogSubtitle: effectiveSubtitle,
      venueId: venueId.isNotEmpty ? venueId : null,
      trackingNotificationId:
          (notification.notificationDocId ?? notification.id).trim().isNotEmpty
          ? (notification.notificationDocId ?? notification.id)
          : null,
    );
  }

  Widget _notificationStatusBadge(String status) {
    Color bg;
    Color text;
    String label;
    switch (status) {
      case 'accepted':
        bg = AppColors.kGreen.withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Accepted';
        break;
      case 'declined':
        bg = AppColors.kError.withOpacity(0.1);
        text = AppColors.kError;
        label = 'Declined';
        break;
      case 'expired':
        bg = Colors.grey.withOpacity(0.15);
        text = Colors.grey[700]!;
        label = 'Expired';
        break;
      case 'terminated':
        bg = AppColors.kError.withOpacity(0.1);
        text = AppColors.kError;
        label = 'Terminated';
        break;
      case 'cancelled':
        bg = Colors.grey.withOpacity(0.15);
        text = Colors.grey[700]!;
        label = 'Cancelled';
        break;
      case 'completed':
        bg = const Color.fromARGB(255, 12, 13, 10).withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Completed';
        break;
      default:
        bg = Colors.grey.withOpacity(0.15);
        text = Colors.grey[700]!;
        label = status.isEmpty ? '—' : status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Notification Models
// ----------------------------------------------------------------------------
class ExpandableNotificationBody extends StatefulWidget {
  final String text;
  const ExpandableNotificationBody({super.key, required this.text});

  @override
  State<ExpandableNotificationBody> createState() =>
      _ExpandableNotificationBodyState();
}

class _ExpandableNotificationBodyState
    extends State<ExpandableNotificationBody> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Style for the main body text
    final TextStyle bodyStyle = TextStyle(
      fontSize: 14,
      color: Colors.grey[700],
      height: 1.4,
    );

    // Style for the clickable link
    final TextStyle linkStyle = const TextStyle(
      color: Color.fromRGBO(97, 97, 97, 1),
      fontWeight: FontWeight.bold,
      fontSize: 13,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: isExpanded
                ? widget.text
                : (widget.text.length >
                          80 // Preliminary check for length
                      ? "${widget.text.substring(0, 80)}..."
                      : widget.text),
            style: bodyStyle,
          ),
          TextSpan(
            text: isExpanded ? " less" : " more",
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                setState(() {
                  isExpanded = !isExpanded;
                });
              },
          ),
        ],
      ),
      // This ensures that when NOT expanded, it cuts off at 2 lines
      maxLines: isExpanded ? null : 2,
      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
    );
  }
}

enum NotificationType {
  trackRequest,
  trackAccepted,
  trackRejected,
  trackStarted, // ?? Add this here
  trackTerminated,
  trackCompleted,
  trackCancelled,
  locationRefresh,
  navigateRequest,
  meetingPointRequest,
  meetingLocationRefresh,
  meetingPointConfirmation,
  allArrived,
  participantCancelled,
  participantAccepted,
  participantRejected,
}

class NotificationItem {
  final String id;
  final String? senderId;
  final bool isSystem;
  String? notificationDocId; // ?? New
  final String? trackRequestId;
  final String? requestStatus;
  final DateTime? endAt;
  final bool requiresAction;
  final bool actionTaken;

  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  bool isRead;
  bool isExpired;
  final String? senderName;
  final String? senderPhone;
  final String? venueName;
  final String? date;
  final String? startTime;
  final String? endTime;
  final DateTime? autoAcceptTime;
  String? actionLabel;

  NotificationItem({
    required this.id,
    this.senderId,
    this.isSystem = false,
    this.notificationDocId,
    this.trackRequestId,
    this.requestStatus,
    this.endAt,

    this.requiresAction = false,
    this.actionTaken = false,

    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = true,
    this.isExpired = false,
    this.senderName,
    this.senderPhone,
    this.venueName,
    this.date,
    this.startTime,
    this.endTime,
    this.autoAcceptTime,
    this.actionLabel,
  });
}

class _TrackRequestLookupResult {
  final String id;
  final Map<String, dynamic> data;

  _TrackRequestLookupResult({required this.id, required this.data});
}
