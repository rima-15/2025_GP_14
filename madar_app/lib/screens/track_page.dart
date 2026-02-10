import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show JavaScriptMessage, JavascriptChannel, WebViewController;
import 'track_request_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

const bool kFeatureEnabled = true;
const String kSolitaireVenueId = 'ChIJcYTQDwDjLj4RZEiboV6gZzM';
final Map<String, Map<String, double>> _trackedPosByUser =
    {}; // userDocId -> {x,y,z}
final Map<String, String> _trackedFloorByUser = {}; // userDocId -> floorLabel
final Map<String, String> _trackedNameByUser = {}; // userDocId -> displayName
final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
_userLocSubs = {};
StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeReqSub;

class TrackPage extends StatefulWidget {
  const TrackPage({
    super.key,
    this.initialExpandRequestId,
    this.initialFilterIndex,
  });

  /// When set (e.g. from notification tap), open with this request expanded.
  final String? initialExpandRequestId;

  /// 0 = Received, 1 = Sent. When opening from notification, which filter tab to show.
  final int? initialFilterIndex;

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  bool _pendingPinApply = false;
  bool _isTrackingView = true;
  String _currentFloor = '';
  List<Map<String, String>> _venueMaps = [];
  bool _mapsLoading = false;
  String? _expandedRequestId;
  Timer? _clockTimer;
  // ===== Track Map (Pin JS) =====
  WebViewController? _trackMapController;

  /// 0 = Sent, 1 = Received (same order as History page)
  int _selectedFilterIndex = 0;
  static const List<String> _requestFilters = ['Sent', 'Received'];
  final ScrollController _scrollController = ScrollController();

  /// Key for the tile to scroll to when opening from notification (by request ID).
  final GlobalKey _scrollToTargetKey = GlobalKey();
  Timer? _scrollToTargetTimer;

  Stream<List<TrackingRequest>> _sentRequestsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('trackRequests')
        .where('senderId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .orderBy('startAt')
        .snapshots()
        .map((snap) {
          _markStaleRequestsIfNeeded(snap.docs);
          return snap.docs.map((d) {
            final data = d.data();

            final startAt = (data['startAt'] as Timestamp).toDate();
            final endAt = (data['endAt'] as Timestamp).toDate();

            final startStr = TimeOfDay.fromDateTime(startAt).format(context);
            final endStr = TimeOfDay.fromDateTime(endAt).format(context);

            return TrackingRequest(
              id: d.id,
              trackedUserName: (data['receiverName'] ?? '').toString(),
              trackedUserPhone: (data['receiverPhone'] ?? '').toString(),
              status: (data['status'] ?? '').toString(),

              startAt: startAt,
              endAt: endAt,

              startTime: startStr,
              endTime: endStr,

              venueName: (data['venueName'] ?? '').toString(),
              venueId: (data['venueId'] ?? '').toString(),
              isFavorite: false,
              lastSeen: _timeAgo(startAt),
              // Add these two lines to satisfy the constructor:
              senderName: (data['senderName'] ?? '').toString(),
              senderPhone: (data['senderPhone'] ?? '').toString(),
            );
          }).toList();
        });
  }

  Stream<List<TrackingRequest>> _incomingRequestsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // You might want to filter by receiverPhone if you store it that way
    if (uid == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('trackRequests')
        .where('receiverId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots()
        .map((snap) {
          _markStaleRequestsIfNeeded(snap.docs);
          return snap.docs.map((d) {
            final data = d.data();
            final startAt = (data['startAt'] as Timestamp).toDate();
            final endAt = (data['endAt'] as Timestamp).toDate();

            return TrackingRequest(
              id: d.id,
              trackedUserName: (data['receiverName'] ?? '').toString(),
              trackedUserPhone: (data['receiverPhone'] ?? '').toString(),
              senderName: (data['senderName'] ?? 'Someone').toString(),
              senderPhone: (data['senderPhone'] ?? '').toString(),
              status: (data['status'] ?? '').toString(),
              startAt: startAt,
              endAt: endAt,
              startTime: TimeOfDay.fromDateTime(startAt).format(context),
              endTime: TimeOfDay.fromDateTime(endAt).format(context),
              venueName: (data['venueName'] ?? '').toString(),
              venueId: (data['venueId'] ?? '').toString(),
            );
          }).toList();
        });
  }

  List<TrackingRequest> _upcomingFrom(List<TrackingRequest> all) {
    final now = DateTime.now();

    final upcoming = all.where((r) {
      final start = r.startAt;
      final end = r.endAt;

      if (now.isAfter(end)) return false;

      if (r.status != 'pending' && r.status != 'accepted') return false;

      // Accepted: only show if not started yet
      // Pending: show even if started (still waiting for response)
      if (r.status == 'accepted') {
        return now.isBefore(start);
      }
      return true; // pending and not expired
    }).toList();

    upcoming.sort((a, b) => a.startAt.compareTo(b.startAt));
    return upcoming;
  }

  List<TrackingRequest> _activeFrom(List<TrackingRequest> all) {
    final now = DateTime.now();

    final active = all.where((r) {
      if (r.status != 'accepted') return false;

      final start = r.startAt;
      final end = r.endAt;

      return now.isAfter(start) && now.isBefore(end);
    }).toList();

    active.sort((a, b) => a.startAt.compareTo(b.startAt));
    return active;
  }

  /// Received: scheduled = pending (before end) or accepted but not started yet
  List<TrackingRequest> _receivedScheduledFrom(List<TrackingRequest> incoming) {
    final now = DateTime.now();
    final scheduled = incoming.where((r) {
      if (now.isAfter(r.endAt)) return false;
      if (r.status == 'pending') return true;
      if (r.status == 'accepted') return now.isBefore(r.startAt);
      return false;
    }).toList();
    scheduled.sort((a, b) => a.startAt.compareTo(b.startAt));
    return scheduled;
  }

  /// Received: active = accepted and in time window
  List<TrackingRequest> _receivedActiveFrom(List<TrackingRequest> incoming) {
    return _activeFrom(incoming);
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
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

function pinId(userId){ return `trackedPin_${userId}`; }
function labelId(userId){ return `trackedLabel_${userId}`; }

function ensureTrackStyle() {
  if (document.getElementById("track_pin_hotspot_style")) return;
  const style = document.createElement("style");
  style.id = "track_pin_hotspot_style";
  style.textContent = `
    .trackedPinHotspot{
      pointer-events:none;
      position:absolute;
      left:0; top:0;
      width:1px; height:1px;
      transform: translate3d(var(--hotspot-x), var(--hotspot-y), 0px);
      will-change: transform;
      z-index: 900;
      opacity: var(--hotspot-visibility);
    }
  `;
  document.head.appendChild(style);
}

function buildTeardropPin(container, opts){
  const size = (opts && opts.size) ? Number(opts.size) : 22;
  const color = (opts && opts.color) ? String(opts.color) : "#ff3b30";
  const label = (opts && typeof opts.label === "string") ? opts.label : "";

  const wrap = document.createElement("div");
  wrap.style.position = "absolute";
  wrap.style.left = "0";
  wrap.style.top = "0";
  wrap.style.transform = "translate(-50%, -92%)";
  wrap.style.pointerEvents = "none";

  const column = document.createElement("div");
  column.style.display = "flex";
  column.style.flexDirection = "column";
  column.style.alignItems = "center";
  column.style.gap = "4px";

  // Optional label bubble (above pin)
  if (label) {
    const bubble = document.createElement("div");
    bubble.style.padding = "3px 8px";
    bubble.style.borderRadius = "12px";
    bubble.style.background = "rgba(0,0,0,0.55)";
    bubble.style.color = "#fff";
    bubble.style.fontSize = "11px";
    bubble.style.maxWidth = "140px";
    bubble.style.whiteSpace = "nowrap";
    bubble.style.overflow = "hidden";
    bubble.style.textOverflow = "ellipsis";
    bubble.textContent = label;
    column.appendChild(bubble);
  }

  const holder = document.createElement("div");
  holder.style.position = "relative";
  holder.style.width = `${size}px`;
  holder.style.height = `${size}px`;
  holder.style.overflow = "visible";

  const pin = document.createElement("div");
  pin.style.width = `${size}px`;
  pin.style.height = `${size}px`;
  pin.style.background = color;
  pin.style.borderRadius = `${size}px ${size}px ${size}px 0`;
  pin.style.position = "absolute";
  pin.style.left = "50%";
  pin.style.top = "50%";
  pin.style.transform = "translate(-50%, -50%) rotate(-45deg)";
  pin.style.transformOrigin = "center";
  pin.style.boxShadow = "0 6px 14px rgba(0,0,0,0.35)";
  pin.style.border = "2px solid rgba(255,255,255,0.85)";

  const inner = document.createElement("div");
  inner.style.width = `${Math.round(size*0.33)}px`;
  inner.style.height = `${Math.round(size*0.33)}px`;
  inner.style.background = "white";
  inner.style.borderRadius = "999px";
  inner.style.position = "absolute";
  inner.style.left = "50%";
  inner.style.top = "50%";
  inner.style.transform = "translate(-50%, -50%)";
  pin.appendChild(inner);

  holder.appendChild(pin);

  const shadow = document.createElement("div");
  shadow.style.width = `${Math.round(size*0.75)}px`;
  shadow.style.height = `${Math.max(5, Math.round(size*0.25))}px`;
  shadow.style.background = "rgba(0,0,0,0.25)";
  shadow.style.borderRadius = "999px";
  shadow.style.filter = "blur(1px)";

  column.appendChild(holder);
  column.appendChild(shadow);

  wrap.appendChild(column);
  container.appendChild(wrap);
}

function ensurePin(viewer, userId, label){
  ensureTrackStyle();

  const id = pinId(userId);
  let hs = viewer.querySelector(`#${id}`);
  if(!hs){
    hs = document.createElement('div');
    hs.id = id;
    hs.slot = `hotspot-${id}`;
    hs.className = "trackedPinHotspot";
    hs.style.display = 'block';
    viewer.appendChild(hs);

    // build UI once
    buildTeardropPin(hs, { size: 22, color: "#ff3b30", label: label || "" });
    hs.__labelText = label || "";
  }else{
    // update label bubble if changed (rebuild simplest)
    const newLabel = label || "";
    if (hs.__labelText !== newLabel) {
      hs.innerHTML = "";
      buildTeardropPin(hs, { size: 22, color: "#ff3b30", label: newLabel });
      hs.__labelText = newLabel;
    }
  }
  return hs;
}

window.upsertTrackedPin = function(userId,x,y,z,label){
  const viewer = getViewer();
  if(!viewer || !userId) return false;

  const hs = ensurePin(viewer, userId, label);

  // Force refresh
  if (hs.parentElement) {
    hs.parentElement.removeChild(hs);
    viewer.appendChild(hs);
  }

  hs.setAttribute('data-position', `${Number(x)} ${Number(y)} ${Number(z)}`);
  hs.setAttribute('data-normal', '0 1 0');
  hs.style.display = 'block';
  viewer.requestUpdate();
  return true;
};

window.hideTrackedPin = function(userId){
  const viewer = getViewer();
  if(!viewer || !userId) return false;
  const hs = viewer.querySelector(`#${pinId(userId)}`);
  if(hs) hs.style.display = 'none';
  viewer.requestUpdate();
  return true;
};

window.removeTrackedPin = function(userId){
  const viewer = getViewer();
  if(!viewer || !userId) return false;
  const hs = viewer.querySelector(`#${pinId(userId)}`);
  if(hs) hs.remove();
  viewer.requestUpdate();
  return true;
};

window.__viewerReady = false;
(function(){
  const v = getViewer();
  if(!v) return;
  v.addEventListener('load', () => { window.__viewerReady = true; }, { once:true });
  v.addEventListener('model-visibility', () => { window.__viewerReady = true; });
})();
window.isViewerReady = function(){ return !!window.__viewerReady; };


''';

  // Meeting point data
  final List<Participant> meetingParticipants = [
    Participant(name: 'Alex Chen', status: 'On the way', isHost: false),
    Participant(name: 'Sarah Kim', status: 'Arrived', isHost: false),
  ];
  final String currentUserName = 'Ahmed Hassan';
  bool isArrived = false;
  // =======================
  // LIVE LOCATION (TRACKING)
  // =======================

  Map<String, double>? _trackedPos; // {x,y,z}
  String _trackedFloorLabel = '';
  StreamSubscription<DocumentSnapshot>? _liveLocSub;

  @override
  void initState() {
    super.initState();
    _loadVenueMaps();
    if (widget.initialExpandRequestId != null) {
      _expandedRequestId = widget.initialExpandRequestId;
      // Notification passes 0 = Received, 1 = Sent; we use 0 = Sent, 1 = Received
      _selectedFilterIndex = widget.initialFilterIndex != null
          ? 1 - widget.initialFilterIndex!
          : 0;
      _isTrackingView = true; // Tracking tab
      _startScrollToTargetWhenReady();
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _listenToActiveTrackedUsers();
  }

  // ضعّيها داخل _TrackPageState (فوق أو تحت)
  Map<String, double> _blenderToGltf({
    required double x,
    required double y,
    required double z,
  }) {
    // Blender (Z-up) -> glTF (Y-up)
    // ✅ بدون عكس X
    return {'x': x, 'y': z, 'z': -y};
  }

  void _listenToActiveTrackedUsers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final q = FirebaseFirestore.instance
        .collection('trackRequests')
        .where('senderId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'accepted');

    _activeReqSub?.cancel();
    _activeReqSub = q.snapshots().listen((snap) {
      final activeReceiverIds = <String>{};

      for (final d in snap.docs) {
        final data = d.data();

        final startAt = (data['startAt'] as Timestamp?)?.toDate();
        final endAt = (data['endAt'] as Timestamp?)?.toDate();

        final now = DateTime.now();
        final isActiveNow =
            startAt != null &&
            endAt != null &&
            now.isAfter(startAt) &&
            now.isBefore(endAt);

        if (!isActiveNow) continue;

        final rid = (data['receiverId'] ?? '').toString().trim();
        if (rid.isNotEmpty) activeReceiverIds.add(rid);
      }

      // Remove subscriptions that are no longer active
      final currentIds = _userLocSubs.keys.toSet();
      final toRemove = currentIds.difference(activeReceiverIds);

      for (final id in toRemove) {
        _userLocSubs[id]?.cancel();
        _userLocSubs.remove(id);

        _trackedPosByUser.remove(id);
        _trackedFloorByUser.remove(id);
        _trackedNameByUser.remove(id);

        _trackMapController?.runJavaScript("removeTrackedPin('$id');");
      }

      // Add new subscriptions
      final toAdd = activeReceiverIds.difference(currentIds);

      for (final id in toAdd) {
        _userLocSubs[id] = FirebaseFirestore.instance
            .collection('users')
            .doc(id)
            .snapshots()
            .listen((docSnap) {
              final u = docSnap.data();
              if (u == null) return;

              final location = (u['location'] as Map?) ?? {};
              final blender = (location['blenderPosition'] as Map?) ?? {};

              final bx = (blender['x'] as num?)?.toDouble();
              final by = (blender['y'] as num?)?.toDouble();
              final bz = (blender['z'] as num?)?.toDouble();

              final floorRaw = (blender['floor'] ?? '').toString();

              final first = (u['firstName'] ?? '').toString().trim();
              final last = (u['lastName'] ?? '').toString().trim();

              final displayName = (first.isNotEmpty || last.isNotEmpty)
                  ? ('$first $last').trim()
                  : (u['name'] ?? u['fullName'] ?? u['email'] ?? 'User')
                        .toString();

              if (bx == null || by == null || bz == null) {
                _trackedPosByUser.remove(id);
                _trackedFloorByUser.remove(id);
                _trackedNameByUser.remove(id);

                _trackMapController?.runJavaScript("hideTrackedPin('$id');");
                return;
              }

              // ✅ التحويل إلى glTF مثل مبدأ الـ Navigation (وبدون عكس X)
              final gltf = _blenderToGltf(x: bx, y: by, z: bz);

              _trackedPosByUser[id] = gltf;
              _trackedFloorByUser[id] = floorRaw;
              _trackedNameByUser[id] = displayName;

              _applyAllTrackedPinsToViewer();
            });
      }

      // After changes, re-apply (important when floor changes)
      _applyAllTrackedPinsToViewer();
    });
  }

  /// Retry until the target tile (by request ID) is built, then scroll so it's visible.
  void _startScrollToTargetWhenReady() {
    int attempts = 0;
    const maxAttempts = 25; // ~2.5 seconds
    _scrollToTargetTimer?.cancel();
    _scrollToTargetTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) {
      if (!mounted || attempts >= maxAttempts) {
        _scrollToTargetTimer?.cancel();
        _scrollToTargetTimer = null;
        return;
      }
      attempts++;
      final ctx = _scrollToTargetKey.currentContext;
      if (ctx != null) {
        _scrollToTargetTimer?.cancel();
        _scrollToTargetTimer = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.15,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOutCubic,
            );
          } catch (_) {}
        });
      }
    });
  }

  @override
  @override
  void dispose() {
    _clockTimer?.cancel();
    _scrollToTargetTimer?.cancel();
    _activeReqSub?.cancel();

    // cancel all tracked-users subscriptions
    for (final sub in _userLocSubs.values) {
      sub.cancel();
    }
    _userLocSubs.clear();

    _scrollController.dispose();
    super.dispose();
  }

  void _toggleExpand(String requestId) {
    setState(() {
      _expandedRequestId = _expandedRequestId == requestId ? null : requestId;
    });
  }

  void _toggleFavorite(String requestId) {
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
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(kSolitaireVenueId)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));

      final data = doc.data();
      if (data != null && data['map'] is List) {
        final maps = (data['map'] as List).cast<Map<String, dynamic>>();
        final convertedMaps = maps.map((map) {
          return {
            'floorNumber': (map['floorNumber'] ?? '').toString(),
            'mapURL': (map['mapURL'] ?? '').toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            if (convertedMaps.isNotEmpty) {
              final firstValid = convertedMaps.firstWhere(
                (m) => (m['mapURL'] ?? '').toString().trim().isNotEmpty,
                orElse: () => const {'mapURL': ''},
              );

              _currentFloor = (firstValid['mapURL'] ?? '').toString();
            }
          });
        }
      } else {
        _useFallbackMaps();
      }
    } catch (e) {
      _useFallbackMaps();
    } finally {
      if (mounted) setState(() => _mapsLoading = false);
    }
    _pendingPinApply = true;
  }

  int? _parseFloorToIndex(String floorRaw) {
    final s = floorRaw.trim().toUpperCase();
    if (s.isEmpty) return null;

    // "1", "2"
    final n1 = int.tryParse(s);
    if (n1 != null) return n1 - 1;

    // "F1", "F2"
    final m = RegExp(r'(\d+)').firstMatch(s);
    if (m != null) return int.parse(m.group(1)!) - 1;

    if (s == 'GF' || s == 'G' || s == 'GROUND') return 0;
    return null;
  }

  String _currentFloorLabel() {
    final m = _venueMaps.firstWhere(
      (x) => (x['mapURL'] ?? '') == _currentFloor,
      orElse: () => const {'floorNumber': ''},
    );
    return (m['floorNumber'] ?? '').toString().trim().toUpperCase();
  }

  String _normalizeTrackedFloorLabel(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';

    final n = int.tryParse(s);
    if (n != null) {
      if (n == 0) return 'GF';
      if (n == 1) return 'F1';
      return 'F$n';
    }

    return s;
  }

  bool _floorsMatch(String trackedRaw, String currentLabel) {
    final tracked = _normalizeTrackedFloorLabel(trackedRaw);
    final cur = currentLabel.trim().toUpperCase();

    if (tracked.isEmpty || cur.isEmpty) return true;

    if (cur == tracked) return true;

    final tNum = RegExp(r'\d+').firstMatch(tracked)?.group(0);
    if (tNum != null && cur.contains(tNum)) return true;

    return false;
  }

  Future<void> _applyAllTrackedPinsToViewer() async {
    if (_trackMapController == null) {
      _pendingPinApply = true;
      return;
    }

    final currentLabel = _currentFloorLabel(); // GF / F1 (or whatever you have)

    // If nothing tracked -> just do nothing
    if (_trackedPosByUser.isEmpty) {
      _pendingPinApply = false;
      return;
    }

    for (final entry in _trackedPosByUser.entries) {
      final userId = entry.key;
      final pos = entry.value;

      final trackedFloorLabel = _trackedFloorByUser[userId] ?? '';
      final ok = _floorsMatch(trackedFloorLabel, currentLabel);

      if (!ok) {
        await _trackMapController!.runJavaScript("hideTrackedPin('$userId');");
        continue;
      }
      final x = (pos['x'] ?? 0).toDouble();
      final y = (pos['y'] ?? 0).toDouble();
      final z = (pos['z'] ?? 0).toDouble();

      final label = (_trackedNameByUser[userId] ?? 'User').replaceAll(
        "'",
        "\\'",
      );

      _trackMapController!.runJavaScript(
        "upsertTrackedPin('$userId',$x,$y,$z,'$label');",
      );
    }

    _pendingPinApply = false;
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
        _currentFloor = fallback.first['mapURL'] ?? '';
      });
    }
  }

  void _showTrackRequestDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TrackRequestDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: kFeatureEnabled ? _buildFullContent() : _buildComingSoon(),
      ),
    );
  }

  Widget _buildComingSoon() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text(
            'Coming Soon',
            style: TextStyle(fontSize: 24, color: Colors.grey[800]),
          ),
        ],
      ),
    );
  }

  static const List<String> _mainTabs = ['Tracking', 'Meeting point'];

  Widget _buildFullContent() {
    return ListView(
      controller: _scrollController,
      key: const ValueKey<String>('track_requests_list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _buildMainTabs(),
        Container(height: 1, color: Colors.black12),
        const SizedBox(height: 12),

        // Map visible for both Tracking and Meeting point
        _buildMapPreview(),
        const SizedBox(height: 16),

        if (_isTrackingView) ...[
          _buildTrackRequestButton(),
          const SizedBox(height: 24),
          const Text(
            'Tracking Requests',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildFilterPills(),
          const SizedBox(height: 20),

          if (_selectedFilterIndex == 0)
            StreamBuilder<List<TrackingRequest>>(
              stream: _sentRequestsStream(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? [];
                final upcoming = _upcomingFrom(all);
                final active = _activeFrom(all);
                return _buildSentContent(upcoming, active);
              },
            )
          else
            StreamBuilder<List<TrackingRequest>>(
              stream: _incomingRequestsStream(),
              builder: (context, snapshot) {
                final incoming = snapshot.data ?? [];
                final scheduled = _receivedScheduledFrom(incoming);
                final active = _receivedActiveFrom(incoming);
                return _buildReceivedContent(scheduled, active);
              },
            ),
        ] else ...[
          // Meeting point view (same as before)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _pillButton(
                  icon: Icons.place_outlined,
                  label: 'Create Meeting Point',
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 20),

          _buildSectionHeader(
            icon: Icons.place_outlined,
            title: 'Meeting Point Participants',
            subtitle: 'Active meeting point',
            count: meetingParticipants.length + 1,
          ),
          const SizedBox(height: 12),

          _buildHostCard(),
          const SizedBox(height: 8),

          for (final p in meetingParticipants) ...[
            _buildParticipantTile(p),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  /// Main tabs: Tracking | Meeting point (compact like History — text + underline).
  Widget _buildMainTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: List.generate(_mainTabs.length, (i) {
          final isSelected = i == 0 ? _isTrackingView : !_isTrackingView;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _isTrackingView = (i == 0);
                _expandedRequestId = null;
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _mainTabs[i],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.kGreen : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
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

  /// Sent | Received filter pills (same style as History page — grey container, green selected pill).
  Widget _buildFilterPills() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_requestFilters.length, (i) {
          final isSelected = i == _selectedFilterIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedFilterIndex = i;
                _expandedRequestId = null;
              }),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.kGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  _requestFilters[i],
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

  Widget _buildMapPreview() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F0),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (_mapsLoading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.kGreen),
              )
            else if (_currentFloor.isEmpty)
              const Center(child: Text('No 3D map'))
            else
              ModelViewer(
                key: ValueKey(_currentFloor),
                src: _currentFloor,
                alt: "3D Map",
                ar: false,
                cameraControls: true,
                autoRotate: false,
                backgroundColor: Colors.transparent,
                cameraOrbit: "0deg 65deg 2.5m",
                minCameraOrbit: "auto 0deg auto",
                maxCameraOrbit: "auto 90deg auto",
                cameraTarget: "0m 0m 0m",

                // ===== NEW: JS pin + controller =====
                relatedJs: _trackPinJs,
                onWebViewCreated: (controller) {
                  _trackMapController = controller;

                  _pendingPinApply = true; // ✅ مهم

                  _applyPinsWhenViewerReady();
                },
              ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.people_outline,
                      size: 18,
                      color: AppColors.kGreen,
                    ),
                    const SizedBox(width: 6),
                    _isTrackingView
                        ? StreamBuilder<List<TrackingRequest>>(
                            stream: _sentRequestsStream(),
                            builder: (context, snapshot) {
                              final all = snapshot.data ?? [];
                              final active = _activeFrom(all);

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
                            (meetingParticipants.length + 1).toString(),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
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
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _floorButton(
                            m['floorNumber'] ?? '',
                            _currentFloor == m['mapURL'],
                            () {
                              setState(() {
                                _trackMapController = null;
                                _currentFloor = m['mapURL'] ?? '';
                                _pendingPinApply = true;
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

  Future<void> _applyPinsWhenViewerReady() async {
    if (_trackMapController == null) return;

    int tries = 0;
    while (tries < 20) {
      tries++;
      try {
        final ok = await _trackMapController!.runJavaScriptReturningResult(
          "isViewerReady();",
        );
        final ready = ok.toString().contains('true');
        if (ready) break;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    _applyAllTrackedPinsToViewer();
  }

  Widget _floorButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.kGreen : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTrackRequestButton() {
    return GestureDetector(
      onTap: _showTrackRequestDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.kGreen,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.kGreen.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_outlined, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Track Request',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Light grey text only, no background, no icon
  Widget _buildSubsectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildReceivedContent(
    List<TrackingRequest> scheduled,
    List<TrackingRequest> active,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // -------- Scheduled Tracking (always show title) --------
        _buildSubsectionLabel('Scheduled Tracking'),
        const SizedBox(height: 4),
        if (scheduled.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 0),
            child: Center(
              child: Text(
                'No Scheduled Requests',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          ...scheduled.map(
            (r) => Padding(
              key:
                  widget.initialExpandRequestId != null &&
                      r.id == widget.initialExpandRequestId
                  ? _scrollToTargetKey
                  : null,
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildReceivedScheduledTile(r),
            ),
          ),
        const SizedBox(height: 24),
        // -------- Active Tracking (always show title) --------
        _buildSubsectionLabel('Active Tracking'),
        const SizedBox(height: 4),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 0),
            child: Center(
              child: Text(
                'No Active Requests',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          ...active.map(
            (r) => Padding(
              key:
                  widget.initialExpandRequestId != null &&
                      r.id == widget.initialExpandRequestId
                  ? _scrollToTargetKey
                  : null,
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildReceivedActiveTile(r),
            ),
          ),
      ],
    );
  }

  Widget _buildSentContent(
    List<TrackingRequest> upcoming,
    List<TrackingRequest> active,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubsectionLabel('Scheduled Tracking'),
        const SizedBox(height: 4),
        if (upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 0),
            child: Center(
              child: Text(
                'No Scheduled Requests',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          ...upcoming.map(
            (r) => Padding(
              key:
                  widget.initialExpandRequestId != null &&
                      r.id == widget.initialExpandRequestId
                  ? _scrollToTargetKey
                  : null,
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildUpcomingTile(r),
            ),
          ),
        const SizedBox(height: 24),
        _buildSubsectionLabel('Active Tracking'),
        const SizedBox(height: 4),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 0),
            child: Center(
              child: Text(
                'No Active Requests',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          ...active.map(
            (r) => Padding(
              key:
                  widget.initialExpandRequestId != null &&
                      r.id == widget.initialExpandRequestId
                  ? _scrollToTargetKey
                  : null,
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildActiveTile(r),
            ),
          ),
      ],
    );
  }

  /// Received scheduled tile: same design as Sent _buildUpcomingTile (heart, no divider). Pending → Accept/Decline; Accepted (not started) → Cancel Tracking.
  Widget _buildReceivedScheduledTile(TrackingRequest r) {
    final isExpanded = _expandedRequestId == r.id;
    final now = DateTime.now();
    final bool isPending = r.status == 'pending' && now.isBefore(r.endAt);
    final bool isAcceptedScheduled =
        r.status == 'accepted' && now.isBefore(r.startAt);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(r.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.senderName ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _statusBadge(r.status),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _toggleFavorite(r.id),
                    icon: Icon(
                      r.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: r.isFavorite ? Colors.red : Colors.grey[400],
                      size: 24,
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildReceivedDetails(r),
                  const SizedBox(height: 16),
                  if (isPending)
                    _buildIncomingActionButtons(context, r)
                  else if (isAcceptedScheduled)
                    _buildCancelTrackingButton(context, r),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Received active tile: same design as Sent _buildActiveTile (heart, same container) but only "Stop Tracking" button. Show lastSeen (e.g. "2 min ago").
  Widget _buildReceivedActiveTile(TrackingRequest r) {
    final isExpanded = _expandedRequestId == r.id;
    final lastSeen = _timeAgo(r.startAt);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(r.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.senderName ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastSeen,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _toggleFavorite(r.id),
                    icon: Icon(
                      r.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: r.isFavorite ? Colors.red : Colors.grey[400],
                      size: 24,
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildReceivedDetails(r),
                  const SizedBox(height: 16),
                  _buildStopTrackingButton(context, r),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStopTrackingButton(BuildContext context, TrackingRequest r) {
    final senderName = r.senderName ?? 'this person';
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final confirmed = await ConfirmationDialog.showDeleteConfirmation(
            context,
            title: 'Stop Sharing',
            message:
                'Are you sure you want to stop sharing your location with $senderName?',
            cancelText: 'Keep',
            confirmText: 'Stop Sharing',
          );
          if (confirmed && mounted) {
            _updateRequestStatus(
              r.id,
              'terminated',
              successMessage: 'Location sharing has been stopped.',
            );
          }
        },
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: const Text(
          'Stop Tracking',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.kError,
          side: const BorderSide(color: AppColors.kError),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.grey[700], size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: Colors.grey[700]),
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingTile(TrackingRequest r) {
    final isExpanded = _expandedRequestId == r.id;
    // For sent requests: show receiver name. For received: show sender name.
    final displayName = r.trackedUserName.isNotEmpty
        ? r.trackedUserName
        : (r.senderName ?? 'Unknown');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(r.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _statusBadge(r.status),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _toggleFavorite(r.id),
                    icon: Icon(
                      r.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: r.isFavorite ? Colors.red : Colors.grey[400],
                      size: 24,
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Padding(padding: const EdgeInsets.all(16), child: _buildDetails(r)),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveTile(TrackingRequest r) {
    final isExpanded = _expandedRequestId == r.id;
    // For sent requests: show receiver name. For received: show sender name.
    final displayName = r.trackedUserName.isNotEmpty
        ? r.trackedUserName
        : (r.senderName ?? 'Unknown');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(r.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.lastSeen ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _toggleFavorite(r.id),
                    icon: Icon(
                      r.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: r.isFavorite ? Colors.red : Colors.grey[400],
                      size: 24,
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDetails(r),
                  const SizedBox(height: 16),
                  _buildActionButtons(r),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCancelTrackingButton(BuildContext context, TrackingRequest r) {
    final senderName = r.senderName ?? 'this person';
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final confirmed = await ConfirmationDialog.showDeleteConfirmation(
            context,
            title: 'Cancel Tracking',
            message:
                'Are you sure you want to cancel this tracking request with $senderName?',
            cancelText: 'Keep',
            confirmText: 'Cancel Tracking',
          );
          if (confirmed && mounted) {
            _updateRequestStatus(
              r.id,
              'declined',
              successMessage: 'Scheduled tracking has been removed',
            );
          }
        },

        icon: const Icon(Icons.cancel_outlined, size: 18),
        label: const Text(
          'Cancel Tracking',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.kError,
          side: const BorderSide(color: AppColors.kError),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Mark requests that are past endAt as expired (pending) or completed (accepted) so they appear in History.
  void _markStaleRequestsIfNeeded(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    for (final d in docs) {
      final data = d.data();
      final status = (data['status'] ?? '').toString();
      final endAt = data['endAt'] is Timestamp
          ? (data['endAt'] as Timestamp).toDate()
          : null;
      if (endAt == null || endAt.isAfter(now)) continue;
      if (status == 'pending') {
        FirebaseFirestore.instance.collection('trackRequests').doc(d.id).update(
          {'status': 'expired'},
        );
      } else if (status == 'accepted') {
        FirebaseFirestore.instance.collection('trackRequests').doc(d.id).update(
          {'status': 'completed'},
        );
      }
    }
  }

  // Logic to update Firestore
  Future<void> _updateRequestStatus(
    String requestId,
    String newStatus, {
    String? successMessage,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('trackRequests')
          .doc(requestId)
          .update({
            'status': newStatus,
            'respondedAt': FieldValue.serverTimestamp(),
            if (newStatus == 'accepted') 'startNotifiedUsers': [],
          });

      // Show snackbar immediately after status update
      if (mounted) {
        setState(() => _expandedRequestId = null);
        SnackbarHelper.showSuccess(
          context,
          successMessage ?? _statusUpdateMessage(newStatus),
        );
      }

      // Mark related notifications as read in the background
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance
            .collection('notifications')
            .where('data.requestId', isEqualTo: requestId)
            .where('userId', isEqualTo: uid)
            .get()
            .then((snap) {
              for (final doc in snap.docs) {
                doc.reference.update({'isRead': true});
              }
            });
      }
    } catch (e) {
      debugPrint('Error updating request: $e');

      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Failed to update request. Please try again.',
        );
      }
    }
  }

  String _statusUpdateMessage(String status) {
    switch (status) {
      case 'accepted':
        return 'Tracking request accepted successfully';
      case 'declined':
        return 'Tracking request has been declined';
      case 'terminated':
        return 'Active tracking has been terminated';
      default:
        return 'Request updated successfully';
    }
  }

  Widget _buildIncomingActionButtons(BuildContext context, TrackingRequest r) {
    return Row(
      children: [
        // Decline = same design as "Navigate to friend" (outlined)
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await ConfirmationDialog.showDeleteConfirmation(
                context,
                title: 'Decline Request',
                message: 'Are you sure you want to decline this request?',
                confirmText: 'Decline',
              );
              if (confirmed && mounted) {
                _updateRequestStatus(
                  r.id,
                  'declined',
                  successMessage: 'Tracking request has been declined.',
                );
              }
            },
            icon: Icon(
              Icons.cancel_outlined,
              size: 18,
              color: AppColors.kGreen,
            ),
            label: const Text(
              'Decline',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.kGreen,
              side: BorderSide(color: AppColors.kGreen, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Accept = same design as "Refresh Location" (filled green)
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              final confirmed =
                  await ConfirmationDialog.showPositiveConfirmation(
                    context,
                    title: 'Accept Track Request',
                    message:
                        'Are you sure you want to accept this tracking request?',
                    confirmText: 'Accept',
                  );
              if (confirmed && mounted) {
                _updateRequestStatus(
                  r.id,
                  'accepted',
                  successMessage: 'Tracking request accepted successfully.',
                );
              }
            },
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text(
              'Accept',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color bg, text;
    String label;
    switch (status) {
      case 'accepted':
        bg = AppColors.kGreen.withOpacity(0.1);
        text = AppColors.kGreen;
        label = 'Accepted';
        break;
      default:
        bg = Colors.orange.withOpacity(0.1);
        text = Colors.orange.shade700;
        label = 'Pending';
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

  /// Build duration string with overnight "(next day)" support and • separator
  String _buildDurationStr(TrackingRequest r) {
    final dateStr = _formatDateForDuration(
      DateTime(r.startAt.year, r.startAt.month, r.startAt.day),
    );
    final isOvernight =
        r.endAt.day != r.startAt.day ||
        r.endAt.month != r.startAt.month ||
        r.endAt.year != r.startAt.year;
    final suffix = isOvernight ? ' (next day)' : '';
    return '$dateStr • ${r.startTime} - ${r.endTime}$suffix';
  }

  Widget _buildDetails(TrackingRequest r) {
    return _buildDetailsColumn(
      label: 'Tracked User',
      name: r.trackedUserName,
      phone: r.trackedUserPhone,
      duration: _buildDurationStr(r),
      venue: r.venueName,
    );
  }

  Widget _buildReceivedDetails(TrackingRequest r) {
    return _buildDetailsColumn(
      label: 'Sender',
      name: r.senderName ?? 'Unknown',
      phone: r.senderPhone ?? '',
      duration: _buildDurationStr(r),
      venue: r.venueName,
    );
  }

  Widget _buildDetailsColumn({
    required String label,
    required String name,
    required String phone,
    required String duration,
    required String venue,
  }) {
    return IntrinsicHeight(
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
                  '$label: ',
                  phone.isEmpty ? name : '$name ($phone)',
                ),
                const SizedBox(height: 8),
                _labeledDetail('Duration: ', duration),
                const SizedBox(height: 8),
                _labeledDetail('Venue: ', venue),
              ],
            ),
          ),
        ],
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

  /// For duration: "Today" (no date) or "Jan 31" (date only, no day name). Yesterday/Tomorrow left for later.
  String _formatDateForDuration(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}';
  }

  // ========== ACTION BUTTONS - UPDATED ==========
  Widget _buildActionButtons(TrackingRequest r) {
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.kGreen,
              side: BorderSide(color: AppColors.kGreen, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text(
              'Refresh Location',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Host Card ----------

  Widget _buildHostCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.kGreen.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
                decoration: BoxDecoration(
                  color: AppColors.kGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          currentUserName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _roleChip('Host'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Now',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Arrived'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.kError, width: 2),
                    foregroundColor: AppColors.kError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
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

  Widget _buildParticipantTile(Participant p) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(
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
            child: Icon(Icons.person, color: Colors.grey[600], size: 22),
          ),
          title: Text(
            p.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            p.status,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Refresh Location Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.kGreen, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.kGreen,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.kGreen, width: 2),
          shape: shape,
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: Colors.white,
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.kGreen,
        foregroundColor: Colors.white,
        shape: shape,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _roleChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.kGreen.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
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

  final String? senderName; // Add this
  final String? senderPhone; // Add this

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
    required this.senderName, // Add this
    required this.senderPhone, // Add this
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
  Participant({required this.name, required this.status, required this.isHost});
}
