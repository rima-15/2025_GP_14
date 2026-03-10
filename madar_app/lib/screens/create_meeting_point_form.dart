import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

// ── DEV FLAG ──────────────────────────────────────────────────────────────────
/// Set to true so the full wizard can be tested even outside a real venue.
const bool forceVenueForTesting = true;

/// Geofence radius in metres – user must be this close to a venue centre.
const double _kVenueGeofenceMeters = 150;

// ── Entry point ───────────────────────────────────────────────────────────────

class CreateMeetingPointForm extends StatefulWidget {
  const CreateMeetingPointForm({super.key});

  @override
  State<CreateMeetingPointForm> createState() => _CreateMeetingPointFormState();
}

class _CreateMeetingPointFormState extends State<CreateMeetingPointForm> {
  // ── Wizard state ─────────────────────────────────────────────────────────
  int _step = 1; // 1-5

  // ── Step 1: Venue ─────────────────────────────────────────────────────────
  bool _loadingVenue = true;
  String? _venueId;
  String? _venueName;
  String? _venueError;

  // ── Step 1: Friends ───────────────────────────────────────────────────────
  final TextEditingController _phoneCtrl = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
  bool _isPhoneFocused = false;
  bool _isAddingPhone = false;
  bool _phoneValid = true;
  String? _phoneError;

  final List<_Friend> _selectedFriends = [];

  /// Active tracked friends inside the same venue.
  List<_Friend> _activeVenueFriends = [];
  bool _loadingActiveVenueFriends = false;

  // ── Step 1: Place Type ───────────────────────────────────────────────────
  final List<String> _allPlaceTypes = [
    'Any',
    'Café',
    'Restaurant',
    'Shop',
    'Entrance',
  ];
  final Set<String> _selectedPlaceTypes = {'Any'};

  // ── Step 2: Location ──────────────────────────────────────────────────────
  _HostLocation? _hostLocation;

  // ── Step 4: Participants ──────────────────────────────────────────────────
  /// Simulated participant list built from _selectedFriends at step 4 entry.
  List<_Participant> _participants = [];

  /// Step-4 10-minute countdown.
  Timer? _waitTimer;
  int _waitSecondsLeft = 600; // 10 min

  /// Proceed button unlock delay (5 s) before checking real acceptance.
  bool _proceedUnlocked = false;
  Timer? _proceedTimer;

  // ── Step 5: Suggested meeting point ──────────────────────────────────────
  /// 5-minute timer for host to accept/reject.
  Timer? _suggestTimer;
  int _suggestSecondsLeft = 300; // 5 min

  // ── Cached current user ───────────────────────────────────────────────────
  String? _myPhone;
  String? _myName;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(() {
      setState(() => _isPhoneFocused = _phoneFocus.hasFocus);
    });
    _loadCurrentUser();
    _loadAndResolveVenue();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    _waitTimer?.cancel();
    _proceedTimer?.cancel();
    _suggestTimer?.cancel();
    super.dispose();
  }

  // ─── Venue detection ──────────────────────────────────────────────────────

  Future<void> _loadAndResolveVenue() async {
    setState(() {
      _loadingVenue = true;
      _venueError = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('venues')
          .orderBy('venueName')
          .get();

      final venues = snap.docs
          .map((d) {
            final data = d.data();
            return _VenueOption(
              id: d.id,
              name: (data['venueName'] ?? '').toString(),
              lat: (data['latitude'] as num?)?.toDouble(),
              lng: (data['longitude'] as num?)?.toDouble(),
            );
          })
          .where((v) => v.name.isNotEmpty)
          .toList();

      final pos = await _getPositionOrNull();
      final matched = pos == null ? null : _matchVenue(venues, pos);

      if (matched != null) {
        // User is inside a real venue.
        _venueId = matched.id;
        _venueName = matched.name;
      } else if (forceVenueForTesting && venues.isNotEmpty) {
        // DEV override: always set the first venue so wizard can be tested.
        _venueId = venues.first.id;
        _venueName = venues.first.name; // no "(DEV)" label shown to user
      } else {
        _venueError =
            'You must be inside a supported venue to create a meeting point.';
      }

      if (!mounted) return;
      setState(() => _loadingVenue = false);

      // Load active venue friends after venue is known.
      if (_venueId != null) _loadActiveVenueFriends();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingVenue = false;
        _venueError = 'Could not detect venue. Please try again.';
      });
    }
  }

  Future<Position?> _getPositionOrNull() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever)
        return null;
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  _VenueOption? _matchVenue(List<_VenueOption> venues, Position pos) {
    _VenueOption? best;
    var bestDist = double.infinity;
    for (final v in venues) {
      if (v.lat == null || v.lng == null) continue;
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        v.lat!,
        v.lng!,
      );
      if (d <= _kVenueGeofenceMeters && d < bestDist) {
        best = v;
        bestDist = d;
      }
    }
    return best;
  }

  bool get _isVenueValid => _venueId != null;

  // ─── Current user ─────────────────────────────────────────────────────────

  Future<void> _loadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        _myPhone = (data['phone'] ?? '').toString();
        _myName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
      }
    } catch (_) {}
  }

  // ─── Active venue friends ─────────────────────────────────────────────────

  Future<void> _loadActiveVenueFriends() async {
    if (_venueId == null) return;
    setState(() => _loadingActiveVenueFriends = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Fetch accepted track requests that are currently active for this venue.
      final sentSnap = await FirebaseFirestore.instance
          .collection('trackRequests')
          .where('senderId', isEqualTo: user.uid)
          .where('venueId', isEqualTo: _venueId)
          .where('status', isEqualTo: 'accepted')
          .limit(40)
          .get();

      final receivedSnap = await FirebaseFirestore.instance
          .collection('trackRequests')
          .where('receiverId', isEqualTo: user.uid)
          .where('venueId', isEqualTo: _venueId)
          .where('status', isEqualTo: 'accepted')
          .limit(40)
          .get();

      final now = DateTime.now();
      final byPhone = <String, _Friend>{};

      for (final doc in sentSnap.docs) {
        final d = doc.data();
        final start = (d['startAt'] as Timestamp?)?.toDate();
        final end = (d['endAt'] as Timestamp?)?.toDate();
        if (start == null || end == null) continue;
        if (now.isBefore(start) || now.isAfter(end)) continue;
        final phone = d['receiverPhone']?.toString() ?? '';
        if (phone.isEmpty) continue;
        final name = (d['receiverName']?.toString().trim().isNotEmpty == true)
            ? d['receiverName'].toString().trim()
            : phone;
        byPhone.putIfAbsent(
          phone,
          () => _Friend(id: '', name: name, phone: phone, isFavorite: false),
        );
      }

      for (final doc in receivedSnap.docs) {
        final d = doc.data();
        final start = (d['startAt'] as Timestamp?)?.toDate();
        final end = (d['endAt'] as Timestamp?)?.toDate();
        if (start == null || end == null) continue;
        if (now.isBefore(start) || now.isAfter(end)) continue;
        final phone = d['senderPhone']?.toString() ?? '';
        if (phone.isEmpty) continue;
        final name = (d['senderName']?.toString().trim().isNotEmpty == true)
            ? d['senderName'].toString().trim()
            : phone;
        byPhone.putIfAbsent(
          phone,
          () => _Friend(id: '', name: name, phone: phone, isFavorite: false),
        );
      }

      if (!mounted) return;
      setState(() {
        // Exclude already-selected friends.
        _activeVenueFriends = byPhone.values
            .where((f) => !_selectedFriends.any((s) => s.phone == f.phone))
            .toList();
        _loadingActiveVenueFriends = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingActiveVenueFriends = false);
    }
  }

  // ─── Friend management ────────────────────────────────────────────────────

  void _addFriend(_Friend friend) {
    if (_selectedFriends.any((f) => f.phone == friend.phone)) return;
    setState(() {
      _selectedFriends.add(friend);
      _activeVenueFriends.removeWhere((f) => f.phone == friend.phone);
    });
  }

  void _removeFriend(_Friend friend) {
    setState(() {
      _selectedFriends.removeWhere((f) => f.phone == friend.phone);
      // Return to active list if applicable.
      _loadActiveVenueFriends();
    });
  }

  bool get _canAddPhone {
    final phone = _phoneCtrl.text.trim();
    return phone.length == 9 && RegExp(r'^\d{9}$').hasMatch(phone);
  }

  Future<void> _addFriendByPhone() async {
    if (_isAddingPhone) return;

    if (!_canAddPhone) {
      setState(() {
        _phoneValid = false;
        _phoneError = 'Enter 9 digits';
      });
      return;
    }

    final raw = _phoneCtrl.text.trim();
    final phone = '+966$raw';

    if (_selectedFriends.any((f) => f.phone == phone)) {
      setState(() {
        _phoneValid = false;
        _phoneError = 'Friend already added';
      });
      return;
    }
    if (_myPhone != null && _myPhone == phone) {
      setState(() {
        _phoneValid = false;
        _phoneError = "You can't add yourself";
      });
      return;
    }

    setState(() => _isAddingPhone = true);

    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (!mounted) return;

      if (q.docs.isEmpty) {
        _phoneFocus.unfocus();
        setState(() {
          _isAddingPhone = false;
          _phoneCtrl.clear();
          _phoneValid = true;
          _phoneError = null;
        });
        _showInviteToMadarDialog(phone);
        return;
      }

      final data = q.docs.first.data();
      final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
          .trim();

      setState(() {
        _isAddingPhone = false;
        _phoneValid = true;
        _phoneError = null;
        _selectedFriends.add(
          _Friend(
            id: q.docs.first.id,
            name: name.isEmpty ? phone : name,
            phone: phone,
            isFavorite: false,
          ),
        );
        _phoneCtrl.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAddingPhone = false;
        _phoneValid = false;
        _phoneError = 'Could not verify. Try again.';
      });
    }
  }

  static const String _inviteMessage =
      "Hey! I'm using Madar for location sharing.\n"
      "Join me using this invite link:\n"
      "https://madar.app/invite";

  void _showInviteToMadarDialog(String phone) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Invite to Madar?'),
          content: Text(
            "$phone isn't on Madar yet.\nSend them an invite to join?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _shareInvite();
              },
              child: const Text('Send Invite'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareInvite() async {
    try {
      await Share.share(_inviteMessage, subject: 'Invite to Madar');
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: _inviteMessage));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite copied to clipboard.')),
      );
    }
  }

  static String _normalizePhone(String raw) {
    var phone = raw.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
    if (phone.startsWith('+966')) phone = phone.substring(4);
    if (phone.startsWith('966')) phone = phone.substring(3);
    if (phone.startsWith('05') && phone.length >= 9) phone = phone.substring(2);
    phone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.length >= 9) phone = phone.substring(phone.length - 9);
    return phone.length == 9 ? '+966$phone' : '';
  }

  Future<void> _pickContact() async {
    _phoneFocus.unfocus();

    try {
      final allowed = await FlutterContacts.requestPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacts permission is required.')),
        );
        return;
      }

      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final items = <_ContactItem>[];
      final seen = <String>{};

      for (final c in contacts) {
        if (c.phones.isEmpty) continue;
        final name = c.displayName.trim().isEmpty ? 'Unknown' : c.displayName;
        for (final p in c.phones) {
          final normalized = _normalizePhone(p.number);
          if (normalized.isEmpty || !seen.add(normalized)) continue;
          items.add(_ContactItem(name: name, phone: normalized));
        }
      }

      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No valid contacts found.')));
        return;
      }

      final selectedPhone = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ContactListSheet(contacts: items),
      );

      if (!mounted || selectedPhone == null) return;
      final local = selectedPhone.startsWith('+966')
          ? selectedPhone.substring(4)
          : selectedPhone;

      setState(() {
        _phoneCtrl.text = local;
        _phoneCtrl.selection = TextSelection.collapsed(offset: local.length);
        _phoneValid = true;
        _phoneError = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load contacts. Try again.')),
      );
    }
  }

  Future<void> _showFavoritesList() async {
    final selected = await showModalBottomSheet<List<_Friend>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FavoriteListSheet(
        alreadySelectedPhones: _selectedFriends.map((f) => f.phone).toSet(),
      ),
    );
    if (selected == null || selected.isEmpty) return;
    for (final f in selected) {
      _addFriend(f);
    }
  }

  // ─── Step navigation ──────────────────────────────────────────────────────

  void _goNext() {
    if (_step == 3) {
      // Step 3 → 4: build participant list and start timers.
      _initStep4();
    } else if (_step == 4) {
      // Step 4 → 5: cancel wait timer, start suggestion timer.
      _waitTimer?.cancel();
      _proceedTimer?.cancel();
      _initStep5();
    }
    setState(() => _step++);
  }

  void _goBack() {
    if (_step == 4) {
      _waitTimer?.cancel();
      _proceedTimer?.cancel();
    }
    if (_step == 5) {
      _suggestTimer?.cancel();
    }
    setState(() => _step--);
  }

  void _initStep4() {
    // Build participant list from selected friends.
    _participants = _selectedFriends
        .map((f) => _Participant(friend: f, status: _ParticipantStatus.pending))
        .toList();

    // 10-minute countdown.
    _waitSecondsLeft = 600;
    _waitTimer?.cancel();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _waitSecondsLeft--;
        if (_waitSecondsLeft <= 0) {
          t.cancel();
          _onWaitTimerExpired();
        }
      });
    });

    // Unlock "Proceed" after 5 seconds (UI demo).
    _proceedUnlocked = false;
    _proceedTimer?.cancel();
    _proceedTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _proceedUnlocked = true);
    });

    // Simulate a participant accepting after 3 s for demo purposes.
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _step != 4) return;
      if (_participants.isNotEmpty) {
        setState(() {
          _participants[0] = _participants[0].copyWith(
            status: _ParticipantStatus.accepted,
          );
        });
      }
    });
  }

  void _onWaitTimerExpired() {
    final anyAccepted = _participants.any(
      (p) => p.status == _ParticipantStatus.accepted,
    );
    if (!anyAccepted) {
      // No one accepted → cancel meeting point.
      if (mounted) {
        Navigator.pop(context);
        SnackbarHelper.showError(
          context,
          'Meeting point cancelled – no participants accepted.',
        );
      }
    } else {
      // At least one accepted → advance to step 5.
      _initStep5();
      if (mounted) setState(() => _step = 5);
    }
  }

  void _initStep5() {
    _suggestSecondsLeft = 300;
    _suggestTimer?.cancel();
    _suggestTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _suggestSecondsLeft--;
        if (_suggestSecondsLeft <= 0) {
          t.cancel();
          // Timer expired → auto-accept.
          _acceptSuggestedMeetingPoint();
        }
      });
    });
  }

  void _acceptSuggestedMeetingPoint() {
    _suggestTimer?.cancel();
    if (!mounted) return;
    Navigator.pop(context);
    SnackbarHelper.showSuccess(context, 'Meeting point accepted!');
  }

  void _rejectSuggestedMeetingPoint() {
    _suggestTimer?.cancel();
    if (!mounted) return;
    Navigator.pop(context);
    SnackbarHelper.showError(context, 'Meeting point rejected.');
  }

  // ─── Step-level gate conditions ───────────────────────────────────────────

  bool get _step1CanNext => _isVenueValid && _selectedFriends.isNotEmpty;
  bool get _step2CanNext => _hostLocation != null;

  /// Proceed is enabled if: unlock timer fired AND at least one accepted + location set.
  bool get _step4CanProceed {
    if (!_proceedUnlocked) return false;
    return _participants.any((p) => p.status == _ParticipantStatus.accepted);
  }

  // ─── Stubs ────────────────────────────────────────────────────────────────

  Future<void> _sendInvites() async {
    final payload = {
      'venueId': _venueId,
      'venueName': _venueName,
      'placeTypes': _selectedPlaceTypes.toList(),
      'hostLocation': _hostLocation?.toMap(),
      'invitedFriendIds': _selectedFriends
          .map((f) => f.id)
          .where((id) => id.isNotEmpty)
          .toList(),
    };
    debugPrint('Meeting point payload: $payload');
    // Stub delay.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildProgressBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: _buildStepBody(),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    const subtitles = [
      'Select friends and type of meeting point',
      'Set your location',
      'Review & send',
      'Waiting for participants',
      'Suggested meeting point',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, color: AppColors.kGreen, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create Meeting Point',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitles[_step - 1],
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _step / 5,
              minHeight: 3,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(AppColors.kGreen),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Step $_step of 5',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // ── Step body dispatcher ──────────────────────────────────────────────────

  Widget _buildStepBody() {
    switch (_step) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      case 4:
        return _buildStep4();
      case 5:
        return _buildStep5();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 – Venue · Friends · Place Type
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    final inputsEnabled = _isVenueValid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Venue field (read-only, auto-detected) ──────────────────────────
        _sectionLabel('Venue'),
        const SizedBox(height: 10),
        _venueReadOnlyField(),
        if (_venueError != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.red[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _venueError!,
                  style: TextStyle(fontSize: 13, color: Colors.red[600]),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // ── Friends section (disabled when no venue) ────────────────────────
        AbsorbPointer(
          absorbing: !inputsEnabled,
          child: Opacity(
            opacity: inputsEnabled ? 1.0 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Select Friends to Meet'),
                const SizedBox(height: 14),

                // Phone + Add + Favorites row
                _buildPhoneInputRow(),
                const SizedBox(height: 6),
                SizedBox(
                  height: 18,
                  child: (!_phoneValid && _phoneError != null)
                      ? Text(
                          _phoneError!,
                          style: const TextStyle(
                            color: AppColors.kError,
                            fontSize: 13,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 14),

                // Active tracked friends at venue
                _buildActiveVenueFriendsList(),

                // Selected friends list
                if (_selectedFriends.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Selected friends',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._selectedFriends.map(_buildSelectedFriendRow),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedFriends.length} friend${_selectedFriends.length == 1 ? '' : 's'} selected',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Place type (chips) ────────────────────────────────────
                _sectionLabel('Select Type of Meeting Point'),
                const SizedBox(height: 12),
                _buildPlaceTypeChips(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _venueReadOnlyField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _venueError != null ? AppColors.kError : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.place_outlined, color: AppColors.kGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: _loadingVenue
                ? Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Detecting venue...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _venueName ?? 'No venue detected',
                    style: TextStyle(
                      fontSize: 15,
                      // Normal weight so it reads as non-editable
                      fontWeight: FontWeight.w400,
                      color: _venueName != null
                          ? Colors.black54
                          : Colors.grey[400],
                    ),
                  ),
          ),
          // Subtle lock to indicate read-only without being obtrusive
          if (!_loadingVenue)
            Icon(Icons.lock_outline, size: 15, color: Colors.grey[400]),
        ],
      ),
    );
  }

  Widget _buildPhoneInputRow() {
    final canTapAdd = _canAddPhone && !_isAddingPhone;

    return Row(
      children: [
        // Phone field
        Expanded(
          child: TextField(
            controller: _phoneCtrl,
            focusNode: _phoneFocus,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (_) => setState(() {
              _phoneValid = true;
              _phoneError = null;
            }),
            decoration: InputDecoration(
              hintText: 'Phone number',
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontWeight: FontWeight.w400,
              ),
              prefixText: _phoneCtrl.text.isEmpty ? null : '+966 ',
              prefixStyle: TextStyle(
                color: Colors.grey[600],
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              suffixIcon: _isPhoneFocused
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.contacts, color: AppColors.kGreen),
                      onPressed: _pickContact,
                    ),
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _phoneValid ? Colors.grey.shade300 : AppColors.kError,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _phoneValid ? AppColors.kGreen : AppColors.kError,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Add button
        GestureDetector(
          onTap: canTapAdd ? _addFriendByPhone : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: canTapAdd ? AppColors.kGreen : Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isAddingPhone ? '...' : 'Add',
              style: TextStyle(
                color: canTapAdd ? Colors.white : Colors.grey[500],
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Favorites heart button
        IconButton(
          onPressed: _showFavoritesList,
          icon: const Icon(
            Icons.favorite_border,
            color: AppColors.kGreen,
            size: 28,
          ),
          padding: const EdgeInsets.all(12),
          style: IconButton.styleFrom(
            backgroundColor: Colors.grey[100],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveVenueFriendsList() {
    final name = _venueName ?? 'venue';

    if (_loadingActiveVenueFriends) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading active friends...',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    if (_activeVenueFriends.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label: "Active tracked friends at [venue]"
        Row(
          children: [
            Icon(Icons.groups_2_outlined, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              'Active tracked friends at $name',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._activeVenueFriends.map(
          (friend) => _buildActiveVenueFriendRow(friend),
        ),
      ],
    );
  }

  Widget _buildActiveVenueFriendRow(_Friend friend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  friend.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // Heart icon
          Icon(
            friend.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: friend.isFavorite ? Colors.red : Colors.grey[400],
          ),
          const SizedBox(width: 10),

          // Add button (no background, text-only)
          GestureDetector(
            onTap: () => _addFriend(friend),
            child: const Text(
              'Add',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedFriendRow(_Friend friend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  friend.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // Heart icon
          Icon(
            friend.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: friend.isFavorite ? Colors.red : Colors.grey[400],
          ),
          const SizedBox(width: 8),

          // Green checkmark / remove indicator
          GestureDetector(
            onTap: () => _removeFriend(friend),
            child: const Icon(
              Icons.check_circle,
              color: AppColors.kGreen,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceTypeChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _allPlaceTypes.map((type) {
        final selected = _selectedPlaceTypes.contains(type);
        return GestureDetector(
          onTap: () {
            setState(() {
              _togglePlaceType(type);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.kGreen.withOpacity(0.13)
                  : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.kGreen : Colors.grey.shade400,
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  type,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected ? AppColors.kGreen : Colors.black87,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.close, size: 14, color: AppColors.kGreen),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _togglePlaceType(String type) {
    const any = 'Any';

    // "Any" must be exclusive.
    if (type == any) {
      _selectedPlaceTypes
        ..clear()
        ..add(any);
      return;
    }

    // Choosing any specific type should always unselect "Any".
    _selectedPlaceTypes.remove(any);

    if (_selectedPlaceTypes.contains(type)) {
      _selectedPlaceTypes.remove(type);
    } else {
      _selectedPlaceTypes.add(type);
    }

    // Keep at least one selected.
    if (_selectedPlaceTypes.isEmpty) {
      _selectedPlaceTypes.add(any);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 – Set My Location
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Set My Location'),
        const SizedBox(height: 8),
        Text(
          'Choose how you want to set your current location.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),

        // Two square buttons side by side
        Row(
          children: [
            Expanded(
              child: _locationOptionSquare(
                icon: Icons.location_on_outlined,
                label: 'Pin on map',
                onTap: _openMapPicker,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _locationOptionSquare(
                icon: Icons.camera_alt_outlined,
                label: 'Scan with camera',
                onTap: _scanWithCamera,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Location set confirmation
        if (_hostLocation != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.kGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.kGreen.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.kGreen,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Location set ✓',
                  style: TextStyle(
                    color: AppColors.kGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _locationOptionSquare({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.kGreen, size: 32),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.kGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMapPicker() async {
    // Reuse the navigation flow's SetYourLocationDialog as a stub.
    // For now, set a placeholder location and show confirmation.
    setState(() {
      _hostLocation = const _HostLocation(
        latitude: 24.7136,
        longitude: 46.6753,
        label: 'Pinned location',
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Map picker: placeholder location set.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _scanWithCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required.')),
      );
      return;
    }
    // Stub: set a placeholder location.
    setState(() {
      _hostLocation = const _HostLocation(
        latitude: 24.7136,
        longitude: 46.6753,
        label: 'Camera scan',
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Camera scan: placeholder location set.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3 – Summary + Send Invites
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Summary'),
        const SizedBox(height: 16),

        // Green left-border summary card (no filled background)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Green vertical line
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: AppColors.kGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryRow('Venue', _venueName ?? '—'),
                    const SizedBox(height: 10),
                    _summaryRow('Place type', _selectedPlaceTypes.join(', ')),
                    const SizedBox(height: 10),
                    _summaryRow(
                      'My location',
                      _hostLocation != null
                          ? '${_hostLocation!.label} ✓'
                          : 'Not set',
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Invited friends',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._selectedFriends.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person,
                                size: 15,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${f.name} · ${f.phone}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendInvitesAndAdvance() async {
    await _sendInvites();
    if (!mounted) return;
    _initStep4();
    setState(() => _step = 4);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 – Waiting for participants (10-min timer)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep4() {
    final mm = (_waitSecondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_waitSecondsLeft % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('Waiting for participants'),
            const Spacer(),
            // Small grey timer in top-right corner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    '$mm:$ss',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Participant rows
        ..._participants.map(_buildParticipantRow),

        const SizedBox(height: 24),

        // Hint text
        Center(
          child: Text(
            '(you can proceed with accepted participants)',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildParticipantRow(_Participant p) {
    final statusText = p.status == _ParticipantStatus.accepted
        ? 'Accepted'
        : p.status == _ParticipantStatus.declined
        ? 'Declined'
        : 'Pending';

    final statusColor = p.status == _ParticipantStatus.accepted
        ? AppColors.kGreen
        : p.status == _ParticipantStatus.declined
        ? AppColors.kError
        : Colors.orange[600]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.grey[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.friend.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  p.friend.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // Heart
          Icon(
            p.friend.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: p.friend.isFavorite ? Colors.red : Colors.grey[400],
          ),
          const SizedBox(width: 10),

          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 5 – Accept or Reject Suggested Meeting Point
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep5() {
    final mm = (_suggestSecondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_suggestSecondsLeft % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        // Timer at top
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  '$mm:$ss',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),

        // Big pin icon centred
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.kGreen.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.place, color: AppColors.kGreen, size: 52),
        ),
        const SizedBox(height: 20),

        const Text(
          'The most suitable meeting point is',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        const Text(
          '"Adidas"',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'If you don\'t decide, it will be auto-accepted when the timer runs out.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),

        const SizedBox(height: 36),

        // Accept button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _acceptSuggestedMeetingPoint,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.kGreen,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Accept',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Reject button (outlined)
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _rejectSuggestedMeetingPoint,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.kGreen,
              side: BorderSide(color: AppColors.kGreen.withOpacity(0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            child: const Text('Reject'),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Footer actions
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    // Step 5 manages its own CTAs inside the body; no bottom footer.
    if (_step == 5) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Back button (shown from step 2 onwards, except step 4)
          if (_step > 1 && _step != 4) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _goBack,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: AppColors.kGreen,
                  side: BorderSide(color: AppColors.kGreen.withOpacity(0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Next / Proceed button
          Expanded(
            flex: _step > 1 && _step != 4 ? 2 : 1,
            child: _buildPrimaryFooterButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryFooterButton() {
    // Step 4: "Proceed"
    if (_step == 4) {
      final enabled = _step4CanProceed;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: enabled ? _goNext : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: enabled ? AppColors.kGreen : Colors.grey[300],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Proceed',
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.grey[500],
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Step 3: "Send Invites"
    if (_step == 3) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _sendInvitesAndAdvance,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.kGreen,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Send Invites',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // Steps 1 and 2: "Next"
    final enabled = _step == 1 ? _step1CanNext : _step2CanNext;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? _goNext : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? AppColors.kGreen : Colors.grey[300],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Next',
          style: TextStyle(
            color: enabled ? Colors.white : Colors.grey[500],
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FAVORITES LIST SHEET  (matches exact pattern from TrackRequestDialog)
// ═════════════════════════════════════════════════════════════════════════════

class _FavoriteListSheet extends StatefulWidget {
  const _FavoriteListSheet({required this.alreadySelectedPhones});
  final Set<String> alreadySelectedPhones;

  @override
  State<_FavoriteListSheet> createState() => _FavoriteListSheetState();
}

class _FavoriteListSheetState extends State<_FavoriteListSheet> {
  final _searchCtrl = TextEditingController();

  // Stub favorites – replace with real Firestore query.
  final List<_Friend> _allFavorites = [
    _Friend(
      id: '1',
      name: 'Mona Saleh',
      phone: '+966557225235',
      isFavorite: true,
    ),
    _Friend(
      id: '2',
      name: 'ar saeed',
      phone: '+966334333333',
      isFavorite: true,
    ),
    _Friend(id: '3', name: 'Ameera', phone: '+966503347974', isFavorite: true),
    _Friend(id: '4', name: 'Amjad', phone: '+966503347973', isFavorite: true),
  ];

  late List<_Friend> _filtered;
  final List<_Friend> _picked = [];

  @override
  void initState() {
    super.initState();
    _filtered = _allFavorites
        .where((f) => !widget.alreadySelectedPhones.contains(f.phone))
        .toList();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allFavorites
          .where((f) => !widget.alreadySelectedPhones.contains(f.phone))
          .where((f) => f.name.toLowerCase().contains(q) || f.phone.contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle
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
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const Expanded(
                  child: Text(
                    'Favorite list',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, _picked),
                  child: Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _picked.isEmpty
                          ? Colors.grey[400]
                          : AppColors.kGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              cursorColor: AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 0.5),
              itemBuilder: (ctx, i) {
                final f = _filtered[i];
                final selected = _picked.contains(f);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      color: Colors.grey[600],
                      size: 22,
                    ),
                  ),
                  title: Text(
                    f.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    f.phone,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  trailing: GestureDetector(
                    onTap: () => setState(() {
                      selected ? _picked.remove(f) : _picked.add(f);
                    }),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.kGreen : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? AppColors.kGreen
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                  onTap: () => setState(() {
                    selected ? _picked.remove(f) : _picked.add(f);
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class _ContactItem {
  const _ContactItem({required this.name, required this.phone});

  final String name;
  final String phone;
}

class _ContactListSheet extends StatefulWidget {
  const _ContactListSheet({required this.contacts});

  final List<_ContactItem> contacts;

  @override
  State<_ContactListSheet> createState() => _ContactListSheetState();
}

class _ContactListSheetState extends State<_ContactListSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<_ContactItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = List<_ContactItem>.from(widget.contacts);
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = List<_ContactItem>.from(widget.contacts);
      } else {
        _filtered = widget.contacts
            .where(
              (c) =>
                  c.name.toLowerCase().contains(query) || c.phone.contains(query),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select a contact',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              cursorColor: AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 0.5),
              itemBuilder: (_, i) {
                final contact = _filtered[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[300],
                    child: Icon(Icons.person, color: Colors.grey[600], size: 20),
                  ),
                  title: Text(
                    contact.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    contact.phone,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  onTap: () => Navigator.pop(context, contact.phone),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
// MODELS
// ═════════════════════════════════════════════════════════════════════════════

class _VenueOption {
  const _VenueOption({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
  });
  final String id;
  final String name;
  final double? lat;
  final double? lng;
}

class _Friend {
  const _Friend({
    required this.id,
    required this.name,
    required this.phone,
    this.isFavorite = false,
  });
  final String id;
  final String name;
  final String phone;
  final bool isFavorite;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Friend &&
          runtimeType == other.runtimeType &&
          phone == other.phone;

  @override
  int get hashCode => phone.hashCode;
}

class _HostLocation {
  const _HostLocation({
    required this.latitude,
    required this.longitude,
    this.label = 'Set location',
  });
  final double latitude;
  final double longitude;
  final String label;

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'label': label,
  };
}

enum _ParticipantStatus { pending, accepted, declined }

class _Participant {
  const _Participant({required this.friend, required this.status});
  final _Friend friend;
  final _ParticipantStatus status;

  _Participant copyWith({_ParticipantStatus? status}) {
    return _Participant(friend: friend, status: status ?? this.status);
  }
}
