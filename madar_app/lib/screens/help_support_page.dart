import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:madar_app/widgets/app_widgets.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final FocusNode _messageFocusNode = FocusNode();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _selectedTopic = 'General question';
  String _activeTab = 'all';
  String _searchQuery = '';
  bool _isMessageExpanded = false;
  bool _showAllFaqs = false;
  bool _isSending = false;

  final List<FaqItem> _allFaqs = [
    FaqItem(
      category: 'navigation',
      question: 'How do I start AR navigation inside a venue?',
      answer:
          'Open Madar and select your venue. Tap "Navigate" on any place or point of interest, then point your camera at the floor to initialize AR. Follow the animated path arrows on your screen.',
    ),
    FaqItem(
      category: 'navigation',
      question: 'What should I do if the AR path looks wrong or glitchy?',
      answer:
          'Try moving your phone slowly in a figure-8 motion to recalibrate the AR. Make sure you are in a well-lit area. If the issue persists, close and reopen the navigation screen.',
    ),
    FaqItem(
      category: 'navigation',
      question: 'Can I navigate between different floors?',
      answer:
          'Yes. Madar supports multi-floor navigation. When your path crosses a floor, you will see a clear prompt to use stairs or elevators. Tap your preferred option to continue navigation to the next floor.',
    ),
    FaqItem(
      category: 'navigation',
      question: 'Does AR navigation work outdoors?',
      answer:
          'Madar is designed for large indoor venues. Outdoor areas are shown on the 3D map with basic info, but AR turn-by-turn navigation is only active inside supported venues.',
    ),
    FaqItem(
      category: 'exploration',
      question: 'How does AR Exploration mode work?',
      answer:
          'Tap "Explore" from the home screen, then point your camera around you. Madar overlays icons on nearby points of interest — shops, food courts, restrooms, exits — so you can discover what\'s around you without navigating to a specific destination.',
    ),
    FaqItem(
      category: 'exploration',
      question: 'Can I filter what shows up in Exploration mode?',
      answer:
          'Yes. Use the category filters at the bottom of the exploration screen to show only specific types of places, such as food, services, or exits.',
    ),
    FaqItem(
      category: 'exploration',
      question: 'Why don\'t I see POIs in Exploration mode?',
      answer:
          'Make sure you granted camera and location permissions for Madar. Also check that your venue has full data coverage — some venues show only basic info without AR overlays.',
    ),
    FaqItem(
      category: 'groups',
      question: 'How do I create a meeting point with friends?',
      answer:
          'Go to the Groups tab and tap "Create Meeting Point." Choose a location from the map, then invite friends from your list. All participants will receive a notification and can track each other\'s status in real time.',
    ),
    FaqItem(
      category: 'groups',
      question: 'How do I update my status in a meeting point?',
      answer:
          'Inside the meeting point screen, tap your current status and choose "On the way" or "Arrived." Your friends will see your update instantly.',
    ),
    FaqItem(
      category: 'groups',
      question: 'Can I cancel a meeting point I created?',
      answer:
          'Yes. Open the meeting point, tap the options menu (three dots), and select "Cancel meeting point." This action is permanent and all participants will be notified.',
    ),
    FaqItem(
      category: 'groups',
      question: 'How does live tracking work?',
      answer:
          'Send a tracking request to a friend from the Groups tab. Once they accept, you can see their approximate location on the venue map until either of you ends the session.',
    ),
    FaqItem(
      category: 'account',
      question: 'How do I create a Madar account?',
      answer:
          'Open the app and tap "Sign up." Enter your name, email address, and a password. Verify your email, then log in to start using Madar.',
    ),
    FaqItem(
      category: 'account',
      question: 'I forgot my password — how do I reset it?',
      answer:
          'On the login screen, tap "Forgot password?" and enter your registered email. You will receive a reset link within a few minutes.',
    ),
    FaqItem(
      category: 'account',
      question: 'How do I add friends in Madar?',
      answer:
          'Go to your profile and tap "Add friends." You can search by username or share your invite link. Once someone accepts, they appear in your friends list.',
    ),
    FaqItem(
      category: 'account',
      question: 'How do I delete my account?',
      answer:
          'Go to Settings → Account → Delete account. You will be asked to confirm. Please note that deletion is permanent and all your data, including meeting history and favorites, will be removed.',
    ),
  ];

  List<FaqItem> get _filteredFaqs {
    var list = _allFaqs;
    if (_activeTab != 'all') {
      list = list.where((f) => f.category == _activeTab).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list
          .where(
            (f) =>
                f.question.toLowerCase().contains(query) ||
                f.answer.toLowerCase().contains(query),
          )
          .toList();
    }
    return list;
  }

  List<FaqItem> get _visibleFaqs =>
      _showAllFaqs ? _filteredFaqs : _filteredFaqs.take(4).toList();

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<bool> _sendEmail({
    required String subject,
    required String body,
  }) async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'madar.support@gmail.com',
      queryParameters: {'subject': subject, 'body': body},
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      return true;
    }
    return false;
  }

  // IMPROVED onSendMessage (only one copy)
  void _onSendMessage() async {
    final topic = _selectedTopic;
    final message = _messageController.text.trim();
    final userEmail = FirebaseAuth.instance.currentUser?.email?.trim();

    if (message.isEmpty) {
      SnackbarHelper.showError(
        context,
        'Please enter a message before sending.',
      );
      return;
    }

    if (userEmail == null || userEmail.isEmpty) {
      SnackbarHelper.showError(context, 'Could not find your email address.');
      return;
    }

    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance.collection('mail').add({
        'to': ['madar.support@gmail.com'],
        'replyTo': userEmail,
        'message': {
          'subject': '[Madar Support] $topic',
          'html':
              '''
          <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #222;">
            <h2>New Support Request</h2>
            <p><strong>User email:</strong> $userEmail</p>
            <p><strong>Topic:</strong> $topic</p>
            <hr style="margin: 16px 0;">
            <p><strong>Message:</strong></p>
            <div style="background:#f7f7f7; padding:12px; border-radius:8px;">
              ${message.replaceAll('\n', '<br>')}
            </div>
          </div>
        ''',
          'text': 'User email: $userEmail\nTopic: $topic\n\n$message',
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      _messageController.clear();
      setState(() => _isSending = false);

      SnackbarHelper.showSuccess(
        context,
        'Your request was submitted successfully.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSending = false);
      SnackbarHelper.showError(
        context,
        'Failed to send message. Please try again.',
      );
    }
  }

  void _showEmailFallbackDialog(String messageBody) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No email app found'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We couldn’t open your email client. You can manually send your request to:',
            ),
            const SizedBox(height: 8),
            SelectableText(
              'madar.support@gmail.com',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.kGreen,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Your message has been copied to the clipboard.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: messageBody));
              Navigator.pop(context);
              SnackbarHelper.showSuccess(
                context,
                'Message copied! Please paste it into your email client.',
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.kGreen),
            child: const Text('Copy & Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        SnackbarHelper.showError(context, 'Could not open link.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    final horizontalPadding = isSmallScreen ? 16.0 : 24.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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
            'Help & Support',
            style: TextStyle(
              color: AppColors.kGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: CustomScrollView(
          slivers: [
            // FAQ Section
            // Category chips (filter buttons)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildTabChip('All', 'all'),
                        _buildTabChip('AR Navigation', 'navigation'),
                        _buildTabChip('AR Exploration', 'exploration'),
                        _buildTabChip('Groups & Tracking', 'groups'),
                        _buildTabChip('Account', 'account'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            // FAQ list with toggle button (simple TextButton)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (_filteredFaqs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No results found. Try different keywords.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      );
                    }

                    final visibleFaqs = _showAllFaqs
                        ? _filteredFaqs
                        : _filteredFaqs.take(4).toList();

                    if (index < visibleFaqs.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildFaqTile(visibleFaqs[index]),
                      );
                    }

                    if (_filteredFaqs.length > 4 &&
                        index == visibleFaqs.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Center(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _showAllFaqs = !_showAllFaqs),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _showAllFaqs ? 'Show less' : 'Show more',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.kGreen,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return const SizedBox.shrink();
                  },
                  childCount: _filteredFaqs.isEmpty
                      ? 1
                      : (_filteredFaqs.length > 4
                            ? (_showAllFaqs ? _filteredFaqs.length + 1 : 5)
                            : _filteredFaqs.length),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // Still need help? + Submit issue form
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const Text(
                    'Still need help?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Enhanced submit issue card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _isMessageExpanded = !_isMessageExpanded;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    //color: AppColors.kGreen.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.mail,
                                    color: AppColors.kGreen,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Submit your issue',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _isMessageExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 220),
                          crossFadeState: _isMessageExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                // Topic dropdown
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedTopic,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'General question',
                                        child: Text('General question'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'AR Navigation issue',
                                        child: Text('AR Navigation issue'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'AR Exploration issue',
                                        child: Text('AR Exploration issue'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Meeting point / tracking',
                                        child: Text('Meeting point / tracking'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Account & login',
                                        child: Text('Account & login'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Bug report',
                                        child: Text('Bug report'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Other',
                                        child: Text('Other'),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _selectedTopic = value!),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Icon(
                                        Icons.keyboard_arrow_down,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Message field
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _messageController,
                                    focusNode: _messageFocusNode,
                                    maxLines: 4,
                                    style: const TextStyle(fontSize: 14),
                                    decoration: const InputDecoration(
                                      hintText:
                                          'Describe your issue or question in detail…',
                                      hintStyle: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.all(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Send button
                                SizedBox(
                                  width: double.infinity,
                                  child: PrimaryButton(
                                    text: _isSending
                                        ? 'Sending...'
                                        : 'Send message',
                                    onPressed: _isSending
                                        ? null
                                        : _onSendMessage,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Follow us',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSocialCircle(
                        icon: FontAwesomeIcons.xTwitter,
                        label: 'X',
                        url: 'https://x.com/madar_app',
                      ),
                      const SizedBox(width: 40),
                      _buildSocialCircle(
                        icon: FontAwesomeIcons.instagram,
                        label: 'Instagram',
                        url: 'https://instagram.com/madar_app',
                      ),
                      const SizedBox(width: 40),
                      _buildSocialCircle(
                        icon: FontAwesomeIcons.youtube,
                        label: 'YouTube',
                        url: 'https://youtube.com/@madar_app',
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialCircle({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon, color: AppColors.kGreen, size: 22),
      ),
    );
  }

  Widget _buildTabChip(String label, String tab) {
    final isActive = _activeTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.kGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.kGreen : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  Widget _buildFaqTile(FaqItem faq) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(
            faq.question,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          iconColor: AppColors.kGreen,
          collapsedIconColor: AppColors.kGreen,
          children: [
            Text(
              faq.answer,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FaqItem {
  final String category;
  final String question;
  final String answer;
  FaqItem({
    required this.category,
    required this.question,
    required this.answer,
  });
}
