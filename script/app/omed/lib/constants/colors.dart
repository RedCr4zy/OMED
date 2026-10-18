import 'package:flutter/material.dart';

// =========================================
//         Palette partagee de l'app
// =========================================
/// Palette centrale afin de garder une apparence coherente entre les ecrans.
class AppColors {
  /// Cette classe ne contient que des constantes statiques.
  AppColors._();

  // Couleurs d'accent disponibles pour les composants.
  static const Color primary = Color(0xFF7C5CFC);
  static const Color secondary = Color(0xFF4C8DFF);

  // Fond global, surfaces de cartes/formulaires, bordure et transparence.
  static const Color background = Color(0xFF0F1117);
  static const Color primarySurface = Color(0xFFF5F5F5);
  static const Color secondarySurface = Color(0xFF191D27);
  static const Color outline = Color(0xFF503B31);
  static const Color transparent = Color.fromARGB(0, 255, 255, 255);

  // Couleurs des textes principaux et secondaires.
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF9CA3AF);

  // Couleurs semantiques pour les etats de succes, avertissement et erreur.
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);
}
