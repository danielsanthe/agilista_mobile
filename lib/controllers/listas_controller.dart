import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../nucleo/constantes/estados_constants.dart';
import '../services/localizacao_service.dart';
import '../services/sincronizacao_listas_service.dart';
import '../models/item_lista_model.dart';
import '../models/lista_model.dart';
import '../repositories/listas_repository.dart';

/// Provider global reativo para gerenciamento de estado da lista de compras.
/// Utiliza `AsyncNotifierProvider` para manipular estados assíncronos (Carregando, Sucesso, Erro).
final listsControllerProvider =
    AsyncNotifierProvider<ListsController, List<ListaModel>>(
  ListsController.new,
);

class ListsController extends AsyncNotifier<List<ListaModel>> {
  @override
  Future<List<ListaModel>> build() async {
    // Inicializa o estado com uma lista vazia por padrão
    return [];
  }

  /// Dispara a sincronização de listas e itens com a Agilista-api em segundo plano.
  /// Chamado apenas nos marcos de confirmação do usuário:
  /// 1. Salvar lista planejada criada / replicada
  /// 2. Salvar lista planejada editada / excluída
  /// 3. Iniciar compra
  /// 4. Finalizar compra (e pull-to-refresh manual da Home)
  void _sincronizarListasEmSegundoPlano(int usuarioId) {
    unawaited(() async {
      try {
        final syncService = ref.read(sincronizacaoListasServiceProvider);
        final houveAlteracao = await syncService.sincronizarListasEItens(usuarioId);
        if (houveAlteracao) {
          final repository = ref.read(listsRepositoryProvider);
          final atualizadas = await repository.listarPorUsuario(usuarioId);
          state = AsyncValue.data(atualizadas);
        }
      } catch (e, st) {
        debugPrint('[ListsController._sincronizarListasEmSegundoPlano] erro: $e\n$st');
      }
    }());
  }

  /// Carrega as listas cadastradas de um determinado usuário a partir do SQLite/Repositório.
  /// Quando `sincronizar` for `true`, dispara a sincronização bidirecional em segundo plano.
  Future<void> carregarListas(int usuarioId, {bool sincronizar = true}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(listsRepositoryProvider);
      return await repository.listarPorUsuario(usuarioId);
    });

    if (sincronizar) {
      _sincronizarListasEmSegundoPlano(usuarioId);
    }
  }

  /// Atualiza silenciosamente as listas no Riverpod sem colocar a tela em estado de carregamento completo.
  /// Ideal para ser chamado após adicionar, editar ou remover itens do carrinho durante a compra.
  /// Mantém a operação 100% local no SQLite, aguardando o usuário clicar em "Finalizar Compra"
  /// para enviar os itens consolidados ao servidor.
  Future<void> atualizarAposAcaoCarrinho(int usuarioId) async {
    try {
      final repository = ref.read(listsRepositoryProvider);
      final listasAtualizadas = await repository.listarPorUsuario(usuarioId);
      state = AsyncValue.data(listasAtualizadas);
    } catch (e, st) {
      debugPrint('[ListsController.atualizarAposAcaoCarrinho] erro: $e\n$st');
    }
  }

  /// F04 — Cria uma nova lista planejada para o usuário logado e sincroniza com o servidor.
  Future<bool> criarLista({
    required String nome,
    required double orcamento,
    required int usuarioId,
  }) async {
    try {
      final repository = ref.read(listsRepositoryProvider);
      final novaLista = ListaModel(
        usuarioId: usuarioId,
        nomeLista: nome,
        valorOrcamento: orcamento,
        statusLista: 'Planejada',
        dataCriacao: DateTime.now(),
      );
      await repository.criarLista(novaLista);
      await carregarListas(usuarioId, sincronizar: true);
      return true;
    } catch (e, st) {
      debugPrint('[ListsController.criarLista] erro: $e\n$st');
      return false;
    }
  }

  /// F05 — Inicia a compra de uma lista carregando geolocalização, normalizando a UF
  /// e atualizando o status para "Em Andamento" com sincronização imediata.
  Future<bool> iniciarCompra({
    required int listaId,
    required int usuarioId,
    String? nomeEstabelecimentoManual,
    String? estabelecimento,
    String? endereco,
    String? bairro,
    String? cidade,
    String? uf,
  }) async {
    try {
      final repository = ref.read(listsRepositoryProvider);
      final locationService = ref.read(locationServiceProvider);

      // 1. Validar se a lista possui itens para permitir iniciar a compra
      final itens = await repository.listarItensDaLista(listaId);
      if (itens.isEmpty) {
        throw Exception(
          'Não é possível iniciar compras em uma lista sem itens planejados.',
        );
      }

      // 2. Tentar capturar a geolocalização caso o modal não tenha repassado explicitamente os campos
      DadosEndereco? enderecoGps;
      if (endereco == null && cidade == null) {
        try {
          enderecoGps = await locationService.obterEnderecoAtual();
        } catch (_) {
          // Prossegue mesmo se a localização falhar/for negada pelo usuário
        }
      }

      // 3. Determinar o nome do estabelecimento (manual override ou logradouro/default)
      final String estabFinal = (estabelecimento != null && estabelecimento.trim().isNotEmpty)
          ? estabelecimento.trim()
          : (nomeEstabelecimentoManual != null && nomeEstabelecimentoManual.trim().isNotEmpty)
              ? nomeEstabelecimentoManual.trim()
              : (enderecoGps?.logradouro ?? 'Estabelecimento Não Informado');

      // 4. Normalizar UF para sigla oficial de 2 caracteres (ex: "PIAUÍ" -> "PI")
      final String? ufNormalizada = EstadosConstants.normalizarUf(uf ?? enderecoGps?.uf);

      // 5. Gravar os dados geográficos e atualizar status no repositório para "Em Andamento"
      await repository.iniciarCompra(
        listaId: listaId,
        estabelecimento: estabFinal,
        endereco: endereco ?? enderecoGps?.logradouro,
        bairro: bairro ?? enderecoGps?.bairro,
        cidade: cidade ?? enderecoGps?.cidade,
        uf: ufNormalizada,
      );

      // 6. Recarregar as listas na tela e disparar sincronização do início da compra
      await carregarListas(usuarioId, sincronizar: true);
      return true;
    } catch (e, st) {
      debugPrint('[ListsController.iniciarCompra] erro: $e\n$st');
      return false;
    }
  }

  /// F12 — Finaliza uma compra em andamento marcando-a como "Concluída"
  /// e enviando todos os itens comprados e totais consolidados ao servidor.
  Future<bool> finalizarCompra({
    required int listaId,
    required int usuarioId,
  }) async {
    try {
      final repository = ref.read(listsRepositoryProvider);
      final lista = await repository.buscarPorId(listaId);
      if (lista == null) return false;

      final listaConcluida = lista.finalizarCompra();
      await repository.atualizarLista(listaConcluida);
      await carregarListas(usuarioId, sincronizar: true);
      return true;
    } catch (e, st) {
      debugPrint('[ListsController.finalizarCompra] erro: $e\n$st');
      return false;
    }
  }

  /// Adiciona um novo item diretamente na compra em andamento (carrinho)
  /// e atualiza o estado local da Home sem disparar requisições HTTP no meio da compra.
  Future<bool> adicionarItemNoCarrinho({
    required ItemListaModel item,
    required int usuarioId,
  }) async {
    try {
      final repository = ref.read(listsRepositoryProvider);
      await repository.adicionarItem(item);
      await atualizarAposAcaoCarrinho(usuarioId);
      return true;
    } catch (e, st) {
      debugPrint('[ListsController.adicionarItemNoCarrinho] erro: $e\n$st');
      return false;
    }
  }

  /// Atualiza as informações do item no carrinho (quantidade real, preço pago, flag comprado)
  /// e atualiza o estado local da Home sem disparar requisições HTTP no meio da compra.
  Future<bool> atualizarItemNoCarrinho({
    required ItemListaModel item,
    required int usuarioId,
  }) async {
    try {
      final repository = ref.read(listsRepositoryProvider);
      await repository.atualizarItem(item);
      await atualizarAposAcaoCarrinho(usuarioId);
      return true;
    } catch (e, st) {
      debugPrint('[ListsController.atualizarItemNoCarrinho] erro: $e\n$st');
      return false;
    }
  }

  /// Remove um item da lista de compras em andamento
  /// e atualiza o estado local da Home sem disparar requisições HTTP no meio da compra.
  Future<bool> removerItemDoCarrinho({
    required int idItemLista,
    required int usuarioId,
  }) async {
    try {
      final repository = ref.read(listsRepositoryProvider);
      await repository.removerItem(idItemLista);
      await atualizarAposAcaoCarrinho(usuarioId);
      return true;
    } catch (e, st) {
      debugPrint('[ListsController.removerItemDoCarrinho] erro: $e\n$st');
      return false;
    }
  }

  /// F18 — Replica/Duplica uma lista existente (planejada ou concluída),
  /// criando uma nova lista com status "Planejada" e copiando seus itens.
  Future<bool> replicarLista({
    required ListaModel listaOriginal,
    required String novoNome,
    required int usuarioId,
    bool incluirForaDaLista = false,
  }) async {
    try {
      if (listaOriginal.idLista == null) return false;

      final repository = ref.read(listsRepositoryProvider);

      // Réplica transacional no SQLite: lista nova + itens, tudo ou nada
      await repository.replicarLista(
        listaOriginal.idLista!,
        novoNome,
        incluirForaDaLista: incluirForaDaLista,
      );

      // Recarrega o estado das listas no Riverpod e dispara sincronização da nova lista planejada
      await carregarListas(usuarioId, sincronizar: true);
      return true;
    } catch (e, st) {
      debugPrint('[ListsController.replicarLista] erro: $e\n$st');
      return false;
    }
  }

  /// Exclui uma lista por completo pelo seu ID e sincroniza a exclusão.
  Future<void> deletarLista(int idLista, int usuarioId) async {
    final repository = ref.read(listsRepositoryProvider);
    await repository.excluirLista(idLista);
    await carregarListas(usuarioId, sincronizar: true);
  }
}