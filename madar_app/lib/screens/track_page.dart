import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:madar_app/screens/navigation_flow_complete.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show JavaScriptMessage, JavascriptChannel, WebViewController;
import 'track_request_dialog.dart';
import 'create_meeting_point_form.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
// by remas start
import 'package:geolocator/geolocator.dart';
// by remas end

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
    this.initialMeetingPointId,
  });

  /// When set (e.g. from notification tap), open with this request expanded.
  final String? initialExpandRequestId;

  /// 0 = Received, 1 = Sent. When opening from notification, which filter tab to show.
  final int? initialFilterIndex;

  /// When set (e.g. from notification tap), open Meeting Point tab and expand this invite.
  final String? initialMeetingPointId;

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
  String? _highlightRequestId;
  String? _highlightMeetingInviteId;
  Timer? _highlightClearTimer;
  // by remas start
  final Map<String, double> _trackedGpsLatByUser = {};
  final Map<String, double> _trackedGpsLngByUser = {};
  final Map<String, DateTime> _trackedUpdatedAtByUser = {};
  final Map<String, double> _venueLatByRequest = {};
  final Map<String, double> _venueLngByRequest = {};
  final Map<String, String> _userPinColorMap = {};
  int _nextPinColorIndex = 0;
  final Map<String, String> _requestIdByTrackedUser = {};
  // by remas end
  bool _highlightClearScheduled = false;
  Timer? _clockTimer;
  // ===== Track Map (Pin JS) =====
  WebViewController? _trackMapController;
  final Set<String> _refreshingRequestIds = {};
  static const Duration _refreshCooldownDuration = Duration(minutes: 10);
  static const Duration _refreshCooldownMessageDuration = Duration(seconds: 2);
  final Map<String, DateTime> _refreshCooldownUntilByRequestId = {};
  final Set<String> _refreshCooldownMessageRequestIds = {};
  final Map<String, Timer> _refreshCooldownMessageTimers = {};

  /// 0 = Sent, 1 = Received (same order as History page)
  int _selectedFilterIndex = 0;
  static const List<String> _requestFilters = ['Sent', 'Received'];
  final ScrollController _scrollController = ScrollController();
  Timer? _meetingPointCardTimer;
  Stream<MeetingPointRecord?>? _activeMeetingPointCardStream;
  Stream<MeetingPointRecord?>? _activeMeetingPointCountStream;
  Stream<List<MeetingPointRecord>>? _activeMeetingPointListStream;
  MeetingPointRecord? _lastKnownActiveMeetingCard;
  MeetingPointRecord? _lastKnownActiveMeetingCount;
  List<MeetingPointRecord> _lastKnownBlockingMeetings = [];
  String? _expandedMeetingInviteId;

  // ── Arrival section state ──────────────────────────────────────────────────
  Timer? _arrivalTimer;
  String? _expandedArrivalParticipantId; // userId of expanded participant card
  DateTime? _lastMeetingMaintainAttemptAt;

  /// IDs of meeting invitations the user locally declined — hidden immediately
  /// in the UI before Firestore confirms the write.
  final Set<String> _locallyDeclinedMeetingIds = {};
  static const Duration _kMeetingMaintainThrottle = Duration(seconds: 2);

  /// Key for the tile to scroll to when opening from notification (by request ID).
  final GlobalKey _scrollToTargetKey = GlobalKey();
  Timer? _scrollToTargetTimer;

  /// Key for the meeting invitation tile to scroll to when opening from notification.
  final GlobalKey _scrollToMeetingInviteKey = GlobalKey();
  Timer? _scrollToMeetingInviteTimer;
  String? _meetingInviteScrollTargetId;

  //Stream<MeetingPointRecord?>
  // get _meetingPointCardStream =>
  Stream<MeetingPointRecord?> get _meetingPointCardStream =>
      _activeMeetingPointCardStream ??=
          MeetingPointService.watchActiveForCurrentUser();

  Stream<MeetingPointRecord?> get _meetingPointCountStream =>
      _activeMeetingPointCountStream ??=
          MeetingPointService.watchActiveForCurrentUser();

  Stream<List<MeetingPointRecord>> get _meetingPointListStream =>
      _activeMeetingPointListStream ??=
          MeetingPointService.watchAllBlockingForCurrentUser();

  MeetingPointRecord? _resolveActiveMeetingCardSnapshot(
    AsyncSnapshot<MeetingPointRecord?> snapshot,
  ) {
    if (snapshot.hasError) return _lastKnownActiveMeetingCard;

    // Only update the cache once the stream has settled (active). During the
    // brief ConnectionState.waiting period that occurs when the stream is
    // refreshed, keep the previous cached value so the card doesn't flicker.
    if (snapshot.connectionState == ConnectionState.active) {
      _lastKnownActiveMeetingCard = snapshot.data;
    }
    return _lastKnownActiveMeetingCard;
  }

  MeetingPointRecord? _resolveActiveMeetingCountSnapshot(
    AsyncSnapshot<MeetingPointRecord?> snapshot,
  ) {
    if (snapshot.hasError) return _lastKnownActiveMeetingCount;

    if (snapshot.connectionState == ConnectionState.active) {
      _lastKnownActiveMeetingCount = snapshot.data;
    }
    return _lastKnownActiveMeetingCount;
  }

  List<MeetingPointRecord> _resolveMeetingListSnapshot(
    AsyncSnapshot<List<MeetingPointRecord>> snapshot,
  ) {
    if (snapshot.hasError) return _lastKnownBlockingMeetings;
    if (snapshot.connectionState == ConnectionState.active) {
      _lastKnownBlockingMeetings = snapshot.data ?? [];
    }
    return _lastKnownBlockingMeetings;
  }

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
            final refreshRequestedAtRaw = data['refreshRequestedAt'];
            final refreshRequestedAt = refreshRequestedAtRaw is Timestamp
                ? refreshRequestedAtRaw.toDate()
                : null;
            final refreshRequestedBy = (data['refreshRequestedBy'] ?? '')
                .toString()
                .trim();

            final startStr = TimeOfDay.fromDateTime(startAt).format(context);
            final endStr = TimeOfDay.fromDateTime(endAt).format(context);

            return TrackingRequest(
              id: d.id,
              trackedUserName: (data['receiverName'] ?? '').toString(),
              trackedUserPhone: (data['receiverPhone'] ?? '').toString(),
              receiverId: (data['receiverId'] ?? '').toString(),
              senderId: (data['senderId'] ?? '').toString(),
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
              refreshRequestedAt: refreshRequestedAt,
              refreshRequestedBy: refreshRequestedBy.isEmpty
                  ? null
                  : refreshRequestedBy,
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
            final refreshRequestedAtRaw = data['refreshRequestedAt'];
            final refreshRequestedAt = refreshRequestedAtRaw is Timestamp
                ? refreshRequestedAtRaw.toDate()
                : null;
            final refreshRequestedBy = (data['refreshRequestedBy'] ?? '')
                .toString()
                .trim();

            return TrackingRequest(
              id: d.id,
              trackedUserName: (data['receiverName'] ?? '').toString(),
              trackedUserPhone: (data['receiverPhone'] ?? '').toString(),
              receiverId: (data['receiverId'] ?? '').toString(),
              senderId: (data['senderId'] ?? '').toString(),
              senderName: (data['senderName'] ?? 'Someone').toString(),
              senderPhone: (data['senderPhone'] ?? '').toString(),
              status: (data['status'] ?? '').toString(),
              startAt: startAt,
              endAt: endAt,
              startTime: TimeOfDay.fromDateTime(startAt).format(context),
              endTime: TimeOfDay.fromDateTime(endAt).format(context),
              venueName: (data['venueName'] ?? '').toString(),
              venueId: (data['venueId'] ?? '').toString(),
              refreshRequestedAt: refreshRequestedAt,
              refreshRequestedBy: refreshRequestedBy.isEmpty
                  ? null
                  : refreshRequestedBy,
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

// by remas start
function ensurePin(viewer, userId, label, pinColor){
  pinColor = pinColor || "#ff3b30";
// by remas end
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
// by remas start
    buildTeardropPin(hs, { size: 22, color: pinColor, label: label || "" });
    hs.__labelText = label || "";
    hs.__pinColor = pinColor;
  }else{
    const newLabel = label || "";
    const colorChanged = hs.__pinColor !== pinColor;
    if (hs.__labelText !== newLabel || colorChanged) {
      hs.innerHTML = "";
      buildTeardropPin(hs, { size: 22, color: pinColor, label: newLabel });
      hs.__labelText = newLabel;
      hs.__pinColor = pinColor;
    }
    // by remas end
  }
  return hs;
}

// by remas start
window.upsertTrackedPin = function(userId,x,y,z,label,pinColor){
  pinColor = pinColor || "#ff3b30";
// by remas end
  const viewer = getViewer();
  if(!viewer || !userId) return false;

  const hs = ensurePin(viewer, userId, label, pinColor);

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
    _activeMeetingPointCardStream =
        MeetingPointService.watchActiveForCurrentUser();
    _activeMeetingPointCountStream =
        MeetingPointService.watchActiveForCurrentUser();
    _loadVenueMaps();
    if (widget.initialMeetingPointId != null) {
      _isTrackingView = false;
      _expandedMeetingInviteId = widget.initialMeetingPointId;
      _highlightMeetingInviteId = widget.initialMeetingPointId;
      _meetingInviteScrollTargetId = widget.initialMeetingPointId;
      _startScrollToMeetingInviteWhenReady();
    } else if (widget.initialExpandRequestId != null) {
      _expandedRequestId = widget.initialExpandRequestId;
      _highlightRequestId = widget.initialExpandRequestId;
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
    _meetingPointCardTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Keep meeting-point countdown badge ticking when visible.
      if (!_isTrackingView) setState(() {});
      // Ensure timed transitions (cancel / step advance) happen immediately
      // when the displayed countdown reaches 00:00.
      unawaited(_maybeMaintainActiveMeetingIfNeeded());
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
        if (rid.isNotEmpty) {
          activeReceiverIds.add(rid);

          final requestId = d.id;
          final venueId = (data['venueId'] ?? '').toString().trim();

          _requestIdByTrackedUser[rid] = requestId;

          if (venueId.isNotEmpty) {
            _loadVenueCoords(venueId, requestId);
          }
        }
      }

      final currentIds = _userLocSubs.keys.toSet();
      final toRemove = currentIds.difference(activeReceiverIds);
      // by remas start
      for (final id in toRemove) {
        _userLocSubs[id]?.cancel();
        _userLocSubs.remove(id);
        _trackedPosByUser.remove(id);
        _trackedFloorByUser.remove(id);
        _trackedNameByUser.remove(id);
        _trackedGpsLatByUser.remove(id);
        _trackedGpsLngByUser.remove(id);
        _trackedUpdatedAtByUser.remove(id);

        final requestId = _requestIdByTrackedUser[id];
        if (requestId != null) {
          _venueLatByRequest.remove(requestId);
          _venueLngByRequest.remove(requestId);
        }
        _requestIdByTrackedUser.remove(id);

        _trackMapController?.runJavaScript("removeTrackedPin('$id');");
      } // by remas end

      final toAdd = activeReceiverIds.difference(currentIds);

      for (final id in toAdd) {
        // by remas start
        // Assign a unique color to this user if not already assigned
        if (!_userPinColorMap.containsKey(id)) {
          _userPinColorMap[id] =
              _pinColors[_nextPinColorIndex % _pinColors.length];
          _nextPinColorIndex++;
        }
        // by remas end

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

              // by remas start
              final gpsLat = (location['gpsLat'] as num?)?.toDouble();
              final gpsLng = (location['gpsLng'] as num?)?.toDouble();
              final updatedAtRaw = location['updatedAt'];
              final updatedAt = updatedAtRaw is Timestamp
                  ? updatedAtRaw.toDate()
                  : null;
              if (gpsLat != null) _trackedGpsLatByUser[id] = gpsLat;
              if (gpsLng != null) _trackedGpsLngByUser[id] = gpsLng;
              if (updatedAt != null) _trackedUpdatedAtByUser[id] = updatedAt;
              // by remas end

              if (bx == null || by == null || bz == null) {
                _trackedPosByUser.remove(id);
                _trackedFloorByUser.remove(id);
                _trackedNameByUser.remove(id);
                _trackMapController?.runJavaScript("hideTrackedPin('$id');");
                return;
              }

              final gltf = _blenderToGltf(x: bx!, y: by!, z: bz!);
              _trackedPosByUser[id] = gltf;
              _trackedFloorByUser[id] = floorRaw;
              _trackedNameByUser[id] = displayName;
              _applyAllTrackedPinsToViewer();
            });
      }

      _applyAllTrackedPinsToViewer();
    });
  }

  void _startHighlightClearTimer() {
    _highlightClearScheduled = true;
    _highlightClearTimer?.cancel();

    _highlightClearTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      setState(() {
        _highlightRequestId = null;
        _highlightMeetingInviteId = null;
        _highlightedDisconnectedIds.clear();
        _highlightClearScheduled = false;
      });
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
        _startHighlightClearTimer();
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

  void _startScrollToMeetingInviteWhenReady() {
    int attempts = 0;
    const maxAttempts = 25; // ~2.5 seconds
    _scrollToMeetingInviteTimer?.cancel();
    _scrollToMeetingInviteTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (!mounted || attempts >= maxAttempts) {
          _scrollToMeetingInviteTimer?.cancel();
          _scrollToMeetingInviteTimer = null;
          return;
        }
        attempts++;
        final ctx = _scrollToMeetingInviteKey.currentContext;
        if (ctx != null) {
          _scrollToMeetingInviteTimer?.cancel();
          _scrollToMeetingInviteTimer = null;
          _startHighlightClearTimer();
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
      },
    );
  }

  // by remas start
  /// Scrolls to the first disconnected friend and highlights all disconnected tiles briefly
  // by remas start
  // Highlights ALL disconnected friends, not just the first one
  final Set<String> _highlightedDisconnectedIds = {};
  // by remas start
  void _scrollToAllActive(List<TrackingRequest> active) {
    if (active.isEmpty) return;

    if (_selectedFilterIndex != 0) {
      setState(() => _selectedFilterIndex = 0);
    }

    setState(() {
      _highlightedDisconnectedIds
        ..clear()
        ..addAll(active.map((r) => r.id));
      _highlightRequestId = active.first.id;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });

    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _highlightRequestId = null;
          _highlightedDisconnectedIds.clear();
          _highlightClearScheduled = false;
        });
      }
    });
  }

  // by remas end
  void _scrollToDisconnected(List<TrackingRequest> active) {
    final disconnected = active
        .where((r) => !_isConnected(r.receiverId, r.id))
        .toList();
    if (disconnected.isEmpty) return;

    // Switch to Sent filter if not already there
    if (_selectedFilterIndex != 0) {
      setState(() => _selectedFilterIndex = 0);
    }

    // Highlight all disconnected friends
    setState(() {
      _highlightedDisconnectedIds
        ..clear()
        ..addAll(disconnected.map((r) => r.id));
      _highlightRequestId = disconnected.first.id;
    });

    // Scroll to first disconnected friend after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });

    // Clear all highlights after 3 seconds
    _startHighlightClearTimer();
  }
  // by remas end

  @override
  void dispose() {
    _clockTimer?.cancel();
    _meetingPointCardTimer?.cancel();
    _arrivalTimer?.cancel();
    _scrollToTargetTimer?.cancel();
    _scrollToMeetingInviteTimer?.cancel();
    _highlightClearTimer?.cancel();
    _activeReqSub?.cancel();

    // cancel all tracked-users subscriptions
    for (final sub in _userLocSubs.values) {
      sub.cancel();
    }
    _userLocSubs.clear();

    for (final timer in _refreshCooldownMessageTimers.values) {
      timer.cancel();
    }
    _refreshCooldownMessageTimers.clear();
    _refreshCooldownMessageRequestIds.clear();

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

    final currentLabel = _currentFloorLabel();

    if (_trackedPosByUser.isEmpty) {
      _pendingPinApply = false;
      return;
    }

    // by remas start
    for (final entry in _trackedPosByUser.entries) {
      final userId = entry.key;
      final pos = entry.value;
      // by remas end

      final trackedFloorLabel = _trackedFloorByUser[userId] ?? '';
      final ok = _floorsMatch(trackedFloorLabel, currentLabel);

      if (!ok) {
        await _trackMapController!.runJavaScript("hideTrackedPin('$userId');");
        continue;
      }

      // by remas start
      final updatedAt = _trackedUpdatedAtByUser[userId];
      final hasRecentLocation =
          updatedAt != null &&
          DateTime.now().difference(updatedAt).inHours < 24;

      if (!hasRecentLocation) {
        await _trackMapController!.runJavaScript("hideTrackedPin('$userId');");
        continue;
      }
      final requestId = _requestIdByTrackedUser[userId];

      final outsideVenue = requestId != null
          ? _isOutsideVenue(userId, requestId)
          : false;
      final pinColor = outsideVenue
          ? '#9E9E9E'
          : (_userPinColorMap[userId] ?? '#FF3B30');
      // by remas end

      final x = (pos['x'] ?? 0).toDouble();
      final y = (pos['y'] ?? 0).toDouble();
      final z = (pos['z'] ?? 0).toDouble();

      final label = (_trackedNameByUser[userId] ?? 'User').replaceAll(
        "'",
        "\\'",
      );

      // by remas start
      _trackMapController!.runJavaScript(
        "upsertTrackedPin('$userId',$x,$y,$z,'$label','$pinColor');",
      );
      // by remas end
    }

    _pendingPinApply = false;
  }
  // by remas start ─────────────────────────────────────────────────────────

  /// Loads venue lat/lng from Firestore and caches it by cacheKey
  Future<void> _loadVenueCoords(String venueId, String cacheKey) async {
    if (_venueLatByRequest.containsKey(cacheKey)) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(venueId)
          .get();
      final data = doc.data();
      if (data == null) return;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _venueLatByRequest[cacheKey] = lat;
        _venueLngByRequest[cacheKey] = lng;
      }
    } catch (e) {
      debugPrint('[TRACK] Failed to load venue coords: $e');
    }
  }

  /// Returns true if the friend is outside the venue boundary (>500m)
  bool _isOutsideVenue(String userId, String cacheKey) {
    final lat = _trackedGpsLatByUser[userId];
    final lng = _trackedGpsLngByUser[userId];
    final vLat = _venueLatByRequest[cacheKey];
    final vLng = _venueLngByRequest[cacheKey];
    if (lat == null || lng == null || vLat == null || vLng == null)
      return false;
    final distance = Geolocator.distanceBetween(lat, lng, vLat, vLng);
    return distance > 500;
  }

  /// Returns true if the friend is connected:
  /// - Has a location updated within the last 24 hours AND inside venue
  bool _isConnected(String userId, String cacheKey) {
    final updatedAt = _trackedUpdatedAtByUser[userId];
    if (updatedAt == null) return false;
    final isRecent = DateTime.now().difference(updatedAt).inHours < 24;
    if (!isRecent) return false;
    return !_isOutsideVenue(userId, cacheKey);
  }

  /// Returns human-readable last update time
  String _lastUpdateText(String userId) {
    final updatedAt = _trackedUpdatedAtByUser[userId];

    if (updatedAt == null) {
      return 'No recent location';
    }

    final now = DateTime.now();
    final diff = now.difference(updatedAt);

    if (diff.inHours >= 24) {
      return 'No recent location';
    }

    final String timeAgo = diff.inSeconds < 60
        ? 'Just now'
        : _timeAgo(updatedAt);

    final requestId = _requestIdByTrackedUser[userId];
    final outsideVenue = requestId != null
        ? _isOutsideVenue(userId, requestId)
        : false;

    return 'Location updated • $timeAgo';
  }

  /// Returns a green or grey dot widget based on connection status
  Widget _connectionDot(String userId, String cacheKey) {
    final connected = _isConnected(userId, cacheKey);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // by remas start
        color: connected ? const Color(0xFF4CAF50) : Colors.grey[400],
        // by remas end
      ),
    );
  }

  // by remas start
  /// Returns a consistent unique color for a connected user based on their userId
  static const List<String> _pinColors = [
    '#FF3B30',
    '#007AFF',
    '#34C759',
    '#FF9500',
    '#AF52DE',
    '#FF2D55',
    '#5AC8FA',
    '#FFCC00',
  ];

  // by remas end ─────────────────────────────────────────────────────────────

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

  String? _currentStepTimerLabel(MeetingPointRecord meeting) {
    final deadline = meeting.activeDeadline;
    if (deadline == null) return null;
    final seconds = deadline
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 3600);
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _hostStepLabel(int step) {
    switch (step) {
      case 4:
        return 'Waiting for participants';
      case 5:
        return 'Suggested meeting point';
      default:
        return 'Create meeting point';
    }
  }

  int _inviteeStep(MeetingPointRecord meeting, String currentUserId) {
    final me = meeting.participantFor(currentUserId);
    if (me == null || me.isPending) return 1;
    // Step 3 = waiting for host to confirm the suggested point.
    // This happens either when the host explicitly advanced (hostStep >= 5)
    // OR when no participants are still pending (everyone responded, so
    // the wait-timer expiry will advance to step 5 imminently).
    if (me.isAccepted && (meeting.hostStep >= 5 || meeting.pendingCount == 0)) {
      return 3;
    }
    if (me.isAccepted) return 2;
    return 1;
  }

  String _inviteeStepLabel(int step) {
    switch (step) {
      case 1:
        return 'Respond to invitation';
      case 2:
        return 'Accepted and waiting for others';
      case 3:
        return 'Accepted and waiting for host confirmation';
      default:
        return 'Meeting point in progress';
    }
  }

  bool _isBlockingMeetingForUser(MeetingPointRecord? meeting, String? uid) {
    if (meeting == null || uid == null || uid.trim().isEmpty) return false;
    // isActive is derived: true only when status == 'pending'.
    if (!meeting.isActive) return false;
    if (meeting.isHost(uid)) return true;
    final me = meeting.participantFor(uid);
    if (me == null) return false;
    final fullyDeclined =
        meeting.participants.isNotEmpty &&
        meeting.participants.every((p) => p.isDeclined);
    if (fullyDeclined) return false;
    return !me.isDeclined;
  }

  Future<void> _maybeMaintainActiveMeetingIfNeeded() async {
    // Check all blocking meetings for expired deadlines.
    final candidates = _lastKnownBlockingMeetings.isNotEmpty
        ? _lastKnownBlockingMeetings
        : (_lastKnownActiveMeetingCard != null
              ? [_lastKnownActiveMeetingCard!]
              : <MeetingPointRecord>[]);

    final now = DateTime.now();
    final needsMaintain = candidates.any((m) {
      if (!m.isActive) return false;
      final deadline = m.activeDeadline;
      return deadline != null && !deadline.isAfter(now);
    });
    if (!needsMaintain) return;

    final last = _lastMeetingMaintainAttemptAt;
    if (last != null && now.difference(last) < _kMeetingMaintainThrottle) {
      return;
    }
    _lastMeetingMaintainAttemptAt = now;

    // Run maybeMaintain on any expired meeting (host-only transitions are
    // guarded inside maybeMaintain itself).
    final meeting = candidates.firstWhere((m) {
      if (!m.isActive) return false;
      final deadline = m.activeDeadline;
      return deadline != null && !deadline.isAfter(now);
    }, orElse: () => candidates.first);
    if (!meeting.isActive) return;

    try {
      await MeetingPointService.maybeMaintain(meeting);
    } catch (_) {}

    // Force a fresh Firestore subscription so the UI reflects the state
    // change (cancel / step-5 advance) immediately without waiting for the
    // stream to emit on its own — which can lag or be missed entirely.
    if (mounted) {
      _activeMeetingPointCardStream =
          MeetingPointService.watchActiveForCurrentUser();
      _activeMeetingPointCountStream =
          MeetingPointService.watchActiveForCurrentUser();
      _activeMeetingPointListStream =
          MeetingPointService.watchAllBlockingForCurrentUser();
      setState(() {});
    }
  }

  String _firstName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Host';
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts.first;
  }

  Future<void> _showCreateMeetingPointForm({
    bool resumeDraft = false,
    String? meetingPointId,
  }) async {
    final id = meetingPointId?.trim() ?? '';
    if (resumeDraft && id.isNotEmpty) {
      final meeting = await MeetingPointService.getById(id);
      if (!mounted) return;
      if (meeting == null || !meeting.isActive) {
        SnackbarHelper.showError(
          context,
          'This meeting point is no longer active.',
        );
        return;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateMeetingPointForm(
        resumeDraft: resumeDraft,
        meetingPointId: meetingPointId,
      ),
    );

    // When the form closes (step 4 created or any step), the Firestore stream
    // may not have delivered the update to the existing StreamBuilder yet.
    // Reset the streams so the StreamBuilder re-subscribes and immediately
    // receives the current Firestore state, making the host card appear.
    if (mounted) {
      _activeMeetingPointCardStream =
          MeetingPointService.watchActiveForCurrentUser();
      _activeMeetingPointCountStream =
          MeetingPointService.watchActiveForCurrentUser();
      _activeMeetingPointListStream =
          MeetingPointService.watchAllBlockingForCurrentUser();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            kFeatureEnabled ? _buildFullContent() : _buildComingSoon(),
            if (_refreshCooldownMessageRequestIds.isNotEmpty)
              const Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: ErrorMessageBox(
                  message: 'you cannot send many request within short period',
                ),
              ),
          ],
        ),
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

  Widget _buildRequestsLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: AppColors.kGreen),
            SizedBox(height: 12),
            Text(
              'Loading requests...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildMainTabs(),
        ),
        Container(height: 1, color: Colors.black12),
        Expanded(
          child: ListView(
            controller: _scrollController,
            key: const ValueKey<String>('track_requests_list'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
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
                      if (widget.initialExpandRequestId != null &&
                          snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return _buildRequestsLoading();
                      }
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
                      if (widget.initialExpandRequestId != null &&
                          snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return _buildRequestsLoading();
                      }
                      final incoming = snapshot.data ?? [];
                      final scheduled = _receivedScheduledFrom(incoming);
                      final active = _receivedActiveFrom(incoming);
                      return _buildReceivedContent(scheduled, active);
                    },
                  ),
              ] else ...[
                _buildMeetingPointContent(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Guard to prevent calling maybeMaintain on every rebuild — only call once
  // per meeting document ID (maybeMaintain writes updatedAt which causes the
  // stream to re-emit, so calling it every build would be an infinite loop).
  String? _lastMaybeMaintainId;

  Widget _buildMeetingPointContent() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<MeetingPointRecord>>(
      stream: _meetingPointListStream,
      builder: (context, snapshot) {
        final meetings = _resolveMeetingListSnapshot(snapshot);

        // Show spinner only on the very first load when nothing is cached yet.
        final isFirstLoad =
            snapshot.connectionState == ConnectionState.waiting &&
            _lastKnownBlockingMeetings.isEmpty;

        // Split into: confirmed (arrival phase), active setup, and pending invites.
        MeetingPointRecord? confirmedMeeting; // status == 'active'
        MeetingPointRecord?
        activeMeeting; // status == 'pending', host or accepted
        final List<MeetingPointRecord> pendingMeetings = [];

        if (uid != null) {
          for (final m in meetings) {
            if (_locallyDeclinedMeetingIds.contains(m.id)) continue;
            if (m.isConfirmed) {
              confirmedMeeting ??= m;
            } else if (m.isHost(uid)) {
              activeMeeting ??= m;
            } else {
              final me = m.participantFor(uid);
              if (me != null && me.isAccepted) {
                activeMeeting ??= m;
              } else if (me != null && me.isPending) {
                pendingMeetings.add(m);
              }
            }
          }
        }

        // Start/stop the arrival countdown timer.
        if (confirmedMeeting != null) {
          _arrivalTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        } else {
          _arrivalTimer?.cancel();
          _arrivalTimer = null;
        }

        // Disable create when user is in active setup or confirmed arrival phase.
        final canCreateMeetingPoint =
            !isFirstLoad && activeMeeting == null && confirmedMeeting == null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _pillButton(
                    icon: Icons.place_outlined,
                    label: 'Create Meeting Point',
                    enabled: canCreateMeetingPoint,
                    onTap: () => _showCreateMeetingPointForm(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Meeting Point Requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            if (isFirstLoad)
              const SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  color: AppColors.kGreen,
                  backgroundColor: Colors.black12,
                ),
              )
            else if (confirmedMeeting == null &&
                activeMeeting == null &&
                pendingMeetings.isEmpty) ...[
              // ── Nothing at all ──────────────────────────────────────────
              SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    'No meeting point requests',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ] else ...[
              // ── Active meeting point ────────────────────────────────────
              _buildSubsectionLabel('Active Meeting Point'),
              if (confirmedMeeting != null && uid != null) ...[
                // ── Arrival-phase UI ──────────────────────────────────────
                _buildRunningMeetingSection(confirmedMeeting, uid),
              ] else if (activeMeeting != null && uid != null) ...[
                // ── Setup-phase UI ────────────────────────────────────────
                if (activeMeeting.isHost(uid))
                  _buildHostMeetingPointStatusCard(activeMeeting)
                else
                  _buildInviteeMeetingPointStatusCard(activeMeeting, uid),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No active meeting point',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              if (pendingMeetings.isNotEmpty) const SizedBox(height: 16),

              // ── Pending invitations ─────────────────────────────────────
              if (pendingMeetings.isNotEmpty && uid != null) ...[
                _buildSubsectionLabel('Meeting Point Invitations'),
                ...pendingMeetings.map(
                  (m) => Padding(
                    key:
                        _meetingInviteScrollTargetId != null &&
                            m.id == _meetingInviteScrollTargetId
                        ? _scrollToMeetingInviteKey
                        : null,
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildMeetingPointInvitationTile(m, uid),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ARRIVAL PHASE UI  (meeting.status == 'active')
  // ══════════════════════════════════════════════════════════════════════════

  /// Formats a remaining-seconds value as "MM:SS", clamped to min 1:00.
  String _formatArrivalTimer(int totalSecondsLeft) {
    final secs = totalSecondsLeft.clamp(60, 99999);
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Remaining seconds for a person whose estimated minutes is [estMins]
  /// and the meeting was confirmed at [confirmedAt].
  int _arrivalSecondsLeft(DateTime? confirmedAt, int estMins) {
    if (confirmedAt == null) return estMins * 60;
    final deadline = confirmedAt.add(Duration(minutes: estMins));
    return deadline.difference(DateTime.now()).inSeconds;
  }

  /// Formats a DateTime as "HH:mm" (24-h).
  String _formatTime(DateTime dt) {
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  Widget _arrivalStatusChip(String arrivalStatus) {
    late Color bg;
    late Color fg;
    late String label;
    switch (arrivalStatus) {
      case 'arrived':
        bg = AppColors.kGreen.withValues(alpha: 0.12);
        fg = AppColors.kGreen;
        label = 'Arrived';
        break;
      case 'cancelled':
        bg = AppColors.kError.withValues(alpha: 0.12);
        fg = AppColors.kError;
        label = 'Cancelled';
        break;
      default:
        bg = Colors.orange[600]!.withValues(alpha: 0.12);
        fg = Colors.orange[600]!;
        label = 'On the way';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  /// The "Me" card at the top of the arrival section.
  Widget _buildMeArrivalCard({
    required MeetingPointRecord meeting,
    required String uid,
    required bool isHost,
  }) {
    final arrivalStatus = isHost
        ? meeting.hostArrivalStatus
        : meeting.participantFor(uid)?.arrivalStatus ?? 'on_the_way';
    final arrivedAt = isHost
        ? meeting.hostArrivedAt
        : meeting.participantFor(uid)?.arrivedAt;
    final estMins = isHost
        ? meeting.hostEstimatedMinutes
        : (meeting.participantFor(uid)?.estimatedArrivalMinutes ?? 3);
    final locationUpdatedAt = isHost
        ? meeting.hostLocationUpdatedAt
        : meeting.participantFor(uid)?.locationUpdatedAt;

    final secsLeft = _arrivalSecondsLeft(meeting.confirmedAt, estMins);
    final isArrived = arrivalStatus == 'arrived';
    final isCancelled = arrivalStatus == 'cancelled';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.kGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
                  color: AppColors.kGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isHost ? 'Me (Host)' : 'Me',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _arrivalStatusChip(arrivalStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Location updated • ${locationUpdatedAt != null ? _timeAgo(locationUpdatedAt) : 'Unknown'}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Timer or arrived-at line ────────────────────────────────────
          if (!isCancelled)
            if (isArrived && arrivedAt != null)
              Text(
                'Arrived at: ${_formatTime(arrivedAt)}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              )
            else
              Row(
                children: [
                  Text(
                    'Estimated arrive by: ',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  Icon(Icons.timer_outlined, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    _formatArrivalTimer(secsLeft),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

          if (!isCancelled) const SizedBox(height: 14),

          // ── Action buttons ──────────────────────────────────────────────
          if (!isCancelled)
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    text: 'Cancel',
                    onPressed: () =>
                        _cancelArrival(meeting, isHost: isHost, uid: uid),
                  ),
                ),
                if (!isArrived) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      text: 'Arrive',
                      onPressed: () =>
                          _markArrived(meeting, isHost: isHost, uid: uid),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// One participant card in the arrival section (expandable).
  Widget _buildParticipantArrivalCard({
    required MeetingPointParticipant p,
    required MeetingPointRecord meeting,
    required bool isHostParticipant, // this participant IS the host
  }) {
    final isExpanded = _expandedArrivalParticipantId == p.userId;
    final isCancelled = p.arrivalStatus == 'cancelled';
    final isArrived = p.arrivalStatus == 'arrived';
    final secsLeft = _arrivalSecondsLeft(
      meeting.confirmedAt,
      p.estimatedArrivalMinutes,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Collapsed header ──────────────────────────────────────────
          InkWell(
            onTap: isCancelled
                ? null
                : () => setState(() {
                    _expandedArrivalParticipantId = isExpanded
                        ? null
                        : p.userId;
                  }),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.name.trim().isEmpty ? p.phone : p.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _arrivalStatusChip(p.arrivalStatus),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (isCancelled)
                          Text(
                            p.phone,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          )
                        else
                          Text(
                            'Location updated • ${_timeAgo(p.locationUpdatedAt ?? p.updatedAt ?? DateTime.now())}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isCancelled) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                        size: 22,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Expanded body ─────────────────────────────────────────────
          if (isExpanded && !isCancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
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
                              // Participant label
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                  children: [
                                    TextSpan(
                                      text: isHostParticipant
                                          ? 'Participant (Host): '
                                          : 'Participant: ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          '${p.name.trim().isEmpty ? 'Unknown' : p.name} (${p.phone})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Timer or arrived-at
                              if (isArrived && p.arrivedAt != null)
                                Text(
                                  'Arrived at: ${_formatTime(p.arrivedAt!)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w400,
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Text(
                                      'Estimated arrive by: ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 14,
                                      color: Colors.black87,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatArrivalTimer(secsLeft),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Refresh location button — outside the green line
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text(
                        'Refresh Location',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.kGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        // Location refresh — to be implemented by teammate
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Main container for the arrival phase.
  Widget _buildRunningMeetingSection(MeetingPointRecord meeting, String uid) {
    final isHost = meeting.isHost(uid);

    // Participants who originally accepted (they are in the arrival phase).
    final arrivalParticipants = meeting.participants
        .where((p) => p.isAccepted)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Destination info ────────────────────────────────────────────
        if (meeting.venueName.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.kGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: AppColors.kGreen,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        'JOE & THE JUICE',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        meeting.venueName,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // ── Participants subtitle ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                'Meeting Point Participants',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey[500],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(
                    255,
                    132,
                    132,
                    132,
                  ).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group, size: 14, color: AppColors.kGreen),
                    const SizedBox(width: 4),
                    Text(
                      '${1 + arrivalParticipants.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.kGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Me card ────────────────────────────────────────────────────
        _buildMeArrivalCard(meeting: meeting, uid: uid, isHost: isHost),
        const SizedBox(height: 8),

        // ── Other participants ──────────────────────────────────────────
        // If I am NOT the host, show the host as first participant card.
        if (!isHost)
          _buildParticipantArrivalCard(
            p: MeetingPointParticipant(
              userId: meeting.hostId,
              name: meeting.hostName,
              phone: meeting.hostPhone,
              status: 'accepted',
              arrivalStatus: meeting.hostArrivalStatus,
              arrivedAt: meeting.hostArrivedAt,
              estimatedArrivalMinutes: meeting.hostEstimatedMinutes,
              locationUpdatedAt: meeting.hostLocationUpdatedAt,
            ),
            meeting: meeting,
            isHostParticipant: true,
          ),

        // Other participants (excluding me).
        ...arrivalParticipants
            .where((p) => p.userId != uid)
            .map(
              (p) => _buildParticipantArrivalCard(
                p: p,
                meeting: meeting,
                isHostParticipant: p.userId == meeting.hostId,
              ),
            ),
      ],
    );
  }

  Future<void> _markArrived(
    MeetingPointRecord meeting, {
    required bool isHost,
    required String uid,
  }) async {
    final now = DateTime.now();
    try {
      await MeetingPointService.updateArrivalStatus(
        meetingPointId: meeting.id,
        isHost: isHost,
        userId: uid,
        arrivalStatus: 'arrived',
        arrivedAt: now,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to mark arrived: $e')));
      }
    }
  }

  Future<void> _cancelArrival(
    MeetingPointRecord meeting, {
    required bool isHost,
    required String uid,
  }) async {
    // ── Participant: simple two-button confirmation ────────────────────────
    if (!isHost) {
      final confirmed = await ConfirmationDialog.showDeleteConfirmation(
        context,
        title: 'Cancel Participation?',
        message: 'You will be removed from this active meeting point.',
        cancelText: 'Keep',
        confirmText: 'Cancel',
      );
      if (confirmed != true) return;
      try {
        await MeetingPointService.updateArrivalStatus(
          meetingPointId: meeting.id,
          isHost: false,
          userId: uid,
          arrivalStatus: 'cancelled',
        );
      } catch (e) {
        if (mounted)
          SnackbarHelper.showError(
            context,
            'Failed to cancel. Please try again.',
          );
      }
      return;
    }

    // ── Host: three-button dialog ─────────────────────────────────────────
    // Returns 'all' | 'me' | null (keep)
    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text(
                'Cancel Meeting?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx, null),
              icon: Icon(Icons.close, size: 20, color: Colors.grey[600]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: const Text(
          'As the host, you can cancel the meeting for everyone or just remove yourself.',
          style: TextStyle(fontSize: 15),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          // Cancel for all
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.kError,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Cancel for all participants',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Cancel for me
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, 'me'),
              style: TextButton.styleFrom(
                backgroundColor: Colors.grey[200],
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Cancel for me',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (choice == null) return;

    try {
      if (choice == 'all') {
        await MeetingPointService.cancelMeetingForAll(meeting.id);
        if (mounted)
          SnackbarHelper.showSuccess(
            context,
            'Meeting point cancelled for all.',
          );
      } else {
        await MeetingPointService.updateArrivalStatus(
          meetingPointId: meeting.id,
          isHost: true,
          userId: uid,
          arrivalStatus: 'cancelled',
        );
      }
    } catch (e) {
      if (mounted)
        SnackbarHelper.showError(
          context,
          'Failed to cancel. Please try again.',
        );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // END ARRIVAL PHASE UI
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildHostMeetingPointStatusCard(MeetingPointRecord meeting) {
    final timerLabel = _currentStepTimerLabel(meeting);
    final completedSteps = (meeting.hostStep - 1).clamp(0, 5).toInt();
    final progress = completedSteps / 5;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showCreateMeetingPointForm(
          resumeDraft: true,
          meetingPointId: meeting.id,
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8E9E0),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.kGreen.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Meeting point in progress',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.kGreen,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _hostStepLabel(meeting.hostStep),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.kGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'View details',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: AppColors.kGreen.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation((AppColors.kGreen)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Step ${meeting.hostStep} of 5',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.kGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (timerLabel != null) ...[
                    const Spacer(),
                    _meetingTimerBadge(timerLabel),
                  ],
                ],
              ),
              if (meeting.hostStep != 5) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _meetingStatusChip(
                      '${meeting.acceptedCount} Accepted',
                      backgroundColor: AppColors.kGreen.withOpacity(0.11),
                      textColor: AppColors.kGreen,
                    ),
                    _meetingStatusChip(
                      '${meeting.pendingCount} Pending',
                      backgroundColor: Colors.orange.withOpacity(0.1),
                      textColor: Colors.orange.shade700,
                    ),
                    _meetingStatusChip(
                      '${meeting.declinedCount} Declined',
                      backgroundColor: AppColors.kError.withOpacity(0.1),
                      textColor: AppColors.kError,
                    ),
                  ],
                ),
              ],
              if (meeting.hostStep == 4) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: 'Cancel',
                        onPressed: () => _cancelMeetingPoint(meeting),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        text: 'Proceed',
                        enabled: meeting.acceptedCount > 0,
                        onPressed: () => _showCreateMeetingPointForm(
                          resumeDraft: true,
                          meetingPointId: meeting.id,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteeMeetingPointStatusCard(
    MeetingPointRecord meeting,
    String currentUserId,
  ) {
    final me = meeting.participantFor(currentUserId);
    if (me == null) return const SizedBox.shrink();
    final step = _inviteeStep(meeting, currentUserId);
    final timerLabel = _currentStepTimerLabel(meeting);
    final title = me.isPending
        ? '${_firstName(meeting.hostName)} invited you to meet'
        : 'Meeting point in progress';
    final subtitle = me.isPending
        ? 'Respond to the invitation and set your location if you join'
        : _inviteeStepLabel(step);

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8E9E0),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.kGreen.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.kGreen,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showInviteeDetailsSheet(meeting),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.kGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'View details',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (step - 1) / 3,
              minHeight: 7,
              backgroundColor: AppColors.kGreen.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(AppColors.kGreen),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Step $step of 3',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.kGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (timerLabel != null) ...[
                const Spacer(),
                _meetingTimerBadge(timerLabel),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _meetingStatusChip(
                '${meeting.acceptedCount} Accepted',
                backgroundColor: AppColors.kGreen.withOpacity(0.11),
                textColor: AppColors.kGreen,
              ),
              _meetingStatusChip(
                '${meeting.pendingCount} Pending',
                backgroundColor: Colors.orange.withOpacity(0.1),
                textColor: Colors.orange.shade700,
              ),
              _meetingStatusChip(
                '${meeting.declinedCount} Declined',
                backgroundColor: AppColors.kError.withOpacity(0.1),
                textColor: AppColors.kError,
              ),
            ],
          ),
          if (step == 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                text: 'Cancel',
                onPressed: () => _declineMeetingInvite(meeting),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Meeting Point Invitation Tile ───────────────────────────────────────────

  Widget _buildMeetingPointInvitationTile(
    MeetingPointRecord meeting,
    String uid,
  ) {
    final isExpanded = _expandedMeetingInviteId == meeting.id;
    final isHighlighted = _highlightMeetingInviteId == meeting.id;
    final timerLabel = _currentStepTimerLabel(meeting);

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
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _expandedMeetingInviteId = isExpanded ? null : meeting.id;
            }),
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
                          meeting.hostName.isEmpty
                              ? 'Unknown'
                              : meeting.hostName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (timerLabel != null)
                          _meetingTimerBadge(timerLabel)
                        else
                          Text(
                            'Meeting point invitation',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                      ],
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMeetingPointInvitationDetails(meeting),
                  const SizedBox(height: 16),
                  _buildMeetingInviteActionButtons(meeting),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeetingPointInvitationDetails(MeetingPointRecord meeting) {
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
                if (meeting.venueName.isNotEmpty) ...[
                  _labeledDetail('Venue: ', meeting.venueName),
                  const SizedBox(height: 10),
                ],
                Text(
                  'Participants:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                _buildMeetingInviteParticipantRow(
                  name: meeting.hostName,
                  phone: meeting.hostPhone,
                  isHost: true,
                ),
                ...meeting.participants.map(
                  (p) => _buildMeetingInviteParticipantRow(
                    name: p.name,
                    phone: p.phone,
                    isHost: false,
                    status: p.status,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingInviteParticipantRow({
    required String name,
    required String phone,
    required bool isHost,
    String? status, // 'pending' | 'accepted' | 'declined' — null for host
  }) {
    Color? statusColor;
    String? statusLabel;
    if (status != null) {
      switch (status) {
        case 'accepted':
          statusColor = AppColors.kGreen;
          statusLabel = 'Accepted';
          break;
        case 'declined':
          statusColor = AppColors.kError;
          statusLabel = 'Declined';
          break;
        default:
          statusColor = Colors.orange[600]!;
          statusLabel = 'Pending';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unknown' : name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (phone.isNotEmpty)
                  Text(
                    phone,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
          if (isHost)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Host',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ),
          if (!isHost && statusLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor!.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMeetingInviteActionButtons(MeetingPointRecord meeting) {
    return Row(
      children: [
        Expanded(
          child: SecondaryButton(
            text: 'Decline',
            onPressed: () => _declineMeetingInvite(meeting),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PrimaryButton(
            text: 'Accept',
            onPressed: () => _acceptMeetingInvite(meeting),
          ),
        ),
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
            // by remas start
            Positioned(
              top: 16,
              left: 16,
              child: StreamBuilder<List<TrackingRequest>>(
                stream: _sentRequestsStream(),
                builder: (context, snapshot) {
                  final all = snapshot.data ?? [];
                  final active = _activeFrom(all);
                  final disconnectedCount = active
                      .where((r) => !_isConnected(r.receiverId, r.id))
                      .length;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Active count badge ──
                      GestureDetector(
                        onTap: _isTrackingView
                            ? () => _scrollToAllActive(active)
                            : null,
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
                                  ? Text(
                                      active.length.toString(),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : StreamBuilder<MeetingPointRecord?>(
                                      stream: _meetingPointCountStream,
                                      builder: (context, snap) {
                                        final meeting =
                                            _resolveActiveMeetingCountSnapshot(
                                              snap,
                                            );
                                        final total = meeting == null
                                            ? 0
                                            : (meeting.invitedCount + 1);
                                        return Text(
                                          total.toString(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        );
                                      },
                                    ),
                            ],
                          ),
                        ),
                      ),
                      // ── Not Connected badge ──
                      if (_isTrackingView && disconnectedCount > 0) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _scrollToDisconnected(active),
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
                                Icon(
                                  Icons.person_off_outlined,
                                  size: 16,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  disconnectedCount.toString(),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            // by remas end
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

  Widget _meetingTimerBadge(String timerLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: AppColors.kGreen),
          const SizedBox(width: 5),
          Text(
            timerLabel,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.kGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showInviteeDetailsSheet(MeetingPointRecord meeting) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    final me = meeting.participantFor(currentUid);
    if (me == null) return;
    final step = _inviteeStep(meeting, currentUid);
    final timerLabel = _currentStepTimerLabel(meeting);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.location_on_outlined,
                        color: Colors.grey[600],
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Meeting Point Request',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _inviteeStepLabel(step),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
              // ── Scrollable body ──────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: step / 3,
                          minHeight: 7,
                          backgroundColor: AppColors.kGreen.withValues(
                            alpha: 0.2,
                          ),
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.kGreen,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Step $step of 3',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.kGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Section title
                      const Text(
                        'Meeting point details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Details block with green left bar
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
                                    'Host: ',
                                    meeting.hostPhone.isEmpty
                                        ? meeting.hostName
                                        : '${meeting.hostName} (${meeting.hostPhone})',
                                  ),
                                  const SizedBox(height: 8),
                                  _labeledDetail('Venue: ', meeting.venueName),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Participants label + timer
                      Row(
                        children: [
                          Text(
                            'Participants:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (timerLabel != null) ...[
                            const Spacer(),
                            _meetingTimerBadge(timerLabel),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...meeting.participants.map(
                        (p) => _buildInviteeParticipantStatusRow(
                          p,
                          isMe: p.userId == currentUid,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Note
                      Text(
                        'Note: You can cancel your participation in this meeting point.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Cancel button ────────────────────────────────────────────
              if (me.isAccepted)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    10,
                    20,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: SecondaryButton(
                      text: 'Cancel',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _declineMeetingInvite(meeting);
                      },
                    ),
                  ),
                )
              else
                SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInviteeParticipantStatusRow(
    MeetingPointParticipant p, {
    bool isMe = false,
  }) {
    final bg = p.isAccepted
        ? AppColors.kGreen.withValues(alpha: 0.1)
        : p.isDeclined
        ? AppColors.kError.withValues(alpha: 0.1)
        : Colors.orange.withValues(alpha: 0.1);
    final textColor = p.isAccepted
        ? AppColors.kGreen
        : p.isDeclined
        ? AppColors.kError
        : Colors.orange.shade700;
    final label = p.isAccepted
        ? 'Accepted'
        : p.isDeclined
        ? 'Declined'
        : 'Pending';

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
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    children: [
                      TextSpan(text: p.name.trim().isEmpty ? p.phone : p.name),
                      if (isMe)
                        TextSpan(
                          text: ' (me)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
                if (p.phone.isNotEmpty && p.name.trim().isNotEmpty)
                  Text(
                    p.phone,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptMeetingInvite(MeetingPointRecord meeting) async {
    final confirmed = await ConfirmationDialog.showPositiveConfirmation(
      context,
      title: 'Accept Invitation',
      message: 'Are you sure you want to accept this meeting point invitation?',
      confirmText: 'Accept',
    );
    if (confirmed != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ── Conflict check ────────────────────────────────────────────────────────
    // Warn if the user is already hosting or has accepted another meeting.
    if (uid != null) {
      MeetingPointRecord? conflicting;
      for (final m in _lastKnownBlockingMeetings) {
        if (m.id == meeting.id) continue;
        if (m.isHost(uid) || m.participantFor(uid)?.isAccepted == true) {
          conflicting = m;
          break;
        }
      }

      if (conflicting != null) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black54,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
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
        if (!mounted || proceed != true) return;

        // Leave / cancel the conflicting meeting before accepting the new one.
        try {
          if (conflicting.isHost(uid)) {
            await MeetingPointService.markHostDecision(
              meetingPointId: conflicting.id,
              accepted: false,
            );
          } else {
            await MeetingPointService.respondToInvitation(
              meetingPointId: conflicting.id,
              accepted: false,
            );
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;

    // ── Location choice ───────────────────────────────────────────────────────
    // Show the navigation choice sheet (Pin on Map / Scan With Camera).
    // The invitation is confirmed only after the user sets their location.
    final navChoice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildAcceptLocationChoiceSheet(ctx, meeting),
    );
    if (!mounted || navChoice == null) return; // user dismissed without picking

    // ── Set location ──────────────────────────────────────────────────────────
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
    if (!mounted || locationResult == null) return; // user cancelled location

    // ── Accept invitation ─────────────────────────────────────────────────────
    try {
      await MeetingPointService.respondToInvitation(
        meetingPointId: meeting.id,
        accepted: true,
      );
      if (!mounted) return;
      SnackbarHelper.showSuccess(context, 'Invitation accepted.');
    } catch (e) {
      if (!mounted) return;
      SnackbarHelper.showError(
        context,
        'Failed to accept invitation. Please try again.',
      );
    }
  }

  /// Bottom sheet that lets the user pick how to set their starting location
  /// before accepting a meeting point invitation. Returns 'map' or 'camera'.
  Widget _buildAcceptLocationChoiceSheet(
    BuildContext ctx,
    MeetingPointRecord meeting,
  ) {
    final venueName = meeting.venueName.isEmpty
        ? 'Meeting Point'
        : meeting.venueName;
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

  Future<void> _declineMeetingInvite(MeetingPointRecord meeting) async {
    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Decline Invitation',
      message:
          'Are you sure you want to decline this meeting point invitation?',
      confirmText: 'Decline',
    );
    if (confirmed != true) return;

    // Immediately hide the tile in the UI — don't wait for Firestore round-trip.
    if (mounted) setState(() => _locallyDeclinedMeetingIds.add(meeting.id));

    try {
      await MeetingPointService.respondToInvitation(
        meetingPointId: meeting.id,
        accepted: false,
      );
      if (!mounted) return;
      SnackbarHelper.showSuccess(context, 'Invitation declined.');
    } catch (e) {
      // Restore the tile if the write failed.
      if (mounted)
        setState(() => _locallyDeclinedMeetingIds.remove(meeting.id));
      if (!mounted) return;
      SnackbarHelper.showError(
        context,
        'Failed to decline invitation. Please try again.',
      );
    }
  }

  Future<void> _cancelMeetingPoint(MeetingPointRecord meeting) async {
    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Cancel Meeting Point',
      message:
          'Are you sure you want to cancel this meeting point for all participants?',
      confirmText: 'Cancel Meeting',
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('meetingPoints')
          .doc(meeting.id)
          .update({
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      SnackbarHelper.showSuccess(context, 'Meeting point cancelled.');
    } catch (e) {
      if (!mounted) return;
      SnackbarHelper.showError(context, 'Failed to cancel. Please try again.');
    }
  }

  Widget _meetingStatusChip(
    String label, {
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
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

  // by remas start
  /// Sorts active tracking requests: connected (green) first, disconnected (grey) last
  List<TrackingRequest> _sortByConnectionStatus(List<TrackingRequest> list) {
    final sorted = List<TrackingRequest>.from(list);
    sorted.sort((a, b) {
      final aConn = _isConnected(a.receiverId, a.id);
      final bConn = _isConnected(b.receiverId, b.id);
      if (aConn && !bConn) return -1;
      if (!aConn && bConn) return 1;
      return 0;
    });
    return sorted;
  }
  // by remas end

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
          // by remas start
          ..._sortByConnectionStatus(active).map(
            // by remas end
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
    final isHighlighted = _highlightRequestId == r.id;
    if (isHighlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startHighlightClearTimer();
      });
    }
    final now = DateTime.now();
    final bool isPending = r.status == 'pending' && now.isBefore(r.endAt);
    final bool isAcceptedScheduled =
        r.status == 'accepted' && now.isBefore(r.startAt);

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

  /// Received active tile: same design as Sent _buildActiveTile
  /// (heart, same container) but only "Stop Tracking" button.
  /// Show lastSeen (e.g. "2 min ago").
  Widget _buildReceivedActiveTile(TrackingRequest r) {
    final isExpanded = _expandedRequestId == r.id;
    final isHighlighted =
        _highlightRequestId == r.id ||
        _highlightedDisconnectedIds.contains(r.id);

    if (isHighlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startHighlightClearTimer();
      });
    }

    final lastSeen = _timeAgo(r.startAt);

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
              successMessage: 'Active tracking has been terminated',
            );
          }
        },
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: const Text(
          'Stop Sharing',
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
    // by remas start
    final isHighlighted =
        _highlightRequestId == r.id ||
        _highlightedDisconnectedIds.contains(r.id);
    // by remas end
    // For sent requests: show receiver name. For received: show sender name.
    final displayName = r.trackedUserName.isNotEmpty
        ? r.trackedUserName
        : (r.senderName ?? 'Unknown');
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
    final isHighlighted =
        _highlightRequestId == r.id ||
        _highlightedDisconnectedIds.contains(r.id);

    if (isHighlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startHighlightClearTimer();
      });
    }

    // For sent requests: show receiver name. For received: show sender name.
    final displayName = r.trackedUserName.isNotEmpty
        ? r.trackedUserName
        : (r.senderName ?? 'Unknown');

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
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(r.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // by remas start
                  Stack(
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
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: _connectionDot(r.receiverId, r.id),
                      ),
                    ],
                  ),
                  // by remas end
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (_) {
                            final requestId =
                                _requestIdByTrackedUser[r.receiverId];
                            final updatedAt =
                                _trackedUpdatedAtByUser[r.receiverId];

                            final hasRecentLocation =
                                updatedAt != null &&
                                DateTime.now().difference(updatedAt).inHours <
                                    24;

                            final outsideVenue = requestId != null
                                ? _isOutsideVenue(r.receiverId, requestId)
                                : false;

                            final showOutsideBadge =
                                hasRecentLocation && outsideVenue;

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (showOutsideBadge) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Outside venue',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        // by remas start
                        Text(
                          _lastUpdateText(r.receiverId),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        // by remas end
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
              successMessage: 'Tracking request declined after acceptance',
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

  DateTime? _refreshCooldownUntil(TrackingRequest r) {
    final localUntil = _refreshCooldownUntilByRequestId[r.id];
    DateTime? serverUntil;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null &&
        r.refreshRequestedAt != null &&
        r.refreshRequestedBy != null &&
        r.refreshRequestedBy == currentUserId) {
      serverUntil = r.refreshRequestedAt!.add(_refreshCooldownDuration);
    }

    if (localUntil == null) return serverUntil;
    if (serverUntil == null) return localUntil;
    return localUntil.isAfter(serverUntil) ? localUntil : serverUntil;
  }

  bool _isRefreshCooldownActive(TrackingRequest r) {
    final until = _refreshCooldownUntil(r);
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _setRefreshCooldown(String requestId) {
    _refreshCooldownUntilByRequestId[requestId] = DateTime.now().add(
      _refreshCooldownDuration,
    );
  }

  void _showRefreshCooldownMessage(String requestId) {
    _refreshCooldownMessageTimers[requestId]?.cancel();
    if (mounted) {
      setState(() {
        _refreshCooldownMessageRequestIds.add(requestId);
      });
    } else {
      _refreshCooldownMessageRequestIds.add(requestId);
    }

    _refreshCooldownMessageTimers[requestId] = Timer(
      _refreshCooldownMessageDuration,
      () {
        _refreshCooldownMessageTimers.remove(requestId);
        if (!mounted) {
          _refreshCooldownMessageRequestIds.remove(requestId);
          return;
        }
        setState(() {
          _refreshCooldownMessageRequestIds.remove(requestId);
        });
      },
    );
  }

  // Logic to update Firestore
  Future<void> _requestLocationRefresh(TrackingRequest r) async {
    if (_refreshingRequestIds.contains(r.id)) return;
    if (_isRefreshCooldownActive(r)) {
      _showRefreshCooldownMessage(r.id);
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'You must be signed in to send a refresh request.',
        );
      }
      return;
    }

    if (r.receiverId.isEmpty) {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Unable to find the tracked user for this request.',
        );
      }
      return;
    }

    setState(() => _refreshingRequestIds.add(r.id));

    try {
      final refreshToken =
          '${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection('trackRequests')
          .doc(r.id)
          .update({
            'refreshRequestId': refreshToken,
            'refreshRequestedBy': currentUser.uid,
            'refreshRequestedAt': FieldValue.serverTimestamp(),
          });

      _setRefreshCooldown(r.id);

      if (mounted) {
        final targetName = r.trackedUserName.isNotEmpty
            ? r.trackedUserName
            : (r.trackedUserPhone.isNotEmpty ? r.trackedUserPhone : 'friend');
        SnackbarHelper.showSuccess(
          context,
          'Refresh location request sent to $targetName.',
        );
      }
    } catch (e) {
      debugPrint('Failed to request location refresh: $e');
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Failed to send refresh request. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingRequestIds.remove(r.id));
      } else {
        _refreshingRequestIds.remove(r.id);
      }
    }
  }

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
        return 'Tracking request accepted';
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
        // Accept (left) = filled green
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
        const SizedBox(width: 12),
        // Decline (right) = outlined
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
  String _buildDateStr(TrackingRequest r) {
    final isOvernight =
        r.endAt.day != r.startAt.day ||
        r.endAt.month != r.startAt.month ||
        r.endAt.year != r.startAt.year;

    if (isOvernight) {
      final startDay = r.startAt.day;
      final endDay = r.endAt.day;
      final startMonth = _shortMonth(r.startAt.month);
      final endMonth = _shortMonth(r.endAt.month);
      return r.startAt.month == r.endAt.month
          ? '$startDay - $endDay $endMonth'
          : '$startDay $startMonth - $endDay $endMonth';
    }

    return _formatDateForDuration(
      DateTime(r.startAt.year, r.startAt.month, r.startAt.day),
    );
  }

  String _buildTimeStr(TrackingRequest r) {
    return '${r.startTime} - ${r.endTime}';
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

  Widget _buildDetails(TrackingRequest r) {
    return _buildDetailsColumn(
      label: 'Tracked User',
      name: r.trackedUserName,
      phone: r.trackedUserPhone,
      date: _buildDateStr(r),
      time: _buildTimeStr(r),
      venue: r.venueName,
    );
  }

  Widget _buildReceivedDetails(TrackingRequest r) {
    return _buildDetailsColumn(
      label: 'Sender',
      name: r.senderName ?? 'Unknown',
      phone: r.senderPhone ?? '',
      date: _buildDateStr(r),
      time: _buildTimeStr(r),
      venue: r.venueName,
    );
  }

  Widget _buildDetailsColumn({
    required String label,
    required String name,
    required String phone,
    required String date,
    required String time,
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
                Row(
                  children: [
                    _labeledDetail('Date: ', date),
                    const SizedBox(width: 16),
                    _labeledDetail('Time: ', time),
                  ],
                ),
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

  // ========== NAVIGATE TO FRIEND ==========
  void _navigateToFriend(TrackingRequest r) {
    final pos = _trackedPosByUser[r.receiverId];
    final floor = _trackedFloorByUser[r.receiverId] ?? '0';
    final friendName = r.trackedUserName.isNotEmpty
        ? r.trackedUserName
        : 'Friend';

    if (pos == null) {
      SnackbarHelper.showError(
        context,
        'Location of $friendName is not available yet. Try refreshing.',
      );
      return;
    }

    // pos is already in glTF format (x, y, z)
    showNavigationDialog(
      context,
      friendName, // shopName
      r.receiverId, // shopId (friend's userId)
      destinationPoiMaterial: '', // no material
      floorSrc: '', // not needed
      destinationHitGltf: pos, // friend's glTF coordinates
      destinationFloorLabel: floor, // raw floor string (e.g. "0")
      venueId: r.venueId, // same venue
    );
  }

  // ========== ACTION BUTTONS - UPDATED ==========
  Widget _buildActionButtons(TrackingRequest r) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _navigateToFriend(r),
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
        Expanded(child: _buildRefreshButton(r)),
      ],
    );
  }

  Widget _buildRefreshButton(TrackingRequest r) {
    final isSendingRefresh = _refreshingRequestIds.contains(r.id);
    final isCooldownActive = _isRefreshCooldownActive(r);
    final isDisabled = isSendingRefresh || isCooldownActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isDisabled ? null : () => _requestLocationRefresh(r),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(
                  'Refresh Location',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.kGreen.withOpacity(0.4),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (isDisabled)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (isCooldownActive) {
                        _showRefreshCooldownMessage(r.id);
                      }
                    },
                  ),
                ),
              ),
          ],
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
    bool enabled = true,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(
          icon,
          color: enabled ? AppColors.kGreen : Colors.grey[500],
          size: 20,
        ),
        label: Text(
          label,
          style: TextStyle(
            color: enabled ? AppColors.kGreen : Colors.grey[500],
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: enabled ? AppColors.kGreen : Colors.grey.shade400,
            width: 2,
          ),
          shape: shape,
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: Colors.white,
          disabledForegroundColor: Colors.grey[500],
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        color: enabled ? Colors.white : Colors.grey[500],
        size: 20,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: enabled ? Colors.white : Colors.grey[500],
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? AppColors.kGreen : Colors.grey.shade300,
        foregroundColor: enabled ? Colors.white : Colors.grey[500],
        disabledBackgroundColor: Colors.grey.shade300,
        disabledForegroundColor: Colors.grey[500],
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
  final String receiverId;
  final String senderId;
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
  final DateTime? refreshRequestedAt;
  final String? refreshRequestedBy;

  TrackingRequest({
    required this.id,
    required this.trackedUserName,
    required this.trackedUserPhone,
    required this.receiverId,
    required this.senderId,
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
    this.refreshRequestedAt,
    this.refreshRequestedBy,
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
