import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'nucleo/tema/app_theme.dart';
import 'views/autenticacao/t01_login_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AgiListaApp(),
    ),
  );
}

class AgiListaApp extends StatelessWidget {
  const AgiListaApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgiLista',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      
      // CONFIGURAÇÃO DE LOCALIZAÇÃO (PT-BR)
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      
      home: const LoginScreen(),
    );
  }
}