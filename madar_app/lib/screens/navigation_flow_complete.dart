// ============================================================================
// NAVIGATION FLOW IMPLEMENTATION FOR SOLITAIRE VENUE
// ============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show
        JavaScriptMessage,
        JavascriptChannel,
        WebViewController;

import 'package:madar_app/screens/AR_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

// ============================================================================
// 1. TRIGGER: Navigation Arrow Click Handler
// ============================================================================
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
      return snap.docs.first.reference;
    }
  }

  return users.doc(user.uid);
}

void showNavigationDialog(
  BuildContext context,
  String shopName,
  String shopId,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        NavigateToShopDialog(
          shopName: shopName,
          shopId: shopId,
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

  const NavigateToShopDialog({
    super.key,
    required this.shopName,
    required this.shopId,
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

          // ------------------------------------------------------------------
          // [PATCH A] Pin on Map = Manual mode (شغل صديقتك)
          // ------------------------------------------------------------------
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
                        autoFromScan:
                            false, // [PATCH A] manual/tap
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
                    ).context; // ✅ أهم سطر
                Navigator.pop(
                  context,
                ); // يقفل الـ sheet
                await _handleScanWithCamera(
                  rootCtx,
                  shopName,
                  shopId,
                ); // ✅ مرري rootCtx
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
  ) async {
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
              'Camera permission is required to use AR.',
            ),
          ),
        );
      }
      return;
    }

    // ✅ IMPORTANT: docId لازم يطابق اللي Unity يكتب فيه
    const docId = "demo_user";

    await _openScanAndReturnToMapWithConfirm(
      context: context,
      docId: docId,
      shopName: shopName,
      shopId: shopId,
    );
  }

  Future<void>
  _openScanAndReturnToMapWithConfirm({
    required BuildContext context,
    required String docId,
    required String shopName,
    required String shopId,
  }) async {
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

    final docRef = FirebaseFirestore
        .instance
        .collection('liveLocations')
        .doc(docId);

    final scanStartUtc = DateTime.now()
        .toUtc();

    // Baseline قبل ما نفتح Unity (عشان ما نلتقط بيانات قديمة)
    /* final beforeSnap = await docRef
        .get();
    final beforePos =
        (beforeSnap
                .data()?['blenderPosition']
            as Map?) ??
        {};
    final beforeUpdatedAt = beforeSnap
        .data()?['updatedAt'];*/

    late final StreamSubscription sub;
    bool didReturn = false;

    DateTime? _toUtcDate(dynamic v) {
      if (v == null) return null;

      if (v is Timestamp)
        return v.toDate().toUtc();

      // لو Unity تكتب رقم milliseconds
      if (v is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          v,
          isUtc: true,
        );
      }
      if (v is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          v.toInt(),
          isUtc: true,
        );
      }

      // لو بالغلط جا String ISO
      if (v is String) {
        final dt = DateTime.tryParse(v);
        return dt?.toUtc();
      }

      return null;
    }

    sub = docRef.snapshots().listen((
      snap,
    ) async {
      if (didReturn) return;
      final data = snap.data();
      if (data == null) return;

      final pos =
          (data['blenderPosition']
              as Map?) ??
          {};
      final updatedAtUtc = _toUtcDate(
        data['updatedAt'],
      );

      // ✅ أهم سطر: تجاهل أي شيء مكتوب قبل بداية السكان الحالي
      if (updatedAtUtc == null) return;
      if (!updatedAtUtc.isAfter(
        scanStartUtc,
      ))
        return;

      // الآن هذا تحديث “جديد” تابع لهذا السكان
      final x = (pos['x'] as num?)
          ?.toDouble();
      final y = (pos['y'] as num?)
          ?.toDouble();
      final z = (pos['z'] as num?)
          ?.toDouble();
      final floor = data['floor'];

      if (x == null ||
          y == null ||
          z == null)
        return;

      didReturn = true;

      try {
        final userDocRef =
            await _resolveUserDocRef(
              user,
            );
        await userDocRef.set({
          'location': {
            'blenderPosition': {
              'x': x,
              'y': y,
              'z': z,
              'floor': floor ?? '',
            },
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint(
          '❌ Failed saving scanned location to users: $e',
        );
      }

      if (context.mounted) {
        Navigator.of(
          context,
        ).pop(); // closes UnityCameraPage
      }

      await sub.cancel();

      if (!context.mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor:
            Colors.transparent,
        builder: (_) =>
            SetYourLocationDialog(
              shopName: shopName,
              shopId: shopId,
              autoFromScan: true,
            ),
      );
    });

    // ✅ افتح Unity ScanOnly
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const UnityCameraPage(
              isScanOnly: true,
            ),
      ),
    );

    if (!didReturn) {
      await sub.cancel();
    }
  }
}

// ============================================================================
// 3. SET YOUR LOCATION DIALOG (ستكملينه في PART 2)
// ============================================================================

class SetYourLocationDialog
    extends StatefulWidget {
  final String shopName;
  final String shopId;

  // --------------------------------------------------------------------------
  // [PATCH D] هذا الفلاغ يفرق بين:
  // - false: Pin on Map (manual tap) = شغل صديقتك
  // - true : Scan with camera (auto pin) = شغلك
  // --------------------------------------------------------------------------
  final bool autoFromScan;

  const SetYourLocationDialog({
    super.key,
    required this.shopName,
    required this.shopId,
    this.autoFromScan =
        false, // [PATCH D]
  });

  @override
  State<SetYourLocationDialog>
  createState() =>
      _SetYourLocationDialogState();
}

class _SetYourLocationDialogState
    extends
        State<SetYourLocationDialog> {
  bool _pendingAutoPin = false;
  bool _pendingPinApply = false;
  String _currentFloorURL = '';
  List<Map<String, String>> _venueMaps =
      [];
  bool _mapsLoading = true;
  WebViewController? _mvController;

  Map<String, double>?
  _pickedPos; // {x,y,z}
  String _pickedFloorLabel = '';

  // ✅ QUICK TEST (remove/comment later)
  final _testXCtrl =
      TextEditingController();
  final _testYCtrl =
      TextEditingController();
  final _testZCtrl =
      TextEditingController();
  final _testFloorCtrl =
      TextEditingController();

  bool _showQuickTest = true;

  @override
  void initState() {
    super.initState();

    // ------------------------------------------------------------------------
    // [PATCH E] مهم: لا نخرب شغل صديقتك
    // - manual (autoFromScan=false): لا نقرأ شيء تلقائي
    // - scan   (autoFromScan=true) : سنقرأ من users ونرسم pin تلقائي (في PART 2)
    // ------------------------------------------------------------------------
    if (widget.autoFromScan) {
      _loadUserBlenderPosition(); // في PART 2 سنضيف رسم pin تلقائي
    }

    _loadVenueMaps();
  }

  @override
  void dispose() {
    _testXCtrl.dispose();
    _testYCtrl.dispose();
    _testZCtrl.dispose();
    _testFloorCtrl.dispose();
    super.dispose();
  }

  // ... (يكمل في PART 2)

  Widget _quickTestSection() {
    if (!_showQuickTest)
      return const SizedBox.shrink();

    InputDecoration deco(
      String hint,
    ) => InputDecoration(
      hintText: hint,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(10),
      ),
      contentPadding:
          const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
    );

    double? parseD(String s) =>
        double.tryParse(s.trim());

    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        10,
        16,
        0,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(
          0.08,
        ),
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: Colors.amber
              .withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Test (temporary)',
            style: TextStyle(
              fontWeight:
                  FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      _testXCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                  decoration: deco('x'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller:
                      _testYCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                  decoration: deco('y'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller:
                      _testZCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                  decoration: deco('z'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      _testFloorCtrl,
                  decoration: deco(
                    'floor (optional) e.g. GF/F1',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  final x = parseD(
                    _testXCtrl.text,
                  );
                  final y = parseD(
                    _testYCtrl.text,
                  );
                  final z = parseD(
                    _testZCtrl.text,
                  );

                  if (x == null ||
                      y == null ||
                      z == null) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter valid numbers for x, y, z',
                        ),
                      ),
                    );
                    return;
                  }

                  setState(() {
                    _pickedPos = {
                      'x': x,
                      'y': y,
                      'z': z,
                    };
                    _pickedFloorLabel =
                        _testFloorCtrl
                            .text
                            .trim();
                  });

                  // ✅ NEW: update the visual pin
                  final c =
                      _mvController;
                  if (c != null) {
                    await c.runJavaScript(
                      'setUserPinFromFlutterSafe($x, $y, $z);',
                    );
                  }
                },

                icon: const Icon(
                  Icons
                      .play_circle_outline,
                ),
                label: const Text(
                  'Test',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      AppColors.kGreen,
                  foregroundColor:
                      Colors.white,
                  padding:
                      const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                          12,
                        ),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tip: after testing, Confirm will be enabled because _pickedPos is set.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeFloorLabel(
    dynamic floorRaw,
  ) {
    if (floorRaw == null) return '';
    final s = floorRaw
        .toString()
        .trim()
        .toUpperCase();
    if (s.isEmpty) return '';

    final n = int.tryParse(s);
    if (n != null) {
      // نفس مابينغ أزرارك: 1=GF ، 2=F1
      if (n == 1) return 'GF';
      if (n == 2) return 'F1';
      return 'F$n';
    }
    return s; // لو جا "GF" أو "F1"
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

      final doc = await userDocRef.get(
        const GetOptions(
          source: Source.serverAndCache,
        ),
      );

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
      final floorLabel =
          _normalizeFloorLabel(
            bp['floor'],
          );

      if (x == null ||
          y == null ||
          z == null)
        return;
      if (!mounted) return;

      setState(() {
        _pickedPos = {
          'x': x,
          'y': y,
          'z': z,
        };
        _pickedFloorLabel = floorLabel;
        _pendingAutoPin =
            true; // نطلب رسم البن
      });

      // لو الخرائط جاهزة: بدّل للدور المطابق
      if (floorLabel.isNotEmpty &&
          _venueMaps.isNotEmpty) {
        final match = _venueMaps
            .firstWhere(
              (m) =>
                  (m['floorNumber'] ??
                          '')
                      .toString()
                      .trim()
                      .toUpperCase() ==
                  floorLabel,
              orElse: () => const {
                'mapURL': '',
              },
            );

        final url =
            (match['mapURL'] ?? '')
                .toString()
                .trim();
        if (url.isNotEmpty && mounted) {
          setState(
            () =>
                _currentFloorURL = url,
          );
        }
      }

      // جرّبي ترسمين (إذا الويبفيو جاهز بيرسم، إذا لا بيظل pending)
      await _applyPinToViewerIfReady();
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
    .userPinIcon{
      transform: translate(-50%, -100%);
      font-size: 34px;
      filter: drop-shadow(0px 2px 3px rgba(0,0,0,0.25));
    }
  `;
  document.head.appendChild(style);
}

function ensureUserPinHotspot(viewer) {
  ensurePinStyle();
  let hs = viewer.querySelector('#userPinHotspot');
  if (!hs) {
    hs = document.createElement('div');
    hs.id = 'userPinHotspot';
    hs.slot = 'hotspot-userpin';
    hs.className = 'userPinHotspot';
    hs.innerHTML = '<div class="userPinIcon">📍</div>';
    viewer.appendChild(hs);
  }
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


function doPickAt(viewer, x, y, source) {
  try {
    const hit = viewer.positionAndNormalFromPoint(x, y);
    if (!hit || !hit.position) {
      postToPOI({ type: "user_pin", ok: false, reason: "no_hit", source });
      return;
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

  let __lastTouch = 0;

  viewer.addEventListener("click", function(event) {
    if (Date.now() - __lastTouch < 500) return;
    const p = cssPointFromEvent(viewer, event);
    doPickAt(viewer, p.x, p.y, "click");
  });

  viewer.addEventListener("touchend", function(event) {
    __lastTouch = Date.now();
    const p = getPointFromTouchEnd(viewer, event);
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
// ✅ Allow Flutter to move the pin programmatically:
window.setUserPinFromFlutter = function(x, y, z) {
  const viewer = getViewer();
  if (!viewer) return false;
  setUserPin(viewer, { x: Number(x), y: Number(y), z: Number(z) });
  return true;
};

// ✅ Safer: retry until model-viewer is ready
window.setUserPinFromFlutterSafe = function(x, y, z) {
  let tries = 0;
  const t = setInterval(() => {
    tries++;
    const ok = window.setUserPinFromFlutter(x, y, z);
    if (ok || tries > 20) clearInterval(t);
  }, 150);
};

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

          final floor =
              _floorLabelForUrl(
                _currentFloorURL,
              );
          setState(() {
            _pickedPos = {
              'x': x,
              'y': y,
              'z': z,
            };
            _pickedFloorLabel = floor;
          });
        }
      }
    } catch (_) {
      // ignore non-JSON or unexpected payloads
    }
  }

  // ---------------------------------------------------------------------------
  // [PATCH F] Apply pin visually to ModelViewer (USED ONLY FOR SCAN MODE)
  // ---------------------------------------------------------------------------
  Future<void>
  _applyPinToViewerIfReady() async {
    if (!widget.autoFromScan) return;
    if (_pickedPos == null) {
      _pendingAutoPin = false;
      return;
    }

    // لو الويبفيو ماجهز، نخزن طلب الرسم
    if (_mvController == null) {
      _pendingAutoPin = true;
      return;
    }

    final x = -(_pickedPos!['x']!);
    final y = _pickedPos!['y']!;
    final z = _pickedPos!['z']!;

    _pendingAutoPin = false;
    await _mvController!.runJavaScript(
      'setUserPinFromFlutterSafe($x, $y, $z);',
    );
  }

  Future<bool>
  _saveBlenderPosition() async {
    final pos = _pickedPos;
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
      await userDocRef.set({
        'location': {
          'blenderPosition': {
            'x': pos['x'],
            'y': pos['y'],
            'z': pos['z'],
            'floor': floorValue,
          },
          'updatedAt':
              FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

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
              // ✅ لو عندنا دور محفوظ (جا من scan) خليه الافتراضي
              if (_pickedFloorLabel
                  .isNotEmpty) {
                final match = convertedMaps.firstWhere(
                  (m) =>
                      (m['floorNumber'] ??
                              '')
                          .toString()
                          .trim()
                          .toUpperCase() ==
                      _pickedFloorLabel
                          .trim()
                          .toUpperCase(),
                  orElse: () => const {
                    'mapURL': '',
                  },
                );

                final url =
                    (match['mapURL'] ??
                            '')
                        .toString();
                if (url.isNotEmpty)
                  _currentFloorURL =
                      url;
              }

              // ✅ بعد تحميل الخرائط، لو كنا في scan mode جرّبي ترسمين البن
              if (widget.autoFromScan) {
                _applyPinToViewerIfReady();
              }

              // If we already loaded a saved floor, prefer that.
              if (_pickedFloorLabel
                  .isNotEmpty) {
                final match = convertedMaps
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
                final url =
                    match['mapURL'] ??
                    '';
                if (url.isNotEmpty)
                  _currentFloorURL =
                      url;
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
        _pickedPos != null;

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
          _quickTestSection(),
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
    final pos = _pickedPos;

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
              relatedJs: _pinPickerJs,
              onWebViewCreated: (controller) {
                _mvController =
                    controller;

                if (widget
                    .autoFromScan) {
                  Future.delayed(
                    const Duration(
                      milliseconds: 150,
                    ),
                    () {
                      if (!mounted)
                        return;
                      if (_pendingAutoPin ||
                          _pickedPos !=
                              null) {
                        _applyPinToViewerIfReady(); // ✅ هنا
                      }
                    },
                  );
                }
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
                  children: _venueMaps.map((
                    map,
                  ) {
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

          if (!widget.autoFromScan) {
            _pickedPos = null;
            _pickedFloorLabel = '';
          }
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

class PathOverviewScreen
    extends StatefulWidget {
  final String shopName;
  final String shopId;
  final String startingMethod;

  const PathOverviewScreen({
    super.key,
    required this.shopName,
    required this.shopId,
    required this.startingMethod,
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

  @override
  void initState() {
    super.initState();
    _loadVenueMaps();
    if (widget.startingMethod ==
        'pin') {
      _loadUserBlenderPosition();
    }
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
      // نفس المرجع اللي نكتب فيه (email أو uid)
      final userDocRef =
          await _resolveUserDocRef(
            user,
          );

      final doc = await userDocRef.get(
        const GetOptions(
          source: Source.serverAndCache,
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

      // طبّعي الدور لنفس صيغة أزرارك GF / F1
      String floorLabel = floorRaw
          .toString()
          .trim()
          .toUpperCase();
      final n = int.tryParse(
        floorLabel,
      );
      if (n != null) {
        if (n == 1)
          floorLabel = 'GF';
        else if (n == 2)
          floorLabel = 'F1';
        else
          floorLabel = 'F$n';
      }

      if (!mounted) return;
      setState(() {
        _originFloorLabel = floorLabel;
        _desiredStartFloorLabel =
            floorLabel;
      });
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
                  children: _venueMaps.map((
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
