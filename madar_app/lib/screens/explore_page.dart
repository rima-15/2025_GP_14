import 'package:flutter/material.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:permission_handler/permission_handler.dart';

// ----------------------------------------------------------------------------
// Explore Page
// ----------------------------------------------------------------------------

/// AR exploration page with camera access
class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.horizontalPadding(context),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon circle
            Container(
              width: isSmallScreen ? 64 : 72,
              height: isSmallScreen ? 64 : 72,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: isSmallScreen ? 26 : 30,
                  color: AppColors.kGreen,
                ),
              ),
            ),
            SizedBox(height: isSmallScreen ? 22 : 28),

            // Title
            Text(
              'Explore with AR',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isSmallScreen ? 22 : 26,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: AppColors.kGreen,
              ),
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              'Point your camera at your surroundings to discover points of interest and get real-time navigation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 15,
                height: 1.45,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: isSmallScreen ? 26 : 32),

            // Open Camera Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _openCamera(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.buttonVerticalPadding,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.buttonRadius,
                    ),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Open Camera',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 15 : 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Camera Permission & Navigation ----------

  Future<void> _openCamera(BuildContext context) async {
    final status = await Permission.camera.request();

    if (!context.mounted) return;

    if (status.isGranted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const UnityCameraPage(isNavigation: false),
        ),
      );
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is permanently denied. Please enable it from Settings.',
          ),
        ),
      );
      openAppSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to use AR.'),
        ),
      );
    }
  }
}
