// ============================================================================
// NAVIGATION FLOW IMPLEMENTATION FOR SOLITAIRE VENUE
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:madar_app/nav/navmesh.dart';
import 'path_overview_screen.dart';
export 'path_overview_screen.dart';

// ============================================================================
// 1. TRIGGER: Navigation Arrow Click Handler
// ============================================================================

void showNavigationDialog(
  BuildContext context,
  String shopName,
  String shopId, {
  String destinationPoiMaterial = '',
  String floorSrc = '',
  Map<String, double>?
  destinationHitGltf,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        NavigateToShopDialog(
          shopName: shopName,
          shopId: shopId,
          destinationPoiMaterial:
              destinationPoiMaterial,
          floorSrc: floorSrc,
          destinationHitGltf:
              destinationHitGltf,
        ),
  );
}

// ============================================================================
// 2. NAVIGATE TO SHOP DIALOG
// ============================================================================

class NavigateToShopDialog
    extends StatelessWidget {
  final String shopName;
  final String shopId;

  /// Material name like "POIMAT_Balenciaga.001" (optional; keeps old call sites working).
  final String destinationPoiMaterial;

  /// Current floor model URL/src (optional)
  final String floorSrc;

  /// Destination hit point in glTF coords from the map hotspot (optional)
  final Map<String, double>?
  destinationHitGltf;

  const NavigateToShopDialog({
    super.key,
    required this.shopName,
    required this.shopId,
    this.destinationPoiMaterial = '',
    this.floorSrc = '',
    this.destinationHitGltf,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(
      context,
    ).size.height;
    final isSmallScreen =
        screenHeight < 700;

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
              borderRadius:
                  BorderRadius.circular(
                    2,
                  ),
            ),
          ),

          // Header matched to "Set Your Location" style
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  10,
                ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Navigate to $shopName',
                        style: TextStyle(
                          fontSize:
                              isSmallScreen
                              ? 20
                              : 22,
                          fontWeight:
                              FontWeight
                                  .w600,
                          color: AppColors
                              .kGreen,
                        ),
                        maxLines: 2,
                        overflow:
                            TextOverflow
                                .ellipsis,
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        'First, set your starting point.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors
                              .grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          Padding(
            padding:
                const EdgeInsets.symmetric(
                  horizontal: 20,
                ),
            child: SecondaryButton(
              text: 'Pin on Map',
              icon: Icons
                  .location_on_outlined,
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled:
                      true,
                  backgroundColor:
                      Colors
                          .transparent,
                  builder: (context) =>
                      SetYourLocationDialog(
                        shopName:
                            shopName,
                        shopId: shopId,
                        destinationPoiMaterial:
                            destinationPoiMaterial,
                        floorSrc:
                            floorSrc,
                        destinationHitGltf:
                            destinationHitGltf,
                      ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding:
                const EdgeInsets.symmetric(
                  horizontal: 20,
                ),
            child: PrimaryButton(
              text: 'Scan With Camera',
              icon: Icons
                  .camera_alt_outlined,
              onPressed: () async {
                final rootCtx =
                    Navigator.of(
                      context,
                      rootNavigator:
                          true,
                    ).context;

                Navigator.pop(context);

                await _handleScanWithCamera(
                  rootCtx,
                  shopName,
                  shopId,
                  destinationPoiMaterial,
                  floorSrc,
                  destinationHitGltf,
                );
              },
            ),
          ),
          SizedBox(
            height:
                MediaQuery.of(
                  context,
                ).padding.bottom +
                35,
          ),
        ],
      ),
    );
  }

  Future<void> _handleScanWithCamera(
    BuildContext context,
    String shopName,
    String shopId,
    String destinationPoiMaterial,
    String floorSrc,
    Map<String, double>?
    destinationHitGltf,
  ) async {
    // 1) Camera permission
    final status = await Permission
        .camera
        .request();
    if (!context.mounted) return;

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera permission required. Please enable in Settings.',
            ),
          ),
        );
        openAppSettings();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera permission is required.',
            ),
          ),
        );
      }
      return;
    }

    // 2) Ensure signed-in
    final user = FirebaseAuth
        .instance
        .currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'You must be signed in.',
          ),
        ),
      );
      return;
    }

    // 3) Baseline time (like your old scan logic)
    final scanStartUtc = DateTime.now()
        .toUtc();

    // 4) Resolve correct users doc (email/uid)
    final userDocRef =
        await _resolveUserDocRef(user);

    // 5) Helper: convert Firestore timestamp to DateTime UTC
    DateTime? _toUtcDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp)
        return v.toDate().toUtc();
      if (v is int)
        return DateTime.fromMillisecondsSinceEpoch(
          v,
          isUtc: true,
        );
      if (v is num)
        return DateTime.fromMillisecondsSinceEpoch(
          v.toInt(),
          isUtc: true,
        );
      if (v is String)
        return DateTime.tryParse(
          v,
        )?.toUtc();
      return null;
    }

    // 6) Try loading navmesh for snapping (do NOT block if fails)
    NavMesh? nav;
    try {
      nav = await NavMesh.loadAsset(
        'assets/nav_cor/navmesh_GF.json',
      );
      debugPrint(
        '✅ Navmesh loaded for scan snapping',
      );
    } catch (e) {
      nav = null;
      debugPrint(
        '⚠️ Navmesh not available for scan snapping: $e',
      );
    }

    bool didReturn = false;
    late final StreamSubscription sub;

    // 7) Listen for DB update (users doc)
    sub = userDocRef.snapshots().listen((
      snap,
    ) async {
      if (didReturn) return;

      final data = snap.data();
      if (data == null) return;

      final loc = data['location'];
      if (loc is! Map) return;

      // Must be updated after scan started
      final updatedAtUtc = _toUtcDate(
        loc['updatedAt'],
      );
      if (updatedAtUtc == null) return;

      // Ignore old cached/previous updates
      if (!updatedAtUtc.isAfter(
        scanStartUtc,
      ))
        return;

      final bp = loc['blenderPosition'];
      if (bp is! Map) return;

      final x = (bp['x'] as num?)
          ?.toDouble();
      final y = (bp['y'] as num?)
          ?.toDouble();
      final z = (bp['z'] as num?)
          ?.toDouble();
      final floor =
          bp['floor']; // keep whatever Unity sends

      if (x == null ||
          y == null ||
          z == null)
        return;

      // 8) Snap to closest allowed point (navmesh if available)
      var snapped = <String, double>{
        'x': x,
        'y': y,
        'z': z,
      };
      if (nav != null) {
        try {
          snapped = nav!
              .snapBlenderPoint(
                snapped,
              );
        } catch (_) {
          // keep raw
        }
      }

      didReturn = true;

      // 9) Close Unity page (top route)
      if (Navigator.of(
        context,
      ).canPop()) {
        Navigator.of(context).pop();
      }

      await sub.cancel();
      if (!context.mounted) return;
      final snappedGltf =
          <String, double>{
            'x': snapped['x'] ?? x,
            'y': snapped['y'] ?? y,
            'z': snapped['z'] ?? z,
          };

      // 10) Show the Pin-on-Map UI again (so you can see the pin and press Confirm)

      final floorLabelFromScan =
          floor == null
          ? ''
          : floor.toString();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor:
            Colors.transparent,
        builder: (_) =>
            SetYourLocationDialog(
              shopName: shopName,
              shopId: shopId,
              destinationPoiMaterial:
                  destinationPoiMaterial,
              floorSrc: floorSrc,
              destinationHitGltf:
                  destinationHitGltf,
              initialUserPinGltf:
                  snappedGltf,
              initialFloorLabel:
                  floorLabelFromScan,
            ),
      );
    });

    // 11) Open Unity (no need to wait for "result == true")
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const UnityCameraPage(
              isScanOnly: true,
            ),
      ),
    );

    // 12) If user exits Unity manually without any DB update, cancel the listener
    if (!didReturn) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
  }

  Future<
    DocumentReference<
      Map<String, dynamic>
    >
  >
  _resolveUserDocRef(User user) async {
    final users = FirebaseFirestore
        .instance
        .collection('users');

    final email = user.email;
    if (email != null &&
        email.isNotEmpty) {
      final snap = await users
          .where(
            'email',
            isEqualTo: email,
          )
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap
            .docs
            .first
            .reference;
      }
    }

    // Fallback: use uid as doc id.
    return users.doc(user.uid);
  }
}

class SetYourLocationDialog
    extends StatefulWidget {
  final String shopName;
  final String shopId;

  /// Material name like "POIMAT_Balenciaga.001" (optional).
  final String destinationPoiMaterial;

  /// Current floor model URL/src (optional)
  final String floorSrc;

  /// Destination hit point in glTF coords from the map hotspot (optional)
  final Map<String, double>?
  destinationHitGltf;
  final Map<String, double>?
  initialUserPinGltf;
  final String? initialFloorLabel;

  const SetYourLocationDialog({
    super.key,
    required this.shopName,
    required this.shopId,
    this.destinationPoiMaterial = '',
    this.floorSrc = '',
    this.destinationHitGltf,
    this.initialUserPinGltf,
    this.initialFloorLabel,
  });

  @override
  State<SetYourLocationDialog>
  createState() =>
      _SetYourLocationDialogState();
}

class _SetYourLocationDialogState
    extends
        State<SetYourLocationDialog> {
  String _currentFloorURL = '';
  List<Map<String, String>> _venueMaps =
      [];
  bool _mapsLoading = true;
  bool _jsReady = false;
  Map<String, double>?
  _pendingUserPinGltf;
  NavMesh? _navmeshF1;

  WebViewController?
  _webCtrl; // for Flutter -> JS calls (move snapped pin)

  bool _jsBridgeReady =
      false; // becomes true after JS runs (prevents calling setUserPinFromFlutter too early)
  Map<String, double>?
  _pendingPinToSend; // cached pin to push once JS bridge is ready

  String?
  _pendingPoiToHighlight; // destination POI material to highlight once JS is ready

  // User-picked start location (BlenderPosition)
  Map<String, double>?
  _pickedPosGltf; // what model-viewer returns (Y-up)
  Map<String, double>?
  _pickedPosBlender; // converted for navmesh + Firestore (Z-up)
  String _pickedFloorLabel = '';

  @override
  void initState() {
    super.initState();

    // Open the correct floor if the caller provided it (Path/Pin flow).
    if (widget.floorSrc
        .trim()
        .isNotEmpty) {
      _currentFloorURL = widget.floorSrc
          .trim();
    }

    // Destination highlight only (NO PATH on this screen).
    final dest = widget
        .destinationPoiMaterial
        .trim();
    if (dest.isNotEmpty) {
      _pendingPoiToHighlight = dest;
    } else if (widget.shopId
        .trim()
        .startsWith('POIMAT_')) {
      // VenuePage often passes POI material as shopId
      _pendingPoiToHighlight = widget
          .shopId
          .trim();
    } else {
      _pendingPoiToHighlight = null;
    }

    if (widget.initialUserPinGltf !=
        null) {
      final g =
          widget.initialUserPinGltf!;
      _pickedPosGltf = g;
      _pickedPosBlender =
          _gltfToBlender(g);
    }
    if (widget.initialFloorLabel !=
            null &&
        widget.initialFloorLabel!
            .trim()
            .isNotEmpty) {
      _pickedFloorLabel = widget
          .initialFloorLabel!
          .trim();
    }

    _loadVenueMaps();
    if (widget.initialUserPinGltf ==
        null) {
      _loadUserBlenderPosition();
    }

    // Load navmesh only for snapping the user's pin to the walkable floor.
    _loadNavmeshF1();
  }

  Future<void> _loadNavmeshF1() async {
    try {
      final m = await NavMesh.loadAsset(
        'assets/nav_cor/navmesh_GF.json',
      );
      if (!mounted) return;
      setState(() => _navmeshF1 = m);
      debugPrint(
        '✅ Navmesh loaded (F1) for snapping',
      );
    } catch (e) {
      debugPrint(
        '❌ Failed to load navmesh_GF.json: $e',
      );
    }
  }

  /// Loads the last saved user location (if any). It reads from:
  /// users/{uid}.location.blenderPosition {x,y,z,floor}
  /// and sets the UI state (and preferred floor) accordingly.
  Future<void>
  _loadUserBlenderPosition() async {
    final user = FirebaseAuth
        .instance
        .currentUser;
    if (user == null) return;

    try {
      final userDocRef =
          await _resolveUserDocRef(
            user,
          );
      final doc = await userDocRef
          .get();

      final data = doc.data();
      if (data == null) return;

      final location = data['location'];
      if (location is! Map) return;

      final bp =
          location['blenderPosition'];
      if (bp is! Map) return;

      final x = (bp['x'] as num?)
          ?.toDouble();
      final y = (bp['y'] as num?)
          ?.toDouble();
      final z = (bp['z'] as num?)
          ?.toDouble();
      final floorRaw = bp['floor'];
      if (x == null ||
          y == null ||
          z == null)
        return;

      final floorLabel =
          floorRaw == null
          ? ''
          : floorRaw.toString();

      if (!mounted) return;
      final blenderRaw = {
        'x': x,
        'y': y,
        'z': z,
      };

      // Snap to navmesh if it is already loaded (keeps the pin on walkable floor).
      final blender =
          (_navmeshF1 != null)
          ? _navmeshF1!
                .snapBlenderPoint(
                  blenderRaw,
                )
          : blenderRaw;
      final gltf = _blenderToGltf(
        blender,
      );

      setState(() {
        _pickedPosBlender = blender;
        _pickedPosGltf = gltf;
        _pickedFloorLabel = floorLabel;
      });

      // Update the visible pin if JS is ready (safe even if it isn't).
      if (_jsReady &&
          _pickedPosGltf != null) {
        _pushUserPinToJs(
          _pickedPosGltf!,
        );
      }

      // If we already have maps loaded, switch to the saved floor.
      if (floorLabel.isNotEmpty &&
          _venueMaps.isNotEmpty) {
        final match = _venueMaps
            .firstWhere(
              (m) =>
                  (m['floorNumber'] ??
                      '') ==
                  floorLabel,
              orElse: () => const {
                'mapURL': '',
              },
            );
        final url =
            match['mapURL'] ?? '';
        if (url.isNotEmpty && mounted) {
          setState(
            () =>
                _currentFloorURL = url,
          );
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading user blenderPosition: $e',
      );
    }
  }

  String _floorLabelForUrl(String url) {
    for (final m in _venueMaps) {
      if ((m['mapURL'] ?? '') == url)
        return (m['floorNumber'] ?? '')
            .toString();
    }
    return '';
  }

  String _fNumberForUrl(String url) {
    for (final m in _venueMaps) {
      if ((m['mapURL'] ?? '') == url)
        return (m['F_number'] ?? '')
            .toString();
    }
    return '';
  }

  Map<String, double> _gltfToBlender(
    Map<String, double> g,
  ) {
    // glTF (Y up) -> Blender (Z up)
    return {
      'x': g['x'] ?? 0,
      'y': -(g['z'] ?? 0),
      'z': (g['y'] ?? 0),
    };
  }

  Map<String, double> _blenderToGltf(
    Map<String, double> b,
  ) {
    // Blender (Z up) -> glTF (Y up)
    return {
      'x': b['x'] ?? 0,
      'y': (b['z'] ?? 0),
      'z': -(b['y'] ?? 0),
    };
  }

  Future<void> _pushUserPinToJs(
    Map<String, double> gltf,
  ) async {
    final c = _webCtrl;
    if (c == null) return;

    if (!_jsBridgeReady) {
      _pendingPinToSend = gltf;
      return;
    }

    final x = gltf['x'];
    final y = gltf['y'];
    final z = gltf['z'];
    if (x == null ||
        y == null ||
        z == null)
      return;

    final js =
        'window.setUserPinFromFlutter($x, $y, $z);';
    try {
      await c.runJavaScript(js);
    } catch (e) {
      debugPrint(
        '❌ runJavaScript failed: $e',
      );
    }
  }

  Future<void>
  _pushDestinationHighlightToJs() async {
    final c = _webCtrl;
    final name = _pendingPoiToHighlight;
    if (c == null ||
        name == null ||
        name.trim().isEmpty)
      return;

    if (!_jsBridgeReady) return;

    final safe = jsonEncode(
      name.trim(),
    ); // ensures quotes/escaping
    final js =
        'window.highlightPoiFromFlutter($safe);';
    try {
      await c.runJavaScript(js);
    } catch (e) {
      debugPrint(
        '❌ highlight runJavaScript failed: $e',
      );
    }
  }

  // JS: tap → positionAndNormalFromPoint → show hotspot pin → send JSON to Flutter via POI_CHANNEL
  String get _pinPickerJs => r'''
console.log("✅ PinPicker relatedJs injected");

function postToPOI(obj) {
  try { POI_CHANNEL.postMessage(JSON.stringify(obj)); return true; } catch (e) { return false; }
}
function postToTest(msg) {
  try { JS_TEST_CHANNEL.postMessage(msg); return true; } catch (e) { return false; }
}
function getViewer() { return document.querySelector('model-viewer'); }
// ---- Location picking guard (Flutter controls this) ----
window.__locationMode = true;               // Set-location screen should be true
window.__allowedFloorMaterial = "Allowed_floor";

window.setLocationModeFromFlutter = function(enabled) {
  window.__locationMode = !!enabled;
  postToTest("🟨 LocationMode=" + window.__locationMode);
};

window.setAllowedFloorMaterialFromFlutter = function(name) {
  window.__allowedFloorMaterial = String(name || "");
  postToTest("🟨 AllowedFloorMaterial=" + window.__allowedFloorMaterial);
};

function cssPointFromEvent(viewer, event) {
  const rect = viewer.getBoundingClientRect();
  return { x: event.clientX - rect.left, y: event.clientY - rect.top };
}
function getPointFromTouchEnd(viewer, e) {
  const t = (e.changedTouches && e.changedTouches[0]) ? e.changedTouches[0] : null;
  if (!t) return null;
  const rect = viewer.getBoundingClientRect();
  return { x: t.clientX - rect.left, y: t.clientY - rect.top };
}

// ---- Tap vs Gesture filter (prevents accidental repicks while zoom/pan) ----
let __touchStartPt = null;
let __touchMoved = false;
let __touchMulti = false;
let __touchStartTime = 0;

const TAP_MOVE_PX = 10;   // increase to 14 if still too sensitive
const TAP_TIME_MS = 450;  // optional: ignore long presses

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

  // Wrapper to offset upward so the tip touches the ground point
  var wrap = document.createElement("div");
  wrap.style.position = "absolute";
  wrap.style.left = "0";
  wrap.style.top = "0";
  wrap.style.transform = "translate(-50%, -92%)";
  wrap.style.pointerEvents = "none";

  // Pin body (teardrop)
  var pin = document.createElement("div");
  pin.style.width = "24px";
  pin.style.height = "24px";
  pin.style.background = "#ff3b30";
  pin.style.borderRadius = "24px 24px 24px 0";
  pin.style.transform = "rotate(-45deg)";
  pin.style.position = "relative";
  pin.style.boxShadow = "0 6px 14px rgba(0,0,0,0.35)";
  pin.style.border = "2px solid rgba(255,255,255,0.85)";

  // Inner white circle
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

  // Ground shadow
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
  // Some Android WebView builds don't refresh hotspot position
  // when only data-position changes. Detach/attach forces refresh.
  const hs = ensureUserPinHotspot(viewer);

  if (hs.parentElement) {
    hs.parentElement.removeChild(hs);
    viewer.appendChild(hs);
  }

  // Use raw numbers (no "m") for maximum compatibility
  hs.setAttribute('data-position', `${pos.x} ${pos.y} ${pos.z}`);
  hs.setAttribute('data-normal', `0 1 0`);

  viewer.requestUpdate();
  requestAnimationFrame(() => viewer.requestUpdate());
}

// --- Flutter -> JS (move pin after Flutter-side snapping) ---
window.__pendingUserPin = null;

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

// --- Destination POI highlight (by material name) ---
window.__pendingPoiHighlight = null;
window.__highlightedPoi = null;
window.__poiOriginals = window.__poiOriginals || {};

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
      if (!name || !/^POIMAT_/i.test(name)) return;
      if (window.__poiOriginals[name]) return;

      // Cache base/emissive/roughness so we can restore later.
      const pbr = m.pbrMetallicRoughness;
      window.__poiOriginals[name] = {
        base: _getBase(pbr),
        emis: _getEmis(m),
        rough: _getRough(pbr),
      };
    });

    postToPOI({ type: "debug", step: "cacheOriginalPoiMaterials", ok: true, cachedTotal: Object.keys(window.__poiOriginals).length, cachedThisCall: 0 });
  } catch (e) {
    postToPOI({ type: "debug", step: "cacheOriginalPoiMaterials", ok: false, error: String(e) });
  }
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

  // Resolve material name across variants:
  // - "POIMAT_X.001" vs "POIMAT_X"
  // - missing "POIMAT_" / "POI_" prefixes
  function _stripSuffix(n) {
    return (n || '').trim().replace(/\.\d+$/, '');
  }
  function _candidateNames(n) {
    const s = (n || '').trim();
    if (!s) return [];
    const base = _stripSuffix(s);
    const out = [s];
    if (base && base !== s) out.push(base);

    // If caller passed "Balenciaga" try common prefixes
    if (base && !/^POIMAT_/i.test(base) && !/^POI_/i.test(base)) {
      out.push('POIMAT_' + base);
      out.push('POI_' + base);
    }
    // Dedup while preserving order
    return out.filter((v, i) => out.indexOf(v) === i);
  }
  function _resolveMaterialName(req) {
  const candidates = _candidateNames(req);

  // Normalize for case-insensitive matching and suffix-insensitive matching.
  function _norm(n) {
    return _stripSuffix(String(n || "").trim()).toUpperCase();
  }

  // Build a lookup map from normalized name -> actual material name in the model.
  const map = {};
  for (const m of viewer.model.materials) {
    const actual = _matName(m);
    if (!actual) continue;
    const key = _norm(actual);
    if (!map[key]) map[key] = actual;
  }

  // 1) candidate direct match (case-insensitive, ignores .### suffix)
  for (const c of candidates) {
    const hit = map[_norm(c)];
    if (hit) return hit;
  }

  // 2) If caller passed name without prefixes, try POIMAT_ prefix (case-insensitive)
  const reqBase = _stripSuffix(String(req || "").trim());
  if (!reqBase) return null;

  const pref = "POIMAT_" + reqBase;
  const hit2 = map[_norm(pref)];
  if (hit2) return hit2;

  return null;
}

  const resolvedName = _resolveMaterialName(name);
  if (!resolvedName) return false;

  const mat = viewer.model.materials.find(m => _matName(m) === resolvedName);
  if (!mat) return false;

  // Restore previous highlight if exists
  if (window.__highlightedPoi && window.__highlightedPoi !== resolvedName) {
    _restorePoi(viewer, window.__highlightedPoi);
  }

  // Cache originals once (covers all materials)
  if (!window.__poiOriginals || Object.keys(window.__poiOriginals).length === 0) {
    window.__poiOriginals = {};
  }
  if (!window.__poiOriginals[resolvedName]) cacheOriginalPoiMaterials(viewer);

  // Apply highlight (safe factors)
  const pbr = mat.pbrMetallicRoughness;
  if (pbr) {
    _setBase(pbr, [0.4353, 0.2941, 0.1608, 1.0]);
    _setRough(pbr, 0.10);
  }
  _setEmis(mat, [0.2612, 0.1765, 0.0965]);

  window.__highlightedPoi = resolvedName;
  viewer.requestUpdate();
  return true;
}

// Flutter -> JS
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
  postToTest(ok ? ("✅ highlightPoiFromFlutter applied: " + n) : ("⚠️ highlightPoiFromFlutter: material not found: " + n));
};

function hitWithFallback(viewer, x, y) {
  const offsets = [
    [0, 0], [2, 0], [-2, 0], [0, 2], [0, -2],
    [2, 2], [-2, 2], [2, -2], [-2, -2]
  ];
  for (const [dx, dy] of offsets) {
    const h = viewer.positionAndNormalFromPoint(x + dx, y + dy);
    if (h && h.position) return h;
  }
  return null;
}

function doPickAt(viewer, x, y, source) {
  try {
    // If we're in location mode, only allow taps on the allowed floor material.
    if (window.__locationMode) {
      const mat = viewer.materialFromPoint(x, y);
      const matName = (mat && mat.name) ? String(mat.name) : "";
      postToTest("🧪 locationMode hit material=" + matName);

      const base = String(window.__allowedFloorMaterial || "");
const ok = (matName === base) || matName.startsWith(base + ".");

if (!ok) {
  postToTest("⛔ Tap rejected. Hit=" + matName + " allowed=" + base + "(.###)");
  postToPOI({ type: "user_pin", ok: false, reason: "not_allowed_floor", hitMaterial: matName, source });
  return;
}

    }

    const hit = hitWithFallback(viewer, x, y);
    if (!hit || !hit.position) {
      postToPOI({ type: "user_pin", ok: false, reason: "no_hit", source });
      return;
    }
  // Extra safety: in location mode accept only mostly-horizontal surfaces (floor)
if (window.__locationMode && hit.normal) {
  const up = Math.abs(Number(hit.normal.y || 0)); // glTF Y-up
  if (up < 0.7) {
    postToTest("⛔ rejected: not floor-like normal (up=" + up.toFixed(2) + ")");
    postToPOI({ type: "user_pin", ok: false, reason: "not_floor_normal", up, source });
    return;
  }
}

    const pos = hit.position;
    setUserPin(viewer, pos);

    postToPOI({
      type: "user_pin",
      ok: true,
      source,
      src: viewer.getAttribute("src") || "",
      position: { x: pos.x, y: pos.y, z: pos.z }
    });
  } catch (e) {
    postToPOI({ type: "user_pin", ok: false, reason: String(e), source });
  }
}


function setupViewer() {
  const viewer = getViewer();
  if (!viewer) return false;

  // Avoid double-binding across rebuilds
  if (viewer.__pinPickerBound) return true;
  viewer.__pinPickerBound = true;

  // Apply any pending snapped pin once the model finishes loading
  viewer.addEventListener("load", () => {
    // Cache POI originals once model loads.
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
  });


  let __lastTouch = 0;
    // Track touch gestures so zoom/pan doesn't count as a "tap"
  viewer.addEventListener("touchstart", function(e) {
    __touchMoved = false;
    __touchMulti = (e.touches && e.touches.length > 1);
    __touchStartTime = Date.now();

    const t = (e.touches && e.touches[0]) ? e.touches[0] : null;
    if (!t) { __touchStartPt = null; return; }

    const rect = viewer.getBoundingClientRect();
    __touchStartPt = { x: t.clientX - rect.left, y: t.clientY - rect.top };
  }, { passive: true });

  viewer.addEventListener("touchmove", function(e) {
    if (e.touches && e.touches.length > 1) {
      __touchMulti = true; // pinch/zoom
      return;
    }
    if (!__touchStartPt) return;

    const t = (e.touches && e.touches[0]) ? e.touches[0] : null;
    if (!t) return;

    const rect = viewer.getBoundingClientRect();
    const x = t.clientX - rect.left;
    const y = t.clientY - rect.top;

    const dx = x - __touchStartPt.x;
    const dy = y - __touchStartPt.y;
    if ((dx * dx + dy * dy) > (TAP_MOVE_PX * TAP_MOVE_PX)) {
      __touchMoved = true; // pan/drag
    }
  }, { passive: true });

  viewer.addEventListener("click", function(event) {
    if (Date.now() - __lastTouch < 500) return;
    const p = cssPointFromEvent(viewer, event);
    doPickAt(viewer, p.x, p.y, "click");
  });

   viewer.addEventListener("touchend", function(event) {
    __lastTouch = Date.now();

    // If this interaction was a pan/zoom/pinch, ignore it
    if (__touchMulti || __touchMoved) {
      postToTest("🚫 touchend ignored (gesture) multi=" + __touchMulti + " moved=" + __touchMoved);
      __touchStartPt = null;
      __touchMoved = false;
      __touchMulti = false;
      return;
    }

    // Optional: ignore long presses
    const dt = Date.now() - __touchStartTime;
    if (dt > TAP_TIME_MS) {
      postToTest("🚫 touchend ignored (too long) dt=" + dt);
      __touchStartPt = null;
      return;
    }

    // Use touchstart point (more stable than touchend point)
    const p = __touchStartPt || getPointFromTouchEnd(viewer, event);
    __touchStartPt = null;

    if (!p) return;
    doPickAt(viewer, p.x, p.y, "touchend");
  }, { passive: true });


  postToPOI({ type: "pin_picker_ready" });
  return true;
}

let tries = 0;
const timer = setInterval(function() {
  tries++;
  postToTest("✅ PinPicker JS alive");
  if (setupViewer() || tries > 30) clearInterval(timer);
}, 250);
''';

  void _handleJsMessage(String raw) {
    try {
      dynamic decoded = jsonDecode(raw);

      // Some WebViews deliver JSON as a quoted string, e.g. ""{...}""
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }

      if (decoded is! Map) return;
      final obj = decoded;
      final type = (obj['type'] ?? '')
          .toString();

      if (type == 'pin_picker_ready') {
        _jsBridgeReady = true;

        final p = _pendingPinToSend;
        if (p != null) {
          _pendingPinToSend = null;
          _pushUserPinToJs(p);
        }

        // Also highlight destination POI (if provided) in this viewer.
        _pushDestinationHighlightToJs();
        return;
      }

      if (type == 'user_pin') {
        final ok = obj['ok'] == true;
        if (!ok) return;

        final pos = obj['position'];
        if (pos is Map) {
          final x = (pos['x'] as num?)
              ?.toDouble();
          final y = (pos['y'] as num?)
              ?.toDouble();
          final z = (pos['z'] as num?)
              ?.toDouble();
          if (x == null ||
              y == null ||
              z == null)
            return;

          final gltf = {
            'x': x,
            'y': y,
            'z': z,
          };
          final blender =
              _gltfToBlender(gltf);

          // snap in Blender-space (corridor floor)
          final nav = _navmeshF1;
          final snappedBlender =
              (nav == null)
              ? blender
              : nav.snapBlenderPoint(
                  blender,
                ); // we'll add this helper in navmesh.dart

          final snappedGltf =
              _blenderToGltf(
                snappedBlender,
              );

          final floor =
              _floorLabelForUrl(
                _currentFloorURL,
              );

          setState(() {
            _pickedPosGltf =
                snappedGltf;
            _pickedPosBlender =
                snappedBlender;
            _pickedFloorLabel = floor;
          });

          // ✅ Move the visible pin to the snapped position (Flutter -> JS)
          _pushUserPinToJs(snappedGltf);

          debugPrint(
            '📌 PIN glTF: $gltf',
          );
          debugPrint(
            '📌 PIN Blender: $blender',
          );
          debugPrint(
            '📌 SNAPPED Blender: $snappedBlender',
          );
        }
      }
    } catch (_) {
      // ignore non-JSON or unexpected payloads
    }
  }

  Future<
    DocumentReference<
      Map<String, dynamic>
    >
  >
  _resolveUserDocRef(User user) async {
    final users = FirebaseFirestore
        .instance
        .collection('users');

    // If your users collection uses auto-generated document IDs (as in your screenshot),
    // we find the doc by email and update that doc instead of creating a new {uid} doc.
    final email = user.email;
    if (email != null &&
        email.isNotEmpty) {
      final snap = await users
          .where(
            'email',
            isEqualTo: email,
          )
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap
            .docs
            .first
            .reference;
      }
    }

    // Fallback: use uid as doc id.
    return users.doc(user.uid);
  }

  Future<bool>
  _saveBlenderPosition() async {
    final pos = _pickedPosBlender;
    if (pos == null) return false;

    final user = FirebaseAuth
        .instance
        .currentUser;
    if (user == null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'You must be signed in to save your location.',
          ),
        ),
      );
      return false;
    }

    final floorLabel =
        _pickedFloorLabel.isNotEmpty
        ? _pickedFloorLabel
        : _floorLabelForUrl(
            _currentFloorURL,
          );

    // Store canonical floor id (F_number) when available (e.g. "0","1"...).
    final fNumberStr = _fNumberForUrl(
      _currentFloorURL,
    );
    final floorValue =
        fNumberStr.isNotEmpty
        ? (int.tryParse(fNumberStr) ??
              fNumberStr)
        : (int.tryParse(floorLabel) ??
              floorLabel);

    try {
      final userDocRef =
          await _resolveUserDocRef(
            user,
          );

      // Save under location.{blenderPosition,updatedAt}
      // Using dotted keys avoids overwriting future location.multisetPosition.
      await userDocRef.update({
        'location.blenderPosition': {
          'x': pos['x'],
          'y': pos['y'],
          'z': pos['z'],
          'floor': floorValue,
        },
        'location.updatedAt':
            FieldValue.serverTimestamp(),
      });

      if (!mounted) return true;
      return true;
    } catch (e) {
      debugPrint(
        '❌ Failed to save location: $e',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save location: $e',
            ),
          ),
        );
      }
      // Don't rethrow — keep UI alive.
      return false;
    }
  }

  Future<void> _loadVenueMaps() async {
    if (!mounted) return;
    setState(() => _mapsLoading = true);

    try {
      // Solitaire Place ID verified from your venue_page logic
      const String solitaireId =
          'ChIJcYTQDwDjLj4RZEiboV6gZzM';

      final doc =
          await FirebaseFirestore
              .instance
              .collection('venues')
              .doc(solitaireId)
              .get(
                const GetOptions(
                  source: Source
                      .serverAndCache,
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
          m,
        ) {
          return {
            'F_number':
                (m['F_number'] ?? '')
                    .toString(),
            'floorNumber':
                (m['floorNumber'] ?? '')
                    .toString(),
            'mapURL':
                (m['mapURL'] ?? '')
                    .toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            if (convertedMaps
                .isNotEmpty) {
              _currentFloorURL =
                  convertedMaps
                      .first['mapURL'] ??
                  '';

              // If we already loaded a saved floor, prefer that.
              // If we already loaded a saved floor, prefer that.
              // IMPORTANT: _pickedFloorLabel might be "0"/"1" from Unity (F_number), not "GF"/"F1".
              if (_pickedFloorLabel
                  .isNotEmpty) {
                Map<String, String>
                match;

                // 1) Try match by F_number ("0","1"...)
                match = convertedMaps
                    .firstWhere(
                      (m) =>
                          (m['F_number'] ??
                              '') ==
                          _pickedFloorLabel,
                      orElse: () =>
                          const {
                            'mapURL':
                                '',
                          },
                    );

                // 2) Fallback: match by floorNumber ("GF","F1"...)
                if ((match['mapURL'] ??
                        '')
                    .isEmpty) {
                  match = convertedMaps
                      .firstWhere(
                        (m) =>
                            (m['floorNumber'] ??
                                '') ==
                            _pickedFloorLabel,
                        orElse: () =>
                            const {
                              'mapURL':
                                  '',
                            },
                      );
                }

                final url =
                    match['mapURL'] ??
                    '';
                if (url.isNotEmpty) {
                  _currentFloorURL =
                      url;
                }
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint(
        "Error loading maps in dialog: $e",
      );
    } finally {
      if (mounted)
        setState(
          () => _mapsLoading = false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(
      context,
    ).size.height;

    final pinPlaced =
        _pickedPosGltf != null;

    // Match venue_page ordering: higher floors first (F2, F1, ... , GF last)
    final sortedMaps =
        List<Map<String, String>>.from(
          _venueMaps,
        );

    int floorRank(String s) {
      final f = s.trim().toUpperCase();
      if (f == 'GF') return 0;
      if (f.startsWith('F'))
        return int.tryParse(
              f.substring(1),
            ) ??
            0;
      return 0;
    }

    sortedMaps.sort((a, b) {
      final ra = floorRank(
        a['floorNumber'] ?? '',
      );
      final rb = floorRank(
        b['floorNumber'] ?? '',
      );
      return rb.compareTo(ra);
    });

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.85,
        minHeight: 500,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius:
                  BorderRadius.circular(
                    2,
                  ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
                  10,
                  10,
                  20,
                  10,
                ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: AppColors
                        .kGreen,
                  ),
                  onPressed: () =>
                      Navigator.pop(
                        context,
                      ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Set Your Location',
                        style: TextStyle(
                          fontSize:
                              screenHeight <
                                  700
                              ? 20
                              : 22,
                          fontWeight:
                              FontWeight
                                  .w600,
                          color: AppColors
                              .kGreen,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        pinPlaced
                            ? 'Location selected. Tap again to move it.'
                            : 'Tap on the 3D map to place your pin.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors
                              .grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),
              child: _buildMapContent(),
            ),
          ),
          Padding(
            padding:
                EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(
                        context,
                      ).padding.bottom +
                      20,
                ),
            child: PrimaryButton(
              text: 'Confirm Location',
              enabled: pinPlaced,
              onPressed: pinPlaced
                  ? () async {
                      final ok =
                          await _saveBlenderPosition();
                      if (!ok) return;
                      if (!mounted)
                        return;

                      Navigator.pop(
                        context,
                      );
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PathOverviewScreen(
                            shopName: widget
                                .shopName,
                            shopId: widget
                                .shopId,
                            startingMethod:
                                'pin',
                            destinationPoiMaterial:
                                widget
                                    .destinationPoiMaterial,
                            floorSrc:
                                widget
                                    .floorSrc
                                    .isNotEmpty
                                ? widget
                                      .floorSrc
                                : _currentFloorURL,
                            destinationHitGltf:
                                widget
                                    .destinationHitGltf,
                          ),
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapContent() {
    if (_mapsLoading) {
      return const AppLoadingIndicator();
    }

    if (_venueMaps.isEmpty) {
      return const Center(
        child: Text(
          "Map missing for Solitaire.",
        ),
      );
    }

    final floorLabel =
        _floorLabelForUrl(
          _currentFloorURL,
        );
    final pos = _pickedPosGltf;
    final bpos = _pickedPosBlender;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(16),
        child: Stack(
          children: [
            // 3D Model Viewer (with JS picking)
            ModelViewer(
              key: ValueKey(
                _currentFloorURL,
              ),
              src: _currentFloorURL,
              alt: "Solitaire 3D Map",
              cameraControls: true,
              autoRotate: false,
              backgroundColor:
                  Colors.transparent,
              cameraOrbit:
                  "0deg 65deg 2.5m",
              minCameraOrbit:
                  "auto 0deg auto",
              maxCameraOrbit:
                  "auto 90deg auto",
              cameraTarget: "0m 0m 0m",
              relatedJs: _pinPickerJs,
              onWebViewCreated: (controller) {
                _webCtrl = controller;

                // New WebView instance -> JS is not ready yet
                _jsBridgeReady = false;

                // If we already have a saved pin, cache it and push once JS becomes ready
                _pendingPinToSend =
                    _pickedPosGltf;
              },
              javascriptChannels: {
                JavascriptChannel(
                  'JS_TEST_CHANNEL',
                  onMessageReceived:
                      (
                        JavaScriptMessage
                        message,
                      ) {
                        debugPrint(
                          "✅ JS_TEST_CHANNEL: ${message.message}",
                        );

                        // As soon as JS starts running, our window.setUserPinFromFlutter exists.
                        if (!_jsBridgeReady &&
                            message
                                .message
                                .contains(
                                  'PinPicker JS alive',
                                )) {
                          _jsBridgeReady =
                              true;
                          // Restrict taps to Allowed_floor during Set Location step
                          _webCtrl?.runJavaScript(
                            "window.setLocationModeFromFlutter(true);",
                          );
                          _webCtrl?.runJavaScript(
                            "window.setAllowedFloorMaterialFromFlutter('Allowed_floor');",
                          );

                          final p =
                              _pendingPinToSend;
                          if (p !=
                              null) {
                            _pendingPinToSend =
                                null;
                            _pushUserPinToJs(
                              p,
                            );
                          }
                          _pushDestinationHighlightToJs();
                        }
                      },
                ),
                JavascriptChannel(
                  'POI_CHANNEL',
                  onMessageReceived:
                      (
                        JavaScriptMessage
                        message,
                      ) {
                        debugPrint(
                          "🟦 POI_CHANNEL: ${message.message}",
                        );
                        _handleJsMessage(
                          message
                              .message,
                        );
                      },
                ),
              },
            ),

            // Floor Selectors
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.all(
                      8,
                    ),
                decoration: BoxDecoration(
                  color: Colors.white
                      .withOpacity(0.9),
                  borderRadius:
                      BorderRadius.circular(
                        8,
                      ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors
                          .black
                          .withOpacity(
                            0.1,
                          ),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  children:
                      (List<Map<String, String>>.from(
                            _venueMaps,
                          )..sort((
                            a,
                            b,
                          ) {
                            int rank(
                              String s,
                            ) {
                              final f = s
                                  .trim()
                                  .toUpperCase();
                              if (f ==
                                  'GF')
                                return 0;
                              if (f
                                  .startsWith(
                                    'F',
                                  ))
                                return int.tryParse(
                                      f.substring(
                                        1,
                                      ),
                                    ) ??
                                    0;
                              return 0;
                            }

                            final ra = rank(
                              a['floorNumber'] ??
                                  '',
                            );
                            final rb = rank(
                              b['floorNumber'] ??
                                  '',
                            );
                            return rb
                                .compareTo(
                                  ra,
                                ); // higher floors first
                          }))
                          .map((map) {
                            final label =
                                map['floorNumber'] ??
                                '';
                            final url =
                                map['mapURL'] ??
                                '';
                            final isSelected =
                                _currentFloorURL ==
                                url;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom:
                                    8,
                              ),
                              child: _buildFloorButton(
                                label,
                                url,
                                isSelected,
                              ),
                            );
                          })
                          .toList(),
                ),
              ),
            ),

            // Debug/feedback chip (optional, lightweight)
            if (pos != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withOpacity(
                          0.92,
                        ),
                    borderRadius:
                        BorderRadius.circular(
                          10,
                        ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors
                            .black
                            .withOpacity(
                              0.08,
                            ),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Text(
                    'Floor: $floorLabel\nx: ${pos['x']!.toStringAsFixed(3)}  y: ${pos['y']!.toStringAsFixed(3)}  z: ${pos['z']!.toStringAsFixed(3)}',
                    style:
                        const TextStyle(
                          fontSize: 12,
                          height: 1.2,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloorButton(
    String label,
    String url,
    bool isSelected,
  ) {
    return SizedBox(
      width: 44,
      height: 40,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected
              ? AppColors.kGreen
              : Colors.white,
          foregroundColor: isSelected
              ? Colors.white
              : AppColors.kGreen,
          padding: EdgeInsets.zero,
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
                  8,
                ),
            side: BorderSide(
              color: isSelected
                  ? AppColors.kGreen
                  : Colors
                        .grey
                        .shade300,
            ),
          ),
        ),
        onPressed: () => setState(() {
          _currentFloorURL = url;
          _pickedPosGltf = null;
          _pickedPosBlender = null;

          _pickedFloorLabel = '';
        }),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 4. PATH OVERVIEW SCREEN - FIXED MAP VISIBILITY & CONSISTENT FLOOR SELECTORS
// ============================================================================

// ============================================================================
// 4. PATH OVERVIEW SCREEN - FIXED MAP VISIBILITY & CONSISTENT FLOOR SELECTORS
// ============================================================================

/// Backwards-compatible name used by VenuePage.
/// This screen lets the user pick a start location (pin) on the map.
class PinStartLocationScreen
    extends SetYourLocationDialog {
  const PinStartLocationScreen({
    super.key,
    required String shopName,
    required String shopId,

    // Backwards-compat: some older call sites pass this, but SetYourLocationDialog
    // decides the method internally ("pin" / "scan"), so we don't forward it.
    required String startingMethod,

    String destinationPoiMaterial = '',
  }) : super(
         shopName: shopName,
         shopId: shopId,
         destinationPoiMaterial:
             destinationPoiMaterial,
       );
}
