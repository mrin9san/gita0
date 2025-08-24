import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Map<String, dynamic> _toUserJson(User user) {
    return {
      "uid": user.uid,
      "displayName": user.displayName,
      "email": user.email,
      "phoneNumber": user.phoneNumber,
      "photoURL": user.photoURL,
      "emailVerified": user.emailVerified,
      "isAnonymous": user.isAnonymous,
      "providerId":
      user.providerData.isNotEmpty ? user.providerData[0].providerId : null,
      "refreshToken": user.refreshToken,
      "tenantId": user.tenantId,
      "metadata": {
        "creationTime": user.metadata.creationTime?.toIso8601String(),
        "lastSignInTime": user.metadata.lastSignInTime?.toIso8601String(),
      },
      "providerData": user.providerData.map((info) => {
        "providerId": info.providerId,
        "uid": info.uid,
        "displayName": info.displayName,
        "email": info.email,
        "phoneNumber": info.phoneNumber,
        "photoURL": info.photoURL,
      }).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("User Profile")),
        body: const Center(
          child: Text("No user is logged in."),
        ),
      );
    }

    final jsonData = const JsonEncoder.withIndent("  ").convert(_toUserJson(user));

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
        child: SelectableText(
          jsonData,
          style: const TextStyle(fontSize: 14, fontFamily: "monospace"),
        ),
      ),
    );
  }
}
