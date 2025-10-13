import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:madar_app/screens/home_page.dart';
import 'package:madar_app/screens/explore_page.dart';
import 'package:madar_app/screens/track_page.dart';
import 'package:madar_app/screens/signin_page.dart';

const kGreen = Color(0xFF787E65);

class MainLayout
    extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() =>
      _MainLayoutState();
}

class _MainLayoutState
    extends State<MainLayout> {
  int _index = 0;
  final _homeKey =
      GlobalKey<HomePageState>();

  late final pages = <Widget>[
    HomePage(key: _homeKey),
    const ExplorePage(),
    const TrackPage(),
  ];

  final _scaffoldKey =
      GlobalKey<ScaffoldState>();

  Future<void> _logout(
    BuildContext context,
  ) async {
    await FirebaseAuth.instance
        .signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const SignInScreen(),
        ),
        (route) => false,
      );
    }
  }

  void _openMenu() => _scaffoldKey
      .currentState
      ?.openEndDrawer();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      appBar: _buildAppBar(_index),
      body: pages[_index],
      endDrawer: _buildDrawer(context),
      bottomNavigationBar:
          _buildBottomBar(),
      backgroundColor: const Color(
        0xFFF8F8F3,
      ),
    );
  }

  // -------------------------- 🔹 AppBar Builder 🔹 --------------------------
  PreferredSizeWidget _buildAppBar(
    int index,
  ) {
    final titles = [
      'Home',
      'Explore',
      'Track',
    ];

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,

      // leading (الجهة اليسار)
      leading: index == 0
          ? IconButton(
              icon: const Icon(
                Icons
                    .notifications_outlined,
                color: kGreen,
              ),
              onPressed:
                  () {}, // الإشعارات فقط في Home
            )
          : null,

      // title
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
                fontWeight:
                    FontWeight.w600,
              ),
            ),

      // actions (يمين)
      actions: [
        IconButton(
          icon: const Icon(
            Icons.menu,
            color: kGreen,
          ),
          onPressed: _openMenu,
        ),
      ],
    );
  }

  // -------------------------- 🔹 Drawer 🔹 --------------------------
  Widget _buildDrawer(
    BuildContext context,
  ) {
    return SizedBox(
      width:
          MediaQuery.of(
            context,
          ).size.width *
          0.6,
      child: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: kGreen,
              ),
              margin: EdgeInsets.all(0),
              padding: EdgeInsets.all(
                16,
              ),
              child: Align(
                alignment: Alignment
                    .centerLeft,
                child: Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.logout,
                color: Colors.red,
              ),
              title: const Text(
                'Log out',
              ),
              onTap: () =>
                  _logout(context),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------- 🔹 Bottom Navigation 🔹 --------------------------
  Widget _buildBottomBar() {
    return CurvedNavigationBar(
      index: _index,
      height: 60,
      color: kGreen,
      backgroundColor:
          Colors.transparent,
      buttonBackgroundColor:
          Colors.white,
      animationCurve: Curves.easeInOut,
      animationDuration: const Duration(
        milliseconds: 300,
      ),
      items: [
        Icon(
          Icons.home,
          size: 28,
          color: _index == 0
              ? kGreen
              : Colors.white,
        ),
        Icon(
          Icons.explore,
          size: 28,
          color: _index == 1
              ? kGreen
              : Colors.white,
        ),
        Icon(
          Icons.group_outlined,
          size: 28,
          color: _index == 2
              ? kGreen
              : Colors.white,
        ),
      ],
      onTap: (i) =>
          setState(() => _index = i),
    );
  }
}
