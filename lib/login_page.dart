import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isSigningIn = false;

  Future<User?> _signInWithGoogle() async {
    try {
      setState(() => _isSigningIn = true);

      // Create GoogleSignIn instance
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email']);

      // Start sign-in flow
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isSigningIn = false);
        return null; // User cancelled
      }

      // Obtain auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create Firebase credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
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
    // Get screen size for responsive layout
    final media = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.asset('assets/background.png', fit: BoxFit.cover),
          // Column aligned from top
          Column(
            children: [
              SizedBox(height: media.height * 0.1), // 10% from top
              Center(
                child: Image.asset(
                  'assets/logo.png',
                  width: media.width * 0.4, // 50% of screen width
                  height: media.height * 0.2, // 25% of screen height
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(height: media.height * 0.5), // spacing below logo
              Center(
                child: _isSigningIn
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text("Sign in with Google"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          textStyle: const TextStyle(fontSize: 18),
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
            ],
          ),
        ],
      ),
    );
  }
}
