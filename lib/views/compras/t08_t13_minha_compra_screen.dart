import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Imports de constantes e utilitários da aplicação
import '../../nucleo/constantes/status_constants.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';

// Imports de modelos de dados
import '../../models/item_lista_model.dart';
import '../../models/lista_model.dart';

// Imports de controllers
import '../../controllers/compras_controller.dart';
import '../../controllers/listas_controller.dart';

// Imports das telas relacionadas ao fluxo de compra
import 't09_t14_t15_adicionar_produto_screen.dart';
import 't16_finalizar_compra_screen.dart';

/// ============================================================================
/// TELA T08 / T13 — MINHA COMPRA (LISTA DE COMPRAS E CARRINHO)
/// ============================================================================
/// Gerencia o processo em tempo real de realização de uma compra em andamento.
///
/// Arquitetura Offline-First:
/// - Todas as interações de marcação, inclusão de itens fora da lista e
///   remoção do carrinho operam 100% no SQLite local via [ComprasController]
///   e atualizam o painel financeiro da Home via [ListsController] sem
///   disparar requisições HTTP intermediárias.
/// - A sincronização completa da compra com o servidor ocorre apenas ao
///   concluir o fechamento na tela [FinalizarCompraScreen] (T16).
///
/// Divisão em 2 abas sincronizadas:
/// - ABA 1 (LISTA - T08): Exibe os itens planejados e o status individual.
/// - ABA 2 (CARRINHO - T13): Exibe os itens já adquiridos, valores e opção de remoção.
class ShoppingScreen extends ConsumerStatefulWidget {
  /// Instância da lista de compras que está em andamento no momento.
  final ListaModel lista;

  const ShoppingScreen({
    super.key,
    required this.lista,
  });

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen>
    with SingleTickerProviderStateMixin {
  /// Controlador para alternância suave entre as abas 'LISTA' e 'CARRINHO'.
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Inicializa o TabController com 2 abas e animação vsync
    _tabController = TabController(length: 2, vsync: this);

    // Carrega os itens da compra ativa a partir do SQLite via ComprasController
    Future.microtask(() {
      if (widget.lista.idLista != null) {
        ref
            .read(comprasControllerProvider.notifier)
            .carregarItensDaCompra(widget.lista.idLista!);
      }
    });
  }

  @override
  void dispose() {
    // Libera os recursos do TabController para prevenir vazamento de memória
    _tabController.dispose();
    super.dispose();
  }

  /// Recarrega os itens locais no [ComprasController] e notifica o
  /// [ListsController] para atualizar os totais da Home sem disparar rede.
  Future<void> _recarregarItens() async {
    await ref
        .read(comprasControllerProvider.notifier)
        .carregarItensDaCompra(widget.lista.idLista!);

    // Atualiza o saldo e o total gasto exibidos na Home em tempo real
    await ref
        .read(listsControllerProvider.notifier)
        .atualizarAposAcaoCarrinho(widget.lista.usuarioId);
  }

  /// Abre a tela modal (T09) para informar quantidade comprada e preço unitário
  /// de um item planejado pendente.
  Future<void> _abrirAdicionarProdutoT09(ItemListaModel item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdicionarProdutoScreen(
          listaId: widget.lista.idLista!,
          usuarioId: widget.lista.usuarioId,
          itemPlanejado: item,
        ),
      ),
    );
    // Atualiza os dados na tela e no painel principal ao retornar da inserção
    await _recarregarItens();
  }

  /// Abre a tela modal (T14) para adicionar um produto extra que não constava
  /// no planejamento original ("Fora da Lista").
  Future<void> _abrirProdutoForaDaListaT14() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdicionarProdutoScreen(
          listaId: widget.lista.idLista!,
          usuarioId: widget.lista.usuarioId,
          itemPlanejado: null, // null indica criação de produto fora da lista
        ),
      ),
    );
    await _recarregarItens();
  }

  /// Remove um item do carrinho seguindo as regras de negócio locais:
  /// - Se for um item inserido "fora da lista" (`flagForaDaLista == true`),
  ///   é excluído do SQLite (e enfileirado em `exclusoes_pendentes` caso já tenha `servidor_id`).
  /// - Se for um item do planejamento original, retorna ao status 'Pendente'
  ///   zerando quantidade comprada e preço unitário.
  Future<void> _removerItemDoCarrinho(ItemListaModel item) async {
    final controller = ref.read(comprasControllerProvider.notifier);

    if (item.flagForaDaLista == true) {
      await controller.removerItem(
        idItemLista: item.idItemLista!,
        listaId: widget.lista.idLista!,
        usuarioId: widget.lista.usuarioId,
      );
    } else {
      final itemPendente = item.copyWith(
        statusItem: StatusItem.pendente,
        qtdComprada: 0.0,
        precoUnitario: 0.0,
      );
      await controller.atualizarItemNoCarrinho(
        item: itemPendente,
        usuarioId: widget.lista.usuarioId,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${item.nomeItemPlanejado}" foi retornado para a Lista como Pendente.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Navega para a tela de encerramento da compra (T16), onde ocorre a
  /// finalização local e a sincronização completa da compra com o servidor.
  Future<void> _navegarParaFinalizarCompraT16(
    List<ItemListaModel> todosOsItens,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FinalizarCompraScreen(
          lista: widget.lista,
          itens: todosOsItens,
        ),
      ),
    );
    await _recarregarItens();
  }

  @override
  Widget build(BuildContext context) {
    // Observa o estado reativo dos itens da compra ativa no Riverpod
    final asyncItens = ref.watch(comprasControllerProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: const Text(
          'Minha Compra',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppTheme.primaryBlue,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.orange,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: [
                const Tab(text: 'LISTA'),
                // Atualiza dinamicamente o contador entre parênteses da aba CARRINHO
                asyncItens.maybeWhen(
                  data: (itens) {
                    final qtdCarrinho = itens
                        .where(
                          (i) =>
                              i.statusItem == StatusItem.comprado ||
                              i.statusItem == StatusItem.compradoFL,
                        )
                        .length;
                    return Tab(text: 'CARRINHO ($qtdCarrinho)');
                  },
                  orElse: () => const Tab(text: 'CARRINHO'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: asyncItens.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erro ao carregar itens: $err')),
        data: (itens) {
          // Filtra apenas os itens com status de compra realizada
          final itensCarrinho = itens
              .where(
                (i) =>
                    i.statusItem == StatusItem.comprado ||
                    i.statusItem == StatusItem.compradoFL,
              )
              .toList();

          // Cálculos financeiros em tempo real (orçamento, gasto atual e saldo restante)
          final totalGasto = itensCarrinho.fold<double>(
            0.0,
            (sum, i) => sum + i.subtotalItem,
          );
          final orcamento = widget.lista.valorOrcamento;
          final restante = orcamento - totalGasto;

          return Column(
            children: [
              // ==================== PAINEL SUPERIOR FINANCEIRO ====================
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryBlue, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'ORÇAMENTO: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            Formatters.fmtMoeda(orcamento),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                          'Gasto: ${Formatters.fmtMoeda(totalGasto)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                        Container(height: 16, width: 1, color: Colors.grey),
                        Text(
                          'Restante: ${Formatters.fmtMoeda(restante)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: restante < 0
                                ? AppTheme.statusDanger
                                : AppTheme.statusSuccess,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ==================== CONTEÚDO DAS ABAS ====================
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAbaListaT08(itens),
                    _buildAbaCarrinhoT13(itensCarrinho, itens),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ABA 1 — LISTA (T08): Apresenta o planejamento com o status individual de cada item.
  Widget _buildAbaListaT08(List<ItemListaModel> todosOsItens) {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                // Cabeçalho da grade de acompanhamento dos itens
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          'SEL.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          'ITEM',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'STATUS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'QTD_PLANEJ',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Lista estendida dos itens cadastrados (planejados e fora da lista)
                Expanded(
                  child: todosOsItens.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum item na lista.',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: todosOsItens.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = todosOsItens[index];
                            final isComprado =
                                item.statusItem == StatusItem.comprado ||
                                item.statusItem == StatusItem.compradoFL;

                            final String textoStatus =
                                (isComprado && item.flagForaDaLista == true)
                                    ? StatusItem.compradoFL
                                    : item.statusItem;

                            return InkWell(
                              onTap: isComprado
                                  ? null
                                  : () => _abrirAdicionarProdutoT09(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Icon(
                                        isComprado
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        color: isComprado
                                            ? AppTheme.statusSuccess
                                            : Colors.grey.shade400,
                                        size: 20,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        item.nomeItemPlanejado,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: isComprado
                                              ? Colors.grey
                                              : AppTheme.textDark,
                                          decoration: isComprado
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        textoStatus,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isComprado
                                              ? AppTheme.statusSuccess
                                              : Colors.amber,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        Formatters.fmtQtd(item.qtdPlanejada),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isComprado
                                              ? Colors.grey
                                              : AppTheme.textDark,
                                          decoration: isComprado
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        // Botão para inclusão rápida de produto avulso ("Fora da Lista")
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _abrirProdutoForaDaListaT14,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                '+ PRODUTO FORA DA LISTA',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// ABA 2 — CARRINHO (T13): Detalhamento em 2 linhas por item com valores e remoção.
  Widget _buildAbaCarrinhoT13(
    List<ItemListaModel> itensCarrinho,
    List<ItemListaModel> todosOsItens,
  ) {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Expanded(
                  child: itensCarrinho.isEmpty
                      ? const Center(
                          child: Text(
                            'Seu carrinho está vazio.',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: itensCarrinho.length,
                          separatorBuilder: (_, _) => const Divider(height: 16),
                          itemBuilder: (context, index) {
                            final item = itensCarrinho[index];

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.nomeExibicaoCarrinho,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppTheme.textDark,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: AppTheme.statusDanger,
                                          size: 22,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () =>
                                            _removerItemDoCarrinho(item),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Qtd: ${Formatters.fmtQtd(item.qtdComprada)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'Unit: ${Formatters.fmtMoeda(item.precoUnitario)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                      Text(
                                        'Subtotal: ${Formatters.fmtMoeda(item.subtotalItem)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        // Botão principal de ação no rodapé para prosseguir à tela de fechamento (T16)
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _navegarParaFinalizarCompraT16(todosOsItens),
              style: AppTheme.orangeButtonStyle,
              child: const Text(
                'FINALIZAR COMPRA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}