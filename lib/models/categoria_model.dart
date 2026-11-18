/// ============================================================================
/// MODELO DE DADOS — CATEGORIA (GLOBAL E COMPARTILHADA)
/// ============================================================================
/// Representa a entidade Categoria no ecossistema AgiLista Mobile.
/// Conforme a regra de negócio do sistema e Regras de Domínio:
/// - Categorias Padrão: usuarioId == NULL (compartilhadas e inalteráveis pelo usuário).
/// - Categorias Privadas: usuarioId == idDoUsuarioLogado (editáveis e excluíveis).
/// - As categorias possuem cadastro GLOBAL e são compartilhadas entre todos os usuários.
/// 
/// 
class CategoriaModel {
  final int? idCategoria;
  final int? servidorId;
  final int? usuarioId; // NULL = Categoria Padrão Global do Sistema
  final String nomeCategoria;
  final int ativo; // 1 = Ativo, 0 = Inativo
  final String statusCategoria; // 'Ativo' ou 'Inativo'
  final int flagSincronizado;

  CategoriaModel({
    this.idCategoria,
    this.servidorId,
    this.usuarioId,
    required this.nomeCategoria,
    this.ativo = 1,
    this.statusCategoria = 'Ativo',
    this.flagSincronizado = 0,
  });

  // ===========================================================================
  // GETTERS DE REGRA DE NEGÓCIO
  // ===========================================================================

  /// Indica se é uma categoria padrão mestre do sistema (inalterável)
  bool get ehCategoriaPadrao => usuarioId == null;

  /// Indica se o usuário atual tem permissão para editar ou excluir esta categoria
  bool podeEditarOuExcluir(int usuarioAtualId) {
    return !ehCategoriaPadrao && usuarioId == usuarioAtualId;
  }

  // ===========================================================================
  // IMUTABILIDADE & SERIALIZAÇÃO (SQLite)
  // ===========================================================================

  CategoriaModel copyWith({
    int? idCategoria,
    int? servidorId,
    int? usuarioId,
    String? nomeCategoria,
    int? ativo,
    String? statusCategoria,
    int? flagSincronizado,
  }) {
    return CategoriaModel(
      idCategoria: idCategoria ?? this.idCategoria,
      servidorId: servidorId ?? this.servidorId,
      usuarioId: usuarioId ?? this.usuarioId,
      nomeCategoria: nomeCategoria ?? this.nomeCategoria,
      ativo: ativo ?? this.ativo,
      statusCategoria: statusCategoria ?? this.statusCategoria,
      flagSincronizado: flagSincronizado ?? this.flagSincronizado,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idCategoria != null) 'id_categoria': idCategoria,
      'servidor_id': servidorId,
      'usuario_id': usuarioId,
      'nome_categoria': nomeCategoria,
      'ativo': ativo,
      'status_categoria': statusCategoria,
      'flag_sincronizado': flagSincronizado,
    };
  }

  factory CategoriaModel.fromMap(Map<String, dynamic> map) {
    final status = map['status_categoria']?.toString() ?? 'Ativo';
    final isAtivoNum = (map['ativo'] as int?) ?? (status.toUpperCase() == 'ATIVO' ? 1 : 0);

    return CategoriaModel(
      idCategoria: map['id_categoria'] as int?,
      servidorId: map['servidor_id'] as int?,
      usuarioId: map['usuario_id'] as int?,
      nomeCategoria: map['nome_categoria'] as String,
      ativo: isAtivoNum,
      statusCategoria: isAtivoNum == 1 ? 'Ativo' : 'Inativo',
      flagSincronizado: (map['flag_sincronizado'] as int?) ?? 0,
    );
  }
}