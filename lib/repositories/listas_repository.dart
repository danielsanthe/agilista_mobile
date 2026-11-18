import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../nucleo/constantes/estados_constants.dart';
import '../nucleo/database/app_database.dart';
import '../models/produto_model.dart';
import '../models/item_lista_model.dart';
import 'exclusao_repository.dart';
import '../models/lista_model.dart';

/// Provider Riverpod para fornecer a instância do repositório de listas e categorias.
final listsRepositoryProvider = Provider<ListsRepository>((ref) {
  return ListsRepositoryImpl();
});

/// Interface abstrata definindo as operações de Listas, Itens e Categorias.
abstract class ListsRepository {
  // Gestão de Listas de Compras
  Future<ListaModel> criarLista(ListaModel lista);
  Future<List<ListaModel>> listarPorUsuario(int usuarioId);
  Future<ListaModel?> buscarPorId(int listaId);
  Future<void> atualizarLista(ListaModel lista);
  Future<void> excluirLista(int listaId);

  // F05 — Iniciar Compra e registrar geolocalização
  Future<void> iniciarCompra({
    required int listaId,
    required String estabelecimento,
    String? endereco,
    String? bairro,
    String? cidade,
    String? uf,
  });

  // Gestão de Itens da Lista
  Future<List<ItemListaModel>> listarItensDaLista(int listaId);
  Future<ItemListaModel> adicionarItem(ItemListaModel item);
  Future<void> atualizarItem(ItemListaModel item);
  Future<void> removerItem(int idItemLista);

  // F18 — Replicar Lista
  Future<ListaModel> replicarLista(
    int idListaOriginal,
    String novoNome, {
    bool incluirForaDaLista = false,
  });

  // ===========================================================================
  // GESTÃO DE CATEGORIAS (T12 / T22 - GLOBAL)
  // ===========================================================================

  Future<List<Map<String, dynamic>>> listarCategorias();

  Future<int> inserirCategoria(Map<String, dynamic> dados);

  Future<int> atualizarCategoria(Map<String, dynamic> dados);

  Future<bool> verificarCategoriaPodeSerExcluida(int idCategoria);

  Future<int> excluirCategoria(int idCategoria);
}

/// Implementação concreta do repositório acessando a base local SQLite.
class ListsRepositoryImpl implements ListsRepository {
  final AppDatabase _db = AppDatabase.instance;
  final ExclusaoRepository _exclusaoRepo = ExclusaoRepository();

  // ===========================================================================
  // GESTÃO DE LISTAS
  // ===========================================================================

  @override
  Future<ListaModel> criarLista(ListaModel lista) async {
    final db = await _db.database;

    final listaNormalizada = lista.copyWith(
      uf: EstadosConstants.normalizarUf(lista.uf),
    );
    final dados = listaNormalizada.toMap();
    dados['flag_sincronizado'] = 0;

    final idInserido = await db.insert('listas', dados);

    return listaNormalizada.copyWith(
      idLista: idInserido,
      servidorId: null,
      flagSincronizado: 0,
    );
  }

  @override
  Future<List<ListaModel>> listarPorUsuario(int usuarioId) async {
    final db = await _db.database;

    final result = await db.query(
      'listas',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'data_criacao DESC',
    );

    return result.map((map) => ListaModel.fromMap(map)).toList();
  }

  @override
  Future<ListaModel?> buscarPorId(int listaId) async {
    final db = await _db.database;

    final result = await db.query(
      'listas',
      where: 'id_lista = ?',
      whereArgs: [listaId],
    );

    if (result.isNotEmpty) {
      return ListaModel.fromMap(result.first);
    }

    return null;
  }

  @override
  Future<void> atualizarLista(ListaModel lista) async {
    final db = await _db.database;

    final listaNormalizada = lista.copyWith(
      uf: EstadosConstants.normalizarUf(lista.uf),
    );
    final dados = listaNormalizada.toMap();

    // Toda alteração local precisa ser enviada ao servidor na próxima confirmação.
    dados['flag_sincronizado'] = 0;

    await db.update(
      'listas',
      dados,
      where: 'id_lista = ?',
      whereArgs: [lista.idLista],
    );
  }

  @override
  Future<void> iniciarCompra({
    required int listaId,
    required String estabelecimento,
    String? endereco,
    String? bairro,
    String? cidade,
    String? uf,
  }) async {
    final lista = await buscarPorId(listaId);

    if (lista == null) {
      throw Exception('Lista não encontrada para iniciar a compra.');
    }

    final listaAtualizada = lista.iniciarCompra(
      estabelecimento: estabelecimento,
      endereco: endereco,
      bairro: bairro,
      cidade: cidade,
      uf: EstadosConstants.normalizarUf(uf),
    );

    await atualizarLista(listaAtualizada);
  }

  @override
  Future<void> excluirLista(int listaId) async {
    final lista = await buscarPorId(listaId);
    if (lista == null) return;

    await _exclusaoRepo.excluirOffline(
      tabela: 'listas',
      nomeColunaIdLocal: 'id_lista',
      idLocal: listaId,
      servidorId: lista.servidorId,
    );
  }

  // ===========================================================================
  // GESTÃO DE ITENS DA LISTA
  // ===========================================================================

  /// Lista os itens e realiza LEFT JOIN com a tabela produtos
  /// para carregar o ProdutoModel associado, quando houver.
  @override
  Future<List<ItemListaModel>> listarItensDaLista(int listaId) async {
    final db = await _db.database;

    final result = await db.rawQuery('''
      SELECT
        i.*,
        p.id_produto AS prod_id_produto,
        p.categoria_id AS prod_categoria_id,
        p.codigo_barras AS prod_codigo_barras,
        p.nome_produto AS prod_nome_produto,
        p.unidade_medida AS prod_unidade_medida,
        p.flag_produto_recorrente AS prod_flag_produto_recorrente
      FROM itens_lista i
      LEFT JOIN produtos p ON i.produto_id = p.id_produto
      WHERE i.lista_id = ?
      ORDER BY i.id_item_lista ASC
    ''', [listaId]);

    return result.map((map) {
      ProdutoModel? produtoAssociado;

      if (map['prod_id_produto'] != null &&
          map['prod_categoria_id'] != null) {
        produtoAssociado = ProdutoModel(
          idProduto: map['prod_id_produto'] as int?,
          categoriaId: map['prod_categoria_id'] as int,
          codigoBarras: map['prod_codigo_barras']?.toString(),
          nomeProduto: map['prod_nome_produto']?.toString() ?? '',
          unidadeMedida: map['prod_unidade_medida']?.toString() ?? 'Un',
          flagProdutoRecorrente:
              (map['prod_flag_produto_recorrente'] as int?) == 1,
        );
      }

      return ItemListaModel.fromMap(
        map,
        produto: produtoAssociado,
      );
    }).toList();
  }

  @override
  Future<ItemListaModel> adicionarItem(ItemListaModel item) async {
    final db = await _db.database;

    return await db.transaction((txn) async {
      final dados = item.toMap();

      // Novo item local: ainda não possui identificação no servidor.
      dados['servidor_id'] = null;
      dados['flag_sincronizado'] = 0;

      final idInserido = await txn.insert('itens_lista', dados);

      await _recalcularTotalLista(txn, item.listaId);

      return item.copyWith(
        idItemLista: idInserido,
        servidorId: null,
        flagSincronizado: 0,
      );
    });
  }

  @override
  Future<void> atualizarItem(ItemListaModel item) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      final dados = item.toMap();

      // Preserva o servidor_id existente, mas marca a alteração como pendente.
      dados['flag_sincronizado'] = 0;

      await txn.update(
        'itens_lista',
        dados,
        where: 'id_item_lista = ?',
        whereArgs: [item.idItemLista],
      );

      await _recalcularTotalLista(txn, item.listaId);
    });
  }

  @override
  Future<void> removerItem(int idItemLista) async {
    final db = await _db.database;

    final result = await db.query(
      'itens_lista',
      columns: ['id_item_lista', 'lista_id', 'servidor_id'],
      where: 'id_item_lista = ?',
      whereArgs: [idItemLista],
    );

    if (result.isEmpty) return;

    final itemMap = result.first;
    final listaId = itemMap['lista_id'] as int;
    final servidorId = itemMap['servidor_id'] as int?;

    // Exclusão + recálculo do total na mesma transação (tudo ou nada).
    await db.transaction((txn) async {
      await _exclusaoRepo.excluirOffline(
        tabela: 'itens_lista',
        nomeColunaIdLocal: 'id_item_lista',
        idLocal: idItemLista,
        servidorId: servidorId,
        executor: txn,
      );

      await _recalcularTotalLista(txn, listaId);
    });
  }

  // ===========================================================================
  // F18 — REPLICAR LISTA
  // ===========================================================================

  /// Replica uma lista em uma NOVA lista Planejada.
  /// Preserva o orçamento e os preços estimados dos itens.
  @override
  Future<ListaModel> replicarLista(
    int idListaOriginal,
    String novoNome, {
    bool incluirForaDaLista = false,
  }) async {
    final db = await _db.database;

    return await db.transaction((txn) async {
      // 1. Buscar a lista original.
      final listaQuery = await txn.query(
        'listas',
        where: 'id_lista = ?',
        whereArgs: [idListaOriginal],
      );

      if (listaQuery.isEmpty) {
        throw Exception('Lista original não encontrada.');
      }

      final listaOriginal = ListaModel.fromMap(listaQuery.first);

      // 2. Criar uma nova lista Planejada.
      final novaListaModel = ListaModel(
        usuarioId: listaOriginal.usuarioId,
        nomeLista: novoNome,
        valorOrcamento: listaOriginal.valorOrcamento,
        statusLista: 'Planejada',
        dataCriacao: DateTime.now(),
        valorTotalAtual: 0.0,
        servidorId: null,
        flagSincronizado: 0,
      );

      final dadosNovaLista = novaListaModel.toMap();
      dadosNovaLista['servidor_id'] = null;
      dadosNovaLista['flag_sincronizado'] = 0;

      final idNovaLista = await txn.insert(
        'listas',
        dadosNovaLista,
      );

      final novaListaCriada = novaListaModel.copyWith(
        idLista: idNovaLista,
        servidorId: null,
        flagSincronizado: 0,
      );

      // 3. Buscar os itens originais na ordem de criação.
      final itensQuery = await txn.query(
        'itens_lista',
        where: 'lista_id = ?',
        whereArgs: [idListaOriginal],
        orderBy: 'id_item_lista ASC',
      );

      final itensOriginais = itensQuery
          .map((m) => ItemListaModel.fromMap(m))
          .toList();

      // 4. Filtrar os itens fora da lista, conforme a opção selecionada.
      final itensParaCopiar = itensOriginais.where((item) {
        return incluirForaDaLista || !item.flagForaDaLista;
      }).toList();

      // 5. Criar novos registros de itens na nova lista.
      for (final item in itensParaCopiar) {
        final novoItem = item.paraNovaLista(idNovaLista);
        final dadosNovoItem = novoItem.toMap();

        dadosNovoItem['servidor_id'] = null;
        dadosNovoItem['flag_sincronizado'] = 0;

        await txn.insert(
          'itens_lista',
          dadosNovoItem,
        );
      }

      return novaListaCriada;
    });
  }

  // ===========================================================================
  // RECÁLCULO DO TOTAL DA LISTA
  // ===========================================================================

  /// Atualiza o valor_total_atual e marca a lista como pendente de sincronização.
  Future<void> _recalcularTotalLista(
    DatabaseExecutor executor,
    int listaId,
  ) async {
    final itensMap = await executor.query(
      'itens_lista',
      where: 'lista_id = ?',
      whereArgs: [listaId],
    );

    final itens = itensMap
        .map((m) => ItemListaModel.fromMap(m))
        .toList();

    final valorTotalAtual = ListaModel.calcularTotalCarrinho(itens);

    await executor.update(
      'listas',
      {
        'valor_total_atual': valorTotalAtual,
        'flag_sincronizado': 0,
      },
      where: 'id_lista = ?',
      whereArgs: [listaId],
    );
  }

  // ===========================================================================
  // IMPLEMENTAÇÃO DOS MÉTODOS DE CATEGORIAS (T12 / T22 - GLOBAL)
  // ===========================================================================

  @override
  Future<List<Map<String, dynamic>>> listarCategorias() async {
    final db = await _db.database;

    return await db.query(
      'categorias',
      orderBy: 'nome_categoria ASC',
    );
  }

  @override
  Future<int> inserirCategoria(Map<String, dynamic> dados) async {
    final db = await _db.database;

    final novosDados = Map<String, dynamic>.from(dados);
    novosDados['flag_sincronizado'] = 0;

    return await db.insert('categorias', novosDados);
  }

  @override
  Future<int> atualizarCategoria(Map<String, dynamic> dados) async {
    final db = await _db.database;

    final novosDados = Map<String, dynamic>.from(dados);
    novosDados['flag_sincronizado'] = 0;

    return await db.update(
      'categorias',
      novosDados,
      where: 'id_categoria = ?',
      whereArgs: [dados['id_categoria']],
    );
  }

  @override
  Future<bool> verificarCategoriaPodeSerExcluida(int idCategoria) async {
    final db = await _db.database;

    final result = await db.query(
      'produtos',
      where: 'categoria_id = ?',
      whereArgs: [idCategoria],
    );

    return result.isEmpty;
  }

  @override
  Future<int> excluirCategoria(int idCategoria) async {
    final db = await _db.database;

    final result = await db.query(
      'categorias',
      columns: ['id_categoria', 'servidor_id'],
      where: 'id_categoria = ?',
      whereArgs: [idCategoria],
    );

    if (result.isEmpty) return 0;

    final servidorId = result.first['servidor_id'] as int?;

    await _exclusaoRepo.excluirOffline(
      tabela: 'categorias',
      nomeColunaIdLocal: 'id_categoria',
      idLocal: idCategoria,
      servidorId: servidorId,
    );

    return 1;
  }
}