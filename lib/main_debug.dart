import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Text('OK - работает',
            style: TextStyle(fontSize: 24, color: Colors.red)),
      ),
    ),
  ));
}
