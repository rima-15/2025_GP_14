import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/services/favorites_service.dart';

// ----------------------------------------------------------------------------
// Favorite Friends Page
// Favorites stored as a List field on users/{uid}.favoriteFriends
// to stay within the same security rules that allow profile writes.
// ----------------------------------------------------------------------------

class FavoriteFriendsPage
    extends StatefulWidget {
  const FavoriteFriendsPage({
    super.key,
  });

  @override
  State<FavoriteFriendsPage>
  createState() =>
      _FavoriteFriendsPageState();
}

class _FavoriteFriendsPageState
    extends State<FavoriteFriendsPage> {
  final _searchCtrl =
      TextEditingController();

  List<Map<String, dynamic>>
  _favorites = [];
  List<Map<String, dynamic>> _filtered =
      [];
  bool _loading = true;
  String _query = '';
  String _currentUserPhone = '';

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _searchCtrl.addListener(() {
      setState(() {
        _query = _searchCtrl.text
            .trim()
            .toLowerCase();
        _applyFilter();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- Data ----------

  final _favService =
      FavoritesService();

  Future<void> _loadFavorites() async {
    if (FirebaseAuth
            .instance
            .currentUser ==
        null) {
      setState(() => _loading = false);
      return;
    }
    try {
      // Also load current user's phone for self-check
      final uid = FirebaseAuth
          .instance
          .currentUser!
          .uid;
      final snap =
          await FirebaseFirestore
              .instance
              .collection('users')
              .doc(uid)
              .get();
      final phone =
          (snap.data()?['phone']
              as String? ??
          '');

      await _favService.load();

      if (mounted) {
        setState(() {
          _favorites = _favService.all;
          _currentUserPhone = phone;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(
          () => _loading = false,
        );
    }
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = List.from(_favorites);
    } else {
      _filtered = _favorites
          .where(
            (f) =>
                (f['name'] as String? ??
                        '')
                    .toLowerCase()
                    .contains(_query) ||
                (f['phone'] as String? ??
                        '')
                    .contains(_query),
          )
          .toList();
    }
  }

  Future<void> _removeFavorite(
    String phone,
  ) async {
    await _favService.toggle(
      phone,
      '',
    ); // toggle removes when already favorite
    setState(() {
      _favorites = _favService.all;
      _applyFilter();
    });
  }

  Future<void> _addFavorite(
    String phone,
    String name,
  ) async {
    await _favService.toggle(
      phone,
      name,
    ); // toggle adds when not favorite
    setState(() {
      _favorites = _favService.all;
      _applyFilter();
    });
  }

  bool _isAlreadyFavorite(
    String phone,
  ) => _favService.isFavorite(phone);

  // ---------- Bottom Sheet ----------

  void _openAddFriendSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent,
      builder: (_) => _AddFriendSheet(
        currentUserPhone:
            _currentUserPhone,
        isAlreadyFavorite:
            _isAlreadyFavorite,
        onAdd: (phone, name) async {
          await _addFavorite(
            phone,
            name,
          );
          if (mounted) {
            SnackbarHelper.showSuccess(
              context,
              'Friend added to favorites successfully',
            );
          }
        },
        onInvite: _showInviteDialog,
      ),
    );
  }

  // ---------- Invite Dialog ----------

  static const String _inviteMessage =
      "Hey! I'm using Madar for location sharing.\n"
      "Join me using this invite link:\n"
      "https://madar.app/invite";

  void _showInviteDialog(String phone) {
    final dialogPadding =
        MediaQuery.of(
              context,
            ).size.width <
            360
        ? 20.0
        : 28.0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(24),
        ),
        elevation: 0,
        backgroundColor:
            Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.all(
                dialogPadding,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(
                      24,
                    ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(
                          0.15,
                        ),
                    blurRadius: 20,
                    offset:
                        const Offset(
                          0,
                          10,
                        ),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 8,
                  ),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors
                          .kGreen
                          .withOpacity(
                            0.15,
                          ),
                      shape: BoxShape
                          .circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons
                            .person_add_rounded,
                        size: 42,
                        color: AppColors
                            .kGreen,
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  const Text(
                    'Invite to Madar?',
                    textAlign: TextAlign
                        .center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight
                              .bold,
                      color: AppColors
                          .kGreen,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  Text(
                    "This person isn't on Madar yet.\nInvite them to start sharing location.",
                    textAlign: TextAlign
                        .center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors
                          .grey[700],
                    ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(
                          dialogCtx,
                        ).pop();
                        Share.share(
                          _inviteMessage,
                          subject:
                              'Invite to Madar',
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors
                                .kGreen,
                        foregroundColor:
                            Colors
                                .white,
                        padding:
                            const EdgeInsets.symmetric(
                              vertical:
                                  14,
                            ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                                12,
                              ),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Send Invite',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight
                                  .w600,
                          letterSpacing:
                              0.3,
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
                onTap: () =>
                    Navigator.of(
                      dialogCtx,
                    ).pop(),
                child: Icon(
                  Icons.close,
                  size: 22,
                  color:
                      Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final isSmallScreen =
        MediaQuery.of(
          context,
        ).size.width <
        360;
    final hp = isSmallScreen
        ? 16.0
        : 20.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.kGreen,
          ),
          onPressed: () =>
              Navigator.pop(context),
        ),
        title: const Text(
          'Favorite Friends',
          style: TextStyle(
            color: AppColors.kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize:
              const Size.fromHeight(1),
          child: Container(
            color: Colors.grey[300],
            height: 1,
          ),
        ),
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : Padding(
              padding:
                  EdgeInsets.symmetric(
                    horizontal: hp,
                  ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  const SizedBox(
                    height: 16,
                  ),

                  // Search bar + Add icon
                  Row(
                    children: [
                      Expanded(
                        child:
                            _buildSearchBar(),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      GestureDetector(
                        onTap:
                            _openAddFriendSheet,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors
                                .white,
                            borderRadius:
                                BorderRadius.circular(
                                  12,
                                ),
                            border: Border.all(
                              color: Colors
                                  .grey
                                  .shade300,
                            ),
                          ),
                          child: Stack(
                            alignment:
                                Alignment
                                    .center,
                            children: [
                              Icon(
                                Icons
                                    .favorite_border,
                                color: AppColors
                                    .kGreen,
                                size:
                                    22,
                              ),
                              Positioned(
                                right:
                                    6,
                                bottom:
                                    6,
                                child: Container(
                                  width:
                                      13,
                                  height:
                                      13,
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.kGreen,
                                    shape:
                                        BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color:
                                        Colors.white,
                                    size:
                                        9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Expanded(
                    child:
                        _buildContent(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: Colors.grey.shade600,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration:
                  const InputDecoration(
                    hintText: 'Search',
                    hintStyle:
                        TextStyle(
                          color: Color(
                            0xFF9E9E9E,
                          ),
                        ),
                    border: InputBorder
                        .none,
                    enabledBorder:
                        InputBorder
                            .none,
                    focusedBorder:
                        InputBorder
                            .none,
                    isDense: true,
                    contentPadding:
                        EdgeInsets.zero,
                  ),
              style: const TextStyle(
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_favorites.isEmpty) {
      return Align(
        alignment: const Alignment(
          0,
          -0.3,
        ),
        child: Text(
          "You haven't added any favorite friends yet.",
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Align(
        alignment: const Alignment(
          0,
          -0.3,
        ),
        child: Text(
          'No results found. Try again',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(
        bottom: 24,
      ),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final friend = _filtered[i];
        final name =
            friend['name'] as String? ??
            '';
        final phone =
            friend['phone']
                as String? ??
            '';

        return Container(
          padding:
              const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
                  12,
                ),
            border: Border.all(
              color:
                  Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(
                  0,
                  2,
                ),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(
                      color: AppColors
                          .kGreen
                          .withOpacity(
                            0.12,
                          ),
                      shape: BoxShape
                          .circle,
                    ),
                child: const Icon(
                  Icons.person,
                  color:
                      AppColors.kGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight:
                            FontWeight
                                .w600,
                        color: Colors
                            .black87,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors
                            .grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () =>
                    _removeFavorite(
                      phone,
                    ),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.red,
                  size: 24,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Add Friend Bottom Sheet
// ----------------------------------------------------------------------------

class _AddFriendSheet
    extends StatefulWidget {
  final String currentUserPhone;
  final bool Function(String phone)
  isAlreadyFavorite;
  final Future<void> Function(
    String phone,
    String name,
  )
  onAdd;
  final void Function(String phone)
  onInvite;

  const _AddFriendSheet({
    required this.currentUserPhone,
    required this.isAlreadyFavorite,
    required this.onAdd,
    required this.onInvite,
  });

  @override
  State<_AddFriendSheet>
  createState() =>
      _AddFriendSheetState();
}

class _AddFriendSheetState
    extends State<_AddFriendSheet> {
  final _phoneCtrl =
      TextEditingController();
  final _phoneFocus = FocusNode();

  bool _loading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(
      () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  static String _normalizePhone(
    String raw,
  ) {
    var phone = raw
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '');
    if (phone.startsWith('+966'))
      phone = phone.substring(4);
    if (phone.startsWith('966'))
      phone = phone.substring(3);
    if (phone.startsWith('05') &&
        phone.length >= 9)
      phone = phone.substring(2);
    phone = phone.replaceAll(
      RegExp(r'[^\d]'),
      '',
    );
    return phone;
  }

  Future<void> _pickContact() async {
    _phoneFocus.unfocus();
    try {
      final allowed =
          await FlutterContacts.requestPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'Contacts permission is required.',
            ),
          ),
        );
        return;
      }

      final contacts =
          await FlutterContacts.getContacts(
            withProperties: true,
          );
      final items = <_FavContactItem>[];
      final seen = <String>{};

      for (final c in contacts) {
        if (c.phones.isEmpty) continue;
        final name =
            c.displayName.trim().isEmpty
            ? 'Unknown'
            : c.displayName;
        for (final p in c.phones) {
          final normalized =
              _normalizePhone(p.number);
          if (normalized.isEmpty ||
              !seen.add(normalized))
            continue;
          items.add(
            _FavContactItem(
              name: name,
              phone: normalized,
            ),
          );
        }
      }

      items.sort(
        (a, b) => a.name
            .toLowerCase()
            .compareTo(
              b.name.toLowerCase(),
            ),
      );
      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'No valid contacts found.',
            ),
          ),
        );
        return;
      }

      final selectedPhone =
          await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  _FavSelectContactPage(
                    contacts: items,
                    onInvite:
                        widget.onInvite,
                  ),
            ),
          );

      if (!mounted ||
          selectedPhone == null)
        return;
      final local =
          selectedPhone.startsWith(
            '+966',
          )
          ? selectedPhone.substring(4)
          : selectedPhone;

      setState(() {
        _phoneCtrl.text = local;
        _phoneCtrl.selection =
            TextSelection.collapsed(
              offset: local.length,
            );
        _errorMsg = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load contacts. Try again.',
          ),
        ),
      );
    }
  }

  Future<void> _handleAdd() async {
    final digits = _phoneCtrl.text
        .trim();

    if (digits.isEmpty) {
      setState(
        () => _errorMsg =
            'Please enter a phone number',
      );
      return;
    }
    if (digits.length < 9) {
      setState(
        () => _errorMsg =
            'Enter a valid 9-digit phone number',
      );
      return;
    }

    final fullPhone = '+966$digits';

    if (widget.currentUserPhone ==
            fullPhone ||
        widget.currentUserPhone
            .replaceAll('+', '')
            .endsWith(digits)) {
      setState(
        () => _errorMsg =
            "You can't add yourself to favorites",
      );
      return;
    }

    if (widget.isAlreadyFavorite(
      fullPhone,
    )) {
      setState(
        () => _errorMsg =
            'Friend already in favorite list',
      );
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      // Look up the phone in the users collection
      final query =
          await FirebaseFirestore
              .instance
              .collection('users')
              .where(
                'phone',
                isEqualTo: fullPhone,
              )
              .limit(1)
              .get();

      if (query.docs.isEmpty) {
        _phoneFocus.unfocus();
        if (mounted) {
          setState(() {
            _loading = false;
            _phoneCtrl.clear();
            _errorMsg = null;
          });
          Navigator.of(context).pop();
        }
        widget.onInvite(fullPhone);
        return;
      }

      final data = query.docs.first
          .data();
      final firstName =
          (data['firstName'] ?? '')
              .toString();
      final lastName =
          (data['lastName'] ?? '')
              .toString();
      var name = '$firstName $lastName'
          .trim();
      if (name.isEmpty)
        name = fullPhone;

      // Write favorite to parent document (no subcollection)
      await widget.onAdd(
        fullPhone,
        name,
      );

      if (mounted)
        Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg =
              e.message ??
              'Something went wrong. Try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg =
              'Something went wrong. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(
      context,
    ).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(
              top: Radius.circular(24),
            ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius:
                    BorderRadius.circular(
                      2,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Add to Favorites',
            style: TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w700,
              color: AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 20),

          // Phone field
          TextField(
            controller: _phoneCtrl,
            focusNode: _phoneFocus,
            keyboardType:
                TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter
                  .digitsOnly,
              LengthLimitingTextInputFormatter(
                9,
              ),
            ],
            onChanged: (_) =>
                setState(() => _errorMsg = null),
            decoration: InputDecoration(
              hintText:
                  _phoneFocus.hasFocus
                  ? 'Enter 9 digits'
                  : 'Phone number',
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontWeight:
                    FontWeight.w400,
              ),
              prefix:
                  (_phoneFocus
                          .hasFocus ||
                      _phoneCtrl
                          .text
                          .isNotEmpty)
                  ? Text(
                      '+966 ',
                      style: TextStyle(
                        color: Colors
                            .grey[400],
                        fontSize: 15,
                        fontWeight:
                            FontWeight
                                .w400,
                      ),
                    )
                  : null,
              suffixIcon:
                  _phoneFocus.hasFocus
                  ? IconButton(
                      icon: const Icon(
                        Icons.contacts,
                        color: AppColors
                            .kGreen,
                      ),
                      onPressed:
                          _pickContact,
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                borderSide: BorderSide(
                  color: Colors
                      .grey
                      .shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                borderSide: BorderSide(
                  color:
                      _errorMsg != null
                      ? AppColors.kError
                      : Colors
                            .grey
                            .shade300,
                ),
              ),
              focusedBorder:
                  OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                          12,
                        ),
                    borderSide: BorderSide(
                      color:
                          _errorMsg !=
                              null
                          ? AppColors
                                .kError
                          : AppColors
                                .kGreen,
                      width: 2,
                    ),
                  ),
              contentPadding:
                  const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
            ),
          ),

          if (_errorMsg != null) ...[
            const SizedBox(height: 6),
            Text(
              _errorMsg!,
              style: const TextStyle(
                color: AppColors.kError,
                fontSize: 12,
                fontWeight:
                    FontWeight.w400,
              ),
            ),
          ],

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ||
                      _phoneCtrl.text
                              .trim()
                              .length <
                          9
                  ? null
                  : _handleAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    AppColors.kGreen,
                foregroundColor:
                    Colors.white,
                disabledBackgroundColor:
                    Colors.grey[300],
                disabledForegroundColor:
                    Colors.grey[500],
                padding:
                    const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                        10,
                      ),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                            color: Colors
                                .white,
                            strokeWidth:
                                2.5,
                          ),
                    )
                  : const Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w600,
                        letterSpacing:
                            0.3,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Contact picker support for Add to Favorites
// ----------------------------------------------------------------------------

class _FavContactItem {
  const _FavContactItem({
    required this.name,
    required this.phone,
  });
  final String name;
  final String phone;
}

class _FavSelectContactPage
    extends StatefulWidget {
  final List<_FavContactItem> contacts;
  final void Function(String phone)
  onInvite;

  const _FavSelectContactPage({
    required this.contacts,
    required this.onInvite,
  });

  @override
  State<_FavSelectContactPage>
  createState() =>
      _FavSelectContactPageState();
}

class _FavSelectContactPageState
    extends
        State<_FavSelectContactPage> {
  final _searchCtrl =
      TextEditingController();
  final Map<String, bool> _inDbStatus =
      {};
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() {}),
    );
    _checkContacts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkContacts() async {
    if (_checking) return;
    _checking = true;
    const batchSize = 10;
    final toCheck = widget.contacts
        .toList();
    for (
      var i = 0;
      i < toCheck.length;
      i += batchSize
    ) {
      if (!mounted) return;
      final batch = toCheck
          .skip(i)
          .take(batchSize)
          .toList();
      await Future.wait(
        batch.map((item) async {
          try {
            final q =
                await FirebaseFirestore
                    .instance
                    .collection('users')
                    .where(
                      'phone',
                      isEqualTo:
                          '+966${item.phone}',
                    )
                    .limit(1)
                    .get();
            if (mounted)
              setState(
                () =>
                    _inDbStatus[item
                        .phone] = q
                        .docs
                        .isNotEmpty,
              );
          } catch (_) {
            if (mounted)
              setState(
                () =>
                    _inDbStatus[item
                            .phone] =
                        false,
              );
          }
        }),
      );
    }
    _checking = false;
  }

  List<_FavContactItem> get _filtered {
    final q = _searchCtrl.text
        .trim()
        .toLowerCase();
    if (q.isEmpty)
      return widget.contacts;
    return widget.contacts
        .where(
          (i) =>
              i.name
                  .toLowerCase()
                  .contains(q) ||
              i.phone.contains(q),
        )
        .toList();
  }

  Map<String, List<_FavContactItem>>
  get _grouped {
    final map =
        <
          String,
          List<_FavContactItem>
        >{};
    for (final i in _filtered) {
      final letter = i.name.isNotEmpty
          ? i.name[0].toUpperCase()
          : '#';
      map
          .putIfAbsent(letter, () => [])
          .add(i);
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
    return colors[name.hashCode.abs() %
        colors.length];
  }

  String _initial(String name) {
    final parts = name.trim().split(
      RegExp(r'\s+'),
    );
    if (parts.length >= 2) {
      final a = parts[0].isNotEmpty
          ? parts[0][0]
          : '';
      final b = parts[1].isNotEmpty
          ? parts[1][0]
          : '';
      return (a + b).toUpperCase();
    }
    return name.isNotEmpty
        ? name[0].toUpperCase()
        : '?';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final keys = grouped.keys.toList()
      ..sort();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.kGreen,
          ),
          onPressed: () =>
              Navigator.pop(context),
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
          Padding(
            padding:
                const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(
                  color:
                      Colors.grey[400],
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors
                      .grey
                      .shade600,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                  borderSide:
                      BorderSide(
                        color: Colors
                            .grey
                            .shade300,
                      ),
                ),
                enabledBorder:
                    OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                            12,
                          ),
                      borderSide:
                          BorderSide(
                            color: Colors
                                .grey
                                .shade300,
                          ),
                    ),
                focusedBorder:
                    OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                            12,
                          ),
                      borderSide:
                          BorderSide(
                            color: Colors
                                .grey
                                .shade300,
                          ),
                    ),
                contentPadding:
                    const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
              ),
              cursorColor:
                  AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                widget.contacts.isEmpty
                ? const Center(
                    child:
                        CircularProgressIndicator(
                          color: AppColors
                              .kGreen,
                        ),
                  )
                : keys.isEmpty
                ? Center(
                    child: Text(
                      'No contacts',
                      style: TextStyle(
                        color: Colors
                            .grey[600],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(
                          horizontal:
                              16,
                        ),
                    itemCount: keys
                        .fold<int>(
                          0,
                          (acc, k) =>
                              acc +
                              1 +
                              grouped[k]!
                                  .length,
                        ),
                    itemBuilder: (context, index) {
                      int total = 0;
                      for (final k
                          in keys) {
                        final list =
                            grouped[k]!;
                        if (index ==
                            total) {
                          return Padding(
                            padding:
                                const EdgeInsets.only(
                                  top:
                                      8,
                                  bottom:
                                      4,
                                ),
                            child: Text(
                              k,
                              style: TextStyle(
                                fontSize:
                                    16,
                                fontWeight:
                                    FontWeight.w700,
                                color: Colors
                                    .grey[600],
                              ),
                            ),
                          );
                        }
                        total += 1;
                        final rowIndex =
                            index -
                            total;
                        if (rowIndex <
                            list.length) {
                          final item =
                              list[rowIndex];
                          final inDb =
                              _inDbStatus[item
                                  .phone];
                          final loading =
                              !_inDbStatus
                                  .containsKey(
                                    item.phone,
                                  );
                          final fullPhone =
                              '+966${item.phone}';
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(
                                  vertical:
                                      4,
                                ),
                            leading: Container(
                              width: 44,
                              height:
                                  44,
                              decoration: BoxDecoration(
                                color: _avatarColor(
                                  item.name,
                                ),
                                shape: BoxShape
                                    .circle,
                              ),
                              child: Center(
                                child: Text(
                                  _initial(
                                    item.name,
                                  ),
                                  style: const TextStyle(
                                    color:
                                        Colors.white,
                                    fontWeight:
                                        FontWeight.w600,
                                    fontSize:
                                        16,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontSize:
                                    16,
                                fontWeight:
                                    FontWeight.w500,
                                color: Colors
                                    .black87,
                              ),
                            ),
                            subtitle: Text(
                              fullPhone,
                              style: TextStyle(
                                fontSize:
                                    13,
                                color: Colors
                                    .grey[600],
                              ),
                            ),
                            trailing:
                                loading
                                ? const SizedBox(
                                    width:
                                        20,
                                    height:
                                        20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.kGreen,
                                    ),
                                  )
                                : inDb ==
                                      false
                                ? OutlinedButton(
                                    onPressed: () => widget.onInvite(
                                      fullPhone,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.kGreen,
                                      side: const BorderSide(
                                        color: AppColors.kGreen,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          20,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'Invite',
                                    ),
                                  )
                                : null,
                            onTap:
                                inDb ==
                                    true
                                ? () => Navigator.pop(
                                    context,
                                    fullPhone,
                                  )
                                : null,
                          );
                        }
                        total +=
                            list.length;
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
