// ============================================================================
// PATH OVERVIEW SCREEN (split out from navigation_flow_complete.dart)
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:madar_app/nav/navmesh.dart';

class PathOverviewScreen extends StatefulWidget {
  final String shopName;
  final String shopId;
  final String startingMethod;

  /// Material name like "POIMAT_Balenciaga.001" (optional).
  final String destinationPoiMaterial;

  /// Floor model URL/src to open first (optional)
  final String floorSrc;

  /// Destination hit point in glTF coords from map (optional)
  final Map<String, double>? destinationHitGltf;

  const PathOverviewScreen({
    super.key,
    required this.shopName,
    required this.shopId,
    required this.startingMethod,
    this.destinationPoiMaterial = '',
    this.floorSrc = '',
    this.destinationHitGltf,
  });

  @override
  State<PathOverviewScreen> createState() => _PathOverviewScreenState();
}

class _PathOverviewScreenState extends State<PathOverviewScreen> {
  String _currentFloor = '';
  // Caller-provided floor selector. Can be a mapURL (assets/...glb) or a label like "GF"/"F1"/"0"/"1".
  String _requestedFloorToken = '';
  bool _requestedFloorIsUrl = false;

  bool _looksLikeMapUrl(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return t.contains('/') || t.endsWith('.glb') || t.startsWith('http');
  }

  List<Map<String, String>> _venueMaps = [];
  bool _mapsLoading = false;
  String _selectedPreference = 'stairs';
  String _originFloorLabel = 'GF';
  String _desiredStartFloorLabel = '';
  String _estimatedTime = '2 min';
  String _estimatedDistance = '166 m';

  WebViewController? _webCtrl;
  bool _jsReady = false;
  Map<String, double>? _pendingUserPinGltf;
  String? _pendingPoiToHighlight;

  // ---- POI index (for resolving destination coords) ----
  Map<String, Map<String, dynamic>>? _poiByNorm;
  bool _poiLoading = false;


  // ---- Navmesh & path state ----
  NavMesh? _navmeshF1;
  Map<String, double>? _userPosBlender;
  Map<String, double>? _destPosBlender;
  Map<String, double>? _userSnappedBlender;
  Map<String, double>? _destSnappedBlender;

  List<Map<String, double>> _pathPointsGltf = [];
  bool _pathPushed = false;

  // ---- Flutter -> JS helpers (Path Overview) ----
  Future<void> _pushUserPinToJsPath(Map<String, double> gltf) async {
    final c = _webCtrl;
    if (c == null || !_jsReady) return;

    final x = gltf['x'];
    final y = gltf['y'];
    final z = gltf['z'];
    if (x == null || y == null || z == null) return;

    try {
      // webview_flutter (new): runJavaScript
      await c.runJavaScript('window.setUserPinFromFlutter($x,$y,$z);');
    } catch (e) {
      debugPrint('pushUserPinToJsPath failed: $e');
    }
  }

  Future<void> _pushDestinationHighlightToJsPath() async {
    final c = _webCtrl;
    final name = _pendingPoiToHighlight;
    if (c == null || !_jsReady || name == null || name.trim().isEmpty) return;

    final safe = name.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    try {
      await c.runJavaScript("window.highlightPoiFromFlutter('$safe');");
    } catch (e) {
      debugPrint('pushDestinationHighlightToJsPath failed: $e');
    }
  }

  
  // ---- POI JSON loading / destination resolving ----
  String _normPoiKey(String s) {
    var n = (s).trim().toLowerCase();
    n = n.replaceAll(RegExp(r'\.[0-9]+$'), ''); // strip .001 suffix
    n = n.replaceAll(RegExp(r'[\s_]+'), ''); // ignore spaces/underscores
    if (n.startsWith('poimat')) {
      // normalize both "POIMAT_" and "POIMAT " cases
      n = n.replaceFirst(RegExp(r'^poimat[_\s]*'), 'poimat');
    }
    // ensure POIMAT prefix present in normalized string
    if (!n.startsWith('poimat')) {
      n = 'poimat' + n;
    }
    return n;
  }

  Future<void> _loadPoiIndexIfNeeded() async {
    if (_poiByNorm != null || _poiLoading) return;
    _poiLoading = true;
    try {
      // Try common asset locations (you can prune later)
      const candidates = <String>[
        'assets/Solitaire_poi_GF.json',
        'assets/nav_cor/Solitaire_poi_GF.json',
        'assets/poi/Solitaire_poi_GF.json',
        'assets/pois/Solitaire_poi_GF.json',
      ];

      String? jsonStr;
      for (final p in candidates) {
        try {
          jsonStr = await rootBundle.loadString(p);
          debugPrint('✅ POI json loaded: $p');
          break;
        } catch (_) {}
      }
      if (jsonStr == null) {
        debugPrint('❌ POI json not found in assets (Solitaire_poi_GF.json)');
        return;
      }

      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map || decoded['pois'] is! Map) {
        debugPrint('❌ POI json format unexpected: missing "pois" map');
        return;
      }

      final pois = decoded['pois'] as Map;
      final out = <String, Map<String, dynamic>>{};
      for (final e in pois.entries) {
        final key = e.key?.toString() ?? '';
        if (key.isEmpty) continue;
        if (e.value is Map) {
          out[_normPoiKey(key)] = Map<String, dynamic>.from(e.value as Map);
        }
      }
      _poiByNorm = out;
      debugPrint('✅ POI index built: ${out.length} items');
    } catch (e) {
      debugPrint('❌ Failed to build POI index: $e');
    } finally {
      _poiLoading = false;
    }
  }

  Future<void> _resolveDestinationFromPoiJsonIfNeeded() async {
    if (_destPosBlender != null) return;

    final name = (_pendingPoiToHighlight ?? widget.destinationPoiMaterial).trim();
    if (name.isEmpty) return;

    await _loadPoiIndexIfNeeded();
    final idx = _poiByNorm;
    if (idx == null) return;

    final norm = _normPoiKey(name);
    final poi = idx[norm];

    if (poi == null) {
      debugPrint('⚠️ Destination not found in POI json for "$name" (norm="$norm")');
      return;
    }

    final x = (poi['x'] as num?)?.toDouble();
    final y = (poi['y'] as num?)?.toDouble();
    final z = (poi['z'] as num?)?.toDouble();
    if (x == null || y == null || z == null) {
      debugPrint('⚠️ POI json missing x/y/z for "$name"');
      return;
    }

    setState(() {
      _destPosBlender = {'x': x, 'y': y, 'z': z};
      // Optional: set floor label if present
      final f = poi['floor']?.toString();
      if (f != null && f.isNotEmpty) {
        _originFloorLabel = f;
      }
    });

    debugPrint('✅ Destination resolved from POI json: $name -> B=($_destPosBlender)');
    _maybeComputeAndPushPath();
  }


// ---- Coordinate conversions ----
  static Map<String, double> _gltfToBlender(Map<String, double> g) {
    final xg = g['x'] ?? 0.0;
    final yg = g['y'] ?? 0.0;
    final zg = g['z'] ?? 0.0;
    return {'x': xg, 'y': -zg, 'z': yg};
  }

  static Map<String, double> _blenderToGltf(Map<String, double> b) {
    final xb = b['x'] ?? 0.0;
    final yb = b['y'] ?? 0.0;
    final zb = b['z'] ?? 0.0;
    return {'x': xb, 'y': zb, 'z': -yb};
  }

  Future<void> _loadNavmeshF1() async {
    try {
      _navmeshF1 = await NavMesh.loadAsset('assets/nav_cor/navmesh_GF.json');
      debugPrint(
        '✅ Navmesh loaded: v=${_navmeshF1!.v.length} t=${_navmeshF1!.t.length}',
      );
      _maybeComputeAndPushPath();
    } catch (e) {
      debugPrint('❌ Failed to load navmesh_GF.json: $e');
    }
  }

  // --- Path cleanup helpers (makes breadcrumbs look more centered/smooth) ---

  List<List<double>> _smoothAndResamplePath(
    List<List<double>> path,
    NavMesh nm,
  ) {
    var pts = path;

    // 1) Chaikin corner-cutting (smooths jagged A* polylines).
    //pts = _chaikinSmooth(pts, iterations: 1); // Funnel output is already smooth; keep this light

    // 2) Snap each point back onto the navmesh (keeps the path on corridors).
    //pts = pts.map((p) => nm.snapPointXY(p)).toList();

    // 3) Resample: keep one point every ~0.25 units (tune for your scale).
    pts = _resampleByDistance(pts, step: 0.06);

    // 4) Cap hotspots to avoid WebView overload.
    const maxPts = 180;
    if (pts.length > maxPts) {
      final stride = (pts.length / maxPts).ceil();
      final reduced = <List<double>>[];
      for (var i = 0; i < pts.length; i += stride) {
        reduced.add(pts[i]);
      }
      if (reduced.isEmpty || !_samePoint(reduced.last, pts.last)) {
        reduced.add(pts.last);
      }
      pts = reduced;
    }

    return pts;
  }

  List<List<double>> _chaikinSmooth(
    List<List<double>> pts, {
    int iterations = 2,
  }) {
    var out = pts;
    for (var it = 0; it < iterations; it++) {
      if (out.length < 3) return out;
      final next = <List<double>>[];
      next.add(out.first);

      for (var i = 0; i < out.length - 1; i++) {
        final p0 = out[i];
        final p1 = out[i + 1];

        // Q = 0.75*p0 + 0.25*p1
        final q = <double>[
          0.75 * p0[0] + 0.25 * p1[0],
          0.75 * p0[1] + 0.25 * p1[1],
          0.75 * p0[2] + 0.25 * p1[2],
        ];

        // R = 0.25*p0 + 0.75*p1
        final r = <double>[
          0.25 * p0[0] + 0.75 * p1[0],
          0.25 * p0[1] + 0.75 * p1[1],
          0.25 * p0[2] + 0.75 * p1[2],
        ];

        next.add(q);
        next.add(r);
      }

      next.add(out.last);
      out = next;
    }
    return out;
  }

  List<List<double>> _resampleByDistance(
    List<List<double>> pts, {
    required double step,
  }) {
    if (pts.length < 2) return pts;

    final out = <List<double>>[pts.first];
    var acc = 0.0;

    for (var i = 1; i < pts.length; i++) {
      var prev = out.last;
      var cur = pts[i];

      var segLen = _distXY(prev, cur);
      if (segLen <= 1e-9) continue;

      while (acc + segLen >= step) {
        final t = (step - acc) / segLen;
        final nx = prev[0] + (cur[0] - prev[0]) * t;
        final ny = prev[1] + (cur[1] - prev[1]) * t;
        final nz = prev[2] + (cur[2] - prev[2]) * t;
        final np = <double>[nx, ny, nz];
        out.add(np);
        prev = np;
        segLen = _distXY(prev, cur);
        acc = 0.0;
        if (segLen <= 1e-9) break;
      }

      acc += segLen;
    }

    if (!_samePoint(out.last, pts.last)) {
      out.add(pts.last);
    }
    return out;
  }

  List<List<double>> _pullPathTowardCenter(
    List<List<double>> pts, {
    double strength = 0.45,
  }) {
    // NOTE:
    // This is a SAFE placeholder that keeps types correct.
    // It returns the same points until we wire it to triangle-centroid logic.
    // So it compiles and you can continue working.

    // You can still do a tiny smoothing here if you want:
    // return _chaikinSmooth3D(pts, iterations: 1);

    return pts;
  }

  bool _pointInTri2D(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
  ) {
    // Barycentric technique
    final v0x = cx - ax;
    final v0y = cy - ay;
    final v1x = bx - ax;
    final v1y = by - ay;
    final v2x = px - ax;
    final v2y = py - ay;

    final dot00 = v0x * v0x + v0y * v0y;
    final dot01 = v0x * v1x + v0y * v1y;
    final dot02 = v0x * v2x + v0y * v2y;
    final dot11 = v1x * v1x + v1y * v1y;
    final dot12 = v1x * v2x + v1y * v2y;

    final denom = (dot00 * dot11 - dot01 * dot01);
    if (denom.abs() < 1e-12) return false;

    final inv = 1.0 / denom;
    final u = (dot11 * dot02 - dot01 * dot12) * inv;
    final v = (dot00 * dot12 - dot01 * dot02) * inv;

    return (u >= -1e-9) && (v >= -1e-9) && (u + v <= 1.0 + 1e-9);
  }

  int? _findContainingTriXY(NavMesh nm, double x, double y) {
    // O(numTriangles) but OK for shortcut sampling.
    for (int ti = 0; ti < nm.t.length; ti++) {
      final tri = nm.t[ti];
      final a = nm.v[tri[0]];
      final b = nm.v[tri[1]];
      final c = nm.v[tri[2]];

      if (_pointInTri2D(x, y, a[0], a[1], b[0], b[1], c[0], c[1])) {
        return ti;
      }
    }
    return null;
  }

  List<List<double>> _shortcutPathBySampling(
    NavMesh nm,
    List<List<double>> pts,
  ) {
    if (pts.length <= 2) return pts;

    const double sampleStep = 0.06; // smaller = stricter

    bool segmentWalkable(List<double> a, List<double> b) {
      final ax = a[0], ay = a[1];
      final bx = b[0], by = b[1];
      final dx = bx - ax;
      final dy = by - ay;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) return true;

      final steps = math.max(2, (len / sampleStep).ceil());
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = ax + dx * t;
        final y = ay + dy * t;

        // Strict: the sample point must actually be inside the navmesh surface
        final triId = _findContainingTriXY(nm, x, y);
        if (triId == null) return false;
      }
      return true;
    }

    final out = <List<double>>[];
    int i = 0;
    out.add(pts.first);

    while (i < pts.length - 1) {
      int best = i + 1;

      for (int j = pts.length - 1; j > i + 1; j--) {
        if (segmentWalkable(pts[i], pts[j])) {
          best = j;
          break;
        }
      }

      out.add(pts[best]);
      i = best;
    }

    return out;
  }

  double _distXY(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _samePoint(List<double> a, List<double> b) {
    return (a[0] - b[0]).abs() < 1e-6 &&
        (a[1] - b[1]).abs() < 1e-6 &&
        (a[2] - b[2]).abs() < 1e-6;
  }

  Future<void> _pushPathToJs() async {
    final c = _webCtrl;
    if (c == null || !_jsReady) return;
    if (_pathPointsGltf.isEmpty) return;

    // Limit hotspots to avoid perf issues.
    final pts = _pathPointsGltf;

    final jsArg = jsonEncode(pts);
    try {
      await c.runJavaScript('window.setPathFromFlutter($jsArg);');
      _pathPushed = true;
    } catch (e) {
      debugPrint('pushPathToJs failed: $e');
    }
  }

  void _maybeComputeAndPushPath() {
    final nm = _navmeshF1;
    if (nm == null) return;

    final u = _userPosBlender;
    final d = _destPosBlender;

    if (u == null || d == null) return;

    // Snap both endpoints to navmesh in Blender XY.
    final uSnap = nm.snapPointXY([u['x']!, u['y']!, u['z']!]);
    final dSnap = nm.snapPointXY([d['x']!, d['y']!, d['z']!]);

    _userSnappedBlender = {'x': uSnap[0], 'y': uSnap[1], 'z': uSnap[2]};
    _destSnappedBlender = {'x': dSnap[0], 'y': dSnap[1], 'z': dSnap[2]};

    // ---- DEBUG: raw vs snapped (Blender space) ----
    final uRaw = [u['x']!, u['y']!, u['z']!];
    final dRaw = [d['x']!, d['y']!, d['z']!];

    final uDx = uRaw[0] - uSnap[0];
    final uDy = uRaw[1] - uSnap[1];
    final uDist = math.sqrt(uDx * uDx + uDy * uDy);

    final dDx = dRaw[0] - dSnap[0];
    final dDy = dRaw[1] - dSnap[1];
    final dDist = math.sqrt(dDx * dDx + dDy * dDy);

    debugPrint("🟩 startRawB=$uRaw  startSnapB=$uSnap  Δxy=$uDist");
    debugPrint("🟥 destRawB=$dRaw   destSnapB=$dSnap   Δxy=$dDist");

    // Compute path as Blender polyline.
    var pathB = nm.findPathFunnelBlenderXY(start: uSnap, goal: dSnap);

    pathB = _pullPathTowardCenter(pathB, strength: 0.45);
    pathB = _shortcutPathBySampling(nm, pathB);

    if (pathB.isEmpty) {
      debugPrint('⚠️ Navmesh returned empty path');
      return;
    }

    // Smooth & resample so the dots look centered and not “hugging” corners.
    final _prettyB = _smoothAndResamplePath(pathB, nm);

    // Convert polyline points to glTF for model-viewer.
    _pathPointsGltf = _prettyB
        .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
        .toList();

    // If JS is ready, push immediately.
    if (_jsReady && !_pathPushed) {
      _pushPathToJs();
    }
  }

  void _handlePoiMessage(String raw) {
    // Path viewer JS posts a small set of messages. We keep this tolerant and
    // non-breaking.
    try {
      final obj = jsonDecode(raw);
      if (obj is Map && obj['type'] == 'path_viewer_ready') {
        // JS is fully ready (viewer exists + listeners bound).
        if (!_jsReady) {
          _jsReady = true;
        }
        final pin = _pendingUserPinGltf;
        if (pin != null) {
          _pushUserPinToJsPath(pin);
        }
        _pushDestinationHighlightToJsPath();
        if (_pathPointsGltf.isNotEmpty && !_pathPushed) {
          _pushPathToJs();
        } else {
          _maybeComputeAndPushPath();
        }
      }
    } catch (_) {
      // ignore non-JSON
    }
  }

  void _handlePathChannelMessage(String message) {
    // Reserved for future polyline/breadcrumb route updates.
    // Keeping it here prevents runtime/compile errors.
    debugPrint('PATH_CHANNEL: $message');
  }

  static const String _pathViewerJs =
      r'''console.log("✅ PathViewer JS injected");

function postToPOI(obj) {
  try { POI_CHANNEL.postMessage(JSON.stringify(obj)); return true; } catch (e) { return false; }
}
function postToTest(msg) {
  try { JS_TEST_CHANNEL.postMessage(msg); return true; } catch (e) { return false; }
}
function getViewer() { return document.querySelector('model-viewer'); }

function ensurePinStyle() {
  if (document.getElementById("user_pin_hotspot_style")) return;

  const style = document.createElement("style");
  style.id = "user_pin_hotspot_style";
  style.textContent = `
    .userPinHotspot{
      pointer-events:none;
      position:absolute;
      left:0; top:0;
      width:1px; height:1px;
      transform: translate3d(var(--hotspot-x), var(--hotspot-y), 0px);
      will-change: transform;
      z-index: 1000;
      opacity: var(--hotspot-visibility);
    }
  `;
  document.head.appendChild(style);
}

function buildPinUI(el) {
  if (el.__pinBuilt) return;
  el.__pinBuilt = true;

  var wrap = document.createElement("div");
  wrap.style.position = "absolute";
  wrap.style.left = "0";
  wrap.style.top = "0";
  wrap.style.transform = "translate(-50%, -92%)";
  wrap.style.pointerEvents = "none";

  var pin = document.createElement("div");
  pin.style.width = "24px";
  pin.style.height = "24px";
  pin.style.background = "#ff3b30";
  pin.style.borderRadius = "24px 24px 24px 0";
  pin.style.transform = "rotate(-45deg)";
  pin.style.position = "relative";
  pin.style.boxShadow = "0 6px 14px rgba(0,0,0,0.35)";
  pin.style.border = "2px solid rgba(255,255,255,0.85)";

  var inner = document.createElement("div");
  inner.style.width = "8px";
  inner.style.height = "8px";
  inner.style.background = "white";
  inner.style.borderRadius = "999px";
  inner.style.position = "absolute";
  inner.style.left = "50%";
  inner.style.top = "50%";
  inner.style.transform = "translate(-50%, -50%)";
  pin.appendChild(inner);

  var shadow = document.createElement("div");
  shadow.style.width = "18px";
  shadow.style.height = "6px";
  shadow.style.background = "rgba(0,0,0,0.25)";
  shadow.style.borderRadius = "999px";
  shadow.style.margin = "6px auto 0";
  shadow.style.filter = "blur(1px)";

  wrap.appendChild(pin);
  wrap.appendChild(shadow);
  el.appendChild(wrap);
}

function ensureUserPinHotspot(viewer) {
  ensurePinStyle();
  let hs = viewer.querySelector('#userPinHotspot');
  if (!hs) {
    hs = document.createElement('div');
    hs.id = 'userPinHotspot';
    hs.slot = 'hotspot-userpin';
    hs.className = 'userPinHotspot';
    viewer.appendChild(hs);
  }
  buildPinUI(hs);
  return hs;
}

function setUserPin(viewer, pos) {
  const hs = ensureUserPinHotspot(viewer);

  // Force refresh on some Android WebViews
  if (hs.parentElement) {
    hs.parentElement.removeChild(hs);
    viewer.appendChild(hs);
  }

  hs.setAttribute('data-position', `${pos.x} ${pos.y} ${pos.z}`);
  hs.setAttribute('data-normal', `0 1 0`);
  viewer.requestUpdate();
}

// --- Path breadcrumbs (safe hotspots) ---
window.__pathHotspots = window.__pathHotspots || [];
window.__pendingPathPoints = window.__pendingPathPoints || null;

function clearPathHotspots(viewer) {
  try {
    if (!viewer) return;
    (window.__pathHotspots || []).forEach((id) => {
      const el = viewer.querySelector('#' + id);
      if (el && el.parentElement) el.parentElement.removeChild(el);
    });
  } catch(e) {}
  window.__pathHotspots = [];
}

function ensurePathStyle() {
  if (document.getElementById("path_hotspot_style")) return;
  const style = document.createElement("style");
  style.id = "path_hotspot_style";
  style.textContent = `
    .pathDotHotspot{
      pointer-events:none;
      position:absolute;
      left:0; top:0;
      width:1px; height:1px;
      transform: translate3d(var(--hotspot-x), var(--hotspot-y), 0px);
      will-change: transform;
      opacity: var(--hotspot-visibility);
      z-index: 900;
    }
    .pathDot{
      transform: translate(-50%, -50%);
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: #ff8a00;
      box-shadow: 0 1px 3px rgba(0,0,0,0.25);
    }
  `;
  document.head.appendChild(style);
}

window.setPathFromFlutter = function(points) {
  try {
    const viewer = getViewer();
    if (!viewer || !viewer.model) {
      window.__pendingPathPoints = points || [];
      postToTest("⏳ setPathFromFlutter pending (viewer/model not ready)");
      return true;
    }
    ensurePathStyle();
    clearPathHotspots(viewer);

    if (!points || !points.length) return true;

    for (let i = 0; i < points.length; i++) {
      const p = points[i];
      const id = 'pathDot_' + i;
      const hs = document.createElement('div');
      hs.id = id;
      hs.slot = 'hotspot-path-' + i;
      hs.className = 'pathDotHotspot';
      hs.innerHTML = '<div class="pathDot"></div>';
      hs.setAttribute('data-position', `${p.x} ${p.y} ${p.z}`);
      hs.setAttribute('data-normal', `0 1 0`);
      viewer.appendChild(hs);
      window.__pathHotspots.push(id);
    }

    viewer.requestUpdate();
    postToTest('✅ setPathFromFlutter applied: ' + points.length + ' points');
    return true;
  } catch(e) {
    postToTest('❌ setPathFromFlutter error: ' + e);
    return false;
  }
};


// --- Material highlight ---
window.__poiOriginals = window.__poiOriginals || {};
window.__highlightedPoi = null;
window.__pendingUserPin = null;
window.__pendingPoiHighlight = null;
window.__poiMatByNorm = window.__poiMatByNorm || {};

function _normPoiName(s) {
  let n = String(s || "");
  n = n.trim().toLowerCase();
  // remove blender numeric suffixes like .001
  n = n.replace(/\.[0-9]+$/g, "");
  // remove spaces and underscores normalization
  n = n.replace(/\s+/g, "");
  // ensure poimat_ prefix
  if (!n.startsWith("poimat_")) n = "poimat_" + n;
  return n;
}


function _matName(m) {
  try { return m.name || (m.material && m.material.name) || ""; } catch(e){ return ""; }
}



function _getBase(pbr){
  try { if(pbr && typeof pbr.getBaseColorFactor === "function") return [...pbr.getBaseColorFactor()]; } catch(e){}
  try { return (pbr && pbr.baseColorFactor) ? [...pbr.baseColorFactor] : null; } catch(e){}
  return null;
}
function _setBase(pbr, arr){
  if(!pbr || !arr) return;
  try { if(typeof pbr.setBaseColorFactor === "function"){ pbr.setBaseColorFactor(arr); return; } } catch(e){}
  try { pbr.baseColorFactor = arr; } catch(e){}
}
function _getRough(pbr){
  try { if(pbr && typeof pbr.getRoughnessFactor === "function") return pbr.getRoughnessFactor(); } catch(e){}
  try { return (pbr && typeof pbr.roughnessFactor === "number") ? pbr.roughnessFactor : null; } catch(e){}
  return null;
}
function _setRough(pbr, v){
  if(!pbr || typeof v !== "number") return;
  try { if(typeof pbr.setRoughnessFactor === "function"){ pbr.setRoughnessFactor(v); return; } } catch(e){}
  try { pbr.roughnessFactor = v; } catch(e){}
}
function _getEmis(mat){
  try { if(mat && typeof mat.getEmissiveFactor === "function") return [...mat.getEmissiveFactor()]; } catch(e){}
  try { return (mat && mat.emissiveFactor) ? [...mat.emissiveFactor] : null; } catch(e){}
  return null;
}
function _setEmis(mat, arr){
  if(!mat || !arr) return;
  try { if(typeof mat.setEmissiveFactor === "function"){ mat.setEmissiveFactor(arr); return; } } catch(e){}
  try { mat.emissiveFactor = arr; } catch(e){}
}
function cacheOriginalPoiMaterials(viewer) {
  try {
    if (!viewer || !viewer.model || !viewer.model.materials) return;
    viewer.model.materials.forEach((m) => {
      const name = _matName(m);
      if (!name) return;

      // Build normalized lookup for POIMAT_* materials.
      if (name.startsWith("POIMAT_")) {
        const nn = _normPoiName(name);
        window.__poiMatByNorm[nn] = m;
      }

      // Cache originals only for POIMAT_*.
      if (!name.startsWith("POIMAT_")) return;
      if (window.__poiOriginals[name]) return;

      const pbr = m.pbrMetallicRoughness;
      window.__poiOriginals[name] = {
        base: _getBase(pbr),
        emis: _getEmis(m),
        rough: _getRough(pbr),
      };
    });
  } catch (e) {}
}


function _restorePoi(viewer, name) {
  const m = (viewer && viewer.model && viewer.model.materials)
    ? viewer.model.materials.find(x => _matName(x) === name)
    : null;
  const orig = window.__poiOriginals[name];
  if (!m || !orig) return;

  const pbr = m.pbrMetallicRoughness;
  if (orig.base) _setBase(pbr, [...orig.base]);
  if (orig.emis) _setEmis(m, [...orig.emis]);
  if (typeof orig.rough === "number") _setRough(pbr, orig.rough);
}

function _applyPoiHighlight(viewer, name) {
  if (!viewer || !viewer.model || !viewer.model.materials) return false;

  const wantNorm = _normPoiName(name);

  // Ensure caches exist.
  if (!window.__poiMatByNorm || !window.__poiOriginals) {
    window.__poiMatByNorm = window.__poiMatByNorm || {};
    window.__poiOriginals = window.__poiOriginals || {};
  }

  // Build lookup if missing.
  cacheOriginalPoiMaterials(viewer);

  let mat = window.__poiMatByNorm[wantNorm] || null;
  if (!mat) {
    // Fallback scan by normalized name.
    mat = viewer.model.materials.find(m => _normPoiName(_matName(m)) === wantNorm) || null;
    if (mat) window.__poiMatByNorm[wantNorm] = mat;
  }
  if (!mat) return false;

  const actualName = _matName(mat);

  // Restore previous highlight (by actual material name).
  if (window.__highlightedPoi && window.__highlightedPoi !== actualName) {
    _restorePoi(viewer, window.__highlightedPoi);
  }

  // Ensure original cached for this actual material.
  if (!window.__poiOriginals[actualName]) cacheOriginalPoiMaterials(viewer);

  const pbr = mat.pbrMetallicRoughness;
  if (pbr) {
    _setBase(pbr, [0.4353, 0.2941, 0.1608, 1.0]);
    _setRough(pbr, 0.10);
  }
  _setEmis(mat, [0.2612, 0.1765, 0.0965]);

  window.__highlightedPoi = actualName;
  viewer.requestUpdate();
  return true;
}


window.setUserPinFromFlutter = function(x, y, z) {
  const viewer = getViewer();
  const pos = { x: Number(x), y: Number(y), z: Number(z) };

  if (!viewer || !viewer.model) {
    window.__pendingUserPin = pos;
    postToTest("⏳ setUserPinFromFlutter pending (viewer/model not ready)");
    return;
  }
  setUserPin(viewer, pos);
  postToTest(`✅ setUserPinFromFlutter applied: ${pos.x},${pos.y},${pos.z}`);
};

window.highlightPoiFromFlutter = function(name) {
  const viewer = getViewer();
  const n = String(name || "");
  if (!n) return;

  if (!viewer || !viewer.model) {
    window.__pendingPoiHighlight = n;
    postToTest("⏳ highlightPoiFromFlutter pending (viewer/model not ready)");
    return;
  }

  const ok = _applyPoiHighlight(viewer, n);
  postToTest(ok ? ("✅ highlightPoiFromFlutter applied: " + n) : ("⚠️ highlightPoiFromFlutter: material not found yet: " + n));
  if (!ok) {
    // Materials may not be ready yet; retry a few times.
    window.__highlightRetry = (window.__highlightRetry || 0) + 1;
    if (window.__highlightRetry <= 8) {
      window.__pendingPoiHighlight = n;
      setTimeout(() => { try { window.highlightPoiFromFlutter(n); } catch(e) {} }, 250);
      return;
    } else {
      window.__highlightRetry = 0;
    }
  } else {
    window.__highlightRetry = 0;
  }
};

function setupViewer() {
  const viewer = getViewer();
  if (!viewer) return false;
  if (viewer.__pathBound) return true;
  viewer.__pathBound = true;

  viewer.addEventListener("load", () => {
    cacheOriginalPoiMaterials(viewer);

    if (window.__pendingUserPin) {
      setUserPin(viewer, window.__pendingUserPin);
      postToTest("✅ applied pending pin on load");
      window.__pendingUserPin = null;
    }

    if (window.__pendingPoiHighlight) {
      const n = window.__pendingPoiHighlight;
      const ok = _applyPoiHighlight(viewer, n);
      postToTest(ok ? ("✅ applied pending highlight on load: " + n) : ("⚠️ pending highlight not found: " + n));
      window.__pendingPoiHighlight = null;
    }

    if (window.__pendingPathPoints && window.__pendingPathPoints.length) {
      const pts = window.__pendingPathPoints;
      window.__pendingPathPoints = null;
      window.setPathFromFlutter(pts);
      postToTest('✅ applied pending path on load');
    }
  });

  // If the model is already loaded by the time setupViewer() runs,
  // apply any pending state immediately (don't rely solely on the load event).
  try {
    if (viewer && viewer.model) {
      if (window.__pendingUserPin) {
        setUserPin(viewer, window.__pendingUserPin);
        postToTest("✅ applied pending pin (immediate)");
        window.__pendingUserPin = null;
      }
      if (window.__pendingPoiHighlight) {
        const n = window.__pendingPoiHighlight;
        const ok = _applyPoiHighlight(viewer, n);
        postToTest(ok ? ("✅ applied pending highlight (immediate): " + n) : ("⚠️ pending highlight not found (immediate): " + n));
        if (ok) window.__pendingPoiHighlight = null;
      }
      if (window.__pendingPathPoints && window.__pendingPathPoints.length) {
        const pts = window.__pendingPathPoints;
        window.__pendingPathPoints = null;
        window.setPathFromFlutter(pts);
        postToTest("✅ applied pending path (immediate)");
      }
    }
  } catch(e) {}

  postToPOI({ type: "path_viewer_ready" });
  return true;
}

let tries = 0;
const timer = setInterval(function() {
  tries++;
  postToTest("✅ PathViewer JS alive");
  if (setupViewer() || tries > 30) clearInterval(timer);
}, 250);''';

  @override
  void initState() {
    super.initState();

    // Prefer opening the floor that VenuePage passed (if any).
    if (widget.floorSrc.trim().isNotEmpty) {
      _currentFloor = widget.floorSrc.trim();
    }

    // If VenuePage provided a destination hit point, store it for navmesh routing.
    final dh = widget.destinationHitGltf;
    if (dh != null &&
        dh.containsKey('x') &&
        dh.containsKey('y') &&
        dh.containsKey('z')) {
      _destPosBlender = _gltfToBlender(dh);
    }

    final dest = widget.destinationPoiMaterial.trim();
    if (dest.isNotEmpty) {
      _pendingPoiToHighlight = dest;
    } else if (widget.shopId.trim().startsWith('POIMAT_')) {
      // VenuePage often passes POI material as shopId
      _pendingPoiToHighlight = widget.shopId.trim();
    } else {
      _pendingPoiToHighlight = null;
    }

    // If we don't have a destination point yet (common for category/venue list flows),
    // resolve it from Solitaire_poi_GF.json using the destination POI material name.
    // ignore: unawaited_futures
    _resolveDestinationFromPoiJsonIfNeeded();

    _loadVenueMaps();
    _loadUserBlenderPosition();
    _loadNavmeshF1();
  }

  /// Loads the user's saved start location from:
  /// users/{uid}.location.blenderPosition {x,y,z,floor}
  /// We currently use it to display the correct origin floor and to
  /// default the 3D map to that floor.
  Future<void> _loadUserBlenderPosition() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache));

      final data = doc.data();
      if (data == null) return;

      final location = data['location'];
      if (location is! Map) return;

      final bp = location['blenderPosition'];
      if (bp is! Map) return;

      final floorRaw = bp['floor'];
      if (floorRaw == null) return;

      final floorLabel = floorRaw.toString();

      // Keep user's saved pin coords (Blender) and convert to glTF for model-viewer.
      final xNum = bp['x'];
      final yNum = bp['y'];
      final zNum = bp['z'];
      if (xNum is num && yNum is num && zNum is num) {
        _userPosBlender = {
          'x': xNum.toDouble(),
          'y': yNum.toDouble(),
          'z': zNum.toDouble(),
        };
        // Blender (x, y, z) -> glTF (x, y, z)  where glTF.y=Blender.z and glTF.z=-Blender.y
        _pendingUserPinGltf = {
          'x': xNum.toDouble(),
          'y': zNum.toDouble(),
          'z': (-yNum.toDouble()),
        };

        if (_jsReady && _pendingUserPinGltf != null) {
          _pushUserPinToJsPath(_pendingUserPinGltf!);
        }
        if (_jsReady) {}
      }

      if (!mounted) return;
      setState(() {
        _originFloorLabel = floorLabel;
        _desiredStartFloorLabel = floorLabel;
      });

      _maybeComputeAndPushPath();
    } catch (e) {
      debugPrint('Error loading user blenderPosition in PathOverview: $e');
    }
  }

  // ---------- AR Navigation Functions ----------

  /// Check if place has world position for AR navigation
  Future<bool> _hasWorldPosition(String placeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('places')
          .doc(placeId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      // Check for worldPosition field
      return data.containsKey('worldPosition') && data['worldPosition'] != null;
    } catch (e) {
      debugPrint("Error checking world position: $e");
      return false;
    }
  }

  /// Show dialog when AR is not supported for this place
  void _showNoPositionDialog(String placeName) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogPadding = screenWidth < 360 ? 20.0 : 28.0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
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
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.kGreen.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.location_off_rounded,
                      size: 42,
                      color: AppColors.kGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'AR Not Supported',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.kGreen,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  'This place doesn\'t support AR navigation yet. Please check back later!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 24),

                // Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
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
                      'Got it',
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
        );
      },
    );
  }

  /// Open AR navigation with validation
  Future<void> _openNavigationAR() async {
    // Validate world position before proceeding
    final hasPosition = await _hasWorldPosition(widget.shopId);

    if (!hasPosition) {
      if (!mounted) return;
      _showNoPositionDialog(widget.shopName);
      return;
    }

    // Request camera permission
    final status = await Permission.camera.request();

    if (status.isGranted) {
      if (!mounted) return;
      onPressed: () {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Camera page not connected yet')),
  );
};

    } else if (status.isPermanentlyDenied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is permanently denied. Please enable it from Settings.',
          ),
        ),
      );
      openAppSettings();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to use AR.'),
        ),
      );
    }
  }

  Future<void> _loadVenueMaps() async {
    setState(() => _mapsLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc('ChIJcYTQDwDjLj4RZEiboV6gZzM') // Solitaire ID
          .get(const GetOptions(source: Source.serverAndCache));

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
              // 1) Safe default.
              _currentFloor = convertedMaps.first['mapURL'] ?? '';

              // 2) If caller provided a mapURL, prefer it if it exists in venue maps.
              if (_requestedFloorIsUrl && _requestedFloorToken.isNotEmpty) {
                final exists = convertedMaps.any((m) => (m['mapURL'] ?? '') == _requestedFloorToken);
                if (exists) _currentFloor = _requestedFloorToken;
              }

              // 3) If caller provided a label (GF/F1/0/1), resolve it to a mapURL.
              if (!_requestedFloorIsUrl && _requestedFloorToken.isNotEmpty) {
                // Try match by floorNumber first ("GF","F1"...)
                final match = convertedMaps.firstWhere(
                  (m) => (m['floorNumber'] ?? '') == _requestedFloorToken,
                  orElse: () => const {'mapURL': ''},
                );
                var url = match['mapURL'] ?? '';

                // Fallback: accept "0"/"1" as GF/F1 style
                if (url.isEmpty) {
                  final f = _requestedFloorToken.trim();
                  String asLabel = '';
                  if (f == '0') asLabel = 'GF';
                  if (f == '1') asLabel = 'F1';
                  if (f == '2') asLabel = 'F2';
                  if (asLabel.isNotEmpty) {
                    final match2 = convertedMaps.firstWhere(
                      (m) => (m['floorNumber'] ?? '') == asLabel,
                      orElse: () => const {'mapURL': ''},
                    );
                    url = match2['mapURL'] ?? '';
                  }
                }

                if (url.isNotEmpty) _currentFloor = url;
              }

              // 4) If we have a saved starting floor (Pin on Map), prefer showing that floor.
              if (_desiredStartFloorLabel.isNotEmpty) {
                final match = convertedMaps.firstWhere(
                  (m) => (m['floorNumber'] ?? '') == _desiredStartFloorLabel,
                  orElse: () => const {'mapURL': ''},
                );
                final url = match['mapURL'] ?? '';
                if (url.isNotEmpty) _currentFloor = url;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading maps: $e");
    } finally {
      if (mounted) setState(() => _mapsLoading = false);
    }
  }

  void _changePreference(String preference) {
    setState(() {
      _selectedPreference = preference;
      if (preference == 'elevator') {
        _estimatedTime = '3 min';
        _estimatedDistance = '180 m';
      } else if (preference == 'escalator') {
        _estimatedTime = '2.5 min';
        _estimatedDistance = '170 m';
      } else {
        _estimatedTime = '2 min';
        _estimatedDistance = '166 m';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Match venue_page ordering: higher floors first (F2, F1, ... , GF last)
    final sortedMaps = List<Map<String, String>>.from(_venueMaps);

    int floorRank(String s) {
      final f = s.trim().toUpperCase();
      if (f == 'GF') return 0;
      if (f.startsWith('F')) return int.tryParse(f.substring(1)) ?? 0;
      return 0;
    }

    sortedMaps.sort((a, b) {
      final ra = floorRank(a['floorNumber'] ?? '');
      final rb = floorRank(b['floorNumber'] ?? '');
      return rb.compareTo(ra);
    });

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Stack(
          children: [
            // FULL SCREEN MAP - This ensures map is visible behind bottom panel
            Positioned.fill(
              child: _mapsLoading
                  ? const AppLoadingIndicator()
                  : ModelViewer(
                      key: ValueKey(_currentFloor),
                      src: _currentFloor,
                      alt: "3D Map",
                      cameraControls: true,
                      backgroundColor: const Color(0xFFF5F5F0),
                      cameraOrbit: "0deg 65deg 2.5m",
                      minCameraOrbit: "auto 0deg auto",
                      maxCameraOrbit: "auto 90deg auto",
                      cameraTarget: "0m 0m 0m",
                      relatedJs: _pathViewerJs,
                      onWebViewCreated: (c) {
                        _webCtrl = c;
                        _jsReady = false;
                        _pathPushed = false; // WebView reload -> re-push path
                      },
                      javascriptChannels: {
                        JavascriptChannel(
                          'POI_CHANNEL',
                          onMessageReceived: (msg) =>
                              _handlePoiMessage(msg.message),
                        ),
                        JavascriptChannel(
                          'JS_TEST_CHANNEL',
                          onMessageReceived: (msg) {
                            // JS sends a heartbeat until setupViewer() succeeds.
                            if (!_jsReady &&
                                msg.message.contains('PathViewer JS alive')) {
                              _jsReady = true;

                              final pin = _pendingUserPinGltf;
                              if (pin != null) {
                                _pushUserPinToJsPath(pin);
                              }
                              _pushDestinationHighlightToJsPath();

                              // ✅ Critical: if path was computed before JS became ready,
                              // push it now. Otherwise compute + push once endpoints exist.
                              if (_pathPointsGltf.isNotEmpty && !_pathPushed) {
                                _pushPathToJs();
                              } else {
                                _maybeComputeAndPushPath();
                              }
                            }
                          },
                        ),
                        JavascriptChannel(
                          'PATH_CHANNEL',
                          onMessageReceived: (msg) =>
                              _handlePathChannelMessage(msg.message),
                        ),
                      },
                    ),
            ),

            // Floor Selectors - Positioned on map
            Positioned(
              top: 220, // Below header
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  children: sortedMaps.map((map) {
                    final label = map['floorNumber'] ?? '';
                    final url = map['mapURL'] ?? '';
                    final isSelected = _currentFloor == url;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildFloorButton(label, url, isSelected),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Header Container - Overlays on top of map
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(10, 20, 20, 16),
                child: Column(
                  children: [
                    // Location rows with back button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: AppColors.kGreen,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              // Origin Row
                              _locationRow(
                                Icons.radio_button_checked,
                                'Your location',
                                'GF',
                                const Color(0xFF6C6C6C),
                              ),

                              // Dotted Line
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    height: 15,
                                    width: 2,
                                    child: Column(
                                      children: List.generate(
                                        3,
                                        (index) => Expanded(
                                          child: Container(
                                            width: 1.5,
                                            color: index % 2 == 0
                                                ? Colors.grey[400]
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Destination Row
                              _locationRow(
                                Icons.location_on,
                                widget.shopName,
                                'F1',
                                const Color(0xFFC88D52),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Preference buttons row - HORIZONTAL LAYOUT (icon + text)
                    Row(
                      children: [
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Stairs',
                            Icons.stairs,
                            'stairs',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Elevator',
                            Icons.elevator,
                            'elevator',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Escalator',
                            Icons.escalator,
                            'escalator',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom UI Panel - Overlays on map with proper transparency
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Time and Distance Info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_estimatedTime ($_estimatedDistance)',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.shopName,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Divider
                    Divider(color: Colors.grey[300], thickness: 1, height: 1),

                    const SizedBox(height: 20),

                    // Start AR Navigation Button
                    PrimaryButton(
                      text: 'Start AR Navigation',
                      onPressed: _openNavigationAR,
                    ),

                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(IconData icon, String label, String floor, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 25,
          child: Text(
            floor,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[300],
            ),
          ),
        ),
      ],
    );
  }

  // Horizontal preference button (icon next to text)
  Widget _preferenceButtonHorizontal(
    String label,
    IconData icon,
    String value,
  ) {
    final isSelected = _selectedPreference == value;
    return GestureDetector(
      onTap: () => _changePreference(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8E9E0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.kGreen : Colors.grey[500],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? AppColors.kGreen : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // CONSISTENT FLOOR BUTTON - Same as Set Your Location dialog
  Widget _buildFloorButton(String label, String url, bool isSelected) {
    return SizedBox(
      width: 44,
      height: 40,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? AppColors.kGreen : Colors.white,
          foregroundColor: isSelected ? Colors.white : AppColors.kGreen,
          padding: EdgeInsets.zero,
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? AppColors.kGreen : Colors.grey.shade300,
            ),
          ),
        ),
        onPressed: () => setState(() {
          _currentFloor = url;
        }),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ============================================================================
// 5. AR SUCCESS DIALOG
// ============================================================================
