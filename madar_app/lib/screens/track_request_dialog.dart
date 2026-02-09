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

  @override
  void initState() {
    super.initState();
    _loadVenues();
    _getCurrentLocation();
    _preloadContacts(); // Pre-load contacts and DB status
    _loadCurrentUserInfo(); // Cache current user's phone/name for fast lookups

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
    } catch (_) {
      // Ignore - will fall back to querying if needed
    }
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
    }
  }

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
      setState(() {
        _selectedVenue = result.name;
        _selectedVenueId = result.id;
      });
    }
  }

  Future<void> _selectDate() async {
    // Dismiss keyboard when opening date picker
    FocusScope.of(context).unfocus();

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
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectStartTime() async {
    // Dismiss keyboard when opening time picker
    FocusScope.of(context).unfocus();

    if (_selectedDate == null) return;

    final date = _selectedDate!;
    final dayStart = DateTime(date.year, date.month, date.day, 0, 0);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59);

    final now = DateTime.now();
    final isToday =
        now.year == date.year && now.month == date.month && now.day == date.day;

    final min = isToday ? now : dayStart;

    DateTime initial;
    if (_startTime != null) {
      initial = DateTime(
        date.year,
        date.month,
        date.day,
        _startTime!.hour,
        _startTime!.minute,
      );
    } else {
      initial = min;
    }

    final picked = await _showCupertinoDateTimePicker(
      title: 'Select Time',
      initial: initial,
      minimum: min,
      maximum: dayEnd,
    );

    if (picked == null) return;

    setState(() {
      _startTime = TimeOfDay(hour: picked.hour, minute: picked.minute);

      if (_endTime != null) {
        final end = DateTime(
          date.year,
          date.month,
          date.day,
          _endTime!.hour,
          _endTime!.minute,
        );
        if (!end.isAfter(picked)) _endTime = null;
      }
    });
  }

  Future<void> _selectEndTime() async {
    // Dismiss keyboard when opening time picker
    FocusScope.of(context).unfocus();

    if (_selectedDate == null || _startTime == null) return;

    final date = _selectedDate!;
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59);

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      _startTime!.hour,
      _startTime!.minute,
    );

    final minEnd = start.add(const Duration(minutes: 1));

    if (minEnd.isAfter(dayEnd)) {
      return;
    }

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
      initial = minEnd;
    }

    final picked = await _showCupertinoDateTimePicker(
      title: 'Select Time',
      initial: initial,
      minimum: minEnd,
      maximum: dayEnd,
    );

    if (picked == null) return;

    setState(() {
      _endTime = TimeOfDay(hour: picked.hour, minute: picked.minute);
    });
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
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
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

    try {
      // Run sender fetch and all receiver lookups in PARALLEL
      final List<Friend> friends = List.from(_selectedFriends);

      // Start all queries at once
      final senderFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // For each friend, query by phone (returns doc with uid and name)
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
      final results = await Future.wait([senderFuture, ...receiverFutures]);

      final senderDoc = results[0] as DocumentSnapshot;
      final senderData = senderDoc.data() as Map<String, dynamic>? ?? {};
      final senderName =
          ('${senderData['firstName'] ?? ''} ${senderData['lastName'] ?? ''}')
              .trim();
      final senderPhone = (senderData['phone'] ?? '').toString();

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
      for (var i = 1; i < results.length; i++) {
        final r = results[i] as Map<String, String>?;
        if (r == null) {
          _isSubmitting = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('User not found for ${friends[i - 1].phone}'),
            ),
          );
          return;
        }
        resolved.add(r);
      }

      // Create one request per receiver but same batchId
      final batchId = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';
      final col = FirebaseFirestore.instance.collection('trackRequests');
      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();

      for (final r in resolved) {
        final docRef = col.doc();
        batch.set(docRef, {
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

      await batch.commit();

      if (!mounted) return;
      Navigator.pop(context);

      SnackbarHelper.showSuccess(
        context,
        'Tracking request sent to ${resolved.length} friend(s).',
      );
    } catch (e) {
      _isSubmitting = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send request: $e')));
    }
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
                            size: 21,
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

                  // Date Selector
                  GestureDetector(
                    onTap: _selectDate,
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
                            Icons.calendar_today,
                            color: AppColors.kGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedDate != null
                                      ? DateFormat(
                                          'EEEE, MMMM d, yyyy',
                                        ).format(_selectedDate!)
                                      : 'Select date',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: _selectedDate != null
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: _selectedDate != null
                                        ? Colors.black87
                                        : Colors.grey[400],
                                  ),
                                ),
                              ],
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
                  const SizedBox(height: 12),

                  // Time Range Selectors
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_selectedDate == null) {
                              return;
                            }
                            _clearTimeError();
                            _selectStartTime();
                          },

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
                                    fontSize: 18,
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_selectedDate == null) {
                              return;
                            }
                            if (_startTime == null) {
                              return;
                            }
                            _clearTimeError();
                            _selectEndTime();
                          },

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
                                    fontSize: 18,
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
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 18,
                    child: (!_isTimeValid && _timeError != null)
                        ? Text(
                            _timeError!,
                            style: const TextStyle(
                              color: AppColors.kError,
                              fontSize: 13,
                            ),
                          )
                        : null,
                  ),

                  const SizedBox(height: 32),
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
