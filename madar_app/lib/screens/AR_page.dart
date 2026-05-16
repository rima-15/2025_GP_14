import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:madar_app/theme/theme.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UnityCameraPage
    extends StatefulWidget {
  final bool isNavigation;
  final String? placeId;
  final bool isScanOnly;
  final String? navigationPreference;
  final bool isFriendNavigation;
  final double? friendX;
  final double? friendY;
  final double? friendZ;
  final String? friendFloor;
  final String? friendName;

  const UnityCameraPage({
    super.key,
    this.isNavigation = false,
    this.placeId,
    this.isScanOnly = false,
    this.navigationPreference,
    this.isFriendNavigation = false,
    this.friendX,
    this.friendY,
    this.friendZ,
    this.friendFloor,
    this.friendName,
  });

  @override
  State<UnityCameraPage>
  createState() =>
      _UnityCameraPageState();
}

class _UnityCameraPageState
    extends State<UnityCameraPage>
    with WidgetsBindingObserver {
  bool _isUnityReady = false;
  String _statusMessage =
      "Initializing AR...";
  String? _cachedUserDocId;
  // ── DEV / UI TESTING ONLY ────────────────────────────────────────────
  // When true: the selector shows immediately with all three buttons enabled,
  // ignoring any availability data from Unity. Use this to test the Flutter
  // UI when localization isn't available (e.g., not at the mall).
  // ⚠️ SET THIS TO false BEFORE SHIPPING.
  static const bool
  _devForceSelectorVisible = true;

  // Selector state — driven entirely by Unity messages
  bool _showSelector = false;
  bool _stairsAvailable = true;
  bool _elevatorAvailable = true;
  bool _escalatorAvailable = true;
  String _selectedPreference = 'none';

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      this,
    );
    _initializeUnity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    super.didChangeAppLifecycleState(
      state,
    );
    if (state ==
        AppLifecycleState.resumed)
      _sendHandshakeAndMode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isUnityReady &&
        ModalRoute.of(
              context,
            )?.isCurrent ==
            true) {
      Future.delayed(
        const Duration(
          milliseconds: 200,
        ),
        () {
          if (mounted)
            _sendHandshakeAndMode();
        },
      );
    }
  }

  // ── Unity init ───────────────────────────────────────────────────────

  Future<void>
  _initializeUnity() async {
    setState(
      () => _statusMessage =
          "Loading AR environment...",
    );
    await Future.delayed(
      const Duration(milliseconds: 600),
    );
    if (!mounted) return;

    setState(() {
      _isUnityReady = true;
      _statusMessage =
          widget.isFriendNavigation
          ? "Navigating to ${widget.friendName ?? 'friend'}..."
          : widget.isNavigation
          ? "Starting navigation..."
          : (widget.isScanOnly
                ? "Scanning location..."
                : "AR Ready");
    });

    await _sendHandshakeAndMode();
  }

  // ── Send to Unity ────────────────────────────────────────────────────

  String _normalizedPreference() {
    final pref =
        (widget.navigationPreference ??
                '')
            .trim()
            .toLowerCase();
    if (pref == 'stairs' ||
        pref == 'elevator' ||
        pref == 'escalator')
      return pref;
    return 'none';
  }

  Future<String?>
  _resolveUserDocIdByEmail() async {
    final user = FirebaseAuth
        .instance
        .currentUser;
    if (user == null) return null;
    final email = user.email;
    if (email == null || email.isEmpty)
      return null;
    final snap = await FirebaseFirestore
        .instance
        .collection('users')
        .where(
          'email',
          isEqualTo: email,
        )
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<String?>
  _getFreshIdToken() async {
    final user = FirebaseAuth
        .instance
        .currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(
        true,
      );
    } catch (e) {
      debugPrint(
        "❌ Failed to get ID token: $e",
      );
      return null;
    }
  }

  Future<void>
  _sendHandshakeAndMode() async {
    if (!_isUnityReady) return;

    _cachedUserDocId ??=
        await _resolveUserDocIdByEmail();
    if (_cachedUserDocId == null ||
        _cachedUserDocId!.isEmpty) {
      debugPrint(
        "❌ Could not resolve Firestore user docId.",
      );
      return;
    }

    final idToken =
        await _getFreshIdToken();
    if (idToken == null ||
        idToken.isEmpty) {
      debugPrint(
        "❌ Could not get Firebase Auth ID token.",
      );
      return;
    }

    try {
      sendToUnity(
        "FlutterListener",
        "OnFlutterMessage",
        "USER_DOC_ID:${_cachedUserDocId!}",
      );
      debugPrint(
        "✅ Sent USER_DOC_ID to Unity: ${_cachedUserDocId!}",
      );
    } catch (e) {
      debugPrint(
        "❌ Failed to send USER_DOC_ID: $e",
      );
      return;
    }

    await Future.delayed(
      const Duration(milliseconds: 120),
    );

    try {
      sendToUnity(
        "FlutterListener",
        "OnFlutterMessage",
        "ID_TOKEN:$idToken",
      );
      debugPrint(
        "✅ Sent ID_TOKEN to Unity (len=${idToken.length})",
      );
    } catch (e) {
      debugPrint(
        "❌ Failed to send ID_TOKEN: $e",
      );
      return;
    }

    await Future.delayed(
      const Duration(milliseconds: 120),
    );

    final String modeMessage;
    final pref =
        _normalizedPreference();

    if (widget.isFriendNavigation &&
        widget.friendX != null &&
        widget.friendY != null &&
        widget.friendZ != null &&
        widget.friendFloor != null) {
      final safeName =
          (widget.friendName ??
                  'Friend')
              .replaceAll(':', '|');
      modeMessage =
          "NAVIGATE_TO_USER:${widget.friendX}:${widget.friendY}:${widget.friendZ}:${widget.friendFloor}:$pref:$safeName";
    } else if (widget.isNavigation &&
        widget.placeId != null &&
        widget.placeId!.isNotEmpty) {
      modeMessage =
          "NAVIGATION:${widget.placeId}:$pref";
    } else if (widget.isScanOnly) {
      modeMessage = "SCAN_ONLY";
    } else {
      modeMessage = "EXPLORE";
    }

    try {
      sendToUnity(
        "FlutterListener",
        "OnFlutterMessage",
        modeMessage,
      );
      debugPrint(
        "✅ Sent mode to Unity: $modeMessage",
      );
    } catch (e) {
      debugPrint(
        "❌ Failed to send mode message: $e",
      );
    }
  }

  // ── Receive from Unity ───────────────────────────────────────────────

  void _onMessageFromUnity(String msg) {
    debugPrint(
      "📩 Message from Unity: $msg",
    );

    if (msg == "HIDE_SELECTOR") {
      setState(() {
        _showSelector = false;
        _selectedPreference = 'none';
      });
      return;
    }

    if (msg.startsWith(
      "SHOW_SELECTOR:",
    )) {
      final payload = msg.substring(
        "SHOW_SELECTOR:".length,
      );
      final parts = Map.fromEntries(
        payload.split(',').map((p) {
          final kv = p.split('=');
          return MapEntry(
            kv[0].trim(),
            kv.length > 1
                ? kv[1].trim()
                : '',
          );
        }),
      );

      setState(() {
        _stairsAvailable =
            parts['stairs'] == '1';
        _elevatorAvailable =
            parts['elevator'] == '1';
        _escalatorAvailable =
            parts['escalator'] == '1';
        _selectedPreference =
            parts['current'] ?? 'none';
        _showSelector = true;
      });

      debugPrint(
        "✅ Selector shown — "
        "stairs=$_stairsAvailable "
        "elevator=$_elevatorAvailable "
        "escalator=$_escalatorAvailable "
        "current=$_selectedPreference",
      );
    }
  }

  // ── User taps a preference button ────────────────────────────────────

  void _onPreferenceTapped(
    String pref,
  ) {
    // Tap selected button again → toggle off (none = shortest path)
    final newPref =
        (_selectedPreference == pref)
        ? 'none'
        : pref;
    setState(
      () =>
          _selectedPreference = newPref,
    );

    try {
      sendToUnity(
        "FlutterListener",
        "OnFlutterMessage",
        "NAVIGATION_PREFERENCE:$newPref",
      );
      debugPrint(
        "✅ Sent preference to Unity: $newPref",
      );
    } catch (e) {
      debugPrint(
        "❌ Failed to send preference: $e",
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(
      context,
    ).padding.top;
    final bottomPadding = MediaQuery.of(
      context,
    ).padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Unity AR view
          EmbedUnity(
            onMessageFromUnity:
                _onMessageFromUnity,
          ),

          // Loading overlay
          if (!_isUnityReady)
            Container(
              color: Colors.black
                  .withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<
                            Color
                          >(kGreen),
                      strokeWidth: 3,
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors
                            .white,
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Back button — top-left circle (unchanged)
          Positioned(
            top: topPadding + 12,
            left: 12,
            child: GestureDetector(
              onTap: () =>
                  Navigator.pop(
                    context,
                  ),
              child: Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(
                      color: Colors
                          .white
                          .withOpacity(
                            0.85,
                          ),
                      shape: BoxShape
                          .circle,
                    ),
                child: const Icon(
                  Icons.arrow_back,
                  color: kGreen,
                  size: 22,
                ),
              ),
            ),
          ),

          // Preference selector — vertical column of circles on right side
          // Only shown when Unity sends SHOW_SELECTOR (navigation mode only)
          if (_showSelector)
            Positioned(
              // Vertically centered between top safe area and bottom safe area
              top: topPadding + 80,
              right: 12,
              child: _ARPreferenceSelector(
                stairsAvailable:
                    _stairsAvailable,
                elevatorAvailable:
                    _elevatorAvailable,
                escalatorAvailable:
                    _escalatorAvailable,
                selected:
                    _selectedPreference,
                onTap:
                    _onPreferenceTapped,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AR PREFERENCE SELECTOR
// Vertical column of circle buttons on the right side.
// Circle size = 44px (matches all other AR page buttons).
// Colors and states match path_overview_screen._preferenceButtonHorizontal exactly.
// ═══════════════════════════════════════════════════════════════════════════

class _ARPreferenceSelector
    extends StatelessWidget {
  final bool stairsAvailable;
  final bool elevatorAvailable;
  final bool escalatorAvailable;
  final String selected;
  final void Function(String) onTap;

  const _ARPreferenceSelector({
    required this.stairsAvailable,
    required this.elevatorAvailable,
    required this.escalatorAvailable,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CirclePreferenceButton(
          icon: Icons.stairs,
          label: 'Stairs',
          pref: 'stairs',
          available: stairsAvailable,
          selected:
              selected == 'stairs',
          onTap: () => onTap('stairs'),
        ),
        const SizedBox(height: 10),
        _CirclePreferenceButton(
          icon: Icons.elevator,
          label: 'Elevator',
          pref: 'elevator',
          available: elevatorAvailable,
          selected:
              selected == 'elevator',
          onTap: () =>
              onTap('elevator'),
        ),
        const SizedBox(height: 10),
        _CirclePreferenceButton(
          icon: Icons.escalator,
          label: 'Escalator',
          pref: 'escalator',
          available: escalatorAvailable,
          selected:
              selected == 'escalator',
          onTap: () =>
              onTap('escalator'),
        ),
      ],
    );
  }
}

// ── Single circle button with label below ────────────────────────────────
class _CirclePreferenceButton
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final String pref;
  final bool available;
  final bool selected;
  final VoidCallback onTap;

  const _CirclePreferenceButton({
    required this.icon,
    required this.label,
    required this.pref,
    required this.available,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Exactly matches path_overview_screen._preferenceButtonHorizontal states:
    final bool isDisabled = !available;
    final bool showAsSelected =
        selected && !isDisabled;

    // Colors from path_overview_screen
    final Color bgColor = showAsSelected
        ? const Color(
            0xFFE8E9E0,
          ) // selected bg — same as path_overview
        : Colors.white.withOpacity(
            0.85,
          ); // unselected — matches AR page buttons

    final Color borderColor =
        showAsSelected
        ? kGreen.withOpacity(
            0.30,
          ) // selected border — same as path_overview
        : Colors.transparent;

    final Color iconColor = isDisabled
        ? Colors
              .grey
              .shade400 // disabled — same as path_overview
        : showAsSelected
        ? kGreen // selected — same as path_overview
        : Colors
              .grey
              .shade500; // unselected — same as path_overview

    final Color labelColor = isDisabled
        ? Colors
              .grey
              .shade400 // disabled — same as path_overview
        : showAsSelected
        ? kGreen // selected — same as path_overview
        : Colors
              .grey
              .shade600; // unselected — same as path_overview

    final FontWeight labelWeight =
        showAsSelected
        ? FontWeight
              .w700 // selected bold — same as path_overview
        : FontWeight.w500;

    return Opacity(
      // Disabled = 45% opacity — exactly as path_overview
      opacity: isDisabled ? 0.45 : 1.0,
      child: GestureDetector(
        behavior:
            HitTestBehavior.opaque,
        // null when disabled — GestureDetector ignores null taps
        onTap: isDisabled
            ? null
            : onTap,
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            // Circle button — 44px to match back button / search button
            AnimatedContainer(
              duration: const Duration(
                milliseconds: 180,
              ),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                  width: 1.5,
                ),
                boxShadow:
                    showAsSelected
                    ? [
                        BoxShadow(
                          color: Colors
                              .black
                              .withOpacity(
                                0.08,
                              ),
                          blurRadius: 8,
                          offset:
                              const Offset(
                                0,
                                2,
                              ),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                size: 20,
                color: iconColor,
              ),
            ),

            const SizedBox(height: 4),

            // Label below circle
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: labelWeight,
                color: labelColor,
                // Subtle shadow so label is readable over AR camera feed
                shadows: [
                  Shadow(
                    color: Colors.black
                        .withOpacity(
                          0.25,
                        ),
                    blurRadius: 4,
                    offset:
                        const Offset(
                          0,
                          1,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
