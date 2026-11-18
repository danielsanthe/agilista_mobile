// ============================================================================
// CONSTANTES DE STATUS DO SISTEMA
// ============================================================================
// Este arquivo centraliza todas as constantes de texto utilizadas para
// controlar os estados de listas, itens de compra e registros gerais no banco.

/// Define os status possíveis para o ciclo de vida de uma Lista de Compras.
abstract class StatusLista {
  /// Lista recém-criada, em fase de planejamento e inclusão de itens.
  static const String planejada = 'Planejada';

  /// Lista com compra iniciada na aba "Minha Compra" (itens sendo adicionados ao carrinho).
  static const String emAndamento = 'Em Andamento';

  /// Compra finalizada e salva no histórico do usuário.
  static const String concluida = 'Concluída';
}

/// Define os status operacionais de um Item individual dentro da Lista de Compras.
abstract class StatusItem {
  /// Item que faz parte do planejamento, mas ainda não foi inserido no carrinho.
  static const String pendente = 'Pendente';

  /// Item cujos detalhes (preço e quantidade) foram informados e inseridos no carrinho.
  static const String comprado = 'Comprado';

  /// Item adicionado durante a compra que não constava na lista planejada original (Fora da Lista).
  static const String compradoFL = 'Comprado FL';
}

/// Define o status de visibilidade ou ativação geral de registros (ex: Usuários ou Produtos).
abstract class StatusGeral {
  /// Registro ativo e visível para uso no sistema.
  static const String ativo = 'Ativo';

  /// Registro desativado ou oculto para novas operações.
  static const String inativo = 'Inativo';
}