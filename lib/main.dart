import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:hive_flutter/hive_flutter.dart';

// Import ONLY Supabase symbol(s) we use; avoids bringing in supabase's User
import 'package:supabase_flutter/supabase_flutter.dart' as supa show Supabase;

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
      title: 'Login App',
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
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          // snapshot.data is fb.User (Firebase)
          return HomePage(user: snapshot.data!);
        }

        return const LoginPage();
      },
    );
  }
}
