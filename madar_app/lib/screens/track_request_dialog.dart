import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

// ----------------------------------------------------------------------------
// Track Request Dialog
// ----------------------------------------------------------------------------

class TrackRequestDialog extends StatefulWidget {
  const TrackRequestDialog({super.key});

  @override
  State<TrackRequestDialog> createState() => _TrackRequestDialogState();
}

class _TrackRequestDialogState extends State<TrackRequestDialog> {
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
  }

  String _formatTime12h(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    return DateFormat('h:mm a').format(dt); // 1:35 AM
  }

  @override
  void dispose() {
    _phoneController.dispose();
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

      // ✅ أهم سطر: إذا مو موجود لا تضيفه
      if (query.docs.isEmpty) {
        setState(() {
          _isPhoneInputValid = false;
          _phoneInputError = 'User not exist';
        });
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

        // ✅ reset error state
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

    // ✅ minimum = الآن (إذا اليوم) وإلا بداية اليوم
    final min = isToday ? now : dayStart;

    // initial = الوقت المختار سابقاً أو min
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

      // ✅ إذا end موجود وصار قبل/يساوي start → صفري end (عشان ما يصير اختيار غلط)
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

    // ✅ minimum end لازم يكون بعد start (دقيقة على الأقل)
    final minEnd = start.add(const Duration(minutes: 1));

    // إذا start قرب آخر اليوم، ما عاد فيه end صالح
    if (minEnd.isAfter(dayEnd)) {
      // هنا تقدرين تحطين نفس error تحت الوقت إذا تبين
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
                    // Title (مثل الصورة)
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
                          // iOS picker بنفسه ما يسمح ينزل تحت minimumDate
                          // بس نخليها احتياط:
                          if (d.isBefore(minimum)) d = minimum;
                          if (d.isAfter(maximum)) d = maximum;

                          setModalState(() => temp = d);
                        },
                      ),
                    ),

                    // OK Button (disabled لين يصير Valid)
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

    // ✅ Validate time
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

    // ✅ Get sender info (name/phone) from users/{uid}
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

    // ✅ Resolve receivers (UIDs)
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

      // ✅ جيبي اسم المستقبل من users/{uid}
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

    // ✅ Create one request per receiver but same batchId
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

                                // ❌ احذفي errorText و errorStyle من هنا
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

                      // ✅ مكان ثابت للخطأ (ما يزحزح الـ Row)
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 18, // مساحة ثابتة حتى لو ما فيه خطأ
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
                              // _setTimeError('Please select a date first');
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
                              // _setTimeError('Please select a date first');
                              return;
                            }
                            if (_startTime == null) {
                              //_setTimeError('Please select start time first');
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
