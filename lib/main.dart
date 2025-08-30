import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Supabase (alias only what we need)
import 'package:supabase_flutter/supabase_flutter.dart' as supa
    show Supabase, OAuthProvider;

import 'login_page.dart';
import 'home_page.dart';

late Box gymsBox;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp();

  // Hive
  await Hive.initFlutter();
  gymsBox = await Hive.openBox('gymsBox');

  // Supabase
  await supa.Supabase.initialize(
    url: 'https://ffwrdbdixtdkawpzfcsu.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZmd3JkYmRpeHRka2F3cHpmY3N1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYzMjEyODAsImV4cCI6MjA3MTg5NzI4MH0.CcEIaWTj9C23M_vWPecameXwB_lP3NbS9eEI0UZ_w-s',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym0',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb.User?>(
      stream: fb.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (!snap.hasData || snap.data == null) {
          return const LoginPage();
        }

        final user = snap.data!;

        // 1) Make sure a Supabase session exists (so RLS sees role=authenticated)
        return FutureBuilder<void>(
          future: _ensureSupabaseSession(),
          builder: (context, sSnap) {
            if (sSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (sSnap.hasError) {
              return _ErrorScaffold(
                title: 'Could not initialize Supabase session.',
                error: '${sSnap.error}',
              );
            }

            // 2) Fetch/create row in "Fire" and get FirebaseID (UUID)
            return FutureBuilder<String>(
              future: _fetchOrCreateFireBaseId(user),
              builder: (context, fSnap) {
                if (fSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                      body: Center(child: CircularProgressIndicator()));
                }
                if (fSnap.hasError || !fSnap.hasData) {
                  return _ErrorScaffold(
                    title: 'Could not load your profile record.',
                    error: '${fSnap.error ?? 'Unknown error'}',
                  );
                }

                final fireBaseId = fSnap.data!;
                return HomePage(user: user, fireBaseId: fireBaseId);
              },
            );
          },
        );
      },
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  final String title;
  final String error;
  const _ErrorScaffold({required this.title, required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => (context as Element).markNeedsBuild(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ensure Supabase Auth session exists (so RLS has auth.email()).
/// If none, try a silent Google sign-in and mint a Supabase session with the ID token.
Future<void> _ensureSupabaseSession() async {
  final client = supa.Supabase.instance.client;
  if (client.auth.currentSession != null) return;

  final silent = await GoogleSignIn().signInSilently();
  if (silent == null) return;
  final gAuth = await silent.authentication;
  final idToken = gAuth.idToken;
  if (idToken == null) return;

  await client.auth.signInWithIdToken(
    provider: supa.OAuthProvider.google,
    idToken: idToken,
    accessToken: gAuth.accessToken, // recommended on Android
  );
}

/// Read/create the user's row in "Fire" by EmailID; return FirebaseID (UUID).
Future<String> _fetchOrCreateFireBaseId(fb.User user) async {
  final client = supa.Supabase.instance.client;

  final email = user.email;
  if (email == null || email.isEmpty) {
    throw Exception(
        'Signed-in Firebase user has no email; cannot map to Fire.EmailID');
  }

  // Try find
  final existing =
      await client.from('Fire').select('FireBaseID').eq('EmailID', email);
  if (existing is List && existing.isNotEmpty) {
    final id = existing.first['FireBaseID'];
    if (id is String && id.isNotEmpty) return id;
  }

  // Insert
  final inserted = await client
      .from('Fire')
      .insert({
        'EmailID': email,
        'Name': user.displayName ?? 'User',
        // 'Location': 'Unknown' // table default exists
      })
      .select('FireBaseID')
      .single();

  final newId = inserted['FireBaseID'];
  if (newId is String && newId.isNotEmpty) return newId;

  throw Exception('Failed to obtain FireBaseID from Fire table');
}
