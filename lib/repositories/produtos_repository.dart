import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../nucleo/database/app_database.dart';
import 'exclusao_repository.dart';
import '../models/categoria_model.dart';
import '../models/produto_model.dart';

/// ============================================================================
/// REPOSITÓRIO — PRODUTOS E CATEGORIAS (CADASTRO GLOBAL E CENTRALIZADO)
/// ============================================================================
/// Interface abstrata responsável pelas operações de persistência e consulta
/// no catálogo global de produtos e categorias do aplicativo.
/// 
/// Enumeração para os filtros de consulta de categorias
enum FiltroStatusCategoria { todas, ativas, inativas }

abstract class ProdutosRepository {
  // ==================== OPERAÇÕES DE PRODUTOS ====================

  /// Cadastra um novo produto no catálogo global
  Future<ProdutoModel> cadastrarProduto(ProdutoModel produto);

  /// Atualiza os dados cadastrais de um produto no catálogo global
  Future<void> alterarProduto(ProdutoModel produto);

  /// Exclui um produto do catálogo global (se não possuir movimentações)
  Future<void> excluirProduto(int idProduto);

  /// Lista todos os produtos cadastrados no catálogo global com suas categorias
  Future<List<ProdutoModel>> listarTodos();

  /// Localiza um produto no catálogo global pelo seu ID
  Future<ProdutoModel?> buscarPorId(int idProduto);

  /// Localiza um produto no catálogo global pelo seu Código de Barras
  Future<ProdutoModel?> buscarPorCodigoBarras(String codigoBarras);

  /// Realiza a busca reativa de produtos no catálogo por termo/nome
  Future<List<ProdutoModel>> buscarPorNome(String termo);

  // ==================== OPERAÇÕES DE CATEGORIAS ====================

  /// Lista todas as categorias ativas do cadastro global
  Future<List<CategoriaModel>> listarCategorias({
    required int usuarioId,
    FiltroStatusCategoria filtro = FiltroStatusCategoria.todas,
  });

  /// Cadastra uma nova categoria no acervo global do aplicativo
  Future<CategoriaModel> cadastrarCategoria(CategoriaModel categoria);
}

/// ============================================================================
/// IMPLEMENTAÇÃO DO REPOSITÓRIO — SQLITE
/// ============================================================================
/// Implementação concreta utilizando a instância Singleton do AppDatabase.
class ProdutosRepositoryImpl implements ProdutosRepository {
  final AppDatabase _db = AppDatabase.instance;
  final ExclusaoRepository _exclusaoRepo = ExclusaoRepository();

  @override
  Future<ProdutoModel> cadastrarProduto(ProdutoModel produto) async {
    final db = await _db.database;

    // Regra de Negócio: Verifica se o código de barras já existe no acervo global
    if (produto.codigoBarras != null && produto.codigoBarras!.isNotEmpty) {
      final existente = await buscarPorCodigoBarras(produto.codigoBarras!);
      if (existente != null && existente.idProduto != produto.idProduto) {
        throw Exception('Já existe um produto com este código de barras.');
      }
    }

    final dados = produto.toMap();
    dados['flag_sincronizado'] = 0;

    // Insere o produto no cadastro global sem vinculação restritiva a usuário
    final idInserido = await db.insert('produtos', dados);
    return produto.copyWith(idProduto: idInserido, flagSincronizado: 0);
  }

  @override
  Future<void> alterarProduto(ProdutoModel produto) async {
    final db = await _db.database;

    final dados = produto.toMap();
    dados['flag_sincronizado'] = 0;

    await db.update(
      'produtos',
      dados,
      where: 'id_produto = ?',
      whereArgs: [produto.idProduto],
    );
  }

  @override
  Future<void> excluirProduto(int idProduto) async {
    final db = await _db.database;

    // Regra de Negócio: Não permite excluir produto com histórico em listas de compras
    final result = await db.rawQuery(
      'SELECT COUNT(*) as total FROM itens_lista WHERE produto_id = ?',
      [idProduto],
    );

    final int movimentacoes = (result.first['total'] as num?)?.toInt() ?? 0;

    if (movimentacoes > 0) {
      throw Exception(
        'Não é possível excluir um produto que possui histórico de compras.',
      );
    }

    // Busca o produto para resgatar o servidor_id antes da remoção
    final produto = await buscarPorId(idProduto);
    if (produto == null) return;

    // Delegação da exclusão para o ExclusaoRepository (Soft Delete + Fila de pendências)
    await _exclusaoRepo.excluirOffline(
      tabela: 'produtos',
      nomeColunaIdLocal: 'id_produto',
      idLocal: idProduto,
      servidorId: produto.servidorId,
    );
  }

  @override
  Future<List<ProdutoModel>> listarTodos() async {
    final db = await _db.database;

    // Consulta global ordenada alfabeticamente
    final result = await db.rawQuery('''
      SELECT p.*, c.nome_categoria, c.status_categoria, c.usuario_id AS cat_usuario_id
      FROM produtos p
      INNER JOIN categorias c ON p.categoria_id = c.id_categoria
      ORDER BY p.nome_produto ASC
    ''');

    return result.map((map) {
      final categoria = CategoriaModel.fromMap(map);
      return ProdutoModel.fromMap(map, categoria: categoria);
    }).toList();
  }

  @override
  Future<ProdutoModel?> buscarPorId(int idProduto) async {
    final db = await _db.database;

    final result = await db.rawQuery('''
      SELECT p.*, c.nome_categoria, c.status_categoria, c.usuario_id AS cat_usuario_id
      FROM produtos p
      INNER JOIN categorias c ON p.categoria_id = c.id_categoria
      WHERE p.id_produto = ?
    ''', [idProduto]);

    if (result.isNotEmpty) {
      final map = result.first;
      return ProdutoModel.fromMap(map, categoria: CategoriaModel.fromMap(map));
    }
    return null;
  }

  @override
  Future<ProdutoModel?> buscarPorCodigoBarras(String codigoBarras) async {
    final db = await _db.database;

    // Busca global por Código de Barras (EAN/UPC)
    final result = await db.rawQuery('''
      SELECT p.*, c.nome_categoria, c.status_categoria, c.usuario_id AS cat_usuario_id
      FROM produtos p
      INNER JOIN categorias c ON p.categoria_id = c.id_categoria
      WHERE p.codigo_barras = ?
    ''', [codigoBarras]);

    if (result.isNotEmpty) {
      final map = result.first;
      return ProdutoModel.fromMap(map, categoria: CategoriaModel.fromMap(map));
    }
    return null;
  }

  @override
  Future<List<ProdutoModel>> buscarPorNome(String termo) async {
    final db = await _db.database;

    // Busca global por aproximação no nome do produto
    final result = await db.rawQuery('''
      SELECT p.*, c.nome_categoria, c.status_categoria, c.usuario_id AS cat_usuario_id
      FROM produtos p
      INNER JOIN categorias c ON p.categoria_id = c.id_categoria
      WHERE p.nome_produto LIKE ?
      ORDER BY p.nome_produto ASC
    ''', ['%$termo%']);

    return result.map((map) {
      return ProdutoModel.fromMap(map, categoria: CategoriaModel.fromMap(map));
    }).toList();
  }

  @override
  Future<List<CategoriaModel>> listarCategorias({
    required int usuarioId,
    FiltroStatusCategoria filtro = FiltroStatusCategoria.todas,
  }) async {
    final db = await _db.database;

    // Traz Categorias Padrão (usuario_id IS NULL) + Categorias do Usuário Logado
    String whereClause = '(usuario_id IS NULL OR usuario_id = ?)';
    List<dynamic> whereArgs = [usuarioId];

    if (filtro == FiltroStatusCategoria.ativas) {
      whereClause += " AND (status_categoria = 'Ativo' OR status_categoria = 'ATIVO' OR ativo = 1)";
    } else if (filtro == FiltroStatusCategoria.inativas) {
      whereClause += " AND (status_categoria = 'Inativo' OR status_categoria = 'INATIVO' OR ativo = 0)";
    }

    final result = await db.query(
      'categorias',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'nome_categoria ASC',
    );

    return result.map((map) => CategoriaModel.fromMap(map)).toList();
  }

  @override
  Future<CategoriaModel> cadastrarCategoria(CategoriaModel categoria) async {
    final db = await _db.database;

    // Regra de Trava: impede salvar/editar como padrão localmente
    if (categoria.ehCategoriaPadrao && categoria.idCategoria != null) {
      throw Exception('As categorias padrões do sistema são somente leitura.');
    }

    final dados = categoria.toMap();
    dados['flag_sincronizado'] = 0;

    if (categoria.idCategoria == null) {
      final idInserido = await db.insert('categorias', dados);
      return categoria.copyWith(idCategoria: idInserido, flagSincronizado: 0);
    } else {
      await db.update(
        'categorias',
        dados,
        where: 'id_categoria = ?',
        whereArgs: [categoria.idCategoria],
      );
      return categoria.copyWith(flagSincronizado: 0);
    }
  }
}

/// ============================================================================
/// PROVIDER GLOBAL RIVERPOD
/// ============================================================================
/// Fornece acesso estático e injetável à instância concreta do repositório.
final produtosRepositoryProvider = Provider<ProdutosRepository>((ref) {
  return ProdutosRepositoryImpl();
});