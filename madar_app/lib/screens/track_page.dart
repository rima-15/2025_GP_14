import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show
        JavaScriptMessage,
        JavascriptChannel,
        WebViewController;
import 'track_request_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

const bool kFeatureEnabled = true;
const String kSolitaireVenueId =
    'ChIJcYTQDwDjLj4RZEiboV6gZzM';

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() =>
      _TrackPageState();
}

class _TrackPageState
    extends State<TrackPage> {
  bool _pendingPinApply = false;
  bool _isTrackingView = true;
  String _currentFloor = '';
  List<Map<String, String>> _venueMaps =
      [];
  bool _mapsLoading = false;
  String? _expandedRequestId;
  Timer? _clockTimer;
  // ===== Track Map (Pin JS) =====
  WebViewController?
  _trackMapController;

  Stream<List<TrackingRequest>>
  _sentRequestsStream() {
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
        .where(
          'status',
          whereIn: [
            'pending',
            'accepted',
          ],
        )
        .orderBy('startAt')
        .snapshots()
        .map((snap) {
          return snap.docs.map((d) {
            final data = d.data();

            final startAt =
                (data['startAt']
                        as Timestamp)
                    .toDate();
            final endAt =
                (data['endAt']
                        as Timestamp)
                    .toDate();

            final startStr =
                TimeOfDay.fromDateTime(
                  startAt,
                ).format(context);
            final endStr =
                TimeOfDay.fromDateTime(
                  endAt,
                ).format(context);

            return TrackingRequest(
              id: d.id,
              trackedUserName:
                  (data['receiverName'] ??
                          '')
                      .toString(),
              trackedUserPhone:
                  (data['receiverPhone'] ??
                          '')
                      .toString(),
              status:
                  (data['status'] ?? '')
                      .toString(),

              startAt: startAt,
              endAt: endAt,

              startTime: startStr,
              endTime: endStr,

              venueName:
                  (data['venueName'] ??
                          '')
                      .toString(),
              venueId:
                  (data['venueId'] ??
                          '')
                      .toString(),
              isFavorite: false,
              lastSeen: _timeAgo(
                startAt,
              ),
            );
          }).toList();
        });
  }

  List<TrackingRequest> _upcomingFrom(
    List<TrackingRequest> all,
  ) {
    final now = DateTime.now();

    final upcoming = all.where((r) {
      final start = r.startAt;
      final end = r.endAt;

      if (now.isAfter(end))
        return false;

      if (r.status != 'pending' &&
          r.status != 'accepted')
        return false;

      return now.isBefore(start);
    }).toList();

    upcoming.sort(
      (a, b) => a.startAt.compareTo(
        b.startAt,
      ),
    );
    return upcoming;
  }

  List<TrackingRequest> _activeFrom(
    List<TrackingRequest> all,
  ) {
    final now = DateTime.now();

    final active = all.where((r) {
      if (r.status != 'accepted')
        return false;

      final start = r.startAt;
      final end = r.endAt;

      return now.isAfter(start) &&
          now.isBefore(end);
    }).toList();

    active.sort(
      (a, b) => a.startAt.compareTo(
        b.startAt,
      ),
    );
    return active;
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now()
        .difference(dateTime);

    if (diff.inSeconds < 60)
      return 'Just now';
    if (diff.inMinutes < 60)
      return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  // =======================
  // [TRACK PIN JS] (NO TAP)
  // =======================
  String get _trackPinJs => r'''
function getViewer(){ return document.querySelector('model-viewer'); }

function ensurePin(viewer){
  let hs = viewer.querySelector('#trackedUserPin');
  if(!hs){
    hs = document.createElement('div');
    hs.id = 'trackedUserPin';
    hs.slot = 'hotspot-trackpin';
    hs.innerHTML = '<div style="font-size:34px">📍</div>';
    viewer.appendChild(hs);
  }
  return hs;
}

window.setTrackedPin = function(x,y,z){
  const viewer = getViewer();
  if(!viewer) return false;

  const hs = ensurePin(viewer);

  // force refresh: detach/attach
  if (hs.parentElement) {
    hs.parentElement.removeChild(hs);
    viewer.appendChild(hs);
  }

  hs.setAttribute('data-position', `${Number(x)} ${Number(y)} ${Number(z)}`);
  hs.setAttribute('data-normal', '0 1 0');

  viewer.requestUpdate();
  requestAnimationFrame(() => viewer.requestUpdate());
  return true;
};
window.setTrackedPinSafe = function(x,y,z){
  let t=0;
  const i=setInterval(()=>{
    t++;
    if(window.setTrackedPin(x,y,z) || t>20) clearInterval(i);
  },150);
};

window.hideTrackedPin = function(){
  const viewer = getViewer();
  if(!viewer) return false;
  const hs = viewer.querySelector('#trackedUserPin');
  if(hs) hs.style.display = 'none';
  return true;
};

window.showTrackedPin = function(){
  const viewer = getViewer();
  if(!viewer) return false;
  const hs = ensurePin(viewer);
  hs.style.display = 'block';
  viewer.requestUpdate();
  return true;
};

''';

  // Meeting point data
  final List<Participant>
  meetingParticipants = [
    Participant(
      name: 'Alex Chen',
      status: 'On the way',
      isHost: false,
    ),
    Participant(
      name: 'Sarah Kim',
      status: 'Arrived',
      isHost: false,
    ),
  ];
  final String currentUserName =
      'Ahmed Hassan';
  bool isArrived = false;

  // =======================
  // LIVE LOCATION (TRACKING)
  // =======================

  Map<String, double>?
  _trackedPos; // {x,y,z}
  String _trackedFloorLabel = '';
  StreamSubscription<DocumentSnapshot>?
  _liveLocSub;

  @override
  void initState() {
    super.initState();
    _loadVenueMaps();

    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
    _startLiveLocationTracking();
  }

  void _startLiveLocationTracking() {
    const docId =
        'demo_user'; // تأكدي Unity تكتب بنفس الـ docId بالضبط

    _liveLocSub = FirebaseFirestore
        .instance
        .collection('liveLocations')
        .doc(docId)
        .snapshots()
        .listen(
          (snap) {
            debugPrint(
              'LIVELOC: exists=${snap.exists} id=${snap.id}',
            );

            final data = snap.data();
            if (data == null) {
              debugPrint(
                'LIVELOC: data is null',
              );
              return;
            }

            debugPrint(
              'LIVELOC: data keys=${data.keys.toList()}',
            );

            final pos =
                data['blenderPosition'];
            if (pos is! Map) {
              debugPrint(
                'LIVELOC: blenderPosition is not a Map => $pos',
              );
              return;
            }

            debugPrint(
              'LIVELOC: pos=$pos',
            );

            final xRaw =
                (pos['x'] as num?)
                    ?.toDouble();
            final yRaw =
                (pos['y'] as num?)
                    ?.toDouble();
            final zRaw =
                (pos['z'] as num?)
                    ?.toDouble();

            if (xRaw == null ||
                yRaw == null ||
                zRaw == null) {
              debugPrint(
                'LIVELOC: null axis values x=$xRaw y=$yRaw z=$zRaw',
              );
              return;
            }

            // ✅ هنا انعكاس الاكس
            final x = xRaw;
            final y = yRaw;
            final z = zRaw;

            final floor =
                data['floor']
                    ?.toString() ??
                '';
            debugPrint(
              'LIVELOC: final(x,y,z)=($x,$y,$z) floor=$floor',
            );

            setState(() {
              _trackedPos = {
                'x': x,
                'y': y,
                'z': z,
              };
              _trackedFloorLabel =
                  floor;
            });

            _applyTrackedPinToViewer();
          },
          onError: (e) {
            debugPrint(
              'LIVELOC: ERROR $e',
            );
          },
        );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _liveLocSub?.cancel();
    super.dispose();
  }

  void _toggleExpand(String requestId) {
    setState(() {
      _expandedRequestId =
          _expandedRequestId ==
              requestId
          ? null
          : requestId;
    });
  }

  void _toggleFavorite(
    String requestId,
  ) {
    // TODO: implement favorites later using Firestore (users/{uid}/favorites)
    // keeping it here to avoid UI changes/errors.
    /*setState(() {
      final index = _trackingRequests.indexWhere((r) => r.id == requestId);
      if (index != -1) {
        _trackingRequests[index].isFavorite =
            !_trackingRequests[index].isFavorite;
      }
    });*/
  }

  Future<void> _loadVenueMaps() async {
    setState(() => _mapsLoading = true);
    try {
      final doc =
          await FirebaseFirestore
              .instance
              .collection('venues')
              .doc(kSolitaireVenueId)
              .get(
                const GetOptions(
                  source: Source
                      .serverAndCache,
                ),
              )
              .timeout(
                const Duration(
                  seconds: 10,
                ),
              );

      final data = doc.data();
      if (data != null &&
          data['map'] is List) {
        final maps =
            (data['map'] as List)
                .cast<
                  Map<String, dynamic>
                >();
        final convertedMaps = maps.map((
          map,
        ) {
          return {
            'floorNumber':
                (map['floorNumber'] ??
                        '')
                    .toString(),
            'mapURL':
                (map['mapURL'] ?? '')
                    .toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            if (convertedMaps
                .isNotEmpty) {
              final firstValid =
                  convertedMaps.firstWhere(
                    (m) =>
                        (m['mapURL'] ??
                                '')
                            .toString()
                            .trim()
                            .isNotEmpty,
                    orElse: () =>
                        const {
                          'mapURL': '',
                        },
                  );

              _currentFloor =
                  (firstValid['mapURL'] ??
                          '')
                      .toString();
            }
          });
        }
      } else {
        _useFallbackMaps();
      }
    } catch (e) {
      _useFallbackMaps();
    } finally {
      if (mounted)
        setState(
          () => _mapsLoading = false,
        );
    }
    _pendingPinApply = true;
  }

  int? _parseFloorToIndex(
    String floorRaw,
  ) {
    final s = floorRaw
        .trim()
        .toUpperCase();
    if (s.isEmpty) return null;

    // "1", "2"
    final n1 = int.tryParse(s);
    if (n1 != null) return n1 - 1;

    // "F1", "F2"
    final m = RegExp(
      r'(\d+)',
    ).firstMatch(s);
    if (m != null)
      return int.parse(m.group(1)!) - 1;

    if (s == 'GF' ||
        s == 'G' ||
        s == 'GROUND')
      return 0;
    return null;
  }

  String _currentFloorLabel() {
    final m = _venueMaps.firstWhere(
      (x) =>
          (x['mapURL'] ?? '') ==
          _currentFloor,
      orElse: () => const {
        'floorNumber': '',
      },
    );
    return (m['floorNumber'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
  }

  /// يحول floor القادم من Unity/Firestore (1/2 أو "F1") إلى label قريب من الموجود عندك (GF/F1)
  String _normalizeTrackedFloorLabel(
    String raw,
  ) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';

    final n = int.tryParse(s);
    if (n != null) {
      // ✅ mapping حسب أزرارك GF / F1
      if (n == 1) return 'GF';
      if (n == 2) return 'F1';
      return 'F$n';
    }

    return s; // لو جا "GF" أو "F1"
  }

  bool _floorsMatch(
    String trackedRaw,
    String currentLabel,
  ) {
    final tracked =
        _normalizeTrackedFloorLabel(
          trackedRaw,
        ); // "F1"
    final cur = currentLabel
        .trim()
        .toUpperCase(); // "GF" or "F1"

    if (tracked.isEmpty || cur.isEmpty)
      return true; // إذا ما نعرف، لا نخفي البن

    // لو current هو GF، لا يطابق F1 (واضح)
    // لو current هو F1 يطابق tracked F1
    if (cur == tracked) return true;

    // fallback ذكي: إذا current يحتوي نفس الرقم (مثلاً F1)
    final tNum = RegExp(
      r'\d+',
    ).firstMatch(tracked)?.group(0);
    if (tNum != null &&
        cur.contains(tNum))
      return true;

    return false;
  }

  void _applyTrackedPinToViewer() {
    // 1) ما عندنا إحداثيات؟ نخفي البن
    if (_trackedPos == null) {
      _pendingPinApply = false;
      _trackMapController
          ?.runJavaScript(
            'hideTrackedPin();',
          );
      return;
    }

    // 2) الكنترولر مو جاهز؟ انتظري
    if (_trackMapController == null) {
      _pendingPinApply = true;
      return;
    }

    // 3) تحقق من الدور
    final currentLabel =
        _currentFloorLabel();
    final ok = _floorsMatch(
      _trackedFloorLabel,
      currentLabel,
    );

    if (!ok) {
      _pendingPinApply = false;
      _trackMapController!
          .runJavaScript(
            'hideTrackedPin();',
          );
      return;
    }

    // 4) الإحداثيات (مع عكس X)
    final double xRaw =
        (_trackedPos!['x'] ?? 0)
            .toDouble();
    final double x =
        -xRaw; // ❗️نعكس X هنا
    final double y =
        (_trackedPos!['y'] ?? 0)
            .toDouble();
    final double z =
        (_trackedPos!['z'] ?? 0)
            .toDouble();

    _pendingPinApply = false;

    // 5) ⬅️⬅️⬅️ هنا مكان السطرين اللي سألتي عنهم
    _trackMapController!.runJavaScript(
      'showTrackedPin();',
    );
    _trackMapController!.runJavaScript(
      'setTrackedPinSafe($x,$y,$z);',
    );
  }

  void _useFallbackMaps() {
    final fallback = [
      {
        'floorNumber': 'GF',
        'mapURL':
            'https://firebasestorage.googleapis.com/v0/b/madar-database.firebasestorage.app/o/3D%20Maps%2FSolitaire%2FGF.glb?alt=media',
      },
      {
        'floorNumber': 'F1',
        'mapURL':
            'https://firebasestorage.googleapis.com/v0/b/madar-database.firebasestorage.app/o/3D%20Maps%2FSolitaire%2FF1.glb?alt=media',
      },
    ];
    if (mounted) {
      setState(() {
        _venueMaps = fallback;
        _currentFloor =
            fallback.first['mapURL'] ??
            '';
      });
    }
  }

  void _showTrackRequestDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent,
      builder: (context) =>
          const TrackRequestDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: kFeatureEnabled
            ? _buildFullContent()
            : _buildComingSoon(),
      ),
    );
  }

  Widget _buildComingSoon() {
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons.construction,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          Text(
            'Coming Soon',
            style: TextStyle(
              fontSize: 24,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildViewToggle(),
        const SizedBox(height: 20),
        _buildMapPreview(),
        const SizedBox(height: 16),

        if (_isTrackingView) ...[
          _buildTrackRequestButton(),
          const SizedBox(height: 24),

          StreamBuilder<
            List<TrackingRequest>
          >(
            stream:
                _sentRequestsStream(),
            builder: (context, snapshot) {
              final all =
                  snapshot.data ?? [];
              final upcoming =
                  _upcomingFrom(all);
              final active =
                  _activeFrom(all);

              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  // -------- Upcoming (always visible) --------
                  _buildSectionHeader(
                    icon:
                        Icons.schedule,
                    title:
                        'Upcoming Requests',
                    subtitle:
                        'Scheduled tracking',
                    count:
                        upcoming.length,
                  ),
                  const SizedBox(
                    height: 12,
                  ),

                  if (upcoming.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.only(
                            bottom: 24,
                            top: 8,
                          ),
                      child: Center(
                        child: Text(
                          'No upcoming requests',
                          style: TextStyle(
                            fontSize:
                                14,
                            color: Colors
                                .grey[600],
                            fontWeight:
                                FontWeight
                                    .w500,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    ...upcoming.map(
                      (r) => Padding(
                        padding:
                            const EdgeInsets.only(
                              bottom: 8,
                            ),
                        child:
                            _buildUpcomingTile(
                              r,
                            ),
                      ),
                    ),
                    const SizedBox(
                      height: 24,
                    ),
                  ],

                  // -------- Active (always visible) --------
                  _buildSectionHeader(
                    icon: Icons
                        .access_time,
                    title:
                        'Active Tracking',
                    subtitle:
                        'Location sharing active',
                    count:
                        active.length,
                  ),
                  const SizedBox(
                    height: 12,
                  ),

                  if (active.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.only(
                            bottom: 8,
                            top: 8,
                          ),
                      child: Center(
                        child: Text(
                          'No active requests',
                          style: TextStyle(
                            fontSize:
                                14,
                            color: Colors
                                .grey[600],
                            fontWeight:
                                FontWeight
                                    .w500,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    ...active.map(
                      (r) => Padding(
                        padding:
                            const EdgeInsets.only(
                              bottom: 8,
                            ),
                        child:
                            _buildActiveTile(
                              r,
                            ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ] else ...[
          // Meeting Point View - ENTIRE SECTION
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _pillButton(
                  icon: Icons
                      .place_outlined,
                  label:
                      'Create Meeting Point',
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 20),

          // Meeting Point Participants Section Header
          _buildSectionHeader(
            icon: Icons.place_outlined,
            title:
                'Meeting Point Participants',
            subtitle:
                'Active meeting point',
            count:
                meetingParticipants
                    .length +
                1,
          ),
          const SizedBox(height: 12),

          // Host (Current User) Card
          _buildHostCard(),
          const SizedBox(height: 8),

          // Meeting Participants
          for (final p
              in meetingParticipants) ...[
            _buildParticipantTile(p),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildViewToggle() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius:
            BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _toggleButton(
              'Tracking',
              _isTrackingView,
              () => setState(
                () => _isTrackingView =
                    true,
              ),
            ),
          ),
          Expanded(
            child: _toggleButton(
              'Meeting Point',
              !_isTrackingView,
              () => setState(
                () => _isTrackingView =
                    false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.kGreen
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(
                          0.1,
                        ),
                    blurRadius: 4,
                    offset:
                        const Offset(
                          0,
                          2,
                        ),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildMapPreview() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F0),
        borderRadius:
            BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(16),
        child: Stack(
          children: [
            if (_mapsLoading)
              const Center(
                child:
                    CircularProgressIndicator(
                      color: AppColors
                          .kGreen,
                    ),
              )
            else if (_currentFloor
                .isEmpty)
              const Center(
                child: Text(
                  'No 3D map',
                ),
              )
            else
              ModelViewer(
                key: ValueKey(
                  _currentFloor,
                ),
                src: _currentFloor,
                alt: "3D Map",
                ar: false,
                autoRotate: false,
                cameraControls: true,

                // ===== NEW: JS pin + controller =====
                relatedJs: _trackPinJs,
                onWebViewCreated: (controller) {
                  _trackMapController =
                      controller;

                  _pendingPinApply =
                      true; // ✅ مهم

                  Future.delayed(
                    const Duration(
                      milliseconds: 150,
                    ),
                    () {
                      if (!mounted)
                        return;
                      if (_pendingPinApply ||
                          _trackedPos !=
                              null) {
                        _applyTrackedPinToViewer();
                      }
                    },
                  );
                },
              ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(
                        20,
                      ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors
                          .black
                          .withOpacity(
                            0.1,
                          ),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons
                          .people_outline,
                      size: 18,
                      color: AppColors
                          .kGreen,
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    _isTrackingView
                        ? StreamBuilder<
                            List<
                              TrackingRequest
                            >
                          >(
                            stream:
                                _sentRequestsStream(),
                            builder:
                                (
                                  context,
                                  snapshot,
                                ) {
                                  final all =
                                      snapshot.data ??
                                      [];
                                  final active = _activeFrom(
                                    all,
                                  );

                                  return Text(
                                    active.length.toString(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  );
                                },
                          )
                        : Text(
                            (meetingParticipants.length +
                                    1)
                                .toString(),
                            style: const TextStyle(
                              fontSize:
                                  15,
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                  ],
                ),
              ),
            ),
            if (_venueMaps.length > 1)
              Positioned(
                top: 16,
                right: 16,
                child: Column(
                  children: _venueMaps
                      .map(
                        (m) => Padding(
                          padding:
                              const EdgeInsets.only(
                                bottom:
                                    8,
                              ),
                          child: _floorButton(
                            m['floorNumber'] ??
                                '',
                            _currentFloor ==
                                m['mapURL'],
                            () {
                              setState(() {
                                _trackMapController =
                                    null; // مهم عشان الكنترولر يتجدد مع الموديل الجديد
                                _currentFloor =
                                    m['mapURL'] ??
                                    '';
                                _pendingPinApply =
                                    true; // ✅ مهم
                              });
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _floorButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.kGreen
              : Colors.white,
          borderRadius:
              BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(0.1),
              blurRadius: 4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isSelected
                ? Colors.white
                : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTrackRequestButton() {
    return GestureDetector(
      onTap: _showTrackRequestDialog,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
              vertical: 14,
            ),
        decoration: BoxDecoration(
          color: AppColors.kGreen,
          borderRadius:
              BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.kGreen
                  .withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(
                0,
                4,
              ),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons
                  .person_search_outlined,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Track Request',
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                    FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
            vertical: 8,
          ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.all(
                  10,
                ),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.grey[700],
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                        fontSize: 17,
                        fontWeight:
                            FontWeight
                                .w700,
                        color: Colors
                            .black87,
                      ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors
                        .grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.people_outline,
                  size: 16,
                  color:
                      Colors.grey[700],
                ),
                const SizedBox(
                  width: 4,
                ),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w700,
                    color: Colors
                        .grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingTile(
    TrackingRequest r,
  ) {
    final isExpanded =
        _expandedRequestId == r.id;
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
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                _toggleExpand(r.id),
            borderRadius:
                BorderRadius.circular(
                  16,
                ),
            child: Padding(
              padding:
                  const EdgeInsets.all(
                    16,
                  ),
              child: Row(
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
                          r.trackedUserName,
                          style: const TextStyle(
                            fontSize:
                                16,
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                        ),
                        const SizedBox(
                          height: 4,
                        ),
                        _statusBadge(
                          r.status,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        _toggleFavorite(
                          r.id,
                        ),
                    icon: Icon(
                      r.isFavorite
                          ? Icons
                                .favorite
                          : Icons
                                .favorite_border,
                      color:
                          r.isFavorite
                          ? Colors.red
                          : Colors
                                .grey[400],
                      size: 24,
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded
                        ? 0.5
                        : 0,
                    duration:
                        const Duration(
                          milliseconds:
                              200,
                        ),
                    child: Icon(
                      Icons
                          .keyboard_arrow_down,
                      color: Colors
                          .grey[600],
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Padding(
              padding:
                  const EdgeInsets.all(
                    16,
                  ),
              child: _buildDetails(r),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveTile(
    TrackingRequest r,
  ) {
    final isExpanded =
        _expandedRequestId == r.id;
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
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                _toggleExpand(r.id),
            borderRadius:
                BorderRadius.circular(
                  16,
                ),
            child: Padding(
              padding:
                  const EdgeInsets.all(
                    16,
                  ),
              child: Row(
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
                          r.trackedUserName,
                          style: const TextStyle(
                            fontSize:
                                16,
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                        ),
                        const SizedBox(
                          height: 4,
                        ),
                        Text(
                          r.lastSeen ??
                              'Unknown',
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
                  IconButton(
                    onPressed: () =>
                        _toggleFavorite(
                          r.id,
                        ),
                    icon: Icon(
                      r.isFavorite
                          ? Icons
                                .favorite
                          : Icons
                                .favorite_border,
                      color:
                          r.isFavorite
                          ? Colors.red
                          : Colors
                                .grey[400],
                      size: 24,
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded
                        ? 0.5
                        : 0,
                    duration:
                        const Duration(
                          milliseconds:
                              200,
                        ),
                    child: Icon(
                      Icons
                          .keyboard_arrow_down,
                      color: Colors
                          .grey[600],
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Padding(
              padding:
                  const EdgeInsets.all(
                    16,
                  ),
              child: Column(
                children: [
                  _buildDetails(r),
                  const SizedBox(
                    height: 16,
                  ),
                  _buildActionButtons(
                    r,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg, text;
    String label;
    switch (status) {
      case 'accepted':
        bg = AppColors.kGreen
            .withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Accepted';
        break;
      default:
        bg = Colors.orange.withOpacity(
          0.1,
        );
        text = Colors.orange.shade700;
        label = 'Pending';
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

  Widget _buildDetails(
    TrackingRequest r,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: AppColors.kGreen,
              borderRadius:
                  BorderRadius.circular(
                    2,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                _detailRow(
                  'Tracked user: ',
                  '${r.trackedUserName} (${r.trackedUserPhone})',
                ),
                const SizedBox(
                  height: 8,
                ),
                _detailRow(
                  'Duration: ',
                  '${_formatDate(DateTime(r.startAt.year, r.startAt.month, r.startAt.day))} • ${r.startTime} - ${r.endTime}',
                ),
                const SizedBox(
                  height: 8,
                ),
                _detailRow(
                  'Venue: ',
                  r.venueName,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
              children: [
                TextSpan(text: label),
                TextSpan(
                  text: value,
                  style:
                      const TextStyle(
                        fontWeight:
                            FontWeight
                                .w600,
                        color: Colors
                            .black87,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ========== ACTION BUTTONS - UPDATED ==========
  Widget _buildActionButtons(
    TrackingRequest r,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: Icon(
              Icons.navigation_outlined,
              size: 18,
              color: AppColors.kGreen,
            ),
            label: const Text(
              'Navigate to friend',
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  AppColors.kGreen,
              side: BorderSide(
                color: AppColors.kGreen,
                width: 2,
              ),
              padding:
                  const EdgeInsets.symmetric(
                    vertical: 12,
                  ),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(
              Icons.refresh,
              size: 18,
            ),
            label: const Text(
              'Refresh Location',
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  AppColors.kGreen,
              foregroundColor:
                  Colors.white,
              padding:
                  const EdgeInsets.symmetric(
                    vertical: 12,
                  ),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatRequestTime(
    TrackingRequest r,
  ) =>
      '${_formatDate(DateTime(r.startAt.year, r.startAt.month, r.startAt.day))} • ${r.startTime} - ${r.endTime}';

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
    if (target ==
        today.add(
          const Duration(days: 1),
        ))
      return 'Tomorrow';
    return '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}, ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.day}';
  }

  // ---------- Host Card ----------

  Widget _buildHostCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.kGreen
              .withOpacity(0.3),
          width: 2,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(
                      color: AppColors
                          .kGreen,
                      shape: BoxShape
                          .circle,
                    ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Row(
                      children: [
                        Text(
                          currentUserName,
                          style: const TextStyle(
                            fontSize:
                                16,
                            fontWeight:
                                FontWeight
                                    .w700,
                            color: Colors
                                .black87,
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        _roleChip(
                          'Host',
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      'Now',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors
                            .grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      isArrived = true;
                    });
                  },
                  icon: const Icon(
                    Icons
                        .check_circle_outline,
                    size: 20,
                  ),
                  label: const Text(
                    'Arrived',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        AppColors
                            .kGreen,
                    foregroundColor:
                        Colors.white,
                    padding:
                        const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                            12,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors
                          .kError,
                      width: 2,
                    ),
                    foregroundColor:
                        AppColors
                            .kError,
                    padding:
                        const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                            12,
                          ),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight:
                          FontWeight
                              .w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // ---------- Participant Tile ----------

  Widget _buildParticipantTile(
    Participant p,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(
              dividerColor:
                  Colors.transparent,
            ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
          childrenPadding:
              const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16,
              ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              color: Colors.grey[600],
              size: 22,
            ),
          ),
          title: Text(
            p.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight:
                  FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            p.status,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          trailing: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.black45,
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(
                Icons.refresh,
                size: 20,
              ),
              label: const Text(
                'Refresh Location Request',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    AppColors.kGreen,
                foregroundColor:
                    Colors.white,
                minimumSize:
                    const Size.fromHeight(
                      48,
                    ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI Helpers ----------

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    final shape =
        RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(14),
        );
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(
          icon,
          color: AppColors.kGreen,
          size: 20,
        ),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.kGreen,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(
            color: AppColors.kGreen,
            width: 2,
          ),
          shape: shape,
          padding:
              const EdgeInsets.symmetric(
                vertical: 14,
              ),
          backgroundColor: Colors.white,
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        color: Colors.white,
        size: 20,
      ),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            AppColors.kGreen,
        foregroundColor: Colors.white,
        shape: shape,
        elevation: 0,
        padding:
            const EdgeInsets.symmetric(
              vertical: 14,
            ),
      ),
    );
  }

  Widget _roleChip(String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
      decoration: BoxDecoration(
        color: AppColors.kGreen
            .withOpacity(0.15),
        borderRadius:
            BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.kGreen,
        ),
      ),
    );
  }
}

class TrackingRequest {
  final String id;
  final String trackedUserName;
  final String trackedUserPhone;
  final String status;

  final DateTime startAt;
  final DateTime endAt;

  final String startTime;
  final String endTime;

  final String venueName;
  final String venueId;
  bool isFavorite;
  final String? lastSeen;

  TrackingRequest({
    required this.id,
    required this.trackedUserName,
    required this.trackedUserPhone,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.startTime,
    required this.endTime,
    required this.venueName,
    required this.venueId,
    this.isFavorite = false,
    this.lastSeen,
  });

  DateTime get startDateTime => startAt;
  DateTime get endDateTime => endAt;
}

/*class TrackingRequest {
  final String id;
  final String trackedUserName;
  final String trackedUserPhone;
  final String status;
  final DateTime scheduledDate;
  final String startTime;
  final String endTime;
  final String venueName;
  final String venueId;
  bool isFavorite;
  final String? lastSeen;

  TrackingRequest({
    required this.id,
    required this.trackedUserName,
    required this.trackedUserPhone,
    required this.status,
    required this.scheduledDate,
    required this.startTime,
    required this.endTime,
    required this.venueName,
    required this.venueId,
    this.isFavorite = false,
    this.lastSeen,
  });
  DateTime get startDateTime => _parseTime(scheduledDate, startTime);
  DateTime get endDateTime => _parseTime(scheduledDate, endTime);

  bool get isActive {
    if (status != 'accepted') return false;
    final now = DateTime.now();
    final start = _parseTime(scheduledDate, startTime);
    final end = _parseTime(scheduledDate, endTime);
    return now.isAfter(start) && now.isBefore(end);
  }

  bool get shouldRemove {
    if (status == 'accepted') return false;
    final now = DateTime.now();
    final end = _parseTime(scheduledDate, endTime);
    return now.isAfter(end);
  }

  DateTime _parseTime(DateTime date, String time) {
    final parts = time.split(' ');
    final timeParts = parts[0].split(':');
    int hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final isPM = parts.length > 1 && parts[1].toUpperCase() == 'PM';
    if (isPM && hour != 12) hour += 12;
    if (!isPM && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
*/
class Participant {
  final String name;
  final String status;
  final bool isHost;
  Participant({
    required this.name,
    required this.status,
    required this.isHost,
  });
}
