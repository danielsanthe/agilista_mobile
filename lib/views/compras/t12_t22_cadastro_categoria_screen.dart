import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/categorias_controller.dart';
import '../../models/categoria_model.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../repositories/produtos_repository.dart';

/// ============================================================================
/// TELA T12 / T22 — CADASTRO E CONSULTA DE CATEGORIAS (PADRÃO DE ABAS)
/// ============================================================================
class CadastroCategoriaScreen extends ConsumerStatefulWidget {
  final int usuarioId;
  final int abaInicial;

  const CadastroCategoriaScreen({
    super.key,
    required this.usuarioId,
    this.abaInicial = 1,
  });

  @override
  ConsumerState<CadastroCategoriaScreen> createState() => _CadastroCategoriaScreenState();
}

class _CadastroCategoriaScreenState extends ConsumerState<CadastroCategoriaScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _descricaoController;

  int? _categoriaEmEdicaoId;
  bool _statusAtivoForm = true;
  int? _categoriaSelecionadaTabelaId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.abaInicial,
    );
    _descricaoController = TextEditingController();

    // Carrega as categorias do usuário via CategoriasController
    Future.microtask(() {
      ref.read(categoriasControllerProvider.notifier).carregarCategorias(widget.usuarioId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _descricaoController.dispose();
    super.dispose();
  }

  void _limparFormulario() {
    _descricaoController.clear();
    setState(() {
      _categoriaEmEdicaoId = null;
      _statusAtivoForm = true;
    });
  }

  void _prepararEdicaoCategoria(CategoriaModel categoria) {
    if (categoria.ehCategoriaPadrao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categorias padrões do sistema são somente leitura.'),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
      return;
    }

    setState(() {
      _categoriaEmEdicaoId = categoria.idCategoria;
      _descricaoController.text = categoria.nomeCategoria;
      _statusAtivoForm = categoria.ativo == 1;
    });
    _tabController.animateTo(0);
  }

  /// Salva ou Atualiza a Categoria via CategoriasController com Validação de Duplicidade no SQLite
  Future<void> _salvarCategoriaNoBanco() async {
    final isNova = _categoriaEmEdicaoId == null;

    try {
      await ref.read(categoriasControllerProvider.notifier).salvarCategoria(
            idCategoria: _categoriaEmEdicaoId,
            usuarioId: widget.usuarioId,
            nome: _descricaoController.text,
            ativo: _statusAtivoForm,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNova
                ? 'Categoria cadastrada com sucesso!'
                : 'Categoria atualizada com sucesso!'),
            backgroundColor: AppTheme.statusSuccess,
          ),
        );
      }

      _limparFormulario();
      _tabController.animateTo(1);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.statusDanger,
          ),
        );
      }
    }
  }

  /// Exclui uma Categoria via CategoriasController se ela não possuir produtos associados
  Future<void> _excluirCategoria(CategoriaModel categoria) async {
    if (categoria.ehCategoriaPadrao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categorias padrões do sistema não podem ser excluídas!'),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Categoria'),
        content: Text('Deseja realmente excluir a categoria "${categoria.nomeCategoria}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusDanger),
            child: const Text('EXCLUIR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await ref.read(categoriasControllerProvider.notifier).excluirCategoria(
            categoria: categoria,
            usuarioId: widget.usuarioId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Categoria excluída com sucesso!'),
            backgroundColor: AppTheme.statusSuccess,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.statusDanger,
          ),
        );
      }
    }
  }

  Future<void> _alternarStatusNaTabela(List<CategoriaModel> categoriasList) async {
    if (_categoriaSelecionadaTabelaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma categoria personalizada na lista para alterar o status!'),
          backgroundColor: AppTheme.statusDanger,
        ),
      );
      return;
    }

    final cat = categoriasList.firstWhere(
      (c) => c.idCategoria == _categoriaSelecionadaTabelaId,
      orElse: () => CategoriaModel(nomeCategoria: ''),
    );

    if (cat.idCategoria != null) {
      try {
        await ref.read(categoriasControllerProvider.notifier).alternarStatus(
              categoria: cat,
              usuarioId: widget.usuarioId,
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Status da categoria alterado com sucesso!'),
              backgroundColor: AppTheme.statusSuccess,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = e.toString().replaceFirst('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppTheme.statusDanger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncCategorias = ref.watch(categoriasControllerProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: const Text(
          'Categoria',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppTheme.primaryBlue,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.orange,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(text: 'CADASTRO'),
                Tab(text: 'CONSULTA'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAbaCadastroT22(),
          asyncCategorias.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Erro ao carregar categorias: $err')),
            data: (listaCategorias) => _buildAbaConsultaT12(listaCategorias),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textMuted,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) {
          if (index == 0) {
            Navigator.pop(context);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Lista'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Compras'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Histórico'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }

  Widget _buildAbaCadastroT22() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          const Text(
            'Descrição Categoria',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descricaoController,
            decoration: InputDecoration(
              hintText: 'Ex.: Higiene Pessoal / Hortifrúti',
              fillColor: Colors.white,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ativo:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<bool>(
                value: _statusAtivoForm,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: true, child: Text('Ativa')),
                  DropdownMenuItem(value: false, child: Text('Inativa')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _statusAtivoForm = val;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _salvarCategoriaNoBanco,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _categoriaEmEdicaoId == null ? 'SALVAR CATEGORIA' : 'ATUALIZAR CATEGORIA',
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaConsultaT12(List<CategoriaModel> categoriasList) {
    final filtroAtual = ref.watch(filtroStatusCategoriaProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text(
                'Filtrar:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<FiltroStatusCategoria>(
                  segments: const [
                    ButtonSegment(
                      value: FiltroStatusCategoria.todas,
                      label: Text('Todas', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: FiltroStatusCategoria.ativas,
                      label: Text('Ativas', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: FiltroStatusCategoria.inativas,
                      label: Text('Inativas', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {filtroAtual},
                  onSelectionChanged: (novaSelecao) {
                    ref
                        .read(categoriasControllerProvider.notifier)
                        .filtrarPorStatus(widget.usuarioId, novaSelecao.first);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 5, child: Text('DESCRIÇÃO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      Expanded(flex: 3, child: Text('ATIVO', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      SizedBox(width: 80, child: Text('AÇÃO', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: categoriasList.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhuma categoria encontrada.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: categoriasList.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final cat = categoriasList[index];
                            final idCat = cat.idCategoria ?? 0;
                            final isSelected = _categoriaSelecionadaTabelaId == idCat;
                            final isAtivo = cat.ativo == 1;

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _categoriaSelecionadaTabelaId = isSelected ? null : idCat;
                                });
                              },
                              child: Container(
                                color: isSelected ? AppTheme.primaryBlue.withAlpha(20) : null,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              cat.nomeCategoria,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                          ),
                                          if (cat.ehCategoriaPadrao)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'Padrão',
                                                style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        isAtivo ? 'Ativa' : 'Inativa',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isAtivo ? AppTheme.statusSuccess : AppTheme.statusDanger,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
                                          if (cat.ehCategoriaPadrao) ...[
                                            const Icon(Icons.lock_outline, color: Colors.grey, size: 18),
                                          ] else ...[
                                            InkWell(
                                              onTap: () => _prepararEdicaoCategoria(cat),
                                              child: const Icon(Icons.edit, color: AppTheme.primaryBlue, size: 20),
                                            ),
                                            InkWell(
                                              onTap: () => _excluirCategoria(cat),
                                              child: const Icon(Icons.delete_outline, color: AppTheme.statusDanger, size: 20),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: InkWell(
                    onTap: () {
                      _limparFormulario();
                      _tabController.animateTo(0);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(30),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => _alternarStatusNaTabela(categoriasList),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'ATIVAR / INATIVAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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
}