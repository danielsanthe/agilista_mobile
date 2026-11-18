import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../nucleo/constantes/estados_constants.dart';
import '../nucleo/constantes/status_constants.dart';
import '../nucleo/database/app_database.dart';
import '../repositories/autenticacao_repository.dart';
import '../repositories/exclusao_repository.dart';
import '../controllers/autenticacao_controller.dart';
import 'sincronizacao_produtos_service.dart';

/// ============================================================================
/// SERVIÇO DE SINCRONIZAÇÃO OFFLINE-FIRST — LISTAS E ITENS (FLUTTER <-> FASTAPI)
/// ============================================================================
/// Orquestra a sincronização bidirecional entre as tabelas locais `listas` e
/// `itens_lista` (SQLite) e os endpoints `/api/v1/listas` e `/api/v1/itens-lista`
/// da Agilista-api, respeitando integralmente a máquina de estados do servidor:
///
///   0. Garante `servidor_id` de Categorias e Produtos antes de enviar itens.
///   1. Processa exclusões pendentes de `itens_lista` e `listas`.
///   2. Envia listas planejadas novas atomicamente com seus itens (`POST /com-itens`)
///      somente após possuírem ao menos 1 item, conduzindo o ciclo:
///      Planejada -> Em Andamento (com estabelecimento) -> Concluída.
///   3. Baixa listas e itens do servidor (`GET /api/v1/listas/` e `/itens`).
class SincronizacaoListasService {
  /// Instância do banco de dados SQLite local do dispositivo.
  final AppDatabase _db;

  /// Repositório responsável pelos tokens JWT e sessão do usuário autenticado.
  final AuthRepository _authRepo;

  /// Repositório de fila de exclusões realizadas offline para sincronização posterior.
  final ExclusaoRepository _exclusaoRepo;

  /// Serviço de sincronização prévia de categorias e catálogo pessoal de produtos.
  final SincronizacaoProdutosService _syncProdutos;

  /// URL base da API FastAPI injetada em tempo de compilação (`--dart-define`).
  /// Utiliza `http://10.0.2.2:8000` como fallback padrão para o emulador Android.
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Construtor com suporte a injeção de dependências para testes e Riverpod.
  SincronizacaoListasService({
    required this._authRepo,
    required this._syncProdutos,
    AppDatabase? db,
    ExclusaoRepository? exclusaoRepo,
  })  : _db = db ?? AppDatabase.instance,
        _exclusaoRepo = exclusaoRepo ?? ExclusaoRepository();

  /// Verifica rapidamente (máximo 2s) se a Agilista-api está acessível na rede.
  /// Evita atrasos acumulados na interface quando o dispositivo está offline.
  Future<bool> _servidorDisponivel() async {
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/openapi.json'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Trava estática anti-concorrência para impedir que múltiplas telas disparem
  /// ciclos simultâneos de sincronização de listas, evitando duplicações HTTP.
  static Future<bool>? _sincronizacaoListasEmAndamento;

  /// Ponto de entrada público para sincronizar listas e itens do usuário logado.
  /// Reutiliza a Future em andamento caso já exista uma sincronização ativa
  /// e retorna `true` se houve qualquer atualização gravada no SQLite local.
  Future<bool> sincronizarListasEItens(int usuarioId) {
    if (_sincronizacaoListasEmAndamento != null) {
      return _sincronizacaoListasEmAndamento!;
    }
    _sincronizacaoListasEmAndamento =
        _executarSincronizarListasEItens(usuarioId).whenComplete(() {
      _sincronizacaoListasEmAndamento = null;
    });
    return _sincronizacaoListasEmAndamento!;
  }

  /// Executa internamente as 4 etapas sequenciais do ciclo offline-first.
  Future<bool> _executarSincronizarListasEItens(int usuarioId) async {
    bool houveAlteracaoLocal = false;

    try {
      // Recupera o token JWT ativo; sem autenticação válida, opera apenas localmente
      final token = await _authRepo.obterTokenAcesso();
      if (token == null || token.isEmpty) {
        debugPrint('[SincronizacaoListas] Sem token JWT ativo. Sincronização adiada.');
        return false;
      }

      // Fast-fail em 2 segundos caso não haja conexão com o servidor FastAPI
      final online = await _servidorDisponivel();
      if (!online) {
        debugPrint('[SincronizacaoListas] Servidor indisponível no momento. Operando offline.');
        return false;
      }

      // Etapa 0: Garante que Categorias e Produtos já possuam `servidor_id`
      // antes de traduzir os vínculos `produto_id` dos itens das listas
      await _syncProdutos.sincronizarProdutos(usuarioId);

      // Etapa 1: Envia exclusões pendentes (itens primeiro, depois listas)
      await _sincronizarExclusoes(token);

      // Etapa 2: Envia listas e itens criados ou alterados localmente (Push)
      final alterouNoPush = await _sincronizarPendenciasLocais(usuarioId, token);
      if (alterouNoPush) houveAlteracaoLocal = true;

      // Etapa 3: Baixa listas e itens do servidor e reconcilia com o SQLite (Pull)
      final alterouNoPull = await _baixarListasEItensDoServidor(usuarioId, token);
      if (alterouNoPull) houveAlteracaoLocal = true;
    } catch (e) {
      debugPrint('[SincronizacaoListas] Modo offline ou falha temporária: $e');
    }

    return houveAlteracaoLocal;
  }

  /// Executa uma requisição HTTP autenticada (GET, POST, PUT ou DELETE).
  /// Em caso de expiração do token (HTTP 401), renova automaticamente via
  /// `refresh_token` e repete a requisição uma única vez.
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
          return http
              .post(uri, headers: headers, body: payload)
              .timeout(const Duration(seconds: 12));
        case 'PUT':
          return http
              .put(uri, headers: headers, body: payload)
              .timeout(const Duration(seconds: 12));
        case 'DELETE':
          return http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
        default:
          return http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
      }
    }

    http.Response response = await enviar(tokenInicial);

    // Se o access_token expirou, solicita renovação e reenvia
    if (response.statusCode == 401) {
      final novoToken = await _authRepo.renovarTokenAcesso();
      if (novoToken != null && novoToken.isNotEmpty) {
        response = await enviar(novoToken);
      }
    }

    return response;
  }

  /// Traduz o `id_produto` local do SQLite para o `servidor_id` correspondente
  /// na tabela `produtos_usuario` da API FastAPI.
  Future<int?> _obterProdutoServidorId(int? idProdutoLocal) async {
    if (idProdutoLocal == null) return null;
    final db = await _db.database;
    final rows = await db.query(
      'produtos',
      columns: ['servidor_id'],
      where: 'id_produto = ?',
      whereArgs: [idProdutoLocal],
    );
    if (rows.isEmpty) return null;
    return (rows.first['servidor_id'] as num?)?.toInt();
  }

  /// Traduz o `produto_id` remoto (`servidor_id`) vindo da API para o `id_produto`
  /// local correspondente na tabela `produtos` do SQLite.
  Future<int?> _obterProdutoLocalId(int? produtoServidorId) async {
    if (produtoServidorId == null) return null;
    final db = await _db.database;
    final rows = await db.query(
      'produtos',
      columns: ['id_produto'],
      where: 'servidor_id = ?',
      whereArgs: [produtoServidorId],
    );
    if (rows.isEmpty) return null;
    return (rows.first['id_produto'] as num?)?.toInt();
  }

  /// ==========================================================================
  /// ETAPA 1 — PUSH DE EXCLUSÕES PENDENTES
  /// ==========================================================================
  /// Envia primeiro as exclusões de `itens_lista` e depois as de `listas`,
  /// removendo cada pendência da fila local após confirmação ou 404/409.
  Future<void> _sincronizarExclusoes(String token) async {
    final pendentes = await _exclusaoRepo.obterExclusoesPendentes();

    // 1.1 Exclui itens avulsos removidos offline
    final exclusoesItens = pendentes.where((e) => e['tabela'] == 'itens_lista');
    for (final item in exclusoesItens) {
      final idExclusao = item['id_exclusao'] as int;
      final servidorId = (item['servidor_id'] as num?)?.toInt();

      // Se o item nunca chegou a ser enviado ao servidor, apenas limpa a fila
      if (servidorId == null) {
        await _exclusaoRepo.removerPendencia(idExclusao);
        continue;
      }

      final uri = Uri.parse('$_apiBaseUrl/api/v1/itens-lista/$servidorId');
      final response = await _requisicaoAutenticada(
        metodo: 'DELETE',
        uri: uri,
        tokenInicial: token,
      );

      if (response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 404 ||
          response.statusCode == 409) {
        await _exclusaoRepo.removerPendencia(idExclusao);
      }
    }

    // 1.2 Exclui listas removidas offline (o servidor remove os itens via CASCADE)
    final exclusoesListas = pendentes.where((e) => e['tabela'] == 'listas');
    for (final item in exclusoesListas) {
      final idExclusao = item['id_exclusao'] as int;
      final servidorId = (item['servidor_id'] as num?)?.toInt();

      // Se a lista nunca existiu no servidor, apenas limpa a fila local
      if (servidorId == null) {
        await _exclusaoRepo.removerPendencia(idExclusao);
        continue;
      }

      final uri = Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorId');
      final response = await _requisicaoAutenticada(
        metodo: 'DELETE',
        uri: uri,
        tokenInicial: token,
      );

      if (response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 404 ||
          response.statusCode == 409) {
        await _exclusaoRepo.removerPendencia(idExclusao);
      }
    }
  }

  /// ==========================================================================
  /// ETAPA 2 — PUSH DE LISTAS E ITENS PENDENTES (MÁQUINA DE ESTADOS)
  /// ==========================================================================
  /// Conduz cada lista pendente do usuário pelo ciclo de vida da API:
  ///   - Passo A: Cria lista planejada + itens via `POST /listas/com-itens`
  ///              (somente quando há pelo menos 1 item planejado).
  ///   - Passo B: Atualiza dados de planejamento e avança para `Em Andamento`
  ///              (informando o estabelecimento).
  ///   - Passo C: Sincroniza compras realizadas, itens fora da lista e encerra
  ///              como `Concluída` caso a compra já tenha sido finalizada.
  Future<bool> _sincronizarPendenciasLocais(int usuarioId, String token) async {
    final db = await _db.database;
    bool houveAlteracao = false;

    // Consulta todas as listas pertencentes ao usuário autenticado no SQLite
    final todasListas = await db.query(
      'listas',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'id_lista ASC',
    );

    for (final listaMap in todasListas) {
      final idListaLocal = listaMap['id_lista'] as int;
      int? servidorIdLista = (listaMap['servidor_id'] as num?)?.toInt();
      final flagSyncLista = (listaMap['flag_sincronizado'] as int?) ?? 0;

      // Carrega todos os itens vinculados à lista local
      final itensDaLista = await db.query(
        'itens_lista',
        where: 'lista_id = ?',
        whereArgs: [idListaLocal],
        orderBy: 'id_item_lista ASC',
      );

      // Verifica se existe algum item local aguardando envio ou atualização
      final temItemPendente = itensDaLista.any(
        (i) => ((i['flag_sincronizado'] as int?) ?? 0) == 0,
      );

      // Se a lista e todos os seus itens já estão sincronizados, avança para a próxima
      if (flagSyncLista == 1 && !temItemPendente) {
        continue;
      }

      // Extrai e normaliza os atributos da lista local
      final nomeLista = (listaMap['nome_lista'] as String).trim();
      final valorOrcamento = (listaMap['valor_orcamento'] as num?)?.toDouble() ?? 0.0;
      final statusLocal = (listaMap['status_lista'] as String?) ?? StatusLista.planejada;

      // No planejamento em casa, o estabelecimento pode ser nulo;
      // ele só será obrigatório ao iniciar a compra (Passo B).
      final estabBruto = (listaMap['nome_estabelecimento'] as String?)?.trim();
      final estabelecimento =
          (estabBruto != null && estabBruto.isNotEmpty) ? estabBruto : null;

      final endereco = (listaMap['endereco_estabelecimento'] as String?)?.trim();
      final bairro = (listaMap['bairro'] as String?)?.trim();
      final cidade = (listaMap['cidade'] as String?)?.trim();
      final uf = EstadosConstants.normalizarUf(listaMap['uf'] as String?);

      String statusNoServidor = statusLocal;

      // -----------------------------------------------------------------------
      // PASSO A: Criar lista planejada no servidor (`servidor_id == null`)
      // Regra de negócio: toda lista planejada deve possuir ao menos 1 item.
      // Enquanto estiver vazia, permanece apenas no SQLite aguardando o 1º item.
      // -----------------------------------------------------------------------
      if (servidorIdLista == null) {
        final itensPlanejados = itensDaLista
            .where((i) => ((i['flag_fora_da_lista'] as int?) ?? 0) == 0)
            .toList();

        // Aguarda o usuário adicionar pelo menos 1 item antes de enviar à API
        if (itensPlanejados.isEmpty) {
          continue;
        }

        // Monta o array de itens planejados traduzindo cada `produto_id` local
        final payloadItens = [];
        for (final itemMap in itensPlanejados) {
          final produtoServidorId = await _obterProdutoServidorId(
            (itemMap['produto_id'] as num?)?.toInt(),
          );
          final flagPromo = (itemMap['flag_promocao'] as int?) ?? 0;
          final qtdMinPromo = (itemMap['qtd_minima_promocional'] as num?)?.toDouble();
          final precoPromo = (itemMap['preco_promocional'] as num?)?.toDouble();

          // Valida consistência dos parâmetros promocionais antes do envio
          final temPromoValida = flagPromo == 1 &&
              qtdMinPromo != null &&
              qtdMinPromo > 0 &&
              precoPromo != null;

          // Garante nome válido, quantidade positiva e omite campos nulos/inválidos
          final nomePlan = (itemMap['nome_item_planejado'] as String).trim();
          if (nomePlan.isEmpty) continue;

          final qtdPlan = (itemMap['qtd_planejada'] as num?)?.toDouble() ?? 1.0;
          final int? prodIdValido =
              (produtoServidorId != null && produtoServidorId > 0)
                  ? produtoServidorId
                  : null;
          final double? qtdMinPromoValida = temPromoValida ? qtdMinPromo : null;
          final double? precoPromoValido = temPromoValida ? precoPromo : null;

          payloadItens.add({
            'produto_id': ?prodIdValido,
            'nome_item_planejado': nomePlan,
            'qtd_planejada': qtdPlan > 0 ? qtdPlan : 1.0,
            'preco_estimado': (itemMap['preco_estimado'] as num?)?.toDouble() ?? 0.0,
            'flag_promocao': temPromoValida ? 1 : 0,
            'qtd_minima_promocional': ?qtdMinPromoValida,
            'preco_promocional': ?precoPromoValido,
            'flag_fora_da_lista': 0,
          });
        }

        // Monta o payload atômico de criação da lista + itens planejados
        final bodyCriacaoComItens = <String, dynamic>{
          'nome_lista': nomeLista,
          'valor_orcamento': valorOrcamento,
          'nome_estabelecimento': ?estabelecimento,
          if (endereco != null && endereco.isNotEmpty)
            'endereco_estabelecimento': endereco,
          if (bairro != null && bairro.isNotEmpty) 'bairro': bairro,
          if (cidade != null && cidade.isNotEmpty) 'cidade': cidade,
          if (uf != null && uf.isNotEmpty) 'uf': uf,
          'itens': payloadItens,
        };

        final respCreate = await _requisicaoAutenticada(
          metodo: 'POST',
          uri: Uri.parse('$_apiBaseUrl/api/v1/listas/com-itens'),
          tokenInicial: token,
          body: bodyCriacaoComItens,
        );

        if (respCreate.statusCode == 201 || respCreate.statusCode == 200) {
          final data = jsonDecode(utf8.decode(respCreate.bodyBytes)) as Map<String, dynamic>;
          servidorIdLista = (data['id_lista'] as num?)?.toInt();
          statusNoServidor = (data['status_lista'] as String?) ?? StatusLista.planejada;

          if (servidorIdLista != null) {
            // Grava o ID gerado pelo servidor na tabela local `listas`
            await db.update(
              'listas',
              {
                'servidor_id': servidorIdLista,
                if (statusNoServidor == statusLocal) 'flag_sincronizado': 1,
              },
              where: 'id_lista = ?',
              whereArgs: [idListaLocal],
            );

            // Busca os itens recém-criados no servidor para mapear cada `servidor_id` local
            // e marcá-los imediatamente como sincronizados, evitando reenvio no Passo B.
            final respItensCriados = await _requisicaoAutenticada(
              metodo: 'GET',
              uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista/itens'),
              tokenInicial: token,
            );
            if (respItensCriados.statusCode == 200) {
              final remotos =
                  jsonDecode(utf8.decode(respItensCriados.bodyBytes)) as List<dynamic>;
              final idsRemotosUsados = <int>{};

              for (int idx = 0; idx < itensPlanejados.length; idx++) {
                final idLocalItem = itensPlanejados[idx]['id_item_lista'] as int;
                final nomeLocalNorm =
                    (itensPlanejados[idx]['nome_item_planejado'] as String)
                        .trim()
                        .toLowerCase();

                Map<String, dynamic>? mapRemoto;

                // 1. Tenta casar pelo mesmo índice se o nome corresponder
                if (idx < remotos.length) {
                  final candidato = remotos[idx] as Map<String, dynamic>;
                  final idCand = (candidato['id_item_lista'] as num?)?.toInt();
                  final nomeCand = (candidato['nome_item_planejado'] as String? ?? '')
                      .trim()
                      .toLowerCase();
                  if (idCand != null &&
                      !idsRemotosUsados.contains(idCand) &&
                      nomeCand == nomeLocalNorm) {
                    mapRemoto = candidato;
                  }
                }

                // 2. Fallback: procura pelo primeiro item remoto não usado com mesmo nome
                if (mapRemoto == null) {
                  for (final raw in remotos) {
                    final r = raw as Map<String, dynamic>;
                    final idCand = (r['id_item_lista'] as num?)?.toInt();
                    final nomeCand = (r['nome_item_planejado'] as String? ?? '')
                        .trim()
                        .toLowerCase();
                    if (idCand != null &&
                        !idsRemotosUsados.contains(idCand) &&
                        nomeCand == nomeLocalNorm) {
                      mapRemoto = r;
                      break;
                    }
                  }
                }

                if (mapRemoto != null) {
                  final idRemotoItem = (mapRemoto['id_item_lista'] as num).toInt();
                  idsRemotosUsados.add(idRemotoItem);

                  await db.update(
                    'itens_lista',
                    {
                      'servidor_id': idRemotoItem,
                      'flag_sincronizado': 1,
                    },
                    where: 'id_item_lista = ?',
                    whereArgs: [idLocalItem],
                  );
                }
              }
            }

            houveAlteracao = true;
          }
        } else {
          debugPrint(
            '[SincronizacaoListas] Falha ao criar lista "$nomeLista": ${respCreate.statusCode} ${respCreate.body}',
          );
          continue;
        }
      } else {
        // Caso a lista já exista no servidor, consulta seu status atual para guiar o fluxo
        final respGet = await _requisicaoAutenticada(
          metodo: 'GET',
          uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista'),
          tokenInicial: token,
        );
        if (respGet.statusCode == 200) {
          final data = jsonDecode(utf8.decode(respGet.bodyBytes)) as Map<String, dynamic>;
          statusNoServidor = (data['status_lista'] as String?) ?? StatusLista.planejada;
        }
      }

      if (servidorIdLista == null) continue;

      // -----------------------------------------------------------------------
      // PASSO B: Enquanto a lista estiver 'Planejada' no servidor:
      // 1) Atualiza dados de planejamento da lista (se editada offline)
      // 2) Envia novos itens planejados adicionados posteriormente
      // 3) Se a lista local já iniciou a compra, avança para 'Em Andamento'
      // -----------------------------------------------------------------------
      if (statusNoServidor == StatusLista.planejada) {
        if (flagSyncLista == 0 && statusLocal == StatusLista.planejada) {
          await _requisicaoAutenticada(
            metodo: 'PUT',
            uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista'),
            tokenInicial: token,
            body: {
              'nome_lista': nomeLista,
              'valor_orcamento': valorOrcamento,
              'nome_estabelecimento': ?estabelecimento,
              if (endereco != null && endereco.isNotEmpty)
                'endereco_estabelecimento': endereco,
              if (bairro != null && bairro.isNotEmpty) 'bairro': bairro,
              if (cidade != null && cidade.isNotEmpty) 'cidade': cidade,
              if (uf != null && uf.isNotEmpty) 'uf': uf,
            },
          );
        }

        // Sincroniza itens planejados novos ou editados antes do início da compra
        // (lê novamente do SQLite para garantir que itens recém-criados no Passo A não sejam reenviados)
        final itensAtualizados = await db.query(
          'itens_lista',
          where: 'lista_id = ?',
          whereArgs: [idListaLocal],
          orderBy: 'id_item_lista ASC',
        );

        for (final itemMap in itensAtualizados) {
          final flagFora = (itemMap['flag_fora_da_lista'] as int?) ?? 0;
          if (flagFora != 0) continue;

          final alterouItem = await _enviarItemPlanejado(
            servidorIdLista: servidorIdLista,
            itemMap: itemMap,
            token: token,
          );
          if (alterouItem) houveAlteracao = true;
        }

        // Transição Planejada -> Em Andamento (exige nome_estabelecimento no backend)
        if (statusLocal == StatusLista.emAndamento || statusLocal == StatusLista.concluida) {
          final respStart = await _requisicaoAutenticada(
            metodo: 'PUT',
            uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista'),
            tokenInicial: token,
            body: {
              'status_lista': StatusLista.emAndamento,
              'nome_estabelecimento': estabelecimento ?? 'Estabelecimento Não Informado',
              if (endereco != null && endereco.isNotEmpty)
                'endereco_estabelecimento': endereco,
              if (bairro != null && bairro.isNotEmpty) 'bairro': bairro,
              if (cidade != null && cidade.isNotEmpty) 'cidade': cidade,
              if (uf != null && uf.isNotEmpty) 'uf': uf,
            },
          );

          if (respStart.statusCode == 200) {
            statusNoServidor = StatusLista.emAndamento;
          } else {
            debugPrint(
              '[SincronizacaoListas] Falha ao iniciar compra da lista "$nomeLista": ${respStart.statusCode} ${respStart.body}',
            );
          }
        }
      }

      // -----------------------------------------------------------------------
      // PASSO C: Com a lista 'Em Andamento' no servidor:
      // 1) Atualiza os itens planejados comprados (preços, quantidades, promoções)
      // 2) Cria ou atualiza itens fora da lista (`flag_fora_da_lista == 1`)
      // 3) Se a lista local já foi finalizada, encerra como 'Concluída'
      // -----------------------------------------------------------------------
      if (statusNoServidor == StatusLista.emAndamento) {
        final itensEmAndamento = await db.query(
          'itens_lista',
          where: 'lista_id = ?',
          whereArgs: [idListaLocal],
          orderBy: 'id_item_lista ASC',
        );

        for (final itemMap in itensEmAndamento) {
          final alterouItem = await _enviarItemEmAndamento(
            servidorIdLista: servidorIdLista,
            itemMap: itemMap,
            token: token,
          );
          if (alterouItem) houveAlteracao = true;
        }

        // Transição Em Andamento -> Concluída (payload exclusivo permitido pelo backend)
        if (statusLocal == StatusLista.concluida) {
          final respFinish = await _requisicaoAutenticada(
            metodo: 'PUT',
            uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista'),
            tokenInicial: token,
            body: {'status_lista': StatusLista.concluida},
          );

          if (respFinish.statusCode == 200) {
            statusNoServidor = StatusLista.concluida;
          } else {
            debugPrint(
              '[SincronizacaoListas] Falha ao concluir compra da lista "$nomeLista": ${respFinish.statusCode} ${respFinish.body}',
            );
          }
        }
      }

      // Marca a lista como sincronizada no SQLite quando o estado remoto acompanha o local
      if (statusNoServidor == statusLocal) {
        await db.update(
          'listas',
          {'flag_sincronizado': 1},
          where: 'id_lista = ?',
          whereArgs: [idListaLocal],
        );
        houveAlteracao = true;
      }
    }

    return houveAlteracao;
  }

  /// Envia ou atualiza um item planejado (`flag_fora_da_lista == 0`) enquanto
  /// a lista ainda está com status 'Planejada' no servidor.
  Future<bool> _enviarItemPlanejado({
    required int servidorIdLista,
    required Map<String, dynamic> itemMap,
    required String token,
  }) async {
    final db = await _db.database;
    final idItemLocal = itemMap['id_item_lista'] as int;
    final servidorIdItem = (itemMap['servidor_id'] as num?)?.toInt();
    final flagSync = (itemMap['flag_sincronizado'] as int?) ?? 0;

    // Ignora itens já sincronizados e mapeados
    if (flagSync == 1 && servidorIdItem != null) return false;

    final produtoServidorId = await _obterProdutoServidorId(
      (itemMap['produto_id'] as num?)?.toInt(),
    );
    final nomeItem = (itemMap['nome_item_planejado'] as String).trim();
    final qtdPlanejada = (itemMap['qtd_planejada'] as num?)?.toDouble() ?? 1.0;
    final precoEstimado = (itemMap['preco_estimado'] as num?)?.toDouble() ?? 0.0;
    final flagPromocao = (itemMap['flag_promocao'] as int?) ?? 0;
    final qtdMinPromo = (itemMap['qtd_minima_promocional'] as num?)?.toDouble();
    final precoPromo = (itemMap['preco_promocional'] as num?)?.toDouble();

    final temPromoValida = flagPromocao == 1 &&
        qtdMinPromo != null &&
        qtdMinPromo > 0 &&
        precoPromo != null;

    if (servidorIdItem == null) {
      // Cria novo item planejado na lista existente (`POST /listas/{id}/itens`)
      final resp = await _requisicaoAutenticada(
        metodo: 'POST',
        uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista/itens'),
        tokenInicial: token,
        body: {
          'produto_id': produtoServidorId,
          'nome_item_planejado': nomeItem,
          'qtd_planejada': qtdPlanejada,
          'preco_estimado': precoEstimado,
          'flag_promocao': temPromoValida ? 1 : 0,
          'qtd_minima_promocional': temPromoValida ? qtdMinPromo : null,
          'preco_promocional': temPromoValida ? precoPromo : null,
          'flag_fora_da_lista': 0,
        },
      );

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final novoServidorId = (data['id_item_lista'] as num?)?.toInt();

        await db.update(
          'itens_lista',
          {
            'servidor_id': ?novoServidorId,
            'flag_sincronizado': 1,
          },
          where: 'id_item_lista = ?',
          whereArgs: [idItemLocal],
        );
        return true;
      }
    } else {
      // Atualiza item planejado já existente (`PUT /itens-lista/{id_item}`)
      final resp = await _requisicaoAutenticada(
        metodo: 'PUT',
        uri: Uri.parse('$_apiBaseUrl/api/v1/itens-lista/$servidorIdItem'),
        tokenInicial: token,
        body: {
          'produto_id': ?produtoServidorId,
          'nome_item_planejado': nomeItem,
          'qtd_planejada': qtdPlanejada,
          'preco_estimado': precoEstimado,
          'flag_promocao': temPromoValida ? 1 : 0,
          'qtd_minima_promocional': temPromoValida ? qtdMinPromo : null,
          'preco_promocional': temPromoValida ? precoPromo : null,
        },
      );

      if (resp.statusCode == 200) {
        await db.update(
          'itens_lista',
          {'flag_sincronizado': 1},
          where: 'id_item_lista = ?',
          whereArgs: [idItemLocal],
        );
        return true;
      }
    }

    return false;
  }

  /// Sincroniza a execução de compra (`Em Andamento`) de cada item:
  ///   - Caso 1: Cria item fora da lista em 1 etapa (`flag_fora_da_lista == 1`).
  ///   - Caso 2: Atualiza status, quantidade comprada, preço unitário e promoção
  ///             de itens já cadastrados no servidor.
  Future<bool> _enviarItemEmAndamento({
    required int servidorIdLista,
    required Map<String, dynamic> itemMap,
    required String token,
  }) async {
    final db = await _db.database;
    final idItemLocal = itemMap['id_item_lista'] as int;
    final servidorIdItem = (itemMap['servidor_id'] as num?)?.toInt();
    final flagSync = (itemMap['flag_sincronizado'] as int?) ?? 0;

    if (flagSync == 1 && servidorIdItem != null) return false;

    final produtoServidorId = await _obterProdutoServidorId(
      (itemMap['produto_id'] as num?)?.toInt(),
    );
    final nomeItem = (itemMap['nome_item_planejado'] as String).trim();
    final flagFora = (itemMap['flag_fora_da_lista'] as int?) ?? 0;
    final statusItem = (itemMap['status_item'] as String?) ?? StatusItem.pendente;
    final qtdComprada = (itemMap['qtd_comprada'] as num?)?.toDouble() ?? 0.0;
    final precoUnitario = (itemMap['preco_unitario'] as num?)?.toDouble() ?? 0.0;
    final flagPromocao = (itemMap['flag_promocao'] as int?) ?? 0;
    final qtdMinPromo = (itemMap['qtd_minima_promocional'] as num?)?.toDouble();
    final precoPromo = (itemMap['preco_promocional'] as num?)?.toDouble();

    final temPromoValida = flagPromocao == 1 &&
        qtdMinPromo != null &&
        qtdMinPromo > 0 &&
        precoPromo != null;

    // Caso 1: Novo item fora da lista adicionado durante a compra (`POST /listas/{id}/itens`)
    if (servidorIdItem == null && flagFora == 1) {
      final qtdValida = qtdComprada > 0 ? qtdComprada : 1.0;

      final resp = await _requisicaoAutenticada(
        metodo: 'POST',
        uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista/itens'),
        tokenInicial: token,
        body: {
          'produto_id': produtoServidorId,
          'nome_item_planejado': nomeItem,
          'qtd_planejada': 0.0,
          'preco_estimado': 0.0,
          'qtd_comprada': qtdValida,
          'preco_unitario': precoUnitario,
          'flag_promocao': temPromoValida ? 1 : 0,
          'qtd_minima_promocional': temPromoValida ? qtdMinPromo : null,
          'preco_promocional': temPromoValida ? precoPromo : null,
          'flag_fora_da_lista': 1,
        },
      );

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final novoServidorId = (data['id_item_lista'] as num?)?.toInt();

        await db.update(
          'itens_lista',
          {
            'servidor_id': ?novoServidorId,
            'flag_sincronizado': 1,
          },
          where: 'id_item_lista = ?',
          whereArgs: [idItemLocal],
        );
        return true;
      }
      return false;
    }

    // Caso 2: Item já existente no servidor (planejado marcado como Comprado/Pendente ou FL editado)
    if (servidorIdItem != null) {
      final statusFinal = flagFora == 1
          ? 'Comprado FL'
          : (statusItem == StatusItem.comprado ? StatusItem.comprado : StatusItem.pendente);

      final double? qtdPromoValida = temPromoValida ? qtdMinPromo : null;
      final double? precoPromoValido = temPromoValida ? precoPromo : null;

      // Não envia campos de planejamento (`nome_item_planejado`, `qtd_planejada`, `preco_estimado`),
      // pois o backend bloqueia alterações de planejamento durante 'Em Andamento'
      final bodyUpdate = <String, dynamic>{
        'produto_id': ?produtoServidorId,
        'status_item': statusFinal,
        'flag_promocao': temPromoValida ? 1 : 0,
        'qtd_minima_promocional': ?qtdPromoValida,
        'preco_promocional': ?precoPromoValido,
      };

      if (statusFinal != StatusItem.pendente) {
        bodyUpdate['qtd_comprada'] = qtdComprada > 0 ? qtdComprada : 1.0;
        bodyUpdate['preco_unitario'] = precoUnitario;
      }

      final resp = await _requisicaoAutenticada(
        metodo: 'PUT',
        uri: Uri.parse('$_apiBaseUrl/api/v1/itens-lista/$servidorIdItem'),
        tokenInicial: token,
        body: bodyUpdate,
      );

      if (resp.statusCode == 200) {
        await db.update(
          'itens_lista',
          {'flag_sincronizado': 1},
          where: 'id_item_lista = ?',
          whereArgs: [idItemLocal],
        );
        return true;
      }
    }

    return false;
  }

  /// ==========================================================================
  /// ETAPA 3 — PULL DO SERVIDOR (RECONCILIAÇÃO DE LISTAS E ITENS REMOTOS)
  /// ==========================================================================
  /// Baixa todas as listas do usuário na API (`GET /api/v1/listas/?status=todas`),
  /// insere ou atualiza os registros locais já sincronizados (`flag_sincronizado == 1`)
  /// e dispara a reconciliação dos itens de cada lista.
  Future<bool> _baixarListasEItensDoServidor(int usuarioId, String token) async {
    final respListas = await _requisicaoAutenticada(
      metodo: 'GET',
      uri: Uri.parse('$_apiBaseUrl/api/v1/listas/?status=todas'),
      tokenInicial: token,
    );

    if (respListas.statusCode != 200) return false;

    final listasApi = jsonDecode(utf8.decode(respListas.bodyBytes)) as List<dynamic>;
    final db = await _db.database;
    bool houveAlteracao = false;

    for (final itemLista in listasApi) {
      final mapApi = itemLista as Map<String, dynamic>;
      final servidorIdLista = (mapApi['id_lista'] as num).toInt();
      final nomeApi = (mapApi['nome_lista'] as String).trim();
      final orcamentoApi = (mapApi['valor_orcamento'] as num?)?.toDouble() ?? 0.0;
      final totalAtualApi = (mapApi['valor_total_atual'] as num?)?.toDouble() ?? 0.0;
      final statusApi = (mapApi['status_lista'] as String?) ?? StatusLista.planejada;
      final estabApi = mapApi['nome_estabelecimento'] as String?;
      final endApi = mapApi['endereco_estabelecimento'] as String?;
      final bairroApi = mapApi['bairro'] as String?;
      final cidadeApi = mapApi['cidade'] as String?;
      final ufApi = EstadosConstants.normalizarUf(mapApi['uf'] as String?);
      final dataCriacaoApi =
          mapApi['data_criacao'] as String? ?? DateTime.now().toIso8601String();
      final dataInicioApi = mapApi['data_hora_inicio'] as String?;
      final dataTerminoApi = mapApi['data_hora_termino'] as String?;

      // Procura primeiramente pelo vínculo explícito `servidor_id`
      var locais = await db.query(
        'listas',
        where: 'servidor_id = ?',
        whereArgs: [servidorIdLista],
      );

      // Fallback por nome normalizado para reconciliar listas criadas anteriormente
      if (locais.isEmpty) {
        locais = await db.query(
          'listas',
          where: 'usuario_id = ? AND LOWER(TRIM(nome_lista)) = ?',
          whereArgs: [usuarioId, nomeApi.toLowerCase()],
        );
      }

      int idListaLocal;

      if (locais.isNotEmpty) {
        final local = locais.first;
        idListaLocal = local['id_lista'] as int;
        final flagSync = (local['flag_sincronizado'] as int?) ?? 1;

        // Só sobrescreve dados locais se não houver alterações offline pendentes
        if (flagSync == 1) {
          await db.update(
            'listas',
            {
              'servidor_id': servidorIdLista,
              'nome_lista': nomeApi,
              'valor_orcamento': orcamentoApi,
              'valor_total_atual': totalAtualApi,
              'status_lista': statusApi,
              'nome_estabelecimento': estabApi,
              'endereco_estabelecimento': endApi,
              'bairro': bairroApi,
              'cidade': cidadeApi,
              'uf': ufApi,
              'data_criacao': dataCriacaoApi,
              'data_hora_inicio': dataInicioApi,
              'data_hora_termino': dataTerminoApi,
              'flag_sincronizado': 1,
            },
            where: 'id_lista = ?',
            whereArgs: [idListaLocal],
          );
          houveAlteracao = true;
        }
      } else {
        // Insere no SQLite local uma lista criada em outro dispositivo ou no portal Web
        idListaLocal = await db.insert('listas', {
          'servidor_id': servidorIdLista,
          'usuario_id': usuarioId,
          'nome_lista': nomeApi,
          'valor_orcamento': orcamentoApi,
          'valor_total_atual': totalAtualApi,
          'status_lista': statusApi,
          'nome_estabelecimento': estabApi,
          'endereco_estabelecimento': endApi,
          'bairro': bairroApi,
          'cidade': cidadeApi,
          'uf': ufApi,
          'data_criacao': dataCriacaoApi,
          'data_hora_inicio': dataInicioApi,
          'data_hora_termino': dataTerminoApi,
          'flag_sincronizado': 1,
        });
        houveAlteracao = true;
      }

      // Baixa e reconcilia os itens vinculados a esta lista
      final alterouItens = await _baixarItensDaLista(
        idListaLocal: idListaLocal,
        servidorIdLista: servidorIdLista,
        token: token,
      );
      if (alterouItens) houveAlteracao = true;
    }

    return houveAlteracao;
  }

  /// Sincroniza os itens remotos de uma lista (`GET /api/v1/listas/{id}/itens`)
  /// com a tabela local `itens_lista`, traduzindo `produto_id` para o ID local.
  Future<bool> _baixarItensDaLista({
    required int idListaLocal,
    required int servidorIdLista,
    required String token,
  }) async {
    final respItens = await _requisicaoAutenticada(
      metodo: 'GET',
      uri: Uri.parse('$_apiBaseUrl/api/v1/listas/$servidorIdLista/itens'),
      tokenInicial: token,
    );

    if (respItens.statusCode != 200) return false;

    final itensApi = jsonDecode(utf8.decode(respItens.bodyBytes)) as List<dynamic>;
    final db = await _db.database;
    bool houveAlteracao = false;

    for (final itemRaw in itensApi) {
      final mapApi = itemRaw as Map<String, dynamic>;
      final servidorIdItem = (mapApi['id_item_lista'] as num).toInt();
      final produtoServidorId = (mapApi['produto_id'] as num?)?.toInt();

      // Converte o ID remoto do produto no ID local da tabela `produtos`
      final produtoLocalId = await _obterProdutoLocalId(produtoServidorId);

      final nomeItem = (mapApi['nome_item_planejado'] as String).trim();
      final qtdPlanejada = (mapApi['qtd_planejada'] as num?)?.toDouble() ?? 1.0;
      final precoEstimado = (mapApi['preco_estimado'] as num?)?.toDouble() ?? 0.0;
      final qtdComprada = (mapApi['qtd_comprada'] as num?)?.toDouble() ?? 0.0;
      final precoUnitario = (mapApi['preco_unitario'] as num?)?.toDouble() ?? 0.0;
      final subtotalItem = (mapApi['subtotal_item'] as num?)?.toDouble() ?? 0.0;
      final statusItem = (mapApi['status_item'] as String?) ?? StatusItem.pendente;
      final flagPromocao = (mapApi['flag_promocao'] as num?)?.toInt() ?? 0;
      final qtdMinPromo = (mapApi['qtd_minima_promocional'] as num?)?.toDouble();
      final precoPromo = (mapApi['preco_promocional'] as num?)?.toDouble();
      final flagFora = (mapApi['flag_fora_da_lista'] as num?)?.toInt() ?? 0;

      var locais = await db.query(
        'itens_lista',
        where: 'servidor_id = ?',
        whereArgs: [servidorIdItem],
      );

      if (locais.isEmpty) {
        locais = await db.query(
          'itens_lista',
          where: 'lista_id = ? AND LOWER(TRIM(nome_item_planejado)) = ?',
          whereArgs: [idListaLocal, nomeItem.toLowerCase()],
        );
      }

      if (locais.isNotEmpty) {
        final local = locais.first;
        final idItemLocal = local['id_item_lista'] as int;
        final flagSync = (local['flag_sincronizado'] as int?) ?? 1;

        if (flagSync == 1) {
          await db.update(
            'itens_lista',
            {
              'servidor_id': servidorIdItem,
              'lista_id': idListaLocal,
              'produto_id': produtoLocalId,
              'nome_item_planejado': nomeItem,
              'qtd_planejada': qtdPlanejada,
              'preco_estimado': precoEstimado,
              'qtd_comprada': qtdComprada,
              'preco_unitario': precoUnitario,
              'subtotal_item': subtotalItem,
              'status_item': statusItem,
              'flag_promocao': flagPromocao,
              'qtd_minima_promocional': qtdMinPromo,
              'preco_promocional': precoPromo,
              'flag_fora_da_lista': flagFora,
              'flag_sincronizado': 1,
            },
            where: 'id_item_lista = ?',
            whereArgs: [idItemLocal],
          );
          houveAlteracao = true;
        }
      } else {
        await db.insert('itens_lista', {
          'servidor_id': servidorIdItem,
          'lista_id': idListaLocal,
          'produto_id': produtoLocalId,
          'nome_item_planejado': nomeItem,
          'qtd_planejada': qtdPlanejada,
          'preco_estimado': precoEstimado,
          'qtd_comprada': qtdComprada,
          'preco_unitario': precoUnitario,
          'subtotal_item': subtotalItem,
          'status_item': statusItem,
          'flag_promocao': flagPromocao,
          'qtd_minima_promocional': qtdMinPromo,
          'preco_promocional': precoPromo,
          'flag_fora_da_lista': flagFora,
          'flag_sincronizado': 1,
        });
        houveAlteracao = true;
      }
    }

    return houveAlteracao;
  }
}

/// Provider global Riverpod que disponibiliza a instância de [SincronizacaoListasService].
final sincronizacaoListasServiceProvider = Provider<SincronizacaoListasService>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final syncProdutos = ref.watch(sincronizacaoProdutosServiceProvider);
  return SincronizacaoListasService(
    authRepo: authRepo,
    syncProdutos: syncProdutos,
  );
});