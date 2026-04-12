// lib/screens/help_support_page.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/widgets/app_widgets.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _selectedTopic = 'General question';
  String _activeTab = 'all';
  String _searchQuery = '';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendEmail({
    required String subject,
    required String body,
  }) async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'support@madar.app',
      queryParameters: {'subject': subject, 'body': body},
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Could not open email client. Please email support@madar.app manually.',
        );
      }
    }
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

  void _onAskPressed() {
    final query = _searchController.text.trim();
    final body = query.isEmpty
        ? 'I need help with Madar.'
        : 'I need help with Madar: $query';
    _sendEmail(subject: 'Madar Support Request', body: body);
  }

  void _onSendMessage() {
    final topic = _selectedTopic;
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      SnackbarHelper.showError(
        context,
        'Please enter a message before sending.',
      );
      return;
    }
    final fullMessage = 'Topic: $topic\n\n$message';
    _sendEmail(subject: 'Madar Support Request', body: fullMessage);
    _messageController.clear();
    SnackbarHelper.showSuccess(context, 'Message sent! We\'ll reply soon.');
  }

  void _reportBug() async {
    final controller = TextEditingController();
    final desc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a Bug'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Describe what went wrong...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (desc != null && desc.trim().isNotEmpty) {
      _sendEmail(subject: 'Bug Report - Madar', body: desc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    final horizontalPadding = isSmallScreen ? 16.0 : 24.0;

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
          'Help & Support',
          style: TextStyle(
            color: AppColors.kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.kGreen,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.kGreen,
          tabs: const [
            Tab(text: 'FAQ'),
            Tab(text: 'Contact us'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // FAQ Tab
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 16),
                    // Search bar + Ask button
                    /*Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              hintText: 'Search for a topic...',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.grey[500],
                              ),
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),*/
                    // Category chips
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
              // FAQ list
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
                      return _buildFaqTile(_filteredFaqs[index]);
                    },
                    childCount:
                        _filteredFaqs.isEmpty ? 1 : _filteredFaqs.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
          // Contact us Tab
          SingleChildScrollView(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
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
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildContactCard(
                      icon: Icons.email_outlined,
                      title: 'Email support',
                      description: 'We reply within 24 hours on business days.',
                      buttonText: 'madar@gmail.com',
                      onPressed: () => _sendEmail(
                        subject: 'Madar Support Request',
                        body: '',
                      ),
                    ),
                    _buildContactCard(
                      icon: Icons.bug_report_outlined,
                      title: 'Report a bug',
                      description:
                          'Found something broken? Let us know the details.',
                      buttonText: 'Report ',
                      onPressed: _reportBug,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Send us a message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedTopic,
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
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) => setState(() => _selectedTopic = value!),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Describe your issue or question in detail…',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    text: 'Send message',
                    onPressed: _onSendMessage,
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleFollowLink({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return GestureDetector(
      onTap: () => _launchUrl(url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.kGreen),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.kGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(String label, String tab) {
    final isActive = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isActive,
        onSelected: (_) => setState(() => _activeTab = tab),
        backgroundColor: Colors.grey[100],
        selectedColor: AppColors.kGreen.withOpacity(0.15),
        checkmarkColor: AppColors.kGreen,
        labelStyle: TextStyle(
          color: isActive ? AppColors.kGreen : Colors.grey[700],
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isActive ? AppColors.kGreen : Colors.grey[300]!,
          ),
        ),
      ),
    );
  }

  Widget _buildFaqTile(FaqItem faq) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            faq.question,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                faq.answer,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 2,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.kGreen, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                buttonText,
                style: const TextStyle(fontSize: 12, color: AppColors.kGreen),
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