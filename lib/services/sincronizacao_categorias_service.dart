import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../controllers/autenticacao_controller.dart';
import '../nucleo/constantes/status_constants.dart';
import '../nucleo/database/app_database.dart';
import '../repositories/autenticacao_repository.dart';
import '../repositories/exclusao_repository.dart';

/// ============================================================================
/// SERVIÇO DE SINCRONIZAÇÃO OFFLINE-FIRST — CATEGORIAS (FLUTTER <-> FASTAPI)
/// ============================================================================
/// Orquestra a sincronização bidirecional entre a tabela local `categorias`
/// (SQLite) e os endpoints `/api/v1/categorias` da Agilista-api:
///
/// 1. PUSH DE EXCLUSÕES:
///    Processa registros de `categorias` na fila `exclusoes_pendentes`
///    enviando `DELETE /api/v1/categorias/{servidor_id}`.
///
/// 2. PUSH DE CRIAÇÕES E ATUALIZAÇÕES:
///    Envia apenas categorias personalizadas (`usuario_id == usuarioId`)
///    com `flag_sincronizado == 0`:
///    - `servidor_id == null` -> `POST /api/v1/categorias/`
///    - `servidor_id != null` -> `PUT /api/v1/categorias/{servidor_id}`
///
/// 3. PULL DO SERVIDOR (`GET /api/v1/categorias/`):
///    - Categorias Padrão (`usuario_id == null`): Somente leitura; apenas
///      vincula o `servidor_id` remoto na categoria padrão local correspondente
///      (necessário para integridade referencial futura com Produtos).
///    - Categorias Personalizadas (`usuario_id != null`): Atualiza ou insere
///      no SQLite local registros criados/editados em outros dispositivos.
class SincronizacaoCategoriasService {
  final AppDatabase _db;
  final AuthRepository _authRepo;
  final ExclusaoRepository _exclusaoRepo;

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  SincronizacaoCategoriasService({
    required this._authRepo,
    AppDatabase? db,
    ExclusaoRepository? exclusaoRepo,
  })  : _db = db ?? AppDatabase.instance,
        _exclusaoRepo = exclusaoRepo ?? ExclusaoRepository();

  /// Executa o ciclo completo de sincronização de categorias para o usuário logado.
  /// Retorna `true` se houve qualquer alteração no banco local (útil para atualizar a UI).
  /// Falhas de rede/offline são capturadas silenciosamente para preservar o modo Offline-First.
  Future<bool> sincronizarCategorias(int usuarioId) async {
    bool houveAlteracaoLocal = false;

    try {
      String? token = await _authRepo.obterTokenAcesso();
      if (token == null || token.isEmpty) {
        debugPrint('[SincronizacaoCategorias] Sem token JWT ativo. Sincronização adiada.');
        return false;
      }

      // 1. Envia exclusões pendentes de categorias personalizadas
      await _sincronizarExclusoes(token);

      // 2. Envia novas categorias e edições pendentes (flag_sincronizado == 0)
      final alterouNoPush = await _sincronizarPendenciasLocais(usuarioId, token);
      if (alterouNoPush) houveAlteracaoLocal = true;

      // 3. Baixa categorias do servidor e vincula servidor_id
      final alterouNoPull = await _baixarCategoriasDoServidor(usuarioId, token);
      if (alterouNoPull) houveAlteracaoLocal = true;
    } catch (e) {
      debugPrint('[SincronizacaoCategorias] Modo offline ou falha temporária: $e');
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

    // Se o access_token expirou, tenta renovar via /api/v1/auth/refresh
    if (response.statusCode == 401) {
      final novoToken = await _authRepo.renovarTokenAcesso();
      if (novoToken != null && novoToken.isNotEmpty) {
        response = await enviar(novoToken);
      }
    }

    return response;
  }

  /// 1. PUSH DE EXCLUSÕES: Processa exclusões de categorias registradas em `exclusoes_pendentes`.
  Future<void> _sincronizarExclusoes(String token) async {
    final pendentes = await _exclusaoRepo.obterExclusoesPendentes();
    final exclusoesCategorias = pendentes.where((e) => e['tabela'] == 'categorias');

    for (final item in exclusoesCategorias) {
      final idExclusao = item['id_exclusao'] as int;
      final servidorId = (item['servidor_id'] as num?)?.toInt();

      // Se nunca chegou a existir no servidor, apenas limpa da fila
      if (servidorId == null) {
        await _exclusaoRepo.removerPendencia(idExclusao);
        continue;
      }

      final uri = Uri.parse('$_apiBaseUrl/api/v1/categorias/$servidorId');
      final response = await _requisicaoAutenticada(
        metodo: 'DELETE',
        uri: uri,
        tokenInicial: token,
      );

      // 204 (removida), 200 (ok) ou 404 (já não existia no servidor): limpa da fila local
      if (response.statusCode == 204 ||
          response.statusCode == 200 ||
          response.statusCode == 404) {
        await _exclusaoRepo.removerPendencia(idExclusao);
      } else if (response.statusCode == 403) {
        // Proteção contra tentativa indevida em categoria padrão
        await _exclusaoRepo.removerPendencia(idExclusao);
      }
    }
  }

  /// 2. PUSH DE CRIAÇÕES E EDIÇÕES: Envia categorias personalizadas com `flag_sincronizado == 0`.
  /// Categorias padrão (`usuario_id IS NULL`) nunca são enviadas para alteração.
  Future<bool> _sincronizarPendenciasLocais(int usuarioId, String token) async {
    final db = await _db.database;
    bool houveAlteracao = false;

    final pendentes = await db.query(
      'categorias',
      where: 'usuario_id = ? AND flag_sincronizado = 0',
      whereArgs: [usuarioId],
    );

    for (final cat in pendentes) {
      final idLocal = cat['id_categoria'] as int;
      final servidorId = (cat['servidor_id'] as num?)?.toInt();
      final nomeCategoria = (cat['nome_categoria'] as String).trim();
      final ativo = (cat['ativo'] as int?) ?? 1;
      final statusApi = ativo == 1 ? 'ATIVO' : 'INATIVO';

      final payload = <String, dynamic>{
        'nome_categoria': nomeCategoria,
        'ativo': ativo,
        'status_categoria': statusApi,
      };

      if (servidorId == null) {
        // Criação de nova categoria personalizada (POST)
        final response = await _requisicaoAutenticada(
          metodo: 'POST',
          uri: Uri.parse('$_apiBaseUrl/api/v1/categorias/'),
          tokenInicial: token,
          body: payload,
        );

        if (response.statusCode == 201 || response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final novoServidorId = (data['id_categoria'] as num?)?.toInt();

          await db.update(
            'categorias',
            {
              'servidor_id': ?novoServidorId,
              'flag_sincronizado': 1,
            },
            where: 'id_categoria = ?',
            whereArgs: [idLocal],
          );
          houveAlteracao = true;
        }
      } else {
        // Atualização de categoria personalizada já existente no servidor (PUT)
        final response = await _requisicaoAutenticada(
          metodo: 'PUT',
          uri: Uri.parse('$_apiBaseUrl/api/v1/categorias/$servidorId'),
          tokenInicial: token,
          body: payload,
        );

        if (response.statusCode == 200) {
          await db.update(
            'categorias',
            {'flag_sincronizado': 1},
            where: 'id_categoria = ?',
            whereArgs: [idLocal],
          );
          houveAlteracao = true;
        }
      }
    }

    return houveAlteracao;
  }

  /// 3. PULL DO SERVIDOR: Obtém categorias padrão e personalizadas da API (`GET /api/v1/categorias/`).
  Future<bool> _baixarCategoriasDoServidor(int usuarioId, String token) async {
    final response = await _requisicaoAutenticada(
      metodo: 'GET',
      uri: Uri.parse('$_apiBaseUrl/api/v1/categorias/'),
      tokenInicial: token,
    );

    if (response.statusCode != 200) return false;

    final listaApi = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    final db = await _db.database;
    bool houveAlteracao = false;

    for (final item in listaApi) {
      final mapApi = item as Map<String, dynamic>;
      final servidorId = (mapApi['id_categoria'] as num).toInt();
      final usuarioIdApi = (mapApi['usuario_id'] as num?)?.toInt();
      final nomeApi = (mapApi['nome_categoria'] as String).trim();
      final ativoApi = (mapApi['ativo'] as num?)?.toInt() ?? 1;
      final statusLocal = ativoApi == 1 ? StatusGeral.ativo : StatusGeral.inativo;

      if (usuarioIdApi == null) {
        // =====================================================================
        // CATEGORIA PADRÃO DO SISTEMA (SOMENTE LEITURA NO APP)
        // Não altera nome nem status local; apenas grava o `servidor_id`
        // correspondente para mapeamento de FK em produtos.
        // =====================================================================
        final locaisPadrao = await db.query(
          'categorias',
          where: 'usuario_id IS NULL AND LOWER(TRIM(nome_categoria)) = ?',
          whereArgs: [nomeApi.toLowerCase()],
        );

        if (locaisPadrao.isNotEmpty) {
          final idLocal = locaisPadrao.first['id_categoria'] as int;
          final servidorIdAtual = (locaisPadrao.first['servidor_id'] as num?)?.toInt();

          if (servidorIdAtual != servidorId) {
            await db.update(
              'categorias',
              {'servidor_id': servidorId},
              where: 'id_categoria = ?',
              whereArgs: [idLocal],
            );
            houveAlteracao = true;
          }
        }
      } else {
        // =====================================================================
        // CATEGORIA PERSONALIZADA DO USUÁRIO
        // =====================================================================
        final locaisUsuario = await db.query(
          'categorias',
          where: 'usuario_id = ? AND (servidor_id = ? OR LOWER(TRIM(nome_categoria)) = ?)',
          whereArgs: [usuarioId, servidorId, nomeApi.toLowerCase()],
        );

        if (locaisUsuario.isNotEmpty) {
          final local = locaisUsuario.first;
          final idLocal = local['id_categoria'] as int;
          final flagSync = (local['flag_sincronizado'] as int?) ?? 1;

          // Só sobrescreve se não houver alteração local pendente de envio
          if (flagSync == 1) {
            final precisaAtualizar = local['servidor_id'] != servidorId ||
                local['nome_categoria'] != nomeApi ||
                local['ativo'] != ativoApi;

            if (precisaAtualizar) {
              await db.update(
                'categorias',
                {
                  'servidor_id': servidorId,
                  'nome_categoria': nomeApi,
                  'ativo': ativoApi,
                  'status_categoria': statusLocal,
                  'flag_sincronizado': 1,
                },
                where: 'id_categoria = ?',
                whereArgs: [idLocal],
              );
              houveAlteracao = true;
            }
          }
        } else {
          // Categoria criada em outro dispositivo: insere no SQLite local
          await db.insert('categorias', {
            'servidor_id': servidorId,
            'usuario_id': usuarioId,
            'nome_categoria': nomeApi,
            'ativo': ativoApi,
            'status_categoria': statusLocal,
            'flag_sincronizado': 1,
          });
          houveAlteracao = true;
        }
      }
    }

    return houveAlteracao;
  }
}

/// Provider global Riverpod para o serviço de sincronização de categorias.
final sincronizacaoCategoriasServiceProvider = Provider<SincronizacaoCategoriasService>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return SincronizacaoCategoriasService(authRepo: authRepo);
});