import 'package:flutter/material.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';

class SignUpScreen
    extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() =>
      _SignUpScreenState();
}

class _SignUpScreenState
    extends State<SignUpScreen> {
  final _formSignupKey =
      GlobalKey<FormState>();
  bool agreePersonalData = true;

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
            flex: 13,
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
                  key: _formSignupKey,
                  child: Column(
                    children: [
                      Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight:
                              FontWeight
                                  .w900,
                          color: const Color(
                            0xFF787E65,
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 40,
                      ),

                      // First Name
                      TextFormField(
                        decoration: InputDecoration(
                          label: const Text(
                            'First Name',
                          ),
                          hintText:
                              'Enter First Name',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                                  10,
                                ),
                          ),
                        ),
                        validator: (value) =>
                            value ==
                                    null ||
                                value
                                    .isEmpty
                            ? 'Enter First Name'
                            : null,
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Last Name
                      TextFormField(
                        decoration: InputDecoration(
                          label: const Text(
                            'Last Name',
                          ),
                          hintText:
                              'Enter Last Name',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                                  10,
                                ),
                          ),
                        ),
                        validator: (value) =>
                            value ==
                                    null ||
                                value
                                    .isEmpty
                            ? 'Enter Last Name'
                            : null,
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Email
                      TextFormField(
                        decoration: InputDecoration(
                          label:
                              const Text(
                                'Email',
                              ),
                          hintText:
                              'Enter Email',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                                  10,
                                ),
                          ),
                        ),
                        validator: (value) =>
                            value ==
                                    null ||
                                value
                                    .isEmpty
                            ? 'Enter Email'
                            : null,
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Phone Number
                      TextFormField(
                        keyboardType:
                            TextInputType
                                .phone,
                        decoration: InputDecoration(
                          label: const Text(
                            'Phone Number',
                          ),
                          hintText:
                              'Enter Phone Number',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                                  10,
                                ),
                          ),
                        ),
                        validator: (value) =>
                            value ==
                                    null ||
                                value
                                    .isEmpty
                            ? 'Enter Phone Number'
                            : null,
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Password
                      TextFormField(
                        obscureText:
                            true,
                        decoration: InputDecoration(
                          label: const Text(
                            'Password',
                          ),
                          hintText:
                              'Enter Password',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                                  10,
                                ),
                          ),
                        ),
                        validator: (value) =>
                            value ==
                                    null ||
                                value
                                    .isEmpty
                            ? 'Enter Password'
                            : null,
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Agree to terms
                      Row(
                        children: [
                          Checkbox(
                            value:
                                agreePersonalData,
                            onChanged: (value) {
                              setState(
                                () => agreePersonalData =
                                    value!,
                              );
                            },
                            activeColor:
                                const Color(
                                  0xFF787E65,
                                ),
                          ),
                          const Text(
                            'I agree to the processing of ',
                          ),
                          Text(
                            'Personal data',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                              color: const Color(
                                0xFF787E65,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Sign Up button
                      SizedBox(
                        width: double
                            .infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(
                                  0xFF787E65,
                                ),
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
                            if (_formSignupKey
                                    .currentState!
                                    .validate() &&
                                agreePersonalData) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Processing Data',
                                  ),
                                ),
                              );
                            }
                          },
                          child:
                              const Text(
                                'Sign up',
                              ),
                        ),
                      ),
                      const SizedBox(
                        height: 30,
                      ),

                      // Already have account
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                        children: [
                          const Text(
                            'Already have an account?',
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const SignInScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              ' Sign in',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                color: Color(
                                  0xFF787E65,
                                ),
                              ),
                            ),
                          ),
                        ],
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
