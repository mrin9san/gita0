import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa
    show Supabase, OAuthProvider;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isLoading = false;

  Future<void> _saveUserToSupabase(User user) async {
    final client = supa.Supabase.instance.client;

    final email = user.email;
    if (email == null || email.isEmpty) {
      throw Exception('Firebase user has no email. Cannot insert into "Fire".');
    }

    final existing = await client
        .from('Fire')
        .select('FireBaseID, EmailID')
        .eq('EmailID', email)
        .maybeSingle();

    if (existing != null) return;

    await client
        .from('Fire')
        .insert({
          'Name': user.displayName ?? 'User',
          'EmailID': email,
          'Location': 'Unknown'
        })
        .select('FireBaseID')
        .single();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;

      // Firebase sign-in
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // ✅ Supabase session from the same Google ID token (enables RLS)
      await supa.Supabase.instance.client.auth.signInWithIdToken(
        provider: supa.OAuthProvider.google,
        idToken: googleAuth.idToken!, // required
        accessToken: googleAuth.accessToken, // recommended on Android
      );

      // Upsert Fire row
      await _saveUserToSupabase(userCred.user!);

      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in & synced to Supabase ✅')));
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Login error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
              image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
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
                              color: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        const Text("Sign in to manage your gyms",
                            style:
                                TextStyle(fontSize: 16, color: Colors.white70)),
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
                                borderRadius: BorderRadius.circular(30)),
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
            Color.fromARGB(20, 255, 255, 255)
          ],
        ),
        border: Border.all(
            color: const Color.fromARGB(30, 255, 255, 255), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color.fromARGB(100, 0, 0, 0),
              blurRadius: 10,
              offset: Offset(4, 6))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child:
              Container(color: const Color.fromARGB(25, 0, 0, 0), child: child),
        ),
      ),
    );
  }
}
