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

  const UnityCameraPage({
    super.key,
    this.isNavigation = false,
    this.placeId,
    this.isScanOnly = false,
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

  String?
  _cachedUserDocId; // ✅ نخزنها عشان ما نسوي query كل مرة

  // --------------------------------------------------------------------------
  // ✅ Resolve Firestore user docId (your model: users docId is NOT uid)
  // --------------------------------------------------------------------------
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
        .id; // ✅ real Firestore docId
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
      _sendHandshakeAndMode(); // ✅ resend when coming back
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

    // Wait for Unity to initialize
    await Future.delayed(
      const Duration(milliseconds: 600),
    );

    // Mark as ready BEFORE sending (so future calls won't skip)
    if (mounted) {
      setState(() {
        _isUnityReady = true;
        _statusMessage =
            widget.isNavigation
            ? "Starting navigation..."
            : (widget.isScanOnly
                  ? "Scanning location..."
                  : "AR Ready");
      });
    }

    await _sendHandshakeAndMode();
  }

  // --------------------------------------------------------------------------
  // ✅ 1) Send USER_DOC_ID
  // ✅ 2) Then send SCAN_ONLY / NAVIGATION / EXPLORE
  // --------------------------------------------------------------------------
  Future<void>
  _sendHandshakeAndMode() async {
    if (!_isUnityReady) return;

    // 1) Resolve docId once (cache)
    _cachedUserDocId ??=
        await _resolveUserDocIdByEmail();

    if (_cachedUserDocId == null ||
        _cachedUserDocId!.isEmpty) {
      debugPrint(
        "❌ Could not resolve Firestore user docId (users docId is not uid). "
        "Make sure users collection has a document with field email == currentUser.email",
      );
      // هنا نوقف: لا نرسل وضع التشغيل لأن Unity ما يعرف يكتب فين
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

    // small delay so Unity receives docId before mode
    await Future.delayed(
      const Duration(milliseconds: 150),
    );

    // 2) Send mode
    final String modeMessage;
    if (widget.isNavigation &&
        widget.placeId != null &&
        widget.placeId!.isNotEmpty) {
      modeMessage =
          "NAVIGATION:${widget.placeId}";
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
        "❌ Failed to send mode message to Unity: $e",
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
