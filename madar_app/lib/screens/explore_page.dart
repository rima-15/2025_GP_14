import 'package:flutter/material.dart';
import 'package:madar_app/screens/category_page.dart'; // فيه kGreen
import 'package:madar_app/screens/unity_page.dart';
import 'package:permission_handler/permission_handler.dart';

class ExplorePage
    extends StatelessWidget {
  const ExplorePage({super.key});

  static const Color green = Color(
    0xFF787E65,
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(
              horizontal: 24,
            ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            // دائرة الأيقونة
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black
                    .withOpacity(0.04),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(
                          0.06,
                        ),
                    blurRadius: 10,
                    offset:
                        const Offset(
                          0,
                          4,
                        ),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons
                      .photo_camera_outlined,
                  size: 30,
                  color: green,
                ),
              ),
            ),
            const SizedBox(height: 28),

            // العنوان
            const Text(
              'Explore with AR',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                height: 1.2,
                fontWeight:
                    FontWeight.w800,
                color: kGreen,
              ),
            ),
            const SizedBox(height: 12),

            // الوصف
            Text(
              'Point your camera at your surroundings to discover points of interest and get real-time navigation.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 32),

            // زر فتح الكاميرا / Unity
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // نطلب صلاحية الكاميرا
                  final status =
                      await Permission
                          .camera
                          .request();

                  if (status
                      .isGranted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            UnityCameraPage(),
                      ),
                    );
                  } else if (status
                      .isPermanentlyDenied) {
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
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      green,
                  foregroundColor:
                      Colors.white,
                  padding:
                      const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                          14,
                        ),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Open Camera',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
