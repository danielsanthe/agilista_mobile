
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../constantes/status_constants.dart';

/// ============================================================================
/// GERENCIADOR DO BANCO DE DADOS LOCAL SQFLITE (OFFLINE-FIRST)
/// ============================================================================
/// Classe Singleton responsável pela abertura, versionamento, criação de tabelas
/// e migrações do banco de dados SQLite (`agilista.db`) utilizado pelo aplicativo.
///
/// Regras de Negócio Aplicadas:
/// - Categorias: Padrões globais do sistema (`usuario_id = NULL`) e personalizadas por usuário.
/// - Produtos: Catálogo privado do usuário com vínculo para categoria e suporte a código de barras (EAN).
/// - Sincronização: Tabelas com `servidor_id` e `flag_sincronizado` para integração com FastAPI.
/// - Exclusões: Tabela separada para registrar exclusões pendentes de sincronização.
class AppDatabase {
  static const String _databaseName = 'agilista.db';

  /// Versão 7: Expansão do CHECK de Controle de exclusões pendentes de sincronização categorias, produtos, lista e itens listas.
  static const int _databaseVersion = 7;

  // Pattern Singleton para garantir apenas uma instância ativa do banco de dados
  AppDatabase._privateConstructor();
  static final AppDatabase instance = AppDatabase._privateConstructor();

  static Database? _database;

  /// Getter assíncrono para obter a instância ativa do banco de dados.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Inicializa e abre a conexão com o banco de dados SQLite local.
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
      onOpen: _onOpen,
    );
  }

  /// Configuração inicial da conexão: habilita o suporte a Chaves Estrangeiras.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Executado sempre que o banco é aberto no dispositivo.
  /// Garante que o seed de categorias padrões esteja presente.
  Future<void> _onOpen(Database db) async {
    await _seedInitialCategories(db);
  }

  /// Cria a tabela de exclusões pendentes de sincronização com suporte a todas as 4 entidades.
  Future<void> _criarTabelaExclusoesPendentes(Database db) async {
    await db.execute('''
      CREATE TABLE exclusoes_pendentes (
        id_exclusao INTEGER PRIMARY KEY AUTOINCREMENT,
        tabela TEXT NOT NULL CHECK (tabela IN ('categorias', 'produtos', 'listas', 'itens_lista')),
        id_local INTEGER NOT NULL,
        servidor_id INTEGER,
        data_exclusao TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX idx_exclusoes_pendentes_servidor
      ON exclusoes_pendentes (servidor_id);
    ''');
  }

  /// Executa migrações progressivas de esquema sem perder os dados das instalações existentes.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migração v2: Adiciona campos de localização do estabelecimento nas listas
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE listas ADD COLUMN endereco_estabelecimento TEXT;');
      await db.execute('ALTER TABLE listas ADD COLUMN bairro TEXT;');
      await db.execute('ALTER TABLE listas ADD COLUMN cidade TEXT;');
      await db.execute('ALTER TABLE listas ADD COLUMN uf TEXT;');
    }

    // Migração v3: Adiciona colunas para suporte a categorias personalizadas
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE categorias ADD COLUMN usuario_id INTEGER DEFAULT NULL;');
      await db.execute('ALTER TABLE categorias ADD COLUMN ativo INTEGER NOT NULL DEFAULT 1;');
    }

    // Migração v4: Torna as categorias iniciais globais e ajusta acentuação de status
    if (oldVersion < 4) {
      await db.execute(
        'UPDATE categorias SET usuario_id = NULL WHERE usuario_id = 1 OR usuario_id IS NOT NULL;',
      );
      await db.execute(
        "UPDATE listas SET status_lista = '${StatusLista.concluida}' WHERE status_lista = 'Concluida'",
      );
    }

    // =========================================================================
    // MIGRAÇÃO V5: Perfil Completo de Usuário + Suporte à Sincronização
    // =========================================================================
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE usuarios ADD COLUMN cpf TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN telefone TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN cep TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN logradouro TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN numero TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN bairro TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN cidade TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN uf TEXT;');
      await db.execute('ALTER TABLE usuarios ADD COLUMN servidor_id INTEGER;');
      await db.execute(
        'ALTER TABLE usuarios ADD COLUMN flag_sincronizado INTEGER NOT NULL DEFAULT 0;',
      );

      await db.execute('ALTER TABLE categorias ADD COLUMN servidor_id INTEGER;');
      await db.execute(
        'ALTER TABLE categorias ADD COLUMN flag_sincronizado INTEGER NOT NULL DEFAULT 0;',
      );

      await db.execute('ALTER TABLE produtos ADD COLUMN servidor_id INTEGER;');
      await db.execute(
        'ALTER TABLE produtos ADD COLUMN flag_sincronizado INTEGER NOT NULL DEFAULT 0;',
      );

      await db.execute('ALTER TABLE listas ADD COLUMN servidor_id INTEGER;');
      await db.execute(
        'ALTER TABLE listas ADD COLUMN flag_sincronizado INTEGER NOT NULL DEFAULT 0;',
      );

      await db.execute('ALTER TABLE itens_lista ADD COLUMN servidor_id INTEGER;');
      await db.execute(
        'ALTER TABLE itens_lista ADD COLUMN flag_sincronizado INTEGER NOT NULL DEFAULT 0;',
      );
    }

    // =========================================================================
    // MIGRAÇÃO V6: Criação inicial da tabela de exclusões
    // =========================================================================
    if (oldVersion < 6) {
      await _criarTabelaExclusoesPendentes(db);
    }

    // =========================================================================
    // MIGRAÇÃO V7: Expansão dos CHECKs para aceitar categorias e produtos
    // =========================================================================
    if (oldVersion < 7 && oldVersion >= 6) {
      // No SQLite não dá para fazer ALTER CHECK direto, recriamos a tabela mantendo dados antigos
      await db.execute('ALTER TABLE exclusoes_pendentes RENAME TO exclusoes_pendentes_old;');
      await _criarTabelaExclusoesPendentes(db);
      await db.execute('''
        INSERT INTO exclusoes_pendentes (id_exclusao, tabela, id_local, servidor_id, data_exclusao)
        SELECT id_exclusao, tabela, id_local, servidor_id, data_exclusao 
        FROM exclusoes_pendentes_old;
      ''');
      await db.execute('DROP TABLE exclusoes_pendentes_old;');
    }
  }

  /// Cria a estrutura inicial de tabelas do banco de dados na primeira instalação.
  Future<void> _onCreate(Database db, int version) async {
    // 1. Tabela CATEGORIAS
    await db.execute('''
      CREATE TABLE categorias (
        id_categoria INTEGER PRIMARY KEY AUTOINCREMENT,
        servidor_id INTEGER,
        usuario_id INTEGER,
        nome_categoria TEXT NOT NULL,
        ativo INTEGER NOT NULL DEFAULT 1,
        status_categoria TEXT NOT NULL DEFAULT '${StatusGeral.ativo}',
        flag_sincronizado INTEGER NOT NULL DEFAULT 0
      );
    ''');

    // 2. Tabela USUARIOS
    await db.execute('''
      CREATE TABLE usuarios (
        id_usuario INTEGER PRIMARY KEY AUTOINCREMENT,
        servidor_id INTEGER,
        nome_usuario TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        cpf TEXT,
        telefone TEXT,
        cep TEXT,
        logradouro TEXT,
        numero TEXT,
        bairro TEXT,
        cidade TEXT,
        uf TEXT,
        senha_hash TEXT NOT NULL,
        tipo_plano TEXT NOT NULL DEFAULT 'FreeTrial',
        flag_sincronizado INTEGER NOT NULL DEFAULT 0,
        data_cadastro TEXT NOT NULL,
        ultima_sincronizacao TEXT
      );
    ''');

    // 3. Tabela PRODUTOS
    await db.execute('''
      CREATE TABLE produtos (
        id_produto INTEGER PRIMARY KEY AUTOINCREMENT,
        servidor_id INTEGER,
        categoria_id INTEGER NOT NULL,
        codigo_barras TEXT UNIQUE,
        nome_produto TEXT NOT NULL,
        unidade_medida TEXT NOT NULL DEFAULT 'Un',
        flag_produto_recorrente INTEGER NOT NULL DEFAULT 0,
        flag_sincronizado INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (categoria_id) REFERENCES categorias (id_categoria) ON DELETE RESTRICT
      );
    ''');

    // 4. Tabela LISTAS
    await db.execute('''
      CREATE TABLE listas (
        id_lista INTEGER PRIMARY KEY AUTOINCREMENT,
        servidor_id INTEGER,
        usuario_id INTEGER NOT NULL,
        nome_lista TEXT NOT NULL,
        valor_orcamento REAL NOT NULL,
        valor_total_atual REAL NOT NULL DEFAULT 0.0,
        status_lista TEXT NOT NULL DEFAULT '${StatusLista.planejada}',
        nome_estabelecimento TEXT,
        endereco_estabelecimento TEXT,
        bairro TEXT,
        cidade TEXT,
        uf TEXT,
        flag_sincronizado INTEGER NOT NULL DEFAULT 0,
        data_criacao TEXT NOT NULL,
        data_hora_inicio TEXT,
        data_hora_termino TEXT,
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id_usuario) ON DELETE CASCADE
      );
    ''');

    // 5. Tabela ITENS_LISTA
    await db.execute('''
      CREATE TABLE itens_lista (
        id_item_lista INTEGER PRIMARY KEY AUTOINCREMENT,
        servidor_id INTEGER,
        lista_id INTEGER NOT NULL,
        produto_id INTEGER,
        nome_item_planejado TEXT NOT NULL,
        qtd_planejada REAL NOT NULL DEFAULT 1.0,
        preco_estimado REAL NOT NULL DEFAULT 0.0,
        qtd_comprada REAL DEFAULT 0.0,
        preco_unitario REAL DEFAULT 0.0,
        subtotal_item REAL DEFAULT 0.0,
        status_item TEXT NOT NULL DEFAULT '${StatusItem.pendente}',
        flag_promocao INTEGER NOT NULL DEFAULT 0,
        qtd_minima_promocional REAL,
        preco_promocional REAL,
        flag_fora_da_lista INTEGER NOT NULL DEFAULT 0,
        flag_sincronizado INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (lista_id) REFERENCES listas (id_lista) ON DELETE CASCADE,
        FOREIGN KEY (produto_id) REFERENCES produtos (id_produto) ON DELETE SET NULL
      );
    ''');

    // 6. Tabela EXCLUSOES_PENDENTES
    await _criarTabelaExclusoesPendentes(db);

    // Insere as categorias padrões do sistema na primeira execução
    await _seedInitialCategories(db);
  }

  /// Insere as categorias padrões do aplicativo (usuario_id = NULL e servidor_id = NULL).
  Future<void> _seedInitialCategories(Database db) async {
    final countResult = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM categorias WHERE usuario_id IS NULL'),
    );

    if (countResult == null || countResult == 0) {
      final List<String> categoriasIniciais = [
        'Hortifrúti',
        'Laticínios',
        'Padaria',
        'Limpeza',
        'Higiene Pessoal',
        'Açougue / Carnes',
        'Bebidas',
        'Mercearia / Grãos',
      ];

      for (var nome in categoriasIniciais) {
        await db.insert('categorias', {
          'usuario_id': null,
          'servidor_id': null,
          'nome_categoria': nome,
          'ativo': 1,
          'status_categoria': StatusGeral.ativo,
          'flag_sincronizado': 1,
        });
      }
    }
  }

  /// Fecha a conexão com a instância do banco de dados local.
  Future<void> close() async {
    final db = await instance.database;
    await db.close();
    _database = null;
  }
}
