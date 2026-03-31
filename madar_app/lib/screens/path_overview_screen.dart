// ============================================================================
// PATH OVERVIEW SCREEN (cleaned version)
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
import 'navigation_flow_complete.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PathOverviewScreen extends StatefulWidget {
  final String shopName;
  final String shopId;
  final String startingMethod;
  final String destinationPoiMaterial;
  final String destinationPoiName;
  final String floorSrc;
  final List<Map<String, String>>? venueMaps;
  final String? originFloorLabel;
  final String? destinationFloorLabel;
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
  final Map<String, Map<String, double>> endpointsByFNumber;

  const ConnectorLink({
    required this.id,
    required this.type,
    required this.endpointsByFNumber,
  });
}

class _PathOverviewScreenState extends State<PathOverviewScreen> {
  String _currentFloor = '';
  String _requestedFloorToken = '';
  bool _requestedFloorIsUrl = false;
  static const double _unitToMeters = 69.32;

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
  bool _isCalculating = false;
  String _estimatedTime = '';
  String _estimatedDistance = '';
  bool _arSupported = false;
  bool _arRefreshPending = false;
  final Map<String, bool> _arSupportCache = {};

  bool _usePinAsStart = true;
  Map<String, dynamic>? _customStartPoi;
  Map<String, dynamic>? _selectedDestPoi;
  List<Map<String, dynamic>> _activeRequests = [];

  String _toFNumber(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    if (s.isEmpty) return '';

    final up0 = s.toUpperCase();

    if (up0 == 'G' ||
        up0 == 'GF' ||
        up0.contains('GROUND') ||
        up0.contains('أرض') ||
        up0.contains('ارضي') ||
        up0.contains('أرضي')) {
      return '0';
    }

    var up = up0.replaceAll(RegExp(r'[\s_\-]+'), '');
    up = up
        .replaceAll('FLOOR', '')
        .replaceAll('LEVEL', '')
        .replaceAll('LVL', '')
        .replaceAll('FL', '');

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

    if (up.contains('الاول') || up.contains('الأول') || up.contains('اول'))
      return '1';
    if (up.contains('الثاني') || up.contains('ثاني')) return '2';
    if (up.contains('الثالث') || up.contains('ثالث')) return '3';
    if (up.contains('الرابع') || up.contains('رابع')) return '4';
    if (up.contains('الخامس') || up.contains('خامس')) return '5';

    final m1 = RegExp(r'^(?:F|L)?(-?\d+)$').firstMatch(up);
    if (m1 != null) return m1.group(1)!;

    final m2 = RegExp(r'(-?\d+)').firstMatch(up);
    if (m2 != null) return m2.group(1)!;

    return '';
  }

  Future<bool> _checkArSupportForDestination() async {
    // No destination coordinates → AR not possible
    if (_destPosBlender == null) return false;

    // If no selected destination POI, assume it's a custom pin (user placed) → valid
    if (_selectedDestPoi == null) return true;

    final dest = _selectedDestPoi!;
    final destType = dest['type'] ?? '';

    // Service destinations (bathrooms, prayer room) have predefined coordinates → valid
    final name = (dest['name'] ?? '').toString().toLowerCase();
    if (name == 'female bathroom' ||
        name == 'male bathroom' ||
        name == 'prayer room') {
      return true;
    }

    // For POIs, check Firestore for worldPosition
    if (destType == 'poi') {
      // Use a cache key
      final cacheKey = dest['id'] ?? dest['material'] ?? dest['name'] ?? '';
      if (cacheKey.isNotEmpty && _arSupportCache.containsKey(cacheKey)) {
        return _arSupportCache[cacheKey]!;
      }

      // Helper to fetch place document by various identifiers, returns null if not found
      Future<DocumentSnapshot<Map<String, dynamic>>?>
      _fetchPlaceDocument() async {
        // 1. Try by place ID (most reliable)
        String? placeId = dest['id']?.toString();
        if (placeId != null && placeId.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('places')
              .doc(placeId)
              .get();
          if (doc.exists) return doc;
        }

        // 2. Try by poiMaterial (raw)
        final material = dest['material']?.toString();
        if (material != null && material.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('places')
              .where('venue_ID', isEqualTo: 'ChIJcYTQDwDjLj4RZEiboV6gZzM')
              .where('poiMaterial', isEqualTo: material)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) return snap.docs.first;
        }

        // 3. Try by poiMaterial without suffix (e.g., POIMAT_Balenciaga.001 → POIMAT_Balenciaga)
        if (material != null && material.isNotEmpty) {
          final base = material.replaceAll(RegExp(r'\.\d+$'), '');
          if (base != material) {
            final snap = await FirebaseFirestore.instance
                .collection('places')
                .where('venue_ID', isEqualTo: 'ChIJcYTQDwDjLj4RZEiboV6gZzM')
                .where('poiMaterial', isEqualTo: base)
                .limit(1)
                .get();
            if (snap.docs.isNotEmpty) return snap.docs.first;
          }
        }

        // 4. Try by placeName (cleaned name)
        final placeName = dest['name']?.toString();
        if (placeName != null && placeName.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('places')
              .where('venue_ID', isEqualTo: 'ChIJcYTQDwDjLj4RZEiboV6gZzM')
              .where('placeName', isEqualTo: placeName)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) return snap.docs.first;
        }

        // 5. Last resort: try to find by material normalized using client-side fetch
        if (material != null && material.isNotEmpty) {
          final norm = _normPoiKey(material);
          final allSnap = await FirebaseFirestore.instance
              .collection('places')
              .where('venue_ID', isEqualTo: 'ChIJcYTQDwDjLj4RZEiboV6gZzM')
              .get();
          for (final doc in allSnap.docs) {
            final docMat = doc.data()['poiMaterial']?.toString();
            if (docMat != null && _normPoiKey(docMat) == norm) {
              return doc;
            }
            final docName = doc.data()['placeName']?.toString();
            if (docName != null && _normPoiKey(docName) == norm) {
              return doc;
            }
          }
        }

        return null; // Not found
      }

      final doc = await _fetchPlaceDocument();
      if (doc != null && doc.exists) {
        final data = doc.data();
        final supported =
            data != null &&
            data.containsKey('worldPosition') &&
            data['worldPosition'] != null;
        if (cacheKey.isNotEmpty) _arSupportCache[cacheKey] = supported;
        return supported;
      }

      // Not found in Firestore → assume not supported
      if (cacheKey.isNotEmpty) _arSupportCache[cacheKey] = false;
      return false;
    }

    // Any other type (e.g., custom pin) → assume valid
    return true;
  }

  Future<void> _refreshArSupport() async {
    if (_arRefreshPending) return; // prevent overlapping runs
    _arRefreshPending = true;
    try {
      final supported = await _checkArSupportForDestination();
      if (mounted && _arSupported != supported) {
        setState(() {
          _arSupported = supported;
        });
      }
    } finally {
      _arRefreshPending = false;
    }
  }

  int? _fNumberFromLabel(String? floorLabel) {
    final s = (floorLabel ?? '').trim().toUpperCase();
    if (s.isEmpty) return null;
    if (s == 'GF' || s == 'G' || s == '0' || s == 'F0') return 0;
    final m = RegExp(r'F?\s*(-?\d+)').firstMatch(s);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  String _floorLabelFromToken(String? token) {
    final raw = (token ?? '').trim();
    if (raw.isEmpty) return '';
    final up = raw.toUpperCase();
    if (up == 'G' ||
        up == 'GF' ||
        up.contains('GROUND') ||
        up.contains('GROUNDFLOOR')) {
      return 'GF';
    }
    final mPath = RegExp(
      r'(?:^|[^A-Z0-9])(GF|F\d+)(?:[^A-Z0-9]|$)',
    ).firstMatch(up);
    if (mPath != null) return mPath.group(1)!;
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

  double _calculateTotalDistance() {
    double total = 0.0;
    _pathPointsByFloorGltf.forEach((floor, points) {
      for (int i = 1; i < points.length; i++) {
        final p1 = points[i - 1];
        final p2 = points[i];
        final dx = p1['x']! - p2['x']!;
        final dy = p1['y']! - p2['y']!;
        final dz = p1['z']! - p2['z']!;
        total += math.sqrt(dx * dx + dy * dy + dz * dz);
      }
    });
    return total;
  }

  String _cleanPoiName(String raw) {
    String name = raw.replaceFirst(
      RegExp(r'^POIMAT_', caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'\.\d+$'), '');
    name = name.replaceAll('_', ' ');
    return name.trim();
  }

  String _displayNameFromEntrance(
    Map<String, dynamic> entry,
    String fallbackKey,
  ) {
    final material = (entry['material'] ?? '').toString().trim();
    final category = (entry['category'] ?? '').toString().trim().toLowerCase();
    final type = (entry['type'] ?? '').toString().trim().toLowerCase();
    final rawName = (entry['name'] ?? '').toString().trim();

    // Bathrooms
    if (category == 'bathrooms' || type.startsWith('bathroom_')) {
      if (type == 'bathroom_female') return 'Female Bathroom';
      if (type == 'bathroom_male') return 'Male Bathroom';
      if (type == 'bathroom_shared') return 'Bathroom';
    }

    // Prayer rooms
    if (category == 'prayer_rooms' || type.startsWith('prayer_')) {
      if (type == 'prayer_shared') return 'Prayer Room';
      if (type == 'prayer_female') return 'Female Prayer Room';
      if (type == 'prayer_male') return 'Male Prayer Room';
    }

    if (rawName.isNotEmpty) return rawName;

    return _cleanPoiName(material.isNotEmpty ? material : fallbackKey);
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
    for (final m in _venueMaps) {
      if (((m['floorNumber'] ?? '').toString()).trim() == want) {
        return (m['mapURL'] ?? '').toString();
      }
    }
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

    if (_venueMaps.isEmpty) {
      _pendingFloorLabelToOpen = label;
      return;
    }

    final desiredUrl = _mapUrlForFloorLabel(label);
    if (desiredUrl.isEmpty) return;

    if (_currentFloor.trim() != desiredUrl) {
      setState(() => _currentFloor = desiredUrl);

      _pathPushed = false;
      _jsReady = false;
      _readyComputeRetry = 0;

      await _ensureNavmeshLoadedForFNumber(_toFNumber(_currentFloorLabel()));

      if (_pathPointsByFloorGltf.isEmpty) {
        _maybeComputeAndPushPath();
      } else {
        _syncOverlaysForCurrentFloor();
      }
    }
  }

  bool _isSavedFloorActive() {
    final savedRaw = _desiredStartFloorLabel.isNotEmpty
        ? _desiredStartFloorLabel
        : _originFloorLabel;
    final saved = _toFNumber(savedRaw);
    final current = _currentFNumber();
    if (saved.isEmpty || current.isEmpty) return true;
    return saved == current;
  }

  WebViewController? _webCtrl;
  bool _jsReady = false;
  int _readyComputeRetry = 0;
  Map<String, double>? _pendingUserPinGltf;
  String? _pendingPoiToHighlight;

  // --- Entrances only (no POI index) ---
  Map<String, List<Map<String, dynamic>>> _entrancesByPoi = {};
  bool _entrancesLoaded = false;
  List<Map<String, dynamic>>? _destEntrances;

  // --- Navmesh & path state ---
  NavMesh? _navmeshF1;
  Map<String, double>? _userPosBlender;
  Map<String, double>? _destPosBlender;
  Map<String, double>? _userSnappedBlender;
  Map<String, double>? _destSnappedBlender;

  final Map<String, List<Map<String, double>>> _pathPointsByFloorGltf = {};
  bool _pathPushed = false;
  bool _routeComputed = false;
  String? _originFloorLabelFixed;
  String? _destFloorLabelFixed;
  String? _originFNumberFixed;
  String? _destFNumberFixed;

  String? _destFloorLabel;
  String? _destPoiMaterialResolved;
  String? _chosenConnectorId;
  Map<String, double>? _connectorStartBlender;
  Map<String, double>? _connectorDestBlender;

  List<ConnectorLink> _connectors = const [];
  bool _connectorsLoaded = false;
  final Map<String, NavMesh> _navmeshCache = {};
  final Map<String, String> _floorLabelByFNumber = {};
  final Map<String, List<ConnectorLink>> _connectorsByFloorLabel = {};
  final Map<String, List<Map<String, dynamic>>>
  _connectorEndpointsByFloorLabel = {};

  List<Map<String, double>> get _currentPathPointsGltf =>
      _pathPointsByFloorGltf[_currentFNumber()] ?? const [];

  // --- Navmesh loading (only GF/F1) ---
  Future<NavMesh?> _ensureNavmeshLoadedForFNumber(String fNumber) async {
    if (_navmeshCache.containsKey(fNumber)) return _navmeshCache[fNumber];

    String? assetPath;
    for (final m in _venueMaps) {
      if ((m["F_number"]?.toString() ?? "") == fNumber) {
        assetPath = m["navmesh"];
        break;
      }
    }

    // Fallback based on fNumber
    assetPath ??= (fNumber == "0")
        ? 'assets/nav_cor/navmesh_GF.json'
        : (fNumber == "1" ? 'assets/nav_cor/navmesh_F1.json' : null);

    if (assetPath == null) return null;

    try {
      final nm = await NavMesh.loadAsset(assetPath);
      _navmeshCache[fNumber] = nm;
      debugPrint("✅ Navmesh loaded for floor $fNumber: $assetPath");
      return nm;
    } catch (e) {
      debugPrint(
        "❌ Failed to load navmesh for floor $fNumber ($assetPath): $e",
      );
      return null;
    }
  }

  // --- Connectors loading (single file) ---
  Future<void> _ensureConnectorsLoaded() async {
    if (_connectorsLoaded) return;
    try {
      const path = 'assets/connectors/connectors_merged_local.json';
      final raw = await rootBundle.loadString(path);
      debugPrint('✅ Connectors loaded: $path');

      final decoded = jsonDecode(raw);
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

            String? f;
            if (ep['floorNumber'] != null) {
              f = ep['floorNumber'].toString();
            } else if (ep['f_number'] != null) {
              f = ep['f_number'].toString();
            } else if (ep['floor'] != null &&
                (ep['floor'] is num || ep['floor'] is String)) {
              f = ep['floor'].toString();
            } else if (ep['floorLabel'] != null ||
                ep['floor_label'] != null ||
                ep['label'] != null) {
              final lbl = (ep['floorLabel'] ?? ep['floor_label'] ?? ep['label'])
                  .toString();
              f = _toFNumber(lbl);
            }
            if (f == null || f.isEmpty) continue;

            Map<String, dynamic>? posMap;
            if (ep['position'] is Map)
              posMap = (ep['position'] as Map).cast<String, dynamic>();
            if (posMap == null && ep['pos'] is Map)
              posMap = (ep['pos'] as Map).cast<String, dynamic>();

            double? x = _asDouble(posMap?['x'] ?? ep['x']);
            double? y = _asDouble(posMap?['y'] ?? ep['y']);
            double? z = _asDouble(posMap?['z'] ?? ep['z']);

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
      _connectorsLoaded = true;
      debugPrint("❌ Failed to load connectors: $e");
    }
  }

  Future<void> _syncOverlaysForCurrentFloor() async {
    if (!_jsReady) return;

    await _pushPathToJs();

    final startLabel = _desiredStartFloorLabel.isNotEmpty
        ? _desiredStartFloorLabel
        : _currentFloorLabel();
    final startF = _toFNumber(startLabel);
    final currF = _currentFNumber();

    // Handle user pin (start)
    if (_pendingUserPinGltf != null && currF == startF) {
      await _pushUserPinToJsPath(_pendingUserPinGltf!);
    } else {
      await _clearUserPinFromJs();
    }

    // Handle destination: either POI highlight or destination pin
    final destLabel =
        _destFloorLabelFixed ??
        _destFloorLabel ??
        widget.destinationFloorLabel ??
        '';
    if (destLabel.isNotEmpty) {
      final destF = _toFNumber(destLabel);
      if (currF == destF && _destPosBlender != null) {
        // Determine if destination is a POI (has a material to highlight)
        final bool isPoi =
            _pendingPoiToHighlight != null &&
            _pendingPoiToHighlight!.trim().isNotEmpty;

        if (isPoi) {
          // POI destination: clear any leftover destination pin,
          // the highlight will be handled by _pushDestinationHighlightToJsPath
          await _webCtrl?.runJavaScript('window.clearDestPinFromFlutter();');
        } else {
          // Custom pin: show the green destination pin and clear any POI highlight
          final destGltf = _blenderToGltf(_destPosBlender!);
          await _pushDestPinToJs(destGltf);
          // _pendingPoiToHighlight is null, so _pushDestinationHighlightToJsPath will clear highlights
        }
      } else {
        // Not on the destination floor: clear both pin and highlight
        await _webCtrl?.runJavaScript('window.clearDestPinFromFlutter();');
        // POI highlight will be cleared by _pushDestinationHighlightToJsPath because destF != currF
      }
    }

    // This call handles POI highlighting (it will clear if no highlight needed)
    await _pushDestinationHighlightToJsPath();
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

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
    return true;
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
    if (c == null || !_jsReady) return;

    final destF = _toFNumber(_destFloorLabel);
    final currF = _currentFNumber();

    // If destination floor is unknown, clear any highlight
    if (destF.isEmpty) {
      await c.runJavaScript(
        'window.clearPoiHighlightFromFlutter && window.clearPoiHighlightFromFlutter();',
      );
      return;
    }

    // If current floor is not the destination floor, clear highlight
    if (destF != currF) {
      await c.runJavaScript(
        'window.clearPoiHighlightFromFlutter && window.clearPoiHighlightFromFlutter();',
      );
      return;
    }

    final name = _pendingPoiToHighlight;
    if (name == null || name.trim().isEmpty) {
      // No destination to highlight, clear
      await c.runJavaScript(
        'window.clearPoiHighlightFromFlutter && window.clearPoiHighlightFromFlutter();',
      );
      return;
    }

    final safe = name.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    await c.runJavaScript('window.highlightPoiFromFlutter("$safe");');
  }

  Future<void> _pushDestPinToJs(Map<String, double> gltf) async {
    final c = _webCtrl;
    if (c == null || !_jsReady) {
      debugPrint('❌ _pushDestPinToJs: webCtrl or jsReady false');
      return;
    }
    final x = gltf['x'];
    final y = gltf['y'];
    final z = gltf['z'];
    if (x == null || y == null || z == null) {
      debugPrint('❌ _pushDestPinToJs: invalid coordinates $gltf');
      return;
    }
    try {
      await c.runJavaScript('window.setDestPinFromFlutter($x,$y,$z);');
      await c.runJavaScript('window.testDestPin();');
    } catch (e) {
      debugPrint('❌ pushDestPinToJs failed: $e');
    }
  }

  String _normPoiKey(String s) {
    var n = (s).trim().toLowerCase();
    n = n.replaceAll(RegExp(r"\.[0-9]+$"), "");
    n = n.replaceAll(RegExp(r"[^a-z0-9]+"), "");
    if (n.startsWith("poimat")) {
      n = n.substring(6);
    }
    if (n.startsWith("_")) n = n.substring(1);
    return "poimat_" + n;
  }

  bool _isBlank(String? s) => s == null || s.trim().isEmpty;

  // --- Load only entrances ---
  Future<void> _loadEntrances() async {
    try {
      const path = 'assets/poi/solitaire_entrances.json';
      final String jsonStr = await rootBundle.loadString(path);
      final List<dynamic> list = jsonDecode(jsonStr);
      final Map<String, List<Map<String, dynamic>>> map = {};

      for (final item in list) {
        if (item is! Map) continue;
        final material = item['poiMaterial']?.toString();
        if (material == null || material.isEmpty) continue;

        final normKey = _normPoiKey(material);

        final pos = item['pos'];
        if (pos is Map) {
          final x = (pos['x'] as num?)?.toDouble();
          final y = (pos['y'] as num?)?.toDouble();
          final z = (pos['z'] as num?)?.toDouble();
          final floor = item['floor']?.toString() ?? 'GF';
          if (x != null && y != null && z != null) {
            map.putIfAbsent(normKey, () => []).add({
              'x': x,
              'y': y,
              'z': z,
              'floor': floor,
              'id': item['id']?.toString(),
              'material': material,
              'name':
                  item['name']?.toString() ??
                  (item['category']?.toString().toLowerCase() == 'gates'
                      ? item['poiMaterial']
                            ?.toString()
                            .replaceFirst('POIMAT_', '')
                            .trim()
                      : null),
              'category': item['category']?.toString(),
              // ---- FIX: parse categories as List<String> ----
              'categories': item['categories'] is List
                  ? (item['categories'] as List)
                        .map((e) => e.toString())
                        .toList()
                  : (item['category'] != null
                        ? [item['category'].toString()]
                        : []),
              'type': item['type']?.toString(),
              'gender': item['gender']?.toString(),
            });
          }
        }
      }

      _entrancesByPoi = map;
      _entrancesLoaded = true;
      debugPrint('✅ Entrances loaded: ${map.length} POIs with entrances');
      // After building _entrancesByPoi, fetch descriptions for gates
      final gateEntries = <Map<String, dynamic>>[];
      _entrancesByPoi.forEach((key, entrances) {
        for (final e in entrances) {
          if ((e['category']?.toString().toLowerCase() == 'gates')) {
            gateEntries.add(e);
          }
        }
      });
      print('🚪 Found ${gateEntries.length} gate entries');

      if (gateEntries.isNotEmpty) {
        // Collect unique gate names
        final gateNames = gateEntries
            .map((e) => e['name']?.toString().trim())
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

        final venueId = "ChIJcYTQDwDjLj4RZEiboV6gZzM";
        final venueName = "solitaire";

        if (gateNames.isNotEmpty) {
          try {
            final querySnapshot = await FirebaseFirestore.instance
                .collection('places')
                .where('venue_ID', isEqualTo: venueId)
                .where('placeName', whereIn: gateNames)
                .get();

            final descMap = <String, String>{};

            for (final doc in querySnapshot.docs) {
              final data = doc.data();

              final rawName = data['placeName']?.toString().trim();
              final desc = data['placeDescription']?.toString();

              if (rawName == null || desc == null) continue;

              final lowerName = rawName.toLowerCase();
              descMap[lowerName] = desc;
            }

            for (final e in gateEntries) {
              final entranceName = e['name']?.toString().trim().toLowerCase();
              e['description'] = descMap[entranceName] ?? 'Gate';
            }
          } catch (e) {
            debugPrint('⚠️ Failed to fetch gate descriptions: $e');
            for (final e in gateEntries) {
              e['description'] = 'Gate';
            }
          }
        }
      }

      _entrancesLoaded = true;
      if (mounted) setState(() {}); // refresh UI
      debugPrint(
        '✅ Entrances loaded: ${_entrancesByPoi.length} POIs with entrances',
      );
    } catch (e) {
      debugPrint('❌ Failed to load entrances: $e');
    }
  }

  Map<String, dynamic>? _findServiceDestinationOption(String shopId) {
    final all = _getAllPoisFromEntrances();

    if (shopId == 'service_bathroom_female') {
      return all.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e?['name'] == 'Female Bathroom',
        orElse: () => null,
      );
    }

    if (shopId == 'service_bathroom_male') {
      return all.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e?['name'] == 'Male Bathroom',
        orElse: () => null,
      );
    }

    if (shopId == 'service_prayer_room') {
      return all.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e?['name'] == 'Prayer Room',
        orElse: () => null,
      );
    }

    return null;
  }

  Future<void> _loadActiveRequests() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final now = DateTime.now();
      final querySnapshot = await FirebaseFirestore.instance
          .collection('trackRequests')
          .where('senderId', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final List<Map<String, dynamic>> active = [];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final startAt = (data['startAt'] as Timestamp?)?.toDate();
        final endAt = (data['endAt'] as Timestamp?)?.toDate();

        // Skip if time window is missing or not currently active
        if (startAt == null || endAt == null) continue;
        if (now.isBefore(startAt) || now.isAfter(endAt)) continue;

        final receiverId = data['receiverId'] as String?;
        if (receiverId == null || receiverId.isEmpty) continue;

        // Fetch receiver's user document to get name and location
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(receiverId)
            .get();

        if (!userDoc.exists) continue;
        final userData = userDoc.data();
        if (userData == null) continue;

        // Compose name
        final firstName = userData['firstName']?.toString().trim() ?? '';
        final lastName = userData['lastName']?.toString().trim() ?? '';
        final fullName = (firstName.isNotEmpty || lastName.isNotEmpty)
            ? '$firstName $lastName'.trim()
            : (userData['name']?.toString() ??
                  userData['fullName']?.toString() ??
                  userData['email']?.toString() ??
                  'Unknown');

        // Get blenderPosition
        final location = userData['location'] as Map?;
        if (location == null) continue;
        final blender = location['blenderPosition'] as Map?;
        if (blender == null) continue;

        final x = (blender['x'] as num?)?.toDouble();
        final y = (blender['y'] as num?)?.toDouble();
        final z = (blender['z'] as num?)?.toDouble();
        final floor = (blender['floor'] ?? '').toString().trim();

        if (x == null || y == null || z == null || floor.isEmpty) continue;

        active.add({'name': fullName, 'floor': floor, 'x': x, 'y': y, 'z': z});
      }

      if (mounted) {
        setState(() {
          _activeRequests = active;
        });
        debugPrint('✅ Active requests loaded: ${active.length}');
      }
    } catch (e) {
      debugPrint('Error loading active requests: $e');
    }
  }

  List<Map<String, dynamic>> _getAllPoisFromEntrances() {
    final result = <Map<String, dynamic>>[];

    final femaleBathrooms = <Map<String, dynamic>>[];
    final maleBathrooms = <Map<String, dynamic>>[];

    final prayerRooms = <Map<String, dynamic>>[];

    _entrancesByPoi.forEach((normKey, entrances) {
      if (entrances.isEmpty) return;

      final first = entrances.first;
      final material = (first['material'] ?? '').toString();
      final category = (first['category'] ?? '').toString().toLowerCase();
      final serviceType = (first['type'] ?? '').toString().toLowerCase();

      final isBathroom =
          category == 'bathrooms' || serviceType.startsWith('bathroom_');
      final isPrayer =
          category == 'prayer_rooms' || serviceType.startsWith('prayer_');

      if (isBathroom) {
        if (serviceType == 'bathroom_female') {
          femaleBathrooms.addAll(
            entrances.map(
              (e) => {...Map<String, dynamic>.from(e), 'material': material},
            ),
          );
        } else if (serviceType == 'bathroom_male') {
          maleBathrooms.addAll(
            entrances.map(
              (e) => {...Map<String, dynamic>.from(e), 'material': material},
            ),
          );
        } else if (serviceType == 'bathroom_shared') {
          final sharedEntries = entrances.map(
            (e) => {...Map<String, dynamic>.from(e), 'material': material},
          );
          femaleBathrooms.addAll(sharedEntries);
          maleBathrooms.addAll(sharedEntries);
        }
        return;
      }

      if (isPrayer) {
        prayerRooms.addAll(
          entrances.map(
            (e) => {...Map<String, dynamic>.from(e), 'material': material},
          ),
        );
        return;
      }

      final displayName = _displayNameFromEntrance(first, normKey);

      result.add({
        'name': displayName,
        'type': 'poi',
        'floor': first['floor'] ?? '',
        'x': first['x'],
        'y': first['y'],
        'z': first['z'],
        'material': material,
        'category': first['category'],
        'categories': first['categories'] ?? [],
        'serviceType': first['type'],
        'gender': first['gender'],
        'description': first['description'],
      });
    });

    if (femaleBathrooms.isNotEmpty) {
      final best = _pickClosestEntryToCurrentStart(femaleBathrooms);
      result.add({
        'name': 'Female Bathroom',
        'type': 'poi',
        'floor': best['floor'] ?? '',
        'x': best['x'],
        'y': best['y'],
        'z': best['z'],
        'material': best['material'],
        'category': 'bathrooms',
        'categories': [],
        'serviceType': 'bathroom_female_or_shared',
        'gender': 'female',
      });
    }

    if (maleBathrooms.isNotEmpty) {
      final best = _pickClosestEntryToCurrentStart(maleBathrooms);
      result.add({
        'name': 'Male Bathroom',
        'type': 'poi',
        'floor': best['floor'] ?? '',
        'x': best['x'],
        'y': best['y'],
        'z': best['z'],
        'material': best['material'],
        'category': 'bathrooms',
        'serviceType': 'bathroom_male_or_shared',
        'gender': 'male',
      });
    }

    if (prayerRooms.isNotEmpty) {
      final best = _pickClosestEntryToCurrentStart(prayerRooms);
      result.add({
        'name': 'Prayer Room',
        'type': 'poi',
        'floor': best['floor'] ?? '',
        'x': best['x'],
        'y': best['y'],
        'z': best['z'],
        'material': best['material'],
        'category': 'prayer_rooms',
        'serviceType': 'prayer_shared',
        'gender': 'shared',
      });
    }

    result.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
    return result;
  }

  Map<String, dynamic> _pickClosestEntryToCurrentStart(
    List<Map<String, dynamic>> entries,
  ) {
    if (entries.isEmpty) return {};

    final start =
        _customStartPoi ??
        {
          'x': _userPosBlender?['x'],
          'y': _userPosBlender?['y'],
          'z': _userPosBlender?['z'],
          'floor': _desiredStartFloorLabel,
        };

    final startFloor = _toFNumber((start['floor'] ?? '').toString());

    List<Map<String, dynamic>> candidates = entries;
    if (startFloor != null) {
      final sameFloor = entries.where((e) {
        return _toFNumber((e['floor'] ?? '').toString()) == startFloor;
      }).toList();

      if (sameFloor.isNotEmpty) {
        candidates = sameFloor;
      }
    }

    Map<String, dynamic> best = candidates.first;
    double bestDistSq = double.infinity;

    final sx = (start['x'] as num?)?.toDouble() ?? 0.0;
    final sy = (start['y'] as num?)?.toDouble() ?? 0.0;
    final sz = (start['z'] as num?)?.toDouble() ?? 0.0;

    for (final e in candidates) {
      final ex = (e['x'] as num?)?.toDouble() ?? 0.0;
      final ey = (e['y'] as num?)?.toDouble() ?? 0.0;
      final ez = (e['z'] as num?)?.toDouble() ?? 0.0;

      final dx = ex - sx;
      final dy = ey - sy;
      final dz = ez - sz;
      final distSq = dx * dx + dy * dy + dz * dz;

      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        best = e;
      }
    }

    return best;
  }

  // --- Resolve destination using entrances only ---
  Future<void> _resolveDestinationFromEntrances() async {
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

    final normName = _normPoiKey(name);
    if (_entrancesByPoi.containsKey(normName)) {
      final entrances = _entrancesByPoi[normName]!;
      _destEntrances = entrances;

      final first = entrances.first;
      setState(() {
        _destPosBlender = {'x': first['x'], 'y': first['y'], 'z': first['z']};
        if (_destFloorLabel == null || _destFloorLabel!.isEmpty) {
          _destFloorLabel = first['floor'];
        }
      });

      // 🔥 Set _selectedDestPoi with full entrance data
      _selectedDestPoi = {
        'name': _displayNameFromEntrance(first, name),
        'type': 'poi',
        'floor': _destFloorLabel ?? first['floor'],
        'x': first['x'],
        'y': first['y'],
        'z': first['z'],
        'material': first['material'],
        'id': first['id'],
      };

      // Try to pick a better label from venue maps
      if (_venueMaps.isNotEmpty) {
        for (final vm in _venueMaps) {
          final t = (vm['floorNumber'] ?? vm['title'] ?? vm['label'] ?? '')
              .toString();
          if (t.isEmpty) continue;
          if (_toFNumber(t) == _toFNumber(first['floor'])) {
            _pendingFloorLabelToOpen = t;
            _destFloorLabel = t;
            break;
          }
        }
      }

      debugPrint(
        '✅ Destination resolved from entrances: $name -> floor=$_destFloorLabel',
      );
    } else {
      debugPrint(
        '⚠️ Destination not found in entrances for "$name" (norm="$normName")',
      );
    }
  }

  // --- Coordinate conversions ---
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
    final nm = await _ensureNavmeshLoadedForFNumber(
      _toFNumber(_currentFloorLabel()),
    );
    if (!mounted) return;
    setState(() {
      _navmeshF1 = nm;
    });
  }

  // --- Path helpers ---
  List<List<double>> _smoothAndResamplePath(
    List<List<double>> path,
    NavMesh nm,
  ) {
    var pts = path;
    pts = _resampleByDistance(pts, step: 0.06);
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

    const double sampleStep = 0.06;

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
    await _resolveDestinationFromEntrances();
    _refreshArSupport();
    if (_routeComputed) {
      await _syncOverlaysForCurrentFloor();
      return;
    }

    if (mounted)
      setState(() {
        _isCalculating = true;
        _estimatedTime = '';
        _estimatedDistance = '';
      });

    try {
      Map<String, double>? effectiveStart;
      String? effectiveStartFloor;

      if (_usePinAsStart) {
        effectiveStart = _userPosBlender;
        effectiveStartFloor = _originFloorLabel;
      } else {
        effectiveStart = _customStartPoi != null
            ? {
                'x': _customStartPoi!['x'],
                'y': _customStartPoi!['y'],
                'z': _customStartPoi!['z'],
              }
            : null;
        effectiveStartFloor = _customStartPoi?['floor'];
      }

      Map<String, double>? effectiveDest =
          _destPosBlender ??
          (_selectedDestPoi != null
              ? {
                  'x': _selectedDestPoi!['x'],
                  'y': _selectedDestPoi!['y'],
                  'z': _selectedDestPoi!['z'],
                }
              : null);
      _refreshArSupport();
      String? effectiveDestFloor =
          _selectedDestPoi?['floor'] ?? _destFloorLabel;

      if (effectiveStart == null || effectiveDest == null) {
        debugPrint('⚠️ Missing start or destination coordinates');
        await _syncOverlaysForCurrentFloor();
        return;
      }

      if (_destEntrances != null &&
          _destEntrances!.length > 1 &&
          effectiveStart != null) {
        final startFloor = _toFNumber(
          effectiveStartFloor ?? _desiredStartFloorLabel,
        );
        final destFloor = _toFNumber(_destFloorLabel ?? '');

        if (startFloor == destFloor) {
          double bestDistSq = double.infinity;
          Map<String, double>? bestEntrance;

          final sameFloorEntrances = _destEntrances!
              .where(
                (e) => _toFNumber(e['floor']?.toString() ?? '') == startFloor,
              )
              .toList();
          final entrList = sameFloorEntrances.isNotEmpty
              ? sameFloorEntrances
              : _destEntrances!;

          for (final e in entrList) {
            final dx = (e['x'] as double) - (effectiveStart['x'] ?? 0);
            final dy = (e['y'] as double) - (effectiveStart['y'] ?? 0);
            final dz = (e['z'] as double) - (effectiveStart['z'] ?? 0);
            final distSq = dx * dx + dy * dy + dz * dz;
            if (distSq < bestDistSq) {
              bestDistSq = distSq;
              bestEntrance = {'x': e['x'], 'y': e['y'], 'z': e['z']};
            }
          }

          if (bestEntrance != null) {
            effectiveDest = bestEntrance;
            _destPosBlender = bestEntrance;
            if (_selectedDestPoi != null) {
              _selectedDestPoi!['x'] = bestEntrance['x'];
              _selectedDestPoi!['y'] = bestEntrance['y'];
              _selectedDestPoi!['z'] = bestEntrance['z'];
            }
            debugPrint('✅ Chosen closest entrance');
          }
        } else {
          debugPrint(
            '⚠️ Start and destination on different floors – using first entrance',
          );
        }
      }

      final startLabel = effectiveStartFloor ?? _desiredStartFloorLabel;
      final destLabel = effectiveDestFloor ?? '';
      if (startLabel.trim().isEmpty) {
        debugPrint('⚠️ Start floor unknown — abort routing');
        await _syncOverlaysForCurrentFloor();
        return;
      }
      final destCandidate = _floorLabelFromToken(destLabel) ?? destLabel;
      final destFloor = destCandidate.isNotEmpty ? destCandidate : startLabel;

      final startF = _toFNumber(startLabel);
      final destF = _toFNumber(destFloor);

      _originFloorLabelFixed ??= startLabel;
      _destFloorLabelFixed ??= destFloor;
      _originFNumberFixed ??= startF;
      _destFNumberFixed ??= destF;

      final startNm = await _ensureNavmeshLoadedForFNumber(startF);
      final destNm = await _ensureNavmeshLoadedForFNumber(destF);
      if (startNm == null || destNm == null) {
        await _syncOverlaysForCurrentFloor();
        return;
      }
      _navmeshF1 = _navmeshCache[_currentFloor];
      await _ensureConnectorsLoaded();

      _pathPointsByFloorGltf.clear();
      _chosenConnectorId = null;
      _connectorStartBlender = null;
      _connectorDestBlender = null;

      List<List<double>> computePathOn(
        NavMesh nm,
        Map<String, double> aBl,
        Map<String, double> bBl,
      ) {
        final a = nm.snapPointXY([aBl['x']!, aBl['y']!, aBl['z']!]);
        final b = [bBl['x']!, bBl['y']!, bBl['z']!];
        var raw = nm.findPathFunnelBlenderXY(start: a, goal: b);
        var sm = _smoothAndResamplePath(raw, nm);
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
        final pts = computePathOn(startNm, effectiveStart, effectiveDest);
        final gltf = pts
            .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
            .toList();
        _pathPointsByFloorGltf[startF] = gltf;
      } else {
        final pref = _selectedPreference.toLowerCase();
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

        final candidates = _connectors
            .where((c) => linksFloors(c) && matchesPref(c))
            .toList();
        final pool = candidates.isNotEmpty
            ? candidates
            : _connectors
                  .where((c) => linksFloors(c) && directionOk(c))
                  .toList();

        debugPrint(
          '🧭 pref=$pref start=$startLabel($startF) dest=$destFloor($destF) matched=${candidates.length} pool=${pool.length}',
        );
        if (pool.isEmpty) {
          debugPrint(
            "⚠️ No connectors found linking $startLabel -> $destFloor",
          );
          await _syncOverlaysForCurrentFloor();
          return;
        }

        double bestScore = double.infinity;
        ConnectorLink? best;
        List<List<double>> bestA = const [];
        List<List<double>> bestB = const [];

        final destCandidates = <Map<String, double>>[];
        if (_destEntrances != null && _destEntrances!.isNotEmpty) {
          for (final e in _destEntrances!) {
            final ef = _toFNumber(e['floor']?.toString() ?? '');
            if (ef == destF) {
              destCandidates.add({
                'x': (e['x'] as num).toDouble(),
                'y': (e['y'] as num).toDouble(),
                'z': (e['z'] as num).toDouble(),
              });
            }
          }
        }
        if (destCandidates.isEmpty && effectiveDest != null) {
          destCandidates.add(effectiveDest);
        }

        Map<String, double>? bestDest;
        for (final c in pool) {
          final aPos = c.endpointsByFNumber[startF]!;
          final bPos = c.endpointsByFNumber[destF]!;
          final aPts = computePathOn(startNm, effectiveStart, aPos);
          if (aPts.length < 2) continue;

          for (final d in destCandidates) {
            final bPts = computePathOn(destNm, bPos, d);
            if (bPts.length < 2) continue;
            final score = pathLen(aPts) + pathLen(bPts);
            if (score < bestScore) {
              bestScore = score;
              best = c;
              bestA = aPts;
              bestB = bPts;
              bestDest = d;
            }
          }
        }
        if (best == null) {
          debugPrint("⚠️ Could not compute a valid connector path.");
          return;
        }

        if (bestDest != null) {
          effectiveDest = bestDest;
          _destPosBlender = bestDest;
        }

        _chosenConnectorId = '${best.type}:${best.id}';
        debugPrint(
          '✅ chosen connector pref=$pref -> $_chosenConnectorId score=${bestScore.toStringAsFixed(2)}',
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

      if (_pathPointsByFloorGltf.isNotEmpty) {
        final rawDist = _calculateTotalDistance();
        final totalDist = rawDist * _unitToMeters;
        _estimatedDistance = '${totalDist.toStringAsFixed(0)} m';
        final timeSeconds = totalDist / 1.4;
        if (timeSeconds < 50) {
          _estimatedTime = 'Less than 1 min';
        } else {
          final minutes = (timeSeconds / 60).ceil();
          _estimatedTime = '$minutes min';
        }
      } else {
        _estimatedDistance = '? m';
        _estimatedTime = '? min';
      }
      if (mounted) setState(() {});
      _syncOverlaysForCurrentFloor();
    } finally {
      if (mounted)
        setState(() {
          _isCalculating = false;
        });
    }
  }

  void _handlePoiMessage(String raw) {
    try {
      final obj = jsonDecode(raw);
      if (obj is Map && obj['type'] == 'path_viewer_ready') {
        _jsReady = true;
        debugPrint("🟦 POI_CHANNEL: path_viewer_ready");
        _syncOverlaysForCurrentFloor();
        return;
      }
    } catch (_) {}
  }

  void _handlePathChannelMessage(String message) {
    debugPrint('PATH_CHANNEL: $message');
  }

  static const String _pathViewerJs =
      r'''console.log("✅ PathViewer JS injected");
postToTest("✅ PathViewer JS top-level executed");
function postToPOI(obj) {
  try { POI_CHANNEL.postMessage(JSON.stringify(obj)); return true; } catch (e) { return false; }
}
function postToTest(msg) {
  try { JS_TEST_CHANNEL.postMessage(msg); return true; } catch (e) { return false; }
}
function getViewer() { return document.querySelector('model-viewer'); }
window.onerror = function(msg, url, line, col, error) {
  postToTest("❌ JS Error: " + msg + " at " + line + ":" + col);
  return true;
};
window.testDestPin = function() { postToTest("✅ testDestPin called"); }
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

  if (hs.parentElement) {
    hs.parentElement.removeChild(hs);
    viewer.appendChild(hs);
  }

  hs.setAttribute('data-position', `${pos.x} ${pos.y} ${pos.z}`);
  hs.setAttribute('data-normal', `0 1 0`);
  viewer.requestUpdate();
}

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

window.__pendingDestPin = null;

function ensureDestPinStyle() {
  if (document.getElementById("dest_pin_hotspot_style")) return;
  const style = document.createElement("style");
  style.id = "dest_pin_hotspot_style";
  style.textContent = `
    .destPinHotspot{
      pointer-events:none;
      position:absolute;
      left:0; top:0;
      width:1px; height:1px;
      transform: translate3d(var(--hotspot-x), var(--hotspot-y), 0px);
      will-change: transform;
      z-index: 1001;
      opacity: var(--hotspot-visibility);
    }
  `;
  document.head.appendChild(style);
}

function buildDestPinUI(el) {
  if (el.__destPinBuilt) return;
  el.__destPinBuilt = true;
  var wrap = document.createElement("div");
  wrap.style.position = "absolute";
  wrap.style.left = "0";
  wrap.style.top = "0";
  wrap.style.transform = "translate(-50%, -92%)";
  wrap.style.pointerEvents = "none";
  var pin = document.createElement("div");
  pin.style.width = "24px";
  pin.style.height = "24px";
  pin.style.background = "#C88D52";   // <-- changed to match destination field
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

function ensureDestPinHotspot(viewer) {
  ensureDestPinStyle();
  let hs = viewer.querySelector('#destPinHotspot');
  if (!hs) {
    hs = document.createElement('div');
    hs.id = 'destPinHotspot';
    hs.slot = 'hotspot-destpin';
    hs.className = 'destPinHotspot';
    viewer.appendChild(hs);
  }
  buildDestPinUI(hs);
  return hs;
}

function setDestPin(viewer, pos) {
  try {
    const hs = ensureDestPinHotspot(viewer);
    if (hs.parentElement) {
      hs.parentElement.removeChild(hs);
      viewer.appendChild(hs);
    }
    hs.setAttribute('data-position', `${pos.x} ${pos.y} ${pos.z}`);
    hs.setAttribute('data-normal', `0 1 0`);
    viewer.requestUpdate();
  } catch(e) {
    postToTest("❌ setDestPin error: " + e);
  }
}

window.clearDestPinFromFlutter = function() {
  const viewer = getViewer();
  if (!viewer) return;
  try {
    const pin = viewer.querySelector('[slot="hotspot-destpin"]');
    if (pin) pin.remove();
    viewer.requestUpdate();
    postToTest("🧹 clearDestPinFromFlutter");
  } catch(e) {}
};

window.__pendingDestPin = null;

window.setDestPinFromFlutter = function(x, y, z) {
  const viewer = getViewer();
  const p = { x: Number(x), y: Number(y), z: Number(z) };

  if (!viewer || !viewer.model) {
    window.__pendingDestPin = p;
    postToTest("⏳ setDestPinFromFlutter pending (viewer/model not ready)");
    return false;
  }

  setDestPin(viewer, p);
  window.__pendingDestPin = null;
  postToTest("✅ setDestPinFromFlutter applied");
  return true;
};

window.__poiOriginals = window.__poiOriginals || {};
window.__highlightedPoi = null;
window.__pendingUserPin = null;
window.__pendingPoiHighlight = null;
window.__poiMatByNorm = window.__poiMatByNorm || {};

function _normPoiName(s) {
  let n = String(s || "");
  n = n.trim().toLowerCase();
  n = n.replace(/\.[0-9]+$/g, "");
  n = n.replace(/[^a-z0-9]+/g, "");
  if (n.startsWith("poimat")) n = n.substring(6);
  return "poimat_" + n;
}

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

      if (name.startsWith("POIMAT_")) {
        const nn = _normPoiKey(name);
        window.__poiMatByNorm[nn] = m;
      }

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

  if (!window.__poiMatByNorm || !window.__poiOriginals) {
    window.__poiMatByNorm = window.__poiMatByNorm || {};
    window.__poiOriginals = window.__poiOriginals || {};
  }

  cacheOriginalPoiMaterials(viewer);

  let mat = window.__poiMatByNorm[wantNorm] || null;
  if (!mat) {
    mat = viewer.model.materials.find(m => _normPoiName(_matName(m)) === wantNorm) || null;
    if (mat) window.__poiMatByNorm[wantNorm] = mat;
  }
  if (!mat) return false;

  const actualName = _matName(mat);

  if (window.__highlightedPoi && window.__highlightedPoi !== actualName) {
    _restorePoi(viewer, window.__highlightedPoi);
  }

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

window.clearPoiHighlightFromFlutter = function() {
  const viewer = getViewer();
  if (!viewer) return;
  if (window.__highlightedPoi) {
    _restorePoi(viewer, window.__highlightedPoi);
    window.__highlightedPoi = null;
  }
  window.__pendingPoiHighlight = null;
  viewer.requestUpdate();
  postToTest("🧹 clearPoiHighlightFromFlutter");
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

    if (window.__pendingDestPin) {
  setDestPin(viewer, window.__pendingDestPin);
  postToTest("✅ applied pending dest pin on load");
  window.__pendingDestPin = null;
}
  });

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
      if (window.__pendingDestPin) {
        setDestPin(viewer, window.__pendingDestPin);
        postToTest("✅ applied pending dest pin (immediate)");
        window.__pendingDestPin = null;
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

    if (widget.floorSrc.trim().isNotEmpty) {
      _currentFloor = widget.floorSrc.trim();
    }

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
      _pendingPoiToHighlight = widget.shopId.trim();
    } else {
      _pendingPoiToHighlight = null;
    }

    _boot();
  }

  bool _booting = false;
  String? _pendingFloorLabelToOpen;

  Future<void> _boot() async {
    _booting = true;
    try {
      await _loadVenueMaps();
      await _loadEntrances();
      await _loadActiveRequests();
      await _resolveDestinationFromEntrances(); // sets _selectedDestPoi and _destPosBlender
      _refreshArSupport();
      await _loadUserBlenderPosition();

      // No need to set _selectedDestPoi again here; entrances already set it.
      // If there's a case where entrances didn't find it, fallback to a default.
      if (_selectedDestPoi == null && _destPosBlender != null) {
        // Fallback for destinations not in entrances (custom pin, etc.)
        _selectedDestPoi = {
          'name': widget.shopName,
          'type': 'poi',
          'floor': _destFloorLabel ?? '',
          'x': _destPosBlender!['x'],
          'y': _destPosBlender!['y'],
          'z': _destPosBlender!['z'],
          'material': _pendingPoiToHighlight ?? '',
        };
        _refreshArSupport();
      }

      final serviceDest = _findServiceDestinationOption(widget.shopId);
      if (serviceDest != null) {
        _selectedDestPoi = serviceDest;
        _pendingPoiToHighlight = serviceDest['material']?.toString();
        _refreshArSupport();
      }

      final target = (_desiredStartFloorLabel.isNotEmpty)
          ? _desiredStartFloorLabel
          : (_pendingFloorLabelToOpen ?? '');
      if (target.isNotEmpty) {
        await _ensureFloorSelected(target);
      }
    } finally {
      _booting = false;
    }

    await _maybeComputeAndPushPath();
    await _syncOverlaysForCurrentFloor();
  }

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

      final xNum = bp['x'];
      final yNum = bp['y'];
      final zNum = bp['z'];
      if (xNum is num && yNum is num && zNum is num) {
        _userPosBlender = {
          'x': xNum.toDouble(),
          'y': yNum.toDouble(),
          'z': zNum.toDouble(),
        };
        _pendingUserPinGltf = {
          'x': xNum.toDouble(),
          'y': zNum.toDouble(),
          'z': (-yNum.toDouble()),
        };

        if (_jsReady && _pendingUserPinGltf != null) {
          _pushUserPinToJsPath(_pendingUserPinGltf!);
        }
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
  Future<bool> _hasWorldPosition(String placeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('places')
          .doc(placeId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      return data.containsKey('worldPosition') && data['worldPosition'] != null;
    } catch (e) {
      debugPrint("Error checking world position: $e");
      return false;
    }
  }

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

  Future<void> _openNavigationAR() async {
    if (_destPosBlender == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Destination not ready.')));
      }
      return;
    }

    final destFloor = _destFNumberFixed ?? _toFNumber(_destFloorLabel ?? '');
    if (destFloor.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Destination floor unknown.')),
        );
      }
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        openAppSettings();
      }
      return;
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UnityCameraPage(
          isFriendNavigation: true,
          friendX: _destPosBlender!['x']!,
          friendY: _destPosBlender!['y']!,
          friendZ: _destPosBlender!['z']!,
          friendFloor: destFloor,
          friendName: _selectedDestPoi?['name'] ?? widget.shopName,
        ),
      ),
    );
  }

  Future<void> _loadVenueMaps() async {
    setState(() => _mapsLoading = true);

    if (widget.venueMaps != null && widget.venueMaps!.isNotEmpty) {
      final List<Map<String, String>> convertedMaps = widget.venueMaps!
          .map((m) => Map<String, String>.from(m))
          .toList();
      if (mounted) {
        setState(() {
          _venueMaps = convertedMaps;
          _floorLabelByFNumber.clear();
          for (final m in _venueMaps) {
            final f = (m["F_number"]?.toString() ?? "");
            final lbl = (m["floorNumber"]?.toString() ?? "");
            if (f.isNotEmpty && lbl.isNotEmpty) _floorLabelByFNumber[f] = lbl;
          }
          _currentFloor = widget.floorSrc;
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
            'floorNumber': (map['floorNumber'] ?? '').toString(),
            'F_number': (map['F_number'] ?? '').toString(),
            'mapURL': (map['mapURL'] ?? '').toString(),
            'navmesh': (map['navmesh'] ?? '').toString(),
            'poiJsonPath':
                (map['poiJsonPath'] ?? map['poi_json'] ?? map['poiJson'] ?? '')
                    .toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            _floorLabelByFNumber.clear();
            for (final m in _venueMaps) {
              final f = (m["F_number"]?.toString() ?? "");
              final lbl = (m["floorNumber"]?.toString() ?? "");
              if (f.isNotEmpty && lbl.isNotEmpty) _floorLabelByFNumber[f] = lbl;
            }
            if (convertedMaps.isNotEmpty) {
              _currentFloor = convertedMaps.first['mapURL'] ?? '';

              if (_requestedFloorIsUrl && _requestedFloorToken.isNotEmpty) {
                final exists = convertedMaps.any(
                  (m) => (m['mapURL'] ?? '') == _requestedFloorToken,
                );
                if (exists) _currentFloor = _requestedFloorToken;
              }

              if (!_requestedFloorIsUrl && _requestedFloorToken.isNotEmpty) {
                final match = convertedMaps.firstWhere(
                  (m) => (m['floorNumber'] ?? '') == _requestedFloorToken,
                  orElse: () => const {'mapURL': ''},
                );
                var url = match['mapURL'] ?? '';

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

              if (_desiredStartFloorLabel.isNotEmpty) {
                final savedF = _toFNumber(_desiredStartFloorLabel);
                final match = convertedMaps.firstWhere(
                  (m) => (m['F_number'] ?? '') == savedF,
                  orElse: () => const {'mapURL': ''},
                );
                final url = match['mapURL'] ?? '';
                if (url.isNotEmpty) _currentFloor = url;
              }
            }
          });

          _ensureConnectorsLoaded();

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

    final startLabel = _desiredStartFloorLabel.isNotEmpty
        ? _desiredStartFloorLabel
        : _originFloorLabel;
    final destLabel =
        (_destFloorLabelFixed ??
                _destFloorLabel ??
                widget.destinationFloorLabel ??
                '')
            .trim();

    if (startLabel.isEmpty || destLabel.isEmpty) return true;

    final startFStr = _toFNumber(startLabel);
    final destFStr = _toFNumber(destLabel);

    if (startFStr.isEmpty || destFStr.isEmpty) return true;
    if (startFStr == destFStr) return false;

    final startF = int.tryParse(startFStr);
    final destF = int.tryParse(destFStr);
    if (startF == null || destF == null) return true;

    for (final c in _connectors) {
      final normType = _normalizeConnectorType(c.type);
      if (!_connectorMatchesPreference(normType, p)) continue;
      if (!_connectorDirectionAllowed(normType, startF, destF)) continue;
      final keys = c.endpointsByFNumber.keys.map((k) => k.toString()).toSet();
      if (keys.contains(startFStr) && keys.contains(destFStr)) return true;
    }
    return false;
  }

  Future<void> _changePreference(String preference) async {
    final String nextPreference = (_selectedPreference == preference)
        ? 'any'
        : preference;

    debugPrint('🎛️ changePreference: $_selectedPreference -> $nextPreference');

    setState(() {
      _selectedPreference = nextPreference;
    });

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

  Future<void> _showStartPicker() async {
    if (!_entrancesLoaded) {
      await _loadEntrances();
      if (!_entrancesLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entrance data not loaded yet.')),
        );
        return;
      }
    }

    final allPois = _getAllPoisFromEntrances();

    // Determine the currently selected start point (if any)
    Map<String, dynamic>? currentStartPoi;
    if (_usePinAsStart && _userPosBlender != null) {
      currentStartPoi = {
        'name': 'Your location',
        'floor': _originFloorLabel,
        'x': _userPosBlender!['x'],
        'y': _userPosBlender!['y'],
        'z': _userPosBlender!['z'],
      };
    } else if (_customStartPoi != null) {
      currentStartPoi = _customStartPoi;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PoiPickerSheet(
        pois: allPois,
        title: 'Select start point',
        showPinPlacement: true,
        selectedPoi: currentStartPoi, // ← pass current selection
      ),
    );

    if (result == null) return;

    if (result['type'] == 'pin_placement') {
      final pinResult = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SetYourLocationDialog(
          shopName: widget.shopName,
          shopId: widget.shopId,
          destinationPoiMaterial: widget.destinationPoiMaterial,
          floorSrc: _currentFloor,
          destinationHitGltf: widget.destinationHitGltf,
          destinationFloorLabel: widget.destinationFloorLabel,
          returnResultOnly: true,
          flowType: 'start',
        ),
      );

      if (pinResult != null) {
        final rawFloor = pinResult['floorLabel'];
        final displayFloor = _floorLabelFromToken(rawFloor) ?? rawFloor;

        setState(() {
          _usePinAsStart = false;
          _customStartPoi = {
            'name': 'Your location',
            'type': 'poi',
            'floor': displayFloor,
            'x': pinResult['blender']['x'],
            'y': pinResult['blender']['y'],
            'z': pinResult['blender']['z'],
            'material': null,
          };
          _desiredStartFloorLabel = displayFloor;
          _originFloorLabelFixed = null;
          _originFNumberFixed = null;
          _selectedPreference = 'any';
        });
        _refreshArSupport();

        final blender = pinResult['blender'];
        _pendingUserPinGltf = {
          'x': blender['x'].toDouble(),
          'y': blender['z'].toDouble(),
          'z': -blender['y'].toDouble(),
        };
        _routeComputed = false;
        _pathPointsByFloorGltf.clear();
        _maybeComputeAndPushPath();
        _ensureFloorSelected(_desiredStartFloorLabel);
      }
      return;
    }

    // Normal POI selection
    setState(() {
      _usePinAsStart = false;
      _customStartPoi = result;
      final displayFloor =
          _floorLabelFromToken(result['floor']) ?? result['floor'];
      _desiredStartFloorLabel = displayFloor;
      _originFloorLabelFixed = null;
      _originFNumberFixed = null;
      _selectedPreference = 'any';
    });
    _pendingUserPinGltf = {
      'x': result['x'],
      'y': result['z'],
      'z': -result['y'],
    };
    _routeComputed = false;
    _pathPointsByFloorGltf.clear();
    _maybeComputeAndPushPath();
    _ensureFloorSelected(_desiredStartFloorLabel);
  }

  Future<void> _showDestPicker() async {
    if (!_entrancesLoaded) {
      await _loadEntrances();
      if (!_entrancesLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entrance data not loaded yet.')),
        );
        return;
      }
    }

    final allPois = _getAllPoisFromEntrances();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PoiPickerSheet(
        pois: allPois,
        title: 'Select destination',
        showPinPlacement: true,
        activeRequests: _activeRequests,
        selectedPoi: _selectedDestPoi,
      ),
    );

    if (result == null) return;

    // --- Handle pin placement ---
    if (result['type'] == 'pin_placement') {
      final pinResult = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SetYourLocationDialog(
          shopName: widget.shopName,
          shopId: widget.shopId,
          destinationPoiMaterial: widget.destinationPoiMaterial,
          floorSrc: _currentFloor,
          destinationHitGltf: widget.destinationHitGltf,
          destinationFloorLabel: widget.destinationFloorLabel,
          returnResultOnly: true,
          flowType: 'destination',
        ),
      );

      if (pinResult != null) {
        final rawFloor = pinResult['floorLabel'];
        final displayFloor = _floorLabelFromToken(rawFloor) ?? rawFloor;

        setState(() {
          _selectedDestPoi = {
            'name': 'Selected location',
            'type': 'poi',
            'floor': displayFloor,
            'x': pinResult['blender']['x'],
            'y': pinResult['blender']['y'],
            'z': pinResult['blender']['z'],
            'material': null,
          };
          _destFloorLabel = displayFloor;
          _destPosBlender = {
            'x': pinResult['blender']['x'],
            'y': pinResult['blender']['y'],
            'z': pinResult['blender']['z'],
          };
          _pendingPoiToHighlight = null;
          _destFloorLabelFixed = null;
          _destFNumberFixed = null;
          _selectedPreference = 'any';
          _destEntrances = null;
        });

        _routeComputed = false;
        _pathPointsByFloorGltf.clear();
        _maybeComputeAndPushPath();
        if (_originFloorLabelFixed == _destFloorLabel) {
          _ensureFloorSelected(_destFloorLabel!);
        }
      }
      return;
    }
    // --- Handle active request ---
    else if (result['type'] == 'active_request') {
      setState(() {
        _selectedDestPoi = {
          'name': result['name'],
          'type': 'poi',
          'floor': result['floor'],
          'x': result['x'],
          'y': result['y'],
          'z': result['z'],
          'material': null,
        };
        _destFloorLabel = result['floor'];
        _destPosBlender = {
          'x': result['x'],
          'y': result['y'],
          'z': result['z'],
        };
        _pendingPoiToHighlight = null;
        _destFloorLabelFixed = null;
        _destFNumberFixed = null;
        _selectedPreference = 'any';
        _destEntrances = null;
      });
      _refreshArSupport();

      _routeComputed = false;
      _pathPointsByFloorGltf.clear();
      _maybeComputeAndPushPath();
      if (_originFloorLabelFixed == _destFloorLabel) {
        _ensureFloorSelected(_destFloorLabel!);
      }
      return;
    }
    // --- Normal POI selection ---
    else {
      setState(() {
        _selectedDestPoi = result;
        _destFloorLabel = result['floor'];
        _destPosBlender = {
          'x': result['x'],
          'y': result['y'],
          'z': result['z'],
        };
        _pendingPoiToHighlight = result['material'];
        _destFloorLabelFixed = null;
        _destFNumberFixed = null;
        _selectedPreference = 'any';
      });
      _refreshArSupport();

      final normName = _normPoiKey(result['material']);
      if (_entrancesByPoi.containsKey(normName)) {
        _destEntrances = _entrancesByPoi[normName]!;
      } else {
        _destEntrances = null;
      }

      _routeComputed = false;
      _pathPointsByFloorGltf.clear();
      _maybeComputeAndPushPath();
      if (_originFloorLabelFixed == _destFloorLabel) {
        _ensureFloorSelected(_destFloorLabel!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        _pathPushed = false;
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
                            if (!_jsReady &&
                                msg.message.contains('PathViewer JS alive')) {
                              _jsReady = true;

                              final pin = _pendingUserPinGltf;
                              if (pin != null) {
                                _pushUserPinToJsPath(pin);
                              }
                              _pushDestinationHighlightToJsPath();

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

            Positioned(
              top: 220,
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

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(10, 20, 20, 16),
                child: Column(
                  children: [
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
                              GestureDetector(
                                onTap: _showStartPicker,
                                child: _locationRow(
                                  Icons.radio_button_checked,
                                  _usePinAsStart
                                      ? 'Your location'
                                      : (_customStartPoi?['name'] ?? ''),
                                  _usePinAsStart
                                      ? (_floorLabelFromToken(
                                              _originFloorLabel,
                                            ) ??
                                            _originFloorLabel)
                                      : (_customStartPoi?['floor'] != null
                                            ? (_floorLabelFromToken(
                                                    _customStartPoi!['floor'],
                                                  ) ??
                                                  _customStartPoi!['floor'])
                                            : ''),
                                  const Color(0xFF6C6C6C),
                                ),
                              ),
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
                              GestureDetector(
                                onTap: _showDestPicker,
                                child: _locationRow(
                                  Icons.location_on,
                                  _selectedDestPoi?['name'] ?? widget.shopName,
                                  _selectedDestPoi?['floor'] != null
                                      ? (_floorLabelFromToken(
                                              _selectedDestPoi!['floor'],
                                            ) ??
                                            _selectedDestPoi!['floor'])
                                      : (_destFloorLabel != null
                                            ? (_floorLabelFromToken(
                                                    _destFloorLabel,
                                                  ) ??
                                                  _destFloorLabel)
                                            : '--'),
                                  const Color(0xFFC88D52),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isCalculating)
                              const Text(
                                'Calculating…',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              )
                            else if (_routeComputed &&
                                _estimatedTime.isNotEmpty &&
                                _estimatedDistance.isNotEmpty)
                              Text(
                                '$_estimatedTime ($_estimatedDistance)',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              )
                            else
                              const Text(
                                '',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedDestPoi?['name'] ?? widget.shopName,
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
                    Divider(color: Colors.grey[300], thickness: 1, height: 1),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      text: 'Start AR Navigation',
                      enabled: _arSupported,
                      onPressed: _arSupported ? _openNavigationAR : null,
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

  Widget _preferenceButtonHorizontal(
    String label,
    IconData icon,
    String value, {
    bool enabled = true,
  }) {
    final bool isSelected = _selectedPreference == value;
    final bool isDisabled = !enabled;
    final bool showAsSelected = isSelected && !isDisabled;

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isDisabled ? null : () => _changePreference(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: showAsSelected ? const Color(0xFFE8E9E0) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: showAsSelected
                  ? AppColors.kGreen.withOpacity(0.30)
                  : const Color(0x00000000),
              width: 1.2,
            ),
            boxShadow: showAsSelected
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
                    : (showAsSelected ? AppColors.kGreen : Colors.grey[500]),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDisabled
                      ? Colors.grey[400]
                      : (showAsSelected ? AppColors.kGreen : Colors.grey[600]),
                  fontWeight: showAsSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
// POI Picker Sheet
// ============================================================================

class _PoiPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> pois;
  final String title;
  final bool showPinPlacement;
  final List<Map<String, dynamic>> activeRequests;
  final Map<String, dynamic>? selectedPoi;

  const _PoiPickerSheet({
    required this.pois,
    required this.title,
    this.showPinPlacement = true,
    this.activeRequests = const [],
    this.selectedPoi,
  });

  @override
  __PoiPickerSheetState createState() => __PoiPickerSheetState();
}

class __PoiPickerSheetState extends State<_PoiPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.pois;
    _searchController.addListener(_filter);
  }

  void _filter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = widget.pois.where((p) {
        final name = (p['name'] ?? '').toString().trim().toLowerCase();
        return name.contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSelected(Map<String, dynamic> item) {
    final selected = widget.selectedPoi;
    if (selected == null) return false;

    final itemName = (item['name'] ?? '').toString().trim().toLowerCase();
    final selectedName = (selected['name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    return itemName.isNotEmpty && itemName == selectedName;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: CustomScrollView(
        slivers: [
          // Fixed header section
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.grey.shade600,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    cursorColor: AppColors.kGreen,
                  ),
                ),
                if (widget.showPinPlacement) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () =>
                            Navigator.pop(context, {'type': 'pin_placement'}),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.kGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.kGreen.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: AppColors.kGreen,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Pin on Map',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.kGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(color: Colors.grey[300], thickness: 1),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Active requests section (if any)
          if (widget.activeRequests.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Active Tracked Users',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final req = widget.activeRequests[index];
                final isSelected = _isSelected(req);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  leading: Icon(
                    Icons.person_outline,
                    color: Colors.grey[600],
                    size: 24,
                  ),
                  title: Text(
                    req['name'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Floor: ${req['floor']}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  onTap: () => Navigator.pop(context, {
                    'type': 'active_request',
                    'name': req['name'],
                    'floor': req['floor'],
                    'x': req['x'],
                    'y': req['y'],
                    'z': req['z'],
                  }),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: AppColors.kGreen)
                      : null,
                );
              }, childCount: widget.activeRequests.length),
            ),
            // Add a separator after active requests
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: Colors.grey[300], thickness: 1),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],

          // POI list
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final poi = _filtered[index];
              final isSelected = _isSelected(poi);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                leading: () {
                  List<String> cats = (poi['categories'] is List)
                      ? List<String>.from(poi['categories'])
                      : const <String>[];
                  // If empty, fall back to the single category field
                  if (cats.isEmpty && poi['category'] != null) {
                    cats = [poi['category'].toString()];
                  }

                  final primaryCat = cats.isNotEmpty
                      ? cats.first.toLowerCase()
                      : '';

                  IconData icon;
                  if (primaryCat.contains('restaurant')) {
                    icon = Icons.restaurant;
                  } else if (primaryCat.contains('café')) {
                    icon = Icons.local_cafe;
                  } else if (primaryCat.contains('shop')) {
                    icon = Icons.store;
                  } else if (primaryCat == 'gates') {
                    icon = Icons.door_front_door;
                  } else if (primaryCat == 'bathrooms') {
                    final gender = poi['gender']?.toString().toLowerCase();
                    if (gender == 'female') {
                      icon = Icons.woman;
                    } else if (gender == 'male') {
                      icon = Icons.man;
                    } else {
                      icon = Icons.wc;
                    }
                  } else if (primaryCat == 'prayer_rooms') {
                    icon = Icons.mosque;
                  } else {
                    icon = Icons.store;
                  }
                  return Icon(icon, color: Colors.grey[600], size: 24);
                }(),
                title: Text(
                  poi['name'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                subtitle: Text(() {
                  final category = poi['category']?.toString().toLowerCase();
                  if (category == 'gates') {
                    return poi['description']?.toString() ?? 'Gate';
                  } else if (category == 'bathrooms' ||
                      category == 'prayer_rooms') {
                    return 'Closest to you';
                  } else {
                    return 'Floor: ${poi['floor']}';
                  }
                }(), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                onTap: () => Navigator.pop(context, poi),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: AppColors.kGreen)
                    : null,
              );
            }, childCount: _filtered.length),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }
}
