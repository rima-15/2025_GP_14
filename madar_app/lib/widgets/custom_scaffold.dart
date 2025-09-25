import 'package:flutter/material.dart';

class CustomScaffold
    extends StatelessWidget {
  final Widget? child;
  final bool showLogo;
  final String logoPath;

  const CustomScaffold({
    super.key,
    this.child,
    this.showLogo = false,
    this.logoPath =
        'images/MadarLogoEnglish.png',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        backgroundColor:
            Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Image.asset(
            'images/solitaireCopy.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),

          SafeArea(
            child: Column(
              children: [
                if (showLogo) ...[
                  Image.asset(
                    logoPath,
                    height: 65,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                ],
                Expanded(
                  child:
                      child ??
                      const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
