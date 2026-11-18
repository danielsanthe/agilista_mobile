import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../controllers/autenticacao_controller.dart';
import '../nucleo/constantes/status_constants.dart';
import '../nucleo/database/app_database.dart';
import '../repositories/autenticacao_repository.dart';
import '../repositories/exclusao_repository.dart';
import 'sincronizacao_categorias_service.dart';

/// ============================================================================
/// SERVIÇO DE SINCRONIZAÇÃO OFFLINE-FIRST — PRODUTOS DO USUÁRIO (FLUTTER <-> FASTAPI)
/// ============================================================================
/// Orquestra a sincronização bidirecional entre a tabela local `produtos` (SQLite)
/// e os endpoints `/api/v1/produtos` da Agilista-api:
///
/// 1. GARANTIA DE DEPENDÊNCIA (CATEGORIAS):
///    Assegura que as categorias possuam `servidor_id` mapeado antes de enviar
///    produtos para evitar erro 404 de chave estrangeira no servidor.
///
/// 2. PUSH DE EXCLUSÕES:
///    Processa registros de `produtos` na fila `exclusoes_pendentes`
///    enviando `DELETE /api/v1/produtos/{servidor_id}`.
///
/// 3. PUSH DE CRIAÇÕES E ATUALIZAÇÕES (`flag_sincronizado == 0`):
///    - `servidor_id == null` -> `POST /api/v1/produtos/`
///    - `servidor_id != null` -> `PUT /api/v1/produtos/{servidor_id}`
///
/// 4. PULL DO SERVIDOR (`GET /api/v1/produtos/`):
///    Baixa o catálogo pessoal do usuário do servidor e sincroniza com o
///    SQLite local (convertendo `categoria_id` remoto no `id_categoria` local).
class SincronizacaoProdutosService {
  final AppDatabase _db;
  final AuthRepository _authRepo;
  final ExclusaoRepository _exclusaoRepo;
  final SincronizacaoCategoriasService _syncCategorias;

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  SincronizacaoProdutosService({
    required this._authRepo,
    required this._syncCategorias,
    AppDatabase? db,
    ExclusaoRepository? exclusaoRepo,
  })  : _db = db ?? AppDatabase.instance,
        _exclusaoRepo = exclusaoRepo ?? ExclusaoRepository();

  /// Executa o ciclo completo de sincronização de produtos para o usuário logado.
  /// Retorna `true` se houve qualquer alteração no banco local (útil para atualizar a UI).
  /// Falhas de rede/offline são capturadas silenciosamente para preservar o modo Offline-First.
  static Future<bool>? _sincronizacaoEmAndamento;

  /// Executa o ciclo completo de sincronização de produtos para o usuário logado.
  /// Impede execuções concorrentes caso múltiplos controllers chamem ao mesmo tempo.
  Future<bool> sincronizarProdutos(int usuarioId) {
    if (_sincronizacaoEmAndamento != null) {
      return _sincronizacaoEmAndamento!;
    }
    _sincronizacaoEmAndamento = _executarSincronizacaoProdutos(usuarioId).whenComplete(() {
      _sincronizacaoEmAndamento = null;
    });
    return _sincronizacaoEmAndamento!;
  }

  Future<bool> _executarSincronizacaoProdutos(int usuarioId) async {
    bool houveAlteracaoLocal = false;

    try {
      final token = await _authRepo.obterTokenAcesso();
      if (token == null || token.isEmpty) {
        debugPrint('[SincronizacaoProdutos] Sem token JWT ativo. Sincronização adiada.');
        return false;
      }

      // 0. Garante que os `servidor_id` das categorias estejam atualizados antes dos produtos
      await _syncCategorias.sincronizarCategorias(usuarioId);

      // 1. Envia exclusões pendentes de produtos
      await _sincronizarExclusoes(token);

      // 2. Envia novos produtos e edições pendentes (flag_sincronizado == 0)
      final alterouNoPush = await _sincronizarPendenciasLocais(token);
      if (alterouNoPush) houveAlteracaoLocal = true;

      // 3. Baixa produtos do servidor e atualiza o banco local
      final alterouNoPull = await _baixarProdutosDoServidor(usuarioId, token);
      if (alterouNoPull) houveAlteracaoLocal = true;
    } catch (e) {
      debugPrint('[SincronizacaoProdutos] Modo offline ou falha temporária: $e');
    }

    return houveAlteracaoLocal;
  }

  /// Executa requisição HTTP autenticada com renovação automática do JWT em caso de 401.
  Future<http.Response> _requisicaoAutenticada({
    required String metodo,
    required Uri uri,
    required String tokenInicial,
    Map<String, dynamic>? body,
  }) async {
    Future<http.Response> enviar(String token) {
      final headers = <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      final payload = body != null ? jsonEncode(body) : null;

      switch (metodo) {
        case 'POST':
          return http.post(uri, headers: headers, body: payload).timeout(const Duration(seconds: 10));
        case 'PUT':
          return http.put(uri, headers: headers, body: payload).timeout(const Duration(seconds: 10));
        case 'DELETE':
          return http.delete(uri, headers: headers).timeout(const Duration(seconds: 10));
        default:
          return http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      }
    }

    http.Response response = await enviar(tokenInicial);

    // Se o access_token expirou, renova via /api/v1/auth/refresh e repete a chamada
    if (response.statusCode == 401) {
      final novoToken = await _authRepo.renovarTokenAcesso();
      if (novoToken != null && novoToken.isNotEmpty) {
        response = await enviar(novoToken);
      }
    }

    return response;
  }

  /// Resolve o `servidor_id` de uma categoria a partir do `id_categoria` local no SQLite.
  Future<int?> _obterCategoriaServidorId(int idCategoriaLocal) async {
    final db = await _db.database;
    final rows = await db.query(
      'categorias',
      columns: ['servidor_id'],
      where: 'id_categoria = ?',
      whereArgs: [idCategoriaLocal],
    );
    if (rows.isEmpty) return null;
    return (rows.first['servidor_id'] as num?)?.toInt();
  }

  /// Resolve o `id_categoria` local no SQLite a partir do `id_categoria` remoto (`servidor_id`).
  /// Caso não localize, retorna o ID local de 'Mercearia / Grãos' como fallback seguro.
  Future<int> _obterCategoriaLocalId(int categoriaServidorId) async {
    final db = await _db.database;

    // 1. Procura pela coluna `servidor_id`
    final porServidor = await db.query(
      'categorias',
      columns: ['id_categoria'],
      where: 'servidor_id = ?',
      whereArgs: [categoriaServidorId],
    );
    if (porServidor.isNotEmpty) {
      return porServidor.first['id_categoria'] as int;
    }

    // 2. Fallback seguro: 'Mercearia / Grãos' ou primeira categoria ativa local
    final mercearia = await db.query(
      'categorias',
      columns: ['id_categoria'],
      where: "LOWER(nome_categoria) LIKE '%mercearia%' AND status_categoria = ?",
      whereArgs: [StatusGeral.ativo],
    );
    if (mercearia.isNotEmpty) {
      return mercearia.first['id_categoria'] as int;
    }

    final primeira = await db.query('categorias', columns: ['id_categoria'], limit: 1);
    return primeira.isNotEmpty ? (primeira.first['id_categoria'] as int) : 1;
  }

  /// 1. PUSH DE EXCLUSÕES: Processa exclusões de produtos registradas em `exclusoes_pendentes`.
  Future<void> _sincronizarExclusoes(String token) async {
    final pendentes = await _exclusaoRepo.obterExclusoesPendentes();
    final exclusoesProdutos = pendentes.where((e) => e['tabela'] == 'produtos');

    for (final item in exclusoesProdutos) {
      final idExclusao = item['id_exclusao'] as int;
      final servidorId = (item['servidor_id'] as num?)?.toInt();

      if (servidorId == null) {
        await _exclusaoRepo.removerPendencia(idExclusao);
        continue;
      }

      final uri = Uri.parse('$_apiBaseUrl/api/v1/produtos/$servidorId');
      final response = await _requisicaoAutenticada(
        metodo: 'DELETE',
        uri: uri,
        tokenInicial: token,
      );

      // 204/200 (excluído), 404 (já removido) ou 409 (histórico no servidor): limpa da fila local
      if (response.statusCode == 204 ||
          response.statusCode == 200 ||
          response.statusCode == 404 ||
          response.statusCode == 409) {
        await _exclusaoRepo.removerPendencia(idExclusao);
      }
    }
  }

  /// 2. PUSH DE CRIAÇÕES E EDIÇÕES: Envia produtos locais com `flag_sincronizado == 0`.
  Future<bool> _sincronizarPendenciasLocais(String token) async {
    final db = await _db.database;
    bool houveAlteracao = false;

    final pendentes = await db.query(
      'produtos',
      where: 'flag_sincronizado = 0',
    );

    for (final prod in pendentes) {
      final idLocal = prod['id_produto'] as int;
      final servidorId = (prod['servidor_id'] as num?)?.toInt();
      final categoriaLocalId = prod['categoria_id'] as int;
      final nomeProduto = (prod['nome_produto'] as String).trim();
      final codigoBarras = (prod['codigo_barras'] as String?)?.trim();
      final unidadeMedida = (prod['unidade_medida'] as String?)?.trim() ?? 'Un';
      final flagRecorrente = (prod['flag_produto_recorrente'] as int?) ?? 0;

      // Converte `id_categoria` local para o `servidor_id` correspondente na API
      final categoriaServidorId = await _obterCategoriaServidorId(categoriaLocalId);
      if (categoriaServidorId == null) {
        debugPrint(
          '[SincronizacaoProdutos] Produto "$nomeProduto" aguardando servidor_id da categoria $categoriaLocalId.',
        );
        continue;
      }

      final payload = <String, dynamic>{
        'nome_produto': nomeProduto,
        'categoria_id': categoriaServidorId,
        'codigo_barras': (codigoBarras != null && codigoBarras.isNotEmpty) ? codigoBarras : null,
        'unidade_medida': unidadeMedida.isEmpty ? 'Un' : unidadeMedida,
        'flag_produto_recorrente': flagRecorrente == 1 ? 1 : 0,
      };

      if (servidorId == null) {
        // Criação de novo produto pessoal (POST /api/v1/produtos/)
        final response = await _requisicaoAutenticada(
          metodo: 'POST',
          uri: Uri.parse('$_apiBaseUrl/api/v1/produtos/'),
          tokenInicial: token,
          body: payload,
        );

        if (response.statusCode == 201 || response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final novoServidorId = (data['id_produto_usuario'] as num?)?.toInt();

          await db.update(
            'produtos',
            {
              'servidor_id': ?novoServidorId,
              'flag_sincronizado': 1,
            },
            where: 'id_produto = ?',
            whereArgs: [idLocal],
          );
          houveAlteracao = true;
        }
      } else {
        // Atualização de produto existente no servidor (PUT /api/v1/produtos/{servidor_id})
        final response = await _requisicaoAutenticada(
          metodo: 'PUT',
          uri: Uri.parse('$_apiBaseUrl/api/v1/produtos/$servidorId'),
          tokenInicial: token,
          body: payload,
        );

        if (response.statusCode == 200) {
          await db.update(
            'produtos',
            {'flag_sincronizado': 1},
            where: 'id_produto = ?',
            whereArgs: [idLocal],
          );
          houveAlteracao = true;
        }
      }
    }

    return houveAlteracao;
  }

  /// 3. PULL DO SERVIDOR: Obtém os produtos pessoais do usuário (`GET /api/v1/produtos/`).
  Future<bool> _baixarProdutosDoServidor(int usuarioId, String token) async {
    final response = await _requisicaoAutenticada(
      metodo: 'GET',
      uri: Uri.parse('$_apiBaseUrl/api/v1/produtos/'),
      tokenInicial: token,
    );

    if (response.statusCode != 200) return false;

    final listaApi = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    final db = await _db.database;
    bool houveAlteracao = false;

    for (final item in listaApi) {
      final mapApi = item as Map<String, dynamic>;
      final servidorId = (mapApi['id_produto_usuario'] as num).toInt();
      final nomeApi = (mapApi['nome_produto'] as String).trim();
      final categoriaServidorId = (mapApi['categoria_id'] as num).toInt();
      final codigoBarrasApi = (mapApi['codigo_barras'] as String?)?.trim();
      final unidadeApi = (mapApi['unidade_medida'] as String?)?.trim() ?? 'Un';
      final recorrenteApi = (mapApi['flag_produto_recorrente'] as num?)?.toInt() ?? 0;

      final categoriaLocalId = await _obterCategoriaLocalId(categoriaServidorId);

      // Procura no SQLite local por `servidor_id`, `codigo_barras` ou `nome_produto`
      var locais = await db.query(
        'produtos',
        where: 'servidor_id = ?',
        whereArgs: [servidorId],
      );

      if (locais.isEmpty && codigoBarrasApi != null && codigoBarrasApi.isNotEmpty) {
        locais = await db.query(
          'produtos',
          where: 'codigo_barras = ?',
          whereArgs: [codigoBarrasApi],
        );
      }

      if (locais.isEmpty) {
        locais = await db.query(
          'produtos',
          where: 'LOWER(TRIM(nome_produto)) = ?',
          whereArgs: [nomeApi.toLowerCase()],
        );
      }

      if (locais.isNotEmpty) {
        final local = locais.first;
        final idLocal = local['id_produto'] as int;
        final flagSync = (local['flag_sincronizado'] as int?) ?? 1;

        // Só atualiza se não houver alteração local pendente de envio
        if (flagSync == 1) {
          final precisaAtualizar = local['servidor_id'] != servidorId ||
              local['nome_produto'] != nomeApi ||
              local['categoria_id'] != categoriaLocalId ||
              local['codigo_barras'] != codigoBarrasApi ||
              local['unidade_medida'] != unidadeApi ||
              local['flag_produto_recorrente'] != recorrenteApi;

          if (precisaAtualizar) {
            await db.update(
              'produtos',
              {
                'servidor_id': servidorId,
                'categoria_id': categoriaLocalId,
                'codigo_barras': codigoBarrasApi,
                'nome_produto': nomeApi,
                'unidade_medida': unidadeApi,
                'flag_produto_recorrente': recorrenteApi,
                'flag_sincronizado': 1,
              },
              where: 'id_produto = ?',
              whereArgs: [idLocal],
            );
            houveAlteracao = true;
          }
        }
      } else {
        // Produto criado em outro dispositivo: insere no SQLite local
        await db.insert('produtos', {
          'servidor_id': servidorId,
          'categoria_id': categoriaLocalId,
          'codigo_barras': codigoBarrasApi,
          'nome_produto': nomeApi,
          'unidade_medida': unidadeApi,
          'flag_produto_recorrente': recorrenteApi,
          'flag_sincronizado': 1,
        });
        houveAlteracao = true;
      }
    }

    return houveAlteracao;
  }
}

/// Provider global Riverpod para o serviço de sincronização de produtos.
final sincronizacaoProdutosServiceProvider = Provider<SincronizacaoProdutosService>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final syncCategorias = ref.watch(sincronizacaoCategoriasServiceProvider);
  return SincronizacaoProdutosService(
    authRepo: authRepo,
    syncCategorias: syncCategorias,
  );
});