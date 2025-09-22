import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';


void main() async {
WidgetsFlutterBinding.ensureInitialized();
await AndroidAlarmManager.initialize();
runApp(const MyApp());
}


class MyApp extends StatelessWidget {
const MyApp({super.key});


@override
Widget build(BuildContext context) {
return MaterialApp(
debugShowCheckedModeBanner: false,
title: 'Presence Mode',
theme: ThemeData(
textTheme: GoogleFonts.playfairDisplayTextTheme(
Theme.of(context).textTheme,
),
scaffoldBackgroundColor: const Color(0xFFFDFDFD),
appBarTheme: const AppBarTheme(
backgroundColor: Colors.white,
elevation: 0.5,
iconTheme: IconThemeData(color: Colors.black87),
),
),
home: const HomeScreen(),
);
}
}