import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:madar_app/widgets/app_widgets.dart';

// ----------------------------------------------------------------------------
// History Page: Past requests in two tabs — Tracking & Meeting point
// ----------------------------------------------------------------------------

class HistoryTrackingRequest {
  final String id;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final String startTime;
  final String endTime;
  final String venueName;
  final String otherUserName;
  final String otherUserPhone;
  final bool isSent;

  HistoryTrackingRequest({
    required this.id,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.startTime,
    required this.endTime,
    required this.venueName,
    required this.otherUserName,
    required this.otherUserPhone,
    required this.isSent,
  });
}

class HistoryMeetingPointParticipant {
  final String userId;
  final String name;
  final String phone;

  HistoryMeetingPointParticipant({
    required this.userId,
    required this.name,
    required this.phone,
  });
}

class HistoryMeetingPoint {
  final String id;
  final String status;
  final String venueName;
  final String hostId;
  final String hostName;
  final String hostPhone;
  final bool isHost;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<HistoryMeetingPointParticipant> participants;

  HistoryMeetingPoint({
    required this.id,
    required this.status,
    required this.venueName,
    required this.hostId,
    required this.hostName,
    required this.hostPhone,
    required this.isHost,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
  });
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.initialFilterIndex,
    this.initialHighlightRequestId,
  });

  /// 0 = Sent, 1 = Received
  final int? initialFilterIndex;

  /// When set, scroll to and briefly highlight this request.
  final String? initialHighlightRequestId;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int _mainTabIndex = 0;
  int _trackingFilterIndex = 0;
  int _meetingFilterIndex = 0; // 0 = Sent (host), 1 = Received (participant)
  String? _highlightRequestId;
  final GlobalKey _highlightKey = GlobalKey();
  Timer? _highlightClearTimer;
  bool _highlightClearScheduled = false;
  final Set<String> _expandedCards = {};

  static const List<String> _mainTabs = ['Tracking', 'Meeting point'];
  static const List<String> _trackingFilters = ['Sent', 'Received'];

  /// Include 'cancelled' so Cancel/Stop Tracking requests show in history as Terminated.
  static const List<String> _historyStatuses = [
    'declined',
    'expired',
    'terminated',
    'completed',
    'cancelled',
  ];
  static const List<String> _meetingPointHistoryStatuses = [
    'cancelled',
    'completed',
    'active',
  ];

  late final Stream<List<HistoryTrackingRequest>> _sentStream;
  late final Stream<List<HistoryTrackingRequest>> _receivedStream;
  late final Stream<List<HistoryMeetingPoint>> _meetingPointHistoryStream;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilterIndex != null) {
      _trackingFilterIndex = widget.initialFilterIndex!;
    }
    _highlightRequestId = widget.initialHighlightRequestId;
    _sentStream = _createSentHistoryStream();
    _receivedStream = _createReceivedHistoryStream();
    _meetingPointHistoryStream = _createMeetingPointHistoryStream();
    _markStaleRequestsOnLoad();
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  /// One-time: mark pending/accepted requests past endAt as expired/completed when opening History.
  void _markStaleRequestsOnLoad() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    final col = FirebaseFirestore.instance.collection('trackRequests');
    col
        .where('senderId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .get()
        .then((snap) {
          for (final d in snap.docs) {
            final endAt = (d.data()['endAt'] as Timestamp?)?.toDate();
            if (endAt == null || !endAt.isBefore(now)) continue;
            final status = (d.data()['status'] ?? '').toString();
            col.doc(d.id).update({
              'status': status == 'pending' ? 'expired' : 'completed',
            });
          }
        });
    col
        .where('receiverId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .get()
        .then((snap) {
          for (final d in snap.docs) {
            final endAt = (d.data()['endAt'] as Timestamp?)?.toDate();
            if (endAt == null || !endAt.isBefore(now)) continue;
            final status = (d.data()['status'] ?? '').toString();
            col.doc(d.id).update({
              'status': status == 'pending' ? 'expired' : 'completed',
            });
          }
        });
  }

  Stream<List<HistoryTrackingRequest>> _createSentHistoryStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('trackRequests')
        .where('senderId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .where(
                (d) => _historyStatuses.contains(
                  (d.data()['status'] ?? '').toString(),
                ),
              )
              .map((d) => _docToHistoryRequest(d, isSent: true))
              .toList();
          list.sort((a, b) => b.endAt.compareTo(a.endAt));
          return list;
        })
        .handleError((e, st) {
          debugPrint('History sent stream error: $e');
        });
  }

  Stream<List<HistoryTrackingRequest>> _createReceivedHistoryStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('trackRequests')
        .where('receiverId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .where(
                (d) => _historyStatuses.contains(
                  (d.data()['status'] ?? '').toString(),
                ),
              )
              .map((d) => _docToHistoryRequest(d, isSent: false))
              .toList();
          list.sort((a, b) => b.endAt.compareTo(a.endAt));
          return list;
        })
        .handleError((e, st) {
          debugPrint('History received stream error: $e');
        });
  }

  HistoryTrackingRequest _docToHistoryRequest(
    QueryDocumentSnapshot<Map<String, dynamic>> d, {
    required bool isSent,
  }) {
    final data = d.data();
    final startAt = _parseTimestamp(data['startAt']) ?? DateTime.now();
    final endAt = _parseTimestamp(data['endAt']) ?? startAt;
    return HistoryTrackingRequest(
      id: d.id,
      status: (data['status'] ?? '').toString(),
      startAt: startAt,
      endAt: endAt,
      startTime: DateFormat('h:mm a').format(startAt),
      endTime: DateFormat('h:mm a').format(endAt),
      venueName: (data['venueName'] ?? '').toString(),
      otherUserName: isSent
          ? (data['receiverName'] ?? '').toString()
          : (data['senderName'] ?? 'Unknown').toString(),
      otherUserPhone: isSent
          ? (data['receiverPhone'] ?? '').toString()
          : (data['senderPhone'] ?? '').toString(),
      isSent: isSent,
    );
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    return null;
  }

  Stream<List<HistoryMeetingPoint>> _createMeetingPointHistoryStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('meetingPoints')
        .where('participantUserIds', arrayContains: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => _docToHistoryMeetingPoint(d, uid))
              .whereType<HistoryMeetingPoint>()
              .toList();
          list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return list;
        })
        .handleError((e, st) {
          debugPrint('Meeting point history stream error: $e');
        });
  }

  List<HistoryMeetingPointParticipant> _parseParticipants(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((p) {
          final userId = (p['userId'] ?? '').toString().trim();
          if (userId.isEmpty) return null;
          return HistoryMeetingPointParticipant(
            userId: userId,
            name: (p['name'] ?? '').toString(),
            phone: (p['phone'] ?? '').toString(),
          );
        })
        .whereType<HistoryMeetingPointParticipant>()
        .toList();
  }

  HistoryMeetingPoint? _docToHistoryMeetingPoint(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    String uid,
  ) {
    final data = d.data();
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final hostId = (data['hostId'] ?? '').toString();
    final venueName = (data['venueName'] ?? '').toString();
    final hostName = (data['hostName'] ?? '').toString();
    final hostPhone = (data['hostPhone'] ?? '').toString();
    final createdAt = _parseTimestamp(data['createdAt']) ?? DateTime.now();
    final updatedAt = _parseTimestamp(data['updatedAt']) ?? createdAt;
    final participants = _parseParticipants(data['participants']);

    // ── Still-pending meeting ─────────────────────────────────────────────
    // Only show in history for a participant who has already declined.
    if (status == 'pending') {
      if (hostId == uid) return null; // host still has an active meeting
      for (final p in participants) {
        if (p.userId == uid) {
          // participant found — only show if they declined
          return null; // still pending for this user (non-declined)
        }
      }
      // check raw for declined
      final rawParticipants = data['participants'];
      if (rawParticipants is List) {
        for (final p in rawParticipants) {
          if (p is Map) {
            final pUid = (p['userId'] ?? '').toString();
            if (pUid == uid) {
              final pStatus = (p['status'] ?? 'pending')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (pStatus == 'declined') {
                return HistoryMeetingPoint(
                  id: d.id,
                  status: 'declined',
                  venueName: venueName,
                  hostId: hostId,
                  hostName: hostName,
                  hostPhone: hostPhone,
                  isHost: false,
                  createdAt: createdAt,
                  updatedAt: updatedAt,
                  participants: participants,
                );
              }
              break;
            }
          }
        }
      }
      return null; // still pending for this user
    }

    // ── Terminal meeting ──────────────────────────────────────────────────
    if (!_meetingPointHistoryStatuses.contains(status)) return null;

    // For non-host participants, derive a personal display status.
    String displayStatus = status;
    if (hostId != uid) {
      final rawParticipants = data['participants'];
      if (rawParticipants is List) {
        for (final p in rawParticipants) {
          if (p is Map) {
            final pUid = (p['userId'] ?? '').toString();
            if (pUid == uid) {
              final pStatus = (p['status'] ?? 'pending')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (pStatus == 'pending') displayStatus = 'expired';
              if (pStatus == 'declined') displayStatus = 'declined';
              break;
            }
          }
        }
      }
    }

    return HistoryMeetingPoint(
      id: d.id,
      status: displayStatus,
      venueName: venueName,
      hostId: hostId,
      hostName: hostName,
      hostPhone: hostPhone,
      isHost: hostId == uid,
      createdAt: createdAt,
      updatedAt: updatedAt,
      participants: participants,
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    if (target == today) return 'Today';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatDateTime(DateTime d) {
    return DateFormat('d MMM yyyy, h:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Requests History',
          style: TextStyle(
            color: AppColors.kGreen,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Column(
            children: [
              _buildMainTabs(),
              Container(height: 1, color: Colors.black12),
            ],
          ),
        ),
      ),
      body: _mainTabIndex == 0 ? _buildTrackingTab() : _buildMeetingPointTab(),
    );
  }

  Widget _buildMainTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(_mainTabs.length, (i) {
          final isSelected = _mainTabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mainTabIndex = i),
              child: Column(
                children: [
                  Text(
                    _mainTabs[i],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.kGreen : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.kGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTrackingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildFilterPills(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _trackingFilterIndex == 0
              ? _buildHistoryList(stream: _sentStream)
              : _buildHistoryList(stream: _receivedStream),
        ),
      ],
    );
  }

  Widget _buildFilterPills() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_trackingFilters.length, (i) {
          final isSelected = _trackingFilterIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _trackingFilterIndex = i),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.kGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  _trackingFilters[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey[600],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHistoryList({
    required Stream<List<HistoryTrackingRequest>> stream,
  }) {
    return StreamBuilder<List<HistoryTrackingRequest>>(
      key: ValueKey(_trackingFilterIndex),
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Couldn\'t load history. Check your connection.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.kGreen),
          );
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              'No past requests',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }
        // Scroll to highlighted request on first build
        if (_highlightRequestId != null) {
          final targetIdx = list.indexWhere((r) => r.id == _highlightRequestId);
          if (targetIdx >= 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final ctx = _highlightKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(
                  ctx,
                  alignment: 0.15,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOutCubic,
                );
              }
            });
            if (!_highlightClearScheduled) {
              _highlightClearScheduled = true;
              _highlightClearTimer?.cancel();
              _highlightClearTimer = Timer(const Duration(seconds: 3), () {
                if (!mounted) return;
                setState(() {
                  _highlightRequestId = null;
                  _highlightClearScheduled = false;
                });
              });
            }
          }
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: list.length,
          itemBuilder: (context, i) => Padding(
            key: list[i].id == _highlightRequestId ? _highlightKey : null,
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildHistoryTile(list[i]),
          ),
        );
      },
    );
  }

  String _shortMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildHistoryTile(HistoryTrackingRequest r) {
    final isOvernight =
        r.endAt.day != r.startAt.day ||
        r.endAt.month != r.startAt.month ||
        r.endAt.year != r.startAt.year;

    final String dateStr;
    if (isOvernight) {
      final startDay = r.startAt.day;
      final endDay = r.endAt.day;
      final startMonth = _shortMonth(r.startAt.month);
      final endMonth = _shortMonth(r.endAt.month);
      dateStr = r.startAt.month == r.endAt.month
          ? '$startDay - $endDay $endMonth ${r.endAt.year}'
          : '$startDay $startMonth - $endDay $endMonth ${r.endAt.year}';
    } else {
      dateStr = _formatDate(
        DateTime(r.startAt.year, r.startAt.month, r.startAt.day),
      );
    }
    final timeStr = '${r.startTime} - ${r.endTime}';
    final userLabel = r.isSent ? 'Tracked User' : 'Sender';
    final isHighlighted = _highlightRequestId == r.id;

    return Container(
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppColors.kGreen.withOpacity(0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted ? AppColors.kGreen : Colors.grey.shade200,
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, color: Colors.grey[600], size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.otherUserName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      if (r.otherUserPhone.isNotEmpty)
                        Text(
                          r.otherUserPhone,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                _historyStatusBadge(r.status),
              ],
            ),
            const SizedBox(height: 12),
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
                        _labeledDetail(
                          '$userLabel: ',
                          r.otherUserPhone.isEmpty
                              ? r.otherUserName
                              : '${r.otherUserName} (${r.otherUserPhone})',
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _labeledDetail('Date: ', dateStr),
                            const SizedBox(width: 16),
                            _labeledDetail('Time: ', timeStr),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _labeledDetail(
                          'Venue: ',
                          r.venueName.isEmpty ? '—' : r.venueName,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledDetail(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.grey[600],
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyStatusBadge(String status) {
    Color bg;
    Color text;
    String label;
    switch (status) {
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
        bg = AppColors.kGreen.withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Completed';
        break;
      case 'active':
        bg = AppColors.kGreen.withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Active';
        break;
      case 'confirmed':
        bg = AppColors.kGreen.withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Active';
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

  Widget _buildMeetingPointTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildMeetingFilterPills(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<HistoryMeetingPoint>>(
            stream: _meetingPointHistoryStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Couldn\'t load meeting points history.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.kGreen),
                );
              }

              final allList = snapshot.data ?? [];
              final list = _meetingFilterIndex == 0
                  ? allList.where((m) => m.isHost).toList()
                  : allList.where((m) => !m.isHost).toList();

              if (list.isEmpty) {
                return Center(
                  child: Text(
                    'No past meeting points',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildMeetingPointTile(list[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMeetingFilterPills() {
    const filters = ['Sent', 'Received'];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(filters.length, (i) {
          final isSelected = _meetingFilterIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _meetingFilterIndex = i),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.kGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  filters[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey[600],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMeetingPointTile(HistoryMeetingPoint item) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isExpanded = _expandedCards.contains(item.id);

    // Participants list: exclude host (already shown in header)
    // Current user first, then others
    final nonHostParticipants = <HistoryMeetingPointParticipant>[];

    HistoryMeetingPointParticipant? currentUserEntry;
    for (final p in item.participants) {
      if (p.userId == uid && p.userId != item.hostId) {
        currentUserEntry = p;
        break;
      }
    }
    if (currentUserEntry != null) nonHostParticipants.add(currentUserEntry);

    for (final p in item.participants) {
      if (p.userId != item.hostId && p.userId != uid) {
        nonHostParticipants.add(p);
      }
    }

    const initialVisible = 3;
    final total = nonHostParticipants.length;
    final shownCount = isExpanded ? total : min(initialVisible, total);
    final othersCount = total - shownCount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: host person icon + name + Host(me)/Host + status ──
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, color: Colors.grey[600], size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.hostName.isEmpty ? 'Unknown' : item.hostName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.isHost ? 'Host (me)' : 'Host',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item.hostPhone.isNotEmpty)
                        Text(
                          item.hostPhone,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _historyStatusBadge(item.status),
              ],
            ),
            const SizedBox(height: 12),

            // ── Venue, date, participants ────────────────────────────────
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
                        _labeledDetail(
                          'Venue: ',
                          item.venueName.isEmpty ? '—' : item.venueName,
                        ),
                        const SizedBox(height: 4),
                        _labeledDetail(
                          'Date: ',
                          _formatDateTime(item.createdAt),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Participants:',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...nonHostParticipants
                            .take(shownCount)
                            .map(
                              (p) => _buildParticipantRow(
                                p,
                                isCurrentUser: p.userId == uid,
                              ),
                            ),
                        if (othersCount > 0 || isExpanded)
                          GestureDetector(
                            onTap: () => setState(() {
                              if (isExpanded) {
                                _expandedCards.remove(item.id);
                              } else {
                                _expandedCards.add(item.id);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                isExpanded
                                    ? 'Show less'
                                    : '+ $othersCount others participants',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.kGreen,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantRow(
    HistoryMeetingPointParticipant p, {
    bool isCurrentUser = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, color: Colors.grey[500], size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name.isEmpty ? 'Unknown' : p.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  if (p.phone.isNotEmpty)
                    Text(
                      p.phone,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
            if (isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Me',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
