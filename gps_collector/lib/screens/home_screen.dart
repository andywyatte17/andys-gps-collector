import 'package:flutter/material.dart';
import 'debug_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Collector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug DB',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DebugScreen()),
              );
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('GPS Collector - Ready'),
      ),
    );
  }
}
