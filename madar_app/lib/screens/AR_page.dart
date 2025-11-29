import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Unity Camera Page - AR experience using Unity
// ----------------------------------------------------------------------------

class UnityCameraPage extends StatefulWidget {
  final bool isNavigation;
  final String? placeId;

  const UnityCameraPage({super.key, this.isNavigation = false, this.placeId});

  @override
  State<UnityCameraPage> createState() => _UnityCameraPageState();
}

class _UnityCameraPageState extends State<UnityCameraPage>
    with WidgetsBindingObserver {
  // Track Unity initialization state
  bool _isUnityReady = false;
  String _statusMessage = "Initializing AR...";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeUnity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Handle app lifecycle changes (when returning from another page)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App resumed - send mode message again
      _sendModeMessage();
    }
  }

  // Detect when this widget becomes visible again (after popping another page)
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // If Unity is already ready and we're becoming visible again, resend message
    if (_isUnityReady && ModalRoute.of(context)?.isCurrent == true) {
      // Small delay to ensure Unity is ready to receive
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _sendModeMessage();
        }
      });
    }
  }

  // Initialize Unity with proper timing
  void _initializeUnity() async {
    setState(() {
      _statusMessage = "Loading AR environment...";
    });

    // Wait for Unity to initialize
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

  // Send mode message to Unity (can be called multiple times)
  void _sendModeMessage() {
    String message;

    if (widget.isNavigation &&
        widget.placeId != null &&
        widget.placeId!.isNotEmpty) {
      // Send navigation message with placeId
      message = "NAVIGATION:${widget.placeId}";
    } else {
      // Send exploration message
      message = "EXPLORE";
    }

    // Send message to Unity
    try {
      sendToUnity("FlutterListener", "OnFlutterMessage", message);
    } catch (e) {
      debugPrint("Failed to send message to Unity: $e");
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    // Responsive back button position
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Unity View
          EmbedUnity(
            onMessageFromUnity: (msg) {
              debugPrint("Message from Unity: $msg");
            },
          ),

          // Loading overlay (shown until Unity is ready)
          if (!_isUnityReady)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kGreen),
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
            top: topPadding + 12,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: kGreen, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
