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
          // Profile Picture Button
          if (user != null && user.photoURL != null)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: CircleAvatar(
                  radius: 18, // size of the circle
                  backgroundImage: NetworkImage(user.photoURL!),
                  backgroundColor: Colors.transparent,
                ),
              ),
            )
          else
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

          // Logout button
          if (user != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Logged out successfully.")),
                );
                // After logout, refresh UI
                Navigator.pushNamedAndRemoveUntil(
                    context, "/", (route) => false);
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
