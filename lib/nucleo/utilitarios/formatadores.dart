import 'package:intl/intl.dart';

/// ============================================================================
/// UTILITÁRIO DE FORMATAÇÃO DE DADOS (FORMATTERS)
/// ============================================================================
/// Classe Utilitária responsável pela padronização visual da exibição de
/// números, quantidades e valores monetários para o padrão brasileiro (pt_BR).
class Formatters {
  /// Formata quantidades numéricas removendo casas decimais desnecessárias
  /// para números inteiros ou exibindo frações dinâmicas (ex: `3` ou `3,5`).
  ///
  /// Utiliza a notação pt_BR com separador de milhar por ponto e decimal por vírgula.
  static String fmtQtd(double qtd) {
    final formatter = NumberFormat('#,##0.###', 'pt_BR');
    return formatter.format(qtd);
  }

  /// Formata valores numéricos para a representação monetária oficial brasileira (Real).
  ///
  /// Converte o valor numérico em texto formatado com o símbolo `R$` e duas casas decimais
  /// de precisão (ex: `1250.5` torna-se `R$ 1.250,50`).
  static String fmtMoeda(double valor) {
    final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return formatter.format(valor);
  }
}