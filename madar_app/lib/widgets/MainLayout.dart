import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/screens/home_page.dart';
import 'package:madar_app/screens/explore_page.dart';
import 'package:madar_app/screens/track_page.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/screens/profile_page.dart';
import 'package:madar_app/screens/settings_page.dart';
import 'package:madar_app/screens/help_page.dart';

const kGreen = Color(0xFF787E65);

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _index = 0;
  final _homeKey = GlobalKey<HomePageState>();

  late final pages = <Widget>[
    HomePage(key: _homeKey),
    const ExplorePage(),
    const TrackPage(),
  ];

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // User data
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

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

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    }
  }

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      appBar: _buildAppBar(_index),
      body: pages[_index],
      drawer: _buildDrawer(context),
      bottomNavigationBar: _buildBottomBar(),
      backgroundColor: const Color(0xFFF8F8F3),
    );
  }

  // -------------------------- 🔹 AppBar Builder 🔹 --------------------------
  PreferredSizeWidget _buildAppBar(int index) {
    final titles = ['Home', 'Explore', 'Track'];

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,

      // Hamburger menu on the LEFT
      leading: IconButton(
        icon: const Icon(Icons.menu, color: kGreen),
        onPressed: _openMenu,
        padding: const EdgeInsets.only(left: 16), // Add padding from edge
      ),

      // Title/Logo in center
      title: index == 0
          ? SizedBox(
              height: 50,
              child: Image.asset(
                'images/MadarLogoEnglish.png',
                fit: BoxFit.contain,
              ),
            )
          : Text(
              titles[index],
              style: const TextStyle(
                color: kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),

      // Notifications on the RIGHT
      actions: index == 0
          ? [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: kGreen),
                onPressed: () {},
                padding: const EdgeInsets.only(
                  right: 16,
                ), // Add padding from edge
              ),
            ]
          : null,
    );
  }

  // -------------------------- 🔹 Professional Drawer 🔹 --------------------------
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header with logo and greeting
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 28),
              decoration: const BoxDecoration(color: kGreen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Image.asset(
                    'images/MadarLogoVersion2.png',
                    height: 45,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),

                  // Greeting
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

            // Menu items
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
                        title: 'Help',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HelpPage()),
                          );
                        },
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Log out at the bottom
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
      leading: Icon(icon, color: isDestructive ? Colors.red : kGreen, size: 24),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }

  Widget _buildBottomBar() {
    return CurvedNavigationBar(
      index: _index,
      height: 60,
      color: kGreen,
      backgroundColor: Colors.transparent,
      buttonBackgroundColor: Colors.white,
      animationCurve: Curves.easeInOut,
      animationDuration: const Duration(milliseconds: 300),
      items: [
        Icon(Icons.home, size: 28, color: _index == 0 ? kGreen : Colors.white),
        Icon(
          Icons.explore,
          size: 28,
          color: _index == 1 ? kGreen : Colors.white,
        ),
        Icon(
          Icons.group_outlined,
          size: 28,
          color: _index == 2 ? kGreen : Colors.white,
        ),
      ],
      onTap: (i) => setState(() => _index = i),
    );
  }
}
