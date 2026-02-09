// ============================================================================
// NAVIGATION FLOW IMPLEMENTATION FOR SOLITAIRE VENUE
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
        'assets/nav_cor/navmesh_F1.json',
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
    // Robust asset lookup: supports both older F1 naming and GF naming.
    final candidates = <String>[
      'assets/nav_cor/navmesh_F1.json',
      'assets/nav_cor/navmesh_GF.json',
    ];

    for (final path in candidates) {
      try {
        final m = await NavMesh.loadAsset(path);
        if (!mounted) return;
        setState(() => _navmeshF1 = m);
        debugPrint('✅ Navmesh loaded: $path  v=${m.v.length} t=${m.t.length}');
        return;
      } catch (_) {
        // try next
      }
    }

    debugPrint('❌ Failed to load navmesh. Check pubspec.yaml assets + file path.');
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
      _pendingPoiToHighlight =
          null; // only need to apply once
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
function _normMatName(s){
  try{
    let t = String(s||"").trim();
    if(t && !t.toUpperCase().startsWith("POIMAT_")) t = "POIMAT_" + t;
    t = t.toLowerCase();
    t = t.replace(/\s+/g, "");
    t = t.replace(/\.\d+$/g, "");
    return t;
  }catch(e){ return ""; }
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
      if (!name || !name.startsWith("POIMAT_")) return;
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
    ? (viewer.model.materials.find(x => _matName(x) === name) || viewer.model.materials.find(x => _normMatName(_matName(x)) === _normMatName(name)))
    : null;
  const orig = window.__poiOriginals[name] || window.__poiOriginals[name.replace(/\.\d+$/g,"")];
  if (!m || !orig) return;

  const pbr = m.pbrMetallicRoughness;
  if (orig.base) _setBase(pbr, [...orig.base]);
  if (orig.emis) _setEmis(m, [...orig.emis]);
  if (typeof orig.rough === "number") _setRough(pbr, orig.rough);
}

function _applyPoiHighlight(viewer, name) {
  if (!viewer || !viewer.model || !viewer.model.materials) return false;

  const target = _normMatName(name);
  const mat = (viewer.model.materials.find(m => _matName(m) === name) || viewer.model.materials.find(m => _normMatName(_matName(m)) === target));
  if (!mat) return false;

  // Restore previous highlight if exists
  if (window.__highlightedPoi && window.__highlightedPoi !== name) {
    _restorePoi(viewer, window.__highlightedPoi);
  }

  // Cache if not cached yet
  if (!window.__poiOriginals[name]) cacheOriginalPoiMaterials(viewer);

  // Apply highlight (safe factors)
  const pbr = mat.pbrMetallicRoughness;
  if (pbr) {
    _setBase(pbr, [0.4353, 0.2941, 0.1608, 1.0]);
    _setRough(pbr, 0.10);
  }
  _setEmis(mat, [0.2612, 0.1765, 0.0965]);

  window.__highlightedPoi = name;
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

class PathOverviewScreen
    extends StatefulWidget {
  final String shopName;
  final String shopId;
  final String startingMethod;

  /// Material name like "POIMAT_Balenciaga.001" (optional).
  final String destinationPoiMaterial;

  /// Floor model URL/src to open first (optional)
  final String floorSrc;

  /// Destination hit point in glTF coords from map (optional)
  final Map<String, double>?
  destinationHitGltf;

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
  State<PathOverviewScreen>
  createState() =>
      _PathOverviewScreenState();
}

class _PathOverviewScreenState
    extends State<PathOverviewScreen> {
  String _currentFloor = '';
  List<Map<String, String>> _venueMaps =
      [];
  bool _mapsLoading = false;
  String _selectedPreference = 'stairs';
  String _originFloorLabel = 'GF';
  String _desiredStartFloorLabel = '';
  String _estimatedTime = '2 min';
  String _estimatedDistance = '166 m';

  WebViewController? _webCtrl;
  bool _jsReady = false;
  Map<String, double>?
  _pendingUserPinGltf;
  String? _pendingPoiToHighlight;

  // ---- Navmesh & path state ----
  NavMesh? _navmeshF1;
  Map<String, double>? _userPosBlender;
  Map<String, double>? _destPosBlender;
  Map<String, double>?
  _userSnappedBlender;
  Map<String, double>?
  _destSnappedBlender;

  List<Map<String, double>>
  _pathPointsGltf = [];
  bool _pathPushed = false;

  // ---- Flutter -> JS helpers (Path Overview) ----
  Future<void> _pushUserPinToJsPath(
    Map<String, double> gltf,
  ) async {
    final c = _webCtrl;
    if (c == null || !_jsReady) return;

    final x = gltf['x'];
    final y = gltf['y'];
    final z = gltf['z'];
    if (x == null ||
        y == null ||
        z == null)
      return;

    try {
      // webview_flutter (new): runJavaScript
      await c.runJavaScript(
        'window.setUserPinFromFlutter($x,$y,$z);',
      );
    } catch (e) {
      debugPrint(
        'pushUserPinToJsPath failed: $e',
      );
    }
  }

  Future<void>
  _pushDestinationHighlightToJsPath() async {
    final c = _webCtrl;
    final name = _pendingPoiToHighlight;
    if (c == null ||
        !_jsReady ||
        name == null ||
        name.trim().isEmpty)
      return;

    final safe = name
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'");
    try {
      await c.runJavaScript(
        "window.highlightPoiFromFlutter('$safe');",
      );
    } catch (e) {
      debugPrint(
        'pushDestinationHighlightToJsPath failed: $e',
      );
    }
  }

  // ---- Coordinate conversions ----
  static Map<String, double>
  _gltfToBlender(
    Map<String, double> g,
  ) {
    final xg = g['x'] ?? 0.0;
    final yg = g['y'] ?? 0.0;
    final zg = g['z'] ?? 0.0;
    return {'x': xg, 'y': -zg, 'z': yg};
  }

  static Map<String, double>
  _blenderToGltf(
    Map<String, double> b,
  ) {
    final xb = b['x'] ?? 0.0;
    final yb = b['y'] ?? 0.0;
    final zb = b['z'] ?? 0.0;
    return {'x': xb, 'y': zb, 'z': -yb};
  }

  Future<void> _loadNavmeshF1() async {
    // Robust asset lookup: supports both older F1 naming and GF naming.
    final candidates = <String>[
      'assets/nav_cor/navmesh_F1.json',
      'assets/nav_cor/navmesh_GF.json'
    ];

    for (final path in candidates) {
      try {
        final m = await NavMesh.loadAsset(path);
        if (!mounted) return;
        setState(() => _navmeshF1 = m);
        debugPrint('✅ Navmesh loaded: $path  v=${m.v.length} t=${m.t.length}');
        _maybeComputeAndPushPath();
        return;
      } catch (_) {
        // try next
      }
    }

    debugPrint('❌ Failed to load navmesh. Check pubspec.yaml assets + file path.');
  }

  String _normalizePoiKey(String s) {
    var t = s.trim();
    if (t.isEmpty) return t;
    if (!t.toUpperCase().startsWith('POIMAT_')) {
      t = 'POIMAT_' + t;
    }
    // Strip Blender suffix like .001
    t = t.replaceAll(RegExp(r'\.\d+$'), '');
    // Normalize whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  String _normalizeForCompare(String s) {
    return _normalizePoiKey(s)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
  }

  Future<void> _loadDestinationFromPoiJsonIfNeeded() async {
    if (_destPosBlender != null) return;

    final rawName = (widget.destinationPoiMaterial.trim().isNotEmpty)
        ? widget.destinationPoiMaterial
        : widget.shopId;

    final wanted = _normalizeForCompare(rawName);
    if (wanted.isEmpty) return;

    final candidates = <String>[
      'assets/Solitaire_poi_GF.json',
      'assets/poi/Solitaire_poi_GF.json',
      'assets/data/Solitaire_poi_GF.json',
      'assets/Solitaire_poi_F0.json',
    ];

    Map<String, dynamic>? pois;
    for (final path in candidates) {
      try {
        final raw = await rootBundle.loadString(path);
        final obj = jsonDecode(raw);
        if (obj is Map && obj['pois'] is Map) {
          pois = Map<String, dynamic>.from(obj['pois'] as Map);
          debugPrint('✅ POI json loaded: $path  (pois=${pois.length})');
          break;
        }
      } catch (_) {
        // try next
      }
    }
    if (pois == null) {
      debugPrint('❌ Could not load POI json (Solitaire_poi_GF.json). Check pubspec.yaml assets.');
      return;
    }

    String? matchedKey;
    Map? matched;
    for (final entry in pois.entries) {
      final k = entry.key.toString();
      if (_normalizeForCompare(k) == wanted) {
        matchedKey = k;
        matched = entry.value as Map?;
        break;
      }
    }

    if (matchedKey == null || matched == null) {
      debugPrint('⚠️ POI not found in json for: $rawName');
      return;
    }

    final x = matched['x'];
    final y = matched['y'];
    final z = matched['z'];
    if (x is num && y is num && z is num) {
      _destPosBlender = {'x': x.toDouble(), 'y': y.toDouble(), 'z': z.toDouble()};
      // Keep highlight using the matched key (no .001 suffix)
      _pendingPoiToHighlight = _normalizePoiKey(matchedKey);
      if (_jsReady) {
        _pushDestinationHighlightToJsPath();
      }
      debugPrint('✅ Destination resolved from POI json: $matchedKey -> ($_destPosBlender)');
      _maybeComputeAndPushPath();
    }
  }


  // --- Path cleanup helpers (makes breadcrumbs look more centered/smooth) ---

  List<List<double>>
  _smoothAndResamplePath(
    List<List<double>> path,
    NavMesh nm,
  ) {
    var pts = path;

    // 1) Chaikin corner-cutting (smooths jagged A* polylines).
    //pts = _chaikinSmooth(pts, iterations: 1); // Funnel output is already smooth; keep this light

    // 2) Snap each point back onto the navmesh (keeps the path on corridors).
    //pts = pts.map((p) => nm.snapPointXY(p)).toList();

    // 3) Resample: keep one point every ~0.25 units (tune for your scale).
    pts = _resampleByDistance(
      pts,
      step: 0.06,
    );

    // 4) Cap hotspots to avoid WebView overload.
    const maxPts = 180;
    if (pts.length > maxPts) {
      final stride =
          (pts.length / maxPts).ceil();
      final reduced = <List<double>>[];
      for (
        var i = 0;
        i < pts.length;
        i += stride
      ) {
        reduced.add(pts[i]);
      }
      if (reduced.isEmpty ||
          !_samePoint(
            reduced.last,
            pts.last,
          )) {
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
    for (
      var it = 0;
      it < iterations;
      it++
    ) {
      if (out.length < 3) return out;
      final next = <List<double>>[];
      next.add(out.first);

      for (
        var i = 0;
        i < out.length - 1;
        i++
      ) {
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

  List<List<double>>
  _resampleByDistance(
    List<List<double>> pts, {
    required double step,
  }) {
    if (pts.length < 2) return pts;

    final out = <List<double>>[
      pts.first,
    ];
    var acc = 0.0;

    for (
      var i = 1;
      i < pts.length;
      i++
    ) {
      var prev = out.last;
      var cur = pts[i];

      var segLen = _distXY(prev, cur);
      if (segLen <= 1e-9) continue;

      while (acc + segLen >= step) {
        final t = (step - acc) / segLen;
        final nx =
            prev[0] +
            (cur[0] - prev[0]) * t;
        final ny =
            prev[1] +
            (cur[1] - prev[1]) * t;
        final nz =
            prev[2] +
            (cur[2] - prev[2]) * t;
        final np = <double>[nx, ny, nz];
        out.add(np);
        prev = np;
        segLen = _distXY(prev, cur);
        acc = 0.0;
        if (segLen <= 1e-9) break;
      }

      acc += segLen;
    }

    if (!_samePoint(
      out.last,
      pts.last,
    )) {
      out.add(pts.last);
    }
    return out;
  }

  List<List<double>>
  _pullPathTowardCenter(
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

    final denom =
        (dot00 * dot11 - dot01 * dot01);
    if (denom.abs() < 1e-12)
      return false;

    final inv = 1.0 / denom;
    final u =
        (dot11 * dot02 -
            dot01 * dot12) *
        inv;
    final v =
        (dot00 * dot12 -
            dot01 * dot02) *
        inv;

    return (u >= -1e-9) &&
        (v >= -1e-9) &&
        (u + v <= 1.0 + 1e-9);
  }

  int? _findContainingTriXY(
    NavMesh nm,
    double x,
    double y,
  ) {
    // O(numTriangles) but OK for shortcut sampling.
    for (
      int ti = 0;
      ti < nm.t.length;
      ti++
    ) {
      final tri = nm.t[ti];
      final a = nm.v[tri[0]];
      final b = nm.v[tri[1]];
      final c = nm.v[tri[2]];

      if (_pointInTri2D(
        x,
        y,
        a[0],
        a[1],
        b[0],
        b[1],
        c[0],
        c[1],
      )) {
        return ti;
      }
    }
    return null;
  }

  List<List<double>>
  _shortcutPathBySampling(
    NavMesh nm,
    List<List<double>> pts,
  ) {
    if (pts.length <= 2) return pts;

    const double sampleStep =
        0.06; // smaller = stricter

    bool segmentWalkable(
      List<double> a,
      List<double> b,
    ) {
      final ax = a[0], ay = a[1];
      final bx = b[0], by = b[1];
      final dx = bx - ax;
      final dy = by - ay;
      final len = math.sqrt(
        dx * dx + dy * dy,
      );
      if (len < 1e-6) return true;

      final steps = math.max(
        2,
        (len / sampleStep).ceil(),
      );
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = ax + dx * t;
        final y = ay + dy * t;

        // Strict: the sample point must actually be inside the navmesh surface
        final triId =
            _findContainingTriXY(
              nm,
              x,
              y,
            );
        if (triId == null) return false;
      }
      return true;
    }

    final out = <List<double>>[];
    int i = 0;
    out.add(pts.first);

    while (i < pts.length - 1) {
      int best = i + 1;

      for (
        int j = pts.length - 1;
        j > i + 1;
        j--
      ) {
        if (segmentWalkable(
          pts[i],
          pts[j],
        )) {
          best = j;
          break;
        }
      }

      out.add(pts[best]);
      i = best;
    }

    return out;
  }

  double _distXY(
    List<double> a,
    List<double> b,
  ) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _samePoint(
    List<double> a,
    List<double> b,
  ) {
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
      await c.runJavaScript(
        'window.setPathFromFlutter($jsArg);',
      );
      _pathPushed = true;
    } catch (e) {
      debugPrint(
        'pushPathToJs failed: $e',
      );
    }
  }

  void _maybeComputeAndPushPath() {
    final nm = _navmeshF1;
    if (nm == null) return;

    final u = _userPosBlender;
    final d = _destPosBlender;

    if (u == null || d == null) return;

    // Snap both endpoints to navmesh in Blender XY.
    final uSnap = nm.snapPointXY([
      u['x']!,
      u['y']!,
      u['z']!,
    ]);
    final dSnap = nm.snapPointXY([
      d['x']!,
      d['y']!,
      d['z']!,
    ]);

    _userSnappedBlender = {
      'x': uSnap[0],
      'y': uSnap[1],
      'z': uSnap[2],
    };
    _destSnappedBlender = {
      'x': dSnap[0],
      'y': dSnap[1],
      'z': dSnap[2],
    };

    // ---- DEBUG: raw vs snapped (Blender space) ----
    final uRaw = [
      u['x']!,
      u['y']!,
      u['z']!,
    ];
    final dRaw = [
      d['x']!,
      d['y']!,
      d['z']!,
    ];

    final uDx = uRaw[0] - uSnap[0];
    final uDy = uRaw[1] - uSnap[1];
    final uDist = math.sqrt(
      uDx * uDx + uDy * uDy,
    );

    final dDx = dRaw[0] - dSnap[0];
    final dDy = dRaw[1] - dSnap[1];
    final dDist = math.sqrt(
      dDx * dDx + dDy * dDy,
    );

    debugPrint(
      "🟩 startRawB=$uRaw  startSnapB=$uSnap  Δxy=$uDist",
    );
    debugPrint(
      "🟥 destRawB=$dRaw   destSnapB=$dSnap   Δxy=$dDist",
    );

    // Compute path as Blender polyline.
    var pathB = nm
        .findPathFunnelBlenderXY(
          start: uSnap,
          goal: dSnap,
        );

    pathB = _pullPathTowardCenter(
      pathB,
      strength: 0.45,
    );
    pathB = _shortcutPathBySampling(
      nm,
      pathB,
    );

    if (pathB.isEmpty) {
      debugPrint(
        '⚠️ Navmesh returned empty path',
      );
      return;
    }

    // Smooth & resample so the dots look centered and not “hugging” corners.
    final _prettyB =
        _smoothAndResamplePath(
          pathB,
          nm,
        );

    // Convert polyline points to glTF for model-viewer.
    _pathPointsGltf = _prettyB
        .map(
          (p) => _blenderToGltf({
            'x': p[0],
            'y': p[1],
            'z': p[2],
          }),
        )
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
      if (obj is Map &&
          obj['type'] ==
              'path_viewer_ready') {
        // JS is fully ready (viewer exists + listeners bound).
        if (!_jsReady) {
          _jsReady = true;
        }
        final pin = _pendingUserPinGltf;
        if (pin != null) {
          _pushUserPinToJsPath(pin);
        }
        _pushDestinationHighlightToJsPath();
        if (_pathPointsGltf
                .isNotEmpty &&
            !_pathPushed) {
          _pushPathToJs();
        }
      }
    } catch (_) {
      // ignore non-JSON
    }
  }

  void _handlePathChannelMessage(
    String message,
  ) {
    // Reserved for future polyline/breadcrumb route updates.
    // Keeping it here prevents runtime/compile errors.
    debugPrint(
      'PATH_CHANNEL: $message',
    );
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
    if (!viewer) return false;
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

function _matName(m) {
  try { return m.name || (m.material && m.material.name) || ""; } catch(e){ return ""; }
}
function _normMatName(s){
  try{
    let t = String(s||"").trim();
    if(t && !t.toUpperCase().startsWith("POIMAT_")) t = "POIMAT_" + t;
    t = t.toLowerCase();
    t = t.replace(/\s+/g, "");
    t = t.replace(/\.\d+$/g, "");
    return t;
  }catch(e){ return ""; }
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
      if (!name || !name.startsWith("POIMAT_")) return;
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
    ? (viewer.model.materials.find(x => _matName(x) === name) || viewer.model.materials.find(x => _normMatName(_matName(x)) === _normMatName(name)))
    : null;
  const orig = window.__poiOriginals[name] || window.__poiOriginals[name.replace(/\.\d+$/g,"")];
  if (!m || !orig) return;

  const pbr = m.pbrMetallicRoughness;
  if (orig.base) _setBase(pbr, [...orig.base]);
  if (orig.emis) _setEmis(m, [...orig.emis]);
  if (typeof orig.rough === "number") _setRough(pbr, orig.rough);
}

function _applyPoiHighlight(viewer, name) {
  if (!viewer || !viewer.model || !viewer.model.materials) return false;
  const target = _normMatName(name);
  const mat = (viewer.model.materials.find(m => _matName(m) === name) || viewer.model.materials.find(m => _normMatName(_matName(m)) === target));
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
  postToTest(ok ? ("✅ highlightPoiFromFlutter applied: " + n) : ("⚠️ highlightPoiFromFlutter: material not found: " + n));
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
  });

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
    if (widget.floorSrc
        .trim()
        .isNotEmpty) {
      _currentFloor = widget.floorSrc
          .trim();
    }

    // If VenuePage provided a destination hit point, store it for navmesh routing.
    final dh =
        widget.destinationHitGltf;
    if (dh != null &&
        dh.containsKey('x') &&
        dh.containsKey('y') &&
        dh.containsKey('z')) {
      _destPosBlender = _gltfToBlender(
        dh,
      );
    }

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
    _loadVenueMaps();
    _loadUserBlenderPosition();
    _loadNavmeshF1();
    _loadDestinationFromPoiJsonIfNeeded();
  }

  /// Loads the user's saved start location from:
  /// users/{uid}.location.blenderPosition {x,y,z,floor}
  /// We currently use it to display the correct origin floor and to
  /// default the 3D map to that floor.
  Future<void>
  _loadUserBlenderPosition() async {
    final user = FirebaseAuth
        .instance
        .currentUser;
    if (user == null) return;

    try {
      final doc =
          await FirebaseFirestore
              .instance
              .collection('users')
              .doc(user.uid)
              .get(
                const GetOptions(
                  source: Source
                      .serverAndCache,
                ),
              );

      final data = doc.data();
      if (data == null) return;

      final location = data['location'];
      if (location is! Map) return;

      final bp =
          location['blenderPosition'];
      if (bp is! Map) return;

      final floorRaw = bp['floor'];
      if (floorRaw == null) return;

      final floorLabel = floorRaw
          .toString();

      // Keep user's saved pin coords (Blender) and convert to glTF for model-viewer.
      final xNum = bp['x'];
      final yNum = bp['y'];
      final zNum = bp['z'];
      if (xNum is num &&
          yNum is num &&
          zNum is num) {
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

        if (_jsReady &&
            _pendingUserPinGltf !=
                null) {
          _pushUserPinToJsPath(
            _pendingUserPinGltf!,
          );
        }
        if (_jsReady) {}
      }

      if (!mounted) return;
      setState(() {
        _originFloorLabel = floorLabel;
        _desiredStartFloorLabel =
            floorLabel;
      });

      _maybeComputeAndPushPath();
    } catch (e) {
      debugPrint(
        'Error loading user blenderPosition in PathOverview: $e',
      );
    }
  }

  // ---------- AR Navigation Functions ----------

  /// Check if place has world position for AR navigation
  Future<bool> _hasWorldPosition(
    String placeId,
  ) async {
    try {
      final doc =
          await FirebaseFirestore
              .instance
              .collection('places')
              .doc(placeId)
              .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      // Check for worldPosition field
      return data.containsKey(
            'worldPosition',
          ) &&
          data['worldPosition'] != null;
    } catch (e) {
      debugPrint(
        "Error checking world position: $e",
      );
      return false;
    }
  }

  /// Show dialog when AR is not supported for this place
  void _showNoPositionDialog(
    String placeName,
  ) {
    final screenWidth = MediaQuery.of(
      context,
    ).size.width;
    final dialogPadding =
        screenWidth < 360 ? 20.0 : 28.0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
                  24,
                ),
          ),
          elevation: 0,
          backgroundColor:
              Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(
              dialogPadding,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                    24,
                  ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(
                        0.15,
                      ),
                  blurRadius: 20,
                  offset: const Offset(
                    0,
                    10,
                  ),
                ),
              ],
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration:
                      BoxDecoration(
                        color: AppColors
                            .kGreen
                            .withOpacity(
                              0.15,
                            ),
                        shape: BoxShape
                            .circle,
                      ),
                  child: const Center(
                    child: Icon(
                      Icons
                          .location_off_rounded,
                      size: 42,
                      color: AppColors
                          .kGreen,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),

                // Title
                const Text(
                  'AR Not Supported',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                    color: AppColors
                        .kGreen,
                    height: 1.2,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),

                // Description
                Text(
                  'This place doesn\'t support AR navigation yet. Please check back later!',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors
                        .grey[700],
                  ),
                ),
                const SizedBox(
                  height: 24,
                ),

                // Button
                SizedBox(
                  width:
                      double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(
                          context,
                        ).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors
                              .kGreen,
                      foregroundColor:
                          Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                            vertical:
                                14,
                          ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                              12,
                            ),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w600,
                        letterSpacing:
                            0.3,
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
  Future<void>
  _openNavigationAR() async {
    // Validate world position before proceeding
    final hasPosition =
        await _hasWorldPosition(
          widget.shopId,
        );

    if (!hasPosition) {
      if (!mounted) return;
      _showNoPositionDialog(
        widget.shopName,
      );
      return;
    }

    // Request camera permission
    final status = await Permission
        .camera
        .request();

    if (status.isGranted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              UnityCameraPage(
                isNavigation: true,
                placeId: widget.shopId,
              ),
        ),
      );
    } else if (status
        .isPermanentlyDenied) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is permanently denied. Please enable it from Settings.',
          ),
        ),
      );
      openAppSettings();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is required to use AR.',
          ),
        ),
      );
    }
  }

  Future<void> _loadVenueMaps() async {
    setState(() => _mapsLoading = true);
    try {
      final doc = await FirebaseFirestore
          .instance
          .collection('venues')
          .doc(
            'ChIJcYTQDwDjLj4RZEiboV6gZzM',
          ) // Solitaire ID
          .get(
            const GetOptions(
              source:
                  Source.serverAndCache,
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
              // Default floor
              _currentFloor =
                  convertedMaps
                      .first['mapURL'] ??
                  '';

              // If we have a saved starting floor (Pin on Map), prefer showing that floor
              if (_desiredStartFloorLabel
                  .isNotEmpty) {
                final match = convertedMaps
                    .firstWhere(
                      (m) =>
                          (m['floorNumber'] ??
                              '') ==
                          _desiredStartFloorLabel,
                      orElse: () =>
                          const {
                            'mapURL':
                                '',
                          },
                    );
                final url =
                    match['mapURL'] ??
                    '';
                if (url.isNotEmpty)
                  _currentFloor = url;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint(
        "Error loading maps: $e",
      );
    } finally {
      if (mounted)
        setState(
          () => _mapsLoading = false,
        );
    }
  }

  void _changePreference(
    String preference,
  ) {
    setState(() {
      _selectedPreference = preference;
      if (preference == 'elevator') {
        _estimatedTime = '3 min';
        _estimatedDistance = '180 m';
      } else if (preference ==
          'escalator') {
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
                      key: ValueKey(
                        _currentFloor,
                      ),
                      src:
                          _currentFloor,
                      alt: "3D Map",
                      cameraControls:
                          true,
                      backgroundColor:
                          const Color(
                            0xFFF5F5F0,
                          ),
                      cameraOrbit:
                          "0deg 65deg 2.5m",
                      minCameraOrbit:
                          "auto 0deg auto",
                      maxCameraOrbit:
                          "auto 90deg auto",
                      cameraTarget:
                          "0m 0m 0m",
                      relatedJs:
                          _pathViewerJs,
                      onWebViewCreated:
                          (c) {
                            _webCtrl =
                                c;
                            _jsReady =
                                false;
                          },
                      javascriptChannels: {
                        JavascriptChannel(
                          'POI_CHANNEL',
                          onMessageReceived:
                              (
                                msg,
                              ) => _handlePoiMessage(
                                msg.message,
                              ),
                        ),
                        JavascriptChannel(
                          'JS_TEST_CHANNEL',
                          onMessageReceived: (msg) {
                            if (!_jsReady &&
                                msg.message.contains(
                                  'PathViewer JS alive',
                                )) {
                              _jsReady =
                                  true;

                              final pin =
                                  _pendingUserPinGltf;
                              if (pin !=
                                  null) {
                                _pushUserPinToJsPath(
                                  pin,
                                );
                              }
                              _pushDestinationHighlightToJsPath();
                            }
                          },
                        ),
                        JavascriptChannel(
                          'PATH_CHANNEL',
                          onMessageReceived:
                              (
                                msg,
                              ) => _handlePathChannelMessage(
                                msg.message,
                              ),
                        ),
                      },
                    ),
            ),

            // Floor Selectors - Positioned on map
            Positioned(
              top: 220, // Below header
              right: 20,
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
                  children: sortedMaps.map((
                    map,
                  ) {
                    final label =
                        map['floorNumber'] ??
                        '';
                    final url =
                        map['mapURL'] ??
                        '';
                    final isSelected =
                        _currentFloor ==
                        url;
                    return Padding(
                      padding:
                          const EdgeInsets.only(
                            bottom: 8,
                          ),
                      child:
                          _buildFloorButton(
                            label,
                            url,
                            isSelected,
                          ),
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
                padding:
                    const EdgeInsets.fromLTRB(
                      10,
                      20,
                      20,
                      16,
                    ),
                child: Column(
                  children: [
                    // Location rows with back button
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(
                                top: 8,
                              ),
                          child: IconButton(
                            icon: const Icon(
                              Icons
                                  .arrow_back,
                              color: AppColors
                                  .kGreen,
                            ),
                            onPressed: () =>
                                Navigator.pop(
                                  context,
                                ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              // Origin Row
                              _locationRow(
                                Icons
                                    .radio_button_checked,
                                'Your location',
                                'GF',
                                const Color(
                                  0xFF6C6C6C,
                                ),
                              ),

                              // Dotted Line
                              Padding(
                                padding: const EdgeInsets.only(
                                  left:
                                      10,
                                ),
                                child: Align(
                                  alignment:
                                      Alignment.centerLeft,
                                  child: SizedBox(
                                    height:
                                        15,
                                    width:
                                        2,
                                    child: Column(
                                      children: List.generate(
                                        3,
                                        (
                                          index,
                                        ) => Expanded(
                                          child: Container(
                                            width: 1.5,
                                            color:
                                                index %
                                                        2 ==
                                                    0
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
                                Icons
                                    .location_on,
                                widget
                                    .shopName,
                                'F1',
                                const Color(
                                  0xFFC88D52,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    // Preference buttons row - HORIZONTAL LAYOUT (icon + text)
                    Row(
                      children: [
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Stairs',
                            Icons
                                .stairs,
                            'stairs',
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Elevator',
                            Icons
                                .elevator,
                            'elevator',
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Escalator',
                            Icons
                                .escalator,
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
                padding:
                    const EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      16,
                    ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.only(
                        topLeft:
                            Radius.circular(
                              30,
                            ),
                        topRight:
                            Radius.circular(
                              30,
                            ),
                      ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors
                          .black12,
                      blurRadius: 8,
                      offset: Offset(
                        0,
                        -2,
                      ),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    // Time and Distance Info
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              '$_estimatedTime ($_estimatedDistance)',
                              style: const TextStyle(
                                fontSize:
                                    22,
                                fontWeight:
                                    FontWeight.bold,
                                color: Colors
                                    .black,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              widget
                                  .shopName,
                              style: TextStyle(
                                color: Colors
                                    .grey[500],
                                fontSize:
                                    16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    // Divider
                    Divider(
                      color: Colors
                          .grey[300],
                      thickness: 1,
                      height: 1,
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    // Start AR Navigation Button
                    PrimaryButton(
                      text:
                          'Start AR Navigation',
                      onPressed:
                          _openNavigationAR,
                    ),

                    SizedBox(
                      height:
                          MediaQuery.of(
                                context,
                              )
                              .padding
                              .bottom,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(
    IconData icon,
    String label,
    String floor,
    Color color,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color: color,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
              border: Border.all(
                color:
                    Colors.grey[100]!,
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight:
                    FontWeight.w500,
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
              fontWeight:
                  FontWeight.bold,
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
    final isSelected =
        _selectedPreference == value;
    return GestureDetector(
      onTap: () =>
          _changePreference(value),
      child: Container(
        padding:
            const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFE8E9E0)
              : Colors.white,
          borderRadius:
              BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AppColors.kGreen
                  : Colors.grey[500],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? AppColors.kGreen
                      : Colors
                            .grey[600],
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight
                            .normal,
                ),
                overflow: TextOverflow
                    .ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // CONSISTENT FLOOR BUTTON - Same as Set Your Location dialog
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
          _currentFloor = url;
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
// 5. AR SUCCESS DIALOG
// ============================================================================

class ARSuccessDialog
    extends StatelessWidget {
  final VoidCallback onOkPressed;

  const ARSuccessDialog({
    super.key,
    required this.onOkPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.kGreen
                    .withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.kGreen,
                size: 50,
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Success!',
              style: TextStyle(
                fontSize: 24,
                fontWeight:
                    FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'Your location has been detected. You will now be taken to the Path Overview screen.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: onOkPressed,
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
              child: const Text(
                'OK',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
