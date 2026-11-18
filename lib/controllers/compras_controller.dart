import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item_lista_model.dart';
import '../nucleo/constantes/status_constants.dart';
import '../repositories/listas_repository.dart';
import 'listas_controller.dart';

/// ============================================================================
/// PROVIDER PRINCIPAL — COMPRAS CONTROLLER (T08 / T09 / T13 / T14 / T15 / T16)
/// ============================================================================
/// Provider global reativo responsável por orquestrar a compra em andamento:
/// - Listagem dos itens planejados, no carrinho e fora da lista.
/// - Cálculo de subtotal com regras promocionais de atacado (T15).
/// - Inclusão/baixa de itens planejados (T09) e itens extras (T14).
/// - Sincronização automática do total da compra com o `listsControllerProvider`.
final comprasControllerProvider =
    AsyncNotifierProvider<ComprasController, List<ItemListaModel>>(
  ComprasController.new,
);

class ComprasController extends AsyncNotifier<List<ItemListaModel>> {
  @override
  Future<List<ItemListaModel>> build() async {
    // Inicializa com lista vazia até que `carregarItensDaCompra(listaId)` seja acionado
    return [];
  }

  /// Carrega todos os itens vinculados à lista/compra ativa a partir do SQLite.
  Future<void> carregarItensDaCompra(int listaId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(listsRepositoryProvider);
      return await repository.listarItensDaLista(listaId);
    });
  }

  /// T15 — Calcula o subtotal do item aplicando a regra promocional de atacado:
  /// Se a promoção estiver ativa, a quantidade comprada atingir a quantidade mínima
  /// e houver preço promocional válido, aplica o preço promocional; caso contrário,
  /// aplica o preço unitário normal.
  double calcularSubtotal({
    required double quantidade,
    required double precoUnitario,
    required bool isPromocao,
    required double qtdMinimaPromocao,
    required double precoPromocional,
  }) {
    final precoAplicado =
        (isPromocao && quantidade >= qtdMinimaPromocao && precoPromocional > 0)
            ? precoPromocional
            : precoUnitario;
    return quantidade * precoAplicado;
  }

  /// T09 / T14 / T15 — Valida e registra um item no carrinho da compra em andamento.
  /// Preserva integralmente as regras de negócio:
  /// - Exige produto válido vinculado ao catálogo (`produtoId > 0`).
  /// - Exige quantidade comprada e preço unitário maiores que zero.
  /// - No fluxo T09 (item planejado): atualiza para `StatusItem.comprado` mantendo
  ///   `nomeItemPlanejado` intacto.
  /// - No fluxo T14 (item fora da lista): insere novo registro com `StatusItem.compradoFL`
  ///   e `flagForaDaLista = true`.
  /// - Recalcula o total da lista e atualiza silenciosamente a Home (`listsControllerProvider`).
  Future<void> registrarItemNoCarrinho({
    required int listaId,
    required int usuarioId,
    required int? produtoId,
    required String nomeProduto,
    ItemListaModel? itemPlanejado,
    required double qtdComprada,
    required double precoUnitario,
    required bool isPromocao,
    required double qtdMinimaPromocao,
    required double precoPromocional,
  }) async {
    // 1. Validação de vínculo com produto cadastrado no banco
    if (produtoId == null || produtoId <= 0) {
      throw Exception(
        'Selecione um produto cadastrado no banco de dados para adicionar ao carrinho!',
      );
    }

    // 2. Validação de quantidade comprada
    if (qtdComprada <= 0) {
      throw Exception(
        'A quantidade comprada é obrigatória e deve ser maior que zero!',
      );
    }

    // 3. Determinação e validação do preço unitário final (normal vs promocional)
    final precoFinalUnitario =
        (isPromocao && qtdComprada >= qtdMinimaPromocao && precoPromocional > 0)
            ? precoPromocional
            : precoUnitario;

    if (precoFinalUnitario <= 0) {
      throw Exception(
        'O preço unitário é obrigatório e deve ser maior que zero!',
      );
    }

    final repository = ref.read(listsRepositoryProvider);

    if (itemPlanejado != null) {
      // FLUXO T09: Atualiza o item planejado alterando o status para Comprado.
      // REGRA: Mantém `nomeItemPlanejado` intacto; o nome real vem do `produtoId`.
      final itemAtualizado = itemPlanejado.copyWith(
        produtoId: produtoId,
        qtdComprada: qtdComprada,
        precoUnitario: precoFinalUnitario,
        statusItem: StatusItem.comprado,
        flagPromocao: isPromocao,
        qtdMinimaPromocional: isPromocao ? qtdMinimaPromocao : null,
        precoPromocional: isPromocao ? precoPromocional : null,
      );
      await repository.atualizarItem(itemAtualizado);
    } else {
      // FLUXO T14: Insere um novo produto fora da lista diretamente no carrinho.
      final nomeItemExtra =
          nomeProduto.trim().isNotEmpty ? nomeProduto.trim() : 'Produto Extra';

      final novoItemExtra = ItemListaModel(
        listaId: listaId,
        produtoId: produtoId,
        nomeItemPlanejado: nomeItemExtra,
        qtdPlanejada: qtdComprada,
        qtdComprada: qtdComprada,
        precoUnitario: precoFinalUnitario,
        precoEstimado: precoFinalUnitario,
        statusItem: StatusItem.compradoFL,
        flagForaDaLista: true,
        flagPromocao: isPromocao,
        qtdMinimaPromocional: isPromocao ? qtdMinimaPromocao : null,
        precoPromocional: isPromocao ? precoPromocional : null,
      );
      await repository.adicionarItem(novoItemExtra);
    }

    // 4. Recarrega os itens da compra ativa e atualiza silenciosamente os totais na Home
    await carregarItensDaCompra(listaId);
    await ref
        .read(listsControllerProvider.notifier)
        .atualizarAposAcaoCarrinho(usuarioId);
  }

  /// Atualiza um item já presente no carrinho (quantidade, preço ou status)
  /// e sincroniza os totais da lista na Home.
  Future<void> atualizarItemNoCarrinho({
    required ItemListaModel item,
    required int usuarioId,
  }) async {
    final repository = ref.read(listsRepositoryProvider);
    await repository.atualizarItem(item);

    await carregarItensDaCompra(item.listaId);
    await ref
        .read(listsControllerProvider.notifier)
        .atualizarAposAcaoCarrinho(usuarioId);
  }

  /// Remove um item da compra em andamento (com registro offline de exclusão)
  /// e recalcula o total da lista.
  Future<void> removerItem({
    required int idItemLista,
    required int listaId,
    required int usuarioId,
  }) async {
    final repository = ref.read(listsRepositoryProvider);
    await repository.removerItem(idItemLista);

    await carregarItensDaCompra(listaId);
    await ref
        .read(listsControllerProvider.notifier)
        .atualizarAposAcaoCarrinho(usuarioId);
  }
}