import 'package:flutter/material.dart';

const kGreen = Color(0xFF787E65);

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() =>
      _TrackPageState();
}

class _TrackPageState
    extends State<TrackPage> {
  final List<Participant>
  meetingParticipants = [
    Participant(
      name: 'Alex Chen',
      status: 'On the way - 2 mins ago',
    ),
    Participant(
      name: 'Sarah Kim',
      status: 'Arrived - Just now',
    ),
    Participant(
      name: 'Jordan Martinez',
      status: 'On the way - 8 mins ago',
    ),
  ];

  final List<TrackingUser>
  trackingUsers = [
    TrackingUser(
      name: 'Mike Johnson',
      lastSeen: '5 mins ago',
    ),
    TrackingUser(
      name: 'Sara Alqahtani',
      lastSeen: 'Just now',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF8F8F3,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(
            16,
          ),
          children: [
            // ---------------- Map Preview ----------------
            _card(
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFEDEFE3,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.map_outlined,
                    size: 48,
                    color:
                        Colors.black45,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---------------- Buttons Create/Track ----------------
            Row(
              children: [
                Expanded(
                  child: _pillButton(
                    icon: Icons
                        .place_outlined,
                    label:
                        'Create Meeting Point',
                    onTap: () {},
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: _pillButton(
                    icon: Icons
                        .person_search_outlined,
                    label:
                        'Track Request',
                    onTap: () {},
                    outlined: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ---------------- Me ----------------
            _card(
              Padding(
                padding:
                    const EdgeInsets.all(
                      12,
                    ),
                child: Column(
                  children: [
                    _tileHeader(
                      title: 'Me',
                      subtitle:
                          'Active meeting point',
                      trailing:
                          _roleChip(
                            'Host',
                          ),
                      showArrow: false,
                    ),
                    const SizedBox(
                      height: 12,
                    ),

                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                () {},
                            icon: const Icon(
                              Icons
                                  .check_circle_outline,
                            ),
                            label: const Text(
                              'Arrived',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  kGreen,
                              foregroundColor:
                                  Colors
                                      .white,
                              padding: const EdgeInsets.symmetric(
                                vertical:
                                    16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                () {},
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color:
                                    kGreen,
                                width:
                                    2,
                              ),
                              foregroundColor:
                                  kGreen,
                              padding: const EdgeInsets.symmetric(
                                vertical:
                                    16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ---------------- Meeting Participants ----------------
            const Text(
              'Meeting Point Participants',
              style: TextStyle(
                fontSize: 16,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),

            for (final p
                in meetingParticipants)
              Container(
                margin:
                    const EdgeInsets.only(
                      bottom: 8,
                    ),
                decoration: BoxDecoration(
                  color: Colors
                      .white, // خلفية واضحة
                  borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors
                          .black
                          .withOpacity(
                            0.04,
                          ),
                      blurRadius: 6,
                      offset:
                          const Offset(
                            0,
                            2,
                          ),
                    ),
                  ],
                ),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                  title: Text(
                    p.name,
                    style:
                        const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                  ),
                  subtitle: Text(
                    p.status,
                    style:
                        const TextStyle(
                          color: Colors
                              .black54,
                        ),
                  ),
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(
                            horizontal:
                                12,
                            vertical: 8,
                          ),
                      child: FilledButton.icon(
                        onPressed:
                            () {},
                        icon: const Icon(
                          Icons.refresh,
                        ),
                        label: const Text(
                          'Refresh Location Request',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              kGreen,
                          foregroundColor:
                              Colors
                                  .white,
                          minimumSize:
                              const Size.fromHeight(
                                48,
                              ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                  12,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // ---------------- Tracking Users ----------------
            const Text(
              'Tracking Users',
              style: TextStyle(
                fontSize: 16,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),

            for (final u
                in trackingUsers)
              Container(
                margin:
                    const EdgeInsets.only(
                      bottom: 8,
                    ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors
                          .black
                          .withOpacity(
                            0.04,
                          ),
                      blurRadius: 6,
                      offset:
                          const Offset(
                            0,
                            2,
                          ),
                    ),
                  ],
                ),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                  title: Text(
                    u.name,
                    style:
                        const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                  ),
                  subtitle: Text(
                    "Location sharing active • ${u.lastSeen}",
                    style:
                        const TextStyle(
                          color: Colors
                              .black54,
                        ),
                  ),
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(
                            horizontal:
                                12,
                            vertical: 8,
                          ),
                      child: Column(
                        children: [
                          FilledButton.icon(
                            onPressed:
                                () {},
                            icon: const Icon(
                              Icons
                                  .refresh,
                            ),
                            label: const Text(
                              'Refresh Location Request',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  kGreen,
                              foregroundColor:
                                  Colors
                                      .white,
                              minimumSize:
                                  const Size.fromHeight(
                                    48,
                                  ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                () {},
                            icon: const Icon(
                              Icons
                                  .flag_outlined,
                            ),
                            label: const Text(
                              'Set Friend as Destination',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  kGreen,
                              side: const BorderSide(
                                color:
                                    kGreen,
                                width:
                                    2,
                              ),
                              minimumSize:
                                  const Size.fromHeight(
                                    48,
                                  ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Widgets helpers ----------

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    final shape =
        RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(14),
        );
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: kGreen),
        label: Text(
          label,
          style: const TextStyle(
            color: kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(
            color: kGreen,
            width: 2,
          ),
          shape: shape,
          padding:
              const EdgeInsets.symmetric(
                vertical: 14,
              ),
          backgroundColor: Colors.white,
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        color: Colors.white,
      ),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        shape: shape,
        padding:
            const EdgeInsets.symmetric(
              vertical: 14,
            ),
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _tileHeader({
    required String title,
    required String subtitle,
    Widget? trailing,
    bool showArrow = true,
    Widget? leading,
  }) {
    return Row(
      children: [
        if (leading != null) leading,
        if (leading != null)
          const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                  ),
                  if (trailing !=
                      null) ...[
                    const SizedBox(
                      width: 8,
                    ),
                    trailing,
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        if (showArrow)
          const Icon(
            Icons.keyboard_arrow_right,
            color: Colors.black38,
          ),
      ],
    );
  }

  Widget _roleChip(String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 2,
          ),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAD9),
        borderRadius:
            BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black87,
        ),
      ),
    );
  }
}

// ---------------- Models ----------------
class Participant {
  final String name;
  final String status;
  Participant({
    required this.name,
    required this.status,
  });
}

class TrackingUser {
  final String name;
  final String lastSeen;
  TrackingUser({
    required this.name,
    required this.lastSeen,
  });
}
