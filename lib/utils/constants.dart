import 'package:flutter/material.dart';

class JarvisColors {
  static const Color background    = Color(0xFF020812);
  static const Color surface       = Color(0xFF050F1E);
  static const Color surfaceLight  = Color(0xFF0A1929);
  static const Color cyan          = Color(0xFF00E5FF);
  static const Color cyanDim       = Color(0xFF0097A7);
  static const Color electricBlue  = Color(0xFF2979FF);
  static const Color neonBlue      = Color(0xFF00B0FF);
  static const Color gold          = Color(0xFFFFD740);
  static const Color red           = Color(0xFFFF1744);
  static const Color green         = Color(0xFF00E676);
  static const Color textPrimary   = Color(0xFFE0F7FA);
  static const Color textSecondary = Color(0xFF4DD0E1);
  static const Color textDim       = Color(0xFF1A3A4A);
  static const Color border        = Color(0xFF0D2137);
  static const Color glowCyan      = Color(0x3300E5FF);
  static const Color glowBlue      = Color(0x332979FF);
}

class JarvisStrings {
  static const String appName      = 'JARVIS AI';
  static const String brand        = 'by CassimTV';
  static const String wakeWord     = 'Jarvis';
  static const String defaultGreet = 'At your service, sir.';
  static const String ready        = 'Ever ready to assist you.';
  static const String standby      = 'STANDBY';
  static const String listening    = 'LISTENING';
  static const String processing   = 'PROCESSING';
  static const String speaking     = 'SPEAKING';
  static const String backendUrl   = 'http://localhost:8000'; // Change to your server
}

class JarvisDurations {
  static const Duration fast    = Duration(milliseconds: 200);
  static const Duration medium  = Duration(milliseconds: 500);
  static const Duration slow    = Duration(milliseconds: 1000);
  static const Duration pulse   = Duration(milliseconds: 2000);
}
