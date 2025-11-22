import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

class UnityCameraPage
    extends StatefulWidget {
  /// false = EXPLORE   ,  true = NAVIGATION
  final bool isNavigation;

  /// 📌 جديد — placeId اللي نرسله ليونتي
  final String? destinationPlaceId;

  const UnityCameraPage({
    super.key,
    this.isNavigation = false,
    this.destinationPlaceId,
  });

  @override
  State<UnityCameraPage>
  createState() =>
      _UnityCameraPageState();
}

class _UnityCameraPageState
    extends State<UnityCameraPage> {
  bool _sentDestination =
      false; // نتأكد ما نكرر الإرسال

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((
      _,
    ) {
      Future.delayed(
        const Duration(
          milliseconds: 800,
        ),
        () {
          final mode =
              widget.isNavigation
              ? "NAVIGATION"
              : "EXPLORE";
          debugPrint(
            "Flutter ➜ Unity | sending mode = $mode",
          );

          sendToUnity(
            "FlutterListener", // GameObject
            "OnFlutterMessage", // Method inside Unity
            mode, // Parameter
          );
        },
      );
    });
  }

  void _handleUnityMessage(String msg) {
    debugPrint("From Unity: $msg");

    // 🚩 Unity يخبرنا أن المشهد جاهز
    if (msg == "scene_loaded" &&
        widget.isNavigation &&
        widget.destinationPlaceId !=
            null &&
        !_sentDestination) {
      _sentDestination = true;

      sendToUnity(
        "SharedPOIManager", // نفس اللي فيه JumpToPOIByPlaceId
        "JumpToPOIByPlaceId", // الميثود
        widget
            .destinationPlaceId!, // placeId من Flutter
      );

      debugPrint(
        "🚀 Flutter ➜ Unity | sent placeId (${widget.destinationPlaceId}) for navigation",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          EmbedUnity(
            onMessageFromUnity:
                _handleUnityMessage,
          ),

          Positioned(
            top:
                MediaQuery.of(
                  context,
                ).padding.top +
                12,
            left: 16,
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
                            0.8,
                          ),
                      shape: BoxShape
                          .circle,
                    ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(
                    0xFF787E65,
                  ),
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
