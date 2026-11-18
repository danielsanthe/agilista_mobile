import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';
import '../../controllers/historico_contoller.dart';
import '../widgets/seletor_periodo_widget.dart';

class T21HistoricoPrecoScreen extends ConsumerStatefulWidget {
  const T21HistoricoPrecoScreen({super.key});

  @override
  ConsumerState<T21HistoricoPrecoScreen> createState() => _T21HistoricoPrecoScreenState();
}

class _T21HistoricoPrecoScreenState extends ConsumerState<T21HistoricoPrecoScreen> {
  int? _produtoSelecionadoId;
  late DateTime _dataInicioTemp;
  late DateTime _dataFimTemp;

  FiltroPrecoParam? _filtroAplicado;

  @override
  void initState() {
    super.initState();
    _dataFimTemp = DateTime.now();
    _dataInicioTemp = DateTime(_dataFimTemp.year, _dataFimTemp.month - 3, 1);
  }

  void _executarFiltro() {
    if (_produtoSelecionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione um produto primeiro!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _filtroAplicado = FiltroPrecoParam(
        produtoId: _produtoSelecionadoId!,
        dataInicio: _dataInicioTemp,
        dataFim: _dataFimTemp,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Busca a lista completa de produtos para popular o Dropdown de Seleção
    final asyncProdutos = ref.watch(todosProdutosProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Histórico de Preços',
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Seletor de Período (Data Início e Fim + Botão FILTRAR)
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

            const Text(
              'Produto',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
            ),
            const SizedBox(height: 4),

            // Dropdown de Seleção do Produto
            asyncProdutos.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Erro ao carregar lista de produtos: $err'),
              data: (listaProdutos) {
                return DropdownButtonFormField<int>(
                  initialValue: _produtoSelecionadoId,
                  hint: const Text('Selecione o produto'),
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: listaProdutos.map((p) {
                    return DropdownMenuItem<int>(
                      value: p['id_produto'] as int,
                      child: Text('${p['nome_produto']} (${p['unidade_medida'] ?? 'Un'})'.trim()),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _produtoSelecionadoId = val;
                      _filtroAplicado = null; // Exige clicar em FILTRAR para atualizar
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // Área da Movimentação de Preços no Período
            Expanded(
              child: _filtroAplicado == null
                  ? const Center(
                      child: Text(
                        'Selecione o produto, ajuste o período e clique em FILTRAR.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  : Consumer(
                      builder: (context, ref, child) {
                        final asyncPrecos = ref.watch(historicoPrecosProdutoProvider(_filtroAplicado!));

                        return asyncPrecos.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Center(child: Text('Erro ao carregar preços: $err')),
                          data: (precos) {
                            if (precos.isEmpty) {
                              return const Center(
                                child: Text('Nenhum registro de preço encontrado no período selecionado.'),
                              );
                            }

                            // Variáveis para identificar o Menor e Maior Preço e os respectivos Estabelecimentos
                            Map<String, dynamic>? itemMenor;
                            Map<String, dynamic>? itemMaior;

                            for (var p in precos) {
                              double val = (p['preco_unitario'] as num).toDouble();
                              if (itemMenor == null || val < (itemMenor['preco_unitario'] as num).toDouble()) {
                                itemMenor = p;
                              }
                              if (itemMaior == null || val > (itemMaior['preco_unitario'] as num).toDouble()) {
                                itemMaior = p;
                              }
                            }

                            final double precoMenor = (itemMenor!['preco_unitario'] as num).toDouble();
                            final String estMenor = itemMenor['nome_estabelecimento']?.toString() ?? 'Mercado';

                            final double precoMaior = (itemMaior!['preco_unitario'] as num).toDouble();
                            final String estMaior = itemMaior['nome_estabelecimento']?.toString() ?? 'Mercado';

                            return Column(
                              children: [
                                // Lista de Ocorrências e Histórico de Movimentação
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: precos.length,
                                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final item = precos[index];
                                      DateTime? dt = DateTime.tryParse(item['data_criacao']?.toString() ?? '');
                                      String dataFmt = dt != null ? DateFormat('dd/MM/yyyy').format(dt) : 'S/D';

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item['nome_estabelecimento']?.toString() ?? 'Estabelecimento',
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                              ),
                                            ),
                                            Text(
                                              dataFmt,
                                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              Formatters.fmtMoeda((item['preco_unitario'] as num).toDouble()),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: AppTheme.primaryBlue,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Card Resumo do Menor vs Maior Preço por Estabelecimento
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Menor: ${Formatters.fmtMoeda(precoMenor)} ($estMenor)',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: AppTheme.statusSuccess,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Maior: ${Formatters.fmtMoeda(precoMaior)} ($estMaior)',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: AppTheme.statusDanger,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}