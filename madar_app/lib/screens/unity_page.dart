import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

class UnityCameraPage extends StatefulWidget {
  final bool isNavigation;
  final String? placeId; // NEW: placeId for navigation mode

  const UnityCameraPage({
    super.key,
    this.isNavigation = false,
    this.placeId, // NEW: receive placeId from navigation
  });

  @override
  State<UnityCameraPage> createState() => _UnityCameraPageState();
}

class _UnityCameraPageState extends State<UnityCameraPage>
    with WidgetsBindingObserver {
  // NEW: Track Unity initialization state
  bool _isUnityReady = false;
  String _statusMessage = "Initializing AR...";

  @override
  void initState() {
    super.initState();

    // NEW: Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // NEW: Start Unity initialization sequence
    _initializeUnity();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ✅ NEW: Handle app lifecycle changes (when returning from another page)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App resumed - send mode message again
      debugPrint("═══════════════════════════════════════════════════");
      debugPrint("🔄 [FLUTTER] App resumed - resending mode message");
      debugPrint("═══════════════════════════════════════════════════");
      _sendModeMessage();
    }
  }

  // ✅ NEW: Detect when this widget becomes visible again (after popping another page)
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // If Unity is already ready and we're becoming visible again, resend message
    if (_isUnityReady && ModalRoute.of(context)?.isCurrent == true) {
      debugPrint("═══════════════════════════════════════════════════");
      debugPrint("🔄 [FLUTTER] Page became active - resending mode message");
      debugPrint("═══════════════════════════════════════════════════");

      // Small delay to ensure Unity is ready to receive
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _sendModeMessage();
        }
      });
    }
  }

  // NEW: Initialize Unity with proper timing and logging
  void _initializeUnity() async {
    debugPrint("═══════════════════════════════════════════════════");
    debugPrint("🚀 [FLUTTER → UNITY] Unity page opened");
    debugPrint(
      "   Mode: ${widget.isNavigation ? 'NAVIGATION' : 'EXPLORATION'}",
    );

    if (widget.isNavigation) {
      debugPrint(
        "   Place ID: ${widget.placeId ?? 'NULL'}",
      ); // NEW: Log placeId
    }

    debugPrint("═══════════════════════════════════════════════════");

    // Wait for Unity to initialize (600ms as in your original code)
    setState(() {
      _statusMessage = "Loading AR environment...";
    });

    await Future.delayed(const Duration(milliseconds: 600));

    // Send initial mode message
    _sendModeMessage();

    setState(() {
      _isUnityReady = true;
      _statusMessage = widget.isNavigation
          ? "Starting navigation..."
          : "AR Ready";
    });
  }

  // ✅ NEW: Extracted method to send mode message (can be called multiple times)
  void _sendModeMessage() {
    // Prepare message based on mode
    String message;

    if (widget.isNavigation &&
        widget.placeId != null &&
        widget.placeId!.isNotEmpty) {
      // UPDATED: Send navigation message with placeId
      message = "NAVIGATION:${widget.placeId}";

      debugPrint("📤 [FLUTTER → UNITY] Sending navigation request:");
      debugPrint("   Message: $message");
      debugPrint("   PlaceID: ${widget.placeId}");
    } else {
      // Send exploration message
      message = "EXPLORE";

      debugPrint("📤 [FLUTTER → UNITY] Sending exploration request:");
      debugPrint("   Message: $message");
    }

    // Send message to Unity
    try {
      sendToUnity("FlutterListener", "OnFlutterMessage", message);

      debugPrint("✅ [FLUTTER → UNITY] Message sent successfully");
      debugPrint("   Target: FlutterListener.OnFlutterMessage");
      debugPrint("   Content: $message");
    } catch (e) {
      // NEW: Error handling with logging
      debugPrint("❌ [FLUTTER → UNITY] Failed to send message:");
      debugPrint("   Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Unity View
          EmbedUnity(
            onMessageFromUnity: (msg) {
              // NEW: Enhanced logging for Unity messages
              debugPrint("═══════════════════════════════════════════════════");
              debugPrint("📥 [UNITY → FLUTTER] Message received:");
              debugPrint("   Content: $msg");
              debugPrint("═══════════════════════════════════════════════════");
            },
          ),

          // NEW: Loading indicator overlay (shown until Unity is ready)
          if (!_isUnityReady)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF787E65),
                      ),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Back button (always visible)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: GestureDetector(
              onTap: () {
                // NEW: Log when user closes Unity
                debugPrint("🔙 [FLUTTER] User closed Unity AR page");
                Navigator.pop(context);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF787E65),
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
