import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../controllers/listas_controller.dart';
import '../../models/item_lista_model.dart';
import '../../models/lista_model.dart';
import '../../nucleo/constantes/status_constants.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';
import '../../repositories/listas_repository.dart';

/// ============================================================================
/// TELA T16 — FINALIZAR COMPRA (RESUMO DA COMPRA)
/// ============================================================================
/// Apresenta o resumo consolidado com total gasto, saldo restante do orçamento,
/// quantidade de itens da lista, itens comprados e itens inseridos fora da lista.
///
/// Arquitetura Offline-First:
/// - Ao confirmar o encerramento, altera o status da lista para 'Concluída' no
///   SQLite local (`flag_sincronizado = 0`) e dispara `carregarListas`, que
///   envia em lote para a API FastAPI toda a execução da compra (itens comprados,
///   itens fora da lista, exclusões pendentes e encerramento da lista).
class FinalizarCompraScreen extends ConsumerStatefulWidget {
  /// Modelo da lista/compra em andamento.
  final ListaModel lista;

  /// Lista de todos os itens vinculados a esta compra.
  final List<ItemListaModel> itens;

  const FinalizarCompraScreen({
    super.key,
    required this.lista,
    required this.itens,
  });

  @override
  ConsumerState<FinalizarCompraScreen> createState() =>
      _FinalizarCompraScreenState();
}

class _FinalizarCompraScreenState extends ConsumerState<FinalizarCompraScreen> {
  /// Indica se a finalização da compra está em andamento, evitando duplo clique.
  bool _finalizando = false;

  /// Altera o status da lista para 'Concluída' no SQLite, dispara a
  /// sincronização em lote da compra via [ListsController] e retorna à Home.
  Future<void> _confirmarEFinalizarCompra() async {
    if (_finalizando) return;
    setState(() => _finalizando = true);

    try {
      final repository = ref.read(listsRepositoryProvider);

      // 1. Busca os totais atualizados diretamente do banco SQLite local
      final atual = await repository.buscarPorId(widget.lista.idLista!);

      // 2. Transiciona o status da lista para 'Concluída' usando a regra do modelo
      final listaFinalizada = (atual ?? widget.lista).finalizarCompra();

      // 3. Persiste o encerramento no banco SQLite (`flag_sincronizado = 0`)
      await repository.atualizarLista(listaFinalizada);

      // 4. Atualiza o estado global no Riverpod e dispara o envio completo
      //    da compra concluída para a API FastAPI
      await ref
          .read(listsControllerProvider.notifier)
          .carregarListas(widget.lista.usuarioId);

      if (mounted) {
        // Exibe notificação de confirmação ao usuário
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compra finalizada com sucesso!'),
            backgroundColor: AppTheme.statusSuccess,
            duration: Duration(seconds: 2),
          ),
        );

        // Limpa a pilha de navegação e retorna para a tela principal (Home)
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _finalizando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar compra: $e'),
            backgroundColor: AppTheme.statusDanger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // =========================================================================
    // CÁLCULO FINANCEIRO:
    // Filtra itens com status 'comprado' OU 'compradoFL' (Fora da Lista)
    // =========================================================================
    final itensCompradosList = widget.itens.where((i) {
      return i.statusItem == StatusItem.comprado ||
          i.statusItem == StatusItem.compradoFL ||
          i.statusItem == 'comprado' ||
          i.statusItem == 'compradoFL';
    }).toList();

    // Soma do valor real de todos os itens comprados (Lista + Fora da Lista)
    final totalGasto = itensCompradosList.fold<double>(
      0.0,
      (sum, i) => sum + i.subtotalItem,
    );

    final orcamento = widget.lista.valorOrcamento;
    final restante = orcamento - totalGasto;

    // Métricas das quantidades para exibição nos blocos resumidos
    final totalItensLista =
        widget.itens.where((i) => !i.flagForaDaLista).length;
    final totalComprados = itensCompradosList.length;
    final totalForaDaLista =
        widget.itens.where((i) => i.flagForaDaLista).length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: const Text(
          'Finalizar Compra',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ==================== ÍCONE DE CONFIRMAÇÃO ====================
            const Center(
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.statusSuccess,
                    size: 72,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Resumo da Compra',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.statusSuccess,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ==================== CARD 1: RESUMO FINANCEIRO ====================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumo financeiro',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  const Divider(height: 20),
                  _buildLinhaResumo(
                    'Total da compra',
                    Formatters.fmtMoeda(totalGasto),
                    AppTheme.statusSuccess,
                  ),
                  const SizedBox(height: 10),
                  _buildLinhaResumo(
                    'Orçamento',
                    Formatters.fmtMoeda(orcamento),
                    AppTheme.statusSuccess,
                  ),
                  const SizedBox(height: 10),
                  _buildLinhaResumo(
                    'Restante',
                    Formatters.fmtMoeda(restante),
                    restante < 0
                        ? AppTheme.statusDanger
                        : AppTheme.statusSuccess,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ==================== CARD 2: RESUMO DE QUANTIDADES ====================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildBlocoMetrica(
                    'Itens da lista',
                    '$totalItensLista',
                    AppTheme.primaryBlue,
                  ),
                  Container(height: 40, width: 1, color: Colors.grey.shade300),
                  _buildBlocoMetrica(
                    'Comprados',
                    '$totalComprados',
                    AppTheme.primaryBlue,
                  ),
                  Container(height: 40, width: 1, color: Colors.grey.shade300),
                  _buildBlocoMetrica(
                    'Fora da lista',
                    '$totalForaDaLista',
                    AppTheme.statusDanger,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ==================== BOTÃO FINALIZAR COMPRA ====================
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _finalizando ? null : _confirmarEFinalizarCompra,
                style: AppTheme.orangeButtonStyle,
                child: _finalizando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'FINALIZAR COMPRA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // ==================== BOTÃO CANCELAR ====================
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _finalizando
                    ? null
                    : () => Navigator.pop(context), // Retorna ao carrinho (T13)
                style: OutlinedButton.styleFrom(
                  side:
                      const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'CANCELAR',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // Barra de navegação inferior padronizada
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textMuted,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Lista',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_bag_outlined),
            label: 'Compras',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Histórico',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  /// Método auxiliar de formatação para as linhas de valores do resumo financeiro.
  Widget _buildLinhaResumo(String rotulo, String valor, Color corValor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          rotulo,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textDark,
          ),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: corValor,
          ),
        ),
      ],
    );
  }

  /// Método auxiliar para renderização das métricas verticais de quantidades.
  Widget _buildBlocoMetrica(String rotulo, String valor, Color corValor) {
    return Column(
      children: [
        Text(
          rotulo,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          valor,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: corValor,
          ),
        ),
      ],
    );
  }
}