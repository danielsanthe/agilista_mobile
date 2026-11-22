import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../nucleo/constantes/api_constants.dart';
import '../nucleo/database/app_database.dart';
import '../models/usuario_model.dart';

/// Lançada quando a API rejeita explicitamente o cadastro (409 duplicado / 422 inválido).
/// Nesses casos NÃO se deve salvar offline, pois o registro nunca seria aceito depois.
class CadastroRejeitadoException implements Exception {
  final String mensagem;
  CadastroRejeitadoException(this.mensagem);
  @override
  String toString() => mensagem;
}

/// ============================================================================
/// REPOSITÓRIO DE AUTENTICAÇÃO E PERFIL DE USUÁRIO (OFFLINE-FIRST + FASTAPI)
/// ============================================================================
/// Abstração e implementação do acesso aos dados da tabela `usuarios` no SQLite
/// integrada à API FastAPI (`/api/v1/auth` e `/api/v1/usuarios`).
///
/// Obs.: usuário criado/editado offline é enviado depois por `sincronizarUsuarioPendente`
/// (cria a conta no servidor, obtém o JWT e envia o perfil pendente).
abstract class AuthRepository {
  Future<UsuarioModel> cadastrarUsuario(UsuarioModel usuario);
  Future<UsuarioModel?> login(String email, String senha);
  Future<UsuarioModel?> restaurarSessaoLocal();
  Future<UsuarioModel?> buscarPorId(int idUsuario);
  Future<bool> atualizarPerfil(UsuarioModel usuario, {String? novaSenha});
  Future<bool> atualizarUsuario(UsuarioModel usuario, {String? novaSenha}); // Alias para integração com o AuthController
  Future<String?> solicitarRecuperacaoSenha(String email);
  Future<bool> redefinirSenha({
    required String email,
    required String codigo,
    required String novaSenha,
  });
  Future<String?> obterTokenAcesso();
  Future<String?> renovarTokenAcesso();
  Future<void> limparTokens();

  /// Envia ao servidor o usuário criado/editado offline (cadastro + tokens + perfil).
  /// Retorna o usuário local atualizado, ou `null` se ainda não foi possível sincronizar.
  Future<UsuarioModel?> sincronizarUsuarioPendente(int idUsuarioLocal);
}

class AuthRepositoryImpl implements AuthRepository {
  final AppDatabase _db = AppDatabase.instance;

  static const String _apiBaseUrl = ApiConstants.baseUrl;

  static const String _keyAccessToken = 'agilista_access_token';
  static const String _keyRefreshToken = 'agilista_refresh_token';
  static const String _keyUsuarioLogadoId = 'agilista_usuario_logado_id';

  /// Salva os tokens JWT retornados por `/api/v1/auth/signin` ou `/refresh`.
  Future<void> _salvarTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    await prefs.setString(_keyRefreshToken, refreshToken);
  }

  /// Persiste o ID local do usuário autenticado para restauração rápida ao reiniciar o app.
  Future<void> _salvarSessaoUsuarioLocal(int? idUsuarioLocal) async {
    if (idUsuarioLocal == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUsuarioLogadoId, idUsuarioLocal);
  }

  @override
  Future<String?> obterTokenAcesso() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken);
  }

  @override
  Future<void> limparTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUsuarioLogadoId);
  }

  @override
  Future<UsuarioModel?> restaurarSessaoLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idLocal = prefs.getInt(_keyUsuarioLogadoId);
      // Obs.: a sessão não exige mais token; usuário cadastrado offline ainda não possui
      // token, mas a sessão local deve ser restaurada mesmo assim.
      if (idLocal == null) return null;

      return await buscarPorId(idLocal);
    } catch (e) {
      debugPrint('[AuthRepositoryImpl.restaurarSessaoLocal] erro: $e');
      return null;
    }
  }

  @override
  Future<String?> renovarTokenAcesso() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_keyRefreshToken);
      if (refreshToken == null || refreshToken.isEmpty) return null;

      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/v1/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(ApiConstants.timeoutPadrao);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final novoAccess = data['access_token'] as String?;
        final novoRefresh = data['refresh_token'] as String?;
        if (novoAccess != null && novoRefresh != null) {
          await _salvarTokens(novoAccess, novoRefresh);
          return novoAccess;
        }
      }
    } catch (e) {
      debugPrint('[AuthRepositoryImpl.renovarTokenAcesso] erro: $e');
    }
    return null;
  }

  /// Sincroniza ou cria o registro do usuário autenticado na API no banco SQLite local.
  /// Obs.: edições locais pendentes (`flag_sincronizado = 0`) são enviadas antes, em
  /// `_autenticarNaApi`, para não serem sobrescritas por esta função.
  Future<UsuarioModel> _sincronizarUsuarioLocal({
    required Map<String, dynamic> dadosApi,
    required String senhaPlana,
  }) async {
    final db = await _db.database;
    final emailLimpo = (dadosApi['email'] as String).trim().toLowerCase();
    final servidorId = (dadosApi['id_usuario'] as num?)?.toInt();

    final existentes = await db.query(
      'usuarios',
      where: 'email = ?',
      whereArgs: [emailLimpo],
    );

    final dadosMapeados = <String, dynamic>{
      'servidor_id': servidorId,
      'nome_usuario': dadosApi['nome_usuario'] ?? emailLimpo.split('@').first,
      'email': emailLimpo,
      'senha_hash': senhaPlana,
      'cpf': dadosApi['cpf'],
      'telefone': dadosApi['telefone'],
      'cep': dadosApi['cep'],
      'logradouro': dadosApi['logradouro'],
      'numero': dadosApi['numero'],
      'bairro': dadosApi['bairro'],
      'cidade': dadosApi['cidade'],
      'uf': dadosApi['uf'],
      'tipo_plano': dadosApi['tipo_plano'] ?? 'FreeTrial',
      'flag_sincronizado': 1,
      'data_cadastro': dadosApi['data_cadastro'] ?? DateTime.now().toIso8601String(),
      'ultima_sincronizacao': DateTime.now().toIso8601String(),
    };

    if (existentes.isNotEmpty) {
      final idLocal = existentes.first['id_usuario'] as int;
      await db.update(
        'usuarios',
        dadosMapeados,
        where: 'id_usuario = ?',
        whereArgs: [idLocal],
      );
      dadosMapeados['id_usuario'] = idLocal;
      await _salvarSessaoUsuarioLocal(idLocal);
      return UsuarioModel.fromMap(dadosMapeados);
    } else {
      final idInserido = await db.insert('usuarios', dadosMapeados);
      dadosMapeados['id_usuario'] = idInserido;
      await _salvarSessaoUsuarioLocal(idInserido);
      return UsuarioModel.fromMap(dadosMapeados);
    }
  }

  /// Realiza signin na FastAPI (`/api/v1/auth/signin`), salva os tokens e busca `/api/v1/usuarios/me`.
  /// Obs.: antes de buscar `/me`, envia cadastro/edição pendente feito offline (se houver).
  Future<UsuarioModel?> _autenticarNaApi(String email, String senha) async {
    final loginResponse = await http
        .post(
          Uri.parse('$_apiBaseUrl/api/v1/auth/signin'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': email,
            'password': senha,
          }),
        )
        .timeout(ApiConstants.timeoutPadrao);

    if (loginResponse.statusCode == 401) {
      throw Exception('E-mail ou senha inválidos.');
    }

    if (loginResponse.statusCode != 200) {
      return null;
    }

    final tokenData = jsonDecode(utf8.decode(loginResponse.bodyBytes)) as Map<String, dynamic>;
    final accessToken = tokenData['access_token'] as String?;
    final refreshToken = tokenData['refresh_token'] as String?;

    if (accessToken == null || refreshToken == null) return null;

    await _salvarTokens(accessToken, refreshToken);

    // Obs.: se houver cadastro/edição feito offline ainda não enviado, envia ANTES de
    // sobrescrever o SQLite com os dados do servidor (evita perder alterações locais).
    final dbPend = await _db.database;
    final pendentes = await dbPend.query(
      'usuarios',
      where: 'email = ? AND (servidor_id IS NULL OR flag_sincronizado = 0)',
      whereArgs: [email.trim().toLowerCase()],
    );
    if (pendentes.isNotEmpty) {
      final enviado = await sincronizarUsuarioPendente(pendentes.first['id_usuario'] as int);
      if (enviado != null) return enviado;
    }

    // Busca o perfil completo do usuário autenticado na API (/api/v1/usuarios/me)
    final meResponse = await http
        .get(
          Uri.parse('$_apiBaseUrl/api/v1/usuarios/me'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
          },
        )
        .timeout(ApiConstants.timeoutPadrao);

    if (meResponse.statusCode == 200) {
      final perfilData = jsonDecode(utf8.decode(meResponse.bodyBytes)) as Map<String, dynamic>;
      return await _sincronizarUsuarioLocal(
        dadosApi: perfilData,
        senhaPlana: senha,
      );
    }

    return null;
  }

  /// Faz signin apenas para obter/salvar os tokens (não altera o SQLite).
  Future<bool> _obterTokensPorSignin(String email, String senha) async {
    final resp = await http
        .post(
          Uri.parse('$_apiBaseUrl/api/v1/auth/signin'),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({'email': email, 'password': senha}),
        )
        .timeout(ApiConstants.timeoutPadrao);
    if (resp.statusCode != 200) return false;
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access == null || refresh == null) return false;
    await _salvarTokens(access, refresh);
    return true;
  }

  /// Monta o payload da API a partir de uma linha da tabela `usuarios`.
  Map<String, dynamic> _payloadUsuarioApi(Map<String, dynamic> u, {required bool incluirSenha}) {
    String? limpo(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final campos = <String, String?>{
      'cpf': limpo(u['cpf'])?.replaceAll(RegExp(r'\D'), ''),
      'telefone': limpo(u['telefone']),
      'cep': limpo(u['cep']),
      'logradouro': limpo(u['logradouro']),
      'numero': limpo(u['numero']),
      'bairro': limpo(u['bairro']),
      'cidade': limpo(u['cidade']),
      'uf': limpo(u['uf']),
    };
    return <String, dynamic>{
      'nome_usuario': (u['nome_usuario'] as String).trim(),
      'email': (u['email'] as String).trim().toLowerCase(),
      if (incluirSenha) 'senha': u['senha_hash'],
      for (final e in campos.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value,
    };
  }

  /// GET/PUT autenticado em endpoints de usuário, com renovação do JWT em caso de 401.
  Future<http.Response> _requisicaoUsuarioAutenticada(
    String metodo,
    String caminho, {
    Map<String, dynamic>? body,
  }) async {
    Future<http.Response> enviar(String token) {
      final uri = Uri.parse('$_apiBaseUrl$caminho');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final f = metodo == 'PUT'
          ? http.put(uri, headers: headers, body: jsonEncode(body))
          : http.get(uri, headers: headers);
      return f.timeout(ApiConstants.timeoutPadrao);
    }

    var token = await obterTokenAcesso();

    // Sem access_token: tenta renovar direto, sem enviar 'Bearer ' vazio ao servidor
    if (token == null || token.isEmpty) {
      token = await renovarTokenAcesso();
      if (token == null || token.isEmpty) {
        return http.Response('', 401); // sem credenciais utilizáveis
      }
    }

    var resp = await enviar(token);
    if (resp.statusCode == 401) {
      final novo = await renovarTokenAcesso();
      if (novo != null && novo.isNotEmpty) resp = await enviar(novo);
    }
    return resp;
  }

  @override
  Future<UsuarioModel?> sincronizarUsuarioPendente(int idUsuarioLocal) async {
    try {
      final db = await _db.database;
      final rows = await db.query('usuarios', where: 'id_usuario = ?', whereArgs: [idUsuarioLocal]);
      if (rows.isEmpty) return null;
      final local = Map<String, dynamic>.from(rows.first);

      final email = (local['email'] as String).trim().toLowerCase();
      final senha = (local['senha_hash'] as String?) ?? '';
      var servidorId = (local['servidor_id'] as num?)?.toInt();
      final pendente = ((local['flag_sincronizado'] as num?)?.toInt() ?? 0) == 0;
      final token = await obterTokenAcesso();
      var temToken = token != null && token.isNotEmpty;

      // Já está tudo em dia
      if (servidorId != null && !pendente && temToken) return UsuarioModel.fromMap(local);

      Future<void> gravarServidorId() async {
        if (servidorId != null) {
          await db.update('usuarios', {'servidor_id': servidorId},
              where: 'id_usuario = ?', whereArgs: [idUsuarioLocal]);
        }
      }

      var recemCriado = false;

      // 1. Cadastro feito offline: cria a conta no servidor
      if (servidorId == null && !temToken) {
        final resp = await http
            .post(
              Uri.parse('$_apiBaseUrl/api/v1/usuarios/'),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode(_payloadUsuarioApi(local, incluirSenha: true)),
            )
            .timeout(ApiConstants.timeoutPadrao);

        if (resp.statusCode == 201 || resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
          servidorId = (data['id_usuario'] as num?)?.toInt();
          recemCriado = true;
          await gravarServidorId();
        } else if (resp.statusCode != 409) {
          // 409 = e-mail/CPF já existe: segue para o signin e tenta vincular a conta existente
          debugPrint('[AuthRepositoryImpl.sincronizarUsuarioPendente] API recusou: ${resp.statusCode}');
          return null;
        }
      }

      // 2. Obtém os tokens JWT (usuário offline ainda não tinha)
      if (!temToken) {
        if (!await _obterTokensPorSignin(email, senha)) return null;
        temToken = true;
      }

      // 3. Conta já existia no servidor: vincula o servidor_id
      if (servidorId == null) {
        final me = await _requisicaoUsuarioAutenticada('GET', '/api/v1/usuarios/me');
        if (me.statusCode != 200) return null;
        final data = jsonDecode(utf8.decode(me.bodyBytes)) as Map<String, dynamic>;
        servidorId = (data['id_usuario'] as num?)?.toInt();
        if (servidorId == null) return null;
        await gravarServidorId();
      }

      // 4. Edições de perfil feitas offline
      if (pendente && !recemCriado) {
        final put = await _requisicaoUsuarioAutenticada(
          'PUT',
          '/api/v1/usuarios/me',
          body: _payloadUsuarioApi(local, incluirSenha: true),
        );
        if (put.statusCode != 200) return null;
      }

      // 5. Marca como sincronizado
      await db.update(
        'usuarios',
        {
          'servidor_id': servidorId,
          'flag_sincronizado': 1,
          'ultima_sincronizacao': DateTime.now().toIso8601String(),
        },
        where: 'id_usuario = ?',
        whereArgs: [idUsuarioLocal],
      );
      final atualizado = await db.query('usuarios', where: 'id_usuario = ?', whereArgs: [idUsuarioLocal]);
      return atualizado.isEmpty ? null : UsuarioModel.fromMap(atualizado.first);
    } catch (e) {
      debugPrint('[AuthRepositoryImpl.sincronizarUsuarioPendente] offline/falha: $e');
      return null;
    }
  }

  /// Login de conta criada/editada offline que o servidor ainda não conhece (signin = 401).
  Future<UsuarioModel?> _loginContaPendenteDeEnvio(String email, String senha) async {
    final db = await _db.database;
    final rows = await db.query(
      'usuarios',
      where: 'email = ? AND senha_hash = ? AND (servidor_id IS NULL OR flag_sincronizado = 0)',
      whereArgs: [email, senha],
    );
    if (rows.isEmpty) return null;

    final idLocal = rows.first['id_usuario'] as int;
    final sincronizado = await sincronizarUsuarioPendente(idLocal);
    await _salvarSessaoUsuarioLocal(idLocal);
    return sincronizado ?? UsuarioModel.fromMap(rows.first);
  }

  @override
  Future<UsuarioModel> cadastrarUsuario(UsuarioModel usuario) async {
    final db = await _db.database;
    final emailLimpo = usuario.email.trim().toLowerCase();

    // 1. Verificar se o e-mail já está cadastrado no SQLite local
    final emaiExistente = await db.query(
      'usuarios',
      where: 'email = ?',
      whereArgs: [emailLimpo],
    );

    if (emaiExistente.isNotEmpty) {
      throw Exception('O e-mail informado já está cadastrado.');
    }

    // 2. Verificar se o CPF já está cadastrado (se informado)
    String? cpfLimpo;
    if (usuario.cpf != null && usuario.cpf!.trim().isNotEmpty) {
      cpfLimpo = usuario.cpf!.replaceAll(RegExp(r'\D'), '');
      final cpfExistente = await db.query(
        'usuarios',
        where: 'cpf = ?',
        whereArgs: [cpfLimpo],
      );

      if (cpfExistente.isNotEmpty) {
        throw Exception('O CPF informado já está cadastrado.');
      }
    }

    int? servidorId;
    bool sincronizado = false;

    // 3. Tenta registrar o usuário na API FastAPI (`POST /api/v1/usuarios/`)
    try {
      final payloadApi = <String, dynamic>{
        'nome_usuario': usuario.nomeUsuario.trim(),
        'email': emailLimpo,
        'senha': usuario.senhaHash,
        if (cpfLimpo != null && cpfLimpo.isNotEmpty) 'cpf': cpfLimpo,
        if (usuario.telefone != null && usuario.telefone!.trim().isNotEmpty)
          'telefone': usuario.telefone!.trim(),
        if (usuario.cep != null && usuario.cep!.trim().isNotEmpty) 'cep': usuario.cep!.trim(),
        if (usuario.logradouro != null && usuario.logradouro!.trim().isNotEmpty)
          'logradouro': usuario.logradouro!.trim(),
        if (usuario.numero != null && usuario.numero!.trim().isNotEmpty)
          'numero': usuario.numero!.trim(),
        if (usuario.bairro != null && usuario.bairro!.trim().isNotEmpty)
          'bairro': usuario.bairro!.trim(),
        if (usuario.cidade != null && usuario.cidade!.trim().isNotEmpty)
          'cidade': usuario.cidade!.trim(),
        if (usuario.uf != null && usuario.uf!.trim().isNotEmpty) 'uf': usuario.uf!.trim(),
      };

      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/v1/usuarios/'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payloadApi),
          )
          .timeout(ApiConstants.timeoutPadrao);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final criadoData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        servidorId = (criadoData['id_usuario'] as num?)?.toInt();
        sincronizado = true;

        // Realiza login automático na API para obter e armazenar o token JWT
        await _autenticarNaApi(emailLimpo, usuario.senhaHash);
      } else if (response.statusCode == 409 || response.statusCode == 422) {
        final erro = jsonDecode(utf8.decode(response.bodyBytes));
        final detalhe = erro is Map ? erro['detail'] : null;
        throw CadastroRejeitadoException(
          detalhe is String
              ? detalhe
              : (response.statusCode == 409
                  ? 'E-mail ou CPF já cadastrado no servidor.'
                  : 'Dados inválidos. Revise os campos informados.'),
        );
      }
    } catch (e) {
      // Se for conflito explícito (409), repassa ao usuário; se for offline/405, segue offline-first
      // Obs.: rejeição explícita da API (409/422) é repassada ao usuário.
      // Timeout, sem rede ou 5xx: segue offline-first e o usuário fica pendente de envio.
      if (e is CadastroRejeitadoException) rethrow;
      debugPrint('[AuthRepositoryImpl.cadastrarUsuario] fallback offline: $e');
    }

    // 4. Persiste no SQLite local (evitando duplicidade caso _autenticarNaApi já tenha inserido)
    // Obs.: sem rede, o usuário fica com `flag_sincronizado = 0` e `servidor_id` nulo; o envio
    // ocorre depois em `sincronizarUsuarioPendente()`.
    final jaInserido = await db.query(
      'usuarios',
      where: 'email = ?',
      whereArgs: [emailLimpo],
    );

    if (jaInserido.isNotEmpty) {
      final usuarioLocal = UsuarioModel.fromMap(jaInserido.first);
      await _salvarSessaoUsuarioLocal(usuarioLocal.idUsuario);
      return usuarioLocal;
    }

    final map = usuario.toMap();
    map['email'] = emailLimpo;
    if (cpfLimpo != null) map['cpf'] = cpfLimpo;
    if (servidorId != null) map['servidor_id'] = servidorId;
    map['flag_sincronizado'] = sincronizado ? 1 : 0;

    final idInserido = await db.insert('usuarios', map);
    await _salvarSessaoUsuarioLocal(idInserido);
    return usuario.copyWith(
      idUsuario: idInserido,
      servidorId: servidorId,
      email: emailLimpo,
      flagSincronizado: sincronizado,
    );
  }

  @override
  Future<UsuarioModel?> login(String email, String senha) async {
    final emailLimpo = email.trim().toLowerCase();

    // 1. Tenta autenticar online na API FastAPI para obter o JWT atualizado
    try {
      final usuarioApi = await _autenticarNaApi(emailLimpo, senha);
      if (usuarioApi != null) {
        return usuarioApi;
      }
    } catch (e) {
      // Se a API rejeitou explicitamente a senha (401), não permite login offline com senha errada
      // Obs.: exceção — conta criada offline que o servidor ainda não conhece é enviada em
      // `_loginContaPendenteDeEnvio` antes de recusar o login.
      if (e.toString().contains('E-mail ou senha inválidos')) {
        // Exceção: conta criada offline que o servidor ainda não conhece -> envia e autentica
        return await _loginContaPendenteDeEnvio(emailLimpo, senha);
      }
      debugPrint('[AuthRepositoryImpl.login] modo offline ativado: $e');
    }

    // 2. Fallback Offline-First: valida credenciais no banco SQLite local
    final db = await _db.database;
    final result = await db.query(
      'usuarios',
      where: 'email = ? AND senha_hash = ?',
      whereArgs: [emailLimpo, senha],
    );

    if (result.isNotEmpty) {
      final usuarioLocal = UsuarioModel.fromMap(result.first);
      await _salvarSessaoUsuarioLocal(usuarioLocal.idUsuario);
      return usuarioLocal;
    }
    return null;
  }

  @override
  Future<UsuarioModel?> buscarPorId(int idUsuario) async {
    final db = await _db.database;

    final result = await db.query(
      'usuarios',
      where: 'id_usuario = ?',
      whereArgs: [idUsuario],
    );

    if (result.isNotEmpty) {
      return UsuarioModel.fromMap(result.first);
    }
    return null;
  }

  @override
  Future<bool> atualizarPerfil(UsuarioModel usuario, {String? novaSenha}) async {
    if (usuario.idUsuario == null) return false;

    final db = await _db.database;
    final emailLimpo = usuario.email.trim().toLowerCase();
    bool sincronizado = false;

    // 1. Tenta atualizar na API FastAPI (`PUT /api/v1/usuarios/me`) se houver token ativo
    try {
      final token = await obterTokenAcesso();
      if (token != null && token.isNotEmpty) {
        final senhaParaEnviar = novaSenha?.trim();
        final payloadPut = <String, dynamic>{
          'nome_usuario': usuario.nomeUsuario,
          'email': emailLimpo,
          if (senhaParaEnviar != null && senhaParaEnviar.isNotEmpty)
            'senha': senhaParaEnviar,
          if (usuario.cpf != null) 'cpf': usuario.cpf,
          if (usuario.telefone != null) 'telefone': usuario.telefone,
          if (usuario.cep != null) 'cep': usuario.cep,
          if (usuario.logradouro != null) 'logradouro': usuario.logradouro,
          if (usuario.numero != null) 'numero': usuario.numero,
          if (usuario.bairro != null) 'bairro': usuario.bairro,
          if (usuario.cidade != null) 'cidade': usuario.cidade,
          if (usuario.uf != null) 'uf': usuario.uf,
        };

        Future<http.Response> enviarPut(String accessToken) {
          return http
              .put(
                Uri.parse('$_apiBaseUrl/api/v1/usuarios/me'),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  'Authorization': 'Bearer $accessToken',
                },
                body: jsonEncode(payloadPut),
              )
              .timeout(ApiConstants.timeoutPadrao);
        }

        var response = await enviarPut(token);

        // Renova o access_token automaticamente caso tenha expirado (HTTP 401)
        if (response.statusCode == 401) {
          final novoToken = await renovarTokenAcesso();
          if (novoToken != null && novoToken.isNotEmpty) {
            response = await enviarPut(novoToken);
          }
        }

        if (response.statusCode == 200) {
          sincronizado = true;
        }
      }
    } catch (e) {
      debugPrint('[AuthRepositoryImpl.atualizarPerfil] falha sync online: $e');
    }

    // 2. Atualiza no SQLite local
    // Obs.: se não sincronizou online, `flag_sincronizado = 0` mantém a edição pendente;
    // ela será enviada depois por `sincronizarUsuarioPendente()`.
    final map = usuario.toMap();
    map['email'] = emailLimpo;
    map['flag_sincronizado'] = sincronizado ? 1 : 0;

    final linhasAfetadas = await db.update(
      'usuarios',
      map,
      where: 'id_usuario = ?',
      whereArgs: [usuario.idUsuario],
    );

    return linhasAfetadas > 0;
  }

  @override
  Future<bool> atualizarUsuario(UsuarioModel usuario, {String? novaSenha}) async {
    return await atualizarPerfil(usuario, novaSenha: novaSenha);
  }

  /// Solicita à FastAPI (`POST /api/v1/auth/esqueci-senha`) o código temporário de 6 dígitos
  /// para recuperação de senha associada ao e-mail informado.
  @override
  Future<String?> solicitarRecuperacaoSenha(String email) async {
    final emailLimpo = email.trim().toLowerCase();
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/v1/auth/esqueci-senha'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': emailLimpo}),
          )
          .timeout(ApiConstants.timeoutPadrao);

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data['codigo_recuperacao'] as String?;
      } else {
        throw Exception(data['detail'] ?? 'Não foi possível solicitar a recuperação.');
      }
    } catch (e) {
      if (e.toString().contains('Nenhuma conta encontrada')) rethrow;
      throw Exception('Sem conexão com o servidor. Conecte-se à internet para recuperar a senha.');
    }
  }

  /// Valida o código de 6 dígitos na FastAPI (`POST /api/v1/auth/redefinir-senha`),
  /// grava a nova senha no servidor e atualiza o registro local no SQLite.
  @override
  Future<bool> redefinirSenha({
    required String email,
    required String codigo,
    required String novaSenha,
  }) async {
    final emailLimpo = email.trim().toLowerCase();
    final senhaLimpa = novaSenha.trim();

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/v1/auth/redefinir-senha'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'email': emailLimpo,
              'codigo': codigo.trim(),
              'nova_senha': senhaLimpa,
            }),
          )
          .timeout(ApiConstants.timeoutPadrao);

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        // Atualiza também no SQLite local para manter o login offline funcionando
        final db = await _db.database;
        await db.update(
          'usuarios',
          {'senha_hash': senhaLimpa, 'flag_sincronizado': 1},
          where: 'email = ?',
          whereArgs: [emailLimpo],
        );
        return true;
      } else {
        throw Exception(data['detail'] ?? 'Código inválido ou expirado.');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro ao conectar ao servidor para redefinir a senha.');
    }
  }
}