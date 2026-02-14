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
  bool _freezeReadUI = true; // نخليها true طول ما الصفحة مفتوحة
  Map<String, bool> _frozenReadMap = {};
  final Map<String, bool> _localReadOverride = {}; // للي تبينه يختفي فوراً

  // Read or Unread notifications
  @override
  void initState() {
    super.initState();

    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onOpenNotificationsPage();
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _onOpenNotificationsPage() async {
    await _freezeCurrentReadMap(); // 1) جمدي الحالة الحالية (قبل التحديث)
    await _markAllNotificationsAsRead(); // 2) حدّثي Firestore (بس UI ما يتغير)
    await NotificationService.clearAllSystemNotifications(); // 3) امسحي badge
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
      // اقرأها تلقائياً فقط إذا أنا المرسل
      if (type == 'trackStarted' && senderId == currentUid) {
        batch.update(doc.reference, {'isRead': true});
        continue;
      }

      // باقي الإشعارات اللي تحتاج أكشن
      if (requiresAction) continue;

      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
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

            final key = data['data']?['requestId']; // ✅ نفس notif.id
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
          onPressed: () => Navigator.pop(context),
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
              final readMap = notifSnap.data ?? {};

              return StreamBuilder<List<NotificationItem>>(
                stream: _incomingTrackRequestsStream(),
                builder: (context, incomingSnap) {
                  final incomingTrack = incomingSnap.data ?? [];

                  return StreamBuilder<List<NotificationItem>>(
                    stream: _senderResponsesStream(),
                    builder: (context, senderSnap) {
                      final senderResponses = senderSnap.data ?? [];

                      return StreamBuilder<List<NotificationItem>>(
                        stream: _trackStartedStream(),
                        builder: (context, trackStartedSnap) {
                          final trackStarted = trackStartedSnap.data ?? [];

                          return StreamBuilder<List<NotificationItem>>(
                            stream: _trackTerminatedStream(),
                            builder: (context, trackTerminatedSnap) {
                              final trackTerminated =
                                  trackTerminatedSnap.data ?? [];

                              return StreamBuilder<List<NotificationItem>>(
                                stream: _trackCompletedStream(),
                                builder: (context, trackCompletedSnap) {
                                  final trackCompleted =
                                      trackCompletedSnap.data ?? [];

                                  return StreamBuilder<List<NotificationItem>>(
                                    stream: _trackCancelledStream(),
                                    builder: (context, trackCancelledSnap) {
                                      final trackCancelled =
                                          trackCancelledSnap.data ?? [];

                                      if (!docMapSnap.hasData ||
                                          !notifSnap.hasData ||
                                          !incomingSnap.hasData ||
                                          !senderSnap.hasData ||
                                          !trackStartedSnap.hasData ||
                                          !trackTerminatedSnap.hasData ||
                                          !trackCompletedSnap.hasData ||
                                          !trackCancelledSnap.hasData) {
                                        return const SizedBox();
                                      }

                                      final trackRequestStatusById = {
                                        for (final n in incomingTrack)
                                          n.id: n.requestStatus ?? '',
                                      };

                                      final merged =
                                          [
                                                ...incomingTrack,
                                                ...senderResponses,
                                                ...trackStarted,
                                                ...trackTerminated,
                                                ...trackCompleted,
                                                ...trackCancelled,
                                              ]
                                              .where(
                                                (n) => notifDocMap.containsKey(
                                                  n.id,
                                                ),
                                              )
                                              .toList();

                                      merged.sort(
                                        (a, b) =>
                                            b.timestamp.compareTo(a.timestamp),
                                      );

                                      // ?? inject notificationDocId
                                      for (final n in merged) {
                                        n.notificationDocId = notifDocMap[n.id];

                                        // ?? ??? ?? ?? notification doc = ?????? ?????
                                        if (n.notificationDocId == null) {
                                          n.isRead = true;
                                        }
                                      }

                                      final visible = _showAll
                                          ? merged
                                          : merged.take(5).toList();

                                      if (merged.isEmpty)
                                        return _buildEmptyState();

                                      return ListView(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              1,
                                              10,
                                              1,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: const [],
                                            ),
                                          ),

                                          ...visible.map((notif) {
                                            final override =
                                                _localReadOverride[notif.id];

                                            notif.isRead =
                                                override ??
                                                (_freezeReadUI
                                                    ? (_frozenReadMap[notif
                                                              .id] ??
                                                          notif.isRead)
                                                    : (readMap[notif.id] ??
                                                          notif.isRead));

                                            return _buildNotificationItem(
                                              notif,
                                              trackRequestStatusById:
                                                  trackRequestStatusById,
                                            );
                                          }),

                                          if (!_showAll && merged.length > 5)
                                            Padding(
                                              padding: const EdgeInsets.all(5),
                                              child: TextButton(
                                                onPressed: () => setState(
                                                  () => _showAll = true,
                                                ),
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
    );
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

                                return OutlinedButton(
                                  onPressed: expired
                                      ? null
                                      : () async {
                                          // mark read
                                          if (notification.notificationDocId !=
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

                                          // لاحقًا تربطين set location
                                        },
                                  style: ButtonStyle(
                                    minimumSize:
                                        MaterialStateProperty.all<Size>(
                                          const Size(double.infinity, 40),
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
                                        borderRadius: BorderRadius.circular(8),
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
                                      Text('Set My Location'),
                                    ],
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
                                  Text(
                                    'Auto-accept in ${_getTimeRemaining(notification.autoAcceptTime!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.orange[700],
                                    ),
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

      case NotificationType.locationRefresh:
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
            InkWell(
              onTap: () => _handleAcceptMeetingPoint(notification),
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

    // Don't show actions for expired meeting confirmations
    if (notification.type == NotificationType.meetingPointConfirmation &&
        (notification.autoAcceptTime == null ||
            notification.autoAcceptTime!.isBefore(DateTime.now()))) {
      return false;
    }

    // Show actions for these types
    return [
      NotificationType.trackRequest,
      NotificationType.locationRefresh,
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

  /// Navigate to source: track request -> Received; accepted/declined -> Sent. Request expanded.
  void _onNotificationTap(NotificationItem notification) async {
    setState(() {
      _localReadOverride[notification.id] = true;
      notification.isRead = true;
    });

    // 🔥 أول شي: اعتبري الإشعار مقروء
    await _markNotificationAsReadByRequestId(notification.id);

    if (notification.type == NotificationType.trackRequest ||
        notification.type == NotificationType.trackAccepted ||
        notification.type == NotificationType.trackRejected) {
      // 0 = Received (incoming request), 1 = Sent (accepted/declined response)
      final filterIndex = notification.type == NotificationType.trackRequest
          ? 0
          : 1;

      Navigator.pop(context, {
        'tab': 2,
        'expandRequestId': notification.id,
        'filterIndex': filterIndex,
      });
    }

    // باقي الأنواع لاحقاً
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

    if (q.docs.isEmpty) return; // ما فيه notification مرتبطة بهذا الطلب

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
              'startNotifiedUsers': [], // ✅ أضيفي هذا السطر
            });

        await _markNotificationAsReadByRequestId(notification.id);

        setState(() {
          notification.actionLabel = "Accepted";
          notification.isRead = true;

          _localReadOverride[notification.id] = true; // 🔥 هذا المهم

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

  void _handleAcceptMeetingPoint(NotificationItem notification) async {
    final confirmed = await ConfirmationDialog.showPositiveConfirmation(
      context,
      title: 'Join Meeting Point',
      message: 'Do you want to join this meeting point and start scanning?',
      confirmText: 'Join',
    );

    if (confirmed && mounted) {
      setState(() {
        notification.actionLabel = "Accepted";
        notification.isRead = true; // Mark as read on interaction
        _respondedNotifications.add(notification.id);
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        _openCameraForScan(context);
      });
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
  trackStarted, // 🔥 أضيفي هذا هنا
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
  String? notificationDocId; // 🔥 جديد
  final String? trackRequestId;
  final String? requestStatus;
  final DateTime? endAt;
  final bool requiresAction;

  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  bool isRead;
  final bool isExpired;
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
    this.notificationDocId,
    this.trackRequestId,
    this.requestStatus,
    this.endAt,

    this.requiresAction = false,

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
