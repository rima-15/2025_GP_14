import 'package:flutter/material.dart';
import 'package:madar_app/screens/otp_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';

class ForgotPasswordScreen
    extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
  });

  @override
  State<ForgotPasswordScreen>
  createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends
        State<ForgotPasswordScreen> {
  final _formKey =
      GlobalKey<FormState>();
  final _emailCtrl =
      TextEditingController();
  final Color green = const Color(
    0xFF787E65,
  );

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Forgot Password',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight:
                              FontWeight
                                  .w900,
                          color: green,
                        ),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      Text(
                        "Enter the email associated with your account and we’ll send you a reset code.",
                        style: TextStyle(
                          color: Colors
                              .grey[700],
                        ),
                      ),
                      const SizedBox(
                        height: 24,
                      ),
                      TextFormField(
                        controller:
                            _emailCtrl,
                        decoration: InputDecoration(
                          labelText:
                              "Email",
                          prefixIcon:
                              const Icon(
                                Icons
                                    .email_outlined,
                              ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                                  10,
                                ),
                          ),
                        ),
                        validator: (v) =>
                            v == null ||
                                v
                                    .trim()
                                    .isEmpty
                            ? "Enter your email"
                            : null,
                      ),
                      const SizedBox(
                        height: 20,
                      ),
                      SizedBox(
                        width: double
                            .infinity,
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
                            if (_formKey
                                .currentState!
                                .validate()) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OTPScreen(
                                    email:
                                        _emailCtrl.text.trim(),
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            "Send reset code",
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
