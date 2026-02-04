import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:icons_plus/icons_plus.dart';

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

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Venue selection
  String? _selectedVenue;
  String? _selectedVenueId;
  List<VenueOption> _allVenues = [];
  bool _loadingVenues = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadVenues();
    _getCurrentLocation();

    _phoneFocusNode.addListener(() {
      setState(() {
        _isPhoneFocused = _phoneFocusNode.hasFocus;
      });
    });
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
    if (!_canAddPhone) {
      setState(() {
        _isPhoneInputValid = false;
        _phoneInputError = 'Enter 9 digits';
      });
      return;
    }

    final phone = '+966${_phoneController.text.trim()}';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final myPhone = (myDoc.data()?['phone'] ?? '').toString();

      if (myPhone.isNotEmpty && myPhone == phone) {
        setState(() {
          _isPhoneInputValid = false;
          _phoneInputError = 'You can’t send a request to yourself';
        });
        return;
      }
    }

    // already added
    if (_selectedFriends.any((f) => f.phone == phone)) {
      setState(() {
        _isPhoneInputValid = false;
        _phoneInputError = 'Friend already added';
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
        _showInviteToMadarDialog(phone);
        return;
      }

      final userData = query.docs.first.data();
      final firstName = (userData['firstName'] ?? '').toString();
      final lastName = (userData['lastName'] ?? '').toString();
      var displayName = '$firstName $lastName'.trim();
      if (displayName.isEmpty) displayName = phone;

      setState(() {
        _selectedFriends.add(
          Friend(
            name: displayName,
            phone: phone,
            isFavorite: false,
            isFromPhoneInput: true,
          ),
        );
        _phoneController.clear();

        // reset error state
        _isPhoneInputValid = true;
        _phoneInputError = null;
      });
    } catch (e) {
      setState(() {
        _isPhoneInputValid = false;
        _phoneInputError = 'Could not verify this number. Try again.';
      });
    }
  }

  static const String _inviteMessage =
      "Hey! I'm using Madar for location sharing.\n"
      "Join me using this invite link:\n"
      "https://madar.app/invite";
  static const String _inviteLink = 'https://madar.app/invite';

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
                    // Icon
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
                      "This person isn’t on Madar yet."
                      "Invite them to start sharing location.",
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
                          _showInviteShareBottomSheet(phone);
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

  void _showInviteShareBottomSheet(String phone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _InviteShareSheet(
        phone: phone,
        inviteMessage: _inviteMessage,
        inviteLink: _inviteLink,
      ),
    );
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
    if (!_canSubmit) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in')));
      return;
    }

    //  Validate time
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    final durationMinutes = end.difference(start).inMinutes;

    // Get sender info (name/phone) from users/{uid}
    final senderDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final senderData = senderDoc.data() ?? {};
    final senderName =
        ('${senderData['firstName'] ?? ''} ${senderData['lastName'] ?? ''}')
            .trim();
    final senderPhone = (senderData['phone'] ?? '').toString();

    if (senderPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your phone number is missing in your profile'),
        ),
      );
      return;
    }

    // Resolve receivers (UIDs)
    final List<Friend> friends = List.from(_selectedFriends);
    final List<Map<String, String>> resolved = []; // {uid, phone, name}

    for (final f in friends) {
      final receiverUid = await _getUserIdByPhone(f.phone);
      if (receiverUid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User not found for ${f.phone}')),
        );
        return;
      }

      final receiverDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverUid)
          .get();

      final receiverData = receiverDoc.data() ?? {};
      final receiverName =
          ('${receiverData['firstName'] ?? ''} ${receiverData['lastName'] ?? ''}')
              .trim();

      resolved.add({
        'uid': receiverUid,
        'phone': f.phone,
        'name': receiverName.isEmpty ? f.phone : receiverName,
      });
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
      });
    }

    try {
      await batch.commit();

      if (!mounted) return;
      Navigator.pop(context);

      SnackbarHelper.showSuccess(
        context,
        'Tracking request sent to ${resolved.length} friend(s).',
      );
    } catch (e) {
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
                                prefixStyle: const TextStyle(
                                  color: Colors.black87,
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
    // Request permission
    if (!await FlutterContacts.requestPermission()) return;

    final contact = await FlutterContacts.openExternalPick();

    if (contact == null || contact.phones.isEmpty) return;

    // Take first phone number
    String phone = contact.phones.first.number;

    // Clean phone number
    phone = phone.replaceAll(RegExp(r'\s+'), '');
    phone = phone.replaceAll('-', '');

    // Normalize Saudi numbers
    if (phone.startsWith('+966')) {
      phone = phone.replaceFirst('+966', '');
    } else if (phone.startsWith('966')) {
      phone = phone.replaceFirst('966', '');
    } else if (phone.startsWith('05')) {
      phone = phone.substring(1);
    }

    if (phone.length != 9) {
      setState(() {
        _isPhoneInputValid = false;
        _phoneInputError = 'Invalid Saudi phone number';
      });
      return;
    }

    setState(() {
      _phoneController.text = phone;
      _isPhoneInputValid = true;
      _phoneInputError = null;
    });
  }
}

// ----------------------------------------------------------------------------
// Invite Share Bottom Sheet (message preview + only installed app icons + More + Copy)
// ----------------------------------------------------------------------------

enum _ShareAppId { sms, whatsapp, instagram, snapchat, more }

class _InviteShareSheet extends StatefulWidget {
  final String phone;
  final String inviteMessage;
  final String inviteLink;

  const _InviteShareSheet({
    required this.phone,
    required this.inviteMessage,
    required this.inviteLink,
  });

  @override
  State<_InviteShareSheet> createState() => _InviteShareSheetState();
}

class _InviteShareSheetState extends State<_InviteShareSheet> {
  List<_ShareAppId> _availableApps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAvailableApps();
  }

  Future<void> _checkAvailableApps() async {
    final list = <_ShareAppId>[];
    try {
      final smsOk = await canLaunchUrl(Uri(scheme: 'sms', path: widget.phone));
      if (smsOk) list.add(_ShareAppId.sms);

      final waOk = await canLaunchUrl(Uri.parse('https://wa.me/'));
      if (waOk) list.add(_ShareAppId.whatsapp);

      final igOk = await canLaunchUrl(Uri.parse('instagram://app'));
      if (igOk) list.add(_ShareAppId.instagram);

      final snapOk = await canLaunchUrl(Uri.parse('snapchat://'));
      if (snapOk) list.add(_ShareAppId.snapchat);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _availableApps = list;
        _loading = false;
      });
    }
  }

  Future<void> _shareViaSms(BuildContext context) async {
    final uri = Uri(
      scheme: 'sms',
      path: widget.phone,
      queryParameters: {'body': widget.inviteMessage},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _copyAndShow(
        context,
        widget.inviteMessage,
        'Message copied. Paste into SMS.',
      );
    }
  }

  Future<void> _shareViaWhatsApp(BuildContext context) async {
    final number = widget.phone.replaceAll(RegExp(r'[^\d]'), '');
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(widget.inviteMessage)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _copyAndShow(
        context,
        widget.inviteMessage,
        'Message copied. Paste into WhatsApp.',
      );
    }
  }

  void _copyAndShow(BuildContext context, String text, String snackbarMessage) {
    Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackbarMessage),
          backgroundColor: AppColors.kGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.inviteMessage));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copied to clipboard!'),
          backgroundColor: AppColors.kGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  void _shareViaInstagram(BuildContext context) {
    _shareViaSystemSheet(context);
  }

  void _shareViaSnapchat(BuildContext context) {
    _shareViaSystemSheet(context);
  }

  (String, Color, Widget, VoidCallback) _shareAppData(
    BuildContext context,
    _ShareAppId id,
  ) {
    const whiteFilter = ColorFilter.mode(Colors.white, BlendMode.srcIn);
    switch (id) {
      case _ShareAppId.sms:
        return (
          'SMS',
          const Color(0xFF5C9EFF),
          Icon(Icons.sms_outlined, size: 28, color: Colors.white),
          () => _shareViaSms(context),
        );
      case _ShareAppId.whatsapp:
        return (
          'WhatsApp',
          const Color(0xFF25D366),
          Brand(Brands.whatsapp, size: 28, colorFilter: whiteFilter),
          () => _shareViaWhatsApp(context),
        );
      case _ShareAppId.instagram:
        return (
          'Instagram',
          const Color(0xFFE4405F),
          Brand(Brands.instagram, size: 28, colorFilter: whiteFilter),
          () => _shareViaInstagram(context),
        );
      case _ShareAppId.snapchat:
        return (
          'Snapchat',
          const Color(0xFFFFFC00),
          Brand(Brands.snapchat, size: 28, colorFilter: whiteFilter),
          () => _shareViaSnapchat(context),
        );
      case _ShareAppId.more:
        return (
          'More',
          Colors.grey.shade600,
          Icon(Icons.more_horiz_rounded, size: 28, color: Colors.white),
          () => _shareViaSystemSheet(context),
        );
    }
  }

  Future<void> _shareViaSystemSheet(BuildContext context) async {
    try {
      await Share.share(widget.inviteMessage, subject: 'Invite to Madar');
    } catch (e) {
      debugPrint('Share error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open share. Try Copy instead.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Share invite',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Send this invite so they can join Madar',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              // Message preview (grey box with invite text + icon)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.send_rounded, size: 22, color: AppColors.kGreen),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.inviteMessage,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[800],
                          height: 1.4,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Horizontal row: only apps available on device + More
              _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.kGreen,
                          ),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._availableApps.map((id) {
                            final (label, bg, iconWidget, onTap) =
                                _shareAppData(context, id);
                            return Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: _ShareAppIcon(
                                label: label,
                                backgroundColor: bg,
                                iconWidget: iconWidget,
                                onTap: onTap,
                              ),
                            );
                          }),
                          Padding(
                            padding: const EdgeInsets.only(right: 0),
                            child: _ShareAppIcon(
                              label: 'More',
                              backgroundColor: Colors.grey.shade600,
                              iconWidget: Icon(
                                Icons.more_horiz_rounded,
                                size: 28,
                                color: Colors.white,
                              ),
                              onTap: () => _shareViaSystemSheet(context),
                            ),
                          ),
                        ],
                      ),
                    ),
              const SizedBox(height: 24),
              // Copy row
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _copyLink(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.copy_rounded,
                          size: 22,
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareAppIcon extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Widget iconWidget;
  final VoidCallback onTap;

  const _ShareAppIcon({
    required this.label,
    required this.backgroundColor,
    required this.iconWidget,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
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
