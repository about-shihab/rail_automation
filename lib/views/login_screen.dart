import 'package:flutter/material.dart';
import '../models/auth_session.dart';
import 'search_screen.dart';
import 'webview_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController(text: '01813570430');
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final session = await AuthSession.load();
    if (session != null && session.isValid) {
      if (session.phoneNumber != null && session.phoneNumber!.isNotEmpty) {
        _phoneController.text = session.phoneNumber!;
      }
      if (session.password != null && session.password!.isNotEmpty) {
        _passwordController.text = session.password!;
      }
    }
  }

  Future<void> _handleDirectLogin() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your mobile number')),
      );
      return;
    }

    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('রেলওয়ের ক্লাউডফ্লেয়ার সুরক্ষার জন্য ওয়েবভিউ এর মাধ্যমে লগইন করুন।'),
        duration: Duration(seconds: 2),
      ),
    );
    await _openWebviewLogin();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _openWebviewLogin() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
    );
    if (result == true && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Bangladesh Railway Crest / Logo
                Container(
                  width: 80,
                  height: 80,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF10B981), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.train, color: Color(0xFF10B981), size: 40),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bangladesh Railway',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'টিকিট এভেইলেবিলিটি নোটিফায়ার',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),

                // Login Form Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sign in with your Railway e-ticket credentials',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 20),

                      // Mobile Number Field
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Mobile Number',
                          labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                          prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF10B981)),
                          hintText: '018XXXXXXXX',
                          hintStyle: const TextStyle(color: Colors.white24),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Password Field
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                          prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF10B981)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.white38,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                          hintText: '••••••••',
                          hintStyle: const TextStyle(color: Colors.white24),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Remember Me Checkbox
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            activeColor: const Color(0xFF10B981),
                            checkColor: Colors.black,
                            onChanged: (val) {
                              setState(() => _rememberMe = val ?? true);
                            },
                          ),
                          const Text(
                            'Remember Login Info',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Sign In Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          onPressed: _isLoading ? null : _handleDirectLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Sign In & Continue',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Alternative Options Divider
                Row(
                  children: [
                    const Expanded(child: Divider(color: Colors.white12)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR CONNECT VIA',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: Colors.white12)),
                  ],
                ),
                const SizedBox(height: 16),

                // Webview Login Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.tealAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.language, color: Colors.tealAccent, size: 18),
                    label: const Text(
                      'Login via Railway Webview',
                      style: TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: _openWebviewLogin,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
