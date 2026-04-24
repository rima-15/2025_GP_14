import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/services/favorites_service.dart';

// ----------------------------------------------------------------------------
// Favorite Friends Page
// Favorites stored as a List field on users/{uid}.favoriteFriends
// to stay within the same security rules that allow profile writes.
// ----------------------------------------------------------------------------

class FavoriteFriendsPage extends StatefulWidget {
  const FavoriteFriendsPage({super.key});

  @override
  State<FavoriteFriendsPage> createState() => _FavoriteFriendsPageState();
}

class _FavoriteFriendsPageState extends State<FavoriteFriendsPage> {
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _query = '';
  String _currentUserPhone = '';

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _searchCtrl.addListener(() {
      setState(() {
        _query = _searchCtrl.text.trim().toLowerCase();
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

  final _favService = FavoritesService();

  Future<void> _loadFavorites() async {
    if (FirebaseAuth.instance.currentUser == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      // Also load current user's phone for self-check
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final phone = (snap.data()?['phone'] as String? ?? '');

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
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = List.from(_favorites);
    } else {
      _filtered = _favorites
          .where((f) =>
              (f['name'] as String? ?? '').toLowerCase().contains(_query) ||
              (f['phone'] as String? ?? '').contains(_query))
          .toList();
    }
  }

  Future<void> _removeFavorite(String phone) async {
    await _favService.toggle(phone, ''); // toggle removes when already favorite
    setState(() {
      _favorites = _favService.all;
      _applyFilter();
    });
  }

  Future<void> _addFavorite(String phone, String name) async {
    await _favService.toggle(phone, name); // toggle adds when not favorite
    setState(() {
      _favorites = _favService.all;
      _applyFilter();
    });
  }

  bool _isAlreadyFavorite(String phone) => _favService.isFavorite(phone);

  // ---------- Bottom Sheet ----------

  void _openAddFriendSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddFriendSheet(
        currentUserPhone: _currentUserPhone,
        isAlreadyFavorite: _isAlreadyFavorite,
        onAdd: (phone, name) async {
          await _addFavorite(phone, name);
          if (mounted) {
            SnackbarHelper.showSuccess(context, 'Friend added to favorites successfully');
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
    final dialogPadding = MediaQuery.of(context).size.width < 360 ? 20.0 : 28.0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                      child: Icon(Icons.person_add_rounded, size: 42, color: AppColors.kGreen),
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
                    style: TextStyle(fontSize: 15, height: 1.5, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogCtx).pop();
                        Share.share(_inviteMessage, subject: 'Invite to Madar');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.kGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Send Invite',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
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
                onTap: () => Navigator.of(dialogCtx).pop(),
                child: Icon(Icons.close, size: 22, color: Colors.grey[500]),
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
    final isSmallScreen = MediaQuery.of(context).size.width < 360;
    final hp = isSmallScreen ? 16.0 : 20.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Favorite Friends',
          style: TextStyle(color: AppColors.kGreen, fontWeight: FontWeight.w600),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[300], height: 1),
        ),
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Search bar + Add icon
                  Row(
                    children: [
                      Expanded(child: _buildSearchBar()),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _openAddFriendSheet,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(Icons.favorite_border, color: AppColors.kGreen, size: 22),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    color: AppColors.kGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Expanded(child: _buildContent()),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey.shade600, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search by name',
                hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_favorites.isEmpty) {
      return Center(
        child: Text(
          "You haven't favorite any friend yet.",
          style: TextStyle(color: Colors.grey[400], fontSize: 15),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Text(
          'No results found. Try again',
          style: TextStyle(color: Colors.grey[400], fontSize: 15),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final friend = _filtered[i];
        final name = friend['name'] as String? ?? '';
        final phone = friend['phone'] as String? ?? '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.kGreen.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: AppColors.kGreen, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _removeFavorite(phone),
                child: const Icon(Icons.favorite, color: Colors.red, size: 26),
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

class _AddFriendSheet extends StatefulWidget {
  final String currentUserPhone;
  final bool Function(String phone) isAlreadyFavorite;
  final Future<void> Function(String phone, String name) onAdd;
  final void Function(String phone) onInvite;

  const _AddFriendSheet({
    required this.currentUserPhone,
    required this.isAlreadyFavorite,
    required this.onAdd,
    required this.onInvite,
  });

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    final digits = _phoneCtrl.text.trim();

    if (digits.isEmpty) {
      setState(() => _errorMsg = 'Please enter a phone number');
      return;
    }
    if (digits.length < 9) {
      setState(() => _errorMsg = 'Enter a valid 9-digit phone number');
      return;
    }

    final fullPhone = '+966$digits';

    if (widget.currentUserPhone == fullPhone ||
        widget.currentUserPhone.replaceAll('+', '').endsWith(digits)) {
      setState(() => _errorMsg = "You can't add yourself to favorites");
      return;
    }

    if (widget.isAlreadyFavorite(fullPhone)) {
      setState(() => _errorMsg = 'Friend already in favorite list');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      // Look up the phone in the users collection
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: fullPhone)
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

      final data = query.docs.first.data();
      final firstName = (data['firstName'] ?? '').toString();
      final lastName = (data['lastName'] ?? '').toString();
      var name = '$firstName $lastName'.trim();
      if (name.isEmpty) name = fullPhone;

      // Write favorite to parent document (no subcollection)
      await widget.onAdd(fullPhone, name);

      if (mounted) Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = e.message ?? 'Something went wrong. Try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = 'Something went wrong. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          const SizedBox(height: 20),

          const Text(
            'Add to Favorites',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.kGreen,
            ),
          ),
          const SizedBox(height: 20),

          // Phone field
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _errorMsg != null ? AppColors.kError : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: const Text(
                    '+966',
                    style: TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    focusNode: _phoneFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    onChanged: (_) {
                      if (_errorMsg != null) setState(() => _errorMsg = null);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Phone number',
                      hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),

          if (_errorMsg != null) ...[
            const SizedBox(height: 6),
            Text(
              _errorMsg!,
              style: const TextStyle(
                color: AppColors.kError,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.kGreen.withOpacity(0.6),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      'Add',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
