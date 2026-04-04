import 'package:flutter/material.dart';
import 'services/database_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the database (creates tables if missing)
  final db = DatabaseService();
  await db.database;

  // Run VACUUM in background only if db is large (>100 MB)
  db.vacuumIfNeeded(100_000_000);
  
  runApp(const GpsCollectorApp());
}

class GpsCollectorApp extends StatelessWidget {
  const GpsCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Collector',
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
