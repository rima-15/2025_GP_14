import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final List<NotificationItem> _trackNotifications = [
    // 1. Active track request
    NotificationItem(
      id: '1',
      type: NotificationType.trackRequest,
      title: 'Track Request',
      message: 'Sara Ali wants to track your location',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      isActive: true,
      senderName: 'Sara Ali',
      expiryTime: DateTime.now().add(const Duration(hours: 2)),
    ),
    // 2. Expired track request
    NotificationItem(
      id: '2',
      type: NotificationType.trackRequest,
      title: 'Track Request Expired',
      message: 'Track request from Mohammed Ahmed has expired',
      timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      isActive: false,
      senderName: 'Mohammed Ahmed',
    ),
    // 3. Request accepted
    NotificationItem(
      id: '3',
      type: NotificationType.trackAccepted,
      title: 'Request Accepted',
      message: 'Amal Ahmed accepted your track request',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      senderName: 'Amal Ahmed',
    ),
    // 4. Request rejected
    NotificationItem(
      id: '4',
      type: NotificationType.trackRejected,
      title: 'Request Rejected',
      message: '+966503359898 rejected your track request',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      senderName: '+966503359898',
    ),
    // 5. Location refresh request
    NotificationItem(
      id: '5',
      type: NotificationType.locationRefresh,
      title: 'Location Refresh',
      message: 'Sara Ali asked to refresh your location',
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      senderName: 'Sara Ali',
    ),
    // 6. Navigate request
    NotificationItem(
      id: '6',
      type: NotificationType.navigateRequest,
      title: 'Navigation Request',
      message: 'Sara Ali asked to navigate to you',
      timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      senderName: 'Sara Ali',
    ),
  ];

  final List<NotificationItem> _meetingPointNotifications = [
    // 1. Meeting point participation request
    NotificationItem(
      id: '7',
      type: NotificationType.meetingPointRequest,
      title: 'Meeting Point Invitation',
      message: 'Ali Mohammed invited you to join a meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
      senderName: 'Ali Mohammed',
    ),
    // 2. Location refresh in meeting point
    NotificationItem(
      id: '8',
      type: NotificationType.meetingLocationRefresh,
      title: 'Location Refresh',
      message: 'Sara Ali asked to refresh your location at meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
      senderName: 'Sara Ali',
    ),
    // 3. Active meeting point confirmation
    NotificationItem(
      id: '9',
      type: NotificationType.meetingPointConfirmation,
      title: 'Meeting Point Suggestion',
      message: 'Is the suggested meeting point good to continue?',
      timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      isActive: true,
      expiryTime: DateTime.now().add(const Duration(minutes: 2)),
    ),
    // 4. Expired meeting point confirmation
    NotificationItem(
      id: '10',
      type: NotificationType.meetingPointConfirmation,
      title: 'Meeting Point Accepted',
      message: 'Meeting point was automatically accepted',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      isActive: false,
    ),
    // 5. All participants arrived
    NotificationItem(
      id: '11',
      type: NotificationType.allArrived,
      title: 'Everyone Arrived!',
      message: 'All participants have arrived at the meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
    ),
    // 6. Participant cancelled
    NotificationItem(
      id: '12',
      type: NotificationType.participantCancelled,
      title: 'Participant Cancelled',
      message: 'Mohammed cancelled participating in the meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 40)),
      senderName: 'Mohammed',
    ),
    // 7. Participant accepted
    NotificationItem(
      id: '13',
      type: NotificationType.participantAccepted,
      title: 'Participant Joined',
      message: 'Adel accepted participating in this meeting point',
      timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
      senderName: 'Adel',
    ),
    // 8. Participant rejected
    NotificationItem(
      id: '14',
      type: NotificationType.participantRejected,
      title: 'Invitation Declined',
      message: 'Adel rejected participating in this meeting point',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      senderName: 'Adel',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
      body: ListView(
        children: [
          // Track Notifications Section
          if (_trackNotifications.isNotEmpty) ...[
            _buildSectionHeader('Track Notifications'),
            ..._trackNotifications.map(
              (notif) => _buildNotificationCard(notif),
            ),
          ],

          // Meeting Point Notifications Section
          if (_meetingPointNotifications.isNotEmpty) ...[
            _buildSectionHeader('Meeting Point Notifications'),
            ..._meetingPointNotifications.map(
              (notif) => _buildNotificationCard(notif),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ---------- Section Header ----------

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ---------- Notification Card ----------

  Widget _buildNotificationCard(NotificationItem notification) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: notification.isActive
              ? AppColors.kGreen.withOpacity(0.3)
              : Colors.grey.shade200,
          width: notification.isActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getNotificationColor(
                    notification.type,
                  ).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getNotificationIcon(notification.type),
                  color: _getNotificationColor(notification.type),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      _formatTimestamp(notification.timestamp),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (!notification.isActive &&
                  notification.type == NotificationType.trackRequest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Expired',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Message
          Text(
            notification.message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),

          // Timer for active confirmations
          if (notification.isActive &&
              notification.type == NotificationType.meetingPointConfirmation &&
              notification.expiryTime != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: Colors.orange[700]),
                const SizedBox(width: 6),
                Text(
                  'Auto-accept in ${_getTimeRemaining(notification.expiryTime!)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
          ],

          // Action Buttons
          if (_shouldShowActions(notification)) ...[
            const SizedBox(height: 16),
            _buildActionButtons(notification),
          ],
        ],
      ),
    );
  }

  // ---------- Action Buttons ----------

  Widget _buildActionButtons(NotificationItem notification) {
    switch (notification.type) {
      case NotificationType.trackRequest:
        if (notification.isActive) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleReject(notification),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.kError,
                    side: const BorderSide(color: AppColors.kError, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Reject',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleAccept(notification),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(fontWeight: FontWeight.w600),
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
        return ElevatedButton.icon(
          onPressed: () => _openCameraForScan(context),
          icon: const Icon(Icons.photo_camera_outlined, size: 20),
          label: const Text('Scan Surrounding'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.kGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );

      case NotificationType.meetingPointRequest:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _handleReject(notification),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kError,
                  side: const BorderSide(color: AppColors.kError, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Reject',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleAcceptMeetingPoint(notification),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Accept',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );

      case NotificationType.meetingPointConfirmation:
        if (notification.isActive) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleReject(notification),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.kError,
                    side: const BorderSide(color: AppColors.kError, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Reject',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleAccept(notification),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(fontWeight: FontWeight.w600),
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

  // ---------- Helper Functions ----------

  bool _shouldShowActions(NotificationItem notification) {
    // Don't show actions for expired/inactive notifications (except specific types)
    if (!notification.isActive &&
        notification.type != NotificationType.locationRefresh &&
        notification.type != NotificationType.navigateRequest &&
        notification.type != NotificationType.meetingLocationRefresh) {
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
      case NotificationType.trackAccepted:
      case NotificationType.trackRejected:
        return Icons.my_location;
      case NotificationType.locationRefresh:
        return Icons.refresh;
      case NotificationType.navigateRequest:
        return Icons.navigation;
      case NotificationType.meetingPointRequest:
      case NotificationType.meetingPointConfirmation:
        return Icons.place;
      case NotificationType.meetingLocationRefresh:
        return Icons.refresh;
      case NotificationType.allArrived:
        return Icons.check_circle_outline;
      case NotificationType.participantCancelled:
        return Icons.cancel_outlined;
      case NotificationType.participantAccepted:
        return Icons.person_add;
      case NotificationType.participantRejected:
        return Icons.person_remove;
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
      case NotificationType.meetingPointConfirmation:
        return Colors.orange;
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

  void _handleAccept(NotificationItem notification) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Accepted ${notification.title}'),
        backgroundColor: AppColors.kGreen,
      ),
    );
    // TODO: Implement actual accept logic
  }

  void _handleReject(NotificationItem notification) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Rejected ${notification.title}'),
        backgroundColor: AppColors.kError,
      ),
    );
    // TODO: Implement actual reject logic
  }

  void _handleAcceptMeetingPoint(NotificationItem notification) {
    // After accepting, show scan button
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Accepted! Please scan your surrounding to join the meeting point',
        ),
        backgroundColor: AppColors.kGreen,
        duration: Duration(seconds: 3),
      ),
    );

    // Open camera after a delay
    Future.delayed(const Duration(seconds: 1), () {
      _openCameraForScan(context);
    });
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
  final bool isActive;
  final String? senderName;
  final DateTime? expiryTime;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isActive = true,
    this.senderName,
    this.expiryTime,
  });
}
