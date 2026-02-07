import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;

class NavMesh {
  final List<List<double>> v;     // vertices [ [x,y,z], ... ]  (Blender space)
  final List<List<int>> t;        // triangles [ [a,b,c], ... ]
  final List<List<int>> n;        // neighbors [ [triIdx...], ... ]

  NavMesh(this.v, this.t, this.n);

  static Future<NavMesh> loadAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final obj = jsonDecode(raw) as Map<String, dynamic>;
    final verts = (obj['vertices'] as List).map((e) => (e as List).map((x) => (x as num).toDouble()).toList()).toList();
    final tris  = (obj['triangles'] as List).map((e) => (e as List).map((x) => (x as num).toInt()).toList()).toList();
    final neigh = (obj['neighbors'] as List).map((e) => (e as List).map((x) => (x as num).toInt()).toList()).toList();
    return NavMesh(verts, tris, neigh);
  }

  // Closest point on a triangle in XY (treat Z as height)
  static List<double> _closestPointOnTriXY(
    List<double> p, List<double> a, List<double> b, List<double> c,
  ) {
    // Work in 2D: (x,y). Keep z from triangle plane (we'll use a.z averaged)
    final px = p[0], py = p[1];
    final ax = a[0], ay = a[1];
    final bx = b[0], by = b[1];
    final cx = c[0], cy = c[1];

    // Barycentric / closest point on triangle in 2D (Ericson-style)
    double dot2(double ux, double uy, double vx, double vy) => ux*vx + uy*vy;

    final abx = bx-ax, aby = by-ay;
    final acx = cx-ax, acy = cy-ay;
    final apx = px-ax, apy = py-ay;

    final d1 = dot2(abx,aby, apx,apy);
    final d2 = dot2(acx,acy, apx,apy);
    if (d1 <= 0 && d2 <= 0) return [ax, ay, a[2]];

    final bpx = px-bx, bpy = py-by;
    final d3 = dot2(abx,aby, bpx,bpy);
    final d4 = dot2(acx,acy, bpx,bpy);
    if (d3 >= 0 && d4 <= d3) return [bx, by, b[2]];

    final vc = d1*d4 - d3*d2;
    if (vc <= 0 && d1 >= 0 && d3 <= 0) {
      final v = d1 / (d1 - d3);
      return [ax + v*abx, ay + v*aby, a[2] + v*(b[2]-a[2])];
    }

    final cpx = px-cx, cpy = py-cy;
    final d5 = dot2(abx,aby, cpx,cpy);
    final d6 = dot2(acx,acy, cpx,cpy);
    if (d6 >= 0 && d5 <= d6) return [cx, cy, c[2]];

    final vb = d5*d2 - d1*d6;
    if (vb <= 0 && d2 >= 0 && d6 <= 0) {
      final w = d2 / (d2 - d6);
      return [ax + w*acx, ay + w*acy, a[2] + w*(c[2]-a[2])];
    }

    final va = d3*d6 - d5*d4;
    if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
      final w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
      return [bx + w*(cx-bx), by + w*(cy-by), b[2] + w*(c[2]-b[2])];
    }

    // Inside face region
    final denom = 1.0 / (va + vb + vc);
    final v2 = vb * denom;
    final w2 = vc * denom;
    final x = ax + abx*v2 + acx*w2;
    final y = ay + aby*v2 + acy*w2;
    final z = a[2] + (b[2]-a[2])*v2 + (c[2]-a[2])*w2;
    return [x,y,z];
  }

  List<double> snapPointXY(List<double> p) {
    double bestD = double.infinity;
    List<double> best = p;

    for (final tri in t) {
      final a = v[tri[0]];
      final b = v[tri[1]];
      final c = v[tri[2]];
      final q = _closestPointOnTriXY(p, a, b, c);
      final dx = q[0]-p[0], dy = q[1]-p[1];
      final d = dx*dx + dy*dy;
      if (d < bestD) {
        bestD = d;
        best = q;
      }
    }
    return best;
  }
  Map<String,double> snapBlenderPoint(Map<String,double> p) {
  final q = snapPointXY([p['x']!, p['y']!, p['z']!]);
  return {'x': q[0], 'y': q[1], 'z': q[2]};
}

  // ------------------------------------------------------------
  // STEP 2 (Navigation): triangle-graph A* pathfinding
  // ------------------------------------------------------------

  /// Returns the triangle index that contains point [p] (Blender XY plane),
  /// or -1 if none.
  int _findContainingTriXY(List<double> p, {double eps = 1e-9}) {
    final px = p[0], py = p[1];

    bool pointInTri(double px, double py,
        double ax, double ay, double bx, double by, double cx, double cy) {
      // Barycentric test in XY
      final v0x = cx - ax, v0y = cy - ay;
      final v1x = bx - ax, v1y = by - ay;
      final v2x = px - ax, v2y = py - ay;

      final dot00 = v0x * v0x + v0y * v0y;
      final dot01 = v0x * v1x + v0y * v1y;
      final dot02 = v0x * v2x + v0y * v2y;
      final dot11 = v1x * v1x + v1y * v1y;
      final dot12 = v1x * v2x + v1y * v2y;

      final denom = (dot00 * dot11 - dot01 * dot01);
      if (denom.abs() < eps) return false; // degenerate
      final inv = 1.0 / denom;
      final u = (dot11 * dot02 - dot01 * dot12) * inv;
      final vv = (dot00 * dot12 - dot01 * dot02) * inv;

      return u >= -eps && vv >= -eps && (u + vv) <= 1.0 + eps;
    }

    for (int ti = 0; ti < t.length; ti++) {
      final tri = t[ti];
      final a = v[tri[0]];
      final b = v[tri[1]];
      final c = v[tri[2]];
      if (pointInTri(px, py, a[0], a[1], b[0], b[1], c[0], c[1])) return ti;
    }
    return -1;
  }

  /// Finds the nearest triangle to [p] in XY by closest-point distance.
  /// Returns:
  /// - tri: triangle index
  /// - closest: closest point [x,y,z] on that triangle (z interpolated)
  Map<String, dynamic> _findNearestTriXY(List<double> p) {
    int bestTri = -1;
    double bestD2 = double.infinity;
    List<double> bestPt = [p[0], p[1], (p.length > 2) ? p[2] : 0.0];

    final px = p[0], py = p[1];

    for (int ti = 0; ti < t.length; ti++) {
      final tri = t[ti];
      final a = v[tri[0]];
      final b = v[tri[1]];
      final c = v[tri[2]];

      final q = _closestPointOnTriXY([px, py, 0.0], a, b, c);
      final dx = q[0] - px;
      final dy = q[1] - py;
      final d2 = dx * dx + dy * dy;

      if (d2 < bestD2) {
        bestD2 = d2;
        bestTri = ti;
        bestPt = q;
      }
    }

    return {"tri": bestTri, "closest": bestPt, "d2": bestD2};
  }

  List<double> _triCenter(int ti) {
    final tri = t[ti];
    final a = v[tri[0]];
    final b = v[tri[1]];
    final c = v[tri[2]];
    return [
      (a[0] + b[0] + c[0]) / 3.0,
      (a[1] + b[1] + c[1]) / 3.0,
      (a[2] + b[2] + c[2]) / 3.0,
    ];
  }

  double _dist2XY(List<double> p, List<double> q) {
    final dx = p[0] - q[0];
    final dy = p[1] - q[1];
    return dx * dx + dy * dy;
  }

  /// Find a navmesh path between two Blender-space points.
  ///
  /// Returns a polyline (list of [x,y,z]) in Blender coords.
  ///
  /// Implementation (simple & debuggable):
  /// 1) snap start/goal onto the navmesh surface
  /// 2) find start/goal triangles
  /// 3) run A* over triangle adjacency (n[])
  /// 4) build waypoints: start, triangle centers, goal
  List<List<double>> findPathBlenderXY({
    required List<double> start,
    required List<double> goal,
    int maxExpanded = 5000,
  }) {
    // 1) snap to surface
    final sSnap = snapPointXY(start);
    final gSnap = snapPointXY(goal);
    final s = [sSnap[0], sSnap[1], sSnap[2]];
    final g = [gSnap[0], gSnap[1], gSnap[2]];

    // 2) start/goal triangles
    int sTri = _findContainingTriXY(s);
    if (sTri < 0) sTri = (_findNearestTriXY(s)["tri"] as int);

    int gTri = _findContainingTriXY(g);
    if (gTri < 0) gTri = (_findNearestTriXY(g)["tri"] as int);

    if (sTri < 0 || gTri < 0) return [s, g];
    if (sTri == gTri) return [s, g];

    // 3) A* search
    final open = <int>{sTri};
    final cameFrom = <int, int>{};
    final gScore = <int, double>{sTri: 0.0};
    final fScore = <int, double>{};

    final goalCenter = _triCenter(gTri);

    double h(int ti) => sqrt(_dist2XY(_triCenter(ti), goalCenter));

    fScore[sTri] = h(sTri);

    int expanded = 0;

    while (open.isNotEmpty && expanded < maxExpanded) {
      expanded++;

      // pick open with smallest fScore
      int current = -1;
      double bestF = double.infinity;
      for (final tIdx in open) {
        final f = fScore[tIdx] ?? double.infinity;
        if (f < bestF) {
          bestF = f;
          current = tIdx;
        }
      }

      if (current == -1) break;

      if (current == gTri) {
        // reconstruct triangle path
        final triPath = <int>[current];
        while (cameFrom.containsKey(current)) {
          current = cameFrom[current]!;
          triPath.add(current);
        }
        final rev = triPath.reversed.toList();

        // build points: start -> centers -> goal
        final pts = <List<double>>[];
        pts.add(s);
        for (int i = 1; i < rev.length - 1; i++) {
          pts.add(_triCenter(rev[i]));
        }
        pts.add(g);

        return _simplifyPathXY(pts);
      }

      open.remove(current);

      for (final nb in n[current]) {
        if (nb < 0) continue;

        final tentative =
            (gScore[current] ?? double.infinity) +
                sqrt(_dist2XY(_triCenter(current), _triCenter(nb)));

        if (tentative < (gScore[nb] ?? double.infinity)) {
          cameFrom[nb] = current;
          gScore[nb] = tentative;
          fScore[nb] = tentative + h(nb);
          open.add(nb);
        }
      }
    }

    // fallback: direct line
    return [s, g];
  }

  /// Cleanup: remove too-close points + near-collinear points (XY).
  List<List<double>> _simplifyPathXY(
    List<List<double>> pts, {
    double minStep = 0.05,
    double collinearEps = 1e-4,
  }) {
    if (pts.length <= 2) return pts;

    final out = <List<double>>[pts.first];
    for (int i = 1; i < pts.length; i++) {
      final last = out.last;
      final dx = pts[i][0] - last[0];
      final dy = pts[i][1] - last[1];
      if ((dx * dx + dy * dy) >= (minStep * minStep)) {
        out.add(pts[i]);
      }
    }
    if (out.length <= 2) return out;

    final out2 = <List<double>>[out.first];
    for (int i = 1; i < out.length - 1; i++) {
      final a = out2.last;
      final b = out[i];
      final c = out[i + 1];

      final abx = b[0] - a[0], aby = b[1] - a[1];
      final bcx = c[0] - b[0], bcy = c[1] - b[1];

      final cross = (abx * bcy - aby * bcx).abs();
      if (cross > collinearEps) out2.add(b);
    }
    out2.add(out.last);
    return out2;
  }

  // ------------------------------------------------------------
  // STEP 3 (Navigation): Funnel (string-pulling) path smoothing
  // ------------------------------------------------------------

  /// Returns a corridor-centered path using A* over triangle neighbors + Funnel algorithm.
  /// Inputs/outputs are Blender space [x,y,z] but funnel operates in XY.
  List<List<double>> findPathFunnelBlenderXY({
    required List<double> start,
    required List<double> goal,
    int maxExpanded = 5000,
  }) {
    // 1) snap start/goal to surface
    final sSnap = snapPointXY(start);
    final gSnap = snapPointXY(goal);
    final s = [sSnap[0], sSnap[1], sSnap[2]];
    final g = [gSnap[0], gSnap[1], gSnap[2]];

    // 2) start/goal triangles
    int sTri = _findContainingTriXY(s);
    if (sTri < 0) sTri = (_findNearestTriXY(s)["tri"] as int);

    int gTri = _findContainingTriXY(g);
    if (gTri < 0) gTri = (_findNearestTriXY(g)["tri"] as int);

    if (sTri < 0 || gTri < 0) return [s, g];
    if (sTri == gTri) return [s, g];

    // 3) A* search to get triangle corridor
    final open = <int>{sTri};
    final cameFrom = <int, int>{};
    final gScore = <int, double>{sTri: 0.0};
    final fScore = <int, double>{};

    final goalCenter = _triCenter(gTri);
    double h(int ti) => sqrt(_dist2XY(_triCenter(ti), goalCenter));
    fScore[sTri] = h(sTri);

    int expanded = 0;

    while (open.isNotEmpty && expanded < maxExpanded) {
      expanded++;

      // pick open with smallest fScore
      int current = -1;
      double bestF = double.infinity;
      for (final tIdx in open) {
        final f = fScore[tIdx] ?? double.infinity;
        if (f < bestF) {
          bestF = f;
          current = tIdx;
        }
      }
      if (current == -1) break;

      if (current == gTri) {
        // reconstruct tri path
        final triPath = <int>[current];
        while (cameFrom.containsKey(current)) {
          current = cameFrom[current]!;
          triPath.add(current);
        }
        final corridor = triPath.reversed.toList();
        final funnelPts = _funnelFromTriPath(s, g, corridor);
        // snap each point back to mesh to obtain z and stay on walkable area
        final out = <List<double>>[];
        for (final p in funnelPts) {
          out.add(snapPointXY([p[0], p[1], p[2]]));
        }
        return _simplifyPathXY(out);
      }

      open.remove(current);

      for (final nb in n[current]) {
        if (nb < 0) continue;
        final tentativeG =
            (gScore[current] ?? double.infinity) +
            sqrt(_dist2XY(_triCenter(current), _triCenter(nb)));

        if (tentativeG < (gScore[nb] ?? double.infinity)) {
          cameFrom[nb] = current;
          gScore[nb] = tentativeG;
          fScore[nb] = tentativeG + h(nb);
          open.add(nb);
        }
      }
    }

    // fallback
    return findPathBlenderXY(start: start, goal: goal, maxExpanded: maxExpanded);
  }

  /// Compute a funnel (string-pulled) polyline from a triangle corridor.
  List<List<double>> _funnelFromTriPath(
    List<double> start,
    List<double> goal,
    List<int> corridor,
  ) {
    // Build portals: (left,right) points in XY. z is carried but may be snapped later.
    final portals = <List<List<double>>>[];

    portals.add([[start[0], start[1], start[2]], [start[0], start[1], start[2]]]);

    for (int i = 0; i < corridor.length - 1; i++) {
      final a = corridor[i];
      final b = corridor[i + 1];
      final edge = _sharedEdgeVerts(a, b);
      if (edge == null) continue;

      final va = v[edge[0]];
      final vb = v[edge[1]];

      // Choose left/right consistently along corridor direction
      final ca = _triCenter(a);
      final cb = _triCenter(b);
      final dirx = cb[0] - ca[0];
      final diry = cb[1] - ca[1];

      final ex = vb[0] - va[0];
      final ey = vb[1] - va[1];

      final cross = dirx * ey - diry * ex;

      final left = (cross >= 0)
          ? [va[0], va[1], (va[2] + vb[2]) * 0.5]
          : [vb[0], vb[1], (va[2] + vb[2]) * 0.5];
      final right = (cross >= 0)
          ? [vb[0], vb[1], (va[2] + vb[2]) * 0.5]
          : [va[0], va[1], (va[2] + vb[2]) * 0.5];

      portals.add([left, right]);
    }

    portals.add([[goal[0], goal[1], goal[2]], [goal[0], goal[1], goal[2]]]);

    // Funnel algorithm (2D in XY)
    double triArea2(List<double> a, List<double> b, List<double> c) {
      return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
    }

    final result = <List<double>>[];
    var apex = portals[0][0];
    var left = portals[0][0];
    var right = portals[0][1];
    int apexIndex = 0;
    int leftIndex = 0;
    int rightIndex = 0;

    result.add([apex[0], apex[1], apex[2]]);

    for (int i = 1; i < portals.length; i++) {
      final pLeft = portals[i][0];
      final pRight = portals[i][1];

      // Update right
      if (triArea2(apex, right, pRight) <= 0.0) {
        if (_samePoint(apex, right) || triArea2(apex, left, pRight) > 0.0) {
          right = pRight;
          rightIndex = i;
        } else {
          // Tighten funnel, move apex to left
          result.add([left[0], left[1], left[2]]);
          apex = left;
          apexIndex = leftIndex;

          // reset
          left = apex;
          right = apex;
          leftIndex = apexIndex;
          rightIndex = apexIndex;

          i = apexIndex;
          continue;
        }
      }

      // Update left
      if (triArea2(apex, left, pLeft) >= 0.0) {
        if (_samePoint(apex, left) || triArea2(apex, right, pLeft) < 0.0) {
          left = pLeft;
          leftIndex = i;
        } else {
          // Tighten funnel, move apex to right
          result.add([right[0], right[1], right[2]]);
          apex = right;
          apexIndex = rightIndex;

          // reset
          left = apex;
          right = apex;
          leftIndex = apexIndex;
          rightIndex = apexIndex;

          i = apexIndex;
          continue;
        }
      }
    }

    final last = portals.last[0];
    if (result.isEmpty || !_samePoint(result.last, last)) {
      result.add([last[0], last[1], last[2]]);
    }
    return result;
  }

  bool _samePoint(List<double> a, List<double> b, {double eps = 1e-9}) {
    return (a[0] - b[0]).abs() < eps && (a[1] - b[1]).abs() < eps;
  }

  /// Returns the 2 shared vertex indices between two neighboring triangles, or null.
  List<int>? _sharedEdgeVerts(int triA, int triB) {
    final ta = t[triA];
    final tb = t[triB];
    final shared = <int>[];
    for (final ia in ta) {
      for (final ib in tb) {
        if (ia == ib) shared.add(ia);
      }
    }
    if (shared.length != 2) return null;
    return [shared[0], shared[1]];
  }

}
