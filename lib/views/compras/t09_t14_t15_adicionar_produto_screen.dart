import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../controllers/compras_controller.dart';
import '../../controllers/produtos_controller.dart';
import '../../models/item_lista_model.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';
import 't10_t11_cadastro_produtos_screen.dart';

/// ==================================================================================
/// TELA T09 / T14 / T15 — ADICIONAR PRODUTO (DA LISTA OU FORA DA LISTA COM PROMOÇÃO)
/// ==================================================================================
/// Gerencia a inclusão e atualização de itens no carrinho de compras:
/// - T09: Item planejado vindo da lista original (preserva o card superior e exibe
///   selo laranja 'PROMOÇÃO' quando a promoção está ativa).
/// - T14: Item fora da lista adicionado durante a compra (preserva 'ITEM FORA DA LISTA'
///   e exibe selo laranja 'PROMOÇÃO' quando a promoção está ativa).
/// - T15: Aplicação de regras promocionais (preço promocional e quantidade mínima).
/// - Cadastro Rápido Inline: Exibido apenas após o usuário escanear ou pesquisar
///   um código de barras ou descrição e o item não constar no cadastro local.
///
/// Arquitetura Offline-First:
/// - O cadastro rápido inline e a inserção no carrinho persistem os registros
///   exclusivamente no SQLite local (`flag_sincronizado = 0`), sem requisições
///   de rede durante a compra; o envio em lote ocorre apenas na tela T16.
class AdicionarProdutoScreen extends ConsumerStatefulWidget {
  /// Identificador local da lista de compras ativa.
  final int listaId;

  /// Identificador local do usuário logado.
  final int usuarioId;

  /// Dados do item planejado (nulo quando o fluxo for de item fora da lista).
  final ItemListaModel? itemPlanejado;

  const AdicionarProdutoScreen({
    super.key,
    required this.listaId,
    required this.usuarioId,
    this.itemPlanejado,
  });

  @override
  ConsumerState<AdicionarProdutoScreen> createState() =>
      _AdicionarProdutoScreenState();
}

class _AdicionarProdutoScreenState
    extends ConsumerState<AdicionarProdutoScreen> {
  // Controladores de texto para os campos do formulário
  late TextEditingController _codigoBarrasController;
  late TextEditingController _nomeNovoProdutoController;
  late TextEditingController _qtdCompradaController;
  late TextEditingController _precoController;
  late TextEditingController _precoPromocaoController;

  // Controladores de foco para controle preciso do teclado
  late FocusNode _nomeNovoProdutoFocusNode;
  late FocusNode _precoFocusNode;

  // Temporizador de debounce para aguardar o usuário terminar de digitar antes de pesquisar
  Timer? _debounceBusca;

  // Variáveis de estado da tela
  double _qtdComprada = 1.0;
  double _qtdMinimaPromocao = 6.0;
  bool _isPromocao = false;
  bool _produtoLocalizado = true;
  bool _encontradoNaBaseExterna = false;
  bool _isBuscandoProduto = false;
  bool _isSalvandoItem = false;

  /// Guarda a chave primária `id_produto` encontrada na tabela 'produtos' no SQLite.
  int? _produtoIdEncontrado;

  /// Armazena o nome oficial do produto encontrado ou planejado.
  String _nomeProdutoEncontrado = '';

  /// Valor total calculado (Quantidade x Preço unitário ou promocional).
  double _subtotal = 0.0;

  @override
  void initState() {
    super.initState();

    // Inicializa controladores auxiliares e focos
    _precoPromocaoController = TextEditingController(text: '0,00');
    _nomeNovoProdutoController = TextEditingController();
    _nomeNovoProdutoFocusNode = FocusNode();
    _precoFocusNode = FocusNode();

    // Preenche os valores iniciais caso seja um item planejado da lista (T09)
    // ou inicia zerado caso seja um item fora da lista (T14).
    // A busca no catálogo NÃO dispara automaticamente na abertura da tela:
    // aguarda o usuário escanear o código de barras ou digitar no campo de pesquisa.
    if (widget.itemPlanejado != null) {
      _qtdComprada = widget.itemPlanejado!.qtdPlanejada > 0
          ? widget.itemPlanejado!.qtdPlanejada
          : 1.0;
      _nomeProdutoEncontrado = widget.itemPlanejado!.nomeItemPlanejado;
      _produtoIdEncontrado = widget.itemPlanejado!.produtoId;
      _precoController = TextEditingController(
        text: widget.itemPlanejado!.precoUnitario > 0
            ? widget.itemPlanejado!.precoUnitario
                .toStringAsFixed(2)
                .replaceAll('.', ',')
            : (widget.itemPlanejado!.precoEstimado > 0
                ? widget.itemPlanejado!.precoEstimado
                    .toStringAsFixed(2)
                    .replaceAll('.', ',')
                : '0,00'),
      );
    } else {
      _qtdComprada = 1.0;
      _nomeProdutoEncontrado = '';
      _precoController = TextEditingController(text: '0,00');
    }

    // Formata a exibição da quantidade inicial (inteiro ou decimal com 3 casas)
    _qtdCompradaController = TextEditingController(
      text: _qtdComprada % 1 == 0
          ? _qtdComprada.toInt().toString()
          : _qtdComprada.toStringAsFixed(3).replaceAll('.', ','),
    );

    _codigoBarrasController = TextEditingController();

    // Registra listeners para recalcular o subtotal automaticamente ao alterar preços ou quantidade
    _precoController.addListener(_recalcularSubtotal);
    _precoPromocaoController.addListener(_recalcularSubtotal);
    _qtdCompradaController.addListener(_atualizarQtdPorTexto);

    _recalcularSubtotal();
  }

  @override
  void dispose() {
    // Cancela timers pendentes e libera todos os controladores e focos
    _debounceBusca?.cancel();
    _codigoBarrasController.dispose();
    _nomeNovoProdutoController.dispose();
    _nomeNovoProdutoFocusNode.dispose();
    _precoFocusNode.dispose();
    _qtdCompradaController.removeListener(_atualizarQtdPorTexto);
    _qtdCompradaController.dispose();
    _precoController.removeListener(_recalcularSubtotal);
    _precoController.dispose();
    _precoPromocaoController.removeListener(_recalcularSubtotal);
    _precoPromocaoController.dispose();
    super.dispose();
  }

  /// Seleciona todo o texto de um campo ao receber toque para agilizar a digitação.
  void _selecionarTextoTodo(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  /// Atualiza a variável numérica `_qtdComprada` sempre que o usuário digita no campo de quantidade.
  void _atualizarQtdPorTexto() {
    final texto = _qtdCompradaController.text.replaceAll(',', '.');
    final val = double.tryParse(texto);
    if (val != null && val >= 0) {
      _qtdComprada = val;
      _recalcularSubtotal();
    }
  }

  /// Recalcula o subtotal da linha considerando regra normal ou atacado/promoção.
  void _recalcularSubtotal() {
    final precoNormalTexto = _precoController.text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    final precoNormalVal = double.tryParse(precoNormalTexto) ?? 0.0;

    final precoPromoTexto = _precoPromocaoController.text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    final precoPromoVal = double.tryParse(precoPromoTexto) ?? 0.0;

    setState(() {
      _subtotal = ref.read(comprasControllerProvider.notifier).calcularSubtotal(
            quantidade: _qtdComprada,
            precoUnitario: precoNormalVal,
            isPromocao: _isPromocao,
            qtdMinimaPromocao: _qtdMinimaPromocao,
            precoPromocional: precoPromoVal,
          );
    });
  }

  /// Gerencia a digitação no campo de pesquisa com debounce de 600ms.
  /// Evita buscas a cada letra e garante que o foco nunca seja roubado enquanto o usuário digita.
  void _onChangedPesquisa(String val) {
    _debounceBusca?.cancel();

    // Se o usuário apagou toda a pesquisa, restaura o estado limpo da tela
    if (val.trim().isEmpty) {
      setState(() {
        _produtoLocalizado = true;
        _encontradoNaBaseExterna = false;
        _produtoIdEncontrado = widget.itemPlanejado?.produtoId;
        _nomeProdutoEncontrado = widget.itemPlanejado?.nomeItemPlanejado ?? '';
        _isBuscandoProduto = false;
      });
      return;
    }

    // Aguarda 600ms após a última tecla antes de consultar o banco/APIs
    _debounceBusca = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _buscarProdutoNoBanco(val, solicitarFocoSeNaoEncontrar: false);
      }
    });
  }

  /// Prepara o campo inline `Nome do Produto` quando o item não é localizado no catálogo local.
  /// Só solicita foco automático quando `solicitarFoco` for verdadeiro (ex.: leitura pela câmera),
  /// preservando a digitação livre quando o usuário estiver escrevendo no campo de pesquisa.
  void _prepararCampoCadastroInline({bool solicitarFoco = false}) {
    if (widget.itemPlanejado != null) {
      // Sugere o nome do item da lista planejada
      _nomeNovoProdutoController.text = widget.itemPlanejado!.nomeItemPlanejado;
    } else {
      _nomeNovoProdutoController.clear();
    }

    if (solicitarFoco) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _nomeNovoProdutoFocusNode.requestFocus();
          if (_nomeNovoProdutoController.text.isNotEmpty) {
            _selecionarTextoTodo(_nomeNovoProdutoController);
          }
        }
      });
    }
  }

  /// Consulta a existência do produto no catálogo local e nas bases externas:
  /// 1º Banco SQLite local do usuário
  /// 2º API Agilista + Bases Públicas (para códigos de barras numéricos)
  /// 3º Libera o campo inline na própria tela caso não conste no cadastro local.
  Future<void> _buscarProdutoNoBanco(
    String termoBusca, {
    bool solicitarFocoSeNaoEncontrar = false,
  }) async {
    final texto = termoBusca.trim();
    final produtosCtrl = ref.read(produtosControllerProvider.notifier);

    if (texto.isEmpty) {
      setState(() {
        _produtoLocalizado = true;
        _encontradoNaBaseExterna = false;
        _produtoIdEncontrado = widget.itemPlanejado?.produtoId;
        _nomeProdutoEncontrado = widget.itemPlanejado?.nomeItemPlanejado ?? '';
        _isBuscandoProduto = false;
      });
      return;
    }

    setState(() => _isBuscandoProduto = true);

    try {
      // Verifica se o termo informado é composto apenas por dígitos (EAN/GTIN)
      final apenasDigitos = produtosCtrl.limparCodigoBarras(texto);
      final isCodigoBarras = apenasDigitos.isNotEmpty && apenasDigitos == texto;

      if (isCodigoBarras) {
        // Consulta completa: 1º SQLite Local -> 2º API Agilista -> 3º Bases Públicas
        final resultado =
            await produtosCtrl.consultarCodigoBarrasCompleto(apenasDigitos);
        if (!mounted) return;

        if (resultado.produtoLocal != null) {
          // Produto já cadastrado no SQLite local do usuário
          final prod = resultado.produtoLocal!;
          setState(() {
            _produtoLocalizado = true;
            _encontradoNaBaseExterna = false;
            _produtoIdEncontrado = prod.idProduto;
            _nomeProdutoEncontrado = prod.nomeProduto;
          });
        } else if (resultado.descricaoExterna != null &&
            resultado.descricaoExterna!.isNotEmpty) {
          // Não estava no cadastro local, mas foi localizado na base pública ou API Agilista
          setState(() {
            _produtoLocalizado = false;
            _encontradoNaBaseExterna = true;
            _produtoIdEncontrado = null;
            _nomeProdutoEncontrado = '';
            _nomeNovoProdutoController.text = resultado.descricaoExterna!;
          });
        } else {
          // Não encontrado em nenhuma base local ou externa
          setState(() {
            _produtoLocalizado = false;
            _encontradoNaBaseExterna = false;
            _produtoIdEncontrado = null;
            _nomeProdutoEncontrado = '';
          });
          _prepararCampoCadastroInline(
            solicitarFoco: solicitarFocoSeNaoEncontrar,
          );
        }
      } else {
        // Busca textual por descrição no banco SQLite local
        final prod = await produtosCtrl.buscarPorTermoOuEan(texto);
        if (!mounted) return;

        if (prod != null) {
          setState(() {
            _produtoLocalizado = true;
            _encontradoNaBaseExterna = false;
            _produtoIdEncontrado = prod.idProduto;
            _nomeProdutoEncontrado = prod.nomeProduto;

            // Preenche o código de barras se o produto local já tiver EAN vinculado
            if (_codigoBarrasController.text.isEmpty &&
                prod.codigoBarras != null &&
                prod.codigoBarras!.isNotEmpty) {
              _codigoBarrasController.text = prod.codigoBarras!;
            }
          });
        } else {
          // Não encontrado no banco local: abre campo inline sem roubar o foco da digitação
          setState(() {
            _produtoLocalizado = false;
            _encontradoNaBaseExterna = false;
            _produtoIdEncontrado = null;
            _nomeProdutoEncontrado = '';
          });

          if (widget.itemPlanejado == null) {
            _nomeNovoProdutoController.text = texto;
          } else {
            _prepararCampoCadastroInline(
              solicitarFoco: solicitarFocoSeNaoEncontrar,
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _produtoLocalizado = false;
        _encontradoNaBaseExterna = false;
        _produtoIdEncontrado = null;
        _nomeProdutoEncontrado = '';
      });
      _prepararCampoCadastroInline(solicitarFoco: solicitarFocoSeNaoEncontrar);
    } finally {
      if (mounted) {
        setState(() => _isBuscandoProduto = false);
      }
    }

    _recalcularSubtotal();
  }

  /// Abre a câmera do aparelho em modal para leitura rápida de código de barras.
  Future<void> _abrirScannerCamera() async {
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
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
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
      _debounceBusca?.cancel();
      setState(() {
        _codigoBarrasController.text = codigoLido;
      });
      await _buscarProdutoNoBanco(
        codigoLido,
        solicitarFocoSeNaoEncontrar: true,
      );
    }
  }

  /// Valida os dados, realiza o cadastro rápido inline no SQLite (quando necessário)
  /// e insere ou atualiza o item no carrinho local da compra em andamento.
  Future<void> _adicionarACompra() async {
    // Impede duplo clique rápido enquanto o item está sendo persistido
    if (_isSalvandoItem) return;

    final precoNormalTexto = _precoController.text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    final precoNormalVal = double.tryParse(precoNormalTexto) ?? 0.0;

    final precoPromoTexto = _precoPromocaoController.text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    final precoPromoVal = double.tryParse(precoPromoTexto) ?? 0.0;

    setState(() => _isSalvandoItem = true);

    try {
      int? prodIdFinal =
          _produtoIdEncontrado ?? widget.itemPlanejado?.produtoId;
      String nomeFinal = _nomeProdutoEncontrado;

      // Caso o produto ainda não esteja vinculado ao catálogo local:
      if (prodIdFinal == null || prodIdFinal <= 0) {
        if (!_produtoLocalizado) {
          final nomeDigitado = _nomeNovoProdutoController.text.trim().isNotEmpty
              ? _nomeNovoProdutoController.text.trim()
              : (widget.itemPlanejado?.nomeItemPlanejado.trim() ?? '');

          if (nomeDigitado.isEmpty) {
            throw Exception(
              'Digite o nome do produto para cadastrar e adicionar ao carrinho!',
            );
          }

          // Infere 'Kg' se a quantidade possuir casas decimais ou 'Un' se for inteira
          final unidadeInferida = (_qtdComprada % 1 != 0) ? 'Kg' : 'Un';
          final produtosCtrl = ref.read(produtosControllerProvider.notifier);
          final possivelEan =
              produtosCtrl.limparCodigoBarras(_codigoBarrasController.text);
          final codigoBarrasParaSalvar = (possivelEan.isNotEmpty &&
                  possivelEan == _codigoBarrasController.text.trim())
              ? possivelEan
              : null;

          // Cadastra rapidamente no catálogo local (categoria padrão Mercearia / Grãos)
          final produtoCriado = await produtosCtrl.cadastrarProdutoRapidoInline(
            usuarioId: widget.usuarioId,
            codigoBarras: codigoBarrasParaSalvar,
            nomeProduto: nomeDigitado,
            unidadeMedida: unidadeInferida,
          );

          prodIdFinal = produtoCriado.idProduto;
          nomeFinal = produtoCriado.nomeProduto;
        } else if (widget.itemPlanejado == null) {
          throw Exception(
            'Escaneie ou pesquise um produto antes de adicionar ao carrinho!',
          );
        }
      }

      // Persiste o item localmente no carrinho ativo da compra
      await ref.read(comprasControllerProvider.notifier).registrarItemNoCarrinho(
            listaId: widget.listaId,
            usuarioId: widget.usuarioId,
            produtoId: prodIdFinal,
            nomeProduto: nomeFinal,
            itemPlanejado: widget.itemPlanejado,
            qtdComprada: _qtdComprada,
            precoUnitario: precoNormalVal,
            isPromocao: _isPromocao,
            qtdMinimaPromocao: _qtdMinimaPromocao,
            precoPromocional: precoPromoVal,
          );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.statusDanger,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSalvandoItem = false);
      }
    }
  }

  /// Abre a tela completa de Cadastro de Produtos (T10) para edição detalhada.
  void _navegarParaCadastroProdutoT10() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastroProdutosScreen(
          usuarioId: widget.usuarioId,
          abaInicial: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFluxoT09 = widget.itemPlanejado != null;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: const Text(
          'Adicionar Produto',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ================================================================================
            // BANNER SUPERIOR COMPACTO DE IDENTIFICAÇÃO DA OPERAÇÃO
            // Preserva a origem do item (ITEM PLANEJADO ou ITEM FORA DA LISTA) e exibe
            // o selo laranja 'PROMOÇÃO' quando o checkbox estiver marcado.
            // ================================================================================
            if (isFluxoT09) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isPromocao
                        ? Colors.orange.shade400
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'ITEM PLANEJADO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              if (_isPromocao) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'PROMOÇÃO',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.itemPlanejado!.nomeItemPlanejado,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'QTD PLANEJADA',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              Formatters.fmtQtd(
                                widget.itemPlanejado!.qtdPlanejada,
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isPromocao
                        ? Colors.orange.shade400
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'ITEM FORA DA LISTA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppTheme.textDark,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (_isPromocao) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PROMOÇÃO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // ================================================================================
            // CONTÊINER PRINCIPAL DOS DADOS DO PRODUTO E VALORES
            // ================================================================================
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Campo de Pesquisa por Código de Barras ou Descrição + Botão da Câmera
                  const Text(
                    'Código de barras (opcional) / Descrição',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codigoBarrasController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Digite ou escaneie [câmera]',
                            fillColor: Colors.grey.shade50,
                            filled: true,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: _onChangedPesquisa,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _abrirScannerCamera,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Barra de progresso discreta durante consulta nas bases locais ou externas
                  if (_isBuscandoProduto) ...[
                    const SizedBox(height: 5),
                    const LinearProgressIndicator(color: Colors.orange),
                  ],

                  const SizedBox(height: 8),

                  // Controle de Promoção / Atacado (QTD MIN + Checkbox Promoção)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isPromocao)
                        Row(
                          children: [
                            const Text(
                              'QTD MIN:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 30,
                                    ),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.remove, size: 16),
                                    onPressed: () {
                                      if (_qtdMinimaPromocao > 1) {
                                        setState(() {
                                          _qtdMinimaPromocao--;
                                        });
                                        _recalcularSubtotal();
                                      }
                                    },
                                  ),
                                  Text(
                                    '${_qtdMinimaPromocao.toInt()}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  IconButton(
                                    constraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 30,
                                    ),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.add, size: 16),
                                    onPressed: () {
                                      setState(() {
                                        _qtdMinimaPromocao++;
                                      });
                                      _recalcularSubtotal();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox(),

                      Row(
                        children: [
                          SizedBox(
                            height: 32,
                            width: 32,
                            child: Checkbox(
                              value: _isPromocao,
                              activeColor: AppTheme.primaryBlue,
                              onChanged: (val) {
                                setState(() {
                                  _isPromocao = val ?? false;
                                });
                                _recalcularSubtotal();
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Promoção',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Feedback da Busca e Campo Inline de Cadastro Rápido
                  if (!_produtoLocalizado) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Text(
                            _encontradoNaBaseExterna
                                ? 'Não localizado no seu cadastro, mas encontrado na base pública / API Agilista — Confirme o nome para cadastrar ao adicionar:'
                                : 'Produto não localizado — Informe o nome para cadastrar ao adicionar:',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              // Laranja quando localizado na base externa; Vermelho quando não encontrado em nenhuma base
                              color: _encontradoNaBaseExterna
                                  ? Colors.orange.shade800
                                  : AppTheme.statusDanger,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nomeNovoProdutoController,
                          focusNode: _nomeNovoProdutoFocusNode,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Nome do Produto',
                            hintText: isFluxoT09
                                ? 'Confirme ou altere o nome da lista'
                                : 'Digite o nome do produto',
                            fillColor: Colors.grey.shade50,
                            filled: true,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onTap: () {
                            if (isFluxoT09 &&
                                _nomeNovoProdutoController.text.isNotEmpty) {
                              _selecionarTextoTodo(_nomeNovoProdutoController);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else if (_nomeProdutoEncontrado.isNotEmpty &&
                      _codigoBarrasController.text.trim().isNotEmpty) ...[
                    Center(
                      child: Text(
                        _nomeProdutoEncontrado,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Quantidade Comprada (QTD COMP)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'QTD COMP:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: () {
                                if (_qtdComprada > 0.1) {
                                  setState(() {
                                    _qtdComprada =
                                        (_qtdComprada - 1.0).clamp(0.1, 9999.0);
                                    _qtdCompradaController.text =
                                        _qtdComprada % 1 == 0
                                            ? _qtdComprada.toInt().toString()
                                            : _qtdComprada
                                                .toStringAsFixed(3)
                                                .replaceAll('.', ',');
                                  });
                                  _recalcularSubtotal();
                                }
                              },
                            ),
                            SizedBox(
                              width: 96,
                              child: TextField(
                                controller: _qtdCompradaController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 6,
                                  ),
                                ),
                                onTap: () =>
                                    _selecionarTextoTodo(_qtdCompradaController),
                              ),
                            ),
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: () {
                                setState(() {
                                  _qtdComprada += 1.0;
                                  _qtdCompradaController.text =
                                      _qtdComprada % 1 == 0
                                          ? _qtdComprada.toInt().toString()
                                          : _qtdComprada
                                              .toStringAsFixed(3)
                                              .replaceAll('.', ',');
                                });
                                _recalcularSubtotal();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Preço Unitário Normal
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Preço unit.:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.textDark,
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _precoController,
                          focusNode: _precoFocusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            fillColor: Colors.grey.shade50,
                            filled: true,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onTap: () => _selecionarTextoTodo(_precoController),
                        ),
                      ),
                    ],
                  ),

                  // Preço Promocional (exibido dinamicamente quando Promoção estiver marcada)
                  if (_isPromocao) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Preço PROMOÇÃO.:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _precoPromocaoController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              fillColor: Colors.grey.shade50,
                              filled: true,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onTap: () =>
                                _selecionarTextoTodo(_precoPromocaoController),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Subtotal Calculado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SubTotal.:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Container(
                        width: 120,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          Formatters.fmtMoeda(_subtotal),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ================================================================================
            // BOTÕES DE AÇÃO (ADICIONAR A COMPRA E CADASTRO DE PRODUTO)
            // ================================================================================
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _isSalvandoItem ? null : _adicionarACompra,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSalvandoItem
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'ADICIONAR A COMPRA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              height: 46,
              child: OutlinedButton(
                onPressed: _navegarParaCadastroProdutoT10,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'CADASTRO DE PRODUTO',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}