import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../nucleo/database/app_database.dart';

/// Repository responsável por gerenciar a exclusão offline (Soft Delete)
/// e registrar as pendências de sincronização para envio posterior ao servidor.
class ExclusaoRepository {
  final AppDatabase _appDatabase;

  ExclusaoRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  /// Exclui um registro offline das entidades ('categorias', 'produtos', 'listas', 'itens_lista').
  /// 
  /// Regra:
  /// - Se [servidorId] for nulo: O registro nunca foi para a nuvem. É deletado FISICAMENTE do SQLite.
  /// - Se [servidorId] existir: O registro é deletado localmente e inserido na fila `exclusoes_pendentes`.
  Future<void> excluirOffline({
    required String tabela,
    required String nomeColunaIdLocal, // Ex: 'id_categoria', 'id_produto', 'id_lista', 'id_item_lista'
    required int idLocal,
    required int? servidorId,
    DatabaseExecutor? executor, // opcional: permite participar de uma transação externa
  }) async {
    // Já dentro de uma transação do chamador: usa o executor recebido.
    if (executor != null) {
      await _executarExclusao(
        executor,
        tabela: tabela,
        nomeColunaIdLocal: nomeColunaIdLocal,
        idLocal: idLocal,
        servidorId: servidorId,
      );
      return;
    }

    // Comportamento original: abre a própria transação.
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await _executarExclusao(
        txn,
        tabela: tabela,
        nomeColunaIdLocal: nomeColunaIdLocal,
        idLocal: idLocal,
        servidorId: servidorId,
      );
    });
  }

  /// Faz a exclusão local e, se o registro já existia no servidor,
  /// registra a pendência na fila de sincronização.
  Future<void> _executarExclusao(
    DatabaseExecutor executor, {
    required String tabela,
    required String nomeColunaIdLocal,
    required int idLocal,
    required int? servidorId,
  }) async {
    // Deleta do SQLite local para sumir da tela instantaneamente
    await executor.delete(
      tabela,
      where: '$nomeColunaIdLocal = ?',
      whereArgs: [idLocal],
    );

    // Só entra na fila de sync se o registro já existia no servidor.
    if (servidorId != null) {
      await executor.insert('exclusoes_pendentes', {
        'tabela': tabela,
        'id_local': idLocal,
        'servidor_id': servidorId,
        'data_exclusao': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Retorna a lista de todas as exclusões pendentes para envio em lote à API
  Future<List<Map<String, dynamic>>> obterExclusoesPendentes() async {
    final db = await _appDatabase.database;
    return await db.query('exclusoes_pendentes', orderBy: 'id_exclusao ASC');
  }

  /// Remove o item da fila após a API FastAPI responder com Sucesso (Status 200/204)
  Future<void> removerPendencia(int idExclusao) async {
    final db = await _appDatabase.database;
    await db.delete(
      'exclusoes_pendentes',
      where: 'id_exclusao = ?',
      whereArgs: [idExclusao],
    );
  }
}