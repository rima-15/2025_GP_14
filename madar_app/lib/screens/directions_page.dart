import 'package:flutter/material.dart';

const kGreen = Color(0xFF787E65);

class DirectionsPage extends StatefulWidget {
  final String placeName;
  const DirectionsPage({super.key, required this.placeName});

  @override
  State<DirectionsPage> createState() => _DirectionsPageState();
}

class _DirectionsPageState extends State<DirectionsPage> {
  int _selectedMode = 0; // 0: Stairs, 1: Elevator, 2: Escalator

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.close, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 220),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _circleChoice(
                      index: 0,
                      label: 'Stairs',
                      icon: Icons.stairs_outlined,
                    ),
                    _circleChoice(
                      index: 1,
                      label: 'Elevator',
                      icon: Icons.elevator_outlined,
                    ),
                    _circleChoice(
                      index: 2,
                      label: 'Escalator',
                      icon: Icons.escalator_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEFE3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.map_outlined,
                      size: 64,
                      color: Colors.black45,
                    ),
                  ),
                ),
              ],
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: _routeBottomSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleChoice({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final selected = _selectedMode == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = index),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: selected ? kGreen : const Color(0xFFEDEFE3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: selected ? Colors.white : kGreen,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? kGreen : Colors.black87,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ===== Bottom Sheet =====
  Widget _routeBottomSheet() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _InfoPill(icon: Icons.access_time, text: '5 min'),
                _InfoPill(icon: Icons.place_outlined, text: '250 m'),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                // ⬇️ Replaced Image.asset(...) with a rounded square shop icon (same size/spacing)
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEFE3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.store_mall_directory_outlined,
                      color: kGreen,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.placeName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Fashion',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.camera),
                label: const Text('AR Mode'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
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

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kGreen, size: 18),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
