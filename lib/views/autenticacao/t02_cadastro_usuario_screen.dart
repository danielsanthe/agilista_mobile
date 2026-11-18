import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/localizacao_service.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../controllers/autenticacao_controller.dart';

/// ============================================================================
/// TELA DE CADASTRO COMPLETO DE USUÁRIO (VERSÃO 5 - OFFLINE-FIRST)
/// ============================================================================
/// Tela responsável por coletar dados cadastrais, credenciais de acesso e
/// localização do usuário durante o primeiro cadastro no aplicativo.
/// Integra-se reativamente com o [AuthController] e [LocationService] utilizando o Riverpod.
class CadastroUsuarioScreen extends ConsumerStatefulWidget {
  const CadastroUsuarioScreen({super.key});

  @override
  ConsumerState<CadastroUsuarioScreen> createState() =>
      _CadastroUsuarioScreenState();
}

class _CadastroUsuarioScreenState extends ConsumerState<CadastroUsuarioScreen> {
  // Chave global responsável por orquestrar a validação do formulário
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto para a Seção de Credenciais e Dados de Acesso
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  // Controladores de texto para os novos campos da Versão 5 (Contato e Localização)
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _cepController = TextEditingController();
  final _logradouroController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _ufController = TextEditingController();

  // Estados locais da tela
  bool _senhaOculta = true;
  bool _buscandoCep = false;

  @override
  void dispose() {
    // Descarte e liberação adequada de todos os recursos da memória ao fechar a tela
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _cepController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    super.dispose();
  }

  /// =========================================================================
  /// CONSULTA DE CEP VIA LOCATION SERVICE (RIVERPOD)
  /// =========================================================================
  Future<void> _consultarCep(String cep) async {
    final cepLimpo = cep.replaceAll(RegExp(r'\D'), '');

    if (cepLimpo.length != 8) return;

    setState(() => _buscandoCep = true);

    try {
      // Injeção do LocationService para obtenção do endereço
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

  /// Processa a submissão do formulário, envia os dados ao repositório local e trata o resultado.
  Future<void> _submeterCadastro() async {
    // Interrompe o fluxo caso algum campo do formulário esteja inválido
    if (!_formKey.currentState!.validate()) return;

    final sucesso = await ref.read(authControllerProvider.notifier).cadastrar(
          nome: _nomeController.text.trim(),
          email: _emailController.text.trim(),
          senha: _senhaController.text,
          cpf: _cpfController.text.trim(),
          telefone: _telefoneController.text.trim(),
          cep: _cepController.text.trim(),
          logradouro: _logradouroController.text.trim(),
          numero: _numeroController.text.trim(),
          bairro: _bairroController.text.trim(),
          cidade: _cidadeController.text.trim(),
          uf: _ufController.text.trim().toUpperCase(),
        );

    if (!mounted) return;

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta criada com sucesso!'),
          backgroundColor: AppTheme.statusSuccess,
        ),
      );
      Navigator.pop(context); // Retorna para a tela de Login
    } else {
      final state = ref.read(authControllerProvider);
      final erroMsg = state.hasError
          ? state.error.toString()
          : 'Falha ao criar conta. Tente novamente.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(erroMsg),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,

      // =======================================================================
      // BARRA SUPERIOR (APPBAR PADRONIZADA)
      // =======================================================================
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Cadastro de Usuário',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // =======================================================================
      // CORPO DO FORMULÁRIO DE CADASTRO
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
                  'Crie sua conta no ÁgiLista',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Preencha seus dados cadastrais para se registrar.',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 20),

                // -------------------------------------------------------------
                // SEÇÃO 1: DADOS PESSOAIS E ACESSO
                // -------------------------------------------------------------
                const Text(
                  'Dados de Acesso',
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
                    hintText: 'Ex.: Daniel Santos',
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

                // CPF e Telefone (Lado a lado)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cpfController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'CPF',
                          hintText: '000.000.000-00',
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
                          hintText: '(00) 00000-0000',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Senha de Acesso
                TextFormField(
                  controller: _senhaController,
                  obscureText: _senhaOculta,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    hintText: 'Mínimo de 6 caracteres',
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
                    if (valor == null || valor.length < 6) {
                      return 'A senha deve ter no mínimo 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirmar Senha
                TextFormField(
                  controller: _confirmarSenhaController,
                  obscureText: _senhaOculta,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar Senha',
                    hintText: 'Repita sua senha',
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                  validator: (valor) {
                    if (valor != _senhaController.text) {
                      return 'As senhas não coincidem';
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

                // CEP com autocompletar ao atingir 8 dígitos ou clicar na lupa
                TextFormField(
                  controller: _cepController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'CEP',
                    hintText: '64000-000',
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
                          hintText: 'Ex.: Av. Brasil',
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
                          hintText: '100',
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
                    hintText: 'Ex.: Centro',
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
                          hintText: 'Ex.: Teresina',
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
                          hintText: 'PI',
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

                // Botão de Finalizar Cadastro
                ElevatedButton(
                  onPressed: isLoading ? null : _submeterCadastro,
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
                          'CADASTRAR CONTA',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
                const SizedBox(height: 12),

                // Botão Secundário para Cancelar ou Retornar ao Login
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'JÁ TENHO UMA CONTA',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
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