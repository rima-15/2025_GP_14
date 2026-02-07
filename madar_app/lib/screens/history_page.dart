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

class HistoryPage
    extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() =>
      _HistoryPageState();
}

class _HistoryPageState
    extends State<HistoryPage> {
  int _mainTabIndex = 0;
  int _trackingFilterIndex = 0;

  static const List<String> _mainTabs =
      ['Tracking', 'Meeting point'];
  static const List<String>
  _trackingFilters = [
    'Sent',
    'Received',
  ];

  /// Include 'cancelled' so Cancel/Stop Tracking requests show in history as Terminated.
  static const List<String>
  _historyStatuses = [
    'declined',
    'expired',
    'terminated',
    'completed',
    'cancelled',
  ];

  late final Stream<
    List<HistoryTrackingRequest>
  >
  _sentStream;
  late final Stream<
    List<HistoryTrackingRequest>
  >
  _receivedStream;

  @override
  void initState() {
    super.initState();
    _sentStream =
        _createSentHistoryStream();
    _receivedStream =
        _createReceivedHistoryStream();
    _markStaleRequestsOnLoad();
  }

  /// One-time: mark pending/accepted requests past endAt as expired/completed when opening History.
  void _markStaleRequestsOnLoad() {
    final uid = FirebaseAuth
        .instance
        .currentUser
        ?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    final col = FirebaseFirestore
        .instance
        .collection('trackRequests');
    col
        .where(
          'senderId',
          isEqualTo: uid,
        )
        .where(
          'status',
          whereIn: [
            'pending',
            'accepted',
          ],
        )
        .get()
        .then((snap) {
          for (final d in snap.docs) {
            final endAt =
                (d.data()['endAt']
                        as Timestamp?)
                    ?.toDate();
            if (endAt == null ||
                !endAt.isBefore(now))
              continue;
            final status =
                (d.data()['status'] ??
                        '')
                    .toString();
            col.doc(d.id).update({
              'status':
                  status == 'pending'
                  ? 'expired'
                  : 'completed',
            });
          }
        });
    col
        .where(
          'receiverId',
          isEqualTo: uid,
        )
        .where(
          'status',
          whereIn: [
            'pending',
            'accepted',
          ],
        )
        .get()
        .then((snap) {
          for (final d in snap.docs) {
            final endAt =
                (d.data()['endAt']
                        as Timestamp?)
                    ?.toDate();
            if (endAt == null ||
                !endAt.isBefore(now))
              continue;
            final status =
                (d.data()['status'] ??
                        '')
                    .toString();
            col.doc(d.id).update({
              'status':
                  status == 'pending'
                  ? 'expired'
                  : 'completed',
            });
          }
        });
  }

  Stream<List<HistoryTrackingRequest>>
  _createSentHistoryStream() {
    final uid = FirebaseAuth
        .instance
        .currentUser
        ?.uid;
    if (uid == null)
      return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('trackRequests')
        .where(
          'senderId',
          isEqualTo: uid,
        )
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .where(
                (d) => _historyStatuses
                    .contains(
                      (d.data()['status'] ??
                              '')
                          .toString(),
                    ),
              )
              .map(
                (d) =>
                    _docToHistoryRequest(
                      d,
                      isSent: true,
                    ),
              )
              .toList();
          list.sort(
            (a, b) => b.endAt.compareTo(
              a.endAt,
            ),
          );
          return list;
        })
        .handleError((e, st) {
          debugPrint(
            'History sent stream error: $e',
          );
        });
  }

  Stream<List<HistoryTrackingRequest>>
  _createReceivedHistoryStream() {
    final uid = FirebaseAuth
        .instance
        .currentUser
        ?.uid;
    if (uid == null)
      return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('trackRequests')
        .where(
          'receiverId',
          isEqualTo: uid,
        )
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .where(
                (d) => _historyStatuses
                    .contains(
                      (d.data()['status'] ??
                              '')
                          .toString(),
                    ),
              )
              .map(
                (d) =>
                    _docToHistoryRequest(
                      d,
                      isSent: false,
                    ),
              )
              .toList();
          list.sort(
            (a, b) => b.endAt.compareTo(
              a.endAt,
            ),
          );
          return list;
        })
        .handleError((e, st) {
          debugPrint(
            'History received stream error: $e',
          );
        });
  }

  HistoryTrackingRequest
  _docToHistoryRequest(
    QueryDocumentSnapshot<
      Map<String, dynamic>
    >
    d, {
    required bool isSent,
  }) {
    final data = d.data();
    final startAt =
        _parseTimestamp(
          data['startAt'],
        ) ??
        DateTime.now();
    final endAt =
        _parseTimestamp(
          data['endAt'],
        ) ??
        startAt;
    return HistoryTrackingRequest(
      id: d.id,
      status: (data['status'] ?? '')
          .toString(),
      startAt: startAt,
      endAt: endAt,
      startTime: DateFormat(
        'h:mm a',
      ).format(startAt),
      endTime: DateFormat(
        'h:mm a',
      ).format(endAt),
      venueName:
          (data['venueName'] ?? '')
              .toString(),
      otherUserName: isSent
          ? (data['receiverName'] ?? '')
                .toString()
          : (data['senderName'] ??
                    'Unknown')
                .toString(),
      otherUserPhone: isSent
          ? (data['receiverPhone'] ??
                    '')
                .toString()
          : (data['senderPhone'] ?? '')
                .toString(),
      isSent: isSent,
    );
  }

  DateTime? _parseTimestamp(
    dynamic value,
  ) {
    if (value == null) return null;
    if (value is Timestamp)
      return value.toDate();
    return null;
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );
    final target = DateTime(
      d.year,
      d.month,
      d.day,
    );
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
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.kGreen,
          ),
          onPressed: () =>
              Navigator.pop(context),
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
          preferredSize:
              const Size.fromHeight(52),
          child: Column(
            children: [
              _buildMainTabs(),
              Container(
                height: 1,
                color: Colors.black12,
              ),
            ],
          ),
        ),
      ),
      body: _mainTabIndex == 0
          ? _buildTrackingTab()
          : _buildMeetingPointTab(),
    );
  }

  Widget _buildMainTabs() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
      child: Row(
        children: List.generate(
          _mainTabs.length,
          (i) {
            final isSelected =
                _mainTabIndex == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(
                  () =>
                      _mainTabIndex = i,
                ),
                child: Column(
                  children: [
                    Text(
                      _mainTabs[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            FontWeight
                                .w600,
                        color:
                            isSelected
                            ? AppColors
                                  .kGreen
                            : Colors
                                  .grey,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color:
                            isSelected
                            ? AppColors
                                  .kGreen
                            : Colors
                                  .transparent,
                        borderRadius:
                            BorderRadius.circular(
                              1,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrackingTab() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding:
              const EdgeInsets.symmetric(
                horizontal: 16,
              ),
          child: _buildFilterPills(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child:
              _trackingFilterIndex == 0
              ? _buildHistoryList(
                  stream: _sentStream,
                )
              : _buildHistoryList(
                  stream:
                      _receivedStream,
                ),
        ),
      ],
    );
  }

  Widget _buildFilterPills() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius:
            BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(
          _trackingFilters.length,
          (i) {
            final isSelected =
                _trackingFilterIndex ==
                i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(
                  () =>
                      _trackingFilterIndex =
                          i,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors
                              .kGreen
                        : Colors
                              .transparent,
                    borderRadius:
                        BorderRadius.circular(
                          18,
                        ),
                  ),
                  alignment:
                      Alignment.center,
                  child: Text(
                    _trackingFilters[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          FontWeight
                              .w600,
                      color: isSelected
                          ? Colors.white
                          : Colors
                                .grey[600],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHistoryList({
    required Stream<
      List<HistoryTrackingRequest>
    >
    stream,
  }) {
    return StreamBuilder<
      List<HistoryTrackingRequest>
    >(
      key: ValueKey(
        _trackingFilterIndex,
      ),
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                    24.0,
                  ),
              child: Text(
                'Couldn\'t load history. Check your connection.',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color:
                      Colors.grey[600],
                  fontWeight:
                      FontWeight.w500,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState ==
                ConnectionState
                    .waiting &&
            !snapshot.hasData) {
          return const Center(
            child:
                CircularProgressIndicator(
                  color:
                      AppColors.kGreen,
                ),
          );
        }
        final list =
            snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              'No past requests',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          );
        }
        return ListView.builder(
          padding:
              const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24,
              ),
          itemCount: list.length,
          itemBuilder: (context, i) =>
              Padding(
                padding:
                    const EdgeInsets.only(
                      bottom: 12,
                    ),
                child:
                    _buildHistoryTile(
                      list[i],
                    ),
              ),
        );
      },
    );
  }

  Widget _buildHistoryTile(
    HistoryTrackingRequest r,
  ) {
    final dateStr = _formatDate(
      DateTime(
        r.startAt.year,
        r.startAt.month,
        r.startAt.day,
      ),
    );
    final durationStr =
        '$dateStr, ${r.startTime} - ${r.endTime}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration:
                      BoxDecoration(
                        color: Colors
                            .grey[200],
                        shape: BoxShape
                            .circle,
                      ),
                  child: Icon(
                    Icons.person,
                    color: Colors
                        .grey[600],
                    size: 22,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        r.otherUserName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight
                                  .w700,
                          color: Colors
                              .black87,
                        ),
                      ),
                      if (r
                          .otherUserPhone
                          .isNotEmpty)
                        Text(
                          r.otherUserPhone,
                          style: TextStyle(
                            fontSize:
                                13,
                            color: Colors
                                .grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                _historyStatusBadge(
                  r.status,
                ),
              ],
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors
                          .kGreen,
                      borderRadius:
                          BorderRadius.circular(
                            2,
                          ),
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          durationStr,
                          style: const TextStyle(
                            fontSize:
                                13,
                            fontWeight:
                                FontWeight
                                    .w500,
                            color: Colors
                                .black87,
                          ),
                        ),
                        const SizedBox(
                          height: 6,
                        ),
                        Text(
                          r.venueName.isEmpty
                              ? '—'
                              : r.venueName,
                          style: TextStyle(
                            fontSize:
                                13,
                            color: Colors
                                .grey[700],
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

  Widget _historyStatusBadge(
    String status,
  ) {
    Color bg;
    Color text;
    String label;
    switch (status) {
      case 'declined':
        bg = AppColors.kError
            .withOpacity(0.1);
        text = AppColors.kError;
        label = 'Declined';
        break;
      case 'expired':
        bg = Colors.grey.withOpacity(
          0.15,
        );
        text = Colors.grey[700]!;
        label = 'Expired';
        break;
      case 'terminated':
      case 'cancelled':
        bg = AppColors.kError
            .withOpacity(0.1);
        text = AppColors.kError;
        label = 'Terminated';
        break;
      case 'completed':
        bg = AppColors.kGreen
            .withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Completed';
        break;
      default:
        bg = Colors.grey.withOpacity(
          0.15,
        );
        text = Colors.grey[700]!;
        label = status.isEmpty
            ? '—'
            : status;
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            BorderRadius.circular(12),
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
    return Center(
      child: Text(
        'No meeting points Request',
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
