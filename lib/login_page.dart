import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  bool _isSigningIn = false;
  double _scale = 1.0;

  Future<User?> _signInWithGoogle() async {
    try {
      setState(() => _isSigningIn = true);

      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email']);
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isSigningIn = false);
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      setState(() => _isSigningIn = false);
      return userCredential.user;
    } catch (e) {
      setState(() => _isSigningIn = false);
      debugPrint('Google Sign-In failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: $e")),
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.asset('assets/background.png', fit: BoxFit.cover),

          // Frosted glass overlay for effect
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),

          Column(
            children: [
              SizedBox(height: media.height * 0.1),

              // Logo
              Center(
                child: Image.asset(
                  'assets/logo.png',
                  width: media.width * 0.4,
                  height: media.height * 0.2,
                  fit: BoxFit.contain,
                ),
              ),

              SizedBox(height: media.height * 0.5),

              // Sign-in button
              Center(
                child: _isSigningIn
                    ? const CircularProgressIndicator()
                    : MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _scale = 1.05),
                        onExit: (_) => setState(() => _scale = 1.0),
                        child: GestureDetector(
                          onTapDown: (_) => setState(() => _scale = 0.95),
                          onTapUp: (_) => setState(() => _scale = 1.05),
                          onTapCancel: () => setState(() => _scale = 1.0),
                          child: AnimatedScale(
                            scale: _scale,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            child: GestureDetector(
                              onTap: () async {
                                final user = await _signInWithGoogle();
                                if (user != null && mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const HomePage()),
                                  );
                                }
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14, horizontal: 26),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 8,
                                          offset: const Offset(2, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Image.asset(
                                          'assets/google-logo.png',
                                          width: 24,
                                          height: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          "Sign in with Google",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
