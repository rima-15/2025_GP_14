import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:madar_app/nav/navmesh.dart';

class ConnectorLink {
  final String id;
  final String type;
  final Map<String, Map<String, double>> endpointsByFNumber;

  const ConnectorLink({
    required this.id,
    required this.type,
    required this.endpointsByFNumber,
  });
}

class PathComputationResult {
  final Map<String, List<Map<String, double>>> pathPointsByFloorGltf;
  final String? chosenConnectorId;
  final Map<String, double>? connectorStartBlender;
  final Map<String, double>? connectorDestBlender;
  final Map<String, double> effectiveDestination;

  const PathComputationResult({
    required this.pathPointsByFloorGltf,
    required this.effectiveDestination,
    this.chosenConnectorId,
    this.connectorStartBlender,
    this.connectorDestBlender,
  });
}

typedef EnsureNavmeshLoaded = Future<NavMesh?> Function(String fNumber);
typedef FloorNormalizer = String Function(String? raw);
typedef ConnectorTypeNormalizer = String Function(String raw);
typedef ConnectorDirectionAllowed = bool Function(String normType, int fromFloor, int toFloor);
typedef ConnectorPreferenceMatcher = bool Function(String normType, String preference);

class PathCalculator {
  static Future<PathComputationResult?> computeRoute({
    required Map<String, double> start,
    required Map<String, double> destination,
    required String startFloorLabel,
    required String destinationFloorLabel,
    required String selectedPreference,
    required List<ConnectorLink> connectors,
    required EnsureNavmeshLoaded ensureNavmeshLoadedForFNumber,
    required FloorNormalizer toFNumber,
    required ConnectorTypeNormalizer normalizeConnectorType,
    required ConnectorDirectionAllowed connectorDirectionAllowed,
    required ConnectorPreferenceMatcher connectorMatchesPreference,
  }) async {
    final startF = toFNumber(startFloorLabel);
    final destF = toFNumber(destinationFloorLabel);

    final startNm = await ensureNavmeshLoadedForFNumber(startF);
    final destNm = await ensureNavmeshLoadedForFNumber(destF);
    if (startNm == null || destNm == null) return null;

    List<List<double>> computePathOn(
      NavMesh nm,
      Map<String, double> aBl,
      Map<String, double> bBl,
    ) {
      final a = nm.snapPointXY([aBl['x']!, aBl['y']!, aBl['z']!]);
      final b = [bBl['x']!, bBl['y']!, bBl['z']!];
      var raw = nm.findPathFunnelBlenderXY(start: a, goal: b);
      var sm = _smoothAndResamplePath(raw);
      if (sm.length < 2) {
        raw = [a, b];
        sm = _smoothAndResamplePath(raw);
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
      final pts = computePathOn(startNm, start, destination);
      final gltf = pts
          .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
          .toList();
      return PathComputationResult(
        pathPointsByFloorGltf: {startF: gltf},
        effectiveDestination: destination,
      );
    }

    final pref = selectedPreference.toLowerCase();

    bool linksFloors(ConnectorLink c) =>
        c.endpointsByFNumber.containsKey(startF) &&
        c.endpointsByFNumber.containsKey(destF);

    bool directionOk(ConnectorLink c) {
      final t = normalizeConnectorType(c.type);
      return connectorDirectionAllowed(
        t,
        int.tryParse(startF) ?? 1,
        int.tryParse(destF) ?? 1,
      );
    }

    bool matchesPref(ConnectorLink c) {
      final t = normalizeConnectorType(c.type);
      return directionOk(c) && connectorMatchesPreference(t, pref);
    }

    final candidates = connectors.where((c) => linksFloors(c) && matchesPref(c)).toList();
    final pool = candidates.isNotEmpty
        ? candidates
        : connectors.where((c) => linksFloors(c) && directionOk(c)).toList();

    debugPrint('🧭 pref=$pref start=$startFloorLabel($startF) dest=$destinationFloorLabel($destF) matched=${candidates.length} pool=${pool.length}');
    if (pool.isEmpty) {
      debugPrint('⚠️ No connectors found linking $startFloorLabel -> $destinationFloorLabel');
      return null;
    }

    double bestScore = double.infinity;
    ConnectorLink? best;
    List<List<double>> bestA = const [];
    List<List<double>> bestB = const [];

    for (final c in pool) {
      final aPos = c.endpointsByFNumber[startF]!;
      final bPos = c.endpointsByFNumber[destF]!;
      final aPts = computePathOn(startNm, start, aPos);
      if (aPts.length < 2) continue;

      final bPts = computePathOn(destNm, bPos, destination);
      if (bPts.length < 2) continue;

      final score = pathLen(aPts) + pathLen(bPts);
      if (score < bestScore) {
        bestScore = score;
        best = c;
        bestA = aPts;
        bestB = bPts;
      }
    }

    if (best == null) {
      debugPrint('⚠️ Could not compute a valid connector path.');
      return null;
    }

    final gltfA = bestA
        .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
        .toList();
    final gltfB = bestB
        .map((p) => _blenderToGltf({'x': p[0], 'y': p[1], 'z': p[2]}))
        .toList();

    return PathComputationResult(
      pathPointsByFloorGltf: {startF: gltfA, destF: gltfB},
      chosenConnectorId: '${best.type}:${best.id}',
      connectorStartBlender: best.endpointsByFNumber[startF],
      connectorDestBlender: best.endpointsByFNumber[destF],
      effectiveDestination: destination,
    );
  }

  static List<List<double>> _smoothAndResamplePath(List<List<double>> path) {
    var pts = _resampleByDistance(path, step: 0.06);
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

  static List<List<double>> _resampleByDistance(List<List<double>> pts, {required double step}) {
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

  static double _distXY(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  static bool _samePoint(List<double> a, List<double> b) {
    return (a[0] - b[0]).abs() < 1e-6 &&
        (a[1] - b[1]).abs() < 1e-6 &&
        (a[2] - b[2]).abs() < 1e-6;
  }

  static Map<String, double> _blenderToGltf(Map<String, double> b) {
    final xb = b['x'] ?? 0.0;
    final yb = b['y'] ?? 0.0;
    final zb = b['z'] ?? 0.0;
    return {'x': xb, 'y': zb, 'z': -yb};
  }
}
