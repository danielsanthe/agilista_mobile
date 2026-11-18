import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Imports de temas, formatadores e componentes do projeto
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';
import '../../controllers/historico_contoller.dart';
import '../widgets/seletor_periodo_widget.dart';

// Imports das telas de destino de relatórios e análises
import 't19_relatorio_compra_screen.dart';
import 't20_produtos_recorrentes_screen.dart';
import 't21_historico_preco_screen.dart';

/// ============================================================================
/// TELA T18 — HISTÓRICO DE COMPRAS
/// ============================================================================
/// Apresenta o histórico sintético de compras realizadas dentro de um período.
/// Permite selecionar uma compra para visualizar o relatório detalhado (T19),
/// navegar para produtos recorrentes (T20) ou histórico de preços (T21).
class T18HistoricoScreen extends ConsumerStatefulWidget {
  final int usuarioId;
  
  const T18HistoricoScreen({
    super.key, 
    required this.usuarioId,
  });

  @override
  ConsumerState<T18HistoricoScreen> createState() => _T18HistoricoScreenState();
}

class _T18HistoricoScreenState extends ConsumerState<T18HistoricoScreen> {
  /// Identificador da lista selecionada na interface.
  /// Inicialmente nulo, mas preenchido automaticamente com o 1º item retornado do banco.
  int? _listaSelecionadaId;

  // Variáveis de controle de datas para filtragem do histórico
  late DateTime _dataInicioTemp;
  late DateTime _dataFimTemp;
  late FiltroDataParam _filtroAplicado;

  @override
  void initState() {
    super.initState();
    // Configura o intervalo padrão de busca para os últimos 30 dias
    _dataFimTemp = DateTime.now();
    _dataInicioTemp = _dataFimTemp.subtract(const Duration(days: 30));

    _filtroAplicado = FiltroDataParam(
      usuarioId: widget.usuarioId,
      dataInicio: _dataInicioTemp,
      dataFim: _dataFimTemp,
    );
  }

  /// Disparado ao clicar no botão 'FILTRAR'
  /// Reseta a seleção anterior para garantir que a nova busca selecione automaticamente o primeiro item.
  void _executarFiltro() {
    setState(() {
      _listaSelecionadaId = null;
      _filtroAplicado = FiltroDataParam(
        usuarioId: widget.usuarioId,
        dataInicio: _dataInicioTemp,
        dataFim: _dataFimTemp,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escuta o provider reativo que busca os dados de compras no banco SQLite
    final asyncHistorico = ref.watch(historicoComprasProvider(_filtroAplicado));

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Histórico', 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryBlue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // COMPONENTE 1: Seletor de Intervalo de Datas e Botão Filtrar
            SeletorPeriodoWidget(
              dataInicio: _dataInicioTemp,
              dataFim: _dataFimTemp,
              onDatasAlteradas: (inicio, fim) {
                _dataInicioTemp = inicio;
                _dataFimTemp = fim;
              },
              onFiltrarClicado: _executarFiltro,
            ),
            const SizedBox(height: 12),

            // COMPONENTE 2: Lista Sintética de Compras com Seleção Automática
            Expanded(
              child: asyncHistorico.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Erro ao carregar histórico: $err')),
                data: (compras) {
                  // Caso não existam registros no período filtrado
                  if (compras.isEmpty) {
                    return const Center(
                      child: Text(
                        'Nenhuma compra encontrada no período.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    );
                  }

                  // ===========================================================
                  // REGRA DE NEGÓCIO: SELEÇÃO AUTOMÁTICA DO PRIMEIRO ITEM
                  // Se nenhum item estiver selecionado, atribui o id do primeiro
                  // registro retornado para habilitar o botão 'VER DETALHADO'.
                  // ===========================================================
                  if (_listaSelecionadaId == null && compras.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _listaSelecionadaId = compras.first['id_lista'] as int?;
                        });
                      }
                    });
                  }

                  return ListView.separated(
                    itemCount: compras.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = compras[index];
                      final idLista = item['id_lista'] as int;
                      final isSelected = _listaSelecionadaId == idLista;

                      // Formatação da data de criação da compra
                      DateTime? dt = DateTime.tryParse(item['data_criacao']?.toString() ?? '');
                      String dataFmt = dt != null ? DateFormat('dd/MM/yyyy').format(dt) : 'S/D';

                      return InkWell(
                        // Permite trocar a seleção ao clicar em qualquer item
                        onTap: () => setState(() => _listaSelecionadaId = idLista),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.orange.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.orange : Colors.grey.shade300,
                              width: isSelected ? 2 : 1, // Destaque visual no item selecionado
                            ),
                          ),
                          child: Row(
                            children: [
                              // Data da Compra
                              Text(
                                dataFmt, 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              const SizedBox(width: 12),

                              // Nome do Estabelecimento ou da Lista
                              Expanded(
                                child: Text(
                                  item['nome_estabelecimento']?.toString() ?? 
                                  item['nome_lista']?.toString() ?? 
                                  'Mercado',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              // Valor Total da Compra Formatado
                              Text(
                                Formatters.fmtMoeda((item['valor_total_atual'] as num?)?.toDouble() ?? 0.0),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 13, 
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // BOTÃO 1: VER DETALHADO (Abre a tela T19 com o id da compra selecionada)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                onPressed: _listaSelecionadaId == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => T19RelatorioCompraScreen(listaId: _listaSelecionadaId!),
                          ),
                        );
                      },
                child: const Text(
                  'VER DETALHADO', 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // BOTÃO 2: PRODUTOS RECORRENTES (Abre a tela T20)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => T20ProdutosRecorrentesScreen(usuarioId: widget.usuarioId),
                    ),
                  );
                },
                child: const Text(
                  'PRODUTOS RECORRENTES', 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // BOTÃO 3: HISTÓRICO DE PREÇO (Abre a tela T21)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const T21HistoricoPrecoScreen(),
                    ),
                  );
                },
                child: const Text(
                  'HISTÓRICO DE PREÇO', 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}