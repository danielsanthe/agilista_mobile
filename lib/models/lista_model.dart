
import '../nucleo/constantes/status_constants.dart';
import 'usuario_model.dart';
import 'item_lista_model.dart';

/// ============================================================================
/// MODELO DE DADOS — LISTA DE COMPRAS
/// ============================================================================
/// Representa uma lista de compras no sistema AgiLista.
class ListaModel {
  final int? idLista;
  final int? servidorId;
  final int usuarioId;
  final UsuarioModel? usuario;
  final String nomeLista;
  final double valorOrcamento;
  final double valorTotalAtual;
  final String statusLista;
  final String? nomeEstabelecimento;
  final String? enderecoEstabelecimento;
  final String? bairro;
  final String? cidade;
  final String? uf;
  final DateTime dataCriacao;
  final DateTime? dataHoraInicio;
  final DateTime? dataHoraTermino;

  /// 0 = pendente de sincronização
  /// 1 = sincronizada com o servidor
  final int flagSincronizado;

  ListaModel({
    this.idLista,
    this.servidorId,
    required this.usuarioId,
    this.usuario,
    required this.nomeLista,
    required this.valorOrcamento,
    this.valorTotalAtual = 0.0,
    this.statusLista = StatusLista.planejada,
    this.nomeEstabelecimento,
    this.enderecoEstabelecimento,
    this.bairro,
    this.cidade,
    this.uf,
    required this.dataCriacao,
    this.dataHoraInicio,
    this.dataHoraTermino,
    this.flagSincronizado = 0,
  });

  // ===========================================================================
  // MÉTODOS DE NEGÓCIO (Diagrama de Classes UML)
  // ===========================================================================

  /// Calcula a soma dos subtotais dos itens no carrinho.
  static double calcularTotalCarrinho(List<ItemListaModel> itens) {
    return itens.fold(0.0, (total, item) => total + item.subtotalItem);
  }

  /// F11 — Controlar Orçamento em Tempo Real.
  /// Retorna 'Dentro do Limite', 'Próximo do Limite' ou 'Excedido'.
  String verificarSituacaoOrcamento() {
    if (valorOrcamento <= 0) return 'Dentro do Limite';

    final percentualGasto = (valorTotalAtual / valorOrcamento) * 100;

    if (percentualGasto > 100) {
      return 'Excedido';
    } else if (percentualGasto >= 80) {
      return 'Próximo do Limite';
    } else {
      return 'Dentro do Limite';
    }
  }

  /// Retorna o saldo restante do orçamento.
  double get saldoRestanteOrcamento => valorOrcamento - valorTotalAtual;

  /// F05 — Iniciar Compra e Registrar Localização do Estabelecimento.
  ListaModel iniciarCompra({
    required String estabelecimento,
    String? endereco,
    String? bairro,
    String? cidade,
    String? uf,
  }) {
    return copyWith(
      statusLista: StatusLista.emAndamento,
      nomeEstabelecimento: estabelecimento,
      enderecoEstabelecimento: endereco,
      bairro: bairro,
      cidade: cidade,
      uf: uf,
      dataHoraInicio: DateTime.now(),
      flagSincronizado: 0,
    );
  }

  /// F12 — Finalizar e Encerrar Compra.
  ListaModel finalizarCompra() {
    return copyWith(
      statusLista: StatusLista.concluida,
      dataHoraTermino: DateTime.now(),
      flagSincronizado: 0,
    );
  }

  /// F18 — Replicar Lista de Compras.
  /// Gera uma nova lista, sem ID local ou remoto, planejada
  /// e pendente de sincronização.
  ListaModel replicarLista({required String novoNome}) {
    return ListaModel(
      idLista: null,
      servidorId: null,
      usuarioId: usuarioId,
      usuario: usuario,
      nomeLista: novoNome,
      valorOrcamento: valorOrcamento,
      valorTotalAtual: 0.0,
      statusLista: StatusLista.planejada,
      nomeEstabelecimento: null,
      enderecoEstabelecimento: null,
      bairro: null,
      cidade: null,
      uf: null,
      dataCriacao: DateTime.now(),
      dataHoraInicio: null,
      dataHoraTermino: null,
      flagSincronizado: 0,
    );
  }

  // ===========================================================================
  // IMUTABILIDADE & SERIALIZAÇÃO (SQLite)
  // ===========================================================================

  ListaModel copyWith({
    int? idLista,
    int? servidorId,
    int? usuarioId,
    UsuarioModel? usuario,
    String? nomeLista,
    double? valorOrcamento,
    double? valorTotalAtual,
    String? statusLista,
    String? nomeEstabelecimento,
    String? enderecoEstabelecimento,
    String? bairro,
    String? cidade,
    String? uf,
    DateTime? dataCriacao,
    DateTime? dataHoraInicio,
    DateTime? dataHoraTermino,
    int? flagSincronizado,
  }) {
    return ListaModel(
      idLista: idLista ?? this.idLista,
      servidorId: servidorId ?? this.servidorId,
      usuarioId: usuarioId ?? this.usuarioId,
      usuario: usuario ?? this.usuario,
      nomeLista: nomeLista ?? this.nomeLista,
      valorOrcamento: valorOrcamento ?? this.valorOrcamento,
      valorTotalAtual: valorTotalAtual ?? this.valorTotalAtual,
      statusLista: statusLista ?? this.statusLista,
      nomeEstabelecimento: nomeEstabelecimento ?? this.nomeEstabelecimento,
      enderecoEstabelecimento:
          enderecoEstabelecimento ?? this.enderecoEstabelecimento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      uf: uf ?? this.uf,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataHoraInicio: dataHoraInicio ?? this.dataHoraInicio,
      dataHoraTermino: dataHoraTermino ?? this.dataHoraTermino,
      flagSincronizado: flagSincronizado ?? this.flagSincronizado,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idLista != null) 'id_lista': idLista,
      'servidor_id': servidorId,
      'usuario_id': usuarioId,
      'nome_lista': nomeLista,
      'valor_orcamento': valorOrcamento,
      'valor_total_atual': valorTotalAtual,
      'status_lista': statusLista,
      'nome_estabelecimento': nomeEstabelecimento,
      'endereco_estabelecimento': enderecoEstabelecimento,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'data_criacao': dataCriacao.toIso8601String(),
      'data_hora_inicio': dataHoraInicio?.toIso8601String(),
      'data_hora_termino': dataHoraTermino?.toIso8601String(),
      'flag_sincronizado': flagSincronizado,
    };
  }

  factory ListaModel.fromMap(
    Map<String, dynamic> map, {
    UsuarioModel? usuario,
  }) {
    return ListaModel(
      idLista: map['id_lista'] as int?,
      servidorId: map['servidor_id'] as int?,
      usuarioId: map['usuario_id'] as int,
      usuario: usuario,
      nomeLista: map['nome_lista'] as String,
      valorOrcamento: (map['valor_orcamento'] as num).toDouble(),
      valorTotalAtual:
          (map['valor_total_atual'] as num?)?.toDouble() ?? 0.0,
      statusLista: map['status_lista'] as String? ?? StatusLista.planejada,
      nomeEstabelecimento: map['nome_estabelecimento'] as String?,
      enderecoEstabelecimento: map['endereco_estabelecimento'] as String?,
      bairro: map['bairro'] as String?,
      cidade: map['cidade'] as String?,
      uf: map['uf'] as String?,
      dataCriacao: DateTime.parse(map['data_criacao'] as String),
      dataHoraInicio: map['data_hora_inicio'] != null
          ? DateTime.parse(map['data_hora_inicio'] as String)
          : null,
      dataHoraTermino: map['data_hora_termino'] != null
          ? DateTime.parse(map['data_hora_termino'] as String)
          : null,
      flagSincronizado: map['flag_sincronizado'] as int? ?? 0,
    );
  }
}
