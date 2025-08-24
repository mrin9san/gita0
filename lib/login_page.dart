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
          // Background
          Image.asset('assets/background.png', fit: BoxFit.cover),
          Column(
            children: [
              SizedBox(height: media.height * 0.1),
              Center(
                child: Image.asset(
                  'assets/logo.png',
                  width: media.width * 0.4,
                  height: media.height * 0.2,
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(height: media.height * 0.5),
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
                            child: ElevatedButton.icon(
                              icon: Image.asset(
                                'assets/google-logo.png',
                                width: 24,
                                height: 24,
                              ),
                              label: const Text(
                                'Sign in with Google',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.black.withOpacity(0.7), // Dark grey
                                foregroundColor: Colors.white, // Text/Icon
                                shadowColor: Colors.black45,
                                elevation: 5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 24),
                              ),
                              onPressed: () async {
                                final user = await _signInWithGoogle();
                                if (user != null && mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const HomePage(),
                                    ),
                                  );
                                }
                              },
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
