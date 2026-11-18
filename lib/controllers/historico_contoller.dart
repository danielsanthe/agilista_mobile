import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../nucleo/constantes/status_constants.dart';
import '../nucleo/database/app_database.dart';

class FiltroDataParam {
  final int usuarioId;
  final DateTime dataInicio;
  final DateTime dataFim;

  FiltroDataParam({
    required this.usuarioId,
    required this.dataInicio,
    required this.dataFim,
  });

  String get dataInicioStr => DateFormat('yyyy-MM-dd').format(dataInicio);
  String get dataFimStr => DateFormat('yyyy-MM-dd').format(dataFim.add(const Duration(days: 1)));
}

class FiltroPrecoParam {
  final int produtoId;
  final DateTime dataInicio;
  final DateTime dataFim;

  FiltroPrecoParam({
    required this.produtoId,
    required this.dataInicio,
    required this.dataFim,
  });

  String get dataInicioStr => DateFormat('yyyy-MM-dd').format(dataInicio);
  String get dataFimStr => DateFormat('yyyy-MM-dd').format(dataFim.add(const Duration(days: 1)));
}

/// Provider para buscar a lista completa de produtos cadastrados (Dropdown da T21)
final todosProdutosProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = await AppDatabase.instance.database;
  return await db.rawQuery('''
    SELECT id_produto, nome_produto, unidade_medida 
    FROM produtos 
    ORDER BY nome_produto ASC
  ''');
});

/// Provider para buscar as compras concluídas no período (T18)
final historicoComprasProvider = FutureProvider.family<List<Map<String, dynamic>>, FiltroDataParam>((ref, param) async {
  final db = await AppDatabase.instance.database;
  return await db.rawQuery('''
    SELECT l.id_lista, l.nome_lista, l.data_criacao, l.valor_orcamento,
           l.valor_total_atual, l.nome_estabelecimento
    FROM listas l
    WHERE l.usuario_id = ?
      AND (l.status_lista = '${StatusLista.concluida}' OR l.status_lista = 'Concluída' OR l.status_lista = 'Concluida')
      AND l.data_criacao >= ? 
      AND l.data_criacao < ?
    ORDER BY l.data_criacao DESC
  ''', [param.usuarioId, param.dataInicioStr, param.dataFimStr]);
});

/// Provider para detalhar o relatório de uma compra (T19)
final relatorioCompraProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, listaId) async {
  final db = await AppDatabase.instance.database;
  
  final listaResult = await db.query('listas', where: 'id_lista = ?', whereArgs: [listaId], limit: 1);
  final itens = await db.rawQuery('''
    SELECT i.*, p.nome_produto 
    FROM itens_lista i
    LEFT JOIN produtos p ON i.produto_id = p.id_produto
    WHERE i.lista_id = ?
  ''', [listaId]);

  int planejados = 0;
  int conforme = 0;
  int foraDaLista = 0;
  double gastoTotal = 0.0;

  if (listaResult.isNotEmpty) {
    gastoTotal = (listaResult.first['valor_total_atual'] as num?)?.toDouble() ?? 0.0;
  }

  for (var item in itens) {
    double qtdPlan = (item['qtd_planejada'] as num?)?.toDouble() ?? 0.0;
    double qtdComp = (item['qtd_comprada'] as num?)?.toDouble() ?? 0.0;
    bool isFora = (item['flag_fora_da_lista'] == 1);

    if (isFora) {
      foraDaLista++;
    } else {
      planejados++;
      if (qtdComp >= qtdPlan && qtdPlan > 0) {
        conforme++;
      }
    }
  }

  return {
    'orcamento': listaResult.isNotEmpty ? ((listaResult.first['valor_orcamento'] as num?)?.toDouble() ?? 0.0) : 0.0,
    'gasto_total': gastoTotal,
    'planejados': planejados,
    'conforme': conforme,
    'fora_da_lista': foraDaLista,
    'itens': itens,
  };
});

/// Provider para buscar produtos recorrentes comprados no período (T20)
final produtosRecorrentesProvider = FutureProvider.family<List<Map<String, dynamic>>, FiltroDataParam>((ref, param) async {
  final db = await AppDatabase.instance.database;
  return await db.rawQuery('''
    SELECT p.id_produto, p.nome_produto, p.unidade_medida,
           COUNT(DISTINCT i.lista_id) as total_compras,
           (SELECT preco_unitario FROM itens_lista WHERE produto_id = p.id_produto AND preco_unitario > 0 ORDER BY id_item_lista DESC LIMIT 1) as ultimo_preco
    FROM produtos p
    INNER JOIN itens_lista i ON p.id_produto = i.produto_id
    INNER JOIN listas l ON i.lista_id = l.id_lista
    WHERE p.flag_produto_recorrente = 1
      AND l.usuario_id = ?
      AND l.data_criacao >= ? 
      AND l.data_criacao < ?
    GROUP BY p.id_produto
    ORDER BY p.nome_produto ASC
  ''', [param.usuarioId, param.dataInicioStr, param.dataFimStr]);
});

/// Provider para buscar a variação de preços de um produto (T21)
final historicoPrecosProdutoProvider = FutureProvider.family<List<Map<String, dynamic>>, FiltroPrecoParam>((ref, param) async {
  final db = await AppDatabase.instance.database;
  return await db.rawQuery('''
    SELECT i.preco_unitario, l.data_criacao, l.nome_estabelecimento
    FROM itens_lista i
    INNER JOIN listas l ON i.lista_id = l.id_lista
    WHERE i.produto_id = ? 
      AND i.preco_unitario > 0
      AND l.data_criacao >= ? 
      AND l.data_criacao < ?
    ORDER BY l.data_criacao DESC
  ''', [param.produtoId, param.dataInicioStr, param.dataFimStr]);
});