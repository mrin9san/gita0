import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("User Profile")),
        body: const Center(child: Text("No user is logged in.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("User Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage:
                    user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                child: user.photoURL == null
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 30),
            Text("UID: ${user.uid}", style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text("Name: ${user.displayName ?? "Not set"}",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text("Email: ${user.email ?? "No email"}",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text("Phone: ${user.phoneNumber ?? "No phone"}",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text(
              "Provider: ${user.providerData.isNotEmpty ? user.providerData[0].providerId : "Unknown"}",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text("Email Verified: ${user.emailVerified}",
                style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
