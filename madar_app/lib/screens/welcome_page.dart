import 'package:flutter/material.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/screens/signup_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/widgets/welcome_button.dart';

class WelcomeScreen
    extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          Flexible(
            flex: 2,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 40.0,
                  ),
              child: Center(
                child: RichText(
                  textAlign:
                      TextAlign.center,
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text:
                            'Welcome!\n',
                        style: TextStyle(
                          fontSize:
                              45.0,
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                      ),
                      TextSpan(
                        text:
                            '\nFind venues, meet friends, and explore with confidence!',
                        style: TextStyle(
                          fontSize: 20,
                          // height: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            flex: 1,
            child: Align(
              alignment:
                  Alignment.bottomRight,
              child: Row(
                children: [
                  const Expanded(
                    child: WelcomeButton(
                      buttonText:
                          'Sign in',
                      onTap:
                          SignInScreen(),
                      color: Colors
                          .transparent,
                      textColor:
                          Colors.white,
                    ),
                  ),
                  Expanded(
                    child: WelcomeButton(
                      buttonText:
                          'Sign up',
                      onTap:
                          const SignUpScreen(),
                      color:
                          Colors.white,
                      textColor: Color(
                        0xFF787E65,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
