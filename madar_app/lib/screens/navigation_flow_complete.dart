// ============================================================================
// NAVIGATION FLOW IMPLEMENTATION FOR SOLITAIRE VENUE
// ============================================================================

import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:madar_app/screens/AR_page.dart';
import 'package:permission_handler/permission_handler.dart';

// ============================================================================
// 1. TRIGGER: Navigation Arrow Click Handler
// ============================================================================

void showNavigationDialog(
  BuildContext context,
  String shopName,
  String shopId,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        NavigateToShopDialog(shopName: shopName, shopId: shopId),
  );
}

// ============================================================================
// 2. NAVIGATE TO SHOP DIALOG
// ============================================================================

class NavigateToShopDialog extends StatelessWidget {
  final String shopName;
  final String shopId;

  const NavigateToShopDialog({
    super.key,
    required this.shopName,
    required this.shopId,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header matched to "Set Your Location" style
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Navigate to $shopName',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 20 : 22,
                          fontWeight: FontWeight.w600,
                          color: AppColors.kGreen,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'First, set your starting point.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SecondaryButton(
              text: 'Pin on Map',
              icon: Icons.location_on_outlined,
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) =>
                      SetYourLocationDialog(shopName: shopName, shopId: shopId),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: PrimaryButton(
              text: 'Scan With Camera',
              icon: Icons.camera_alt_outlined,
              onPressed: () async {
                Navigator.pop(context);
                await _handleScanWithCamera(context, shopName, shopId);
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 35),
        ],
      ),
    );
  }

  Future<void> _handleScanWithCamera(
    BuildContext context,
    String shopName,
    String shopId,
  ) async {
    final status = await Permission.camera.request();

    if (!context.mounted) return;

    if (status.isGranted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const UnityCameraPage(isNavigation: true),
        ),
      );

      if (!context.mounted) return;

      if (result == true) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ARSuccessDialog(
            onOkPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => PathOverviewScreen(
                    shopName: shopName,
                    shopId: shopId,
                    startingMethod: 'scan',
                  ),
                ),
              );
            },
          ),
        );
      }
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission required. Please enable in Settings.',
          ),
        ),
      );
      openAppSettings();
    }
  }
}

class SetYourLocationDialog extends StatefulWidget {
  final String shopName;
  final String shopId;

  const SetYourLocationDialog({
    super.key,
    required this.shopName,
    required this.shopId,
  });

  @override
  State<SetYourLocationDialog> createState() => _SetYourLocationDialogState();
}

class _SetYourLocationDialogState extends State<SetYourLocationDialog> {
  String _currentFloorURL = '';
  List<Map<String, String>> _venueMaps = [];
  bool _mapsLoading = true;
  bool _pinPlaced = false;

  @override
  void initState() {
    super.initState();
    _loadVenueMaps();
  }

  Future<void> _loadVenueMaps() async {
    if (!mounted) return;
    setState(() => _mapsLoading = true);

    try {
      // Solitaire Place ID verified from your venue_page logic
      const String solitaireId = 'ChIJcYTQDwDjLj4RZEiboV6gZzM';

      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(solitaireId)
          .get(const GetOptions(source: Source.serverAndCache));

      final data = doc.data();

      if (data != null && data['map'] is List) {
        final maps = (data['map'] as List).cast<Map<String, dynamic>>();

        final convertedMaps = maps.map((m) {
          return {
            'floorNumber': (m['floorNumber'] ?? '').toString(),
            'mapURL': (m['mapURL'] ?? '').toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            if (convertedMaps.isNotEmpty) {
              _currentFloorURL = convertedMaps.first['mapURL'] ?? '';
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading maps in dialog: $e");
    } finally {
      if (mounted) setState(() => _mapsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.85,
        minHeight: 500,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set Your Location',
                        style: TextStyle(
                          fontSize: screenHeight < 700 ? 20 : 22,
                          fontWeight: FontWeight.w600,
                          color: AppColors.kGreen,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap on the map to place your pin.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildMapContent(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            child: PrimaryButton(
              text: 'Confirm Location',
              enabled: _pinPlaced,
              onPressed: _pinPlaced
                  ? () {
                      Navigator.pop(context);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PathOverviewScreen(
                            shopName: widget.shopName,
                            shopId: widget.shopId,
                            startingMethod: 'pin',
                          ),
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapContent() {
    if (_mapsLoading) {
      return const AppLoadingIndicator();
    }

    if (_venueMaps.isEmpty) {
      return const Center(child: Text("Map missing for Solitaire."));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 3D Model Viewer
            ModelViewer(
              key: ValueKey(_currentFloorURL),
              src: _currentFloorURL,
              alt: "Solitaire 3D Map",
              cameraControls: true,
              autoRotate: false,
              backgroundColor: Colors.transparent,
              cameraOrbit: "0deg 65deg 2.5m",
            ),

            // Tap Overlay
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                setState(() {
                  _pinPlaced = true;
                });
              },
              child: Container(color: Colors.transparent),
            ),

            // Floor Selectors
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  children: _venueMaps.map((map) {
                    final label = map['floorNumber'] ?? '';
                    final url = map['mapURL'] ?? '';
                    final isSelected = _currentFloorURL == url;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildFloorButton(label, url, isSelected),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Visual Pin Indicator
            if (_pinPlaced)
              IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 35),
                    child: Icon(
                      Icons.location_on,
                      color: AppColors.kError,
                      size: 50,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloorButton(String label, String url, bool isSelected) {
    return SizedBox(
      width: 44,
      height: 40,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? AppColors.kGreen : Colors.white,
          foregroundColor: isSelected ? Colors.white : AppColors.kGreen,
          padding: EdgeInsets.zero,
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? AppColors.kGreen : Colors.grey.shade300,
            ),
          ),
        ),
        onPressed: () => setState(() {
          _currentFloorURL = url;
          _pinPlaced = false;
        }),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ============================================================================
// 4. PATH OVERVIEW SCREEN - FIXED MAP VISIBILITY & CONSISTENT FLOOR SELECTORS
// ============================================================================

class PathOverviewScreen extends StatefulWidget {
  final String shopName;
  final String shopId;
  final String startingMethod;

  const PathOverviewScreen({
    super.key,
    required this.shopName,
    required this.shopId,
    required this.startingMethod,
  });

  @override
  State<PathOverviewScreen> createState() => _PathOverviewScreenState();
}

class _PathOverviewScreenState extends State<PathOverviewScreen> {
  String _currentFloor = '';
  List<Map<String, String>> _venueMaps = [];
  bool _mapsLoading = false;
  String _selectedPreference = 'stairs';
  String _estimatedTime = '2 min';
  String _estimatedDistance = '166 m';

  @override
  void initState() {
    super.initState();
    _loadVenueMaps();
  }

  // ---------- AR Navigation Functions ----------

  /// Check if place has world position for AR navigation
  Future<bool> _hasWorldPosition(String placeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('places')
          .doc(placeId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      // Check for worldPosition field
      return data.containsKey('worldPosition') && data['worldPosition'] != null;
    } catch (e) {
      debugPrint("Error checking world position: $e");
      return false;
    }
  }

  /// Show dialog when AR is not supported for this place
  void _showNoPositionDialog(String placeName) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogPadding = screenWidth < 360 ? 20.0 : 28.0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(dialogPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.kGreen.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.location_off_rounded,
                      size: 42,
                      color: AppColors.kGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'AR Not Supported',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.kGreen,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  'This place doesn\'t support AR navigation yet. Please check back later!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 24),

                // Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Open AR navigation with validation
  Future<void> _openNavigationAR() async {
    // Validate world position before proceeding
    final hasPosition = await _hasWorldPosition(widget.shopId);

    if (!hasPosition) {
      if (!mounted) return;
      _showNoPositionDialog(widget.shopName);
      return;
    }

    // Request camera permission
    final status = await Permission.camera.request();

    if (status.isGranted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              UnityCameraPage(isNavigation: true, placeId: widget.shopId),
        ),
      );
    } else if (status.isPermanentlyDenied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is permanently denied. Please enable it from Settings.',
          ),
        ),
      );
      openAppSettings();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to use AR.'),
        ),
      );
    }
  }

  Future<void> _loadVenueMaps() async {
    setState(() => _mapsLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc('ChIJcYTQDwDjLj4RZEiboV6gZzM') // Solitaire ID
          .get(const GetOptions(source: Source.serverAndCache));

      final data = doc.data();
      if (data != null && data['map'] is List) {
        final maps = (data['map'] as List).cast<Map<String, dynamic>>();
        final convertedMaps = maps.map((map) {
          return {
            'floorNumber': (map['floorNumber'] ?? '').toString(),
            'mapURL': (map['mapURL'] ?? '').toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            if (convertedMaps.isNotEmpty) {
              _currentFloor = convertedMaps.first['mapURL'] ?? '';
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading maps: $e");
    } finally {
      if (mounted) setState(() => _mapsLoading = false);
    }
  }

  void _changePreference(String preference) {
    setState(() {
      _selectedPreference = preference;
      if (preference == 'elevator') {
        _estimatedTime = '3 min';
        _estimatedDistance = '180 m';
      } else if (preference == 'escalator') {
        _estimatedTime = '2.5 min';
        _estimatedDistance = '170 m';
      } else {
        _estimatedTime = '2 min';
        _estimatedDistance = '166 m';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Stack(
          children: [
            // FULL SCREEN MAP - This ensures map is visible behind bottom panel
            Positioned.fill(
              child: _mapsLoading
                  ? const AppLoadingIndicator()
                  : ModelViewer(
                      key: ValueKey(_currentFloor),
                      src: _currentFloor,
                      alt: "3D Map",
                      cameraControls: true,
                      backgroundColor: const Color(0xFFF5F5F0),
                      cameraOrbit: "0deg 65deg 2.5m",
                    ),
            ),

            // Floor Selectors - Positioned on map
            Positioned(
              top: 220, // Below header
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  children: _venueMaps.map((map) {
                    final label = map['floorNumber'] ?? '';
                    final url = map['mapURL'] ?? '';
                    final isSelected = _currentFloor == url;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildFloorButton(label, url, isSelected),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Header Container - Overlays on top of map
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(10, 20, 20, 16),
                child: Column(
                  children: [
                    // Location rows with back button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: AppColors.kGreen,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              // Origin Row
                              _locationRow(
                                Icons.radio_button_checked,
                                'Your location',
                                'GF',
                                const Color(0xFF6C6C6C),
                              ),

                              // Dotted Line
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    height: 15,
                                    width: 2,
                                    child: Column(
                                      children: List.generate(
                                        3,
                                        (index) => Expanded(
                                          child: Container(
                                            width: 1.5,
                                            color: index % 2 == 0
                                                ? Colors.grey[400]
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Destination Row
                              _locationRow(
                                Icons.location_on,
                                widget.shopName,
                                'F1',
                                const Color(0xFFC88D52),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Preference buttons row - HORIZONTAL LAYOUT (icon + text)
                    Row(
                      children: [
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Stairs',
                            Icons.stairs,
                            'stairs',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Elevator',
                            Icons.elevator,
                            'elevator',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _preferenceButtonHorizontal(
                            'Escalator',
                            Icons.escalator_warning,
                            'escalator',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom UI Panel - Overlays on map with proper transparency
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Time and Distance Info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_estimatedTime ($_estimatedDistance)',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.shopName,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Divider
                    Divider(color: Colors.grey[300], thickness: 1, height: 1),

                    const SizedBox(height: 20),

                    // Start AR Navigation Button
                    PrimaryButton(
                      text: 'Start AR Navigation',
                      onPressed: _openNavigationAR,
                    ),

                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(IconData icon, String label, String floor, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 25,
          child: Text(
            floor,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[300],
            ),
          ),
        ),
      ],
    );
  }

  // Horizontal preference button (icon next to text)
  Widget _preferenceButtonHorizontal(
    String label,
    IconData icon,
    String value,
  ) {
    final isSelected = _selectedPreference == value;
    return GestureDetector(
      onTap: () => _changePreference(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8E9E0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.kGreen : Colors.grey[500],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? AppColors.kGreen : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // CONSISTENT FLOOR BUTTON - Same as Set Your Location dialog
  Widget _buildFloorButton(String label, String url, bool isSelected) {
    return SizedBox(
      width: 44,
      height: 40,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? AppColors.kGreen : Colors.white,
          foregroundColor: isSelected ? Colors.white : AppColors.kGreen,
          padding: EdgeInsets.zero,
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? AppColors.kGreen : Colors.grey.shade300,
            ),
          ),
        ),
        onPressed: () => setState(() {
          _currentFloor = url;
        }),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ============================================================================
// 5. AR SUCCESS DIALOG
// ============================================================================

class ARSuccessDialog extends StatelessWidget {
  final VoidCallback onOkPressed;

  const ARSuccessDialog({super.key, required this.onOkPressed});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.kGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.kGreen,
                size: 50,
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Success!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'Your location has been detected. You will now be taken to the Path Overview screen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: onOkPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
