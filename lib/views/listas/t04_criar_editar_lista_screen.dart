import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../models/item_lista_model.dart';
import '../../controllers/listas_controller.dart';
import '../../models/lista_model.dart';
import '../../repositories/listas_repository.dart';

/// ============================================================================
/// TELA T04 — CRIAR / EDITAR LISTA DE COMPRAS
/// ============================================================================
/// Permite ao usuário cadastrar uma nova lista planejada com orçamento e itens,
/// ou editar uma lista já existente com layout dinâmico e diálogo modal.
///
/// Fluxo Offline-First:
/// - Todas as manipulações de itens (adicionar, editar, remover) ocorrem em
///   memória enquanto o usuário monta a lista.
/// - Apenas ao confirmar em "SALVAR LISTA" (e havendo ao menos 1 item), a lista
///   e seus itens são gravados no SQLite local e sincronizados com a API.
class CreateEditListScreen extends ConsumerStatefulWidget {
  /// Quando preenchido, abre a tela em modo de edição da lista informada;
  /// quando nulo, abre em modo de criação de uma nova lista planejada.
  final ListaModel? listaParaEditar;

  /// ID local do usuário autenticado proprietário da lista.
  final int usuarioId;

  const CreateEditListScreen({
    super.key,
    this.listaParaEditar,
    required this.usuarioId,
  });

  @override
  ConsumerState<CreateEditListScreen> createState() => _CreateEditListScreenState();
}

class _CreateEditListScreenState extends ConsumerState<CreateEditListScreen> {
  /// Chave global para validação do formulário de cabeçalho (nome e orçamento).
  final _formKey = GlobalKey<FormState>();

  /// Controlador do campo de texto do nome da lista de compras.
  final _nomeListaController = TextEditingController();

  /// Controlador do campo de texto do valor de orçamento planejado.
  final _orcamentoController = TextEditingController();

  /// Lista em memória dos itens planejados exibidos na tela.
  final List<ItemListaModel> _itensPlanejados = [];

  /// Indica se os itens de uma lista em edição estão sendo carregados do SQLite.
  bool _carregandoItens = false;

  /// Indica se o salvamento e sincronização da lista estão em andamento.
  bool _salvando = false;

  /// IDs de itens já gravados no banco que o usuário removeu da tela
  /// e que serão efetivamente excluídos ao clicar em "SALVAR LISTA".
  final List<int> _idsItensRemovidos = [];

  @override
  void initState() {
    super.initState();
    _inicializarDados();
  }

  /// Carrega os dados da lista existente e seus itens do SQLite local
  /// quando a tela é aberta em modo de edição.
  Future<void> _inicializarDados() async {
    if (widget.listaParaEditar != null) {
      final lista = widget.listaParaEditar!;
      _nomeListaController.text = lista.nomeLista;
      _orcamentoController.text = lista.valorOrcamento > 0
          ? lista.valorOrcamento.toStringAsFixed(2).replaceAll('.', ',')
          : '';

      if (lista.idLista != null) {
        setState(() => _carregandoItens = true);
        try {
          final repository = ref.read(listsRepositoryProvider);
          final itensDoBanco = await repository.listarItensDaLista(lista.idLista!);
          setState(() {
            _itensPlanejados.addAll(itensDoBanco);
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao carregar itens da lista: $e')),
            );
          }
        } finally {
          if (mounted) setState(() => _carregandoItens = false);
        }
      }
    }
  }

  @override
  void dispose() {
    // Libera os controladores de texto da memória ao destruir a tela
    _nomeListaController.dispose();
    _orcamentoController.dispose();
    super.dispose();
  }

  /// Converte o texto digitado no campo de orçamento (com vírgula ou ponto decimal)
  /// para [double] de forma segura, sem remover o separador decimal.
  double? _lerValor(String texto) {
    // Remove o prefixo monetário e eventuais espaços em branco
    final limpo = texto.replaceAll('R\$', '').replaceAll(' ', '').trim();
    if (limpo.isEmpty) return null;

    // Caso o texto contenha vírgula (padrão pt-BR, ex: "1.250,50" ou "100,00"),
    // remove os pontos de milhar e converte a vírgula decimal em ponto.
    if (limpo.contains(',')) {
      final normalizado = limpo.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(normalizado);
    }

    // Caso o usuário digite apenas ponto decimal no teclado numérico (ex: "100.00" ou "100.50"),
    // interpreta diretamente como separador decimal sem apagar o ponto.
    return double.tryParse(limpo);
  }

  /// Formata quantidades inteiras sem casas decimais (ex: "2") e fracionadas
  /// com até 3 casas decimais usando vírgula (ex: "0,5").
  String _formatarQuantidade(double qtd) {
    if (qtd % 1 == 0) {
      return qtd.toInt().toString();
    }
    return qtd.toStringAsFixed(3).replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '').replaceAll('.', ',');
  }

  /// Abre diálogo modal para cadastrar ou editar um item individual na lista.
  /// Inclui trava contra duplo clique rápido no botão de confirmação.
  void _exibirDialogoItem({ItemListaModel? itemParaEditar, int? indexParaEditar}) {
    // Remove o foco dos campos do cabeçalho ao abrir o modal do item
    FocusScope.of(context).unfocus();

    final nomeItemController = TextEditingController(
      text: itemParaEditar?.nomeItemPlanejado ?? '',
    );
    final qtdController = TextEditingController(
      text: itemParaEditar != null
          ? _formatarQuantidade(itemParaEditar.qtdPlanejada)
          : '1',
    );
    final precoEstimadoController = TextEditingController(
      text: (itemParaEditar != null && itemParaEditar.precoEstimado > 0)
          ? itemParaEditar.precoEstimado.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );

    final formItemKey = GlobalKey<FormState>();
    bool confirmandoItem = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            /// Incrementa ou decrementa a quantidade do item dentro dos limites permitidos.
            void alterarQuantidade(double delta) {
              final valorAtual = double.tryParse(qtdController.text.replaceAll(',', '.')) ?? 1.0;
              final novoValor = (valorAtual + delta).clamp(0.1, 999.0);
              qtdController.text = _formatarQuantidade(novoValor);
              setModalState(() {});
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                itemParaEditar == null ? 'Adicionar Item Planejado' : 'Editar Item',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Form(
                key: formItemKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Campo obrigatório com o nome/descrição do item planejado
                    TextFormField(
                      controller: nomeItemController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Item (*)',
                        hintText: 'Ex: Arroz 5kg',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Informe o nome do item.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Seletor numérico de quantidade com botões "-" e "+"
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Quantidade (*)',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => alterarQuantidade(-1),
                            icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primaryBlue, size: 28),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: qtdController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                              ),
                              onChanged: (_) => setModalState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Obrigatório.';
                                }
                                final qtdParsed = double.tryParse(val.replaceAll(',', '.'));
                                if (qtdParsed == null || qtdParsed <= 0) {
                                  return 'Inválido.';
                                }
                                return null;
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: () => alterarQuantidade(1),
                            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryBlue, size: 28),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Campo opcional de preço unitário estimado para o planejamento
                    TextFormField(
                      controller: precoEstimadoController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Preço Estimado (R\$) (Opcional)',
                        hintText: '0,00',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: confirmandoItem
                      ? null
                      : () {
                          if (formItemKey.currentState!.validate()) {
                            // Bloqueia reenvio por duplo clique rápido antes de fechar o diálogo
                            setModalState(() => confirmandoItem = true);

                            final nome = nomeItemController.text.trim();
                            final qtd = double.parse(qtdController.text.replaceAll(',', '.'));
                            final precoEstimado =
                                double.tryParse(precoEstimadoController.text.replaceAll(',', '.')) ?? 0.0;

                            setState(() {
                              if (indexParaEditar != null && itemParaEditar != null) {
                                // Atualiza o item existente na lista em memória
                                _itensPlanejados[indexParaEditar] = itemParaEditar.copyWith(
                                  nomeItemPlanejado: nome,
                                  qtdPlanejada: qtd,
                                  precoEstimado: precoEstimado,
                                );
                              } else {
                                // Inclui o novo item planejado na lista em memória
                                _itensPlanejados.add(
                                  ItemListaModel(
                                    listaId: widget.listaParaEditar?.idLista ?? 0,
                                    nomeItemPlanejado: nome,
                                    qtdPlanejada: qtd,
                                    precoEstimado: precoEstimado,
                                  ),
                                );
                              }
                            });

                            Navigator.pop(ctx);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                  ),
                  child: Text(
                    itemParaEditar == null ? 'ADICIONAR' : 'SALVAR',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Remove o item da tela e registra seu ID para remoção no SQLite ao salvar.
  /// Alerta o usuário caso a lista fique vazia após a remoção.
  void _removerItem(int index) {
    final id = _itensPlanejados[index].idItemLista;
    if (id != null && id != 0) {
      _idsItensRemovidos.add(id);
    }
    setState(() {
      _itensPlanejados.removeAt(index);
    });

    if (_itensPlanejados.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atenção: A lista precisa de pelo menos 1 item para ser salva!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Salva a lista inteira e seus itens com integridade relacional.
  /// REGRA DE NEGÓCIO: Impede salvar caso a lista esteja sem nenhum item planejado.
  Future<void> _salvarListaCompleta() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    // BLOQUEIO DE SEGURANÇA: Não permite salvar lista vazia
    if (_itensPlanejados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não é possível salvar uma lista sem itens! Adicione ao menos 1 item.'),
          backgroundColor: AppTheme.statusDanger,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _salvando = true);

    try {
      final repository = ref.read(listsRepositoryProvider);
      final nomeLista = _nomeListaController.text.trim();
      final orcamento = _lerValor(_orcamentoController.text) ?? 0.0;

      // 1. Cria ou atualiza a lista e obtém o ID real gravado
      final int idListaPersistida;
      if (widget.listaParaEditar == null) {
        final criada = await repository.criarLista(
          ListaModel(
            usuarioId: widget.usuarioId,
            nomeLista: nomeLista,
            valorOrcamento: orcamento,
            statusLista: 'Planejada',
            dataCriacao: DateTime.now(),
          ),
        );
        idListaPersistida = criada.idLista!;
      } else {
        idListaPersistida = widget.listaParaEditar!.idLista!;
        await repository.atualizarLista(
          widget.listaParaEditar!.copyWith(
            nomeLista: nomeLista,
            valorOrcamento: orcamento,
          ),
        );
      }

      // 2. Apaga do banco os itens removidos pelo usuário na interface
      for (final id in _idsItensRemovidos) {
        await repository.removerItem(id);
      }
      _idsItensRemovidos.clear();

      // 3. Adiciona itens novos e atualiza existentes
      for (final item in _itensPlanejados) {
        if (item.idItemLista == null || item.idItemLista == 0) {
          final itemComListaId = item.copyWith(listaId: idListaPersistida);
          await repository.adicionarItem(itemComListaId);
        } else {
          await repository.atualizarItem(item);
        }
      }

      // 4. Atualiza estado global do Riverpod e dispara a sincronização
      await ref.read(listsControllerProvider.notifier).carregarListas(widget.usuarioId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lista salva com sucesso!'),
            backgroundColor: AppTheme.statusSuccess,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar lista: $e'),
            backgroundColor: AppTheme.statusDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tituloTela = widget.listaParaEditar == null ? 'Criar Lista' : 'Editar Lista';

    return GestureDetector(
      // Fecha o teclado ao clicar em qualquer área vazia fora dos campos
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AppTheme.backgroundLight,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryBlue,
          title: Text(tituloTela, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // ==================== CABEÇALHO FIXO (Nome e Orçamento) ====================
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Nome da Lista',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textMuted),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nomeListaController,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'Compra do mês',
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return 'Informe o nome.';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Define Orçamento *',
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.textMuted),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _orcamentoController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    hintText: 'R\$ 300,00',
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (val) {
                                    final n = _lerValor(val ?? '');
                                    if (n == null || n <= 0) {
                                      return 'Informe um valor válido.';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ITENS PLANEJADOS (${_itensPlanejados.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Cabeçalho da grade de itens planejados
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 22, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted))),
                            Expanded(flex: 3, child: Text('ITEM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted))),
                            Expanded(flex: 2, child: Text('QTD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted), textAlign: TextAlign.center)),
                            Expanded(flex: 5, child: Text('PREÇO ESTIMADO', maxLines: 1, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.right)),
                            SizedBox(width: 28),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ==================== LISTA DE ITENS ====================
                Expanded(
                  child: _carregandoItens
                      ? const Center(child: CircularProgressIndicator())
                      : _itensPlanejados.isEmpty
                          ? SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24.0),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.format_list_bulleted, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Nenhum item adicionado.',
                                        style: TextStyle(color: AppTheme.textMuted),
                                      ),
                                      const Text(
                                        'Clique no botão "+" para incluir itens.',
                                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _itensPlanejados.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final item = _itensPlanejados[index];

                                return Card(
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: InkWell(
                                    onTap: () => _exibirDialogoItem(
                                      itemParaEditar: item,
                                      indexParaEditar: index,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 22,
                                            child: Text(
                                              '${index + 1}.',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: AppTheme.textMuted,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              item.nomeItemPlanejado,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              _formatarQuantidade(item.qtdPlanejada),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 5,
                                            child: Text(
                                              'R\$ ${item.precoEstimado.toStringAsFixed(2).replaceAll('.', ',')}',
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 28,
                                            child: IconButton(
                                              icon: const Icon(Icons.delete_outline, color: AppTheme.statusDanger, size: 20),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: () => _removerItem(index),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),

                // ==================== RODAPÉ FIXO (BOTÃO "+" E SALVAR LISTA) ====================
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // BOTÃO FLUTUANTE AZUL (+) DE INCLUSÃO DE ITEM
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: InkWell(
                            onTap: () => _exibirDialogoItem(),
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryBlue,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // BOTÃO SALVAR LISTA
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _salvando ? null : _salvarListaCompleta,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Colors.orange, width: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _salvando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                                )
                              : const Text(
                                  'SALVAR LISTA',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}