import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'login_page.dart';
import 'home_page.dart';

late Box gymsBox;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  gymsBox = await Hive.openBox('gymsBox');

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

/// If no Supabase session -> LoginPage.
/// If signed in -> ensure a stable `Fire` row and pass `fireBaseId` to HomePage.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = supa.Supabase.instance.client.auth;

    return StreamBuilder<supa.AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        if (session == null) {
          return const LoginPage();
        }
        return FutureBuilder<String>(
          future: _getOrCreateFireBaseId(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return _ErrorScaffold(
                title: 'Could not load your profile record.',
                error: '${snap.error ?? 'Unknown error'}',
              );
            }
            return HomePage(fireBaseId: snap.data!);
          },
        );
      },
    );
  }

  /// IMPORTANT:
  /// - Never change an existing FireBaseID (it’s referenced by Gyms/Users).
  /// - Find by EmailID; if missing, INSERT and let DB generate FireBaseID.
  Future<String> _getOrCreateFireBaseId() async {
    final client = supa.Supabase.instance.client;
    final user = client.auth.currentUser;
    final email = user?.email;
    final name = (user?.userMetadata?['name'] as String?) ?? 'User';
    if (email == null || email.isEmpty) {
      throw Exception('Signed-in user has no email');
    }

    final existing = await client
        .from('Fire')
        .select('FireBaseID, Name, Location')
        .eq('EmailID', email)
        .maybeSingle();

    if (existing != null) {
      // Optionally keep Name/Location fresh (but do NOT touch FireBaseID)
      try {
        await client.from('Fire').update({'Name': name}).eq('EmailID', email);
      } catch (_) {}
      final id = existing['FireBaseID'] as String?;
      if (id == null || id.isEmpty) {
        throw Exception('Existing Fire row has no FireBaseID');
      }
      return id;
    }

    // Create new; let DB generate FireBaseID
    final inserted = await client
        .from('Fire')
        .insert({
          'EmailID': email,
          'Name': name,
          'Location': 'Unknown',
        })
        .select('FireBaseID')
        .single();

    final newId = inserted['FireBaseID'] as String?;
    if (newId == null || newId.isEmpty) {
      throw Exception('Failed to obtain FireBaseID from insert');
    }
    return newId;
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
