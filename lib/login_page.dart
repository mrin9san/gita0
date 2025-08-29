// login_page.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa show Supabase;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isLoading = false;

  // === Write to Supabase "Fire" if not already present ===
  Future<void> _saveUserToSupabase(User user) async {
    final client = supa.Supabase.instance.client;

    // Safety: ensure we have an email; if not, stop here so you notice it.
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw Exception(
        'Firebase user has no email. Cannot insert into "Fire".',
      );
    }

    final payload = <String, dynamic>{
      // Use exact case to match your quoted columns
      'Name': user.displayName ?? 'User',
      'EmailID': email, // <-- key we de-duplicate on
      'Location': 'Unknown',
      // "GymID" and "created_at" are auto-populated by DB defaults
    };

    try {
      // 1) Check if row exists for this EmailID
      final existing = await client
          .from('Fire') // IMPORTANT: exact case because table is "Fire"
          .select('GymID, EmailID')
          .eq('EmailID', email)
          .maybeSingle();

      if (existing != null) {
        // Already there; nothing more to do.
        return;
      }

      // 2) Not found -> insert
      // Use .select().single() to fail loudly if insert didn’t happen
      await client.from('Fire').insert(payload).select('GymID').single();
    } catch (e) {
      // Bubble up so caller shows a visible error
      rethrow;
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => isLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return; // user canceled
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // 🔽 Try saving to Supabase
      await _saveUserToSupabase(userCred.user!);

      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed in & synced to Supabase ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login/Supabase error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                )
              : GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Gym0",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Sign in to manage your gyms",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.login),
                          label: const Text("Sign in with Google"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color.fromARGB(60, 255, 255, 255),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: _signInWithGoogle,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(60, 255, 255, 255),
            Color.fromARGB(20, 255, 255, 255),
          ],
        ),
        border: Border.all(
          color: Color.fromARGB(30, 255, 255, 255),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(100, 0, 0, 0),
            blurRadius: 10,
            offset: Offset(4, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: const Color.fromARGB(25, 0, 0, 0),
            child: child,
          ),
        ),
      ),
    );
  }
}
