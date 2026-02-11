import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';

// ----------------------------------------------------------------------------
// Contact Item Model (for pre-loading)
// ----------------------------------------------------------------------------

class _ContactItem {
  final String name;
  final String phone;
  _ContactItem({required this.name, required this.phone});
}

// ----------------------------------------------------------------------------
// Track Request Dialog
// ----------------------------------------------------------------------------

class TrackRequestDialog extends StatefulWidget {
  const TrackRequestDialog({super.key});

  @override
  State<TrackRequestDialog> createState() => _TrackRequestDialogState();
}

class _TrackRequestDialogState extends State<TrackRequestDialog> {
  final FocusNode _phoneFocusNode = FocusNode();
  bool _isPhoneFocused = false;
  final _phoneController = TextEditingController();
  final List<Friend> _selectedFriends = [];
  bool _isPhoneInputValid = true;
  String? _phoneInputError;
  bool _isTimeValid = true;
  String? _timeError;
  bool _isAddingPhone = false; // Prevent multiple clicks on Add button
  bool _isSubmitting = false; // Prevent multiple clicks on Send Request

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Venue selection
  String? _selectedVenue;
  String? _selectedVenueId;
  List<VenueOption> _allVenues = [];
  bool _loadingVenues = false;
  Position? _currentPosition;

  // Pre-loaded contacts data (loaded when dialog opens for fast access)
  List<_ContactItem> _preloadedContacts = [];
  Map<String, bool> _preloadedInDbStatus = {};

  // Cached current user info (loaded once in initState to avoid repeated queries)
  String? _cachedMyPhone;
  String? _cachedMyName;

  // Venue opening hours
  List<String> _venueWeekdayText = [];
  List<dynamic> _venuePeriods = [];
  int? _venueUtcOffset;
  String? _venueBusinessStatus;
  bool _loadingHours = false;

  // End date (for overnight tracking)
  DateTime? _selectedEndDate;

  // Overlap detection state
  // Active overlaps: friends auto-removed (stored so they can be restored)
  List<Friend> _activeOverlapRemovedFriends = [];
  // Scheduled overlaps: friends with pending/accepted scheduled overlap
  List<Map<String, String>> _scheduledOverlapFriends = [];
  List<String> _scheduledOverlapDocIds = [];

  // UID cache to avoid repeated Firestore lookups
  final Map<String, String> _phoneToUidCache = {};

  // ScrollController for main content
  final ScrollController _mainScrollController = ScrollController();
  // GlobalKey for the overlap message container
  final GlobalKey _overlapMsgKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadVenues();
    _getCurrentLocation();
    _preloadContacts(); // Pre-load contacts and DB status
    _loadCurrentUserInfo(); // Cache current user's phone/name

    _phoneFocusNode.addListener(() {
      setState(() {
        _isPhoneFocused = _phoneFocusNode.hasFocus;
      });
    });
  }

  /// Cache current user's phone and name to avoid repeated Firestore queries
  Future<void> _loadCurrentUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        _cachedMyPhone = (data['phone'] ?? '').toString();
        _cachedMyName = ('${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
            .trim();
      }
    } catch (_) {}
  }

  /// Pre-load contacts and check DB status in background
  Future<void> _preloadContacts() async {
    try {
      if (!await FlutterContacts.requestPermission()) {
        return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final List<_ContactItem> items = [];
      for (final c in contacts) {
        if (c.phones.isEmpty) continue;
        final name = c.displayName.trim().isEmpty ? 'Unknown' : c.displayName;
        for (final p in c.phones) {
          final phone = _normalizePhone(p.number);
          if (phone.isNotEmpty)
            items.add(_ContactItem(name: name, phone: phone));
        }
      }
      final seen = <String>{};
      final deduped = <_ContactItem>[];
      for (final i in items) {
        if (seen.add(i.phone)) deduped.add(i);
      }
      deduped.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _preloadedContacts = deduped;
      });

      // Check DB status in batches
      const batchSize = 20;
      for (var i = 0; i < deduped.length; i += batchSize) {
        if (!mounted) return;
        final batch = deduped.skip(i).take(batchSize).toList();
        for (final item in batch) {
          if (!mounted) return;
          try {
            final uid = await _getUserIdByPhone(item.phone);
            if (mounted) {
              setState(() {
                _preloadedInDbStatus[item.phone] = uid != null;
              });
            }
          } catch (_) {
            if (mounted) {
              setState(() {
                _preloadedInDbStatus[item.phone] = false;
              });
            }
          }
        }
      }
    } catch (e) {
      // Ignore errors - contacts will show loading state for unchecked items
    }
  }

  static String _normalizePhone(String raw) {
    String phone = raw.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
    if (phone.startsWith('+966')) phone = phone.replaceFirst('+966', '');
    if (phone.startsWith('966')) phone = phone.replaceFirst('966', '');
    if (phone.startsWith('05') && phone.length >= 9) phone = phone.substring(2);
    phone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.length >= 9) phone = phone.substring(phone.length - 9);
    return phone.length == 9 ? '+966$phone' : '';
  }

  String _formatTime12h(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    return DateFormat('h:mm a').format(dt); // 1:35 AM
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  void _setTimeError(String msg) {
    setState(() {
      _isTimeValid = false;
      _timeError = msg;
    });
  }

  void _clearTimeError() {
    if (!_isTimeValid || _timeError != null) {
      setState(() {
        _isTimeValid = true;
        _timeError = null;
      });
    }
  }

  Future<String?> _getUserIdByPhone(String phone) async {
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;
    return q.docs.first.id; // docId = uid
  }

  Future<void> _loadVenues() async {
    setState(() => _loadingVenues = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('venues')
          .orderBy('venueName')
          .get();

      final venues = snapshot.docs.map((doc) {
        final data = doc.data();
        return VenueOption(
          id: doc.id,
          name: data['venueName'] ?? '',
          latitude: data['latitude'] as double?,
          longitude: data['longitude'] as double?,
        );
      }).toList();

      // Sort alphabetically (case-insensitive)
      venues.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      setState(() {
        _allVenues = venues;
        _loadingVenues = false;
      });
    } catch (e) {
      setState(() => _loadingVenues = false);
      debugPrint('Error loading venues: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() => _currentPosition = position);

      // Auto-select nearest venue
      if (_allVenues.isNotEmpty) {
        _autoSelectNearestVenue(position);
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _autoSelectNearestVenue(Position position) {
    VenueOption? nearestVenue;
    double minDistance = double.infinity;

    for (final venue in _allVenues) {
      if (venue.latitude != null && venue.longitude != null) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          venue.latitude!,
          venue.longitude!,
        );

        // Within 500 meters
        if (distance < 500 && distance < minDistance) {
          minDistance = distance;
          nearestVenue = venue;
        }
      }
    }

    if (nearestVenue != null) {
      setState(() {
        _selectedVenue = nearestVenue!.name;
        _selectedVenueId = nearestVenue.id;
      });
      _loadVenueHours(nearestVenue.id);
    }
  }

  // ---------- Venue Opening Hours Helpers ----------

  /// Load opening hours for the selected venue from Firestore cache
  Future<void> _loadVenueHours(String venueId) async {
    if (!mounted) return;
    setState(() => _loadingHours = true);
    try {
      final cacheDoc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(venueId)
          .collection('cache')
          .doc('googlePlaces')
          .get();
      if (!mounted) return;
      if (cacheDoc.exists && cacheDoc.data() != null) {
        final data = cacheDoc.data()!;
        final opening = (data['openingHours'] as Map<String, dynamic>?) ?? {};
        List<String> weekdayText =
            (opening['weekday_text'] as List?)?.cast<String>() ?? [];
        final periods = (opening['periods'] as List?) ?? [];
        final utcOffset = data['utcOffset'] as int?;
        final businessStatus = data['businessStatus'] as String?;
        final types =
            (data['types'] as List?)?.cast<String>() ?? const <String>[];

        // Airports with no hours data → assume open 24 hours
        if (weekdayText.isEmpty && types.contains('airport')) {
          weekdayText = const [
            'Sunday: Open 24 hours',
            'Monday: Open 24 hours',
            'Tuesday: Open 24 hours',
            'Wednesday: Open 24 hours',
            'Thursday: Open 24 hours',
            'Friday: Open 24 hours',
            'Saturday: Open 24 hours',
          ];
        }

        // Ensure Sunday-first order
        if (weekdayText.isNotEmpty &&
            weekdayText.first.toLowerCase().startsWith('monday')) {
          final idxSun = weekdayText.indexWhere(
            (l) => l.toLowerCase().startsWith('sunday'),
          );
          if (idxSun > 0) {
            weekdayText = [
              ...weekdayText.sublist(idxSun),
              ...weekdayText.sublist(0, idxSun),
            ];
          }
        }
        setState(() {
          _venueWeekdayText = weekdayText;
          _venuePeriods = periods;
          _venueUtcOffset = utcOffset;
          _venueBusinessStatus = businessStatus;
          _loadingHours = false;
        });
      } else {
        setState(() {
          _venueWeekdayText = [];
          _venuePeriods = [];
          _venueUtcOffset = null;
          _venueBusinessStatus = null;
          _loadingHours = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHours = false);
    }
  }

  bool _venueIsOpen24Hours() {
    // Check weekday_text (e.g. "Sunday: Open 24 hours")
    if (_venueWeekdayText.isNotEmpty) {
      final all24 = _venueWeekdayText.every(
        (line) =>
            line.toLowerCase().contains('24') ||
            line.toLowerCase().contains('open 24'),
      );
      if (all24) return true;
    }
    // Check periods: single period with no 'close' → open 24/7
    if (_venuePeriods.length == 1) {
      final period = _venuePeriods.first;
      if (period is Map<String, dynamic> && !period.containsKey('close')) {
        return true;
      }
    }
    return false;
  }

  bool _venueIsTemporarilyClosed() {
    return _venueBusinessStatus?.toLowerCase() == 'closed_temporarily';
  }

  int? _parseHHMM(String time) {
    if (time.length != 4) return null;
    final h = int.tryParse(time.substring(0, 2));
    final m = int.tryParse(time.substring(2, 4));
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// Get venue hours for a specific date from periods data
  ({TimeOfDay? open, TimeOfDay? close, bool overnight, bool closed})
  _getVenueHoursForDate(DateTime date) {
    if (_venueIsTemporarilyClosed()) {
      return (open: null, close: null, overnight: false, closed: true);
    }
    if (_venueIsOpen24Hours()) {
      return (
        open: const TimeOfDay(hour: 0, minute: 0),
        close: const TimeOfDay(hour: 23, minute: 59),
        overnight: false,
        closed: false,
      );
    }
    if (_venuePeriods.isEmpty && _venueWeekdayText.isEmpty) {
      return (
        open: const TimeOfDay(hour: 0, minute: 0),
        close: const TimeOfDay(hour: 23, minute: 59),
        overnight: false,
        closed: false,
      );
    }
    final dartWeekday = date.weekday;
    final googleDay = dartWeekday == 7 ? 0 : dartWeekday;
    for (final period in _venuePeriods) {
      if (period is! Map<String, dynamic>) continue;
      final openData = period['open'] as Map<String, dynamic>?;
      final closeData = period['close'] as Map<String, dynamic>?;
      if (openData == null) continue;
      final openDay = openData['day'] as int?;
      final openTime = openData['time'] as String?;
      if (openDay != googleDay || openTime == null) continue;
      final openMin = _parseHHMM(openTime);
      if (openMin == null) continue;
      if (closeData == null) {
        return (
          open: TimeOfDay(hour: openMin ~/ 60, minute: openMin % 60),
          close: const TimeOfDay(hour: 23, minute: 59),
          overnight: false,
          closed: false,
        );
      }
      final closeDay = closeData['day'] as int?;
      final closeTime = closeData['time'] as String?;
      if (closeDay == null || closeTime == null) continue;
      final closeMin = _parseHHMM(closeTime);
      if (closeMin == null) continue;
      final isOvernight = closeDay != openDay;
      return (
        open: TimeOfDay(hour: openMin ~/ 60, minute: openMin % 60),
        close: TimeOfDay(hour: closeMin ~/ 60, minute: closeMin % 60),
        overnight: isOvernight,
        closed: false,
      );
    }
    // Fallback: parse from weekday_text
    const dayLabels = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final line = _venueWeekdayText.firstWhere(
      (l) => l.toLowerCase().startsWith(dayLabels[googleDay].toLowerCase()),
      orElse: () => '',
    );
    if (line.isEmpty || line.toLowerCase().contains('closed')) {
      return (open: null, close: null, overnight: false, closed: true);
    }
    if (line.toLowerCase().contains('24')) {
      return (
        open: const TimeOfDay(hour: 0, minute: 0),
        close: const TimeOfDay(hour: 23, minute: 59),
        overnight: false,
        closed: false,
      );
    }
    return (
      open: const TimeOfDay(hour: 0, minute: 0),
      close: const TimeOfDay(hour: 23, minute: 59),
      overnight: false,
      closed: false,
    );
  }

  String _getVenueHoursStringForDate(DateTime date) {
    if (_venueIsTemporarilyClosed()) return 'temporarily closed';
    if (_venueIsOpen24Hours()) return 'open 24 hours';
    // No hours data at all
    if (_venuePeriods.isEmpty && _venueWeekdayText.isEmpty) {
      return 'not available';
    }
    final hours = _getVenueHoursForDate(date);
    if (hours.closed) return 'closed';
    if (hours.open == null || hours.close == null) return 'not available';
    final openStr = _formatTime12h(hours.open!);
    final closeStr = _formatTime12h(hours.close!);
    if (hours.overnight) return '$openStr - $closeStr (next day)';
    return '$openStr - $closeStr';
  }

  /// Whether venue is closed / temporarily closed on date → disable time
  bool _venueIsClosedOnDate(DateTime date) {
    if (_venueIsTemporarilyClosed()) return true;
    final hours = _getVenueHoursForDate(date);
    return hours.closed;
  }

  /// Whether the venue allows selecting "next day" as end date.
  /// True when: open-24h, not-available, or venue is overnight on the date.
  bool _venueAllowsNextDay(DateTime date) {
    if (_venueIsOpen24Hours()) return true;
    if (_venuePeriods.isEmpty && _venueWeekdayText.isEmpty) return true;
    final hours = _getVenueHoursForDate(date);
    return hours.overnight;
  }

  // ---------- End Venue Hours Helpers ----------

  bool get _canAddPhone {
    final phone = _phoneController.text.trim();
    return phone.length == 9 && RegExp(r'^\d{9}$').hasMatch(phone);
  }

  Future<void> _addPhoneNumber() async {
    // Prevent multiple clicks while processing
    if (_isAddingPhone) return;

    if (!_canAddPhone) {
      setState(() {
        _isPhoneInputValid = false;
        _phoneInputError = 'Enter 9 digits';
      });
      return;
    }

    final phone = '+966${_phoneController.text.trim()}';

    // Check if already added (instant check, no network)
    if (_selectedFriends.any((f) => f.phone == phone)) {
      setState(() {
        _isPhoneInputValid = false;
        _phoneInputError = 'Friend already added';
      });
      return;
    }

    // Check self-request using cached phone (instant, no network)
    if (_cachedMyPhone != null &&
        _cachedMyPhone!.isNotEmpty &&
        _cachedMyPhone == phone) {
      setState(() {
        _isPhoneInputValid = false;
        _phoneInputError = 'You can\'t send a request to yourself';
      });
      return;
    }

    // Start loading - prevent further clicks
    setState(() => _isAddingPhone = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        // Unfocus phone field to hide keyboard
        _phoneFocusNode.unfocus();
        // Clear field and show invite dialog
        setState(() {
          _isAddingPhone = false;
          _phoneController.clear();
          _isPhoneInputValid = true;
          _phoneInputError = null;
        });
        _showInviteToMadarDialog(phone);
        return;
      }

      final userData = query.docs.first.data();
      final firstName = (userData['firstName'] ?? '').toString();
      final lastName = (userData['lastName'] ?? '').toString();
      var displayName = '$firstName $lastName'.trim();
      if (displayName.isEmpty) displayName = phone;

      // Keep keyboard open for adding more numbers
      setState(() {
        _isAddingPhone = false;
        _selectedFriends.add(
          Friend(
            name: displayName,
            phone: phone,
            isFavorite: false,
            isFromPhoneInput: true,
          ),
        );
        _phoneController.clear();
        _isPhoneInputValid = true;
        _phoneInputError = null;
      });
      // Re-check overlaps if time is already set
      _checkOverlapsForFriends();
    } catch (e) {
      setState(() {
        _isAddingPhone = false;
        _isPhoneInputValid = false;
        _phoneInputError = 'Could not verify this number. Try again.';
      });
    }
  }

  static const String _inviteMessage =
      "Hey! I'm using Madar for location sharing.\n"
      "Join me using this invite link:\n"
      "https://madar.app/invite";

  /// Shows "Invite to Madar?" popup when phone number not in DB
  void _showInviteToMadarDialog(String phone) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogPadding = screenWidth < 360 ? 20.0 : 28.0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
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
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.kGreen.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_add_rounded,
                          size: 42,
                          color: AppColors.kGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Invite to Madar?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.kGreen,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "This person isn't on Madar yet.\nInvite them to start sharing location.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _shareInvite(phone);
                        },
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
                          'Send Invite',
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
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: Icon(Icons.close, size: 22, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Opens the system share sheet directly with the invite message
  Future<void> _shareInvite(String phone) async {
    try {
      await Share.share(_inviteMessage, subject: 'Invite to Madar');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open share. Link copied instead.'),
            backgroundColor: AppColors.kGreen,
          ),
        );
        Clipboard.setData(ClipboardData(text: _inviteMessage));
      }
    }
  }

  void _removeFriend(Friend friend) {
    setState(() {
      _selectedFriends.remove(friend);
      // Remove from scheduled overlaps too
      _scheduledOverlapFriends.removeWhere((f) => f['phone'] == friend.phone);
    });
  }

  void _toggleFavorite(Friend friend) {
    setState(() {
      final index = _selectedFriends.indexOf(friend);
      if (index != -1) {
        _selectedFriends[index] = Friend(
          name: friend.name,
          phone: friend.phone,
          isFavorite: !friend.isFavorite,
          isFromPhoneInput: friend.isFromPhoneInput,
        );
      }
    });
  }

  Future<void> _showFavoritesList() async {
    // Dismiss keyboard when opening favorites list
    FocusScope.of(context).unfocus();

    final result = await showModalBottomSheet<List<Friend>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FavoritesListSheet(),
    );

    if (result != null) {
      setState(() {
        for (final friend in result) {
          // Only add if not already in list
          if (!_selectedFriends.any((f) => f.phone == friend.phone)) {
            _selectedFriends.add(friend);
          }
        }
      });
      // Re-check overlaps if time is already set
      _checkOverlapsForFriends();
    }
  }

  Future<void> _showVenueSelection() async {
    // Dismiss keyboard when opening venue selector
    FocusScope.of(context).unfocus();

    final result = await showModalBottomSheet<VenueOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VenueSelectionSheet(venues: _allVenues),
    );

    if (result != null) {
      final venueChanged = _selectedVenueId != result.id;
      setState(() {
        _selectedVenue = result.name;
        _selectedVenueId = result.id;
        if (venueChanged) {
          // Reset date and time when venue changes
          _selectedDate = null;
          _selectedEndDate = null;
          _startTime = null;
          _endTime = null;
        }
      });
      // Load opening hours for the new venue
      if (venueChanged) {
        _loadVenueHours(result.id);
        // Clear overlap state and restore removed friends
        _clearOverlapState();
      }
    }
  }

  Future<void> _selectDate() async {
    // Dismiss keyboard when opening date picker
    FocusScope.of(context).unfocus();

    // Must select venue first
    if (_selectedVenueId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a venue first')),
      );
      return;
    }

    final now = DateTime.now();
    final firstDate = now;
    final lastDate = now.add(const Duration(days: 30));

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.kGreen,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final dateChanged =
          _selectedDate == null ||
          picked.year != _selectedDate!.year ||
          picked.month != _selectedDate!.month ||
          picked.day != _selectedDate!.day;
      setState(() {
        _selectedDate = picked;
        if (dateChanged) {
          // Date actually changed → reset everything
          _selectedEndDate = picked;
          _startTime = null;
          _endTime = null;
        }
        // If same date re-selected, keep existing end date, start/end times
      });

      // Clear overlap state immediately when date changes
      if (dateChanged) {
        _clearOverlapState();
      }

      // Check if venue is closed on this date
      final hours = _getVenueHoursForDate(picked);
      if (hours.closed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The venue is closed on this date')),
          );
        }
      }
    }
  }

  Future<void> _selectEndDate() async {
    FocusScope.of(context).unfocus();
    if (_selectedDate == null) return;

    final startDate = _selectedDate!;
    final nextDay = startDate.add(const Duration(days: 1));
    final allowsNext = _venueAllowsNextDay(startDate);

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Text(
                    'Select End Date',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Same day option
                _buildEndDateOption(
                  ctx: ctx,
                  date: startDate,
                  isNextDay: false,
                  isSelected:
                      _selectedEndDate != null &&
                      startDate.year == _selectedEndDate!.year &&
                      startDate.month == _selectedEndDate!.month &&
                      startDate.day == _selectedEndDate!.day,
                  enabled: true,
                ),
                // Next day option
                _buildEndDateOption(
                  ctx: ctx,
                  date: nextDay,
                  isNextDay: true,
                  isSelected:
                      _selectedEndDate != null &&
                      nextDay.year == _selectedEndDate!.year &&
                      nextDay.month == _selectedEndDate!.month &&
                      nextDay.day == _selectedEndDate!.day,
                  enabled: allowsNext,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedEndDate = picked;
        _endTime = null;
      });
      // Clear overlap state when end date changes
      _clearOverlapState();
    }
  }

  Widget _buildEndDateOption({
    required BuildContext ctx,
    required DateTime date,
    required bool isNextDay,
    required bool isSelected,
    required bool enabled,
  }) {
    return InkWell(
      onTap: enabled ? () => Navigator.pop(ctx, date) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.kGreen.withOpacity(0.1)
              : (!enabled ? Colors.grey[100] : Colors.grey[50]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.kGreen
                : (!enabled ? Colors.grey.shade200 : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isNextDay ? Icons.nights_stay_outlined : Icons.today,
              color: isSelected
                  ? AppColors.kGreen
                  : (!enabled ? Colors.grey[400] : Colors.grey[600]),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEE d MMM yyyy').format(date),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.kGreen
                          : (!enabled ? Colors.grey[400] : Colors.black87),
                    ),
                  ),
                  Text(
                    isNextDay
                        ? (enabled
                              ? 'Next day (overnight)'
                              : 'Not available – venue closes before midnight')
                        : 'Same day as start',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: !enabled && isNextDay
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: isSelected
                          ? AppColors.kGreen
                          : (!enabled ? Colors.red[700] : Colors.grey[500]),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.kGreen, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _selectStartTime() async {
    FocusScope.of(context).unfocus();

    if (_selectedVenueId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a venue first')),
      );
      return;
    }
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date first')),
      );
      return;
    }

    final date = _selectedDate!;

    // Block if venue is closed or temporarily closed
    if (_venueIsClosedOnDate(date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _venueIsTemporarilyClosed()
                ? 'The venue is temporarily closed'
                : 'The venue is closed on this date',
          ),
        ),
      );
      return;
    }

    final venueHours = _getVenueHoursForDate(date);
    final venueOpen = venueHours.open ?? const TimeOfDay(hour: 0, minute: 0);
    final venueClose =
        venueHours.close ?? const TimeOfDay(hour: 23, minute: 59);

    DateTime dayStart = DateTime(
      date.year,
      date.month,
      date.day,
      venueOpen.hour,
      venueOpen.minute,
    );
    // For overnight venues or open-24h or not-available, allow up to 23:59
    final DateTime dayEnd;
    if (venueHours.overnight ||
        _venueIsOpen24Hours() ||
        (_venuePeriods.isEmpty && _venueWeekdayText.isEmpty)) {
      dayEnd = DateTime(date.year, date.month, date.day, 23, 59);
    } else {
      dayEnd = DateTime(
        date.year,
        date.month,
        date.day,
        venueClose.hour,
        venueClose.minute,
      );
    }

    final now = DateTime.now();
    final isToday =
        now.year == date.year && now.month == date.month && now.day == date.day;
    if (isToday && now.isAfter(dayStart)) dayStart = now;

    if (dayStart.isAfter(dayEnd)) return;

    DateTime initial;
    if (_startTime != null) {
      initial = DateTime(
        date.year,
        date.month,
        date.day,
        _startTime!.hour,
        _startTime!.minute,
      );
      if (initial.isBefore(dayStart)) initial = dayStart;
    } else {
      initial = dayStart;
    }

    final picked = await _showCupertinoDateTimePicker(
      title: 'Start Time',
      initial: initial,
      minimum: dayStart,
      maximum: dayEnd,
    );
    if (picked == null) return;

    setState(() {
      _startTime = TimeOfDay(hour: picked.hour, minute: picked.minute);
      _endTime = null;
      _selectedEndDate = _selectedDate; // reset end date to start date
    });
    // Clear overlap state when start time changes (end time will be null)
    _clearOverlapState();
  }

  Future<void> _selectEndTime() async {
    FocusScope.of(context).unfocus();

    if (_selectedDate == null || _startTime == null) return;

    final date = _selectedDate!;
    final nextDay = date.add(const Duration(days: 1));
    final venueHours = _getVenueHoursForDate(date);
    final venueClose =
        venueHours.close ?? const TimeOfDay(hour: 23, minute: 59);
    final isOpen24 = _venueIsOpen24Hours();
    final noHoursData = _venuePeriods.isEmpty && _venueWeekdayText.isEmpty;
    final allowsNextDay = _venueAllowsNextDay(date);

    final endDate = _selectedEndDate ?? date;
    final isNextDay =
        endDate.day != date.day ||
        endDate.month != date.month ||
        endDate.year != date.year;

    final startMin = _startTime!.hour * 60 + _startTime!.minute;

    // ── CASE 1: User explicitly chose next-day end date ──
    if (isNextDay) {
      // Determine max time on the next day
      int maxMinOnNextDay;
      if (isOpen24 || noHoursData) {
        // Max = startTime - 1 min → total 23h59m
        maxMinOnNextDay = (startMin - 1 + 1440) % 1440;
      } else {
        // Overnight venue → venue close on next day
        maxMinOnNextDay = venueClose.hour * 60 + venueClose.minute;
        // Cap at startTime - 1 min (23h59m max)
        final cap = (startMin - 1 + 1440) % 1440;
        if (maxMinOnNextDay > cap) maxMinOnNextDay = cap;
      }

      final pickerMin = DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        0,
        0,
      );
      final pickerMax = DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        maxMinOnNextDay ~/ 60,
        maxMinOnNextDay % 60,
      );

      if (pickerMin.isAfter(pickerMax)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid end time on next day')),
        );
        return;
      }

      DateTime initial;
      if (_endTime != null) {
        initial = DateTime(
          nextDay.year,
          nextDay.month,
          nextDay.day,
          _endTime!.hour,
          _endTime!.minute,
        );
        if (initial.isBefore(pickerMin)) initial = pickerMin;
        if (initial.isAfter(pickerMax)) initial = pickerMin;
      } else {
        initial = pickerMin;
      }

      final picked = await _showCupertinoDateTimePicker(
        title: 'End Time (next day)',
        initial: initial,
        minimum: pickerMin,
        maximum: pickerMax,
      );
      if (picked == null) return;

      setState(() {
        _endTime = TimeOfDay(hour: picked.hour, minute: picked.minute);
        _selectedEndDate = nextDay;
      });
      await _checkOverlapsForFriends();
      return;
    }

    // ── CASE 2: Same-day end date, overnight / 24h / no-data venue ──
    if (allowsNextDay) {
      // Show full 12-hour wheel (00:00 - 23:59) so user can pick times
      // past midnight. We validate after selection.
      final pickerMin = DateTime(date.year, date.month, date.day, 0, 0);
      final pickerMax = DateTime(date.year, date.month, date.day, 23, 59);

      // Default initial to start + 10 min
      DateTime initial;
      if (_endTime != null) {
        initial = DateTime(
          date.year,
          date.month,
          date.day,
          _endTime!.hour,
          _endTime!.minute,
        );
      } else {
        final def = DateTime(
          date.year,
          date.month,
          date.day,
          _startTime!.hour,
          _startTime!.minute,
        ).add(const Duration(minutes: 10));
        initial = DateTime(
          date.year,
          date.month,
          date.day,
          def.hour,
          def.minute,
        );
      }
      if (initial.isBefore(pickerMin)) initial = pickerMin;
      if (initial.isAfter(pickerMax)) initial = pickerMax;

      final picked = await _showCupertinoDateTimePicker(
        title: 'End Time',
        initial: initial,
        minimum: pickerMin,
        maximum: pickerMax,
      );
      if (picked == null) return;

      final endMin = picked.hour * 60 + picked.minute;
      final wrapsToNextDay = endMin <= startMin;

      // Calculate duration
      int durationMin;
      if (wrapsToNextDay) {
        durationMin = (1440 - startMin) + endMin;
      } else {
        durationMin = endMin - startMin;
      }

      // Validate duration
      if (durationMin < 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duration must be at least 10 minutes')),
        );
        return;
      }
      if (durationMin > 1439) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum duration is 23 hours and 59 minutes'),
          ),
        );
        return;
      }

      // For overnight venues, validate end time against venue close
      if (wrapsToNextDay &&
          venueHours.overnight &&
          !(isOpen24 || noHoursData)) {
        final closeMin = venueClose.hour * 60 + venueClose.minute;
        if (endMin > closeMin) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Venue closes at ${_formatTime12h(venueClose)}'),
            ),
          );
          return;
        }
      }

      setState(() {
        _endTime = TimeOfDay(hour: picked.hour, minute: picked.minute);
        _selectedEndDate = wrapsToNextDay ? nextDay : date;
      });
      await _checkOverlapsForFriends();
      return;
    }

    // ── CASE 3: Regular venue (non-overnight, same day only) ──
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final minEnd = start.add(const Duration(minutes: 10));
    final maxEnd = DateTime(
      date.year,
      date.month,
      date.day,
      venueClose.hour,
      venueClose.minute,
    );

    if (minEnd.isAfter(maxEnd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough time before venue closes (min 10 min)'),
        ),
      );
      return;
    }

    final pickerMin = DateTime(
      date.year,
      date.month,
      date.day,
      minEnd.hour,
      minEnd.minute,
    );
    final pickerMax = DateTime(
      date.year,
      date.month,
      date.day,
      maxEnd.hour,
      maxEnd.minute,
    );

    DateTime initial;
    if (_endTime != null) {
      initial = DateTime(
        date.year,
        date.month,
        date.day,
        _endTime!.hour,
        _endTime!.minute,
      );
      if (initial.isBefore(pickerMin)) initial = pickerMin;
      if (initial.isAfter(pickerMax)) initial = pickerMin;
    } else {
      initial = pickerMin;
    }

    final picked = await _showCupertinoDateTimePicker(
      title: 'End Time',
      initial: initial,
      minimum: pickerMin,
      maximum: pickerMax,
    );
    if (picked == null) return;

    setState(() {
      _endTime = TimeOfDay(hour: picked.hour, minute: picked.minute);
      _selectedEndDate = date;
    });
    await _checkOverlapsForFriends();
  }

  /// Clear all overlap state and restore removed friends back to selected list.
  void _clearOverlapState() {
    setState(() {
      // Restore previously removed friends
      for (final f in _activeOverlapRemovedFriends) {
        if (!_selectedFriends.any((s) => s.phone == f.phone)) {
          _selectedFriends.add(f);
        }
      }
      _activeOverlapRemovedFriends.clear();
      _scheduledOverlapFriends.clear();
      _scheduledOverlapDocIds.clear();
    });
  }

  /// Check overlaps for all selected friends after time is fully set.
  /// - Active overlaps → auto-remove friend, show single red message with names
  /// - Scheduled overlaps → stored for dialog when user submits
  Future<void> _checkOverlapsForFriends() async {
    // Build the full list to check: current selected + previously removed
    // Do NOT add removed friends back to _selectedFriends (avoids flicker)
    final allFriendsToCheck = <Friend>[
      ..._selectedFriends,
      ..._activeOverlapRemovedFriends.where(
        (f) => !_selectedFriends.any((s) => s.phone == f.phone),
      ),
    ];

    if (_selectedDate == null ||
        _startTime == null ||
        _endTime == null ||
        _selectedEndDate == null ||
        _selectedVenueId == null ||
        allFriendsToCheck.isEmpty) {
      setState(() {
        // Restore removed friends since there's nothing to check
        for (final f in _activeOverlapRemovedFriends) {
          if (!_selectedFriends.any((s) => s.phone == f.phone)) {
            _selectedFriends.add(f);
          }
        }
        _activeOverlapRemovedFriends = [];
        _scheduledOverlapFriends.clear();
        _scheduledOverlapDocIds.clear();
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final date = _selectedDate!;
    final endDate = _selectedEndDate!;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      _endTime!.hour,
      _endTime!.minute,
    );
    if (!end.isAfter(start)) return;

    final venueId = _selectedVenueId!;
    final newScheduledFriends = <Map<String, String>>[];
    final newScheduledDocIds = <String>[];
    final friendsToRemove = <Friend>[];

    // Normalize phone for lookup
    String normalizePhone(String phone) {
      String p = phone.replaceAll(RegExp(r'[^\d+]'), '');
      if (p.startsWith('0')) p = '+966${p.substring(1)}';
      if (p.startsWith('5') && p.length == 9) p = '+966$p';
      if (p.startsWith('966')) p = '+$p';
      return p;
    }

    // Resolve UIDs in parallel (using cache) — check ALL friends including previously removed
    final friendsCopy = List<Friend>.from(allFriendsToCheck);
    final uidFutures = friendsCopy.map((friend) async {
      final phone = normalizePhone(friend.phone);
      if (_phoneToUidCache.containsKey(phone)) {
        return MapEntry(friend, _phoneToUidCache[phone]!);
      }
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return MapEntry(friend, '');
      final uid = snap.docs.first.id;
      _phoneToUidCache[phone] = uid;
      return MapEntry(friend, uid);
    }).toList();
    final uidResults = await Future.wait(uidFutures);

    // Filter out friends with no UID
    final validEntries = uidResults.where((e) => e.value.isNotEmpty).toList();

    // Check overlaps in parallel
    final overlapFutures = validEntries.map((entry) async {
      final friend = entry.key;
      final receiverUid = entry.value;
      final snap = await FirebaseFirestore.instance
          .collection('trackRequests')
          .where('senderId', isEqualTo: user.uid)
          .where('receiverId', isEqualTo: receiverUid)
          .where('venueId', isEqualTo: venueId)
          .where('status', whereIn: ['pending', 'accepted'])
          .get();

      final results = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final existingStart = (data['startAt'] as Timestamp).toDate();
        final existingEnd = (data['endAt'] as Timestamp).toDate();
        final existingStatus = data['status'] as String? ?? '';

        if (start.isBefore(existingEnd) && existingStart.isBefore(end)) {
          final now = DateTime.now();
          final isActive =
              existingStatus == 'accepted' &&
              !now.isBefore(existingStart) &&
              now.isBefore(existingEnd);
          results.add({
            'friend': friend,
            'uid': receiverUid,
            'docId': doc.id,
            'isActive': isActive,
          });
        }
      }
      return results;
    }).toList();
    final overlapResults = await Future.wait(overlapFutures);

    for (final results in overlapResults) {
      for (final r in results) {
        final friend = r['friend'] as Friend;
        if (r['isActive'] == true) {
          if (!friendsToRemove.any((f) => f.phone == friend.phone)) {
            friendsToRemove.add(friend);
          }
        } else {
          newScheduledFriends.add({
            'name': friend.name,
            'phone': friend.phone,
            'uid': r['uid'] as String,
          });
          newScheduledDocIds.add(r['docId'] as String);
        }
      }
    }

    if (!mounted) return;

    // Determine which previously removed friends are now clear (no longer overlap)
    final previouslyRemoved = List<Friend>.from(_activeOverlapRemovedFriends);
    final stillOverlapping = friendsToRemove.map((f) => f.phone).toSet();

    setState(() {
      // Restore previously removed friends that no longer have active overlap
      for (final f in previouslyRemoved) {
        if (!stillOverlapping.contains(f.phone) &&
            !_selectedFriends.any((s) => s.phone == f.phone)) {
          _selectedFriends.add(f);
        }
      }

      _activeOverlapRemovedFriends = friendsToRemove;
      _scheduledOverlapFriends = newScheduledFriends;
      _scheduledOverlapDocIds = newScheduledDocIds;

      // Remove friends with active overlap from selected list
      for (final f in friendsToRemove) {
        _selectedFriends.removeWhere((s) => s.phone == f.phone);
      }
    });

    // Scroll to the overlap message only if there are new removals
    final hadNewRemovals = friendsToRemove.any(
      (f) => !previouslyRemoved.any((p) => p.phone == f.phone),
    );
    if (hadNewRemovals) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted && _overlapMsgKey.currentContext != null) {
        Scrollable.ensureVisible(
          _overlapMsgKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  /// Show scheduled overlap dialog matching the app's standard dialog design.
  Future<bool?> _showScheduledOverlapDialog() {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Overlapping Requests',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You already have scheduled requests that overlap with the selected time.',
                  style: TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 16),
                // Friends list with vertical green line (matches app design)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: AppColors.kGreen,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              int i = 0;
                              i < _scheduledOverlapFriends.length;
                              i++
                            ) ...[
                              if (i > 0) const SizedBox(height: 8),
                              Text(
                                '${_scheduledOverlapFriends[i]['name']} (${_scheduledOverlapFriends[i]['phone']})',
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'The existing scheduled requests for these friends will be cancelled.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.red[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Flexible(
                  flex: 2,
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Go Back',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  flex: 3,
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.kGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Replace & Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<DateTime?> _showCupertinoDateTimePicker({
    required DateTime initial,
    required DateTime minimum,
    required DateTime maximum,
    required String title,
  }) async {
    DateTime temp = initial.isBefore(minimum) ? minimum : initial;

    return showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final okEnabled = !temp.isBefore(minimum) && !temp.isAfter(maximum);

            return SafeArea(
              top: false,
              child: Container(
                height: 420,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),

                    // Picker
                    Expanded(
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        use24hFormat: false,
                        minimumDate: minimum,
                        maximumDate: maximum,
                        initialDateTime: temp,
                        onDateTimeChanged: (d) {
                          if (d.isBefore(minimum)) d = minimum;
                          if (d.isAfter(maximum)) d = maximum;

                          setModalState(() => temp = d);
                        },
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: okEnabled
                              ? () => Navigator.pop(context, temp)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.kGreen,
                            // قريب من لون الصورة
                            disabledBackgroundColor: Colors.grey.shade300,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Ok',
                            style: TextStyle(
                              color: okEnabled
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Cancel
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 18, color: Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool get _canSubmit {
    return _selectedFriends.isNotEmpty &&
        _selectedVenue != null &&
        _selectedDate != null &&
        _selectedEndDate != null &&
        _startTime != null &&
        _endTime != null;
  }

  Future<void> _submitRequest() async {
    // Prevent multiple clicks
    if (_isSubmitting || !_canSubmit) return;
    _isSubmitting = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isSubmitting = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in')));
      return;
    }

    // Validate time
    final date = _selectedDate!;
    final endDate = _selectedEndDate ?? date;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      _endTime!.hour,
      _endTime!.minute,
    );

    if (!end.isAfter(start)) {
      _isSubmitting = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    final durationMinutes = end.difference(start).inMinutes;
    if (durationMinutes < 10) {
      _isSubmitting = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duration must be at least 10 minutes')),
      );
      return;
    }
    if (durationMinutes > 1439) {
      _isSubmitting = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum duration is 23 hours and 59 minutes'),
        ),
      );
      return;
    }

    try {
      final List<Friend> friends = List.from(_selectedFriends);

      // Use cached sender info if available, otherwise fetch
      String senderName = _cachedMyName ?? '';
      String senderPhone = _cachedMyPhone ?? '';

      // Fetch sender info only if not cached
      final Future<DocumentSnapshot>? senderFuture = senderPhone.isEmpty
          ? FirebaseFirestore.instance.collection('users').doc(user.uid).get()
          : null;

      // For each friend, query by phone in parallel
      final receiverFutures = friends.map((f) async {
        final q = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: f.phone)
            .limit(1)
            .get();
        if (q.docs.isEmpty) return null;
        final doc = q.docs.first;
        final data = doc.data();
        final name = ('${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
            .trim();
        return {
          'uid': doc.id,
          'phone': f.phone,
          'name': name.isEmpty ? f.phone : name,
        };
      }).toList();

      // Wait for all queries in parallel
      final receiverResults = await Future.wait(receiverFutures);

      // If sender needed fetching, await it
      if (senderFuture != null) {
        final senderDoc = await senderFuture;
        final senderData = senderDoc.data() as Map<String, dynamic>? ?? {};
        senderName =
            ('${senderData['firstName'] ?? ''} ${senderData['lastName'] ?? ''}')
                .trim();
        senderPhone = (senderData['phone'] ?? '').toString();
      }

      if (senderPhone.isEmpty) {
        _isSubmitting = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your phone number is missing in your profile'),
          ),
        );
        return;
      }

      // Check receiver results
      final resolved = <Map<String, String>>[];
      for (var i = 0; i < receiverResults.length; i++) {
        final r = receiverResults[i];
        if (r == null) {
          _isSubmitting = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User not found for ${friends[i].phone}')),
          );
          return;
        }
        resolved.add(r);
      }

      // --- Scheduled Overlap Handling ---
      // If scheduled overlaps were detected (from end time selection), show dialog
      if (_scheduledOverlapFriends.isNotEmpty &&
          _scheduledOverlapDocIds.isNotEmpty &&
          mounted) {
        final proceed = await _showScheduledOverlapDialog();
        if (proceed != true) {
          setState(() => _isSubmitting = false);
          return;
        }
        // Cancel the overlapping scheduled requests with 'cancelled' status
        final cancelBatch = FirebaseFirestore.instance.batch();
        for (final docId in _scheduledOverlapDocIds) {
          cancelBatch.update(
            FirebaseFirestore.instance.collection('trackRequests').doc(docId),
            {'status': 'cancelled'},
          );
        }
        await cancelBatch.commit();
        // Clear overlap state after cancellation
        _scheduledOverlapFriends.clear();
        _scheduledOverlapDocIds.clear();
      }

      // Create one request per receiver but same batchId
      final batchId = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';
      final col = FirebaseFirestore.instance.collection('trackRequests');
      final writeBatch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();

      for (final r in resolved) {
        final docRef = col.doc();
        writeBatch.set(docRef, {
          'senderId': user.uid,
          'senderName': senderName.isEmpty ? senderPhone : senderName,
          'senderPhone': senderPhone,

          'receiverId': r['uid'],
          'receiverPhone': r['phone'],
          'receiverName': r['name'],

          'venueId': _selectedVenueId,
          'venueName': _selectedVenue,

          'startAt': Timestamp.fromDate(start),
          'endAt': Timestamp.fromDate(end),
          'durationMinutes': durationMinutes,

          'status': 'pending',
          'createdAt': now,
          'batchId': batchId,
          'startNotifiedUsers': [],
        });
      }

      await writeBatch.commit();

      if (!mounted) return;
      Navigator.pop(context);

      SnackbarHelper.showSuccess(
        context,
        'Tracking request sent to ${resolved.length} friend(s).',
      );
    } catch (e) {
      _isSubmitting = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send request: $e')));
      }
    }
  }

  /// Build venue opening hours widget (like venue page)
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
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person_search_outlined,
                    color: AppColors.kGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create Track Request',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Select friends and set tracking duration',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
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
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              controller: _mainScrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Venue Selection
                  const Text(
                    'Select Venue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: _showVenueSelection,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place,
                            color: AppColors.kGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedVenue ?? 'Select venue',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: _selectedVenue != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _selectedVenue != null
                                    ? Colors.black87
                                    : Colors.grey[400],
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.grey[400],
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Select Friends Section
                  const Text(
                    'Select Friends to Track',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone Number Input with Add Button
                  // Phone Number Input with Add Button + Fixed Error Space
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _phoneController,
                              focusNode: _phoneFocusNode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _isPhoneInputValid = true;
                                  _phoneInputError = null;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Phone number',
                                hintStyle: TextStyle(
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w400,
                                ),
                                prefixText: _phoneController.text.isEmpty
                                    ? null
                                    : '+966 ',
                                prefixStyle: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                suffixIcon: _isPhoneFocused
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.contacts,
                                          color: AppColors.kGreen,
                                        ),
                                        onPressed: _pickContact,
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.grey[50],

                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _isPhoneInputValid
                                        ? Colors.grey.shade300
                                        : AppColors.kError,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _isPhoneInputValid
                                        ? AppColors.kGreen
                                        : AppColors.kError,
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

                          GestureDetector(
                            onTap: _canAddPhone ? _addPhoneNumber : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: _canAddPhone
                                    ? AppColors.kGreen
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Add',
                                style: TextStyle(
                                  color: _canAddPhone
                                      ? Colors.white
                                      : Colors.grey[500],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

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
                      ),

                      const SizedBox(height: 6),
                      SizedBox(
                        height: 18,
                        child: (!_isPhoneInputValid && _phoneInputError != null)
                            ? Text(
                                _phoneInputError!,
                                style: const TextStyle(
                                  color: AppColors.kError,
                                  fontSize: 13,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Active overlap removal message (single red card listing all removed friends)
                  if (_activeOverlapRemovedFriends.isNotEmpty)
                    Container(
                      key: _overlapMsgKey,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red[400],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _activeOverlapRemovedFriends.length == 1
                                      ? '${_activeOverlapRemovedFriends.first.name} (${_activeOverlapRemovedFriends.first.phone}) was removed from this request due to an active tracking overlap.'
                                      : 'The following friends were removed from this request due to active tracking overlaps:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    // Just dismiss the message, don't restore friends
                                    _activeOverlapRemovedFriends = [];
                                  });
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                          if (_activeOverlapRemovedFriends.length > 1) ...[
                            const SizedBox(height: 8),
                            for (final f in _activeOverlapRemovedFriends)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 28),
                                    Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.red[300],
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${f.name} (${f.phone})',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.red[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),

                  // Selected Friends List
                  if (_selectedFriends.isNotEmpty) ...[
                    const Text(
                      'Selected friends',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    for (final friend in _selectedFriends)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    friend.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    friend.phone,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                  // Show scheduled overlap warning inline
                                  if (_scheduledOverlapFriends.any(
                                    (f) => f['phone'] == friend.phone,
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Has a scheduled overlap',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Favorite button for phone-added friends
                            if (friend.isFromPhoneInput)
                              IconButton(
                                onPressed: () => _toggleFavorite(friend),
                                icon: Icon(
                                  friend.isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: friend.isFavorite
                                      ? Colors.red
                                      : Colors.grey[400],
                                  size: 22,
                                ),
                              ),
                            IconButton(
                              onPressed: () => _removeFriend(friend),
                              icon: const Icon(
                                Icons.check_circle,
                                color: AppColors.kGreen,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Text(
                      '${_selectedFriends.length} friend${_selectedFriends.length == 1 ? '' : 's'} selected',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Tracking Duration Section
                  const Text(
                    'Tracking Duration',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date Range Selectors
                  Row(
                    children: [
                      // Start Date
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectedVenueId == null
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select a venue first',
                                      ),
                                    ),
                                  );
                                }
                              : _selectDate,
                          child: Opacity(
                            opacity: _selectedVenueId == null ? 0.5 : 1.0,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today,
                                        color: AppColors.kGreen,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Start Date',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _selectedDate != null
                                        ? DateFormat(
                                            'EEE d MMM yyyy',
                                          ).format(_selectedDate!)
                                        : '--/--/----',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: _selectedDate != null
                                          ? Colors.black87
                                          : Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // End Date
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_selectedDate == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please select a start date first',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (_venueIsClosedOnDate(_selectedDate!)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _venueIsTemporarilyClosed()
                                        ? 'The venue is temporarily closed'
                                        : 'The venue is closed on this date',
                                  ),
                                ),
                              );
                              return;
                            }
                            _selectEndDate();
                          },
                          child: Opacity(
                            opacity:
                                (_selectedDate == null ||
                                    (_selectedDate != null &&
                                        _venueIsClosedOnDate(_selectedDate!)))
                                ? 0.4
                                : 1.0,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        (_selectedEndDate != null &&
                                                _selectedDate != null &&
                                                _selectedEndDate !=
                                                    _selectedDate)
                                            ? Icons.nights_stay_outlined
                                            : Icons.event,
                                        color: AppColors.kGreen,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          (_selectedEndDate != null &&
                                                  _selectedDate != null &&
                                                  _selectedEndDate !=
                                                      _selectedDate)
                                              ? 'End · Next day'
                                              : 'End Date',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                (_selectedEndDate != null &&
                                                    _selectedDate != null &&
                                                    _selectedEndDate !=
                                                        _selectedDate)
                                                ? AppColors.kGreen
                                                : Colors.black54,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _selectedEndDate != null
                                        ? DateFormat(
                                            'EEE d MMM yyyy',
                                          ).format(_selectedEndDate!)
                                        : '--/--/----',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: _selectedEndDate != null
                                          ? Colors.black87
                                          : Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Show venue hours for selected date
                  if (_selectedDate != null && _selectedVenueId != null) ...[
                    const SizedBox(height: 4),
                    Builder(
                      builder: (_) {
                        final hoursStr = _getVenueHoursStringForDate(
                          _selectedDate!,
                        );
                        final isClosed =
                            hoursStr == 'closed' ||
                            hoursStr == 'temporarily closed';
                        final isNotAvailable = hoursStr == 'not available';
                        final isOpen24 = hoursStr == 'open 24 hours';
                        Color textColor;
                        if (isClosed) {
                          textColor = Colors.red;
                        } else if (isOpen24) {
                          textColor = Colors.green;
                        } else if (isNotAvailable) {
                          textColor = Colors.orange[700]!;
                        } else {
                          textColor = Colors.grey[500]!;
                        }
                        return Text(
                          'Opening hours: $hoursStr',
                          style: TextStyle(fontSize: 12, color: textColor),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Time Range Selectors
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _clearTimeError();
                            _selectStartTime();
                          },
                          child: Opacity(
                            opacity:
                                (_selectedDate == null ||
                                    (_selectedDate != null &&
                                        _venueIsClosedOnDate(_selectedDate!)))
                                ? 0.4
                                : 1.0,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        color: AppColors.kGreen,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Start Time',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _startTime != null
                                        ? _formatTime12h(_startTime!)
                                        : '--:--',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: _startTime != null
                                          ? Colors.black87
                                          : Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _clearTimeError();
                            _selectEndTime();
                          },
                          child: Opacity(
                            opacity:
                                (_startTime == null ||
                                    (_selectedDate != null &&
                                        _venueIsClosedOnDate(_selectedDate!)))
                                ? 0.4
                                : 1.0,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        color: AppColors.kGreen,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'End Time',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _endTime != null
                                        ? _formatTime12h(_endTime!)
                                        : '--:--',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: _endTime != null
                                          ? Colors.black87
                                          : Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Duration info
                  if (_startTime != null &&
                      _endTime != null &&
                      _selectedDate != null &&
                      _selectedEndDate != null) ...[
                    const SizedBox(height: 6),
                    Builder(
                      builder: (_) {
                        final s = DateTime(
                          _selectedDate!.year,
                          _selectedDate!.month,
                          _selectedDate!.day,
                          _startTime!.hour,
                          _startTime!.minute,
                        );
                        final e = DateTime(
                          _selectedEndDate!.year,
                          _selectedEndDate!.month,
                          _selectedEndDate!.day,
                          _endTime!.hour,
                          _endTime!.minute,
                        );
                        final mins = e.difference(s).inMinutes;
                        final h = mins ~/ 60;
                        final m = mins % 60;
                        final durStr = h > 0
                            ? (m > 0 ? '${h}h ${m}min' : '${h}h')
                            : '${m}min';
                        return Text(
                          'Duration: $durStr',
                          style: TextStyle(
                            fontSize: 12,
                            color: (mins < 10 || mins > 1439)
                                ? Colors.red
                                : Colors.grey[500],
                            fontWeight: FontWeight.w400,
                          ),
                        );
                      },
                    ),
                  ],
                  if (!_isTimeValid && _timeError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _timeError!,
                      style: const TextStyle(
                        color: AppColors.kError,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Submit Button
          Container(
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
            child: ElevatedButton(
              onPressed: _canSubmit ? _submitRequest : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[500],
                minimumSize: const Size.fromHeight(52),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Send Request',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickContact() async {
    // Unfocus phone field before opening contact picker
    _phoneFocusNode.unfocus();

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectContactPage(
          contacts: _preloadedContacts,
          inDbStatus: _preloadedInDbStatus,
          onInvite: _shareInvite,
        ),
      ),
    );

    // If a phone number was returned, fill the phone field
    if (result != null && result.isNotEmpty) {
      // Remove +966 prefix for the text field (it shows +966 as prefix)
      String phoneDigits = result;
      if (phoneDigits.startsWith('+966')) {
        phoneDigits = phoneDigits.substring(4);
      }
      setState(() {
        _phoneController.text = phoneDigits;
      });
    }
  }
}

// ----------------------------------------------------------------------------
// Select Contact Page – Full page with pre-loaded data, "Invite" for non-DB contacts
// ----------------------------------------------------------------------------

class SelectContactPage extends StatefulWidget {
  final List<_ContactItem> contacts;
  final Map<String, bool> inDbStatus;
  final void Function(String phone) onInvite;

  const SelectContactPage({
    super.key,
    required this.contacts,
    required this.inDbStatus,
    required this.onInvite,
  });

  @override
  State<SelectContactPage> createState() => _SelectContactPageState();
}

class _SelectContactPageState extends State<SelectContactPage> {
  final _searchController = TextEditingController();
  // Local copy of inDbStatus that we can update
  late Map<String, bool> _localInDbStatus;
  bool _isCheckingDb = false;

  @override
  void initState() {
    super.initState();
    // Copy the pre-loaded status
    _localInDbStatus = Map.from(widget.inDbStatus);
    _searchController.addListener(() => setState(() {}));
    // Check remaining contacts that don't have status yet
    _checkRemainingContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Check DB status for contacts that weren't checked during pre-loading
  Future<void> _checkRemainingContacts() async {
    if (_isCheckingDb) return;
    _isCheckingDb = true;

    // Find contacts without status
    final toCheck = widget.contacts
        .where((c) => !_localInDbStatus.containsKey(c.phone))
        .toList();

    if (toCheck.isEmpty) {
      _isCheckingDb = false;
      return;
    }

    // Check in batches
    const batchSize = 10;
    for (var i = 0; i < toCheck.length; i += batchSize) {
      if (!mounted) return;
      final batch = toCheck.skip(i).take(batchSize).toList();

      // Check all in batch concurrently
      await Future.wait(
        batch.map((item) async {
          try {
            final query = await FirebaseFirestore.instance
                .collection('users')
                .where('phone', isEqualTo: item.phone)
                .limit(1)
                .get();
            if (mounted) {
              setState(() {
                _localInDbStatus[item.phone] = query.docs.isNotEmpty;
              });
            }
          } catch (_) {
            if (mounted) {
              setState(() {
                _localInDbStatus[item.phone] = false;
              });
            }
          }
        }),
      );
    }

    _isCheckingDb = false;
  }

  List<_ContactItem> get _filteredItems {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return widget.contacts;
    return widget.contacts
        .where((i) => i.name.toLowerCase().contains(q) || i.phone.contains(q))
        .toList();
  }

  Map<String, List<_ContactItem>> get _grouped {
    final map = <String, List<_ContactItem>>{};
    for (final i in _filteredItems) {
      final letter = i.name.isNotEmpty ? i.name[0].toUpperCase() : '#';
      map.putIfAbsent(letter, () => []).add(i);
    }
    return map;
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF4CAF50),
      Color(0xFF2196F3),
      Color(0xFF9C27B0),
      Color(0xFF009688),
      Color(0xFFE91E63),
      Color(0xFFFF5722),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _initial(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final a = parts[0].isNotEmpty ? parts[0][0] : '';
      final b = parts[1].isNotEmpty ? parts[1][0] : '';
      return (a + b).toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final keys = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Select a contact',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar - matching Favorites list style
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
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
          const SizedBox(height: 16),
          Expanded(
            child: widget.contacts.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.kGreen),
                  )
                : keys.isEmpty
                ? Center(
                    child: Text(
                      'No contacts',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: keys.fold<int>(
                          0,
                          (sum, k) => sum + 1 + grouped[k]!.length,
                        ),
                        itemBuilder: (context, index) {
                          int total = 0;
                          for (final k in keys) {
                            final list = grouped[k]!;
                            if (index == total) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 4,
                                ),
                                child: Text(
                                  k,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              );
                            }
                            total += 1;
                            final rowIndex = index - total;
                            if (rowIndex < list.length) {
                              final item = list[rowIndex];
                              final inDb = _localInDbStatus[item.phone];
                              // Show loading only if status not yet determined
                              final loading = !_localInDbStatus.containsKey(
                                item.phone,
                              );
                              return _ContactRow(
                                name: item.name,
                                phone: item.phone,
                                avatarColor: _avatarColor(item.name),
                                initial: _initial(item.name),
                                inDb: inDb,
                                loading: loading,
                                onInvite: () => widget.onInvite(item.phone),
                                onTap: () {
                                  // If contact is in DB, return phone to fill field
                                  if (inDb == true) {
                                    Navigator.pop(context, item.phone);
                                  }
                                },
                              );
                            }
                            total += list.length;
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      // Alphabet sidebar
                      Positioned(
                        right: 4,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'
                                  .split('')
                                  .map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 1,
                                      ),
                                      child: Text(
                                        c,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String name;
  final String phone;
  final Color avatarColor;
  final String initial;
  final bool? inDb;
  final bool loading;
  final VoidCallback onInvite;
  final VoidCallback onTap;

  const _ContactRow({
    required this.name,
    required this.phone,
    required this.avatarColor,
    required this.initial,
    required this.inDb,
    required this.loading,
    required this.onInvite,
    required this.onTap,
  });

  /// Format phone for display (e.g., +966 5XX XXX XXX)
  String get _displayPhone {
    if (phone.startsWith('+966') && phone.length == 13) {
      final digits = phone.substring(4);
      return '+966 ${digits.substring(0, 2)} ${digits.substring(2, 5)} ${digits.substring(5)}';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final showInvite = inDb == false && !loading;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        _displayPhone,
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      ),
      trailing: loading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.kGreen,
              ),
            )
          : showInvite
          ? OutlinedButton(
              onPressed: onInvite,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.kGreen,
                side: const BorderSide(color: AppColors.kGreen),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Invite'),
            )
          : null, // No trailing widget for contacts in DB
      onTap: inDb == true
          ? onTap
          : null, // Only tap to select for contacts in DB
    );
  }
}

// ----------------------------------------------------------------------------
// Venue Selection Sheet
// ----------------------------------------------------------------------------

class VenueSelectionSheet extends StatefulWidget {
  final List<VenueOption> venues;

  const VenueSelectionSheet({super.key, required this.venues});

  @override
  State<VenueSelectionSheet> createState() => _VenueSelectionSheetState();
}

class _VenueSelectionSheetState extends State<VenueSelectionSheet> {
  final _searchController = TextEditingController();
  List<VenueOption> _filteredVenues = [];

  @override
  void initState() {
    super.initState();
    _filteredVenues = widget.venues;
    _searchController.addListener(_filterVenues);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterVenues() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredVenues = widget.venues;
      } else {
        _filteredVenues = widget.venues
            .where((venue) => venue.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            child: const Text(
              'Select Venue',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),

          // Search Bar - FIXED HEIGHT
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for a venue',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
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
          const SizedBox(height: 16),

          // Venues List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filteredVenues.length,
              itemBuilder: (context, index) {
                final venue = _filteredVenues[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(shape: BoxShape.circle),
                    child: const Icon(
                      Icons.place,
                      color: AppColors.kGreen,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    venue.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, venue),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Favorites List Sheet
// ----------------------------------------------------------------------------

class FavoritesListSheet extends StatefulWidget {
  const FavoritesListSheet({super.key});

  @override
  State<FavoritesListSheet> createState() => _FavoritesListSheetState();
}

class _FavoritesListSheetState extends State<FavoritesListSheet> {
  final _searchController = TextEditingController();
  final List<Friend> _selectedFriends = [];

  // Mock favorite friends data
  final List<Friend> _allFavorites = [
    Friend(name: 'Abeer فاد', phone: '+966503347979', isFavorite: true),
    Friend(name: 'Afnan Salamah', phone: '+966503347978', isFavorite: true),
    Friend(name: 'Razan Aldosari', phone: '+966503347977', isFavorite: true),
    Friend(
      name: 'Dr. Rafah Almousli',
      phone: '+966503347976',
      isFavorite: true,
    ),
    Friend(name: 'AMAL', phone: '+966503347975', isFavorite: true),
    Friend(name: 'Ameera', phone: '+966503347974', isFavorite: true),
    Friend(name: 'Amjad', phone: '+966503347973', isFavorite: true),
    Friend(name: 'Areen', phone: '+966503347972', isFavorite: true),
    Friend(name: 'Aryam', phone: '+966503347971', isFavorite: true),
  ];

  List<Friend> _filteredFavorites = [];

  @override
  void initState() {
    super.initState();
    _filteredFavorites = List.from(_allFavorites);
    _searchController.addListener(_filterFavorites);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterFavorites() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFavorites = List.from(_allFavorites);
      } else {
        _filteredFavorites = _allFavorites
            .where(
              (friend) =>
                  friend.name.toLowerCase().contains(query) ||
                  friend.phone.contains(query),
            )
            .toList();
      }
    });
  }

  void _toggleFriend(Friend friend) {
    setState(() {
      if (_selectedFriends.contains(friend)) {
        _selectedFriends.remove(friend);
      } else {
        _selectedFriends.add(friend);
      }
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
          // Header
          Container(
            padding: const EdgeInsets.all(20),
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
                  onPressed: _selectedFriends.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selectedFriends),
                  child: Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _selectedFriends.isEmpty
                          ? Colors.grey[400]
                          : AppColors.kGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
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
          const SizedBox(height: 16),

          // Friends List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filteredFavorites.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final friend = _filteredFavorites[index];
                final isSelected = _selectedFriends.contains(friend);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                    friend.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    friend.phone,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  trailing: GestureDetector(
                    onTap: () => _toggleFriend(friend),
                    child: Container(
                      key: ValueKey('${friend.phone}_$isSelected'),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.kGreen
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.kGreen
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                  onTap: () => _toggleFriend(friend),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Models
// ----------------------------------------------------------------------------

class Friend {
  final String name;
  final String phone;
  final bool isFavorite;
  final bool isFromPhoneInput;

  Friend({
    required this.name,
    required this.phone,
    this.isFavorite = false,
    this.isFromPhoneInput = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Friend &&
          runtimeType == other.runtimeType &&
          phone == other.phone;

  @override
  int get hashCode => phone.hashCode;
}

class VenueOption {
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;

  VenueOption({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
  });
}
