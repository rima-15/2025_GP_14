import 'package:flutter/material.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
// import 'package:firebase_auth/firebase_auth.dart';

class CheckEmailPage
    extends StatelessWidget {
  final String email;
  const CheckEmailPage({
    super.key,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF787E65);

    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          const Expanded(
            flex: 1,
            child: SizedBox(height: 10),
          ),
          Expanded(
            flex: 7,
            child: Container(
              padding:
                  const EdgeInsets.fromLTRB(
                    25,
                    50,
                    25,
                    20,
                  ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.only(
                      topLeft:
                          Radius.circular(
                            40,
                          ),
                      topRight:
                          Radius.circular(
                            40,
                          ),
                    ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .center,
                children: [
                  const Icon(
                    Icons
                        .email_outlined,
                    size: 90,
                    color: green,
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  Text(
                    'Verify Email',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight:
                          FontWeight
                              .w900,
                      color: green,
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Text(
                    'We have sent a verification email to:',
                    textAlign: TextAlign
                        .center,
                    style:
                        const TextStyle(
                          color: Colors
                              .black54,
                        ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    email,
                    textAlign: TextAlign
                        .center,
                    style:
                        const TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight
                                  .bold,
                          color: Colors
                              .black87,
                        ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  const Text(
                    'Please verify your email before signing in.',
                    textAlign: TextAlign
                        .center,
                    style: TextStyle(
                      color: Colors
                          .black54,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width:
                        double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            green,
                        foregroundColor:
                            Colors
                                .white,
                        padding:
                            const EdgeInsets.symmetric(
                              vertical:
                                  14,
                            ),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const SignInScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Go to Sign In',
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
