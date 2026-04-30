import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/screens/home_page.dart';
import 'package:madar_app/screens/explore_page.dart';
import 'package:madar_app/screens/track_page.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/screens/profile_page.dart';
import 'package:madar_app/screens/settings_page.dart';
import 'package:madar_app/screens/notifications_page.dart';
import 'package:madar_app/screens/history_page.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'package:madar_app/services/gps_tracking_service.dart';
import 'package:madar_app/services/notification_preferences_service.dart';
import 'package:madar_app/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:madar_app/screens/help_support_page.dart';
import 'package:madar_app/screens/favorite_friends_page.dart';

// ----------------------------------------------------------------------------
// Main Layout
// ----------------------------------------------------------------------------

/// Main app layout with bottom navigation and drawer
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  int _index = 0;
  final _homeKey = GlobalKey<HomePageState>();

  // Track page parameters from notification navigation
  String? _trackExpandRequestId;
  int? _trackFilterIndex;
  String? _meetingPointExpandId;

  // GPS tracking service subscription
  StreamSubscription<QuerySnapshot>? _activeTrackingSub;
  StreamSubscription<QuerySnapshot>? _activeMeetingPointSub;

  Timer? _gpsPeriodicTimer;
  bool _hasActiveTrackingRequest = false;

  late final pages = <Widget>[
    HomePage(key: _homeKey),
    const ExplorePage(),
    _buildTrackPage(),
  ];

  Widget _buildTrackPage() {
    return TrackPage(
      key: ValueKey(
        'track_${_trackExpandRequestId ?? 'default'}_${_meetingPointExpandId ?? 'meeting'}',
      ),
      initialExpandRequestId: _trackExpandRequestId,
      initialFilterIndex: _trackFilterIndex,
      initialMeetingPointId: _meetingPointExpandId,
    );
  }

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _listenForActiveTrackingRequests();
    _listenForActiveMeetingPoints();
    unawaited(_syncNotificationPreferencesWithSystem());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncNotificationPreferencesWithSystem());
    }
  }

  // ---------- GPS Tracking Service ──────────────────────────────────────────

  /// Listens for active accepted tracking requests where the current user
  /// is the RECEIVER (being tracked). Starts GPS service if any exist,
  /// stops it otherwise.
  /// We upload OUR GPS so the tracker can see if we left the venue.
  ///
  void _startGpsPeriodicUpdates() {
    _gpsPeriodicTimer?.cancel();

    _gpsPeriodicTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!_hasActiveTrackingRequest) return;

      debugPrint('[GPS-UI] periodic 5-min tick -> uploadGps()');
      await GpsTrackingService.uploadGps();
    });
  }

  void _stopGpsPeriodicUpdates() {
    _gpsPeriodicTimer?.cancel();
    _gpsPeriodicTimer = null;
  }

  void _listenForActiveTrackingRequests() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final email = FirebaseAuth.instance.currentUser?.email;

    debugPrint('================ GPS DEBUG START ================');
    debugPrint('[GPS-CHECK] MainLayout listener started');
    debugPrint('[GPS-CHECK] auth uid   = $uid');
    debugPrint('[GPS-CHECK] auth email = $email');

    if (uid == null) {
      debugPrint('[GPS-CHECK] currentUser.uid is NULL -> stop');
      debugPrint('=================================================');
      return;
    }

    _activeTrackingSub?.cancel();

    _activeTrackingSub = FirebaseFirestore.instance
        .collection('trackRequests')
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen(
          (snap) async {
            debugPrint('---------------- GPS SNAPSHOT ----------------');
            debugPrint('[GPS-CHECK] docs count = ${snap.docs.length}');
            debugPrint('[GPS-CHECK] snapshot empty = ${snap.docs.isEmpty}');

            final now = Timestamp.now();
            debugPrint('[GPS-CHECK] now = ${now.toDate()}');

            bool hasActive = false;

            for (final doc in snap.docs) {
              final data = doc.data();

              final receiverId = data['receiverId'];
              final senderId = data['senderId'];
              final status = data['status'];
              final venueId = data['venueId'];
              final endAtRaw = data['endAt'];

              debugPrint('----------------------------------------------');
              debugPrint('[GPS-CHECK] request doc id = ${doc.id}');
              debugPrint('[GPS-CHECK] receiverId     = $receiverId');
              debugPrint('[GPS-CHECK] senderId       = $senderId');
              debugPrint('[GPS-CHECK] status         = $status');
              debugPrint('[GPS-CHECK] venueId        = $venueId');
              debugPrint(
                '[GPS-CHECK] endAt raw type = ${endAtRaw.runtimeType}',
              );
              debugPrint('[GPS-CHECK] endAt raw      = $endAtRaw');

              if (endAtRaw is Timestamp) {
                final endAt = endAtRaw.toDate();
                final isFuture = endAtRaw.compareTo(now) > 0;

                debugPrint('[GPS-CHECK] endAt parsed  = $endAt');
                debugPrint('[GPS-CHECK] endAt > now   = $isFuture');

                if (isFuture) {
                  hasActive = true;
                }
              } else {
                debugPrint('[GPS-CHECK] endAt is NOT Timestamp');
              }
            }

            debugPrint('[GPS-CHECK] FINAL hasActive = $hasActive');

            if (hasActive) {
              _hasActiveTrackingRequest = true;

              debugPrint(
                '[GPS-CHECK] Found active request -> saving user doc id',
              );
              await _saveUserDocIdForGpsDebug();

              // ارفعي GPS مباشرة فور اكتشاف الطلب المقبول
              debugPrint('[GPS-CHECK] Immediate uploadGps() from UI isolate');
              await GpsTrackingService.uploadGps();

              // شغلي الخدمة كنسخة احتياطية
              debugPrint('[GPS-CHECK] Calling GpsTrackingService.start()');
              await GpsTrackingService.start();

              // وابدئي التحديث كل 5 دقائق طالما التطبيق مفتوح
              _startGpsPeriodicUpdates();
            } else {
              _hasActiveTrackingRequest = false;

              debugPrint('[GPS-CHECK] No active request -> calling stop()');

              _stopGpsPeriodicUpdates();
              await GpsTrackingService.stop();
            }

            debugPrint('----------------------------------------------');
          },
          onError: (e) {
            debugPrint('[GPS-CHECK] STREAM ERROR: $e');
          },
        );
  }

  Future<void> _saveUserDocIdForGpsDebug() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      debugPrint('============= SAVE USER DOC ID DEBUG =============');
      debugPrint('[GPS] current auth uid   = ${user?.uid}');
      debugPrint('[GPS] current auth email = ${user?.email}');

      if (user == null) {
        debugPrint('[GPS] user is NULL -> stop');
        debugPrint('==================================================');
        return;
      }

      if (user.email == null) {
        debugPrint('[GPS] user.email is NULL -> stop');
        debugPrint('==================================================');
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(5)
          .get();

      debugPrint('[GPS] users query docs count = ${snap.docs.length}');

      if (snap.docs.isEmpty) {
        debugPrint('[GPS] No user doc found by email');
        debugPrint('==================================================');
        return;
      }

      for (final doc in snap.docs) {
        debugPrint('[GPS] matched user doc id = ${doc.id}');
        debugPrint('[GPS] matched user data   = ${doc.data()}');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gps_user_doc_id', snap.docs.first.id);

      debugPrint('[GPS] Saved docId: ${snap.docs.first.id}');

      final saved = prefs.getString('gps_user_doc_id');
      debugPrint('[GPS] Read-back docId from prefs: $saved');
      debugPrint('==================================================');
    } catch (e) {
      debugPrint('[GPS] Failed to save docId: $e');
      debugPrint('==================================================');
    }
  }

  void _listenForActiveMeetingPoints() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _activeMeetingPointSub?.cancel();

    _activeMeetingPointSub = FirebaseFirestore.instance
        .collection('meetingPoints')
        .where('participantUserIds', arrayContains: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snap) async {
          for (final doc in snap.docChanges) {
            final data = doc.doc.data();
            if (data == null) continue;
            final tokens = data['locationRefreshTokens'];
            if (tokens is Map && tokens.containsKey(uid)) {
              await GpsTrackingService.uploadGps();
              break;
            }
          }
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeTrackingSub?.cancel();
    _activeMeetingPointSub?.cancel();
    _gpsPeriodicTimer?.cancel();
    super.dispose();
  }

  // ---------- Data Loading ----------

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _firstName = data['firstName'] ?? '';
          });
        }
      } catch (e) {
        debugPrint('Error loading user data: $e');
      }
    }
  }

  Future<void> _syncNotificationPreferencesWithSystem() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final status = await NotificationService.getAuthorizationStatus();
      if (!NotificationService.isPermissionBlocked(status)) return;

      await NotificationPreferencesService.disableInAppNotifications(uid);
    } catch (e) {
      debugPrint('Failed to sync notification system state: $e');
    }
  }

  Future<void> _removeFcmTokenOnLogout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });

    // زيادة أمان
    await FirebaseMessaging.instance.deleteToken();
  }

  // ---------- Actions ----------

  Future<void> _logout(BuildContext context) async {
    final confirmed = await ConfirmationDialog.showPositiveConfirmation(
      context,
      title: 'Log out',
      message: 'Are you sure you want to log out?',
      confirmText: 'Log out',
    );

    if (!confirmed) return;

    await _removeFcmTokenOnLogout(); // <<< أول شيء
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    }
  }

  //Notification read or not
  void _openMenu() => _scaffoldKey.currentState?.openDrawer();
  //count unread notifications
  Stream<int> _unreadNotificationsCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(0);
    }

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(_index),
      body: IndexedStack(index: _index, children: pages),
      drawer: _buildDrawer(context),
      bottomNavigationBar: _buildBottomNavBar(),
      backgroundColor: Colors.white,
    );
  }

  // ---------- App Bar ----------

  PreferredSizeWidget _buildAppBar(int index) {
    final titles = ['Home', 'Explore', 'Social'];

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: AppColors.kGreen),
        onPressed: _openMenu,
        padding: const EdgeInsets.only(left: 16),
      ),
      title: index == 0
          ? SizedBox(
              height: 50,
              child: Image.asset(
                'images/Madar2-resized62.png',
                fit: BoxFit.contain,
              ),
            )
          : Text(
              titles[index],
              style: const TextStyle(
                color: AppColors.kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
      actions: index == 0
          ? [
              StreamBuilder<int>(
                stream: _unreadNotificationsCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;

                  return IconButton(
                    padding: const EdgeInsets.only(right: 16),
                    onPressed: () async {
                      final result = await Navigator.push<Map<String, dynamic>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsPage(),
                        ),
                      );
                      if (result != null && mounted) {
                        final page = result['page'] as String?;
                        final expandId = result['expandRequestId'] as String?;
                        final filterIdx = result['filterIndex'] as int?;
                        final meetingPointId =
                            result['meetingPointId'] as String?;
                        final historyMainTabIndex =
                            result['historyMainTabIndex'] as int?;
                        final meetingFilterIndex =
                            result['meetingFilterIndex'] as int?;
                        final historyFilterIdx = filterIdx == null
                            ? null
                            : 1 - filterIdx;

                        if (page == 'track' &&
                            meetingPointId != null &&
                            meetingPointId.trim().isNotEmpty) {
                          setState(() {
                            _meetingPointExpandId = meetingPointId;
                            _trackExpandRequestId = null;
                            _trackFilterIndex = null;
                            pages[2] = _buildTrackPage();
                            _index = 2;
                          });
                          return;
                        }

                        if (page == 'history' &&
                            meetingPointId != null &&
                            meetingPointId.trim().isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HistoryPage(
                                initialMainTabIndex: historyMainTabIndex ?? 1,
                                initialMeetingFilterIndex: meetingFilterIndex,
                                initialMeetingPointId: meetingPointId,
                              ),
                            ),
                          );
                        } else if (page == 'history' && expandId != null) {
                          // Navigate to History page
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HistoryPage(
                                initialFilterIndex: historyFilterIdx,
                                initialHighlightRequestId: expandId,
                              ),
                            ),
                          );
                        } else if (page == 'track' && expandId != null) {
                          // Navigate to Track page tab with expanded request
                          setState(() {
                            _trackExpandRequestId = expandId;
                            _trackFilterIndex = filterIdx;
                            _meetingPointExpandId = null;
                            pages[2] = _buildTrackPage();
                            _index = 2;
                          });
                        }
                      }
                    },
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.kGreen,
                        ),

                        // 🔴
                        if (count > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 0.5,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  count > 9 ? '+9' : count.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ]
          : index == 2
          ? [
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryPage()),
                  );
                },
                tooltip: 'Requests History',
                icon: Icon(Icons.history, size: 22, color: Colors.grey[600]),
                padding: const EdgeInsets.only(right: 16),
              ),
            ]
          : null,
      bottom: index == 1
          ? PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: Colors.black12),
            )
          : null,
    );
  }

  // ---------- Navigation Drawer ----------

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.of(context).padding.top + 24,
                24,
                28,
              ),
              decoration: const BoxDecoration(color: AppColors.kGreen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'images/MadarLogoVersion2.png',
                    height: 45,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Hello, ${_firstName.isEmpty ? 'User' : _firstName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: Column(
                children: [
                  ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _buildMenuItem(
                        icon: Icons.person_outline,
                        title: 'Profile',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfilePage(),
                            ),
                          ).then((_) => _loadUserData());
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.favorite_border,
                        title: 'Favorite Friends',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FavoriteFriendsPage(),
                            ),
                          );
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.history,
                        title: 'Requests History',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HistoryPage(),
                            ),
                          );
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.settings_outlined,
                        title: 'Settings',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsPage(),
                            ),
                          );
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.help_outline,
                        title: 'Help & Support',
                        onTap: () {
                          Navigator.pop(context); // close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HelpSupportPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Divider(height: 1, thickness: 1),
                  _buildMenuItem(
                    icon: Icons.logout,
                    title: 'Log out',
                    onTap: () => _logout(context),
                    isDestructive: true,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.kError : AppColors.kGreen,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? AppColors.kError : Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }

  // ---------- Bottom Navigation ----------

  Widget _buildBottomNavBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(icon: Icons.home, label: 'Home', index: 0),
              _buildNavItem(
                icon: Icons.explore_outlined,
                label: 'Explore',
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.group_outlined,
                label: 'Social',
                index: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _index == index;

    return InkWell(
      onTap: () => setState(() => _index = index),
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8E9E0) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.kGreen : Colors.grey.shade500,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.kGreen : Colors.grey.shade500,
                fontSize: 11,
                height: 1.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
