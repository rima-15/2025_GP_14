import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Help Page
// ----------------------------------------------------------------------------

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'madar@gmail.com',
      query: 'subject=Madar App Support',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final horizontalPadding = isSmallScreen ? 20.0 : 24.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.kGreen),
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
      body: SingleChildScrollView(
        padding: EdgeInsets.all(horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Contact Card
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isSmallScreen ? 20 : 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: isSmallScreen ? 64 : 80,
                    height: isSmallScreen ? 64 : 80,
                    decoration: BoxDecoration(
                      color: AppColors.kGreen.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      size: isSmallScreen ? 32 : 40,
                      color: AppColors.kGreen,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 16 : 20),
                  Text(
                    'Need Help?',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 20 : 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Contact our support team',
                    style: TextStyle(fontSize: 15, color: Colors.black54),
                  ),
                  SizedBox(height: isSmallScreen ? 20 : 24),
                  InkWell(
                    onTap: _launchEmail,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.kGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.kGreen.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.email, color: AppColors.kGreen, size: 20),
                          SizedBox(width: 12),
                          Text(
                            'madar@gmail.com',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.kGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // FAQ Section
            Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            _buildFAQItem(
              question: 'How do I navigate to a venue?',
              answer:
                  'Select a venue from the home page, then tap the navigation icon to get directions.',
            ),
            const SizedBox(height: 12),

            _buildFAQItem(
              question: 'How do I change my password?',
              answer:
                  'Go to Sign In page and tap "Forgot Password" to reset your password via email.',
            ),
            const SizedBox(height: 12),

            _buildFAQItem(
              question: 'How do I update my profile information?',
              answer:
                  'Open the sidebar menu, tap Profile, make your changes, and tap Save Changes.',
            ),
            const SizedBox(height: 12),

            _buildFAQItem(
              question: 'How does location tracking work?',
              answer:
                  'Enable location services in your device settings. Madar uses your location to show nearby venues and provide accurate navigation.',
            ),
            const SizedBox(height: 12),

            _buildFAQItem(
              question: 'Can I delete my account?',
              answer:
                  'Yes. Go to Profile and tap "Delete Account" at the bottom. This action cannot be undone.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem({required String question, required String answer}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          iconColor: AppColors.kGreen,
          collapsedIconColor: AppColors.kGreen,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                answer,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
