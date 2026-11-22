import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Imports globais do aplicativo (Constantes, Temas e Formatadores de Moeda)
import '../../nucleo/constantes/status_constants.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../nucleo/utilitarios/formatadores.dart';

// Controllers e Visões de Autenticação
import '../../controllers/autenticacao_controller.dart';
import '../autenticacao/t01_login_screen.dart';
import '../autenticacao/t02a_perfil_usuario_screen.dart';

// Visões de Histórico e Relatórios
import '../historico/t18_historico_screen.dart';

// Visões do Módulo de Compras (Carrinho e Diálogos)
import '../compras/t07_iniciar_compra_dialog.dart';
import '../compras/t08_t13_minha_compra_screen.dart';
import '../compras/t10_t11_cadastro_produtos_screen.dart';
import '../compras/t12_t22_cadastro_categoria_screen.dart';

// Controllers e Repositórios do Módulo de Listas
import '../../controllers/listas_controller.dart';
import '../../models/lista_model.dart';
import 't04_criar_editar_lista_screen.dart';
import 't05_t06_minhas_listas_screen.dart';
import 't23_mapa_supermercados_screen.dart';

/// ============================================================================
/// TELA T03 — PAINEL PRINCIPAL / HOME
/// ============================================================================
/// Exibe o painel principal do aplicativo com o resumo da compra em andamento
/// ou da próxima lista planejada, percentual gasto do orçamento, atalhos
/// rápidos e barra de navegação inferior.
///
/// Arquitetura Offline-First:
/// - Lê instantaneamente as listas persistidas no SQLite local via
///   [ListsController] e dispara a sincronização bidirecional em segundo plano
///   ao abrir a tela, ao puxar para atualizar (`RefreshIndicator`) e ao
///   retornar de operações concluídas.
///
/// Obs.: ao retomar o app (`AppLifecycleState.resumed`) também sincroniza via
/// `AuthController.sincronizarAgora()` e recarrega as listas.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  /// Índice da aba selecionada na barra de navegação inferior (BottomNavigationBar).
  int _abaSelecionada = 0;

  @override
  void initState() {
    super.initState();
    // Obs.: observa o ciclo de vida do app para sincronizar ao voltar ao primeiro plano
    WidgetsBinding.instance.addObserver(this);
    // Dispara a carga inicial das listas do SQLite e sincronização em segundo plano
    Future.microtask(() {
      _carregarDados();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Ao retomar o app (primeiro plano), envia pendências offline (usuário, categorias,
  /// produtos e listas) e recarrega a tela com os dados atualizados do SQLite.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authControllerProvider.notifier).sincronizarAgora().then((_) {
        if (mounted) _carregarDados();
      });
    }
  }

  /// Recarrega as listas do usuário autenticado e sincroniza com a API FastAPI.
  void _carregarDados() {
    final usuario = ref.read(authControllerProvider).value;
    if (usuario != null && usuario.idUsuario != null) {
      ref
          .read(listsControllerProvider.notifier)
          .carregarListas(usuario.idUsuario!);
    }
  }

  /// Exibe o diálogo modal "Sobre o Aplicativo" com informações de versão e suporte.
  void _exibirDialogoSobre() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 28,
              fit: BoxFit.contain,
              color: AppTheme.primaryBlue,
            ),
            const SizedBox(width: 8),
            const Text(
              'Sobre o App',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlue,
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AgiLista Mobile',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppTheme.textDark,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Versão: 2.0.0',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            SizedBox(height: 12),
            Divider(),
            SizedBox(height: 8),
            Text(
              'Contato e Suporte:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppTheme.textDark,
              ),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.phone, size: 16, color: AppTheme.primaryBlue),
                SizedBox(width: 6),
                Text(
                  '+55(86) 99996-7953',
                  style: TextStyle(fontSize: 13, color: AppTheme.textDark),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              '© Todos os direitos reservados ao Grupo AgiLista.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: AppTheme.orangeButtonStyle,
            child: const Text(
              'FECHAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navega para a tela de compras/carrinho (T08/T13) e atualiza a Home ao retornar.
  Future<void> _abrirTelaShopping(ListaModel lista) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShoppingScreen(lista: lista),
      ),
    );
    if (mounted) _carregarDados();
  }

  /// Navega para a tela de criação de lista planejada (T04).
  Future<void> _abrirCriarLista(int usuarioId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEditListScreen(usuarioId: usuarioId),
      ),
    );
    if (mounted) _carregarDados();
  }

  /// Navega para a tela Minhas Listas (T05/T06).
  Future<void> _abrirMinhasListas(int usuarioId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MinhasListasScreen(usuarioId: usuarioId),
      ),
    );
    if (mounted) _carregarDados();
  }

  /// Obs. (novo): navega para o Mapa (T23) com localização atual e supermercados frequentados.
  Future<void> _abrirMapa() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MapaSupermercadosScreen()),
    );
  }

  /// Navega para a tela de cadastro e consulta de produtos (T10/T11).
  Future<void> _abrirCadastroProdutos(int usuarioId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastroProdutosScreen(usuarioId: usuarioId),
      ),
    );
    if (mounted) _carregarDados();
  }

  /// Navega para a tela de gerenciamento de categorias (T12/T22).
  Future<void> _abrirCadastroCategorias(int usuarioId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastroCategoriaScreen(usuarioId: usuarioId),
      ),
    );
    if (mounted) _carregarDados();
  }

  /// Exibe diálogo de confirmação e realiza o encerramento da sessão do usuário.
  Future<void> _efetuarLogout() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do Sistema'),
        content: const Text('Deseja realmente encerrar sua sessão?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.statusDanger,
            ),
            child: const Text('SAIR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      ref.read(authControllerProvider.notifier).logout();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  /// Lógica executada ao tocar no atalho da aba 'Compras' na barra inferior:
  /// - Abre diretamente o carrinho caso já exista uma compra em andamento;
  /// - Abre o diálogo de início de compra (GPS) caso exista uma lista planejada;
  /// - Exibe alerta orientativo caso não existam listas ativas.
  void _abrirAbaCompras() {
    final stateListas = ref.read(listsControllerProvider);

    stateListas.whenData((listas) {
      if (listas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma lista cadastrada. Crie uma lista primeiro!'),
            backgroundColor: AppTheme.statusDanger,
          ),
        );
        return;
      }

      final listaAtiva = listas.firstWhere(
        (l) => l.statusLista == StatusLista.emAndamento,
        orElse: () => listas.firstWhere(
          (l) => l.statusLista == StatusLista.planejada,
          orElse: () => listas.first,
        ),
      );

      if (listaAtiva.statusLista == StatusLista.emAndamento) {
        _abrirTelaShopping(listaAtiva);
      } else if (listaAtiva.statusLista == StatusLista.planejada) {
        final usuario = ref.read(authControllerProvider).value;
        IniciarCompraDialog.exibir(
          context,
          lista: listaAtiva,
          usuarioId: usuario?.idUsuario ?? 1,
        ).then((_) => _carregarDados());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Todas as listas atuais foram concluídas. Crie uma nova lista!',
            ),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }
    });
  }

  /// Navega para o histórico de compras concluídas (T18).
  Future<void> _abrirHistorico(int usuarioId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => T18HistoricoScreen(usuarioId: usuarioId),
      ),
    );
    if (mounted) _carregarDados();
  }

  /// Navega para a tela de perfil e edição de dados cadastrais do usuário (T02a).
  Future<void> _abrirPerfilUsuario() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PerfilUsuarioScreen(),
      ),
    );
    if (mounted) _carregarDados();
  }

  @override
  Widget build(BuildContext context) {
    final usuario = ref.watch(authControllerProvider).value;
    final stateListas = ref.watch(listsControllerProvider);
    final usuarioId = usuario?.idUsuario ?? 1;

    final primeiroNome = usuario?.nomeUsuario.split(' ').first ?? 'Usuário';

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Image.asset(
          'assets/images/logo.png',
          height: 38,
          fit: BoxFit.contain,
          color: Colors.white,
          colorBlendMode: BlendMode.srcIn,
        ),
        centerTitle: true,
        actions: [
          // Obs. (novo): atalho para o Mapa, ao lado do ícone de notificações
          IconButton(
            tooltip: 'Mapa',
            icon: const Icon(Icons.map_outlined, color: Colors.white),
            onPressed: _abrirMapa,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),

      // ==================== MENU LATERAL (DRAWER) ====================
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: AppTheme.primaryBlue,
              ),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.person,
                  size: 40,
                  color: AppTheme.primaryBlue,
                ),
              ),
              accountName: Text(
                usuario?.nomeUsuario ?? 'Usuário AgiLista',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              accountEmail: Text(
                usuario?.email ?? 'usuario@email.com',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),

            // Atalho para Cadastro e Consulta de Produtos
            ListTile(
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: AppTheme.primaryBlue,
              ),
              title: const Text(
                'Produtos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Cadastrar e consultar produtos'),
              onTap: () {
                Navigator.pop(context);
                _abrirCadastroProdutos(usuarioId);
              },
            ),
            const Divider(height: 1),

            // Atalho para Gerenciamento de Categorias
            ListTile(
              leading: const Icon(
                Icons.category_outlined,
                color: AppTheme.primaryBlue,
              ),
              title: const Text(
                'Categorias',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Gerenciar categorias de itens'),
              onTap: () {
                Navigator.pop(context);
                _abrirCadastroCategorias(usuarioId);
              },
            ),
            const Divider(height: 1),

            // Atalho para Minhas Listas
            ListTile(
              leading: const Icon(
                Icons.assignment_outlined,
                color: AppTheme.primaryBlue,
              ),
              title: const Text(
                'Minhas Listas',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Planejadas e concluídas'),
              onTap: () {
                Navigator.pop(context);
                _abrirMinhasListas(usuarioId);
              },
            ),
            const Divider(height: 1),

            // Obs. (novo): atalho para o Mapa (localização atual e supermercados frequentados)
            ListTile(
              leading: const Icon(
                Icons.map_outlined,
                color: AppTheme.primaryBlue,
              ),
              title: const Text(
                'Mapa',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Onde estou e meus supermercados'),
              onTap: () {
                Navigator.pop(context);
                _abrirMapa();
              },
            ),
            const Divider(height: 1),

            // Item Sobre o Aplicativo
            ListTile(
              leading: const Icon(
                Icons.info_outline,
                color: AppTheme.primaryBlue,
              ),
              title: const Text(
                'Sobre o App',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Versão, direitos e suporte'),
              onTap: () {
                Navigator.pop(context);
                _exibirDialogoSobre();
              },
            ),

            const Spacer(),
            const Divider(height: 1),

            // Ação de Logout / Encerramento de Sessão
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.statusDanger),
              title: const Text(
                'Sair do Sistema',
                style: TextStyle(
                  color: AppTheme.statusDanger,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _efetuarLogout();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),

      // ==================== CORPO PRINCIPAL COM REFRESH INDICATOR ====================
      body: RefreshIndicator(
        onRefresh: () async => _carregarDados(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Olá, $primeiroNome!',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Que bom te ver por aqui!',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 20),

              // Exibição reativa do card de Compra Ativa ou Lista Planejada
              stateListas.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Center(
                  child: Text('Erro ao carregar dados: $err'),
                ),
                data: (listas) {
                  final listasAtivas = listas
                      .where((l) => l.statusLista != StatusLista.concluida)
                      .toList();

                  if (listasAtivas.isEmpty) {
                    return _buildCardSemCompra(usuario?.idUsuario);
                  }

                  final listaExibida = listasAtivas.firstWhere(
                    (l) => l.statusLista == StatusLista.emAndamento,
                    orElse: () => listasAtivas.first,
                  );

                  return _buildCardCompraAtiva(
                    lista: listaExibida,
                    usuarioId: usuario?.idUsuario,
                  );
                },
              ),

              const SizedBox(height: 24),

              // ==================== CARDS DE ACESSO RÁPIDO ====================
              Row(
                children: [
                  Expanded(
                    child: _buildCardAcessoRapido(
                      icon: Icons.assignment_outlined,
                      titulo: 'Minha lista',
                      subtitulo: 'Ver e editar itens',
                      onTap: () => _abrirMinhasListas(usuarioId),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCardAcessoRapido(
                      icon: Icons.fact_check_outlined,
                      titulo: 'Histórico',
                      subtitulo: 'Suas compras',
                      onTap: () => _abrirHistorico(usuarioId),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

      // ==================== BARRA DE NAVEGAÇÃO INFERIOR ====================
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _abaSelecionada,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textMuted,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) {
          // Atualiza o índice visual apenas quando permanece na aba Início (index 0)
          if (index == 0) {
            setState(() {
              _abaSelecionada = index;
            });
          }

          switch (index) {
            case 0:
              _carregarDados();
              break;
            case 1:
              _abrirMinhasListas(usuarioId);
              break;
            case 2:
              _abrirAbaCompras();
              break;
            case 3:
              _abrirHistorico(usuarioId);
              break;
            case 4:
              _abrirPerfilUsuario();
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Lista',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_bag_outlined),
            label: 'Compras',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Histórico',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  /// Constrói o card exibido quando o usuário não possui listas ativas ou em andamento.
  Widget _buildCardSemCompra(int? usuarioId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Nenhuma compra em andamento.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Comece criando uma NOVA LISTA!',
            style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _abrirCriarLista(usuarioId ?? 1),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'NOVA LISTA',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: AppTheme.orangeButtonStyle,
          )
        ],
      ),
    );
  }

  /// Constrói o card reativo para listas planejadas ou compras em andamento.
  Widget _buildCardCompraAtiva({required ListaModel lista, int? usuarioId}) {
    final orcamento = lista.valorOrcamento;
    final valorGasto = lista.valorTotalAtual;
    final restante = lista.saldoRestanteOrcamento;
    final percentualGasto =
        orcamento > 0 ? (valorGasto / orcamento).clamp(0.0, 1.0) : 0.0;
    final emAndamento = lista.statusLista == StatusLista.emAndamento;

    return Column(
      children: [
        // CABEÇALHO DO CARD (GRADIENTE AZUL)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryBlue, AppTheme.primaryBlueLight],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  emAndamento ? Icons.shopping_cart : Icons.fact_check,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emAndamento ? 'Compra Em Andamento' : 'Lista Planejada',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Lista: ${lista.nomeLista}',
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 13,
                      ),
                    ),
                    if (emAndamento && lista.nomeEstabelecimento != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.white70,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              lista.nomeEstabelecimento!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // Abre o carrinho (se Em Andamento) ou inicia a compra via GPS (se Planejada)
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () {
                  if (emAndamento) {
                    _abrirTelaShopping(lista);
                  } else if (usuarioId != null) {
                    IniciarCompraDialog.exibir(
                      context,
                      lista: lista,
                      usuarioId: usuarioId,
                    ).then((_) => _carregarDados());
                  }
                },
              ),
            ],
          ),
        ),

        // CORPO DO CARD (GRÁFICO CIRCULAR E RESUMO FINANCEIRO)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 85,
                          height: 85,
                          child: CircularProgressIndicator(
                            value: percentualGasto,
                            strokeWidth: 9,
                            backgroundColor: AppTheme.borderLight,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              lista.verificarSituacaoOrcamento() == 'Excedido'
                                  ? AppTheme.statusDanger
                                  : AppTheme.primaryBlueLight,
                            ),
                          ),
                        ),
                        Text(
                          '${(percentualGasto * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color:
                                lista.verificarSituacaoOrcamento() == 'Excedido'
                                    ? AppTheme.statusDanger
                                    : AppTheme.primaryBlueLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: [
                        _buildLinhaValor(
                          'Orçamento',
                          Formatters.fmtMoeda(orcamento),
                          AppTheme.textDark,
                        ),
                        const SizedBox(height: 8),
                        _buildLinhaValor(
                          'Já gasto',
                          Formatters.fmtMoeda(valorGasto),
                          AppTheme.primaryBlueLight,
                        ),
                        const SizedBox(height: 8),
                        _buildLinhaValor(
                          'Restante',
                          Formatters.fmtMoeda(restante),
                          restante < 0
                              ? AppTheme.statusDanger
                              : AppTheme.statusSuccess,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Divider(height: 1),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (emAndamento) {
                      _abrirTelaShopping(lista);
                    } else if (usuarioId != null) {
                      IniciarCompraDialog.exibir(
                        context,
                        lista: lista,
                        usuarioId: usuarioId,
                      ).then((_) => _carregarDados());
                    }
                  },
                  style: AppTheme.orangeButtonStyle,
                  child: Text(
                    emAndamento ? 'Continuar compra' : 'Iniciar compra (GPS)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Constrói uma linha formatada de Rótulo / Valor Monetário.
  Widget _buildLinhaValor(String rotulo, String valor, Color corValor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          rotulo,
          style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: corValor,
          ),
        ),
      ],
    );
  }

  /// Constrói os cards de Atalho Rápido (Minha Lista / Histórico).
  Widget _buildCardAcessoRapido({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppTheme.primaryBlueLight),
            const SizedBox(height: 12),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}