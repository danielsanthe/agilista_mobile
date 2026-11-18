import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../controllers/listas_controller.dart';
import '../../models/lista_model.dart';
import '../../nucleo/constantes/estados_constants.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../services/localizacao_service.dart';
import 't08_t13_minha_compra_screen.dart';

/// ============================================================================
/// TELA T07 — INICIAR COMPRA / LOCALIZAÇÃO POR GPS E ENDEREÇO
/// ============================================================================
/// Diálogo modal desacoplado para confirmação do estabelecimento e captura
/// do endereço completo via GPS (Logradouro, Número, Bairro, Cidade, UF) antes de
/// transicionar a lista de compras para o status 'Em Andamento' e congelar
/// o planejamento e orçamento inicial.
///
/// Arquitetura Offline-First:
/// - Persiste a transição para 'Em Andamento' e o endereço do estabelecimento
///   diretamente no SQLite local (`flag_sincronizado = 0`) via [ListsController],
///   abrindo imediatamente o carrinho [ShoppingScreen] mesmo sem internet.
class IniciarCompraDialog extends ConsumerStatefulWidget {
  /// Instância da lista de compras planejada que será iniciada.
  final ListaModel lista;

  /// ID local do usuário autenticado no sistema.
  final int usuarioId;

  const IniciarCompraDialog({
    super.key,
    required this.lista,
    required this.usuarioId,
  });

  /// Método estático utilitário para invocar a exibição do diálogo modal T07
  /// de qualquer visualização do aplicativo de forma simples e padronizada.
  static Future<void> exibir(
    BuildContext context, {
    required ListaModel lista,
    required int usuarioId,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false, // Impede o fechamento acidental ao clicar fora do modal
      builder: (ctx) => IniciarCompraDialog(
        lista: lista,
        usuarioId: usuarioId,
      ),
    );
  }

  @override
  ConsumerState<IniciarCompraDialog> createState() => _IniciarCompraDialogState();
}

class _IniciarCompraDialogState extends ConsumerState<IniciarCompraDialog> {
  /// Controlador do campo de texto para entrada manual do nome do estabelecimento.
  late TextEditingController _estabController;

  /// Controla a exibição do indicador visual de carregamento da busca de GPS.
  bool _buscandoGps = false;

  /// Trava contra duplo clique rápido durante a confirmação de início da compra.
  bool _iniciando = false;

  /// Mensagem textual de feedback visual sobre o status da geolocalização.
  String? _statusGpsMensagem;

  /// Armazena os componentes do endereço obtidos via [LocationService].
  String? _logradouro;
  String? _bairro;
  String? _cidade;
  String? _uf;

  @override
  void initState() {
    super.initState();
    // Preenche o campo de texto caso o estabelecimento já esteja salvo na lista
    _estabController =
        TextEditingController(text: widget.lista.nomeEstabelecimento ?? '');

    // Dispara automaticamente a busca de localização por GPS ao abrir o modal
    _obterLocalizacaoGps();
  }

  @override
  void dispose() {
    // Descarta o controlador para evitar vazamentos de memória do aplicativo
    _estabController.dispose();
    super.dispose();
  }

  /// Consome o [LocationService] centralizado para obter a localização por GPS
  /// e normaliza a UF para a sigla oficial de 2 caracteres (ex: "PIAUÍ" -> "PI").
  Future<void> _obterLocalizacaoGps() async {
    setState(() {
      _buscandoGps = true;
      _statusGpsMensagem = 'Buscando GPS e obtendo endereço...';
    });

    try {
      final locationService = LocationService();
      final endereco = await locationService.obterEnderecoAtual();

      if (!mounted) return;

      if (endereco != null) {
        setState(() {
          _logradouro = endereco.logradouroComNumero;
          _bairro = endereco.bairro;
          _cidade = endereco.cidade;
          _uf = EstadosConstants.normalizarUf(endereco.uf);
          _statusGpsMensagem = 'Localização obtida com sucesso!';
          _buscandoGps = false;
        });
      } else {
        setState(() {
          _statusGpsMensagem = 'Não foi possível capturar o endereço atual.';
          _buscandoGps = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusGpsMensagem = 'Erro ao obter localização por GPS.';
        _buscandoGps = false;
      });
    }
  }

  /// Conclui a transição da lista para 'Em Andamento', grava o endereço no banco SQLite
  /// (com UF normalizada em 2 caracteres) e abre a tela de compras T08/T13.
  Future<void> _confirmarInicio() async {
    if (_iniciando) return;

    final nav = Navigator.of(context);
    final nomeEstab = _estabController.text.trim();

    // Validação estrita do estabelecimento (obrigatório) antes de submeter
    if (nomeEstab.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, informe o nome do estabelecimento comercial.',
          ),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
      return;
    }

    setState(() => _iniciando = true);

    try {
      // Garante que a UF repassada ao controller esteja no padrão oficial de 2 letras
      final ufNormalizada = EstadosConstants.normalizarUf(_uf);

      // Invoca o notifier do controller repassando o nome do estabelecimento validado
      final sucesso =
          await ref.read(listsControllerProvider.notifier).iniciarCompra(
                listaId: widget.lista.idLista!,
                usuarioId: widget.usuarioId,
                estabelecimento: nomeEstab,
                endereco: _logradouro,
                bairro: _bairro,
                cidade: _cidade,
                uf: ufNormalizada,
              );

      if (sucesso && mounted) {
        nav.pop(); // Fecha a caixa de diálogo T07

        // Obtém o registro atualizado da lista no estado reativo do Riverpod
        final listas = ref.read(listsControllerProvider).value ?? [];
        final listaAtualizada = listas.firstWhere(
          (l) => l.idLista == widget.lista.idLista,
          orElse: () => widget.lista,
        );

        // Direciona o usuário para a interface de execução de compras (T08/T13)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShoppingScreen(lista: listaAtualizada),
          ),
        );
      } else if (mounted) {
        // Exibe mensagem informativa caso a lista não contenha nenhum item ou ocorra erro
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A lista precisa ter itens para iniciar a compra ou ocorreu um erro.',
            ),
            backgroundColor: AppTheme.statusDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Iniciar Compra',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: AppTheme.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Lista: ${widget.lista.nomeLista}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Texto explicativo do procedimento de gravação do endereço
            const Text(
              'O app identificará sua localização e gravará o endereço no banco de dados.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),

            // Campo de Entrada do Nome do Estabelecimento Comercial (Obrigatório *)
            TextField(
              controller: _estabController,
              decoration: InputDecoration(
                labelText: 'Nome do Estabelecimento *',
                hintText: 'Ex: Supermercado Extra',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.my_location,
                    color: AppTheme.primaryBlue,
                  ),
                  onPressed: _obterLocalizacaoGps,
                  tooltip: 'Buscar GPS novamente',
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Card com a Exibição dos Dados do Endereço Identificado via GPS
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Endereço Identificado (Gravação em banco):',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_buscandoGps) ...[
                    const Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Obtendo localização...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_logradouro != null && _logradouro!.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: AppTheme.statusSuccess,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$_logradouro, $_bairro\n$_cidade / $_uf',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      _statusGpsMensagem ?? 'Endereço não capturado.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.statusDanger,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Card Informativo da Regra de Negócio: Congelamento do Planejamento
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryBlue.withAlpha(50)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.lock_clock,
                    color: AppTheme.primaryBlue,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ao iniciar: status = EM ANDAMENTO.\nPlanejamento e orçamento ficam congelados.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Botão para cancelar a operação sem salvar alterações
        TextButton(
          onPressed: _iniciando ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),

        // Botão para confirmar a inicialização da compra
        ElevatedButton(
          onPressed: (_buscandoGps || _iniciando) ? null : _confirmarInicio,
          style: AppTheme.orangeButtonStyle,
          child: _iniciando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'INICIAR COMPRA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}