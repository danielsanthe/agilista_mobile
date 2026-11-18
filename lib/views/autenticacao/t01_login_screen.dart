import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../controllers/autenticacao_controller.dart';
import 't02_cadastro_usuario_screen.dart';
import '../listas/t03_home_screen.dart';

/// ============================================================================
/// TELA DE AUTENTICAÇÃO E LOGIN DO USUÁRIO (T01 - OFFLINE-FIRST)
/// ============================================================================
/// Tela inicial de acesso ao aplicativo ÁgiLista.
///
/// Responsabilidades Principais:
/// - Validar credenciais de acesso (e-mail e senha) de forma híbrida (API + SQLite).
/// - Redirecionar o usuário autenticado para o Dashboard principal (HomeScreen).
/// - Disponibilizar fluxo de recuperação de senha em 2 etapas ("Esqueci minha senha").
/// - Permitir navegação para o cadastro de novas contas (CadastroUsuarioScreen).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// Chave global para controle e validação dos campos do formulário de login
  final _formKey = GlobalKey<FormState>();

  /// Controlador de texto para o campo de e-mail
  final _emailController = TextEditingController();

  /// Controlador de texto para o campo de senha
  final _senhaController = TextEditingController();

  /// Controla a visibilidade (mascaramento) dos caracteres da senha
  bool _senhaOculta = true;

  @override
  void dispose() {
    // Libera os recursos de memória dos controladores ao destruir a tela
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  /// Valida o formulário e submete as credenciais ao [AuthController]
  Future<void> _submeterLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final sucesso = await ref.read(authControllerProvider.notifier).login(
          _emailController.text,
          _senhaController.text,
        );

    if (!mounted) return;

    if (!sucesso) {
      final state = ref.read(authControllerProvider);
      final erroMsg = state.hasError
          ? state.error.toString()
          : 'E-mail ou senha incorretos.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(erroMsg),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login realizado com sucesso!'),
          backgroundColor: AppTheme.statusSuccess,
        ),
      );

      // Redireciona para o Dashboard (T03) e remove a LoginScreen da pilha de navegação
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  /// Abre o modal inferior (BottomSheet) para recuperação de senha em 2 etapas:
  /// - Etapa 1: Solicita o código temporário de 6 dígitos na API (`/esqueci-senha`).
  /// - Etapa 2: Valida o código e define a nova senha (`/redefinir-senha` + SQLite).
  void _abrirModalEsqueciSenha() {
    final formModalKey = GlobalKey<FormState>();

    // Pré-preenche o e-mail caso o usuário já tenha digitado na tela de login
    final emailRecuperacaoCtrl = TextEditingController(
      text: _emailController.text.trim(),
    );
    final codigoCtrl = TextEditingController();
    final novaSenhaCtrl = TextEditingController();
    final confirmarSenhaCtrl = TextEditingController();

    // Estados internos controlados via StatefulBuilder dentro do modal
    bool codigoEnviado = false;
    bool carregando = false;
    bool ocultarNovaSenha = true;
    String? erroModal;
    String? infoModal;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            /// Etapa 1: Envia solicitação do código de 6 dígitos para o e-mail informado
            Future<void> enviarCodigo() async {
              if (!formModalKey.currentState!.validate()) return;

              setModalState(() {
                carregando = true;
                erroModal = null;
                infoModal = null;
              });

              try {
                final codigoDev = await ref
                    .read(authControllerProvider.notifier)
                    .solicitarRecuperacaoSenha(emailRecuperacaoCtrl.text.trim());

                if (!modalContext.mounted) return;

                setModalState(() {
                  codigoEnviado = true;
                  carregando = false;
                  if (codigoDev != null && codigoDev.isNotEmpty) {
                    // Em ambiente de desenvolvimento/testes, preenche o código automaticamente
                    codigoCtrl.text = codigoDev;
                    infoModal =
                        'Código de verificação gerado ($codigoDev). Defina sua nova senha abaixo.';
                  } else {
                    infoModal =
                        'Enviamos um código de 6 dígitos para o seu e-mail. Válido por 15 minutos.';
                  }
                });
              } catch (e) {
                if (!modalContext.mounted) return;
                setModalState(() {
                  carregando = false;
                  erroModal = e.toString().replaceAll('Exception: ', '');
                });
              }
            }

            /// Etapa 2: Confirma o código e grava a nova senha no servidor e localmente
            Future<void> confirmarRedefinicao() async {
              if (!formModalKey.currentState!.validate()) return;

              setModalState(() {
                carregando = true;
                erroModal = null;
              });

              try {
                final ok = await ref
                    .read(authControllerProvider.notifier)
                    .redefinirSenha(
                      email: emailRecuperacaoCtrl.text.trim(),
                      codigo: codigoCtrl.text.trim(),
                      novaSenha: novaSenhaCtrl.text,
                    );

                if (ok) {
                  // Atualiza o e-mail na tela de login e limpa a senha antiga
                  _emailController.text = emailRecuperacaoCtrl.text.trim();
                  _senhaController.clear();

                  // Verifica montagem do BuildContext do modal antes de fechá-lo
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }

                  // Verifica montagem do State da LoginScreen antes de usar seu context
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Senha redefinida com sucesso! Faça login com a nova senha.',
                      ),
                      backgroundColor: AppTheme.statusSuccess,
                    ),
                  );
                }
              } catch (e) {
                if (!modalContext.mounted) return;
                setModalState(() {
                  carregando = false;
                  erroModal = e.toString().replaceAll('Exception: ', '');
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                // Ajusta automaticamente a margem inferior quando o teclado virtual abre
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formModalKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cabeçalho do modal com título e botão fechar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recuperar Senha',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Instrução dinâmica de acordo com a etapa atual
                      Text(
                        codigoEnviado
                            ? 'Informe o código de 6 dígitos e crie sua nova senha de acesso.'
                            : 'Digite o e-mail cadastrado para receber o código de recuperação.',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 16),

                      // Banner de alerta em caso de erro na validação ou rede
                      if (erroModal != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.statusDanger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            erroModal!,
                            style: const TextStyle(color: AppTheme.statusDanger),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Banner informativo de sucesso após gerar o código
                      if (infoModal != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.statusSuccess.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            infoModal!,
                            style: const TextStyle(color: AppTheme.statusSuccess),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Campo E-mail de Recuperação (bloqueado após envio do código)
                      TextFormField(
                        controller: emailRecuperacaoCtrl,
                        enabled: !codigoEnviado && !carregando,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'E-mail cadastrado',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Informe o e-mail';
                          }
                          if (!v.contains('@') || !v.contains('.')) {
                            return 'Informe um e-mail válido';
                          }
                          return null;
                        },
                      ),

                      // Campos exibidos somente na Etapa 2 (após solicitação do código)
                      if (codigoEnviado) ...[
                        const SizedBox(height: 14),

                        // Campo Código de Verificação (6 dígitos)
                        TextFormField(
                          controller: codigoCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Código de 6 dígitos',
                            prefixIcon: Icon(Icons.pin_outlined),
                            counterText: '',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length != 6) {
                              return 'Informe o código de 6 dígitos';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Campo Nova Senha
                        TextFormField(
                          controller: novaSenhaCtrl,
                          obscureText: ocultarNovaSenha,
                          decoration: InputDecoration(
                            labelText: 'Nova Senha',
                            hintText: 'Mínimo de 6 caracteres',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                ocultarNovaSenha
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () {
                                setModalState(() {
                                  ocultarNovaSenha = !ocultarNovaSenha;
                                });
                              },
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 6) {
                              return 'A senha deve ter no mínimo 6 caracteres';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Campo Confirmar Nova Senha
                        TextFormField(
                          controller: confirmarSenhaCtrl,
                          obscureText: ocultarNovaSenha,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar Nova Senha',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          validator: (v) {
                            if (v != novaSenhaCtrl.text) {
                              return 'As senhas não coincidem';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Botão de ação principal do modal (Enviar Código ou Redefinir Senha)
                      ElevatedButton(
                        onPressed: carregando
                            ? null
                            : (codigoEnviado ? confirmarRedefinicao : enviarCodigo),
                        child: carregando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                codigoEnviado
                                    ? 'REDEFINIR SENHA'
                                    : 'ENVIAR CÓDIGO DE VERIFICAÇÃO',
                              ),
                      ),

                      // Opção para voltar à Etapa 1 caso o usuário queira corrigir o e-mail
                      if (codigoEnviado) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: carregando
                              ? null
                              : () {
                                  setModalState(() {
                                    codigoEnviado = false;
                                    erroModal = null;
                                    infoModal = null;
                                  });
                                },
                          child: const Text('Alterar e-mail ou reenviar código'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logomarca Oficial do ÁgiLista
                  Image.asset(
                    'assets/images/logo.png',
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 28),

                  // Campo E-mail
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      hintText: 'digite@seuemail.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return 'Informe o e-mail';
                      }
                      if (!valor.contains('@') || !valor.contains('.')) {
                        return 'Informe um e-mail válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Campo Senha com alternância de visibilidade
                  TextFormField(
                    controller: _senhaController,
                    obscureText: _senhaOculta,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      hintText: 'Digite sua senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _senhaOculta
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _senhaOculta = !_senhaOculta;
                          });
                        },
                      ),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Informe a senha';
                      }
                      return null;
                    },
                  ),

                  // Link para recuperação de senha ("Esqueci minha senha")
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isLoading ? null : _abrirModalEsqueciSenha,
                      child: const Text(
                        'Esqueci minha senha',
                        style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botão Entrar (Primário Azul)
                  ElevatedButton(
                    onPressed: isLoading ? null : _submeterLogin,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('ENTRAR'),
                  ),
                  const SizedBox(height: 16),

                  // Botão Criar Conta (Secundário Laranja)
                  OutlinedButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CadastroUsuarioScreen(),
                              ),
                            );
                          },
                    child: const Text('CRIAR NOVA CONTA'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}