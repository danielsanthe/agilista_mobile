import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Imports globais do app (Tema e Utilitários de Formatação)
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';

// Imports de modelos
import '../../models/item_lista_model.dart';
import '../../models/lista_model.dart';

// Imports de visões e diálogos para navegação
import '../compras/t07_iniciar_compra_dialog.dart';
import '../compras/t08_t13_minha_compra_screen.dart';
import 't04_criar_editar_lista_screen.dart';

// Imports da camada de controle e repositório de dados
import '../../controllers/listas_controller.dart';
import '../../repositories/listas_repository.dart';

/// ============================================================================
/// TELA T05 / T06 — MINHAS LISTAS (PLANEJADAS E CONCLUÍDAS)
/// ============================================================================
/// Exibe as listas de compras separadas em duas abas:
/// - ABA 1 (T05): Listas Planejadas / Em Andamento
/// - ABA 2 (T06): Histórico de Listas Concluídas (permite replicar e ver detalhes)
class MinhasListasScreen extends ConsumerStatefulWidget {
  /// Identificador do usuário logado necessário para buscar as listas no banco
  final int usuarioId;

  const MinhasListasScreen({
    super.key,
    required this.usuarioId,
  });

  @override
  ConsumerState<MinhasListasScreen> createState() => _MinhasListasScreenState();
}

class _MinhasListasScreenState extends ConsumerState<MinhasListasScreen> with SingleTickerProviderStateMixin {
  /// Controlador para alternar entre as abas 'PLANEJADAS' e 'CONCLUÍDAS'
  late TabController _tabController;

  /// Armazena o ID da lista concluída selecionada pelo usuário na segunda aba
  int? _idListaConcluidaSelecionada;

  @override
  void initState() {
    super.initState();
    // Inicializa o TabController para gerenciar 2 abas com animação sincronizada
    _tabController = TabController(length: 2, vsync: this);

    // Carrega as listas diretamente do SQLite local (sincronizar: false),
    // reservando chamadas de rede apenas para ações explícitas de confirmação
    Future.microtask(() {
      ref.read(listsControllerProvider.notifier).carregarListas(
            widget.usuarioId,
            sincronizar: false,
          );
    });
  }

  @override
  void dispose() {
    // Descarta o controller para evitar vazamentos de memória (memory leaks)
    _tabController.dispose();
    super.dispose();
  }

  /// Navega para a tela de criação de uma nova lista de compras
  void _abrirCriarLista() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEditListScreen(usuarioId: widget.usuarioId),
      ),
    );
  }

  /// Navega para a tela de edição de uma lista planejada já existente
  void _abrirEditarLista(ListaModel lista) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEditListScreen(
          usuarioId: widget.usuarioId,
          listaParaEditar: lista,
        ),
      ),
    );
  }

  /// Exibe confirmação e exclui uma lista planejada (dispara sincronização da exclusão)
  void _confirmarExcluirLista(ListaModel lista) {
    if (lista.idLista == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Lista'),
        content: Text('Deseja realmente excluir a lista "${lista.nomeLista}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);

              await ref.read(listsControllerProvider.notifier).deletarLista(
                    lista.idLista!,
                    widget.usuarioId,
                  );

              nav.pop();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Lista excluída com sucesso!'),
                  backgroundColor: AppTheme.statusSuccess,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusDanger),
            child: const Text('EXCLUIR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Exibe diálogo modal para inserção do nome da réplica
  /// e opção de incluir/ignorar os itens adicionados "fora da lista" na compra anterior.
  ///
  /// Enquanto a réplica está sendo gravada, o diálogo fica travado (botões desabilitados,
  /// sem fechar por toque fora ou botão voltar) para evitar réplicas duplicadas e para que
  /// o `pop` final feche sempre o diálogo, nunca a tela.
  void _exibirDialogoReplicarLista(ListaModel lista) {
    final nomeController = TextEditingController(text: '${lista.nomeLista} (Cópia)');
    bool incluirForaDaLista = false;
    bool replicando = false;
    String? erroNome;
    String? erroGeral;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return PopScope(
            canPop: !replicando,
            child: AlertDialog(
              title: const Text('Replicar Lista'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Uma nova lista planejada será criada com todos os itens redefinidos para nova compra.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  // Campo de texto para redefinir o nome da nova lista
                  TextField(
                    controller: nomeController,
                    enabled: !replicando,
                    decoration: InputDecoration(
                      labelText: 'Nome da Nova Lista',
                      errorText: erroNome,
                    ),
                    onChanged: (_) {
                      if (erroNome != null) {
                        setDialogState(() => erroNome = null);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // Opção para incluir ou ignorar produtos cadastrados na hora da compra
                  Row(
                    children: [
                      Checkbox(
                        value: incluirForaDaLista,
                        activeColor: AppTheme.primaryBlue,
                        onChanged: replicando
                            ? null
                            : (val) {
                                setDialogState(() {
                                  incluirForaDaLista = val ?? false;
                                });
                              },
                      ),
                      const Expanded(
                        child: Text(
                          'Copiar itens adicionados "fora da lista"?',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  if (erroGeral != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      erroGeral!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.statusDanger),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: replicando ? null : () => Navigator.pop(ctx),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: replicando
                      ? null
                      : () async {
                          final novoNome = nomeController.text.trim();

                          if (novoNome.isEmpty) {
                            setDialogState(() => erroNome = 'Informe o nome da nova lista.');
                            return;
                          }
                          if (lista.idLista == null) return;

                          // Captura antes do await para não usar o context depois do gap assíncrono
                          final nav = Navigator.of(ctx);
                          final messenger = ScaffoldMessenger.of(this.context);

                          setDialogState(() {
                            replicando = true;
                            erroGeral = null;
                          });

                          final sucesso = await ref.read(listsControllerProvider.notifier).replicarLista(
                                listaOriginal: lista,
                                novoNome: novoNome,
                                usuarioId: widget.usuarioId,
                                incluirForaDaLista: incluirForaDaLista,
                              );

                          if (!sucesso) {
                            // Mantém o diálogo aberto para o usuário tentar de novo
                            setDialogState(() {
                              replicando = false;
                              erroGeral = 'Não foi possível replicar a lista. Tente novamente.';
                            });
                            return;
                          }

                          nav.pop(); // fecha o diálogo

                          if (!mounted) return;
                          setState(() {
                            _idListaConcluidaSelecionada = null;
                          });
                          _tabController.animateTo(0); // mostra a nova lista na aba PLANEJADAS
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Lista replicada com sucesso!'),
                              backgroundColor: AppTheme.statusSuccess,
                            ),
                          );
                        },
                  style: AppTheme.orangeButtonStyle,
                  child: replicando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('REPLICAR', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stateListas = ref.watch(listsControllerProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: const Text(
          'Minhas Listas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'PLANEJADAS'),
            Tab(text: 'CONCLUÍDAS'),
          ],
        ),
      ),
      body: stateListas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erro ao carregar listas: $err')),
        data: (todasAsListas) {
          final planejadas = todasAsListas
              .where((l) => l.statusLista == 'Planejada' || l.statusLista == 'Em Andamento')
              .toList();
          final concluidas = todasAsListas
              .where((l) => l.statusLista == 'Concluída')
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              // ==================== ABA 1: PLANEJADAS (T05) ====================
              Stack(
                children: [
                  planejadas.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhuma lista planejada no momento.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: planejadas.length,
                          itemBuilder: (context, index) {
                            final lista = planejadas[index];
                            return _buildCardListaPlanejada(lista);
                          },
                        ),
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: FloatingActionButton(
                      onPressed: _abrirCriarLista,
                      backgroundColor: Colors.orange,
                      child: const Icon(Icons.add, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),

              // ==================== ABA 2: CONCLUÍDAS (T06) ====================
              Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        concluidas.isEmpty
                            ? const Center(
                                child: Text(
                                  'Nenhuma lista concluída no histórico.',
                                  style: TextStyle(color: AppTheme.textMuted),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: concluidas.length,
                                itemBuilder: (context, index) {
                                  final lista = concluidas[index];
                                  return _buildCardListaConcluida(lista);
                                },
                              ),
                        Positioned(
                          right: 20,
                          bottom: 20,
                          child: FloatingActionButton(
                            onPressed: _abrirCriarLista,
                            backgroundColor: Colors.orange,
                            child: const Icon(Icons.add, color: Colors.white, size: 28),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _idListaConcluidaSelecionada == null
                            ? null
                            : () {
                                // Busca segura: se a lista selecionada não existir mais, não faz nada
                                final selecionadas = concluidas
                                    .where((l) => l.idLista == _idListaConcluidaSelecionada)
                                    .toList();
                                if (selecionadas.isEmpty) {
                                  setState(() => _idListaConcluidaSelecionada = null);
                                  return;
                                }
                                _exibirDialogoReplicarLista(selecionadas.first);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: _idListaConcluidaSelecionada == null ? Colors.grey : Colors.orange,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'REPLICAR LISTA',
                          style: TextStyle(
                            color: _idListaConcluidaSelecionada == null ? Colors.grey : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Constrói o card para listas com status 'Planejada' ou 'Em Andamento'
  Widget _buildCardListaPlanejada(ListaModel lista) {
    final emAndamento = lista.statusLista == 'Em Andamento';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    lista.nomeLista,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: emAndamento ? Colors.blue.shade100 : Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        lista.statusLista,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: emAndamento ? AppTheme.primaryBlue : Colors.amber.shade900,
                        ),
                      ),
                    ),
                    if (!emAndamento) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.statusDanger, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _confirmarExcluirLista(lista),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: emAndamento ? null : () => _abrirEditarLista(lista),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: emAndamento ? Colors.grey : AppTheme.primaryBlue,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'EDITAR LISTA',
                      style: TextStyle(
                        color: emAndamento ? Colors.grey : AppTheme.primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (emAndamento) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ShoppingScreen(lista: lista),
                          ),
                        );
                      } else {
                        IniciarCompraDialog.exibir(context, lista: lista, usuarioId: widget.usuarioId);
                      }
                    },
                    style: AppTheme.orangeButtonStyle,
                    child: Text(
                      emAndamento ? 'CONTINUAR' : 'INICIAR COMPRA',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói o card para listas com status 'Concluída'
  Widget _buildCardListaConcluida(ListaModel lista) {
    final estaSelecionada = _idListaConcluidaSelecionada == lista.idLista;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: estaSelecionada,
                  activeColor: AppTheme.primaryBlue,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _idListaConcluidaSelecionada = lista.idLista;
                      } else {
                        _idListaConcluidaSelecionada = null;
                      }
                    });
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lista.nomeLista,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (lista.nomeEstabelecimento != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Local: ${lista.nomeEstabelecimento}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Concluída',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            if (estaSelecionada && lista.idLista != null) ...[
              const SizedBox(height: 12),
              _buildItensTableConcluida(lista.idLista!),
            ],
          ],
        ),
      ),
    );
  }

  /// Tabela detalhada dos itens da lista concluída
  /// Inclui o cabeçalho descritivo em duas linhas para maior clareza visual
  Widget _buildItensTableConcluida(int listaId) {
    return FutureBuilder<List<ItemListaModel>>(
      future: ref.read(listsRepositoryProvider).listarItensDaLista(listaId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final itens = snapshot.data!;
        if (itens.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Nenhum item encontrado nesta lista.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // ===============================================================
              // CABEÇALHO DE 2 LINHAS
              // Linha 1: Descrição do Item
              // Linha 2: Qtd COMP / Qtd PLAN | Preço unit | Sub.total
              // ===============================================================
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300, width: 1.5),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LINHA 1 CABEÇALHO
                    Text(
                      'DESCRIÇÃO DO ITEM',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    SizedBox(height: 4),
                    // LINHA 2 CABEÇALHO
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            'Qtd COMP / Qtd PLAN',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Preço unit',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Sub.total',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // LISTAGEM DOS ITENS DETALHADOS
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: itens.length,
                separatorBuilder: (_, index) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final item = itens[index];

                  final String qtdPlanFmt = Formatters.fmtQtd(item.qtdPlanejada);
                  final String qtdCompFmt = Formatters.fmtQtd(item.qtdComprada);
                  final double subtotal = item.subtotalItem;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LINHA 1 DADOS: Descrição do Produto
                      Text(
                        item.nomeItemPlanejado,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // LINHA 2 DADOS: Valores organizados e alinhados com o cabeçalho
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              '$qtdCompFmt / $qtdPlanFmt',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              Formatters.fmtMoeda(item.precoUnitario),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              Formatters.fmtMoeda(subtotal),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}