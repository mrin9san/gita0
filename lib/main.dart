import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'login_page.dart';
import 'home_page.dart';

late Box gymsBox; // global Hive box for gyms

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
      // options: DefaultFirebaseOptions.currentPlatform, // uncomment if using firebase_options.dart
      );

  // Initialize Hive
  await Hive.initFlutter();
  gymsBox = await Hive.openBox('gymsBox'); // open box and assign globally

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginPage(),
      routes: {
        '/home': (context) => const HomePage(),
        // Add other routes here if needed
      },
    );
  }
}
