/// ============================================================================
/// MODELO DE DADOS: USUÁRIO (OFFLINE-FIRST)
/// ============================================================================
/// Representa a entidade Usuário na camada de modelo da aplicação Flutter.
/// 
/// Regras de Arquitetura Aplicadas:
/// - Mapeia todas as colunas da tabela `usuarios` no SQLite local (versão 5).
/// - Contém suporte à sincronização cloud via `servidorId` e `flagSincronizado`.
/// - Armazena a geolocalização do perfil do usuário (`bairro`, `cidade`, `uf`) 
///   usada no comparador de preços regional.
/// - Implementa imutabilidade com o padrão `copyWith`.
class UsuarioModel {
  /// Identificador único local do usuário (Chave Primária do SQLite)
  final int? idUsuario;

  /// Identificador único do usuário no servidor PostgreSQL / FastAPI (Cloud)
  final int? servidorId;

  /// Nome completo do usuário registrado no sistema
  final String nomeUsuario;

  /// Endereço de e-mail único do usuário (usado para login e autenticação)
  final String email;

  /// Hash criptográfico da senha do usuário para verificação de acesso
  final String senhaHash;

  /// Cadastro de Pessoa Física (CPF) do usuário
  final String? cpf;

  /// Número de telefone celular ou WhatsApp de contato
  final String? telefone;

  /// Código de Endereçamento Postal (CEP) do usuário
  final String? cep;

  /// Nome da rua, avenida ou logradouro residencial
  final String? logradouro;

  /// Número do imóvel ou complemento residencial
  final String? numero;

  /// Bairro do usuário (utilizado no agrupadore regional de preços)
  final String? bairro;

  /// Cidade do usuário (utilizada no filtro regional de estabelecimentos)
  final String? cidade;

  /// Unidade Federativa / Estado do usuário (ex: 'PI', 'MA', 'SP')
  final String? uf;

  /// Tipo do plano assinado pelo usuário (ex: 'FreeTrial', 'Premium')
  final String tipoPlano;

  /// Sinalizador que indica se as alterações locais foram enviadas para o servidor
  /// true = Dados sincronizados | false = Pendente de envio ao backend
  final bool flagSincronizado;

  /// Data e hora da criação da conta do usuário no sistema
  final DateTime dataCadastro;

  /// Data e hora do último evento de sincronização com o banco de dados na nuvem
  final DateTime? ultimaSincronizacao;

  /// Construtor padrão da classe UsuarioModel
  UsuarioModel({
    this.idUsuario,
    this.servidorId,
    required this.nomeUsuario,
    required this.email,
    required this.senhaHash,
    this.cpf,
    this.telefone,
    this.cep,
    this.logradouro,
    this.numero,
    this.bairro,
    this.cidade,
    this.uf,
    this.tipoPlano = 'FreeTrial',
    this.flagSincronizado = false,
    required this.dataCadastro,
    this.ultimaSincronizacao,
  });

  // ===========================================================================
  // MÉTODOS DE NEGÓCIO E AUTENTICAÇÃO (Diagrama de Classes UML)
  // ===========================================================================

  /// Retorna a própria instância para efetivar a preparação do cadastro local.
  UsuarioModel cadastrarUsuario() {
    return this;
  }

  /// Autentica o acesso do usuário no app comparando a senha informada
  /// com o hash da senha armazenada na instância.
  bool autenticar(String senhaDigitada) {
    return senhaHash == senhaDigitada;
  }

  /// Atualiza as informações do perfil do usuário mantendo a imutabilidade do objeto.
  UsuarioModel atualizarPerfil({
    String? novoNome,
    String? novoEmail,
    String? novaSenhaHash,
    String? novoCpf,
    String? novoTelefone,
    String? novoCep,
    String? novoLogradouro,
    String? novoNumero,
    String? novoBairro,
    String? novaCidade,
    String? novoUf,
    String? novoTipoPlano,
    bool? novaFlagSincronizado,
    DateTime? novaUltimaSincronizacao,
  }) {
    return copyWith(
      nomeUsuario: novoNome,
      email: novoEmail,
      senhaHash: novaSenhaHash,
      cpf: novoCpf,
      telefone: novoTelefone,
      cep: novoCep,
      logradouro: novoLogradouro,
      numero: novoNumero,
      bairro: novoBairro,
      cidade: novaCidade,
      uf: novoUf,
      tipoPlano: novoTipoPlano,
      flagSincronizado: novaFlagSincronizado,
      ultimaSincronizacao: novaUltimaSincronizacao,
    );
  }

  // ===========================================================================
  // IMUTABILIDADE & SERIALIZAÇÃO (SQLite / JSON)
  // ===========================================================================

  /// Cria uma nova cópia do objeto permitindo a substituição seletiva de atributos.
  UsuarioModel copyWith({
    int? idUsuario,
    int? servidorId,
    String? nomeUsuario,
    String? email,
    String? senhaHash,
    String? cpf,
    String? telefone,
    String? cep,
    String? logradouro,
    String? numero,
    String? bairro,
    String? cidade,
    String? uf,
    String? tipoPlano,
    bool? flagSincronizado,
    DateTime? dataCadastro,
    DateTime? ultimaSincronizacao,
  }) {
    return UsuarioModel(
      idUsuario: idUsuario ?? this.idUsuario,
      servidorId: servidorId ?? this.servidorId,
      nomeUsuario: nomeUsuario ?? this.nomeUsuario,
      email: email ?? this.email,
      senhaHash: senhaHash ?? this.senhaHash,
      cpf: cpf ?? this.cpf,
      telefone: telefone ?? this.telefone,
      cep: cep ?? this.cep,
      logradouro: logradouro ?? this.logradouro,
      numero: numero ?? this.numero,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      uf: uf ?? this.uf,
      tipoPlano: tipoPlano ?? this.tipoPlano,
      flagSincronizado: flagSincronizado ?? this.flagSincronizado,
      dataCadastro: dataCadastro ?? this.dataCadastro,
      ultimaSincronizacao: ultimaSincronizacao ?? this.ultimaSincronizacao,
    );
  }

  /// Converte a instância do objeto para um [Map] compatível com inserção/atualização no SQLite.
  /// 
  /// Nota: Converte a [flagSincronizado] (bool) em número inteiro (1 ou 0) 
  /// e datas [DateTime] no formato padrão ISO-8601 String.
  Map<String, dynamic> toMap() {
    return {
      if (idUsuario != null) 'id_usuario': idUsuario,
      'servidor_id': servidorId,
      'nome_usuario': nomeUsuario,
      'email': email,
      'senha_hash': senhaHash,
      'cpf': cpf,
      'telefone': telefone,
      'cep': cep,
      'logradouro': logradouro,
      'numero': numero,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'tipo_plano': tipoPlano,
      'flag_sincronizado': flagSincronizado ? 1 : 0,
      'data_cadastro': dataCadastro.toIso8601String(),
      'ultima_sincronizacao': ultimaSincronizacao?.toIso8601String(),
    };
  }

  /// Constrói uma nova instância do [UsuarioModel] a partir de um [Map] retornado pelo SQLite.
  /// 
  /// Transforma inteiros do SQLite (1 e 0) para [bool] e Strings de data ISO-8601 para [DateTime].
  factory UsuarioModel.fromMap(Map<String, dynamic> map) {
    return UsuarioModel(
      idUsuario: map['id_usuario'] as int?,
      servidorId: map['servidor_id'] as int?,
      nomeUsuario: map['nome_usuario'] as String,
      email: map['email'] as String,
      senhaHash: map['senha_hash'] as String,
      cpf: map['cpf'] as String?,
      telefone: map['telefone'] as String?,
      cep: map['cep'] as String?,
      logradouro: map['logradouro'] as String?,
      numero: map['numero'] as String?,
      bairro: map['bairro'] as String?,
      cidade: map['cidade'] as String?,
      uf: map['uf'] as String?,
      tipoPlano: map['tipo_plano'] as String? ?? 'FreeTrial',
      flagSincronizado: (map['flag_sincronizado'] as int? ?? 0) == 1,
      dataCadastro: DateTime.parse(map['data_cadastro'] as String),
      ultimaSincronizacao: map['ultima_sincronizacao'] != null
          ? DateTime.parse(map['ultima_sincronizacao'] as String)
          : null,
    );
  }
}