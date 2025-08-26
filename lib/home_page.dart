import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              if (user != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("No user is logged in.")),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: user != null
            ? Text(
                "Hello, ${user.displayName ?? "No Name"}!",
                style: const TextStyle(fontSize: 24),
              )
            : const Text(
                "No user is logged in.",
                style: TextStyle(fontSize: 24),
              ),
      ),
    );
  }
}
