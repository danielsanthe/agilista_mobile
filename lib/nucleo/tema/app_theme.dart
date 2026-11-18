import 'package:flutter/material.dart';

/// Centralização do Design System e Identidade Visual do AgiLista
class AppTheme {
  // ===========================================================================
  // PALETA DE CORES OFICIAIS
  // ===========================================================================
  static const Color primaryBlue = Color(0xFF1E3A8A);    // Azul Escuro Primário
  static const Color primaryBlueLight = Color(0xFF2563EB); // Azul Interativo
  static const Color accentOrange = Color(0xFFF97316);   // Laranja Secundário / Destaque
  
  static const Color backgroundLight = Color(0xFFF8FAFC); // Fundo Principal da Tela
  static const Color surfaceWhite = Colors.white;         // Fundo dos Cards e TextFields
  
  static const Color textDark = Color(0xFF1E293B);        // Texto Principal
  static const Color textMuted = Color(0xFF64748B);       // Texto Secundário / Placeholders
  static const Color borderLight = Color(0xFFE2E8F0);     // Bordas Suaves
  
  // Status de Orçamento / Ações
  static const Color statusSuccess = Color(0xFF16A34A);   // Dentro do Limite
  static const Color statusWarning = Color(0xFFD97706);   // Próximo do Limite (>= 80%)
  static const Color statusDanger = Color(0xFFDC2626);    // Excedido / Excluir Item

  // ===========================================================================
  // TEMA GLOBAL DO FLUTTER (ThemeData)
  // ===========================================================================
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: accentOrange,
        surface: surfaceWhite,
        error: statusDanger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDark,
      ),

      // Fonte e Tipografia Padrão
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: primaryBlue,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: primaryBlue,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: textDark,
        ),
        bodyMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: textMuted,
        ),
      ),

      // AppBars (Cabeçalhos Superiores)
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundLight,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryBlue),
        titleTextStyle: TextStyle(
          color: primaryBlue,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Campos de Entrada de Texto (Inputs e Selects)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textDark, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: statusDanger),
        ),
      ),

      // Botões Primários (Azul)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Botões Secundários e Especiais (Laranja - como "CADASTRA CATEGORIA")
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentOrange,
          side: const BorderSide(color: accentOrange, width: 1.5),
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Cards e Containers Elevation
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: borderLight),
        ),
      ),

      // Barra de Navegação Inferior (Início, Lista, Compras, Histórico, Perfil)
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceWhite,
        selectedItemColor: primaryBlue,
        unselectedItemColor: textMuted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  // Estilo auxiliar para Botões de Cor Laranja Sólida
  static ButtonStyle get orangeButtonStyle {
    return ElevatedButton.styleFrom(
      backgroundColor: accentOrange,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 48),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}