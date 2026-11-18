import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/localizacao_service.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../controllers/autenticacao_controller.dart';

/// ============================================================================
/// TELA DE PERFIL E EDIÇÃO DE DADOS DO USUÁRIO (T02A - OFFLINE-FIRST)
/// ============================================================================
/// Tela responsável por exibir e permitir a edição das informações cadastrais,
/// dados de contato e endereço do usuário logado.
class PerfilUsuarioScreen extends ConsumerStatefulWidget {
  const PerfilUsuarioScreen({super.key});

  @override
  ConsumerState<PerfilUsuarioScreen> createState() =>
      _PerfilUsuarioScreenState();
}

class _PerfilUsuarioScreenState extends ConsumerState<PerfilUsuarioScreen> {
  // Chave global responsável por orquestrar a validação do formulário
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto para Acesso e Contato
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _senhaController = TextEditingController();

  // Controladores de texto para Localização
  final _cepController = TextEditingController();
  final _logradouroController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _ufController = TextEditingController();

  // Estados locais da tela
  bool _senhaOculta = true;
  bool _buscandoCep = false;
  bool _dadosCarregados = false;

  @override
  void initState() {
    super.initState();
    // Preenche os campos com os dados do usuário autenticado após a montagem inicial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarDadosUsuario();
    });
  }

  /// Carrega os dados do estado global do AuthController nos controladores de texto
  void _carregarDadosUsuario() {
    final usuario = ref.read(authControllerProvider).value;
    if (usuario != null && !_dadosCarregados) {
      _nomeController.text = usuario.nomeUsuario;
      _emailController.text = usuario.email;
      _cpfController.text = usuario.cpf ?? '';
      _telefoneController.text = usuario.telefone ?? '';
      _cepController.text = usuario.cep ?? '';
      _logradouroController.text = usuario.logradouro ?? '';
      _numeroController.text = usuario.numero ?? '';
      _bairroController.text = usuario.bairro ?? '';
      _cidadeController.text = usuario.cidade ?? '';
      _ufController.text = usuario.uf ?? '';
      setState(() {
        _dadosCarregados = true;
      });
    }
  }

  @override
  void dispose() {
    // Descarte de memória dos controladores
    _nomeController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _senhaController.dispose();
    _cepController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    super.dispose();
  }

  /// Consulta de CEP via LocationService
  Future<void> _consultarCep(String cep) async {
    final cepLimpo = cep.replaceAll(RegExp(r'\D'), '');

    if (cepLimpo.length != 8) return;

    setState(() => _buscandoCep = true);

    try {
      final endereco = await ref
          .read(locationServiceProvider)
          .buscarEnderecoPorCep(cepLimpo);

      if (endereco != null && mounted) {
        setState(() {
          _logradouroController.text = endereco.logradouro ?? '';
          _bairroController.text = endereco.bairro ?? '';
          _cidadeController.text = endereco.cidade ?? '';
          _ufController.text = endereco.uf ?? '';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _buscandoCep = false);
      }
    }
  }

  /// Processa a atualização do perfil do usuário logado
  Future<void> _salvarAlteracoes() async {
    if (!_formKey.currentState!.validate()) return;

    final sucesso = await ref
        .read(authControllerProvider.notifier)
        .atualizarPerfil(
          novoNome: _nomeController.text.trim(),
          novoEmail: _emailController.text.trim(),
          novaSenha: _senhaController.text.isNotEmpty ? _senhaController.text : null,
          novoCpf: _cpfController.text.trim(),
          novoTelefone: _telefoneController.text.trim(),
          novoCep: _cepController.text.trim(),
          novoLogradouro: _logradouroController.text.trim(),
          novoNumero: _numeroController.text.trim(),
          novoBairro: _bairroController.text.trim(),
          novaCidade: _cidadeController.text.trim(),
          novoUf: _ufController.text.trim().toUpperCase(),
        );

    if (!mounted) return;

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil atualizado com sucesso!'),
          backgroundColor: AppTheme.statusSuccess,
        ),
      );
    } else {
      final state = ref.read(authControllerProvider);
      final erroMsg = state.hasError
          ? state.error.toString()
          : 'Falha ao atualizar perfil. Tente novamente.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(erroMsg),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
    }
  }

  /// Encerra a sessão ativa do usuário e desloga do app
  void _efetuarLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da Conta'),
        content: const Text('Deseja realmente encerrar sua sessão no ÁgiLista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authControllerProvider.notifier).logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text(
              'SAIR',
              style: TextStyle(color: AppTheme.statusDanger),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,

      // =======================================================================
      // APPBAR PADRONIZADA COM BOTÃO DE LOGOUT
      // =======================================================================
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Perfil do Usuário',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sair da conta',
            onPressed: _efetuarLogout,
          ),
        ],
      ),

      // =======================================================================
      // CORPO DO FORMULÁRIO DE EDICAO DE PERFIL
      // =======================================================================
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Meus Dados Cadastrais',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Mantenha seu endereço atualizado para receber alertas de preços regionais.',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 20),

                // -------------------------------------------------------------
                // SEÇÃO 1: DADOS PESSOAIS
                // -------------------------------------------------------------
                const Text(
                  'Dados Pessoais & Acesso',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const Divider(),
                const SizedBox(height: 10),

                // Nome Completo
                TextFormField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome Completo',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Informe seu nome completo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // E-mail
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
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

                // CPF e Telefone
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cpfController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'CPF',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _telefoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Alterar Senha (Opcional)
                TextFormField(
                  controller: _senhaController,
                  obscureText: _senhaOculta,
                  decoration: InputDecoration(
                    labelText: 'Nova Senha (Opcional)',
                    hintText: 'Deixe em branco para manter a atual',
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
                    if (valor != null && valor.isNotEmpty && valor.length < 6) {
                      return 'A nova senha deve ter no mínimo 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // -------------------------------------------------------------
                // SEÇÃO 2: ENDEREÇO E LOCALIZAÇÃO (USADO NO COMPARADOR REGIONAL)
                // -------------------------------------------------------------
                const Text(
                  'Endereço / Região',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const Divider(),
                const SizedBox(height: 10),

                // CEP
                TextFormField(
                  controller: _cepController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'CEP',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    suffixIcon: _buscandoCep
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () => _consultarCep(_cepController.text),
                          ),
                  ),
                  onChanged: (valor) {
                    final cepLimpo = valor.replaceAll(RegExp(r'\D'), '');
                    if (cepLimpo.length == 8) {
                      _consultarCep(cepLimpo);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Logradouro e Número
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _logradouroController,
                        decoration: const InputDecoration(
                          labelText: 'Logradouro / Rua',
                          prefixIcon: Icon(Icons.home_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _numeroController,
                        decoration: const InputDecoration(
                          labelText: 'Nº',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Bairro
                TextFormField(
                  controller: _bairroController,
                  decoration: const InputDecoration(
                    labelText: 'Bairro',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Informe o bairro';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Cidade e UF
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cidadeController,
                        decoration: const InputDecoration(
                          labelText: 'Cidade',
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                        validator: (valor) {
                          if (valor == null || valor.trim().isEmpty) {
                            return 'Informe a cidade';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _ufController,
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'UF',
                          counterText: '',
                        ),
                        validator: (valor) {
                          if (valor == null || valor.trim().isEmpty) {
                            return 'UF';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Botão de Salvar Alterações
                ElevatedButton(
                  onPressed: isLoading ? null : _salvarAlteracoes,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'SALVAR ALTERAÇÕES',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
                const SizedBox(height: 12),

                // Botão de Sair da Conta (Logout)
                OutlinedButton(
                  onPressed: _efetuarLogout,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.statusDanger),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'SAIR DA CONTA',
                    style: TextStyle(
                      color: AppTheme.statusDanger,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}