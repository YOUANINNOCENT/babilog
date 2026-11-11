import 'package:flutter/material.dart';

/// Identité BabiLogis : rouge et blanc. #FF0000 réservé au logo, #CC0000 aux actions.
abstract final class Couleurs {
  static const brand = Color(0xFFFF0000);
  static const primary = Color(0xFFCC0000);
  static const primaryPressed = Color(0xFFA30000);
  static const primarySoft = Color(0xFFFFEBEB);
  static const primarySoftBorder = Color(0xFFFFC2C2);
  static const pastille = Color(0xFFE5382F);
  static const fond = Color(0xFFF9F9F9);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF2F2F2);
  static const placeholder = Color(0xFFEDEDED);
  static const texte = Color(0xFF0F0F0F);
  static const texte2 = Color(0xFF606060);
  static const bordure = Color(0xFFE5E5E5);
  static const bordureForte = Color(0xFF767676);
  static const danger = Color(0xFFB42318);

  // Réservées aux verdicts de prix.
  static const justeFg = Color(0xFF146C43), justeBg = Color(0xFFE6F4EC);
  static const hautFg = Color(0xFF8A4B00), hautBg = Color(0xFFFFF1D6);
  static const basFg = Color(0xFF1E4E8C), basBg = Color(0xFFE0ECFA);
}

ThemeData themeBabiLogis() {
  final scheme = ColorScheme.fromSeed(seedColor: Couleurs.primary).copyWith(
    primary: Couleurs.primary,
    onPrimary: Colors.white,
    surface: Couleurs.surface,
    onSurface: Couleurs.texte,
    error: Couleurs.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Couleurs.fond,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 16, color: Couleurs.texte, height: 1.45),
      bodyLarge: TextStyle(fontSize: 17, color: Couleurs.texte, height: 1.45),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Couleurs.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Couleurs.texte,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: const BorderSide(color: Couleurs.bordureForte),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Couleurs.primary,
        minimumSize: const Size(48, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: const DividerThemeData(color: Couleurs.bordure, space: 1),
  );
}

/// Décoration des champs (au lieu d'un thème global, pour rester compatible
/// avec toutes les versions récentes de Flutter).
InputDecoration deco({String? hint, String? label, String? erreur, Widget? prefixe, String? suffixe, String? aide}) {
  OutlineInputBorder b(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    labelText: label,
    errorText: erreur,
    helperText: aide,
    prefixIcon: prefixe,
    suffixText: suffixe,
    filled: true,
    fillColor: Colors.white,
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
    border: b(Couleurs.bordureForte),
    enabledBorder: b(Couleurs.bordureForte),
    focusedBorder: b(Couleurs.primary, 2),
    errorBorder: b(Couleurs.danger),
    focusedErrorBorder: b(Couleurs.danger, 2),
  );
}
