import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';

class OTPScreen extends StatefulWidget {
  final String email;
  const OTPScreen({
    super.key,
    required this.email,
  });

  @override
  State<OTPScreen> createState() =>
      _OTPScreenState();
}

class _OTPScreenState
    extends State<OTPScreen> {
  final Color green = const Color(
    0xFF787E65,
  );
  final _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final _focusNodes = List.generate(
    6,
    (_) => FocusNode(),
  );
  int _seconds = 60;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker((_) {
      if (!mounted) return;
      if (_seconds > 0) {
        setState(() => _seconds--);
      } else {
        _ticker.stop();
      }
    })..start();
  }

  @override
  void dispose() {
    for (final c in _controllers)
      c.dispose();
    for (final f in _focusNodes)
      f.dispose();
    _ticker.dispose();
    super.dispose();
  }

  String get _otp => _controllers
      .map((c) => c.text)
      .join();

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
              child: Column(
                children: [
                  Text(
                    'Enter OTP',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight:
                          FontWeight
                              .w900,
                      color: green,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'We sent a 6-digit code to ${widget.email}',
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .spaceBetween,
                    children:
                        List.generate(
                          6,
                          (i) =>
                              _otpBox(
                                i,
                              ),
                        ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          green,
                      foregroundColor:
                          Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                            vertical:
                                14,
                          ),
                    ),
                    onPressed: () {
                      if (_otp.length ==
                          6) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Verifying code: $_otp",
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'Verify',
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  if (_seconds > 0)
                    Text(
                      "Resend in $_seconds s",
                    )
                  else
                    TextButton(
                      onPressed: () {
                        setState(
                          () =>
                              _seconds =
                                  60,
                        );
                        _ticker.start();
                      },
                      child: const Text(
                        "Resend code",
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

  Widget _otpBox(int index) {
    return SizedBox(
      width: 46,
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType:
            TextInputType.number,
        inputFormatters: [
          LengthLimitingTextInputFormatter(
            1,
          ),
          FilteringTextInputFormatter
              .digitsOnly,
        ],
      ),
    );
  }
}

class Ticker {
  Ticker(this.onTick);
  final void Function(Duration) onTick;
  Duration _elapsed = Duration.zero;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    _tick();
  }

  void stop() => _running = false;
  void dispose() => _running = false;

  void _tick() async {
    while (_running) {
      await Future<void>.delayed(
        const Duration(seconds: 1),
      );
      _elapsed += const Duration(
        seconds: 1,
      );
      onTick(_elapsed);
    }
  }
}
