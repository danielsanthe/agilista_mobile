import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/categoria_model.dart';
import '../repositories/listas_repository.dart';
import '../repositories/produtos_repository.dart';
import '../services/sincronizacao_categorias_service.dart';

/// ============================================================================
/// NOTIFIER DE FILTRO DE STATUS — CATEGORIAS (T12)
/// ============================================================================
/// Gerencia o estado reativo do filtro segmentado selecionado na consulta:
/// - `FiltroStatusCategoria.todas`
/// - `FiltroStatusCategoria.ativas`
/// - `FiltroStatusCategoria.inativas`
class FiltroStatusCategoriaNotifier extends Notifier<FiltroStatusCategoria> {
  @override
  FiltroStatusCategoria build() {
    // Inicia exibindo todas as categorias (padrão e personalizadas)
    return FiltroStatusCategoria.todas;
  }

  /// Atualiza o filtro selecionado pelo usuário na barra segmentada.
  void alterarFiltro(FiltroStatusCategoria novoFiltro) {
    state = novoFiltro;
  }
}

/// Provider global do filtro de status ativo na tela de categorias.
final filtroStatusCategoriaProvider =
    NotifierProvider<FiltroStatusCategoriaNotifier, FiltroStatusCategoria>(
  FiltroStatusCategoriaNotifier.new,
);

/// ============================================================================
/// PROVIDER PRINCIPAL — CATEGORIAS CONTROLLER (T12 / T22)
/// ============================================================================
/// Provider global reativo para gerenciamento de estado das Categorias.
/// Utiliza `AsyncNotifierProvider` para controlar estados de carregamento,
/// sucesso e erro seguindo o mesmo padrão arquitetural do restante do app.
final categoriasControllerProvider =
    AsyncNotifierProvider<CategoriasController, List<CategoriaModel>>(
  CategoriasController.new,
);

class CategoriasController extends AsyncNotifier<List<CategoriaModel>> {
  @override
  Future<List<CategoriaModel>> build() async {
    // Inicializa com lista vazia até que `carregarCategorias(usuarioId)` seja chamado
    return [];
  }

  /// Dispara a sincronização com a Agilista-api em segundo plano (não-bloqueante).
  /// Caso novos dados sejam recebidos ou enviados, atualiza a lista na tela silenciosamente.
  void _sincronizarEmSegundoPlano(int usuarioId) {
    unawaited(() async {
      final syncService = ref.read(sincronizacaoCategoriasServiceProvider);
      final houveAlteracao = await syncService.sincronizarCategorias(usuarioId);
      if (houveAlteracao) {
        final repository = ref.read(produtosRepositoryProvider);
        final filtro = ref.read(filtroStatusCategoriaProvider);
        final atualizadas = await repository.listarCategorias(
          usuarioId: usuarioId,
          filtro: filtro,
        );
        state = AsyncValue.data(atualizadas);
      }
    }());
  }

  /// Carrega as categorias disponíveis (Padrão do Sistema + Personalizadas do Usuário)
  /// aplicando o filtro de status atualmente selecionado em `filtroStatusCategoriaProvider`.
  Future<void> carregarCategorias(int usuarioId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(produtosRepositoryProvider);
      final filtro = ref.read(filtroStatusCategoriaProvider);
      return await repository.listarCategorias(
        usuarioId: usuarioId,
        filtro: filtro,
      );
    });

    // Sincroniza pendências e atualizações com a API sem travar a interface
    _sincronizarEmSegundoPlano(usuarioId);
  }

  /// Retorna apenas as categorias ATIVAS para alimentar o Dropdown de cadastro de produtos (T10).
  Future<List<CategoriaModel>> listarCategoriasAtivasParaSelecao(int usuarioId) async {
    final repository = ref.read(produtosRepositoryProvider);
    return await repository.listarCategorias(
      usuarioId: usuarioId,
      filtro: FiltroStatusCategoria.ativas,
    );
  }

  /// Altera o filtro de status (Todas / Ativas / Inativas) e atualiza a listagem reativa.
  Future<void> filtrarPorStatus(int usuarioId, FiltroStatusCategoria novoFiltro) async {
    ref.read(filtroStatusCategoriaProvider.notifier).alterarFiltro(novoFiltro);
    await carregarCategorias(usuarioId);
  }

  /// T22 — Cadastra uma nova categoria personalizada ou atualiza uma existente.
  /// Preserva todas as regras de negócio:
  /// 1. Descrição obrigatória.
  /// 2. Validação de duplicidade de nome (case-insensitive) entre categorias visíveis.
  /// 3. Preservação do `servidorId` existente na edição e marcação de `flagSincronizado = 0`.
  Future<void> salvarCategoria({
    int? idCategoria,
    required int usuarioId,
    required String nome,
    required bool ativo,
  }) async {
    final nomeLimpo = nome.trim();

    // Regra 1: Validação de preenchimento obrigatório
    if (nomeLimpo.isEmpty) {
      throw Exception('Informe a descrição da categoria!');
    }

    final repository = ref.read(produtosRepositoryProvider);

    // Regra 2: Consulta todas as categorias visíveis ao usuário para validar duplicidade
    final existentes = await repository.listarCategorias(
      usuarioId: usuarioId,
      filtro: FiltroStatusCategoria.todas,
    );

    final jaExiste = existentes.any((cat) {
      final mesmoNome = cat.nomeCategoria.trim().toLowerCase() == nomeLimpo.toLowerCase();
      if (idCategoria != null) {
        return mesmoNome && cat.idCategoria != idCategoria;
      }
      return mesmoNome;
    });

    if (jaExiste) {
      throw Exception('Já existe uma categoria cadastrada com esse nome!');
    }

    // Preserva o servidorId caso seja edição de uma categoria já sincronizada
    int? servidorIdExistente;
    if (idCategoria != null) {
      final categoriaAtual = existentes.where((c) => c.idCategoria == idCategoria).firstOrNull;
      if (categoriaAtual != null && categoriaAtual.ehCategoriaPadrao) {
        throw Exception('As categorias padrões do sistema são somente leitura.');
      }
      servidorIdExistente = categoriaAtual?.servidorId;
    }

    // Regra 3: Monta o modelo vinculado ao usuário logado com flag de pendência de sync
    final model = CategoriaModel(
      idCategoria: idCategoria,
      servidorId: servidorIdExistente,
      usuarioId: usuarioId,
      nomeCategoria: nomeLimpo,
      ativo: ativo ? 1 : 0,
      statusCategoria: ativo ? 'Ativo' : 'Inativo',
      flagSincronizado: 0,
    );

    await repository.cadastrarCategoria(model);
    await carregarCategorias(usuarioId);
  }

  /// T12 — Alterna o status (Ativa <-> Inativa) de uma categoria personalizada selecionada na tabela.
  /// Bloqueia qualquer tentativa de alteração em categorias padrão do sistema (`usuarioId == null`).
  Future<void> alternarStatus({
    required CategoriaModel categoria,
    required int usuarioId,
  }) async {
    // Trava de segurança: categorias padrão são somente leitura
    if (categoria.ehCategoriaPadrao) {
      throw Exception('As categorias padrões do sistema não podem ter seu status alterado.');
    }

    final repository = ref.read(produtosRepositoryProvider);
    final isAtivo = categoria.ativo == 1;

    final atualizada = categoria.copyWith(
      ativo: isAtivo ? 0 : 1,
      statusCategoria: isAtivo ? 'Inativo' : 'Ativo',
      flagSincronizado: 0,
    );

    await repository.cadastrarCategoria(atualizada);
    await carregarCategorias(usuarioId);
  }

  /// T12 — Exclui uma categoria personalizada (Soft Delete + fila de sincronização).
  /// Preserva as travas:
  /// 1. Impede exclusão de categorias padrão do sistema.
  /// 2. Impede exclusão caso existam produtos vinculados à categoria.
  Future<void> excluirCategoria({
    required CategoriaModel categoria,
    required int usuarioId,
  }) async {
    if (categoria.ehCategoriaPadrao) {
      throw Exception('Categorias padrões do sistema não podem ser excluídas!');
    }

    if (categoria.idCategoria == null) return;

    final listasRepo = ref.read(listsRepositoryProvider);

    // Verifica integridade referencial antes de excluir
    final podeExcluir = await listasRepo.verificarCategoriaPodeSerExcluida(categoria.idCategoria!);

    if (!podeExcluir) {
      throw Exception(
        'A categoria "${categoria.nomeCategoria}" está vinculada a produtos e não pode ser excluída!',
      );
    }

    await listasRepo.excluirCategoria(categoria.idCategoria!);
    await carregarCategorias(usuarioId);
  }
}