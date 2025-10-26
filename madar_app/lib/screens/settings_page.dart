import 'package:flutter/material.dart';

const kGreen = Color(0xFF787E65);

class SettingsPage
    extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() =>
      _SettingsPageState();
}

class _SettingsPageState
    extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _locationEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF8F8F3,
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: kGreen,
          ),
          onPressed: () =>
              Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(
          16,
        ),
        children: [
          _buildSection(
            title: 'Preferences',
            children: [
              _buildSwitchTile(
                icon: Icons
                    .notifications_outlined,
                title: 'Notifications',
                subtitle:
                    'Receive push notifications',
                value:
                    _notificationsEnabled,
                onChanged: (val) {
                  setState(
                    () =>
                        _notificationsEnabled =
                            val,
                  );
                },
              ),
              _buildSwitchTile(
                icon: Icons
                    .location_on_outlined,
                title:
                    'Location Services',
                subtitle:
                    'Allow location access',
                value: _locationEnabled,
                onChanged: (val) {
                  setState(
                    () =>
                        _locationEnabled =
                            val,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(
                left: 16,
                bottom: 8,
              ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight:
                  FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
                  12,
                ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(
                  0,
                  2,
                ),
              ),
            ],
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>
    onChanged,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: kGreen,
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
              ),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
<<<<<<< HEAD
        thumbColor:
            MaterialStateProperty.all(
              kGreen,
            ),
=======
        //activeThumbColor: kGreen,
>>>>>>> cac77d776deaea4b99c370092aa355fa102d6eaa
      ),
      contentPadding:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
    );
  }
}

Widget _buildSection({
  required String title,
  required List<Widget> children,
}) {
  return Column(
    crossAxisAlignment:
        CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          left: 16,
          bottom: 8,
        ),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            letterSpacing: 0.5,
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(
                0,
                2,
              ),
            ),
          ],
        ),
        child: Column(
          children: children,
        ),
      ),
    ],
  );
}

Widget _buildSwitchTile({
  required IconData icon,
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return ListTile(
    leading: Icon(icon, color: kGreen),
    title: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
    subtitle: subtitle != null
        ? Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
            ),
          )
        : null,
    trailing: Switch(
      value: value,
      onChanged: onChanged,
<<<<<<< HEAD
      thumbColor:
          MaterialStateProperty.all(
            kGreen,
          ),
=======
      //activeThumbColor: kGreen,
>>>>>>> cac77d776deaea4b99c370092aa355fa102d6eaa
    ),
    contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
  );
}

Widget _buildTile({
  required IconData icon,
  required String title,
  String? subtitle,
  VoidCallback? onTap,
}) {
  return ListTile(
    leading: Icon(icon, color: kGreen),
    title: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
    subtitle: subtitle != null
        ? Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
            ),
          )
        : null,
    trailing: const Icon(
      Icons.chevron_right,
      color: Colors.black38,
    ),
    onTap: onTap,
    contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
  );
}
