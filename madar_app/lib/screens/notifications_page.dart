import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/gestures.dart'; // Required for TapGestureRecognizer
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
  final List<NotificationItem> _notifications = [
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
  ];

  bool _showAll = false;
  final List<String> _respondedNotifications = [];
  final Map<String, double> _notificationOffsets = {};

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

            String? actionLabel;
            bool isExpired = status == 'expired';
            if (status == 'accepted') actionLabel = 'Accepted';
            if (status == 'declined') actionLabel = 'Declined';

            return NotificationItem(
              id: doc.id,
              type: NotificationType.trackRequest,
              title: 'Track Request',
              message: '',
              timestamp: createdAt,
              isRead: status != 'pending',
              isExpired: isExpired,
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
        .collection('trackRequests')
        .where('senderId', isEqualTo: user.uid)
        .where('status', whereIn: ['accepted', 'declined'])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();

            final createdAt =
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final startAt = (d['startAt'] as Timestamp?)?.toDate();
            final endAt = (d['endAt'] as Timestamp?)?.toDate();

            return NotificationItem(
              id: doc.id,

              // 👇 نستخدم نفس الأنواع الموجودة عندك
              type: d['status'] == 'accepted'
                  ? NotificationType.trackAccepted
                  : NotificationType.trackRejected,

              title: d['status'] == 'accepted'
                  ? 'Track Request Accepted'
                  : 'Track Request Declined',

              message: '', // UI عندك ما يعتمد عليه

              timestamp: createdAt,
              isRead: false,

              // 👇 نخلي نفس الحقول اللي UI يستخدمها
              senderName: d['receiverName'], // أو اسم لو أضفتيه لاحقًا
              senderPhone: d['receiverPhone'],
              venueName: d['venueName'],

              date: startAt != null
                  ? DateFormat('EEE, MMM d').format(startAt)
                  : '',
              startTime: startAt != null
                  ? DateFormat('h:mm a').format(startAt)
                  : '',
              endTime: endAt != null ? DateFormat('h:mm a').format(endAt) : '',
            );
          }).toList();
        });
  }

  List<NotificationItem> get _visibleNotifications {
    if (_showAll) return _notifications;
    return _notifications.take(5).toList();
  }

  void _deleteNotification(NotificationItem notification) {
    setState(() {
      _notifications.remove(notification);
      _notificationOffsets.remove(notification.id);
    });
  }

  void _clearAllNotifications() async {
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
  }

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
      body: StreamBuilder<List<NotificationItem>>(
        stream: _incomingTrackRequestsStream(), // للمستقبل (pending)
        builder: (context, incomingSnap) {
          final incomingTrack = incomingSnap.data ?? [];

          return StreamBuilder<List<NotificationItem>>(
            stream: _senderResponsesStream(), // للمرسل (accepted/declined)
            builder: (context, senderSnap) {
              final senderResponses = senderSnap.data ?? [];

              // ✅ ندمج: incoming + senderResponses + mock
              final merged = [
                ...incomingTrack,
                ...senderResponses,
                ..._notifications,
              ];
              merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));

              final visible = _showAll ? merged : merged.take(5).toList();

              if (merged.isEmpty) return _buildEmptyState();

              return ListView(
                children: [
                  // Clear All Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 1, 10, 1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _clearAllNotifications,
                          child: Text(
                            'Clear all',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Notifications List
                  ...visible.map((notif) => _buildNotificationItem(notif)),

                  // View All Button
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

  Widget _buildNotificationItem(NotificationItem notification) {
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

                      if (confirmed) {
                        _deleteNotification(notification);
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
                Container(
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
                            child: Icon(
                              _getNotificationIcon(notification.type),
                              color: _getNotificationColor(notification.type),
                              size: 20,
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
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          notification.actionLabel ?? 'Expired',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[600],
                                          ),
                                        ),
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

                      // Message and Details for Track Request
                      if (notification.type ==
                          NotificationType.trackRequest) ...[
                        // STYLE 1: Incoming Track Request (The one with the green bar)
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
                                text: ' (${notification.senderPhone ?? ""}) ',
                              ),
                              const TextSpan(
                                text: 'is asking to track your location',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        IntrinsicHeight(
                          child: Row(
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
                                    Text(
                                      'Duration: ${notification.date} • ${notification.startTime} - ${notification.endTime}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Venue: ${notification.venueName ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (notification.type ==
                              NotificationType.trackRejected ||
                          notification.type ==
                              NotificationType.trackAccepted) ...[
                        // STYLE 2: Request Result (Matches your photo with more/less)
                        ExpandableNotificationBody(
                          text:
                              "${notification.senderName} (${notification.senderPhone ?? ""}) "
                              "${notification.type == NotificationType.trackRejected ? 'declined' : 'accepted'} "
                              "your track request at ${notification.venueName ?? 'Venue'} "
                              "on ${notification.date ?? ''} from ${notification.startTime ?? ''} "
                              "to ${notification.endTime ?? ''}.",
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

                // Unread indicator - INSIDE the white container
                if (!notification.isRead)
                  Positioned(
                    top: 18,
                    right: 18,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.kGreen,
                        shape: BoxShape.circle,
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

  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.trackRequest:
        return Icons.my_location_outlined;
      case NotificationType.trackAccepted:
        return Icons.check_circle_outline;
      case NotificationType.trackRejected:
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
      case NotificationType.allArrived:
        return AppColors.kGreen;
      case NotificationType.trackRejected:
      case NotificationType.participantRejected:
      case NotificationType.participantCancelled:
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

  // ---------- Action Handlers ----------

  void _handleAccept(NotificationItem notification) async {
    final confirmed = await ConfirmationDialog.showPositiveConfirmation(
      context,
      title: 'Accept Request',
      message: 'Are you sure you want to accept this request?',
      confirmText: 'Accept',
    );

    if (confirmed && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('trackRequests')
            .doc(notification.id)
            .update({'status': 'accepted'});

        setState(() {
          notification.actionLabel = "Accepted";
          notification.isRead = true;
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
            .update({'status': 'declined'});

        setState(() {
          notification.actionLabel = "Declined";
          notification.isRead = true;
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
