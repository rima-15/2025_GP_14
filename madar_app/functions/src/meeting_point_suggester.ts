import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

type Vec3 = { x: number; y: number; z: number };
type Entrance = {
  x: number;
  y: number;
  z: number;
  floor: string;
  category?: string | null;
  material?: string | null;
  name?: string | null;
};

type ConnectorLink = {
  id: string;
  type: string;
  endpointsByFloor: Record<string, Vec3>;
};

type UserPos = {
  userId: string;
  x: number;
  y: number;
  z: number;
  floor: string;
};

type Selection = {
  any: boolean;
  cafe: boolean;
  restaurant: boolean;
  shop: boolean;
  gates: boolean;
};

type SuggestedCandidate = {
  placeId: string;
  placeName: string;
  poiMaterial: string | null;
  entrance: {
    x: number;
    y: number;
    z: number;
    floor: string;
    category?: string | null;
    material?: string | null;
    name?: string | null;
  };
  maxDistance: number;
  avgDistance: number;
  categoryIds: string[];
};

type SuggestionResult = {
  suggestedPoint: string;
  suggestedCandidates: SuggestedCandidate[];
};

let entrancesByKey: Map<string, Entrance[]> | null = null;
let connectors: ConnectorLink[] | null = null;
const navmeshes = new Map<string, NavMesh>();

function loadJson(relPath: string): any {
  const full = path.join(__dirname, "..", "assets", relPath);
  const raw = fs.readFileSync(full, "utf8");
  return JSON.parse(raw);
}

function normPoiKey(raw: string): string {
  let n = raw.trim().toLowerCase();
  n = n.replace(/\.[0-9]+$/, "");
  n = n.replace(/[^a-z0-9]+/g, "");
  if (n.startsWith("poimat")) n = n.substring(6);
  if (n.startsWith("_")) n = n.substring(1);
  return `poimat_${n}`;
}

function toFNumber(raw?: string | null): string {
  if (!raw) return "";
  let s = raw.trim();
  if (!s) return "";
  const up0 = s.toUpperCase();
  if (
    up0 === "G" ||
    up0 === "GF" ||
    up0.includes("GROUND") ||
    up0.includes("أرض") ||
    up0.includes("ارضي") ||
    up0.includes("أرضي")
  ) {
    return "0";
  }
  let up = up0.replace(/[\s_\-]+/g, "");
  up = up
    .replace("FLOOR", "")
    .replace("LEVEL", "")
    .replace("LVL", "")
    .replace("FL", "");
  const ord: Record<string, string> = {
    FIRST: "1",
    "1ST": "1",
    SECOND: "2",
    "2ND": "2",
    THIRD: "3",
    "3RD": "3",
    FOURTH: "4",
    "4TH": "4",
    FIFTH: "5",
    "5TH": "5",
    SIXTH: "6",
    "6TH": "6",
    SEVENTH: "7",
    "7TH": "7",
    EIGHTH: "8",
    "8TH": "8",
    NINTH: "9",
    "9TH": "9",
    TENTH: "10",
    "10TH": "10",
  };
  for (const key of Object.keys(ord)) {
    if (up.includes(key)) return ord[key];
  }
  if (up.includes("الاول") || up.includes("الأول") || up.includes("اول"))
    return "1";
  if (up.includes("الثاني") || up.includes("ثاني")) return "2";
  if (up.includes("الثالث") || up.includes("ثالث")) return "3";
  if (up.includes("الرابع") || up.includes("رابع")) return "4";
  if (up.includes("الخامس") || up.includes("خامس")) return "5";
  if (up.includes("السادس") || up.includes("سادس")) return "6";
  if (up.includes("السابع") || up.includes("سابع")) return "7";
  if (up.includes("الثامن") || up.includes("ثامن")) return "8";
  if (up.includes("التاسع") || up.includes("تاسع")) return "9";
  if (up.includes("العاشر") || up.includes("عاشر")) return "10";
  if (/^[0-9]+$/.test(up)) return up;
  if (up.startsWith("F") && /^[0-9]+$/.test(up.substring(1))) {
    return up.substring(1);
  }
  return "";
}

function normalizeCategory(raw: string): string {
  const lower = raw
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
  if (lower.includes("cafe") || lower.includes("caf")) return "cafe";
  if (lower.includes("restaurant")) return "restaurant";
  if (lower.includes("shop")) return "shop";
  if (lower.includes("gate")) return "gates";
  if (lower.includes("any")) return "any";
  return lower;
}

function parseSelection(list: any): Selection {
  const sel: Selection = {
    any: false,
    cafe: false,
    restaurant: false,
    shop: false,
    gates: false,
  };
  const items = Array.isArray(list) ? list : [];
  for (const raw of items) {
    const v = normalizeCategory((raw ?? "").toString());
    if (v === "any") sel.any = true;
    if (v === "cafe") sel.cafe = true;
    if (v === "restaurant") sel.restaurant = true;
    if (v === "shop") sel.shop = true;
    if (v === "gates") sel.gates = true;
  }
  if (!items.length) sel.any = true;
  return sel;
}

function loadEntrancesOnce(): Map<string, Entrance[]> {
  if (entrancesByKey) return entrancesByKey;
  const list = loadJson(path.join("poi", "solitaire_entrances.json"));
  const map = new Map<string, Entrance[]>();
  if (Array.isArray(list)) {
    for (const item of list) {
      if (!item || typeof item !== "object") continue;
      const material = (item.poiMaterial ?? "").toString();
      if (!material) continue;
      const pos = item.pos ?? {};
      const x = Number(pos.x);
      const y = Number(pos.y);
      const z = Number(pos.z);
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z))
        continue;
      const floor = (item.floor ?? "GF").toString();
      const entry: Entrance = {
        x,
        y,
        z,
        floor,
        category: item.category?.toString(),
        material,
        name: item.name?.toString(),
      };
      const key = normPoiKey(material);
      const listRef = map.get(key) ?? [];
      listRef.push(entry);
      map.set(key, listRef);
    }
  }
  entrancesByKey = map;
  return map;
}

function loadConnectorsOnce(): ConnectorLink[] {
  if (connectors) return connectors;
  const decoded = loadJson(path.join("connectors", "connectors_merged_local.json"));
  const out: ConnectorLink[] = [];
  const list = decoded?.connectors;
  if (Array.isArray(list)) {
    for (const c of list) {
      if (!c || typeof c !== "object") continue;
      const endpointsByFloor: Record<string, Vec3> = {};
      const eps = Array.isArray(c.endpoints) ? c.endpoints : [];
      for (const ep of eps) {
        const floor = toFNumber(ep.floor?.toString() ?? "");
        if (!floor) continue;
        const x = Number(ep.x);
        const y = Number(ep.y);
        const z = Number(ep.z);
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z))
          continue;
        endpointsByFloor[floor] = { x, y, z };
      }
      const floors = Object.keys(endpointsByFloor);
      if (floors.length < 2) continue;
      out.push({
        id: (c.id ?? "").toString(),
        type: (c.type ?? "").toString(),
        endpointsByFloor,
      });
    }
  }
  connectors = out;
  return out;
}

function normalizeConnectorType(raw: string): string {
  const t = raw.toLowerCase().trim();
  if (t === "stair" || t === "stairs") return "stairs";
  if (t === "elev" || t === "elevator" || t === "lift") return "elevator";
  if (t === "esc_up" || t === "escalator_up" || t === "escalatorup")
    return "escalator_up";
  if (
    t === "esc_dn" ||
    t === "esc_down" ||
    t === "escalator_down" ||
    t === "escalatordown"
  )
    return "escalator_down";
  if (t.includes("esc") || t.includes("escalator")) return "escalator";
  return t;
}

function connectorDirectionAllowed(
  normType: string,
  fromFloor: string,
  toFloor: string
): boolean {
  const from = Number(fromFloor);
  const to = Number(toFloor);
  if (!Number.isFinite(from) || !Number.isFinite(to)) return true;
  const t = normType.toLowerCase();
  if (t === "escalator_up") return from < to;
  if (t === "escalator_down") return from > to;
  return true;
}

function loadNavmeshForFloor(floor: string): NavMesh | null {
  if (navmeshes.has(floor)) return navmeshes.get(floor)!;
  let rel: string | null = null;
  if (floor === "0") rel = path.join("navmesh", "navmesh_GF.json");
  if (floor === "1") rel = path.join("navmesh", "navmesh_F1.json");
  if (!rel) return null;
  try {
    const decoded = loadJson(rel);
    if (
      !decoded ||
      !Array.isArray(decoded.vertices) ||
      !Array.isArray(decoded.triangles) ||
      !Array.isArray(decoded.neighbors)
    ) {
      return null;
    }
    const nm = new NavMesh(decoded.vertices, decoded.triangles, decoded.neighbors);
    navmeshes.set(floor, nm);
    return nm;
  } catch {
    return null;
  }
}

function distXY(a: Vec3, b: Vec3): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

function pathLenOnFloor(
  floor: string,
  a: Vec3,
  b: Vec3,
  cache: Map<string, number>
): number {
  const key = `${floor}:${round4(a.x)},${round4(a.y)}|${round4(b.x)},${round4(
    b.y
  )}`;
  const cached = cache.get(key);
  if (cached != null) return cached;

  const nm = loadNavmeshForFloor(floor);
  let len = distXY(a, b);
  if (nm) {
    const pts = nm.findPathBlenderXY([a.x, a.y, a.z], [b.x, b.y, b.z]);
    len = pathLenXY(pts);
  }
  cache.set(key, len);
  return len;
}

function round4(v: number): number {
  return Math.round(v * 10000) / 10000;
}

function pathLenXY(pts: number[][]): number {
  if (!pts || pts.length < 2) return 0;
  let sum = 0;
  for (let i = 1; i < pts.length; i++) {
    const dx = pts[i][0] - pts[i - 1][0];
    const dy = pts[i][1] - pts[i - 1][1];
    sum += Math.sqrt(dx * dx + dy * dy);
  }
  return sum;
}

function entranceIsGate(entrance: Entrance): boolean {
  return (entrance.category ?? "").toLowerCase() === "gates";
}

function placeLooksLikeGate(placeName: string, placeId: string): boolean {
  const p = placeName.toLowerCase();
  const id = placeId.toLowerCase();
  return p.startsWith("gate") || id.startsWith("gate");
}

function placeCategoryKinds(categoryIds: string[]): Set<string> {
  const out = new Set<string>();
  for (const raw of categoryIds) {
    const c = (raw ?? "").toString().toLowerCase();
    if (!c) continue;
    if (c.includes("cafe")) out.add("cafe");
    if (c.includes("restaurant")) out.add("restaurant");
    if (c.includes("shop")) out.add("shop");
    if (c.includes("service")) out.add("services");
  }
  return out;
}

function matchPlaceToSelection(
  kinds: Set<string>,
  selection: Selection
): boolean {
  if (selection.any) {
    if (kinds.size === 0) return true;
    return (
      kinds.has("cafe") ||
      kinds.has("restaurant") ||
      kinds.has("shop") ||
      kinds.has("services")
    );
  }
  if (selection.cafe && kinds.has("cafe")) return true;
  if (selection.restaurant && kinds.has("restaurant")) return true;
  if (selection.shop && kinds.has("shop")) return true;
  if (selection.gates && kinds.has("services")) return true;
  return false;
}

function filterEntrancesForSelection(
  entrances: Entrance[],
  selection: Selection,
  isGate: boolean
): Entrance[] {
  const out: Entrance[] = [];
  const allowGates = selection.gates || selection.any;
  for (const e of entrances) {
    const cat = (e.category ?? "").toLowerCase();
    if (cat === "bathrooms" || cat === "prayer_rooms") continue;
    if (isGate) {
      if (cat !== "gates") continue;
    } else {
      if (!allowGates && cat === "gates") continue;
    }
    out.push(e);
  }
  return out;
}

function buildPoiKeysForPlace(placeName: string, placeId: string, material?: string | null): string[] {
  const keys: string[] = [];
  if (material && material.trim()) {
    keys.push(normPoiKey(material));
  }
  if (placeName && placeName.trim()) {
    keys.push(normPoiKey(`POIMAT_${placeName}`));
  }
  if (placeId && placeId.trim()) {
    keys.push(normPoiKey(`POIMAT_${placeId}`));
  }
  return Array.from(new Set(keys));
}

function bestEntranceForPlace(
  entrances: Entrance[],
  users: UserPos[],
  pathCache: Map<string, number>
): { entrance: Entrance; maxDistance: number; avgDistance: number } | null {
  const conns = loadConnectorsOnce();
  if (!entrances.length || !users.length) return null;
  let best: { entrance: Entrance; maxDistance: number; avgDistance: number } | null = null;

  for (const ent of entrances) {
    const entFloor = toFNumber(ent.floor);
    if (!entFloor) continue;
    const distances: number[] = [];
    let ok = true;
    for (const u of users) {
      const d = distanceUserToEntrance(u, ent, entFloor, conns, pathCache);
      if (d == null) {
        ok = false;
        break;
      }
      distances.push(d);
    }
    if (!ok || distances.length === 0) continue;
    const maxDist = Math.max(...distances);
    const avgDist = distances.reduce((a, b) => a + b, 0) / distances.length;
    if (
      !best ||
      maxDist < best.maxDistance ||
      (maxDist === best.maxDistance && avgDist < best.avgDistance)
    ) {
      best = { entrance: ent, maxDistance: maxDist, avgDistance: avgDist };
    }
  }
  return best;
}

function distanceUserToEntrance(
  user: UserPos,
  ent: Entrance,
  entFloor: string,
  conns: ConnectorLink[],
  pathCache: Map<string, number>
): number | null {
  const userFloor = toFNumber(user.floor);
  if (!userFloor || !entFloor) return null;
  const start: Vec3 = { x: user.x, y: user.y, z: user.z };
  const dest: Vec3 = { x: ent.x, y: ent.y, z: ent.z };
  if (userFloor === entFloor) {
    return pathLenOnFloor(userFloor, start, dest, pathCache);
  }

  let best = Infinity;
  for (const c of conns) {
    const a = c.endpointsByFloor[userFloor];
    const b = c.endpointsByFloor[entFloor];
    if (!a || !b) continue;
    const normType = normalizeConnectorType(c.type);
    if (!connectorDirectionAllowed(normType, userFloor, entFloor)) continue;
    const partA = pathLenOnFloor(userFloor, start, a, pathCache);
    const partB = pathLenOnFloor(entFloor, b, dest, pathCache);
    const total = partA + partB;
    if (total < best) best = total;
  }
  return Number.isFinite(best) ? best : null;
}

async function fetchUserPositions(userIds: string[]): Promise<UserPos[]> {
  const db = admin.firestore();
  const out: UserPos[] = [];
  const chunks: string[][] = [];
  for (let i = 0; i < userIds.length; i += 10) {
    chunks.push(userIds.slice(i, i + 10));
  }
  for (const batch of chunks) {
    if (batch.length === 0) continue;
    const snap = await db
      .collection("users")
      .where(admin.firestore.FieldPath.documentId(), "in", batch)
      .get();
    for (const doc of snap.docs) {
      const data: any = doc.data() ?? {};
      const location: any = data.location ?? {};
      const bp: any = location.blenderPosition ?? {};
      const x = Number(bp.x);
      const y = Number(bp.y);
      const z = Number(bp.z);
      const floor = (bp.floor ?? "").toString();
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z))
        continue;
      out.push({ userId: doc.id, x, y, z, floor });
    }
  }
  return out;
}

export async function computeMeetingPointSuggestions(
  meetingId: string,
  meetingData: any
): Promise<SuggestionResult | null> {
  const hostId = (meetingData.hostId ?? "").toString();
  const venueId = (meetingData.venueId ?? "").toString();
  if (!hostId || !venueId) return null;

  const participants = Array.isArray(meetingData.participants)
    ? meetingData.participants
    : [];
  const acceptedIds = participants
    .filter((p: any) => (p?.status ?? "").toString().toLowerCase() === "accepted")
    .map((p: any) => (p?.userId ?? "").toString())
    .filter((v: string) => v.trim().length > 0);

  const userIds = Array.from(new Set([hostId, ...acceptedIds]));
  if (userIds.length === 0) return null;

  const users = await fetchUserPositions(userIds);
  if (users.length === 0) return null;

  const selection = parseSelection(meetingData.placeCategories);
  const entrancesMap = loadEntrancesOnce();

  const db = admin.firestore();
  const placesSnap = await db
    .collection("places")
    .where("venue_ID", "==", venueId)
    .get();

  const pathCache = new Map<string, number>();

  const collectCandidates = (sel: Selection): SuggestedCandidate[] => {
    const out: SuggestedCandidate[] = [];
    for (const doc of placesSnap.docs) {
      const data: any = doc.data() ?? {};
      const placeId = doc.id;
      const placeName = (data.placeName ?? placeId).toString();
      const categoryIds: string[] = Array.isArray(data.category_IDs)
        ? data.category_IDs
            .map((v: any) => v?.toString() ?? "")
            .filter(Boolean)
        : [];
      const kinds = placeCategoryKinds(categoryIds);
      if (!matchPlaceToSelection(kinds, sel)) continue;

      const poiMaterial: string | null =
        (data.poiMaterial ?? data.material ?? data.poiMat ?? null)
          ?.toString()
          ?.trim() ?? null;
      const keys = buildPoiKeysForPlace(placeName, placeId, poiMaterial);
      let entrances: Entrance[] = [];
      for (const k of keys) {
        const list = entrancesMap.get(k);
        if (list && list.length) {
          entrances = list;
          break;
        }
      }
      if (!entrances.length) continue;

      const isGate =
        placeLooksLikeGate(placeName, placeId) ||
        entrances.some((e) => entranceIsGate(e));
      if (isGate && !sel.gates && !sel.any) continue;

      const usableEntrances = filterEntrancesForSelection(
        entrances,
        sel,
        isGate
      );
      if (!usableEntrances.length) continue;

      const best = bestEntranceForPlace(usableEntrances, users, pathCache);
      if (!best) continue;

      out.push({
        placeId,
        placeName,
        poiMaterial,
        entrance: {
          x: best.entrance.x,
          y: best.entrance.y,
          z: best.entrance.z,
          floor: best.entrance.floor,
          category: best.entrance.category ?? null,
          material: best.entrance.material ?? null,
          name: best.entrance.name ?? null,
        },
        maxDistance: best.maxDistance,
        avgDistance: best.avgDistance,
        categoryIds,
      });
    }
    return out;
  };

  let candidates = collectCandidates(selection);
  if (candidates.length === 0 && !selection.any) {
    const relaxed: Selection = {
      any: true,
      cafe: false,
      restaurant: false,
      shop: false,
      gates: false,
    };
    candidates = collectCandidates(relaxed);
  }

  if (candidates.length === 0) return null;

  candidates.sort((a, b) => {
    if (a.maxDistance !== b.maxDistance) return a.maxDistance - b.maxDistance;
    return a.avgDistance - b.avgDistance;
  });

  const top = candidates.slice(0, 5);
  return {
    suggestedPoint: top[0].placeName,
    suggestedCandidates: top,
  };
}

class NavMesh {
  v: number[][];
  t: number[][];
  n: number[][];

  constructor(verts: number[][], tris: number[][], neigh: number[][]) {
    this.v = verts;
    this.t = tris;
    this.n = neigh;
  }

  private closestPointOnTriXY(
    p: number[],
    a: number[],
    b: number[],
    c: number[]
  ): number[] {
    const px = p[0],
      py = p[1];
    const ax = a[0],
      ay = a[1];
    const bx = b[0],
      by = b[1];
    const cx = c[0],
      cy = c[1];
    const dot2 = (ux: number, uy: number, vx: number, vy: number) =>
      ux * vx + uy * vy;
    const abx = bx - ax,
      aby = by - ay;
    const acx = cx - ax,
      acy = cy - ay;
    const apx = px - ax,
      apy = py - ay;
    const d1 = dot2(abx, aby, apx, apy);
    const d2 = dot2(acx, acy, apx, apy);
    if (d1 <= 0 && d2 <= 0) return [ax, ay, a[2]];
    const bpx = px - bx,
      bpy = py - by;
    const d3 = dot2(abx, aby, bpx, bpy);
    const d4 = dot2(acx, acy, bpx, bpy);
    if (d3 >= 0 && d4 <= d3) return [bx, by, b[2]];
    const vc = d1 * d4 - d3 * d2;
    if (vc <= 0 && d1 >= 0 && d3 <= 0) {
      const v = d1 / (d1 - d3);
      return [ax + v * abx, ay + v * aby, a[2] + v * (b[2] - a[2])];
    }
    const cpx = px - cx,
      cpy = py - cy;
    const d5 = dot2(abx, aby, cpx, cpy);
    const d6 = dot2(acx, acy, cpx, cpy);
    if (d6 >= 0 && d5 <= d6) return [cx, cy, c[2]];
    const vb = d5 * d2 - d1 * d6;
    if (vb <= 0 && d2 >= 0 && d6 <= 0) {
      const w = d2 / (d2 - d6);
      return [ax + w * acx, ay + w * acy, a[2] + w * (c[2] - a[2])];
    }
    const va = d3 * d6 - d5 * d4;
    if (va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0) {
      const w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
      return [bx + w * (cx - bx), by + w * (cy - by), b[2] + w * (c[2] - b[2])];
    }
    const denom = 1.0 / (va + vb + vc);
    const v2 = vb * denom;
    const w2 = vc * denom;
    const x = ax + abx * v2 + acx * w2;
    const y = ay + aby * v2 + acy * w2;
    const z = a[2] + (b[2] - a[2]) * v2 + (c[2] - a[2]) * w2;
    return [x, y, z];
  }

  snapPointXY(p: number[]): number[] {
    let bestD = Infinity;
    let best = p;
    for (const tri of this.t) {
      const a = this.v[tri[0]];
      const b = this.v[tri[1]];
      const c = this.v[tri[2]];
      const q = this.closestPointOnTriXY(p, a, b, c);
      const dx = q[0] - p[0];
      const dy = q[1] - p[1];
      const d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = q;
      }
    }
    return best;
  }

  private findContainingTriXY(p: number[]): number {
    const px = p[0],
      py = p[1];
    const pointInTri = (
      px2: number,
      py2: number,
      ax: number,
      ay: number,
      bx: number,
      by: number,
      cx: number,
      cy: number
    ): boolean => {
      const v0x = cx - ax,
        v0y = cy - ay;
      const v1x = bx - ax,
        v1y = by - ay;
      const v2x = px2 - ax,
        v2y = py2 - ay;
      const dot00 = v0x * v0x + v0y * v0y;
      const dot01 = v0x * v1x + v0y * v1y;
      const dot02 = v0x * v2x + v0y * v2y;
      const dot11 = v1x * v1x + v1y * v1y;
      const dot12 = v1x * v2x + v1y * v2y;
      const denom = dot00 * dot11 - dot01 * dot01;
      if (Math.abs(denom) < 1e-9) return false;
      const inv = 1.0 / denom;
      const u = (dot11 * dot02 - dot01 * dot12) * inv;
      const v = (dot00 * dot12 - dot01 * dot02) * inv;
      return u >= -1e-9 && v >= -1e-9 && u + v <= 1.0 + 1e-9;
    };
    for (let ti = 0; ti < this.t.length; ti++) {
      const tri = this.t[ti];
      const a = this.v[tri[0]];
      const b = this.v[tri[1]];
      const c = this.v[tri[2]];
      if (pointInTri(px, py, a[0], a[1], b[0], b[1], c[0], c[1])) return ti;
    }
    return -1;
  }

  private findNearestTriXY(p: number[]): { tri: number; closest: number[] } {
    let bestTri = -1;
    let bestD2 = Infinity;
    let bestPt = [p[0], p[1], p[2] ?? 0];
    const px = p[0],
      py = p[1];
    for (let ti = 0; ti < this.t.length; ti++) {
      const tri = this.t[ti];
      const a = this.v[tri[0]];
      const b = this.v[tri[1]];
      const c = this.v[tri[2]];
      const q = this.closestPointOnTriXY([px, py, 0.0], a, b, c);
      const dx = q[0] - px;
      const dy = q[1] - py;
      const d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        bestTri = ti;
        bestPt = q;
      }
    }
    return { tri: bestTri, closest: bestPt };
  }

  private triCenter(ti: number): number[] {
    const tri = this.t[ti];
    const a = this.v[tri[0]];
    const b = this.v[tri[1]];
    const c = this.v[tri[2]];
    return [
      (a[0] + b[0] + c[0]) / 3.0,
      (a[1] + b[1] + c[1]) / 3.0,
      (a[2] + b[2] + c[2]) / 3.0,
    ];
  }

  private dist2XY(p: number[], q: number[]): number {
    const dx = p[0] - q[0];
    const dy = p[1] - q[1];
    return dx * dx + dy * dy;
  }

  findPathBlenderXY(start: number[], goal: number[], maxExpanded = 5000): number[][] {
    const sSnap = this.snapPointXY(start);
    const gSnap = this.snapPointXY(goal);
    const s = [sSnap[0], sSnap[1], sSnap[2]];
    const g = [gSnap[0], gSnap[1], gSnap[2]];
    let sTri = this.findContainingTriXY(s);
    if (sTri < 0) sTri = this.findNearestTriXY(s).tri;
    let gTri = this.findContainingTriXY(g);
    if (gTri < 0) gTri = this.findNearestTriXY(g).tri;
    if (sTri < 0 || gTri < 0) return [s, g];
    if (sTri === gTri) return [s, g];

    const open = new Set<number>();
    open.add(sTri);
    const cameFrom = new Map<number, number>();
    const gScore = new Map<number, number>();
    const fScore = new Map<number, number>();
    gScore.set(sTri, 0);
    const goalCenter = this.triCenter(gTri);
    const h = (ti: number) =>
      Math.sqrt(this.dist2XY(this.triCenter(ti), goalCenter));
    fScore.set(sTri, h(sTri));

    let expanded = 0;
    while (open.size > 0 && expanded < maxExpanded) {
      expanded++;
      let current = -1;
      let bestF = Infinity;
      for (const tIdx of open) {
        const f = fScore.get(tIdx) ?? Infinity;
        if (f < bestF) {
          bestF = f;
          current = tIdx;
        }
      }
      if (current === -1) break;
      if (current === gTri) {
        const triPath: number[] = [current];
        let cur = current;
        while (cameFrom.has(cur)) {
          cur = cameFrom.get(cur)!;
          triPath.push(cur);
        }
        const rev = triPath.reverse();
        const pts: number[][] = [];
        pts.push(s);
        for (let i = 1; i < rev.length - 1; i++) {
          pts.push(this.triCenter(rev[i]));
        }
        pts.push(g);
        return pts;
      }
      open.delete(current);
      for (const nb of this.n[current]) {
        if (nb < 0) continue;
        const tentative =
          (gScore.get(current) ?? Infinity) +
          Math.sqrt(this.dist2XY(this.triCenter(current), this.triCenter(nb)));
        if (tentative < (gScore.get(nb) ?? Infinity)) {
          cameFrom.set(nb, current);
          gScore.set(nb, tentative);
          fScore.set(nb, tentative + h(nb));
          open.add(nb);
        }
      }
    }
    return [s, g];
  }
}
