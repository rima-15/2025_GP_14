import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

class UnityCameraPage extends StatefulWidget {
  /// false = EXPLORE   ,  true = NAVIGATION
  final bool isNavigation;

  const UnityCameraPage({super.key, this.isNavigation = false});

  @override
  State<UnityCameraPage> createState() => _UnityCameraPageState();
}

class _UnityCameraPageState extends State<UnityCameraPage> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        final mode = widget.isNavigation ? "NAVIGATION" : "EXPLORE";
        debugPrint("Flutter: sending mode to Unity => $mode");
        sendToUnity("FlutterListener", "OnFlutterMessage", mode);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          EmbedUnity(
            onMessageFromUnity: (String data) {
              debugPrint('From Unity: $data');
            },
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
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
