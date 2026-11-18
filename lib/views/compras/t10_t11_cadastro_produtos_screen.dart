import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Imports de controllers, modelos e tema visual
import '../../controllers/categorias_controller.dart';
import '../../controllers/produtos_controller.dart';
import '../../models/categoria_model.dart';
import '../../models/produto_model.dart';
import '../../nucleo/tema/app_theme.dart';
import 't12_t22_cadastro_categoria_screen.dart';

/// Provider reativo responsável por alimentar o DropdownButton de seleção de categorias (T10).
/// Delega ao `CategoriasController` a busca apenas das categorias ativas disponíveis ao usuário.
final categoriasDropdownProvider =
    FutureProvider.family<List<CategoriaModel>, int>((ref, usuarioId) async {
  return await ref
      .read(categoriasControllerProvider.notifier)
      .listarCategoriasAtivasParaSelecao(usuarioId);
});

/// ============================================================================
/// TELA T10 / T11 — CADASTRO E CONSULTA DE PRODUTOS
/// ============================================================================
/// Tela que unifica o Formulário de Inclusão/Edição de Produtos (T10) e a Tabela 
/// de Consulta com Ações de Edição, Exclusão e Atalho para Novo Cadastro (T11).
class CadastroProdutosScreen extends ConsumerStatefulWidget {
  /// Identificador do usuário logado no sistema
  final int usuarioId;

  /// Aba inicial a ser exibida (0 = CADASTRO, 1 = CONSULTA)
  final int abaInicial;

  const CadastroProdutosScreen({
    super.key,
    required this.usuarioId,
    this.abaInicial = 0,
  });

  @override
  ConsumerState<CadastroProdutosScreen> createState() => _CadastroProdutosScreenState();
}

class _CadastroProdutosScreenState extends ConsumerState<CadastroProdutosScreen> with SingleTickerProviderStateMixin {
  /// Controlador para alternar entre as abas de Cadastro e Consulta com transição suave
  late TabController _tabController;

  /// Controladores dos campos de entrada de texto do formulário
  late TextEditingController _codigoBarrasController;
  late TextEditingController _descricaoController;
  late TextEditingController _unidadeController;

  /// Controla a marcação do checkbox de produto de compra recorrente
  bool _isRecorrente = false;

  /// Controla a exibição da barra de progresso durante a requisição de EAN/GTIN na API pública
  bool _isCarregandoApi = false;

  /// Armazena o ID da categoria selecionada no Dropdown
  int? _categoriaSelecionadaId;

  /// Armazena o ID do produto em edição (null indica que é um novo registro)
  int? _produtoEmEdicaoId;

  @override
  void initState() {
    super.initState();
    // Inicializa o controller de abas respeitando a aba informada no parâmetro
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.abaInicial);

    _codigoBarrasController = TextEditingController();
    _descricaoController = TextEditingController();
    _unidadeController = TextEditingController(text: 'Un');
  }

  @override
  void dispose() {
    // Descarta os controladores para liberar memória do sistema
    _tabController.dispose();
    _codigoBarrasController.dispose();
    _descricaoController.dispose();
    _unidadeController.dispose();
    super.dispose();
  }

  /// Recarrega os dados reativos do catálogo de produtos e do dropdown de categorias
  void _recarregarDados() {
    ref.read(produtosControllerProvider.notifier).carregarProdutos();
    ref.invalidate(categoriasDropdownProvider(widget.usuarioId));
  }

  /// Reseta todos os campos e o estado do formulário para permitir um novo cadastro limpo
  void _limparFormulario() {
    _codigoBarrasController.clear();
    _descricaoController.clear();
    _unidadeController.text = 'Un';
    setState(() {
      _produtoEmEdicaoId = null;
      _isRecorrente = false;
      _categoriaSelecionadaId = null;
    });
  }

  /// Processa a busca por Código de Barras via ProdutosController (1º SQLite Local, 2º APIs externas)
  Future<void> _processarCodigoBarras(String codigoBruto) async {
    final controller = ref.read(produtosControllerProvider.notifier);
    final codigoLimpo = controller.limparCodigoBarras(codigoBruto);
    if (codigoLimpo.isEmpty) return;

    setState(() => _isCarregandoApi = true);

    try {
      final resultado = await controller.consultarCodigoBarrasCompleto(codigoLimpo);
      if (!mounted) return;

      if (resultado.produtoLocal != null) {
        final prod = resultado.produtoLocal!;
        _carregarProdutoParaEdicao(prod);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Produto local carregado para edição (ID: ${prod.idProduto}).'),
            backgroundColor: Colors.blue,
          ),
        );
      } else if (resultado.descricaoExterna != null && resultado.descricaoExterna!.isNotEmpty) {
        setState(() {
          _descricaoController.text = resultado.descricaoExterna!;
          if (resultado.unidadeExterna != null && resultado.unidadeExterna!.isNotEmpty) {
            _unidadeController.text = resultado.unidadeExterna!;
          }
          if (resultado.categoriaIdExterna != null) {
            _categoriaSelecionadaId = resultado.categoriaIdExterna;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto encontrado no catálogo global!'),
            backgroundColor: AppTheme.statusSuccess,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultado.aviso ?? 'Código não encontrado nas bases públicas. Digite a descrição.'),
            backgroundColor: resultado.aviso != null ? Colors.orange : Colors.grey,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCarregandoApi = false);
    }
  }

  /// Abre o modal de leitura do código de barras por câmera
  Future<void> _escanearCodigoBarrasCamera() async {
    bool jaLeu = false;

    final codigoLido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Escanear Código de Barras'),
            backgroundColor: AppTheme.primaryBlue,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: MobileScanner(
            onDetect: (capture) {
              if (jaLeu) return;
              for (final barcode in capture.barcodes) {
                if (barcode.rawValue != null) {
                  jaLeu = true;
                  Navigator.pop(ctx, barcode.rawValue);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );

    if (codigoLido != null && codigoLido.isNotEmpty) {
      final limpo = ref.read(produtosControllerProvider.notifier).limparCodigoBarras(codigoLido);
      setState(() {
        _codigoBarrasController.text = limpo;
      });
      await _processarCodigoBarras(limpo);
    }
  }

  /// Salva ou atualiza o registro no banco de dados via ProdutosController com travas de duplicidade
  Future<void> _salvarProdutoNoBanco() async {
    if (_categoriaSelecionadaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione uma categoria para o produto!'),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
      return;
    }

    final isNovo = _produtoEmEdicaoId == null;

    try {
      await ref.read(produtosControllerProvider.notifier).salvarProduto(
            idProduto: _produtoEmEdicaoId,
            categoriaId: _categoriaSelecionadaId!,
            codigoBarras: _codigoBarrasController.text,
            nomeProduto: _descricaoController.text,
            unidadeMedida: _unidadeController.text,
            flagRecorrente: _isRecorrente,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNovo
                ? 'Produto cadastrado com sucesso!'
                : 'Produto atualizado com sucesso!'),
            backgroundColor: AppTheme.statusSuccess,
          ),
        );
      }

      _limparFormulario();
      _recarregarDados();
      _tabController.animateTo(1);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.statusDanger,
          ),
        );
      }
    }
  }

  /// Carrega os dados do produto selecionado para edição na aba de formulário
  void _carregarProdutoParaEdicao(ProdutoModel prod) {
    setState(() {
      _produtoEmEdicaoId = prod.idProduto;
      _codigoBarrasController.text = prod.codigoBarras ?? '';
      _descricaoController.text = prod.nomeProduto;
      _unidadeController.text = prod.unidadeMedida;
      _isRecorrente = prod.flagProdutoRecorrente;
      _categoriaSelecionadaId = prod.categoriaId;
    });

    _tabController.animateTo(0);
  }

  /// Remove o produto do banco via ProdutosController (bloqueando se estiver vinculado a alguma compra)
  Future<void> _excluirProdutoDoBanco(ProdutoModel prod) async {
    if (prod.idProduto == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Produto'),
        content: Text('Deseja realmente excluir "${prod.nomeProduto}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusDanger),
            child: const Text('EXCLUIR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await ref.read(produtosControllerProvider.notifier).excluirProduto(prod.idProduto!);
      _recarregarDados();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produto excluído com sucesso!'),
          backgroundColor: AppTheme.statusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exclusão Não Permitida'),
          content: const Text(
            'Este produto já possui movimentação registrada em compras e não pode ser excluído.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: AppTheme.orangeButtonStyle,
              child: const Text('ENTENDI', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  /// Abre a tela de cadastro de categorias
  void _abrirCadastroCategoriaT12() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastroCategoriaScreen(usuarioId: widget.usuarioId),
      ),
    ).then((_) => _recarregarDados());
  }

  @override
  Widget build(BuildContext context) {
    final asyncProdutos = ref.watch(produtosControllerProvider);
    final asyncCategorias = ref.watch(categoriasDropdownProvider(widget.usuarioId));

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: const Text(
          'Cadastro de Produto',
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
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(text: 'CADASTRO'),
                Tab(text: 'CONSULTA'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ABA 1: Formulário de Inclusão / Edição (T10)
          asyncCategorias.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Erro ao carregar categorias: $err')),
            data: (listaCategorias) => _buildAbaCadastroT10(listaCategorias),
          ),
          // ABA 2: Tabela de Consulta de Registros com Botão Flutuante (T11)
          asyncProdutos.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Erro ao carregar produtos: $err')),
            data: (listaProdutos) => _buildAbaConsultaT11(listaProdutos),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textMuted,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) {
          if (index == 0) {
            Navigator.pop(context);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Lista'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Compras'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Histórico'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }

  /// Constrói a interface da Aba CADASTRO (T10)
  Widget _buildAbaCadastroT10(List<CategoriaModel> categoriasDoBanco) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isCarregandoApi) ...[
            const LinearProgressIndicator(color: Colors.orange),
            const SizedBox(height: 8),
          ],

          const Text(
            'Código de barras (opcional)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codigoBarrasController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Digite ou escaneie [câmera]',
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (val) => _processarCodigoBarras(val),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _processarCodigoBarras(_codigoBarrasController.text),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.search, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _escanearCodigoBarrasCamera,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          const Text(
            'Descrição Item',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _descricaoController,
            decoration: InputDecoration(
              hintText: 'Ex.: Açúcar Cristal',
              fillColor: Colors.white,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Unidade:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _unidadeController,
                      decoration: InputDecoration(
                        hintText: 'Ex: Un ou Kg',
                        fillColor: Colors.white,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Checkbox(
                      value: _isRecorrente,
                      activeColor: AppTheme.primaryBlue,
                      onChanged: (val) {
                        setState(() {
                          _isRecorrente = val ?? false;
                        });
                      },
                    ),
                    const Expanded(
                      child: Text(
                        'Prod. Recorrente',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          const Text(
            'Categoria:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            key: ValueKey('cat-$_produtoEmEdicaoId-$_categoriaSelecionadaId'),
            initialValue: categoriasDoBanco.any((c) => c.idCategoria == _categoriaSelecionadaId)
                ? _categoriaSelecionadaId
                : null,
            hint: const Text('Selecione a categoria'),
            decoration: InputDecoration(
              fillColor: Colors.white,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: categoriasDoBanco.map((cat) {
              return DropdownMenuItem<int>(
                value: cat.idCategoria,
                child: Text(cat.nomeCategoria),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _categoriaSelecionadaId = val;
              });
            },
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _salvarProdutoNoBanco,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _produtoEmEdicaoId == null ? 'SALVAR PRODUTO' : 'ATUALIZAR PRODUTO',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _abrirCadastroCategoriaT12,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'CADASTRA CATEGORIA',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói a interface da Aba CONSULTA (T11) com a tabela de produtos e botão flutuante redondo
  Widget _buildAbaConsultaT11(List<ProdutoModel> produtosList) {
    return Column(
      children: [
        const SizedBox(height: 16),
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
                // CABEÇALHO DA TABELA
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
                      SizedBox(width: 45, child: Text('ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      Expanded(flex: 4, child: Text('DESCRIÇÃO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      SizedBox(width: 35, child: Text('UN', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      SizedBox(width: 40, child: Text('RECOR.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      SizedBox(width: 70, child: Text('AÇÕES', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // LINHAS DA TABELA
                Expanded(
                  child: produtosList.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum produto cadastrado no banco.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: produtosList.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final prod = produtosList[index];
                            final idProdStr = (prod.idProduto ?? 0).toString().padLeft(5, '0');
                            final isRecorrente = prod.flagProdutoRecorrente;

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 45,
                                    child: Text(
                                      idProdStr,
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prod.nomeProduto,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                        Text(
                                          prod.categoria?.nomeCategoria ?? 'Sem categoria',
                                          style: const TextStyle(fontSize: 10, color: AppTheme.primaryBlue),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 35,
                                    child: Text(
                                      prod.unidadeMedida,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Icon(
                                      isRecorrente ? Icons.check_circle : Icons.cancel_outlined,
                                      color: isRecorrente ? AppTheme.statusSuccess : Colors.grey.shade400,
                                      size: 18,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Ação de Exclusão
                                        InkWell(
                                          onTap: () => _excluirProdutoDoBanco(prod),
                                          child: const Icon(Icons.close, color: AppTheme.statusDanger, size: 18),
                                        ),
                                        const SizedBox(width: 8),
                                        // Ação de Edição
                                        InkWell(
                                          onTap: () => _carregarProdutoParaEdicao(prod),
                                          child: const Icon(Icons.edit, color: AppTheme.primaryBlue, size: 18),
                                        ),
                                      ],
                                    ),
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

        // BOTÃO FLUTUANTE LARANJA DE ADICIONAR NOVO PRODUTO (+)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () {
                _limparFormulario(); // Limpa os campos para um novo produto
                _tabController.animateTo(0); // Anima suavemente para a aba de Cadastro
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(30),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
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
      ],
    );
  }
}