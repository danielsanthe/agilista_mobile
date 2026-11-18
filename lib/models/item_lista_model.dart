
import '../nucleo/constantes/status_constants.dart';
import 'produto_model.dart';

/// ============================================================================
/// MODELO DE DADOS — ITEM DA LISTA DE COMPRAS
/// ============================================================================
/// Representa um item individual em uma lista de compras, com suporte a regras
/// de promoção (F09), replicação de listas e acompanhamento de status.
class ItemListaModel {
  final int? idItemLista;
  final int? servidorId;
  final int listaId;
  final int? produtoId;
  final ProdutoModel? produto;
  final String nomeItemPlanejado;
  final double qtdPlanejada;
  final double precoEstimado;
  final double qtdComprada;
  final double precoUnitario;
  final String statusItem;
  final bool flagPromocao;
  final double? qtdMinimaPromocional;
  final double? precoPromocional;
  final bool flagForaDaLista;

  /// 0 = pendente de sincronização
  /// 1 = sincronizado com o servidor
  final int flagSincronizado;

  ItemListaModel({
    this.idItemLista,
    this.servidorId,
    required this.listaId,
    this.produtoId,
    this.produto,
    required this.nomeItemPlanejado,
    this.qtdPlanejada = 1.0,
    this.precoEstimado = 0.0,
    this.qtdComprada = 0.0,
    this.precoUnitario = 0.0,
    this.statusItem = StatusItem.pendente,
    this.flagPromocao = false,
    this.qtdMinimaPromocional,
    this.precoPromocional,
    this.flagForaDaLista = false,
    this.flagSincronizado = 0,
  });

  /// Nome exibido no carrinho.
  /// Prioriza o nome oficial do produto, caso esteja vinculado.
  String get nomeExibicaoCarrinho {
    if (produto != null && produto!.nomeProduto.trim().isNotEmpty) {
      return produto!.nomeProduto;
    }
    return nomeItemPlanejado;
  }

  /// Calcula o subtotal do item.
  double get subtotalItem {
    if (statusItem == StatusItem.pendente) {
      return 0.0;
    }

    // Promoção por quantidade (F09).
    // Preço promocional igual a zero também é válido.
    if (flagPromocao &&
        qtdMinimaPromocional != null &&
        qtdMinimaPromocional! > 0 &&
        precoPromocional != null &&
        qtdComprada >= qtdMinimaPromocional!) {
      return qtdComprada * precoPromocional!;
    }

    return qtdComprada * precoUnitario;
  }

  // ===========================================================================
  // MÉTODOS DE NEGÓCIO
  // ===========================================================================

  ItemListaModel adicionarItem() {
    return copyWith(
      statusItem: StatusItem.pendente,
      flagSincronizado: 0,
    );
  }

  ItemListaModel registrarCompraItem({
    required double qtd,
    required double preco,
  }) {
    return copyWith(
      qtdComprada: qtd,
      precoUnitario: preco,
      statusItem: StatusItem.comprado,
      flagSincronizado: 0,
    );
  }

  ItemListaModel aplicarPromocaoQuantidade({
    required double qtdMinima,
    required double precoPromo,
  }) {
    return copyWith(
      flagPromocao: true,
      qtdMinimaPromocional: qtdMinima,
      precoPromocional: precoPromo,
      flagSincronizado: 0,
    );
  }

  /// Gera um item novo para replicação em outra lista.
  /// Preserva descrição, quantidade planejada e preço estimado.
  /// O produto só é vinculado durante a compra.
  /// O novo item começa pendente e sem vínculo com o servidor.
  ItemListaModel paraNovaLista(int novaListaId) {
    return ItemListaModel(
      servidorId: null,
      listaId: novaListaId,
      produtoId: null,
      produto: null,
      nomeItemPlanejado: nomeItemPlanejado,
      qtdPlanejada: qtdPlanejada,
      precoEstimado: precoUnitario > 0 ? precoUnitario : precoEstimado,
      statusItem: StatusItem.pendente,
      flagForaDaLista: false,
      qtdComprada: 0.0,
      precoUnitario: 0.0,
      flagPromocao: false,
      qtdMinimaPromocional: null,
      precoPromocional: null,
      flagSincronizado: 0,
    );
  }

  // ===========================================================================
  // IMUTABILIDADE E SERIALIZAÇÃO (SQLite)
  // ===========================================================================

  ItemListaModel copyWith({
    int? idItemLista,
    int? servidorId,
    int? listaId,
    int? produtoId,
    ProdutoModel? produto,
    String? nomeItemPlanejado,
    double? qtdPlanejada,
    double? precoEstimado,
    double? qtdComprada,
    double? precoUnitario,
    String? statusItem,
    bool? flagPromocao,
    double? qtdMinimaPromocional,
    double? precoPromocional,
    bool? flagForaDaLista,
    int? flagSincronizado,
  }) {
    return ItemListaModel(
      idItemLista: idItemLista ?? this.idItemLista,
      servidorId: servidorId ?? this.servidorId,
      listaId: listaId ?? this.listaId,
      produtoId: produtoId ?? this.produtoId,
      produto: produto ?? this.produto,
      nomeItemPlanejado: nomeItemPlanejado ?? this.nomeItemPlanejado,
      qtdPlanejada: qtdPlanejada ?? this.qtdPlanejada,
      precoEstimado: precoEstimado ?? this.precoEstimado,
      qtdComprada: qtdComprada ?? this.qtdComprada,
      precoUnitario: precoUnitario ?? this.precoUnitario,
      statusItem: statusItem ?? this.statusItem,
      flagPromocao: flagPromocao ?? this.flagPromocao,
      qtdMinimaPromocional:
          qtdMinimaPromocional ?? this.qtdMinimaPromocional,
      precoPromocional: precoPromocional ?? this.precoPromocional,
      flagForaDaLista: flagForaDaLista ?? this.flagForaDaLista,
      flagSincronizado: flagSincronizado ?? this.flagSincronizado,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idItemLista != null) 'id_item_lista': idItemLista,
      'servidor_id': servidorId,
      'lista_id': listaId,
      'produto_id': produtoId ?? produto?.idProduto,
      'nome_item_planejado': nomeItemPlanejado,
      'qtd_planejada': qtdPlanejada,
      'preco_estimado': precoEstimado,
      'qtd_comprada': qtdComprada,
      'preco_unitario': precoUnitario,
      'subtotal_item': subtotalItem,
      'status_item': statusItem,
      'flag_promocao': flagPromocao ? 1 : 0,
      'qtd_minima_promocional': qtdMinimaPromocional,
      'preco_promocional': precoPromocional,
      'flag_fora_da_lista': flagForaDaLista ? 1 : 0,
      'flag_sincronizado': flagSincronizado,
    };
  }

  factory ItemListaModel.fromMap(
    Map<String, dynamic> map, {
    ProdutoModel? produto,
  }) {
    return ItemListaModel(
      idItemLista: map['id_item_lista'] as int?,
      servidorId: map['servidor_id'] as int?,
      listaId: map['lista_id'] as int,
      produtoId: map['produto_id'] as int?,
      produto: produto,
      nomeItemPlanejado: map['nome_item_planejado'] as String,
      qtdPlanejada: (map['qtd_planejada'] as num?)?.toDouble() ?? 1.0,
      precoEstimado: (map['preco_estimado'] as num?)?.toDouble() ?? 0.0,
      qtdComprada: (map['qtd_comprada'] as num?)?.toDouble() ?? 0.0,
      precoUnitario: (map['preco_unitario'] as num?)?.toDouble() ?? 0.0,
      statusItem: map['status_item'] as String? ?? StatusItem.pendente,
      flagPromocao: (map['flag_promocao'] as int?) == 1,
      qtdMinimaPromocional:
          (map['qtd_minima_promocional'] as num?)?.toDouble(),
      precoPromocional: (map['preco_promocional'] as num?)?.toDouble(),
      flagForaDaLista: (map['flag_fora_da_lista'] as int?) == 1,
      flagSincronizado: map['flag_sincronizado'] as int? ?? 0,
    );
  }
}
