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

  /// Optional human-readable name for destination.
  ///
  /// If [destinationPoiMaterial] is empty, this can be used to resolve the
  /// destination from the POI index.
  final String destinationPoiName;

  /// Floor model URL/src to open first (optional)
  final String floorSrc;

  /// Optional venue floor maps (label/src pairs). If null, we'll build from POI index + current floor.
  final List<Map<String, String>>? venueMaps;

  /// Backwards-compatible alias used in some older code.
  String get originFloorSrc => floorSrc;

  // Optional: if caller already knows the floor labels.
  final String? originFloorLabel;
  final String? destinationFloorLabel;

  /// Destination hit point in glTF coords from map (optional)
  final Map<String, double>? destinationHitGltf;

  const PathOverviewScreen({
    super.key,
    required this.shopName,
    required this.shopId,
    required this.startingMethod,
    this.destinationPoiMaterial = '',
    this.destinationPoiName = '',
    this.floorSrc = '',
    this.venueMaps,
    this.originFloorLabel,
    this.destinationFloorLabel,
    this.destinationHitGltf,
  });

  @override
  State<PathOverviewScreen> createState() => _PathOverviewScreenState();
}

class ConnectorLink {
  final String id;
  final String type; // e.g. "stairs", "elevator", "escalator"
  final Map<String, Map<String, double>>
  endpointsByFNumber; // f_number -> Blender position

  const ConnectorLink({
    required this.id,
    required this.type,
    required this.endpointsByFNumber,
  });
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
  String _selectedPreference = 'any';
  String _originFloorLabel = 'GF';
  String _desiredStartFloorLabel = '';
  String _estimatedTime = '2 min';
  String _estimatedDistance = '166 m';

  String _toFNumber(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    if (s.isEmpty) return '';

    // Normalize a bit.
    final up0 = s.toUpperCase();

    // Ground floor (English + common Arabic).
    if (up0 == 'G' ||
        up0 == 'GF' ||
        up0.contains('GROUND') ||
        up0.contains('G FLOOR') ||
        up0.contains('أرض') ||
        up0.contains('ارضي') ||
        up0.contains('أرضي')) {
      return '0';
    }

    // Remove separators and generic words.
    var up = up0.replaceAll(RegExp(r'[\s_\-]+'), '');
    up = up
        .replaceAll('FLOOR', '')
        .replaceAll('LEVEL', '')
        .replaceAll('LVL', '')
        .replaceAll('FL', '');

    // English ordinals.
    const ord = <String, String>{
      'FIRST': '1',
      '1ST': '1',
      'SECOND': '2',
      '2ND': '2',
      'THIRD': '3',
      '3RD': '3',
      'FOURTH': '4',
      '4TH': '4',
      'FIFTH': '5',
      '5TH': '5',
      'SIXTH': '6',
      '6TH': '6',
      'SEVENTH': '7',
      '7TH': '7',
      'EIGHTH': '8',
      '8TH': '8',
      'NINTH': '9',
      '9TH': '9',
      'TENTH': '10',
      '10TH': '10',
    };
    for (final e in ord.entries) {
      if (up.contains(e.key)) return e.value;
    }

    // Arabic ordinals (very lightweight).
    if (up.contains('الاول') || up.contains('الأول') || up.contains('اول'))
      return '1';
    if (up.contains('الثاني') || up.contains('ثاني')) return '2';
    if (up.contains('الثالث') || up.contains('ثالث')) return '3';
    if (up.contains('الرابع') || up.contains('رابع')) return '4';
    if (up.contains('الخامس') || up.contains('خامس')) return '5';

    // Patterns like F1, L2, etc.
    final m1 = RegExp(r'^(?:F|L)?(-?\d+)$').firstMatch(up);
    if (m1 != null) return m1.group(1)!;

    // Any digits inside: "FIRSTFLOOR1", "FLOOR-1", etc.
    final m2 = RegExp(r'(-?\d+)').firstMatch(up);
    if (m2 != null) return m2.group(1)!;

    return '';
  }

  int? _fNumberFromLabel(String? floorLabel) {
    final s = (floorLabel ?? '').trim().toUpperCase();
    if (s.isEmpty) return null;
    if (s == 'GF' || s == 'G' || s == '0' || s == 'F0') return 0;

    final m = RegExp(r'F?\s*(-?\d+)').firstMatch(s);
    if (m != null) return int.tryParse(m.group(1)!);

    return null;
  }

  /// Best-effort: turn any "floor token" into a label like GF / F1 / F2.
  /// Accepts: "GF", "G", "Ground", "F1", "1", "Floor 1", asset paths ".../F1_map.glb", "...navmesh_F1.json", etc.
  String _floorLabelFromToken(String? token) {
    final raw = (token ?? '').trim();
    if (raw.isEmpty) return '';

    final up = raw.toUpperCase();

    // Common ground-floor tokens.
    if (up == 'G' ||
        up == 'GF' ||
        up.contains('GROUND') ||
        up.contains('GROUNDFLOOR')) {
      return 'GF';
    }

    // Try extract GF / F<number> from asset/path-like tokens.
    final mPath = RegExp(
      r'(?:^|[^A-Z0-9])(GF|F\d+)(?:[^A-Z0-9]|$)',
    ).firstMatch(up);
    if (mPath != null) return mPath.group(1)!;

    // Try parse into an F-number ('' if unknown).
    final fnum = _toFNumber(up);
    if (fnum.isEmpty) return '';

    if (fnum == '0') return 'GF';
    if (fnum.startsWith('-')) {
      final n = fnum.substring(1);
      return n.isEmpty ? '' : 'B$n';
    }
    return 'F$fnum';
  }

  String _currentFNumber() {
    final url = _currentFloor.trim();
    if (url.isEmpty) return '';
    for (final m in _venueMaps) {
      if ((m['mapURL'] ?? '') == url) {
        return (m['F_number'] ?? '').toString();
      }
    }
    return '';
  }

  bool _isPreferenceAvailableForCurrentRoute(String prefValue) {
    final pref = prefValue.toLowerCase().trim();
    if (pref == 'any') return true;

    final startLabel = _desiredStartFloorLabel.isNotEmpty
        ? _desiredStartFloorLabel
        : _currentFloorLabel();
    final destLabel =
        (_destFloorLabelFixed ??
                _destFloorLabel ??
                widget.destinationFloorLabel ??
                '')
            .trim();
    if (destLabel.isEmpty) return true;

    final startF = _fNumberFromLabel(startLabel);
    final destF = _fNumberFromLabel(destLabel);
    if (startF == null || destF == null) return true;
    if (startF == destF) return true;

    bool linksFloors(ConnectorLink c) =>
        c.endpointsByFNumber.containsKey(startF.toString()) &&
        c.endpointsByFNumber.containsKey(destF.toString());

    bool matchesPref(ConnectorLink c) {
      final t = _normalizeConnectorType(c.type);
      final dirOk = _connectorDirectionAllowed(t, startF, destF);
      return dirOk && _connectorMatchesPreference(t, pref);
    }

    return _connectors.any((c) => linksFloors(c) && matchesPref(c));
  }

  String _navmeshForCurrentFloor() {
    final url = _currentFloor.trim();
    if (url.isEmpty) return '';

    for (final m in _venueMaps) {
      if ((m['mapURL'] ?? '') == url) {
        return (m['navmesh'] ?? '').toString();
      }
    }
    return '';
  }

  String _currentFloorLabel() {
    final url = _currentFloor.trim();
    if (url.isEmpty) return '';
    for (final m in _venueMaps) {
      if ((m['mapURL'] ?? '') == url) {
        return (m['floorNumber'] ?? '').toString();
      }
    }
    return '';
  }

  String _mapUrlForFloorLabel(String floorLabel) {
    final want = floorLabel.trim();
    if (want.isEmpty) return '';
    // Prefer exact label match (GF/F1).
    for (final m in _venueMaps) {
      if (((m['floorNumber'] ?? '').toString()).trim() == want) {
        return (m['mapURL'] ?? '').toString();
      }
    }
    // Fallback: match by F_number ("0","1",...) if caller passes "F1"/"1".
    final wantF = _toFNumber(want);
    if (wantF.isNotEmpty) {
      for (final m in _venueMaps) {
        if (((m['F_number'] ?? '').toString()).trim() == wantF) {
          return (m['mapURL'] ?? '').toString();
        }
      }
    }
    return '';
  }

  Future<void> _ensureFloorSelected(String floorLabel) async {
    final label = floorLabel.trim();
    if (label.isEmpty) return;

    // If maps aren't loaded yet, defer the switch.
    if (_venueMaps.isEmpty) {
      _pendingFloorLabelToOpen = label;
      return;
    }

    final desiredUrl = _mapUrlForFloorLabel(label);
    if (desiredUrl.isEmpty) return;

    if (_currentFloor.trim() != desiredUrl) {
      setState(() => _currentFloor = desiredUrl);

      // IMPORTANT: switching floors reloads the WebView, so the JS state (path dots)
      // is wiped. We must recompute + re-push after navmesh reload and once JS is ready.
      _pathPushed = false;
      _jsReady = false;
      _readyComputeRetry = 0;

      // Reload navmesh for the new floor first.
      await _ensureNavmeshLoadedForFNumber(_toFNumber(_currentFloorLabel()));

      // Compute now if we can; if JS isn't ready yet, the "path_viewer_ready" handler
      // will call this again.
      // Only recompute if we don't already have a route. When just switching the visible floor,
      // re-push the already-computed overlays for that floor to avoid "ghost" paths.
      if (_pathPointsByFloorGltf.isEmpty) {
        _maybeComputeAndPushPath();
      } else {
        _syncOverlaysForCurrentFloor();
      }
    }
  }

  bool _isSavedFloorActive() {
    // saved floor from Firestore (you store floor as 0/1/2...)
    final savedRaw = _desiredStartFloorLabel.isNotEmpty
        ? _desiredStartFloorLabel
        : _originFloorLabel;

    final saved = _toFNumber(savedRaw);
    final current = _currentFNumber();

    // If we can't determine one side yet, don't block.
    if (saved.isEmpty || current.isEmpty) return true;

    return saved == current;
  }

  WebViewController? _webCtrl;
  bool _jsReady = false;
  int _readyComputeRetry = 0;
  Map<String, double>? _pendingUserPinGltf;
  String? _pendingPoiToHighlight;

  // ---- POI index (for resolving destination coords) ----
  // Supports multiple POI json formats:
  // 1) Legacy: { "pois": { "POIMAT_X": {x,y,z,floor?}, ... } }
  // 2) Merged-by-floor: { "floors": { "GF": { "pois": {...} }, "F1": { "pois": {...} } } }
  // 3) All-in-one list: { "pois": { "POIMAT_X": [ {x,y,z,floor}, ... ] } }
  //
  // We normalize POI/material keys to be resilient to casing, spaces, and ".001" suffixes.
  Map<String, Map<String, Map<String, dynamic>>>?
  _poiByFloorNorm; // floorKey -> normKey -> poiMap
  bool _poiLoading = false;
  bool _poiIndexLoaded = false; // set true after POI index built
  bool _booting = false; // true while boot sequence is running

  // When Category page doesn't know the floor, we may discover the destination's floor from POI json.
  String? _pendingFloorLabelToOpen;

  // ---- Navmesh & path state ----
  NavMesh? _navmeshF1;
  Map<String, double>? _userPosBlender;
  Map<String, double>? _destPosBlender;
  Map<String, double>? _userSnappedBlender;
  Map<String, double>? _destSnappedBlender;

  // Path segments per floor (key = f_number string, e.g. "0" for GF, "1" for F1).
  final Map<String, List<Map<String, double>>> _pathPointsByFloorGltf = {};
  bool _pathPushed = false;

  // Once we compute a route, we should NOT recompute it when the user switches floors.
  bool _routeComputed = false;
  String? _originFloorLabelFixed; // e.g. "GF", "F1"
  String? _destFloorLabelFixed; // e.g. "GF", "F1"
  String? _originFNumberFixed; // e.g. "0", "1"
  String? _destFNumberFixed; // e.g. "0", "1"

  // Multi-floor routing state

  String? _destFloorLabel; // e.g. "GF", "F1"
  String? _destPoiMaterialResolved;
  String? _chosenConnectorId;
  Map<String, double>? _connectorStartBlender;
  Map<String, double>? _connectorDestBlender;

  // Connectors + navmesh caches
  List<ConnectorLink> _connectors = const [];
  bool _connectorsLoaded = false;
  final Map<String, NavMesh> _navmeshCache = {};
  final Map<String, String> _floorLabelByFNumber = {};
  // Cached lookups for connectors by floor (optional; helps debugging / future UI)
  final Map<String, List<ConnectorLink>> _connectorsByFloorLabel = {};
  final Map<String, List<Map<String, dynamic>>>
  _connectorEndpointsByFloorLabel = {};

  List<Map<String, double>> get _currentPathPointsGltf =>
      _pathPointsByFloorGltf[_currentFNumber()] ?? const [];

  // ---- Flutter -> JS helpers (Path Overview) ----
  String _fallbackNavmeshAssetForLabel(String label) {
    final up = label.toUpperCase().trim();
    if (up == "GF" || up == "G" || up == "GROUND") {
      return 'assets/nav_cor/navmesh_GF.json';
    }
    if (up == "F1" || up == "1" || up == "FIRST") {
      return 'assets/nav_cor/navmesh_F1.json';
    }
    // Generic naming convention: navmesh_<LABEL>.json
    final safe = up.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return 'assets/nav_cor/navmesh_${safe}.json';
  }

  Future<NavMesh?> _ensureNavmeshLoadedForFNumber(String fNumber) async {
    if (_navmeshCache.containsKey(fNumber)) return _navmeshCache[fNumber];

    String? assetPath;
    for (final m in _venueMaps) {
      if ((m["F_number"]?.toString() ?? "") == fNumber) {
        assetPath = m["navmesh"];
        break;
      }
    }

    assetPath ??= _fallbackNavmeshAssetForLabel(
      _floorLabelByFNumber[fNumber] ??
          (fNumber == "0"
              ? "GF"
              : (fNumber == "1" ? "F1" : _currentFloorLabel())),
    );

    try {
      final nm = await NavMesh.loadAsset(assetPath!);
      _navmeshCache[fNumber] = nm;
      debugPrint(
        "✅ Navmesh loaded for floor $fNumber: $assetPath (v=${nm.v.length} t=${nm.t.length})",
      );
      return nm;
    } catch (e) {
      debugPrint(
        "❌ Failed to load navmesh for floor $fNumber ($assetPath): $e",
      );
      return null;
    }
  }

  Future<void> _ensureConnectorsLoaded() async {
    if (_connectorsLoaded) return;
    try {
      String? raw;
      const candidates = [
        // Option A (per-floor local) connectors (recommended)
        'assets/connectors/connectors_merged_local.json',
        'assets/nav_cor/connectors_merged_local.json',
        // Legacy (world) connectors
        // Newer location (matches navmesh folder)
        'assets/nav_cor/connectors_merged_world.json',
        // Older locations
        'assets/connectors/connectors_merged_world.json',
        'assets/connectors/connectors_world.json',
        'assets/connectors/connectors.json',
      ];
      for (final p in candidates) {
        try {
          raw = await rootBundle.loadString(p);
          debugPrint('✅ Connectors loaded: $p');
          break;
        } catch (_) {
          // try next
        }
      }
      if (raw == null) {
        debugPrint(
          '❌ Connectors json not found in assets (checked: $candidates)',
        );
        _connectorsByFloorLabel.clear();
        _connectorEndpointsByFloorLabel.clear();
        _connectorsLoaded = true;
        return;
      }
      final decoded = jsonDecode(raw!);

      final List<dynamic> list = (decoded is List)
          ? decoded
          : (decoded is Map && decoded['connectors'] is List)
          ? (decoded['connectors'] as List)
          : const [];

      final out = <ConnectorLink>[];
      for (final item in list) {
        if (item is! Map) continue;

        final id = (item['id'] ?? item['name'] ?? item['connector_id'] ?? '')
            .toString();
        if (id.isEmpty) continue;

        final type = (item['type'] ?? item['kind'] ?? item['mode'] ?? '')
            .toString();

        final endpointsRaw =
            (item['endpoints'] ?? item['floors'] ?? item['nodes']);
        final endpoints = <String, Map<String, double>>{};

        if (endpointsRaw is List) {
          for (final ep in endpointsRaw) {
            if (ep is! Map) continue;

            // Floor
            String? f;
            if (ep['floorNumber'] != null) {
              f = ep['floorNumber'].toString();
            } else if (ep['f_number'] != null) {
              f = ep['f_number'].toString();
            } else if (ep['floor'] != null &&
                (ep['floor'] is num || ep['floor'] is String)) {
              // If numeric floor index, assume it is already f_number.
              f = ep['floor'].toString();
            } else if (ep['floorLabel'] != null ||
                ep['floor_label'] != null ||
                ep['label'] != null) {
              final lbl = (ep['floorLabel'] ?? ep['floor_label'] ?? ep['label'])
                  .toString();
              f = _toFNumber(lbl);
            }
            if (f == null || f.isEmpty) continue;

            // Position (Blender coords)
            Map<String, dynamic>? posMap;
            if (ep['position'] is Map)
              posMap = (ep['position'] as Map).cast<String, dynamic>();
            if (posMap == null && ep['pos'] is Map)
              posMap = (ep['pos'] as Map).cast<String, dynamic>();

            double? x = _asDouble(posMap?['x'] ?? ep['x']);
            double? y = _asDouble(posMap?['y'] ?? ep['y']);
            double? z = _asDouble(posMap?['z'] ?? ep['z']);

            // Some files use arrays [x,y,z]
            if ((x == null || y == null || z == null) && ep['xyz'] is List) {
              final l = ep['xyz'] as List;
              if (l.length >= 3) {
                x = _asDouble(l[0]);
                y = _asDouble(l[1]);
                z = _asDouble(l[2]);
              }
            }
            if (x == null || y == null || z == null) continue;

            endpoints[f] = {'x': x, 'y': y, 'z': z};
          }
        }

        if (endpoints.isNotEmpty) {
          out.add(
            ConnectorLink(id: id, type: type, endpointsByFNumber: endpoints),
          );
        }
      }

      _connectors = out;
      _connectorsLoaded = true;
      debugPrint("✅ Connectors parsed: ${_connectors.length}");
    } catch (e) {
      _connectors = const [];
      _connectorsLoaded = true; // avoid retry loops
      debugPrint("❌ Failed to load connectors: $e");
    }
  }

  Future<void> _syncOverlaysForCurrentFloor() async {
    if (!_jsReady) return;

    // Push path for the visible floor
    await _pushPathToJs();

    // Show the user pin only on the start floor
    final startLabel = _desiredStartFloorLabel.isNotEmpty
        ? _desiredStartFloorLabel
        : _currentFloorLabel();
    final startF = _toFNumber(startLabel);

    final currF = _currentFNumber();

    if (_pendingUserPinGltf != null && currF == startF) {
      await _pushUserPinToJsPath(_pendingUserPinGltf!);
    } else {
      await _clearUserPinFromJs();
    }

    // Highlight destination only on destination floor (if we know it)
    final destLabel =
        _destFloorLabelFixed ??
        _destFloorLabel ??
        widget.destinationFloorLabel ??
        _floorLabelFromToken(widget.floorSrc) ??
        '';
    if (destLabel != null && destLabel.isNotEmpty) {
      final destF = _toFNumber(destLabel);
      if (currF == destF && _pendingPoiToHighlight != null) {
        await _pushDestinationHighlightToJsPath();
      }
    }
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // --- Connector type normalization ---
  // connectors_merged_world.json uses short codes like: stair, elev, esc_up, esc_dn.
  // Normalize them so routing + UI preferences work reliably.
  String _normalizeConnectorType(String raw) {
    final t = raw.toLowerCase().trim();
    if (t == 'stair' || t == 'stairs') return 'stairs';
    if (t == 'elev' || t == 'elevator' || t == 'lift') return 'elevator';
    if (t == 'esc_up' || t == 'escalator_up' || t == 'escalatorup')
      return 'escalator_up';
    if (t == 'esc_dn' ||
        t == 'esc_down' ||
        t == 'escalator_down' ||
        t == 'escalatordown')
      return 'escalator_down';
    if (t.contains('esc') || t.contains('escalator')) return 'escalator';
    return t;
  }

  bool _connectorDirectionAllowed(String normType, int fromFloor, int toFloor) {
    final t = normType.toLowerCase();
    if (t == 'escalator_up') return fromFloor < toFloor;
    if (t == 'escalator_down') return fromFloor > toFloor;
    return true; // stairs/elevator/escalator(any) allowed both ways
  }

  bool _connectorMatchesPreference(String normType, String pref) {
    final p = pref.toLowerCase().trim();
    final t = normType.toLowerCase().trim();
    if (p.isEmpty || p == 'any') return true;
    if (p == 'escalator') return t.startsWith('escalator');
    return t == p;
  }

  Future<void> _clearUserPinFromJs() async {
    final c = _webCtrl;
    if (c == null || !_jsReady) return;
    try {
      await c.runJavaScript(
        'window.clearUserPinFromFlutter && window.clearUserPinFromFlutter();',
      );
    } catch (_) {}
  }

  Future<void> _pushUserPinToJsPath(Map<String, double> gltf) async {
    final c = _webCtrl;
    if (c == null || !_jsReady) return;

    // Only show the user pin on its own floor. Otherwise it appears in a wrong spot when viewing other floors.
    final originF = _toFNumber(_originFloorLabel);
    if (originF.isNotEmpty && originF != _currentFNumber()) {
      await _clearUserPinFromJs();
      return;
    }

    final x = gltf['x'];
    final y = gltf['y'];
    final z = gltf['z'];
    if (x == null || y == null || z == null) return;

    try {
      await c.runJavaScript('window.setUserPinFromFlutter($x,$y,$z);');
    } catch (e) {
      debugPrint('pushUserPinToJsPath failed: $e');
    }
  }

  Future<void> _pushDestinationHighlightToJsPath() async {
    final c = _webCtrl;
    final name = _pendingPoiToHighlight;
    if (c == null || !_jsReady || name == null || name.trim().isEmpty) return;

    // Only highlight on the destination floor. Other floors will show their own model
    // and we don't want to highlight an unrelated material there.
    final destF = _toFNumber(_destFloorLabel);
    if (destF.isNotEmpty && destF != _currentFNumber()) return;

    final safe = name.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    await c.runJavaScript('window.highlightPoiFromFlutter("$safe");');
  }

  // ---- POI JSON loading / destination resolving ----
  String _normPoiKey(String s) {
    var n = (s).trim().toLowerCase();
    // remove blender numeric suffixes like .001
    n = n.replaceAll(RegExp(r"\.[0-9]+\$"), "");
    // remove all separators/symbols to make matching resilient
    n = n.replaceAll(RegExp(r"[^a-z0-9]+"), "");
    // normalize "poimat" prefix (POIMAT_* in the glb)
    if (n.startsWith("poimat")) {
      n = n.substring(6);
    }
    if (n.startsWith("_")) n = n.substring(1);
    return "poimat_" + n;
  }

  bool _isBlank(String? s) => s == null || s.trim().isEmpty;

  /// Infer destination floor label using the loaded POI index (solitaire_pois_merged.json).
  /// Returns a human-readable label like "GF" or "F1" when possible.
  String? _inferFloorLabelFromPoiIndex(String poiMaterial) {
    final byFloor = _poiByFloorNorm;
    if (byFloor == null || byFloor.isEmpty) return null;

    final wantNorm = _normPoiKey(poiMaterial);

    for (final floorEntry in byFloor.entries) {
      final p = floorEntry.value[wantNorm];
      if (p == null) continue;

      final fl = (p['floorLabel'] ?? p['floor'] ?? '').toString();
      if (fl.trim().isNotEmpty) {
        _destPoiMaterialResolved = (p['materialName'] ?? poiMaterial)
            .toString();
        return fl.trim();
      }

      // fallback to the normalized floor key if label missing
      return floorEntry.key;
    }

    return null;
  }

  /// Normalize a floor label into a stable key for matching.
  ///
  /// We intentionally map different conventions to the same key:
  /// - POIs might say: "GF", "G", "F1"...
  /// - Connectors might say: "0", "1", "2"...
  /// - Firestore might say: "Floor 1", "1"...
  ///
  /// Canonical keys:
  /// - Ground floor: "FG"
  /// - Positive floors: "F1", "F2", ...
  /// - Basement floors: "B1", "B2", ...
  String _normFloorKey(String s) {
    final raw = (s).toString().trim();
    if (raw.isEmpty) return "";
    final up = raw.toUpperCase();

    // Explicit ground floor labels.
    if (up == 'G' || up == 'GF' || up == 'GROUND' || up.contains('GROUND'))
      return 'GF';

    // Numeric-only labels often appear in connectors ("0" == ground).
    final numOnly = RegExp(r'^-?\d+$').firstMatch(up);
    if (numOnly != null) {
      final n = int.tryParse(up) ?? 0;
      if (n == 0) return 'GF';
      if (n > 0) return 'F$n';
      return 'B${n.abs()}';
    }

    // "F1", "Floor 2", "L3" ... -> extract first number.
    final m = RegExp(r'(\d+)').firstMatch(up);
    if (m != null) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n == 0) return 'GF';
      return 'F$n';
    }

    // "B1" / "Basement" patterns.
    final bm = RegExp(r'B(\d+)').firstMatch(up);
    if (bm != null) return 'B${bm.group(1)}';

    // Fallback: remove whitespace/symbols.
    return up.replaceAll(RegExp(r'[^A-Z0-9]+'), '');
  }

  Future<void> _loadPoiIndexIfNeeded() async {
    if (_poiIndexLoaded) return;
    if (_poiLoading) return;
    _poiLoading = true;

    try {
      // Collect and merge POIs from all available POI jsons.
      //
      // Preferred structure:
      //   {"floors": {"GF": {"POIMAT_X": {"x":..,"y":..,"z":..}}, "F1": {...}}}
      //
      // Legacy structure (often per-floor file):
      //   {"pois": {"POIMAT_X": {"x":..,"y":..,"z":..}, ...}}
      //
      // Some older exports may be:
      //   {"pois": [{"name":"POIMAT_X","x":..,"y":..,"z":..}, ...]}
      //
      // We load *all* matching files and merge. If a POI appears multiple times,
      // the first occurrence wins (to keep behavior deterministic).
      final byFloor = <String, Map<String, Map<String, dynamic>>>{};

      void addPoiAliases(
        String floor,
        Iterable<String> names,
        Map<String, dynamic> v,
      ) {
        if (floor.isEmpty || names.isEmpty) return;

        // Pick a single coordinate set (prefer explicit x/y/z)
        final x = v['x'] ?? v['posX'] ?? v['px'];
        final y = v['y'] ?? v['posY'] ?? v['py'];
        final z = v['z'] ?? v['posZ'] ?? v['pz'];
        if (x == null || y == null || z == null) return;

        final floorKeyRaw = floor.trim();
        final floorKey = _normFloorKey(floorKeyRaw);
        final bucket = byFloor.putIfAbsent(
          floorKey,
          () => <String, Map<String, dynamic>>{},
        );

        for (final n in names) {
          final nn = _normPoiKey(n);
          if (nn.isEmpty) continue;
          bucket[nn] = {
            'name': v['name'] ?? n,
            'floor': floorKey,
            'x': (x as num).toDouble(),
            'y': (y as num).toDouble(),
            'z': (z as num).toDouble(),
            // keep originals for debugging / extra matching
            'materialName': v['materialName'],
            'id': v['id'],
          };
        }
      }

      // Backward-compatible single-name helper
      void addPoi(String floor, String name, Map<String, dynamic> v) =>
          addPoiAliases(floor, [name], v);

      String floorHintFromPath(String path) {
        final u = path.toUpperCase();
        // Common patterns: ..._GF.json, ..._F1.json, ..._B1.json
        final m = RegExp(r'_(GF|F\d+|B\d+)\.JSON').firstMatch(u);
        if (m != null) return m.group(1)!;
        return 'GF';
      }

      // Build candidate list from AssetManifest + known fallbacks.
      final candidates = <String>[
        // ✅ Your actual asset path (pubspec): assets/poi/solitaire_pois_merged.json
        'assets/poi/solitaire_pois_merged.json',
        // Common fallbacks (keep them in case you move the file later)
        'assets/poi/solitaire_pois.json',
        'assets/pois/solitaire_pois_merged.json',
        'assets/pois/solitaire_pois.json',
        'assets/venues/solitaire_pois_merged.json',
        'assets/venues/solitaire_pois.json',
        // Older legacy path that some earlier versions used:
        'assets/nav_cor/solitaire_pois_merged.json',
      ];

      // 🔎 Debug: confirm what Flutter thinks is inside the asset bundle
      try {
        final manifestStr = await rootBundle.loadString('AssetManifest.json');
        final manifest = jsonDecode(manifestStr) as Map<String, dynamic>;
        final keys = manifest.keys.toList()..sort();
        debugPrint('🧾 AssetManifest.json loaded (keys=${keys.length})');
        for (final p in candidates) {
          debugPrint('🧾 manifest has "$p" = ${manifest.containsKey(p)}');
        }
      } catch (e) {
        debugPrint('⚠️ Could not read AssetManifest.json: $e');
      }

      bool anyLoaded = false;

      for (final p in candidates) {
        String jsonStr;
        try {
          jsonStr = await rootBundle.loadString(p);
        } catch (e) {
          debugPrint('❌ Failed to load POI asset: $p -> $e');
          continue;
        }

        anyLoaded = true;
        debugPrint('✅ POI json loaded: $p');

        final decodedAny = jsonDecode(jsonStr);
        if (decodedAny is! Map) continue;

        // Case A: merged floors file
        final floors = decodedAny['floors'];
        if (floors is Map) {
          floors.forEach((floorKey, floorVal) {
            if (floorVal is Map) {
              floorVal.forEach((poiName, v) {
                if (v is Map) {
                  final vm = Map<String, dynamic>.from(v);
                  final aliases = <String>{poiName.toString()};
                  final mat = vm['materialName']?.toString();
                  final disp = vm['name']?.toString();
                  final id = vm['id']?.toString();
                  if (mat != null && mat.isNotEmpty) aliases.add(mat);
                  if (disp != null && disp.isNotEmpty) aliases.add(disp);
                  if (id != null && id.isNotEmpty) aliases.add(id);
                  addPoiAliases(floorKey.toString(), aliases, vm);
                }
              });
            }
          });
          continue;
        }

        // Case B/C: legacy per-floor (or merged-without-floors) format
        final pois = decodedAny['pois'];
        if (pois is Map) {
          pois.forEach((poiName, v) {
            if (v is Map) {
              final vm = Map<String, dynamic>.from(v);
              String floor = '';
              try {
                final fl = vm['floor']?.toString();
                if (fl != null && fl.trim().isNotEmpty)
                  floor = _floorLabelFromToken(fl);
              } catch (_) {}
              if (floor.isEmpty) floor = floorHintFromPath(p);
              if (floor.isEmpty) floor = 'GF';
              final aliases = <String>{poiName.toString()};
              final mat = vm['materialName']?.toString();
              final disp = vm['name']?.toString();
              final id = vm['id']?.toString();
              if (mat != null && mat.isNotEmpty) aliases.add(mat);
              if (disp != null && disp.isNotEmpty) aliases.add(disp);
              if (id != null && id.isNotEmpty) aliases.add(id);
              addPoiAliases(floor, aliases, vm);
            }
          });
        } else if (pois is List) {
          for (final item in pois) {
            if (item is Map) {
              String floor = '';
              try {
                final fl = item['floor']?.toString();
                if (fl != null && fl.trim().isNotEmpty)
                  floor = _floorLabelFromToken(fl);
              } catch (_) {}
              if (floor.isEmpty) floor = floorHintFromPath(p);
              if (floor.isEmpty) floor = 'GF';
              final name = (item['name'] ?? item['material'] ?? item['id'])
                  ?.toString();
              if (name == null || name.isEmpty) continue;
              addPoi(floor, name, Map<String, dynamic>.from(item));
            }
          }
        }
      }

      // Fallback: load per-floor POI JSON referenced from Firestore venue maps (poiJsonPath).
      if ((!anyLoaded || byFloor.isEmpty) && _venueMaps.isNotEmpty) {
        for (final vm in _venueMaps) {
          final p = (vm['poiJsonPath'] ?? '').toString().trim();
          if (p.isEmpty) continue;
          try {
            final s = await rootBundle.loadString(p);
            final decoded = jsonDecode(s);
            anyLoaded = true;
            final floorHint = _floorLabelFromToken(
              (vm['floorNumber'] ?? vm['F_number'] ?? vm['title'] ?? '')
                  .toString(),
            );
            // Accept either {pois:[...]} or [...].
            List<dynamic> pois = [];
            if (decoded is Map) {
              final v =
                  decoded['pois'] ??
                  decoded['POIs'] ??
                  decoded['points'] ??
                  decoded['data'];
              if (v is List) pois = v;
            } else if (decoded is List) {
              pois = decoded;
            }
            for (final item in pois) {
              if (item is Map) {
                final name = (item['name'] ?? item['material'] ?? item['id'])
                    ?.toString();
                if (name == null || name.isEmpty) continue;
                String floor = '';
                try {
                  final fl = item['floor']?.toString();
                  if (fl != null && fl.trim().isNotEmpty)
                    floor = _floorLabelFromToken(fl);
                } catch (_) {}
                if (floor.isEmpty) floor = floorHint;
                if (floor.isEmpty) floor = 'GF';
                addPoi(floor, name, Map<String, dynamic>.from(item));
              }
            }
          } catch (e) {
            debugPrint('⚠️ Could not load POIs from $p: $e');
          }
        }
      }

      if (!anyLoaded) {
        debugPrint('❌ POI json not found in assets (see tried paths above)');
        return;
      }

      if (byFloor.isEmpty) {
        debugPrint(
          '❌ POI index is empty. Make sure you added POI JSON to pubspec.yaml assets (e.g. assets/nav_cor/solitaire_pois_merged.json).',
        );
      } else {
        _poiByFloorNorm = byFloor;
        _poiIndexLoaded = true;
        debugPrint('✅ POI index built: floors=${byFloor.keys.toList()}');
      }
    } finally {
      _poiLoading = false;
    }
  }

  Future<void> _resolveDestinationFromPoiJsonIfNeeded() async {
    // If we already have a destination position, we still may need its floor label for connectors.
    if (_destPosBlender != null && !_isBlank(_destFloorLabel)) return;

    final name =
        (_pendingPoiToHighlight ??
                (widget.destinationPoiMaterial.trim().isNotEmpty
                    ? widget.destinationPoiMaterial
                    : (widget.destinationPoiName.trim().isNotEmpty
                          ? widget.destinationPoiName
                          : widget.shopName)))
            .trim();
    if (name.isEmpty) return;

    await _loadPoiIndexIfNeeded();
    if (!_poiIndexLoaded) {
      debugPrint(
        '❌ Cannot resolve destination floor because POI index failed to load.',
      );
      return;
    }
    final byFloor = _poiByFloorNorm;
    if (byFloor == null || byFloor.isEmpty) return;

    final norm = _normPoiKey(name);

    // Find which floors contain this POI/material.
    final hits = <String>[];
    for (final fk in byFloor.keys) {
      final m = byFloor[fk];
      if (m != null && m.containsKey(norm)) {
        hits.add(fk);
      }
    }

    if (hits.isEmpty) {
      debugPrint(
        '⚠️ Destination not found in POI json for "$name" (norm="$norm")',
      );
      return;
    }

    String floorLabelFromToken(String token) {
      final t = token.trim();
      if (t.isEmpty) return '';

      // If it's a mapURL, resolve to a floor label via venue maps.
      if (_looksLikeMapUrl(t)) {
        for (final m in _venueMaps) {
          if (((m['mapURL'] ?? '').toString()).trim() == t) {
            return (m['floorNumber'] ?? '').toString();
          }
        }
        return '';
      }

      final up = t.toUpperCase();
      if (up == 'GF') return 'GF';
      final mm = RegExp(r'^F\s*(\d+)$', caseSensitive: false).firstMatch(t);
      if (mm != null) return 'F${mm.group(1)}';

      // If it's numeric (0/1/2...) try to map to a floor label.
      final fnum = _toFNumber(t);
      if (fnum.isNotEmpty) {
        for (final m in _venueMaps) {
          if (((m['F_number'] ?? '').toString()).trim() == fnum) {
            return (m['floorNumber'] ?? '').toString();
          }
        }
      }
      return t;
    }

    // Choose which floor to use if the POI exists on multiple floors.
    // Priority:
    // 1) Explicit destinationFloorLabel passed from Flutter (best)
    // 2) floorSrc token (if caller opened this screen while viewing a floor)
    // 3) If there's only one match, use it
    // 4) Fallback: first match
    String chosenFloor = hits.first;
    if (hits.length > 1) {
      String? tokenFloor;
      if (widget.destinationFloorLabel != null &&
          widget.destinationFloorLabel!.trim().isNotEmpty) {
        tokenFloor = floorLabelFromToken(widget.destinationFloorLabel!);
      } // NOTE: do not bias by current floorSrc; it can hide cross-floor destinations
      // else if (widget.floorSrc.trim().isNotEmpty) {
      //   tokenFloor = floorLabelFromToken(widget.floorSrc);
      // }

      if (tokenFloor != null &&
          tokenFloor.isNotEmpty &&
          hits.contains(tokenFloor)) {
        chosenFloor = tokenFloor;
      }
    }

    final poi = byFloor[chosenFloor]?[norm];
    if (poi == null) {
      debugPrint(
        '⚠️ POI found on floors=$hits but missing entry for chosen="$chosenFloor"',
      );
      return;
    }

    final x = (poi['x'] as num?)?.toDouble();
    final y = (poi['y'] as num?)?.toDouble();
    final z = (poi['z'] as num?)?.toDouble();
    if (x == null || y == null || z == null) {
      debugPrint(
        '⚠️ POI json missing x/y/z for "$name" on floor "$chosenFloor"',
      );
      return;
    }

    setState(() {
      // Only set destination position from POI if we don't already have one.
      _destPosBlender ??= {'x': x, 'y': y, 'z': z};
      // Find a venue map label that matches this floor key (e.g. "F1" -> "1").
      String bestLabel = chosenFloor;
      if (_venueMaps.isNotEmpty) {
        for (final vm in _venueMaps) {
          final t = (vm['floorNumber'] ?? vm['title'] ?? vm['label'] ?? '')
              .toString();
          if (t.isEmpty) continue;
          if (_normFloorKey(t) == _normFloorKey(chosenFloor)) {
            bestLabel = t;
            break;
          }
        }
      }
      _pendingFloorLabelToOpen = bestLabel;
      _destFloorLabel = bestLabel; // enables connectors/multi-floor routing
    });

    debugPrint(
      '✅ Destination resolved from POI json: $name -> floor=$chosenFloor B=$_destPosBlender',
    );

    // During boot, we only store the pending floor label; floor selection will happen after maps load.
    if (!_booting && _venueMaps.isNotEmpty) {
      // If Category didn't know the floor, auto-switch to the POI floor.
      // (If you prefer to stay on the user's floor, remove this line.)
      _ensureFloorSelected(_pendingFloorLabelToOpen ?? chosenFloor);
      _maybeComputeAndPushPath();
    }

    // If destination floor is still unknown, try inferring from destinationPoiMaterial
    // using the POI index loaded across floors.
    if (_isBlank(_destFloorLabel)) {
      final mat = widget.destinationPoiMaterial;
      if (!_isBlank(mat)) {
        final fk = _inferFloorLabelFromPoiIndex(mat!.trim());
        if (!_isBlank(fk)) {
          setState(() {
            _destFloorLabel = fk!.trim();
            _destFloorLabelFixed = fk.trim();
          });
          debugPrint(
            "✅ Destination floor inferred from POI index: $mat -> $fk" +
                (_destPoiMaterialResolved != null
                    ? " (resolvedMat=$_destPoiMaterialResolved)"
                    : ""),
          );
        }
      }
    }
  } // ---- Coordinate conversions ----

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

  String _fallbackNavmeshForFloorLabel(String floorLabel) {
    final fl = floorLabel.trim().toUpperCase();
    if (fl == "F1" || fl == "1") return "assets/nav_cor/navmesh_F1.json";
    if (fl == "GF" || fl == "G" || fl == "0")
      return "assets/nav_cor/navmesh_GF.json";
    // Try infer from current floor URL if it contains tokens
    final url = _currentFloor.toLowerCase();
    if (url.contains("f1") || url.contains("floor1") || url.contains("_1"))
      return "assets/nav_cor/navmesh_F1.json";
    return "assets/nav_cor/navmesh_GF.json";
  }

  Future<void> _loadNavmeshF1() async {
    final nm = await _ensureNavmeshLoadedForFNumber(
      _toFNumber(_currentFloorLabel()),
    );
    if (!mounted) return;
    setState(() {
      _navmeshF1 = nm;
    });
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

    final pts = _currentPathPointsGltf;
    final jsArg = jsonEncode(pts);

    try {
      await c.runJavaScript('window.setPathFromFlutter($jsArg);');
      _pathPushed = true;
    } catch (e) {
      debugPrint('pushPathToJs failed: $e');
    }
  }

  Future<void> _maybeComputeAndPushPath() async {
    if (_booting) return;
    // Ensure destination is resolved from POI json if the caller only supplied
    // a POI material name.
    await _resolveDestinationFromPoiJsonIfNeeded();
    if (_routeComputed) {
      // Route already computed; just (re)sync overlays for the currently viewed floor.
      await _syncOverlaysForCurrentFloor();
      return;
    }

    if (_userPosBlender == null || _destPosBlender == null) return;

    // Determine floors
    final startLabel =
        _originFloorLabelFixed ??
        (_desiredStartFloorLabel.isNotEmpty ? _desiredStartFloorLabel : '');
    if (startLabel.trim().isEmpty) {
      debugPrint(
        '⚠️ Start floor unknown (no saved Firestore location yet) — abort routing',
      );
      return;
    }
    // Destination floor label: prefer fixed -> POI json -> caller -> infer from floorSrc token.
    final destCandidateRaw =
        (_destFloorLabelFixed != null && _destFloorLabelFixed!.isNotEmpty)
        ? _destFloorLabelFixed!
        : ((_destFloorLabel != null && _destFloorLabel!.isNotEmpty)
              ? _destFloorLabel!
              : ((widget.destinationFloorLabel != null &&
                        widget.destinationFloorLabel!.isNotEmpty)
                    ? widget.destinationFloorLabel!
                    : ''));
    // Normalize if the caller passed a map token/path.
    final destCandidate =
        _floorLabelFromToken(destCandidateRaw) ?? destCandidateRaw;

    // If still unknown, default to the ORIGIN floor (not the currently viewed floor),
    // so switching floors won't accidentally recompute a route with wrong navmesh.
    final destLabel = destCandidate.isNotEmpty ? destCandidate : startLabel;
    if (destCandidate.isEmpty) {
      debugPrint(
        '⚠️ Destination floor label unknown; defaulting to origin floor ($destLabel). Connectors will NOT be used.',
      );
    }
    final startF = _toFNumber(startLabel);
    final destF = _toFNumber(destLabel);

    // Lock floors for this navigation session (prevents weird paths when changing floors).
    _originFloorLabelFixed ??= startLabel;
    _destFloorLabelFixed ??= destLabel;
    _originFNumberFixed ??= startF;
    _destFNumberFixed ??= destF;

    final startNm = await _ensureNavmeshLoadedForFNumber(startF);
    final destNm = await _ensureNavmeshLoadedForFNumber(destF);
    if (startNm == null || destNm == null) return;

    // Always keep _navmeshF1 aligned to the currently visible floor (for legacy helpers).
    _navmeshF1 = _navmeshCache[_currentFloor];

    await _ensureConnectorsLoaded();

    // Reset previous path
    _pathPointsByFloorGltf.clear();
    _chosenConnectorId = null;
    _connectorStartBlender = null;
    _connectorDestBlender = null;

    // Helper: compute path on a specific floor
    List<List<double>> computePathOn(
      NavMesh nm,
      Map<String, double> aBl,
      Map<String, double> bBl,
    ) {
      final a = nm.snapPointXY([aBl['x']!, aBl['y']!, aBl['z']!]);
      final b = nm.snapPointXY([bBl['x']!, bBl['y']!, bBl['z']!]);
      var raw = nm.findPathFunnelBlenderXY(start: a, goal: b);
      var sm = _smoothAndResamplePath(raw, nm);

      // Fallback: some navmesh implementations may return an empty/single-point
      // path when the start and goal are very close or in the same polygon.
      // In that case, draw a simple straight-line path.
      if (sm.length < 2) {
        raw = [a, b];
        sm = _smoothAndResamplePath(raw, nm);
        if (sm.length < 2) sm = raw;
      }
      return sm;
    }

    double pathLen(List<List<double>> pts) {
      double sum = 0;
      for (int i = 1; i < pts.length; i++) {
        sum += _distXY(pts[i - 1], pts[i]);
      }
      return sum;
    }

    if (startF == destF) {
      final pts = computePathOn(startNm, _userPosBlender!, _destPosBlender!);
      final gltf = pts
          .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
          .toList();
      _pathPointsByFloorGltf[startF] = gltf;
    } else {
      // Multi-floor: go from start -> connector(start floor), then connector(dest floor) -> destination.
      final pref = _selectedPreference
          .toLowerCase(); // any / stairs / elevator / escalator
      bool linksFloors(ConnectorLink c) =>
          c.endpointsByFNumber.containsKey(startF) &&
          c.endpointsByFNumber.containsKey(destF);

      bool directionOk(ConnectorLink c) {
        final t = _normalizeConnectorType(c.type);
        return _connectorDirectionAllowed(
          t,
          int.tryParse(startF) ?? 1,
          int.tryParse(destF) ?? 1,
        );
      }

      bool matchesPref(ConnectorLink c) {
        final t = _normalizeConnectorType(c.type);
        return directionOk(c) && _connectorMatchesPreference(t, pref);
      }

      // 1) Try connectors that link floors AND match preference
      final candidates = _connectors
          .where((c) => linksFloors(c) && matchesPref(c))
          .toList();

      // 2) Fallback: ignore preference (still respect escalator direction)
      final pool = candidates.isNotEmpty
          ? candidates
          : _connectors.where((c) => linksFloors(c) && directionOk(c)).toList();

      debugPrint(
        '🧭 pref=' +
            pref +
            ' start=' +
            startLabel +
            '(' +
            startF +
            ') dest=' +
            destLabel +
            '(' +
            destF +
            ') ' +
            'matched=' +
            candidates.length.toString() +
            ' pool=' +
            pool.length.toString(),
      );
      if (pool.isNotEmpty) {
        final preview = pool
            .take(8)
            .map((c) => '${_normalizeConnectorType(c.type)}:${c.id}')
            .join(', ');
        debugPrint(
          '🧭 connector pool: ' + preview + (pool.length > 8 ? ' ...' : ''),
        );
      }

      if (pool.isEmpty) {
        debugPrint("⚠️ No connectors found linking $startLabel -> $destLabel");
        return;
      }

      double bestScore = double.infinity;
      ConnectorLink? best;
      List<List<double>> bestA = const [];
      List<List<double>> bestB = const [];

      for (final c in pool) {
        final aPos = c.endpointsByFNumber[startF]!;
        final bPos = c.endpointsByFNumber[destF]!;
        final aPts = computePathOn(startNm, _userPosBlender!, aPos);
        final bPts = computePathOn(destNm, bPos, _destPosBlender!);

        // Skip broken paths
        if (aPts.length < 2 || bPts.length < 2) continue;

        final score = pathLen(aPts) + pathLen(bPts);
        if (score < bestScore) {
          bestScore = score;
          best = c;
          bestA = aPts;
          bestB = bPts;
        }
      }

      if (best == null) {
        debugPrint("⚠️ Could not compute a valid connector path.");
        return;
      }

      _chosenConnectorId = '${best.type}:${best.id}';
      debugPrint(
        '✅ chosen connector pref=' +
            pref +
            ' -> ' +
            _chosenConnectorId! +
            ' score=' +
            bestScore.toStringAsFixed(2),
      );
      _connectorStartBlender = best.endpointsByFNumber[startF];
      _connectorDestBlender = best.endpointsByFNumber[destF];

      final gltfA = bestA
          .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
          .toList();
      final gltfB = bestB
          .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
          .toList();

      _pathPointsByFloorGltf[startF] = gltfA;
      _pathPointsByFloorGltf[destF] = gltfB;
    }

    _routeComputed = true;

    if (mounted) setState(() {});
    _syncOverlaysForCurrentFloor();
  }

  void _handlePoiMessage(String raw) {
    // Path viewer JS posts a small set of messages. We keep this tolerant and
    // non-breaking.
    try {
      final obj = jsonDecode(raw);
      if (obj is Map && obj['type'] == 'path_viewer_ready') {
        _jsReady = true;
        debugPrint("🟦 POI_CHANNEL: path_viewer_ready");

        // When the viewer is recreated (e.g., floor switch), redraw overlays for this floor.
        _syncOverlaysForCurrentFloor();
        return;
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

window.clearPathFromFlutter = function() {
  const viewer = getViewer();
  if (!viewer) return;
  try {
    clearPathHotspots(viewer);
    window.__pendingPathPoints = null;
    viewer.requestUpdate();
    postToTest("🧹 clearPathFromFlutter");
  } catch (e) {}
};

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
  // remove all separators/symbols to make matching resilient
  n = n.replace(/[^a-z0-9]+/g, "");
  if (n.startsWith("poimat")) n = n.substring(6);
  return "poimat_" + n;
}

// Backwards-compatible alias (older snippets referenced _normPoiKey)
function _normPoiKey(s) { return _normPoiName(s); }


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
        const nn = _normPoiKey(name);
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

  const wantNorm = _normPoiKey(name);

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


// Clear pin (can be called when switching to a different floor)
window.clearUserPinFromFlutter = function() {
  const viewer = getViewer();
  if (!viewer) return;

  try {
    const pin = viewer.querySelector('[slot="hotspot-userpin"]');
    if (pin) pin.remove();
    window.__pendingUserPin = null;
    viewer.requestUpdate();
    postToTest("🧹 clearUserPinFromFlutter");
  } catch (e) {}
};

// Set pin from Flutter (supports pending until model is ready)
window.setUserPinFromFlutter = function(x, y, z) {
  const viewer = getViewer();
  const p = { x: Number(x), y: Number(y), z: Number(z) };

  if (!viewer || !viewer.model) {
    window.__pendingUserPin = p;
    postToTest("⏳ setUserPinFromFlutter pending (viewer/model not ready)");
    return false;
  }

  setUserPin(viewer, p);
  window.__pendingUserPin = null;
  postToTest("✅ setUserPinFromFlutter applied");
  return true;
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

    // Apply any floors passed in by caller.
    if (widget.originFloorLabel != null &&
        widget.originFloorLabel!.isNotEmpty) {
      _originFloorLabel = widget.originFloorLabel!;
    }
    if (widget.destinationFloorLabel != null &&
        widget.destinationFloorLabel!.isNotEmpty) {
      _destFloorLabel = widget.destinationFloorLabel!;
    }

    _requestedFloorToken = widget.floorSrc.trim();
    _requestedFloorIsUrl = _looksLikeMapUrl(_requestedFloorToken);

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

    // Boot in a strict order to ensure destination/user/floor data is ready
    // before we attempt any path computation or connector routing.
    // ignore: unawaited_futures
    _boot();
  }

  Future<void> _boot() async {
    _booting = true;
    try {
      // 1) Load maps first so POI fallbacks (poiJsonPath) can work.
      await _loadVenueMaps();

      // 2) Resolve destination from POI index (may set _pendingFloorLabelToOpen).
      await _resolveDestinationFromPoiJsonIfNeeded();

      // 3) Load user pin + preferred start floor (may set _desiredStartFloorLabel).
      await _loadUserBlenderPosition();

      // 4) Ensure we are on the best initial floor:
      //    prefer user start floor, otherwise destination floor.
      final target = (_desiredStartFloorLabel.isNotEmpty)
          ? _desiredStartFloorLabel
          : (_pendingFloorLabelToOpen ?? '');
      if (target.isNotEmpty) {
        await _ensureFloorSelected(target);
      }
    } finally {
      _booting = false;
    }

    // 4) Compute and push the path once everything is ready.
    await _maybeComputeAndPushPath();
    await _syncOverlaysForCurrentFloor();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera page not connected yet')),
      );
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

    // Prefer widget-provided venue maps (offline/local).
    if (widget.venueMaps != null && widget.venueMaps!.isNotEmpty) {
      // Keep the same static type as the widget field.
      // Using Map<String, String>.from avoids widening to Map<String, dynamic>
      // which later fails assignment.
      final List<Map<String, String>> convertedMaps = widget.venueMaps!
          .map((m) => Map<String, String>.from(m))
          .toList();
      if (mounted) {
        setState(() {
          _venueMaps = convertedMaps;
          // Build floor label lookup (F_number -> floor label like GF/F1)
          _floorLabelByFNumber.clear();
          for (final m in _venueMaps) {
            final f = (m["F_number"]?.toString() ?? "");
            final lbl = (m["floorNumber"]?.toString() ?? "");
            if (f.isNotEmpty && lbl.isNotEmpty) _floorLabelByFNumber[f] = lbl;
          }
          _currentFloor = widget.originFloorSrc;
        });
      }
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc('ChIJcYTQDwDjLj4RZEiboV6gZzM') // Solitaire ID
          .get(const GetOptions(source: Source.serverAndCache));

      final data = doc.data();
      if (data != null && data['map'] is List) {
        final maps = (data['map'] as List).cast<Map<String, dynamic>>();
        final convertedMaps = maps.map<Map<String, String>>((map) {
          return {
            'floorNumber': (map['floorNumber'] ?? '').toString(), // "GF", "F1"
            'F_number': (map['F_number'] ?? '').toString(), // "0", "1"
            'mapURL': (map['mapURL'] ?? '').toString(),
            'navmesh': (map['navmesh'] ?? '').toString(), // ✅ add
            'poiJsonPath':
                (map['poiJsonPath'] ?? map['poi_json'] ?? map['poiJson'] ?? '')
                    .toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            // Build floor label lookup (F_number -> floor label like GF/F1)
            _floorLabelByFNumber.clear();
            for (final m in _venueMaps) {
              final f = (m["F_number"]?.toString() ?? "");
              final lbl = (m["floorNumber"]?.toString() ?? "");
              if (f.isNotEmpty && lbl.isNotEmpty) _floorLabelByFNumber[f] = lbl;
            }
            if (convertedMaps.isNotEmpty) {
              // 1) Safe default.
              _currentFloor = convertedMaps.first['mapURL'] ?? '';

              // 2) If caller provided a mapURL, prefer it if it exists in venue maps.
              if (_requestedFloorIsUrl && _requestedFloorToken.isNotEmpty) {
                final exists = convertedMaps.any(
                  (m) => (m['mapURL'] ?? '') == _requestedFloorToken,
                );
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
                final savedF = _toFNumber(
                  _desiredStartFloorLabel,
                ); // "0"/"1"/...
                final match = convertedMaps.firstWhere(
                  (m) => (m['F_number'] ?? '') == savedF,
                  orElse: () => const {'mapURL': ''},
                );
                final url = match['mapURL'] ?? '';
                if (url.isNotEmpty) _currentFloor = url;
              }
            }
          });
          // If Category didn't know the floor, we may have discovered it from POI json.
          // Load connectors once we know venue floors.
          _ensureConnectorsLoaded();

          // Prefer showing the user's start floor if we already have it.
          if (_desiredStartFloorLabel.isNotEmpty) {
            _ensureFloorSelected(_desiredStartFloorLabel);
          } else if (widget.floorSrc.trim().isEmpty &&
              _pendingFloorLabelToOpen != null) {
            _ensureFloorSelected(_pendingFloorLabelToOpen!);
          } else {
            _loadNavmeshF1();
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading maps: $e");
    } finally {
      if (mounted) setState(() => _mapsLoading = false);
    }
  }

  bool _isPreferenceAvailableForCurrentTrip(String pref) {
    final p = pref.toLowerCase().trim();
    if (p.isEmpty || p == 'any') return true;

    final startLabel = _originFloorLabel.trim();
    final destLabel =
        (_destFloorLabelFixed ??
                _destFloorLabel ??
                widget.destinationFloorLabel ??
                '')
            .trim();

    // If floor labels are not resolved yet, don't block the UI.
    if (startLabel.isEmpty || destLabel.isEmpty) return true;

    final startFStr = _toFNumber(startLabel);
    final destFStr = _toFNumber(destLabel);

    // If parsing fails, don't block the UI.
    if (startFStr.isEmpty || destFStr.isEmpty) return true;

    // Same-floor trips don't need connectors; keep all prefs enabled.
    if (startFStr == destFStr) return false;

    final startF = int.tryParse(startFStr);
    final destF = int.tryParse(destFStr);
    if (startF == null || destF == null) return true;

    for (final c in _connectors) {
      final normType = _normalizeConnectorType(c.type);

      // Respect both type and direction (e.g. esc_up vs esc_dn).
      if (!_connectorMatchesPreference(normType, p)) continue;
      if (!_connectorDirectionAllowed(normType, startF, destF)) continue;

      final keys = c.endpointsByFNumber.keys.map((k) => k.toString()).toSet();
      if (keys.contains(startFStr) && keys.contains(destFStr)) return true;
    }

    return false;
  }

  Future<void> _changePreference(String preference) async {
    // Optional shortcut: tapping the same selected option resets to "All"
    final String nextPreference = (_selectedPreference == preference)
        ? 'any'
        : preference;

    if (!_isPreferenceAvailableForCurrentTrip(nextPreference)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextPreference == 'any'
                ? 'No route is available for these floors.'
                : 'No ${nextPreference.toLowerCase()} route is available for these floors.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    debugPrint('🎛️ changePreference: $_selectedPreference -> $nextPreference');

    setState(() {
      _selectedPreference = nextPreference;

      // Optional placeholder estimates (replace later with real route metrics)
      if (nextPreference == 'elevator') {
        _estimatedTime = '3 min';
        _estimatedDistance = '180 m';
      } else if (nextPreference == 'escalator') {
        _estimatedTime = '2.5 min';
        _estimatedDistance = '170 m';
      } else if (nextPreference == 'stairs') {
        _estimatedTime = '2 min';
        _estimatedDistance = '166 m';
      } else {
        // "any" = All connectors / shortest route
        _estimatedTime = '2 min';
        _estimatedDistance = '166 m';
      }
    });

    // Recompute current route immediately so connector filtering takes effect.
    try {
      final hadRoute = _routeComputed || _pathPointsByFloorGltf.isNotEmpty;
      final canCompute = _userPosBlender != null;

      if (hadRoute || canCompute) {
        _routeComputed = false;
        _pathPushed = false;
        _chosenConnectorId = null;
        _connectorStartBlender = null;
        _connectorDestBlender = null;
        _pathPointsByFloorGltf.clear();

        await _maybeComputeAndPushPath();

        debugPrint(
          '🎛️ recompute done. chosen=' +
              (_chosenConnectorId ?? 'none') +
              ' routeComputed=' +
              _routeComputed.toString() +
              ' visibleFloor=' +
              _currentFNumber() +
              ' pathFloors=' +
              _pathPointsByFloorGltf.keys.join(','),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to recompute route after preference change: $e');
    }
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
                              if (_currentPathPointsGltf.isNotEmpty &&
                                  !_pathPushed) {
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
                                (_originFloorLabel.isNotEmpty
                                    ? _originFloorLabel
                                    : _currentFloorLabel()),
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
                                _destFloorLabel ?? '--',
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
                            enabled: _isPreferenceAvailableForCurrentTrip(
                              'stairs',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Elevator',
                            Icons.elevator,
                            'elevator',
                            enabled: _isPreferenceAvailableForCurrentTrip(
                              'elevator',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Escalator',
                            Icons.escalator,
                            'escalator',
                            enabled: _isPreferenceAvailableForCurrentTrip(
                              'escalator',
                            ),
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
    String value, {
    bool enabled = true,
  }) {
    final bool isSelected = _selectedPreference == value;
    final bool isDisabled = !enabled;

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isDisabled ? null : () => _changePreference(value),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The button (original padding, unchanged)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE8E9E0) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.kGreen.withOpacity(0.30)
                      : const Color(0x00000000),
                  width: 1.2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isDisabled
                        ? Colors.grey[400]
                        : (isSelected ? AppColors.kGreen : Colors.grey[500]),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDisabled
                          ? Colors.grey[400]
                          : (isSelected ? AppColors.kGreen : Colors.grey[600]),
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Close icon – sits exactly on the top‑right border
            if (isSelected && !isDisabled)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.kGreen, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 9,
                    color: AppColors.kGreen,
                  ),
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

        onPressed: () async {
          // Clear current rendered path; it will be re-computed / re-pushed for the selected floor.
          setState(() {
            _pathPushed = false;
          });

          await _ensureFloorSelected(label);
        },

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
