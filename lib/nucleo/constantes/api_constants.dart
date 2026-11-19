/// ============================================================================
/// CONSTANTES DE CONFIGURAÇÃO DA API RESTFUL (AGILISTA-API)
/// ============================================================================
/// Centraliza a URL base do backend FastAPI em produção (Render) e os tempos
/// limite (timeouts) das requisições HTTP do aplicativo Flutter.
///
/// Mantém compatibilidade com injeção em tempo de compilação via `--dart-define`:
/// - Produção (padrão): `https://agilista-api.onrender.com`
/// - Desenvolvimento local: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000`
class ApiConstants {
  /// Construtor privado para impedir a instanciação desta classe utilitária.
  ApiConstants._();

  /// URL base da API RESTful do AgiLista (sem barra final para evitar `//` nas rotas).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://agilista-api.onrender.com',
  );

  /// Tempo limite padrão das requisições HTTP (65 segundos).
  /// Valor dimensionado para absorver o tempo de despertar (cold start de ~50s)
  /// da instância gratuita no Render após períodos de inatividade.
  static const Duration timeoutPadrao = Duration(seconds: 65);
}