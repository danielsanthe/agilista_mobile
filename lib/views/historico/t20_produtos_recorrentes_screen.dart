import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';
import '../../controllers/historico_contoller.dart';
import '../widgets/seletor_periodo_widget.dart';

class T20ProdutosRecorrentesScreen extends ConsumerStatefulWidget {
  final int usuarioId;
  const T20ProdutosRecorrentesScreen({super.key, required this.usuarioId});

  @override
  ConsumerState<T20ProdutosRecorrentesScreen> createState() => _T20ProdutosRecorrentesScreenState();
}

class _T20ProdutosRecorrentesScreenState extends ConsumerState<T20ProdutosRecorrentesScreen> {
  late DateTime _dataInicioTemp;
  late DateTime _dataFimTemp;

  FiltroDataParam? _filtroAplicado;

  @override
  void initState() {
    super.initState();
    _dataFimTemp = DateTime.now();
    _dataInicioTemp = DateTime(_dataFimTemp.year, _dataFimTemp.month, 1);
  }

  void _executarFiltro() {
    setState(() {
      _filtroAplicado = FiltroDataParam(
        usuarioId: widget.usuarioId,
        dataInicio: _dataInicioTemp,
        dataFim: _dataFimTemp,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Produtos Recorrentes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            Expanded(
              child: _filtroAplicado == null
                  ? const Center(
                      child: Text(
                        'Selecione o período e clique em FILTRAR para pesquisar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  : Consumer(
                      builder: (context, ref, child) {
                        final asyncRecorrentes = ref.watch(produtosRecorrentesProvider(_filtroAplicado!));

                        return asyncRecorrentes.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Center(child: Text('Erro ao carregar produtos: $err')),
                          data: (produtos) {
                            if (produtos.isEmpty) {
                              return const Center(child: Text('Nenhum produto recorrente comprado no período.'));
                            }
                            return ListView.separated(
                              itemCount: produtos.length,
                              separatorBuilder: (_, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final p = produtos[index];
                                final preco = (p['ultimo_preco'] as num?)?.toDouble() ?? 0.0;

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.orange, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${p['nome_produto']} ${p['unidade_medida'] ?? ''}'.trim(),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ),
                                      Text(
                                        '${p['total_compras']} compras | ${Formatters.fmtMoeda(preco)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                                      ),
                                    ],
                                  ),
                                );
                              },
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