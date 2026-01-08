import 'package:flutter/material.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'track_request_dialog.dart';

// ----------------------------------------------------------------------------
// Track Page
// ----------------------------------------------------------------------------

// Toggle this for Release 2
const bool kFeatureEnabled = true;

// Solitaire venue ID for loading the 3D map
const String kSolitaireVenueId = 'ChIJ_WZ_Y1iXwxUR_U6jcP83SIg';

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  // Sample data for full feature (Release 2)
  final List<Participant> meetingParticipants = [
    Participant(
      name: 'Alex Chen',
      status: 'On the way - 2 mins ago',
      isHost: false,
    ),
    Participant(name: 'Sarah Kim', status: 'Arrived - Just now', isHost: false),
    Participant(
      name: 'Jordan Martinez',
      status: 'On the way - 8 mins ago',
      isHost: false,
    ),
  ];

  final List<TrackingUser> trackingUsers = [
    TrackingUser(name: 'Mike Johnson', lastSeen: '5 mins ago'),
    TrackingUser(name: 'Emma Davis', lastSeen: '1 min ago'),
    TrackingUser(name: 'Ryan Foster', lastSeen: '12 mins ago'),
  ];

  // For the host/current user
  final String currentUserName = 'Ahmed Hassan';
  bool isArrived = false;

  // View mode toggle
  bool _isTrackingView = true; // false = Meeting Point, true = Tracking

  // 3D Map data
  String _currentFloor = '';
  List<Map<String, String>> _venueMaps = [];
  bool _mapsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadVenueMaps();
  }

  // ---------- Load 3D Maps from Solitaire Venue ----------

  Future<void> _loadVenueMaps() async {
    setState(() => _mapsLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(kSolitaireVenueId)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));

      final data = doc.data();
      debugPrint('Venue data loaded: ${data != null}');
      debugPrint('Map field exists: ${data?['map'] != null}');
      debugPrint('Map is List: ${data?['map'] is List}');

      if (data != null && data['map'] is List) {
        final maps = (data['map'] as List).cast<Map<String, dynamic>>();
        debugPrint('Number of maps: ${maps.length}');

        final convertedMaps = maps.map((map) {
          final floorNumber = (map['floorNumber'] ?? '').toString();
          final mapURL = (map['mapURL'] ?? '').toString();
          debugPrint('Floor: $floorNumber, URL: $mapURL');
          return {'floorNumber': floorNumber, 'mapURL': mapURL};
        }).toList();

        if (mounted) {
          setState(() {
            _venueMaps = convertedMaps;
            if (convertedMaps.isNotEmpty) {
              final firstMapURL = convertedMaps.first['mapURL'];
              if (firstMapURL != null && firstMapURL.isNotEmpty) {
                _currentFloor = firstMapURL;
                debugPrint('Set current floor to: $_currentFloor');
              }
            }
          });
        }
      } else {
        debugPrint('Map data not found, using fallback');
        _useFallbackMaps();
      }
    } catch (e) {
      debugPrint('Error loading venue maps: $e');
      _useFallbackMaps();
    } finally {
      if (mounted) {
        setState(() => _mapsLoading = false);
      }
    }
  }

  // Fallback maps in case Firestore fails
  void _useFallbackMaps() {
    // These are example URLs - you should replace with actual Solitaire 3D map URLs
    final fallbackMaps = [
      {
        'floorNumber': 'GF',
        'mapURL':
            'https://firebasestorage.googleapis.com/v0/b/madar-database.firebasestorage.app/o/3D%20Maps%2FSolitaire%2FGF.glb?alt=media',
      },
      {
        'floorNumber': 'F1',
        'mapURL':
            'https://firebasestorage.googleapis.com/v0/b/madar-database.firebasestorage.app/o/3D%20Maps%2FSolitaire%2FF1.glb?alt=media',
      },
      {
        'floorNumber': 'F2',
        'mapURL':
            'https://firebasestorage.googleapis.com/v0/b/madar-database.firebasestorage.app/o/3D%20Maps%2FSolitaire%2FF2.glb?alt=media',
      },
    ];

    if (mounted) {
      setState(() {
        _venueMaps = fallbackMaps;
        if (fallbackMaps.isNotEmpty) {
          _currentFloor = fallbackMaps.first['mapURL'] ?? '';
        }
      });
    }
  }

  // ---------- Show Track Request Dialog ----------

  void _showTrackRequestDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TrackRequestDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: kFeatureEnabled ? _buildFullContent() : _buildComingSoon(),
      ),
    );
  }

  // ---------- Coming Soon Placeholder ----------

  Widget _buildComingSoon() {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_outlined,
            size: isSmallScreen ? 80 : 96,
            color: AppColors.kGreen,
          ),
          const SizedBox(height: 16),
          Text(
            'Coming soon',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isSmallScreen ? 22 : 26,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ---------- Full Content (Release 2) ----------

  Widget _buildFullContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // View Toggle Switch
        _buildViewToggle(),
        const SizedBox(height: 20),

        // Map Preview with floor selector
        _buildMapPreview(),
        const SizedBox(height: 16),

        // Action Buttons - Different based on view mode
        if (!_isTrackingView) ...[
          // Meeting Point View - Shows both buttons
          Row(
            children: [
              Expanded(
                flex: 3, // Takes 60% of the space
                child: _pillButton(
                  icon: Icons.place_outlined,
                  label: 'Create Meeting Point',
                  onTap: () {
                    // TODO: Implement create meeting point
                  },
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 20),

          // Meeting Point Participants Section Header
          _buildSectionHeader(
            icon: Icons.place_outlined,
            title: 'Meeting Point Participants',
            subtitle: 'Active meeting point',
            count: meetingParticipants.length + 1, // +1 for host
          ),
          const SizedBox(height: 12),

          // Host (Current User) Card
          _buildHostCard(),
          const SizedBox(height: 8),

          // Meeting Participants
          for (final p in meetingParticipants) ...[
            _buildParticipantTile(p),
            const SizedBox(height: 8),
          ],
        ] else ...[
          // Tracking View - Shows only Track Request button
          _pillButton(
            icon: Icons.person_search_outlined,
            label: 'Track Request',
            onTap: _showTrackRequestDialog,
          ),
          const SizedBox(height: 20),

          // Tracking Users Section Header
          _buildSectionHeader(
            icon: Icons.access_time,
            title: 'Tracking Users',
            subtitle: 'Location sharing active',
            count: trackingUsers.length,
          ),
          const SizedBox(height: 12),

          // Tracking Users
          for (final u in trackingUsers) ...[
            _buildTrackingUserTile(u),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  // ---------- View Toggle Switch ----------

  Widget _buildViewToggle() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _toggleButton(
              label: 'Tracking',
              isSelected: _isTrackingView,
              onTap: () => setState(() => _isTrackingView = true),
            ),
          ),
          Expanded(
            child: _toggleButton(
              label: 'Meeting Point',
              isSelected: !_isTrackingView,
              onTap: () => setState(() => _isTrackingView = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.kGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  // ---------- Map Preview with 3D Model Viewer ----------

  Widget _buildMapPreview() {
    if (_mapsLoading) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: AppColors.kGreen,
                backgroundColor: AppColors.kGreen.withOpacity(0.2),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading 3D map...',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_venueMaps.isEmpty || _currentFloor.isEmpty) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No 3D map available',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 3D Model Viewer
            ModelViewer(
              key: ValueKey(_currentFloor),
              src: _currentFloor,
              alt: "3D Floor Map",
              ar: false,
              autoRotate: false,
              cameraControls: true,
              backgroundColor: const Color(0xFFF5F5F0),
              cameraOrbit: "0deg 65deg 2.5m",
              minCameraOrbit: "auto 0deg auto",
              maxCameraOrbit: "auto 90deg auto",
              cameraTarget: "0m 0m 0m",
            ),

            // Vertical floor selector buttons (top-right)
            if (_venueMaps.length > 1)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: _venueMaps.map((map) {
                      final floorNumber = map['floorNumber'] ?? '';
                      final mapURL = map['mapURL'] ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _floorButton(floorNumber, mapURL),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // People count indicator (top-left)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 18,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${meetingParticipants.length + 1}', // +1 for host
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _floorButton(String label, String mapURL) {
    bool isSelected = _currentFloor == mapURL;

    return SizedBox(
      width: 44,
      height: 38,
      child: ElevatedButton(
        onPressed: () {
          setState(() => _currentFloor = mapURL);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? AppColors.kGreen : Colors.white,
          foregroundColor: isSelected ? Colors.white : AppColors.kGreen,
          padding: EdgeInsets.zero,
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected ? AppColors.kGreen : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ---------- Section Header ----------

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.kGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 14, color: Colors.grey[700]),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Host Card ----------

  Widget _buildHostCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.kGreen.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.kGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          currentUserName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _roleChip('Host'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Now',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      isArrived = true;
                    });
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Arrived'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.kError, width: 2),
                    foregroundColor: AppColors.kError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Participant Tile ----------

  Widget _buildParticipantTile(Participant p) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 22),
          ),
          title: Text(
            p.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            p.status,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          trailing: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.black45,
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Refresh Location Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Tracking User Tile ----------

  Widget _buildTrackingUserTile(TrackingUser u) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 22),
          ),
          title: Text(
            u.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            u.lastSeen,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          trailing: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.black45,
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Refresh Location Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.navigation_outlined, size: 20),
              label: const Text('Set Friend as Destination'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.kGreen,
                side: const BorderSide(color: AppColors.kGreen, width: 2),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI Helpers ----------

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.kGreen, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.kGreen,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.kGreen, width: 2),
          shape: shape,
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: Colors.white,
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.kGreen,
        foregroundColor: Colors.white,
        shape: shape,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _roleChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.kGreen.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.kGreen,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Models
// ----------------------------------------------------------------------------

class Participant {
  final String name;
  final String status;
  final bool isHost;

  Participant({required this.name, required this.status, this.isHost = false});
}

class TrackingUser {
  final String name;
  final String lastSeen;

  TrackingUser({required this.name, required this.lastSeen});
}
