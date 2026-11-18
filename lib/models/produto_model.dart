import 'categoria_model.dart';

/// ============================================================================
/// MODELO DE DADOS — PRODUTO (GLOBAL E REUTILIZÁVEL)
/// ============================================================================
/// Representa a entidade Produto no ecossistema AgiLista Mobile.
/// Conforme a regra de negócio do sistema:
/// - Os produtos possuem cadastro GLOBAL, compartilhado por todos os usuários
///   e reutilizável em diferentes listas de compras.
/// - Todo produto deve estar vinculado obrigatoriamente a uma categoria_id válida.
class ProdutoModel {
  /// Identificador único do produto no banco SQLite (PK)
  final int? idProduto;

  /// Identificador único (id_produto_usuario) gerado pelo servidor FastAPI
  final int? servidorId;

  /// Identificador do usuário proprietário do registro
  final int? usuarioId;

  /// Vínculo opcional com a tabela de produtos globais do servidor
  final int? produtoGlobalId;

  /// Chave estrangeira para a categoria associada (FK)
  final int categoriaId;

  /// Objeto da categoria populado em consultas com JOIN
  final CategoriaModel? categoria;

  /// Código de barras opcional (EAN/UPC) utilizado na busca por câmera ou scanner
  final String? codigoBarras;

  /// Descrição ou nome do produto
  final String nomeProduto;

  /// Unidade de medida padrão do produto ('Un', 'Kg', 'L', 'Pacote', etc.)
  final String unidadeMedida;

  /// Sinaliza se o produto é de compra frequente/recorrente
  final bool flagProdutoRecorrente;

  /// 0 = pendente de envio para o servidor / 1 = sincronizado
  final int flagSincronizado;

  ProdutoModel({
    this.idProduto,
    this.servidorId,
    this.usuarioId,
    this.produtoGlobalId,
    required this.categoriaId,
    this.categoria,
    this.codigoBarras,
    required this.nomeProduto,
    this.unidadeMedida = 'Un',
    this.flagProdutoRecorrente = false,
    this.flagSincronizado = 0,
  });

  // ===========================================================================
  // MÉTODOS DE NEGÓCIO (Diagrama de Classes UML & Regras de Domínio)
  // ===========================================================================

  /// Retorna a instância atual preparada para inclusão no catálogo global
  ProdutoModel cadastrarProduto() {
    return this;
  }

  /// Altera as informações cadastrais do produto mantendo imutabilidade
  /// Marca automaticamente flagSincronizado = 0 para pendência de sync
  ProdutoModel alterarProduto({
    String? novoNome,
    int? novaCategoriaId,
    String? novoCodigoBarras,
    String? novaUnidadeMedida,
    bool? novaFlagRecorrente,
  }) {
    return copyWith(
      nomeProduto: novoNome,
      categoriaId: novaCategoriaId,
      codigoBarras: novoCodigoBarras,
      unidadeMedida: novaUnidadeMedida,
      flagProdutoRecorrente: novaFlagRecorrente,
      flagSincronizado: 0,
    );
  }

  /// Regra de Negócio: Verifica se o produto pode ser excluído do catálogo.
  /// Só é permitida a exclusão se não houver vinculação prévia com itens de lista.
  bool podeSerExcluido(int quantidadeDeUsoEmItens) {
    return quantidadeDeUsoEmItens == 0;
  }

  /// Marca ou desmarca o produto como item de compra recorrente
  ProdutoModel marcarRecorrente({required bool eRecorrente}) {
    return copyWith(
      flagProdutoRecorrente: eRecorrente,
      flagSincronizado: 0,
    );
  }

  // ===========================================================================
  // IMUTABILIDADE & SERIALIZAÇÃO (SQLite & API DTOs)
  // ===========================================================================

  /// Gera uma nova instância modificando apenas os campos especificados
  ProdutoModel copyWith({
    int? idProduto,
    int? servidorId,
    int? usuarioId,
    int? produtoGlobalId,
    int? categoriaId,
    CategoriaModel? categoria,
    String? codigoBarras,
    String? nomeProduto,
    String? unidadeMedida,
    bool? flagProdutoRecorrente,
    int? flagSincronizado,
  }) {
    return ProdutoModel(
      idProduto: idProduto ?? this.idProduto,
      servidorId: servidorId ?? this.servidorId,
      usuarioId: usuarioId ?? this.usuarioId,
      produtoGlobalId: produtoGlobalId ?? this.produtoGlobalId,
      categoriaId: categoriaId ?? this.categoriaId,
      categoria: categoria ?? this.categoria,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      nomeProduto: nomeProduto ?? this.nomeProduto,
      unidadeMedida: unidadeMedida ?? this.unidadeMedida,
      flagProdutoRecorrente: flagProdutoRecorrente ?? this.flagProdutoRecorrente,
      flagSincronizado: flagSincronizado ?? this.flagSincronizado,
    );
  }

  /// Converte a instância em um Map para inclusão/atualização na tabela 'produtos' no SQLite local
  Map<String, dynamic> toMap() {
    return {
      if (idProduto != null) 'id_produto': idProduto,
      'servidor_id': servidorId,
      'categoria_id': categoriaId,
      'codigo_barras': (codigoBarras != null && codigoBarras!.trim().isNotEmpty)
          ? codigoBarras!.trim()
          : null,
      'nome_produto': nomeProduto.trim(),
      'unidade_medida': unidadeMedida.trim().isEmpty ? 'Un' : unidadeMedida.trim(),
      'flag_produto_recorrente': flagProdutoRecorrente ? 1 : 0,
      'flag_sincronizado': flagSincronizado,
    };
  }

  /// Constrói a instância a partir de uma consulta no SQLite local
  factory ProdutoModel.fromMap(Map<String, dynamic> map, {CategoriaModel? categoria}) {
    return ProdutoModel(
      idProduto: map['id_produto'] as int?,
      servidorId: map['servidor_id'] as int?,
      categoriaId: map['categoria_id'] as int,
      categoria: categoria,
      codigoBarras: map['codigo_barras'] as String?,
      nomeProduto: map['nome_produto'] as String,
      unidadeMedida: map['unidade_medida'] as String? ?? 'Un',
      flagProdutoRecorrente: (map['flag_produto_recorrente'] as int?) == 1,
      flagSincronizado: (map['flag_sincronizado'] as int?) ?? 0,
    );
  }

  /// Converte o Map vindo da API FastAPI (ProdutoUsuarioResponse) em ProdutoModel
  factory ProdutoModel.fromApiJson(Map<String, dynamic> json, {CategoriaModel? categoria}) {
    return ProdutoModel(
      servidorId: json['id_produto_usuario'] as int?,
      usuarioId: json['usuario_id'] as int?,
      produtoGlobalId: json['produto_global_id'] as int?,
      categoriaId: json['categoria_id'] as int,
      categoria: categoria,
      codigoBarras: json['codigo_barras'] as String?,
      nomeProduto: json['nome_produto'] as String,
      unidadeMedida: json['unidade_medida'] as String? ?? 'Un',
      flagProdutoRecorrente: (json['flag_produto_recorrente'] as int?) == 1,
      flagSincronizado: 1,
    );
  }

  // ===========================================================================
  // MÉTODOS ESTÁTICOS DE CONSULTA (Suporte a Buscas Locais em Memória)
  // ===========================================================================

  /// Busca um produto na lista em memória através da correspondência exata do Código de Barras
  static ProdutoModel? buscarPorCodigoBarras(List<ProdutoModel> produtos, String codigo) {
    try {
      return produtos.firstWhere((p) => p.codigoBarras == codigo);
    } catch (_) {
      return null;
    }
  }

  /// Filtra produtos na memória cujo nome contenha o termo pesquisado (Case-insensitive)
  static List<ProdutoModel> buscarPorNome(List<ProdutoModel> produtos, String termo) {
    return produtos
        .where((p) => p.nomeProduto.toLowerCase().contains(termo.toLowerCase()))
        .toList();
  }

  /// Localiza um produto na memória pelo seu ID único
  static ProdutoModel? buscarPorId(List<ProdutoModel> produtos, int id) {
    try {
      return produtos.firstWhere((p) => p.idProduto == id);
    } catch (_) {
      return null;
    }
  }
}