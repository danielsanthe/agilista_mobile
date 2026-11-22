import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/usuario_model.dart';
import '../repositories/autenticacao_repository.dart';
import '../services/sincronizacao_listas_service.dart';

/// ============================================================================
/// GERENCIAMENTO DE ESTADO E AUTENTICAÇÃO (AUTH CONTROLLER & PROVIDERS)
/// ============================================================================
/// Módulo responsável por gerenciar a sessão ativa do usuário, orquestrar a
/// comunicação com o repositório de autenticação e expor o estado reativo
/// para as telas da aplicação via Riverpod.

/// Provider global que disponibiliza a instância concreta do repositório de autenticação.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl();
});

/// Provider do tipo [AsyncNotifierProvider] que gerencia e expõe o estado global do usuário autenticado.
///
/// Mantém um [UsuarioModel] quando logado ou `null` quando desconectado/não autenticado.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, UsuarioModel?>(() {
  return AuthController();
});

/// Controller reativo assíncrono para operações de Autenticação (Login, Cadastro, Atualização de Perfil e Logout).
class AuthController extends AsyncNotifier<UsuarioModel?> {
  /// Instância do repositório de dados de autenticação
  late final AuthRepository _repository;

  /// Método do ciclo de vida do Riverpod invocado ao inicializar o Provider.
  ///
  /// Restaura automaticamente a sessão salva no dispositivo (se houver tokens válidos)
  /// e dispara a sincronização global em segundo plano sem bloquear a abertura do app.
  @override
  Future<UsuarioModel?> build() async {
    _repository = ref.watch(authRepositoryProvider);
    final usuarioSalvo = await _repository.restaurarSessaoLocal();
    if (usuarioSalvo != null) {
      _dispararSincronizacaoGlobal(usuarioSalvo.idUsuario);
    }
    return usuarioSalvo;
  }

  /// Dispara a sincronização global (Categorias -> Produtos -> Listas -> Itens)
  /// em segundo plano de forma não-bloqueante (sem travar navegação ou UI).
  /// Obs.: antes das demais etapas executa a ETAPA 0 (envio do usuário criado/editado offline e
  /// obtenção do JWT) via `_sincronizarTudo`, com trava contra execuções simultâneas.
  void _dispararSincronizacaoGlobal(int? usuarioId) {
    if (usuarioId == null) return;
    unawaited(_sincronizarTudo(usuarioId));
  }

  /// Trava anti-concorrência: login, cadastro, build() e retomada do app podem
  /// disparar o ciclo ao mesmo tempo (evita POST duplicado de usuário e conflitos 409).
  static Future<void>? _sincronizacaoEmAndamento;

  Future<void> _sincronizarTudo(int usuarioId) {
    return _sincronizacaoEmAndamento ??=
        _executarSincronizacao(usuarioId).whenComplete(() => _sincronizacaoEmAndamento = null);
  }

  Future<void> _executarSincronizacao(int usuarioId) async {
    // ETAPA 0: usuário (cadastro/edição feitos offline + obtenção do JWT).
    // Sem isso não existe token e todas as demais sincronizações ficam adiadas.
    try {
      final atualizado = await _repository.sincronizarUsuarioPendente(usuarioId);
      if (atualizado != null && state.hasValue && state.value?.idUsuario == usuarioId) {
        state = AsyncValue.data(atualizado);
      }
    } catch (e) {
      debugPrint('[AuthController] sincronização de usuário adiada: $e');
    }

    // Demais etapas: Categorias -> Produtos -> Listas -> Itens
    await ref.read(sincronizacaoListasServiceProvider).sincronizarListasEItens(usuarioId);
  }

  /// Pode ser chamado ao retomar o app ou quando a conexão voltar.
  Future<void> sincronizarAgora() async {
    final usuario = state.value;
    if (usuario?.idUsuario == null) return;
    await _sincronizarTudo(usuario!.idUsuario!);
  }

  /// Efetua a autenticação do usuário a partir do e-mail e senha informados.
  ///
  /// Atualiza o [state] para [AsyncValue.loading] durante o processamento e,
  /// em caso de sucesso, atribui os dados do [UsuarioModel] autenticado.
  /// Retorna `true` se as credenciais forem válidas, ou `false` em caso de erro.
  Future<bool> login(String email, String senha) async {
    state = const AsyncValue.loading();
    try {
      final usuario = await _repository.login(email, senha);
      if (usuario != null) {
        state = AsyncValue.data(usuario);
        _dispararSincronizacaoGlobal(usuario.idUsuario);
        return true;
      } else {
        state = AsyncValue.error('E-mail ou senha inválidos', StackTrace.current);
        return false;
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Cadastra um novo usuário no banco de dados local/cloud com perfil completo e realiza login automático.
  ///
  /// Instancia o [UsuarioModel] com todos os dados cadastrais (incluindo endereço e contato),
  /// chama a persistência no repositório e atribui o usuário criado ao [state].
  Future<bool> cadastrar({
    required String nome,
    required String email,
    required String senha,
    String? cpf,
    String? telefone,
    String? cep,
    String? logradouro,
    String? numero,
    String? bairro,
    String? cidade,
    String? uf,
  }) async {
    state = const AsyncValue.loading();
    try {
      final novoUsuario = UsuarioModel(
        nomeUsuario: nome,
        email: email,
        senhaHash: senha,
        cpf: cpf,
        telefone: telefone,
        cep: cep,
        logradouro: logradouro,
        numero: numero,
        bairro: bairro,
        cidade: cidade,
        uf: uf,
        dataCadastro: DateTime.now(),
        flagSincronizado: false,
      );

      final usuarioCriado = await _repository.cadastrarUsuario(novoUsuario);
      state = AsyncValue.data(usuarioCriado);
      _dispararSincronizacaoGlobal(usuarioCriado.idUsuario);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e.toString().replaceAll('Exception: ', ''), st);
      return false;
    }
  }

  /// Atualiza as informações de perfil do usuário logado no estado global e no banco de dados.
  Future<bool> atualizarPerfil({
    String? novoNome,
    String? novoEmail,
    String? novaSenha,
    String? novoCpf,
    String? novoTelefone,
    String? novoCep,
    String? novoLogradouro,
    String? novoNumero,
    String? novoBairro,
    String? novaCidade,
    String? novoUf,
  }) async {
    final usuarioAtual = state.value;
    if (usuarioAtual == null) return false;

    state = const AsyncValue.loading();
    try {
      final usuarioAtualizado = usuarioAtual.atualizarPerfil(
        novoNome: novoNome,
        novoEmail: novoEmail,
        novaSenhaHash: novaSenha,
        novoCpf: novoCpf,
        novoTelefone: novoTelefone,
        novoCep: novoCep,
        novoLogradouro: novoLogradouro,
        novoNumero: novoNumero,
        novoBairro: novoBairro,
        novaCidade: novaCidade,
        novoUf: novoUf,
        novaFlagSincronizado: false, // Marca como pendente de sincronização cloud
      );

      final sucesso = await _repository.atualizarUsuario(
        usuarioAtualizado,
        novaSenha: novaSenha,
      );
      if (sucesso) {
        state = AsyncValue.data(usuarioAtualizado);
        _dispararSincronizacaoGlobal(usuarioAtualizado.idUsuario);
        return true;
      } else {
        state = AsyncValue.data(usuarioAtual);
        return false;
      }
    } catch (e, st) {
      state = AsyncValue.error(e.toString().replaceAll('Exception: ', ''), st);
      return false;
    }
  }

  /// Solicita à API o código temporário de 6 dígitos para recuperação de senha.
  Future<String?> solicitarRecuperacaoSenha(String email) async {
    return await _repository.solicitarRecuperacaoSenha(email);
  }

  /// Valida o código de 6 dígitos na API e redefine a senha do usuário no servidor e no SQLite local.
  Future<bool> redefinirSenha({
    required String email,
    required String codigo,
    required String novaSenha,
  }) async {
    return await _repository.redefinirSenha(
      email: email,
      codigo: codigo,
      novaSenha: novaSenha,
    );
  }

  /// Encerra a sessão ativa do usuário no aplicativo.
  ///
  /// Limpa os tokens JWT armazenados e reseta o [state] para [AsyncValue.data(null)].
  Future<void> logout() async {
    await _repository.limparTokens();
    state = const AsyncValue.data(null);
  }
}