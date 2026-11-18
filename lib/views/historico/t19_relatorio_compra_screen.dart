import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';
import '../../controllers/historico_contoller.dart';

class T19RelatorioCompraScreen extends ConsumerWidget {
  final int listaId;
  const T19RelatorioCompraScreen({super.key, required this.listaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRelatorio = ref.watch(relatorioCompraProvider(listaId));

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Relatório da Compra',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: asyncRelatorio.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Erro ao carregar relatório: $err',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.statusDanger),
            ),
          ),
        ),
        data: (dados) {
          final List itens = dados['itens'] ?? [];

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Banner Resumo de Métricas (Planejados / Conforme / Fora da lista)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${dados['planejados']} planejados  |  ${dados['conforme']} conforme  |  ${dados['fora_da_lista']} fora da lista',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Cabeçalho da Tabela
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ITEM',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        'QTD COMP / QTD PLAN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Lista Analítica de Itens Comprados
                Expanded(
                  child: itens.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum item encontrado nesta compra.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: itens.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = itens[index];
                            final bool isFora = (item['flag_fora_da_lista'] == 1);
                            final String nomeItem = item['nome_produto']?.toString() ??
                                item['nome_item_planejado']?.toString() ??
                                'Item sem nome';

                            final double valQtdPlan = (item['qtd_planejada'] as num?)?.toDouble() ?? 0.0;
                            final double valQtdComp = (item['qtd_comprada'] as num?)?.toDouble() ?? 0.0;

                            final String qtdPlanFmt = Formatters.fmtQtd(valQtdPlan);
                            final String qtdCompFmt = Formatters.fmtQtd(valQtdComp);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      nomeItem,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    isFora ? 'fora da lista' : '$qtdCompFmt / $qtdPlanFmt',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isFora ? AppTheme.statusDanger : AppTheme.textDark,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),

                // Rodapé de Fechamento Financeiro (Orçamento vs Gasto Realizado)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Orçamento ${Formatters.fmtMoeda((dados['orcamento'] as num?)?.toDouble() ?? 0.0)}  |  Gasto ${Formatters.fmtMoeda((dados['gasto_total'] as num?)?.toDouble() ?? 0.0)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}