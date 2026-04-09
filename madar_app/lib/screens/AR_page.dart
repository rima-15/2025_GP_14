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

  /// Added: shared navigation preference for both place navigation
  /// and friend navigation.
  /// Expected values: stairs / elevator / escalator / any / null
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

  String _normalizedPreference() {
    final pref =
        (widget.navigationPreference ??
                '')
            .trim()
            .toLowerCase();

    if (pref == 'stairs' ||
        pref == 'elevator' ||
        pref == 'escalator') {
      return pref;
    }

    // no preference => Unity should use normal shortest path
    return 'none';
  }

  // Resolve Firestore user docId by email (your model: users docId != uid)
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
    return snap
        .docs
        .first
        .id; // real Firestore docId
  }

  // Get a fresh Firebase Auth ID token
  Future<String?>
  _getFreshIdToken() async {
    final user = FirebaseAuth
        .instance
        .currentUser;
    if (user == null) return null;

    try {
      return await user.getIdToken(
        true,
      ); // force refresh
    } catch (e) {
      debugPrint(
        "❌ Failed to get ID token: $e",
      );
      return null;
    }
  }

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
        AppLifecycleState.resumed) {
      _sendHandshakeAndMode();
    }
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

  // 1) Send USER_DOC_ID
  // 2) Send ID_TOKEN
  // 3) Then send SCAN_ONLY / NAVIGATION / EXPLORE / NAVIGATE_TO_USER
  Future<void>
  _sendHandshakeAndMode() async {
    if (!_isUnityReady) return;

    _cachedUserDocId ??=
        await _resolveUserDocIdByEmail();
    if (_cachedUserDocId == null ||
        _cachedUserDocId!.isEmpty) {
      debugPrint(
        "❌ Could not resolve Firestore user docId. Ensure users has a document where email == currentUser.email",
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

    // Send USER_DOC_ID
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

    // Send ID_TOKEN
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

    // Send mode
    final String modeMessage;
    final pref =
        _normalizedPreference();

    if (widget.isFriendNavigation &&
        widget.friendX != null &&
        widget.friendY != null &&
        widget.friendZ != null &&
        widget.friendFloor != null) {
      // Encode name to avoid colons breaking the split
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

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(
      context,
    ).padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          EmbedUnity(
            onMessageFromUnity: (msg) {
              debugPrint(
                "Message from Unity: $msg",
              );
            },
          ),

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
        ],
      ),
    );
  }
}
