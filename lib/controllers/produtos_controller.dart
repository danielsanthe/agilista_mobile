import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/produto_model.dart';
import '../models/categoria_model.dart';
import '../nucleo/constantes/api_constants.dart';
import '../repositories/produtos_repository.dart';
import '../services/sincronizacao_produtos_service.dart';
import 'autenticacao_controller.dart';

/// ============================================================================
/// RESULTADO DA CONSULTA DE CÓDIGO DE BARRAS (EAN / GTIN)
/// ============================================================================
/// Encapsula o retorno da busca por código de barras para a camada de View:
/// - `produtoLocal`: Preenchido quando o produto já existe no SQLite local (modo edição).
/// - `descricaoExterna`: Preenchida quando a descrição foi obtida no Catálogo Global da API ou bases públicas.
/// - `unidadeExterna`: Preenchida quando a unidade de medida padrão foi obtida no Catálogo Global da API.
/// - `categoriaIdExterna`: Preenchida quando a categoria padrão foi obtida no Catálogo Global da API.
/// - `aviso`: Mensagem informativa caso ocorra limite de franquia ou código não encontrado.
class ResultadoBuscaCodigoBarras {
  final ProdutoModel? produtoLocal;
  final String? descricaoExterna;
  final String? unidadeExterna;
  final int? categoriaIdExterna;
  final String? aviso;

  const ResultadoBuscaCodigoBarras({
    this.produtoLocal,
    this.descricaoExterna,
    this.unidadeExterna,
    this.categoriaIdExterna,
    this.aviso,
  });
}

/// ============================================================================
/// PROVIDER PRINCIPAL — PRODUTOS CONTROLLER (T10 / T11)
/// ============================================================================
/// Provider global reativo para gerenciamento do Catálogo de Produtos do Usuário.
/// Centraliza buscas locais, consultas na API FastAPI (produtos-globais) e bases
/// públicas de EAN/GTIN, validações de duplicidade e operações CRUD no SQLite.
final produtosControllerProvider =
    AsyncNotifierProvider<ProdutosController, List<ProdutoModel>>(
  ProdutosController.new,
);

class ProdutosController extends AsyncNotifier<List<ProdutoModel>> {
  // Configurações de integração com a API FastAPI (Produtos Globais) e APIs públicas (GTIN)
  static const String _apiBaseUrl = ApiConstants.baseUrl;
  static const String _si5Token = String.fromEnvironment('SI5_TOKEN');

  /// Cache em memória para evitar requisições repetidas do mesmo código de barras na sessão
  static final Map<String, ResultadoBuscaCodigoBarras> _cacheGtin = {};

  /// Cabeçalhos HTTP obrigatórios para consulta nas bases abertas Open *Facts
  static const Map<String, String> _headersOpenFacts = {
    'User-Agent': 'AgilistaMobileApp/1.0 (contato@agilista.app)',
    'Accept': 'application/json',
  };

  /// Armazena mensagens de alerta específicas da última consulta externa (ex.: limite de taxa)
  String? _avisoUltimaBusca;

  @override
  Future<List<ProdutoModel>> build() async {
    // Carrega automaticamente a lista completa de produtos do SQLite local ao iniciar
    final repository = ref.read(produtosRepositoryProvider);
    final produtosLocais = await repository.listarTodos();

    // Dispara sincronização em segundo plano caso exista usuário logado na sessão
    _sincronizarProdutosEmSegundoPlano();

    return produtosLocais;
  }

  /// Dispara a sincronização de produtos com a Agilista-api em segundo plano (não-bloqueante).
  void _sincronizarProdutosEmSegundoPlano() {
    final usuarioLogado = ref.read(authControllerProvider).value;
    final usuarioId = usuarioLogado?.idUsuario;
    if (usuarioId == null) return;

    unawaited(() async {
      final syncService = ref.read(sincronizacaoProdutosServiceProvider);
      final houveAlteracao = await syncService.sincronizarProdutos(usuarioId);
      if (houveAlteracao) {
        final repository = ref.read(produtosRepositoryProvider);
        final atualizados = await repository.listarTodos();
        state = AsyncValue.data(atualizados);
      }
    }());
  }

  /// Recarrega a listagem completa de produtos ordenada alfabeticamente.
  Future<void> carregarProdutos({bool sincronizar = true}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(produtosRepositoryProvider);
      return await repository.listarTodos();
    });

    if (sincronizar) {
      _sincronizarProdutosEmSegundoPlano();
    }
  }

  /// Filtra os produtos na tabela de consulta (T11) por código de barras ou descrição.
  Future<void> pesquisarProdutos(String termo) async {
    final texto = termo.trim();
    if (texto.isEmpty) {
      await carregarProdutos(sincronizar: false);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(produtosRepositoryProvider);
      final porEan = await repository.buscarPorCodigoBarras(texto);
      if (porEan != null) return [porEan];
      return await repository.buscarPorNome(texto);
    });
  }

  /// Localiza um produto exato pelo seu código de barras no SQLite local.
  Future<ProdutoModel?> buscarPorCodigoBarras(String codigoBarras) async {
    final limpo = limparCodigoBarras(codigoBarras);
    if (limpo.isEmpty) return null;

    final repository = ref.read(produtosRepositoryProvider);
    return await repository.buscarPorCodigoBarras(limpo);
  }

  /// Localiza um produto pelo código de barras exato ou aproximação no nome (usado na T09/T14).
  Future<ProdutoModel?> buscarPorTermoOuEan(String termo) async {
    final texto = termo.trim();
    if (texto.isEmpty) return null;

    final repository = ref.read(produtosRepositoryProvider);

    // 1. Tenta localizar pelo código de barras exato
    final porCodigo = await repository.buscarPorCodigoBarras(texto);
    if (porCodigo != null) return porCodigo;

    // 2. Tenta localizar por aproximação no nome do produto
    final porNome = await repository.buscarPorNome(texto);
    return porNome.isNotEmpty ? porNome.first : null;
  }

  /// Sanitiza o código de barras mantendo apenas dígitos numéricos.
  String limparCodigoBarras(String codigoBruto) {
    return codigoBruto.replaceAll(RegExp(r'[^\d]'), '').trim();
  }

  /// Fluxo completo de consulta de Código de Barras (T10 / T09 / T14):
  /// 1º Pesquisa no banco SQLite local (se existir, retorna o registro local).
  /// 2º Se não existir localmente, consulta a API FastAPI (`/api/v1/produtos-globais/codigo-barras/{codigo}`)
  ///    e, como fallback, as bases públicas (SI5 -> Open *Facts).
  Future<ResultadoBuscaCodigoBarras> consultarCodigoBarrasCompleto(String codigoBruto) async {
    final codigoLimpo = limparCodigoBarras(codigoBruto);
    if (codigoLimpo.isEmpty) {
      return const ResultadoBuscaCodigoBarras();
    }

    // 1. Pesquisa no banco de dados local
    final local = await buscarPorCodigoBarras(codigoLimpo);
    if (local != null) {
      return ResultadoBuscaCodigoBarras(produtoLocal: local);
    }

    // 2. Verifica cache em memória da sessão
    final emCache = _cacheGtin[codigoLimpo];
    if (emCache != null) return emCache;

    _avisoUltimaBusca = null;

    // 3. Consulta externa na API FastAPI (Catálogo Global)
    final resultadoApi = await _buscarNoBackend(codigoLimpo);
    if (resultadoApi != null) {
      _cacheGtin[codigoLimpo] = resultadoApi;
      return resultadoApi;
    }

    // 4. Fallback nas bases públicas externas de GTIN (SI5 -> Open *Facts)
    final descricao = await _buscarDescricaoExterna(codigoLimpo);
    if (descricao != null && descricao.isNotEmpty) {
      final resultadoExterno = ResultadoBuscaCodigoBarras(
        descricaoExterna: descricao.toUpperCase(),
      );
      _cacheGtin[codigoLimpo] = resultadoExterno;
      return resultadoExterno;
    }

    return ResultadoBuscaCodigoBarras(
      aviso: _avisoUltimaBusca ?? 'Código não encontrado nas bases públicas. Digite a descrição.',
    );
  }

  /// T10 — Salva um novo produto ou atualiza um existente no catálogo local e sincroniza.
  /// Preserva todas as travas de negócio:
  /// 1. Descrição e categoria obrigatórias.
  /// 2. Trava de duplicidade de código de barras.
  /// 3. Trava de duplicidade de descrição (case-insensitive).
  /// 4. Preservação do `servidorId` existente na edição.
  Future<void> salvarProduto({
    int? idProduto,
    required int categoriaId,
    String? codigoBarras,
    required String nomeProduto,
    required String unidadeMedida,
    required bool flagRecorrente,
  }) async {
    final desc = nomeProduto.trim();
    final codLimpo = limparCodigoBarras(codigoBarras ?? '');

    if (desc.isEmpty) {
      throw Exception('Por favor, informe a descrição do item!');
    }

    final repository = ref.read(produtosRepositoryProvider);
    final todosProdutos = await repository.listarTodos();

    // Trava 1: Verifica duplicidade de Código de Barras
    if (codLimpo.isNotEmpty) {
      final duplicadoEan = todosProdutos.any(
        (p) => p.codigoBarras == codLimpo && p.idProduto != idProduto,
      );
      if (duplicadoEan) {
        throw Exception('Este código de barras já está cadastrado para outro produto!');
      }
    }

    // Trava 2: Verifica duplicidade de Descrição
    final duplicadoNome = todosProdutos.any(
      (p) => p.nomeProduto.trim().toLowerCase() == desc.toLowerCase() && p.idProduto != idProduto,
    );
    if (duplicadoNome) {
      throw Exception('Já existe um produto cadastrado com esta mesma descrição!');
    }

    // Preserva o `servidorId` existente caso seja edição de um produto já sincronizado
    int? servidorIdExistente;
    if (idProduto != null) {
      final produtoAtual = todosProdutos.where((p) => p.idProduto == idProduto).firstOrNull;
      servidorIdExistente = produtoAtual?.servidorId;
    }

    final model = ProdutoModel(
      idProduto: idProduto,
      servidorId: servidorIdExistente,
      categoriaId: categoriaId,
      codigoBarras: codLimpo.isEmpty ? null : codLimpo,
      nomeProduto: desc,
      unidadeMedida: unidadeMedida.trim().isEmpty ? 'Un' : unidadeMedida.trim(),
      flagProdutoRecorrente: flagRecorrente,
      flagSincronizado: 0,
    );

    if (idProduto == null) {
      await repository.cadastrarProduto(model);
    } else {
      await repository.alterarProduto(model);
    }

    await carregarProdutos();
  }

  /// ============================================================================
  /// CADASTRO RÁPIDO INLINE (T09 / T14)
  /// ============================================================================
  /// Salva rapidamente um novo produto no catálogo local SQLite durante a compra
  /// (sem exigir saída da tela de carrinho) e retorna o `ProdutoModel` criado
  /// contendo o `idProduto` recém-gerado para vínculo imediato ao carrinho.
  ///
  /// Regra de Categoria Padrão:
  /// Vincula automaticamente à categoria `'Mercearia / Grãos'` (ou primeira ativa
  /// disponível como fallback) para evitar que itens gerais caiam em `'Açougue / Carnes'`.
  Future<ProdutoModel> cadastrarProdutoRapidoInline({
    required int usuarioId,
    String? codigoBarras,
    required String nomeProduto,
    String unidadeMedida = 'Un',
  }) async {
    final desc = nomeProduto.trim();
    final codLimpo = limparCodigoBarras(codigoBarras ?? '');

    if (desc.isEmpty) {
      throw Exception('Por favor, informe o nome do produto para cadastrar e adicionar ao carrinho!');
    }

    final repository = ref.read(produtosRepositoryProvider);
    final todosProdutos = await repository.listarTodos();

    // 1. Se já existir produto com exatamente esse código de barras, retorna o existente
    if (codLimpo.isNotEmpty) {
      final existenteEan = todosProdutos.where((p) => p.codigoBarras == codLimpo).firstOrNull;
      if (existenteEan != null) {
        return existenteEan;
      }
    }

    // 2. Se já existir produto com exatamente essa descrição (case-insensitive), retorna o existente
    final existenteNome = todosProdutos
        .where((p) => p.nomeProduto.trim().toLowerCase() == desc.toLowerCase())
        .firstOrNull;
    if (existenteNome != null) {
      return existenteNome;
    }

    // 3. Obtém a categoria padrão 'Mercearia / Grãos' do banco para satisfazer a FK `categoria_id`
    final categoriasDisponiveis = await repository.listarCategorias(
      usuarioId: usuarioId,
      filtro: FiltroStatusCategoria.ativas,
    );

    int categoriaPadraoId;
    if (categoriasDisponiveis.isNotEmpty && categoriasDisponiveis.first.idCategoria != null) {
      // Prioriza explicitamente 'Mercearia / Grãos' entre as categorias ativas
      final catMercearia = categoriasDisponiveis.where((c) {
        final nome = c.nomeCategoria.toLowerCase();
        return nome.contains('mercearia') || nome.contains('grãos') || nome.contains('graos');
      }).firstOrNull;

      categoriaPadraoId = catMercearia?.idCategoria ?? categoriasDisponiveis.first.idCategoria!;
    } else {
      // Fallback de segurança caso nenhuma categoria ativa exista ainda no banco
      final catCriada = await repository.cadastrarCategoria(
        CategoriaModel(
          usuarioId: usuarioId,
          nomeCategoria: 'Mercearia / Grãos',
          statusCategoria: 'Ativo',
        ),
      );
      categoriaPadraoId = catCriada.idCategoria ?? 1;
    }

    // 4. Monta o modelo e insere no SQLite local com flagSincronizado = 0
    final novoModel = ProdutoModel(
      categoriaId: categoriaPadraoId,
      codigoBarras: codLimpo.isEmpty ? null : codLimpo,
      nomeProduto: desc,
      unidadeMedida: unidadeMedida.trim().isEmpty ? 'Un' : unidadeMedida.trim(),
      flagProdutoRecorrente: false,
      flagSincronizado: 0,
    );

    final produtoSalvo = await repository.cadastrarProduto(novoModel);

    // 5. Atualiza reativamente o catálogo em memória e dispara sync em segundo plano
    await carregarProdutos();

    return produtoSalvo;
  }

  /// T11 — Exclui um produto do catálogo e sincroniza a exclusão com o servidor.
  /// Delega ao repositório a validação que impede excluir produtos com histórico em compras.
  Future<void> excluirProduto(int idProduto) async {
    final repository = ref.read(produtosRepositoryProvider);
    await repository.excluirProduto(idProduto);
    await carregarProdutos();
  }

  // ===========================================================================
  // MÉTODOS PRIVADOS — CONSULTA NA API FASTAPI E BASES EXTERNAS DE GTIN / EAN
  // ===========================================================================

  /// Monta a descrição unificando Nome, Marca e Quantidade sem duplicar termos.
  String _montarDescricao(String nome, {String marca = '', String qtd = ''}) {
    final partes = <String>[nome.trim()];
    if (marca.trim().isNotEmpty && !nome.toLowerCase().contains(marca.trim().toLowerCase())) {
      partes.add(marca.trim());
    }
    if (qtd.trim().isNotEmpty && !nome.toLowerCase().contains(qtd.trim().toLowerCase())) {
      partes.add(qtd.trim());
    }
    return partes.join(' ');
  }

  /// Consulta externa 1: Backend próprio FastAPI (`GET /api/v1/produtos-globais/codigo-barras/{codigo}`).
  /// Obtém automaticamente o token JWT salvo no login/cadastro e renova via `/refresh` se expirado.
  Future<ResultadoBuscaCodigoBarras?> _buscarNoBackend(String codigo) async {
    try {
      final authRepo = ref.read(authRepositoryProvider);
      String? token = await authRepo.obterTokenAcesso();

      if (token == null || token.isEmpty) {
        debugPrint('[ProdutosController._buscarNoBackend] Nenhum token JWT armazenado na sessão.');
        return null;
      }

      final uri = Uri.parse('$_apiBaseUrl/api/v1/produtos-globais/codigo-barras/$codigo');
      http.Response response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(ApiConstants.timeoutPadrao);

      // Se o access_token expirou (401), tenta renovar automaticamente usando o refresh_token
      if (response.statusCode == 401) {
        final novoToken = await authRepo.renovarTokenAcesso();
        if (novoToken != null && novoToken.isNotEmpty) {
          response = await http.get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $novoToken',
            },
          ).timeout(ApiConstants.timeoutPadrao);
        }
      }

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final nomeOficial = (data['nome_oficial'] ?? '').toString().trim();
      if (nomeOficial.isEmpty) return null;

      final unidadePadrao = (data['unidade_medida_padrao'] ?? 'Un').toString().trim();
      final categoriaId = (data['categoria_id'] as num?)?.toInt();

      return ResultadoBuscaCodigoBarras(
        descricaoExterna: nomeOficial.toUpperCase(),
        unidadeExterna: unidadePadrao.isNotEmpty ? unidadePadrao : 'Un',
        categoriaIdExterna: categoriaId,
      );
    } catch (e) {
      debugPrint('[ProdutosController._buscarNoBackend] erro: $e');
      return null;
    }
  }

  /// Consulta externa 2: SI5 Global (API Brasileira).
  Future<String?> _buscarNoSi5(String codigo) async {
    if (_si5Token.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse('https://global.si5.com.br/api/produtos/$codigo'),
        headers: {
          'Authorization': 'Bearer $_si5Token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 429) {
        _avisoUltimaBusca = 'Limite diário de consultas atingido. Digite a descrição.';
        return null;
      }
      if (response.statusCode == 401) {
        _avisoUltimaBusca = 'Token da consulta de produtos inválido. Verifique o SI5_TOKEN.';
        return null;
      }
      if (response.statusCode != 200) return null;

      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final nome = (data['produto'] ?? '').toString().trim();
      if (nome.isEmpty) return null;

      return _montarDescricao(nome, marca: (data['marca'] ?? '').toString());
    } catch (e) {
      debugPrint('[ProdutosController._buscarNoSi5] erro: $e');
      return null;
    }
  }

  /// Consulta externa 3: Requisição individual em uma base do Open *Facts.
  Future<String?> _buscarNoOpenFacts(String urlStr) async {
    try {
      final response = await http
          .get(Uri.parse(urlStr), headers: _headersOpenFacts)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['status'] != 1 || data['product'] == null) return null;

      final p = data['product'] as Map<String, dynamic>;
      final nome = (p['product_name_pt'] ??
              p['product_name'] ??
              p['generic_name_pt'] ??
              p['generic_name'] ??
              '')
          .toString()
          .trim();
      if (nome.isEmpty) return null;

      return _montarDescricao(
        nome,
        marca: (p['brands'] ?? '').toString().split(',').first,
        qtd: (p['quantity'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('[ProdutosController._buscarNoOpenFacts] erro em $urlStr: $e');
      return null;
    }
  }

  /// Dispara consultas paralelas nas bases OpenFoodFacts BR, OpenFoodFacts World e OpenProductsFacts.
  Future<String?> _buscarNoOpenFactsParalelo(String codigo) async {
    final urls = [
      'https://br.openfoodfacts.org/api/v0/product/$codigo.json',
      'https://world.openfoodfacts.org/api/v2/product/$codigo?lc=pt&fields=product_name,product_name_pt,generic_name,generic_name_pt,brands,quantity',
      'https://world.openproductsfacts.org/api/v0/product/$codigo.json',
    ];

    final futuros = urls.map(_buscarNoOpenFacts).toList();
    for (final f in futuros) {
      final desc = await f;
      if (desc != null) return desc;
    }
    return null;
  }

  /// Orquestra a busca externa nas bases públicas de fallback respeitando a ordem de prioridade.
  Future<String?> _buscarDescricaoExterna(String codigo) async {
    String? descricao = await _buscarNoSi5(codigo);
    descricao ??= await _buscarNoOpenFactsParalelo(codigo);
    return descricao;
  }
}