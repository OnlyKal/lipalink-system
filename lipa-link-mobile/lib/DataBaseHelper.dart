import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '/classes/Avance.dart';
import 'func/export.dart';

/// Sens d'une dette (colonne `own`, stockée en texte pour compatibilité) :
/// - 'false' : le client VOUS DOIT de l'argent ;
/// - 'true'  : VOUS DEVEZ de l'argent au client.
const String kTheyOweMe = 'false';
const String kIOweThem = 'true';

/// Résultat d'une opération sur une avance ou une dette.
class DebtResult {
  final bool ok;
  final String message;

  /// true si la dette vient d'être entièrement réglée.
  final bool closed;

  const DebtResult(this.ok, this.message, {this.closed = false});
}

/// Soldes d'un client, séparés par sens et par devise.
class CustomerBalance {
  final double theyOweUSD;
  final double theyOweCDF;
  final double iOweUSD;
  final double iOweCDF;

  const CustomerBalance({
    this.theyOweUSD = 0,
    this.theyOweCDF = 0,
    this.iOweUSD = 0,
    this.iOweCDF = 0,
  });

  bool get isEmpty =>
      theyOweUSD <= kMoneyEpsilon &&
      theyOweCDF <= kMoneyEpsilon &&
      iOweUSD <= kMoneyEpsilon &&
      iOweCDF <= kMoneyEpsilon;

  factory CustomerBalance.fromRow(Map<String, Object?> row) => CustomerBalance(
    theyOweUSD: toAmount(row['they_owe_usd']),
    theyOweCDF: toAmount(row['they_owe_cdf']),
    iOweUSD: toAmount(row['i_owe_usd']),
    iOweCDF: toAmount(row['i_owe_cdf']),
  );
}

/// Sous-requête : chaque dette avec le total déjà payé et le reste à payer.
/// C'est la SEULE source de vérité pour les soldes : tous les totaux
/// (client, tableau de bord, relevés) sont calculés à partir d'elle.
const String _debtBalancesSql = '''
  SELECT d.id, d.customerId, d.devise, d.own, d.status, d.dueDate,
         d.motif, d.todayDate,
         d.borrowedAmount,
         COALESCE(a.paid, 0) AS paid,
         d.borrowedAmount - COALESCE(a.paid, 0) AS rest
  FROM debts d
  LEFT JOIN (SELECT debtId, SUM(amount) AS paid FROM avance GROUP BY debtId) a
         ON a.debtId = d.id
''';

/// Somme des restes positifs, par sens et devise (à utiliser sur _debtBalancesSql).
const String _balanceColumnsSql =
    '''
  COALESCE(SUM(CASE WHEN b.own = 'false' AND b.devise = 'USD' AND b.rest > $kMoneyEpsilon THEN b.rest END), 0) AS they_owe_usd,
  COALESCE(SUM(CASE WHEN b.own = 'false' AND b.devise = 'CDF' AND b.rest > $kMoneyEpsilon THEN b.rest END), 0) AS they_owe_cdf,
  COALESCE(SUM(CASE WHEN b.own = 'true'  AND b.devise = 'USD' AND b.rest > $kMoneyEpsilon THEN b.rest END), 0) AS i_owe_usd,
  COALESCE(SUM(CASE WHEN b.own = 'true'  AND b.devise = 'CDF' AND b.rest > $kMoneyEpsilon THEN b.rest END), 0) AS i_owe_cdf
''';

class DatabaseHelper {
  // Une seule connexion pour toute l'application.
  static Database? _db;
  static Future<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _opening ??= _open();
    _db = await _opening;
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'debt_.db');
    return openDatabase(path, version: 1, onCreate: _createDb);
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fullname TEXT,
        phone TEXT,
        email TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE debts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER,
        name TEXT,
        telephone TEXT,
        todayDate TEXT,
        dueDate TEXT,
        borrowedAmount REAL,
        devise TEXT,
        motif TEXT,
        status TEXT,
        own TEXT,
        FOREIGN KEY (customerId) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE avance(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debtId INTEGER,
        customerId INTEGER,
        amount REAL,
        paidDate TEXT,
        devise TEXT,
        own TEXT,
        FOREIGN KEY (debtId) REFERENCES debts(id),
        FOREIGN KEY (customerId) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE rate (
        id INTEGER PRIMARY KEY,
        valueRate TEXT DEFAULT 2000
      )
    ''');
    await db.insert('rate', {'valueRate': '2000'});

    await db.execute('''
      CREATE TABLE company (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT DEFAULT 'LIPALINK'
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(fullname)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_debts_customer_devise ON debts(customerId, devise, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_debts_due_date ON debts(dueDate, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_avance_debt ON avance(debtId, devise)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_avance_customer ON avance(customerId, devise)',
    );
  }

  /// À appeler au démarrage : garantit le taux par défaut et l'entreprise,
  /// puis recalcule le statut "réglée" de chaque dette à partir des avances
  /// (répare les incohérences laissées par les anciennes versions).
  Future<void> ensureInitialData() async {
    final db = await database;
    final rates = await db.query('rate', limit: 1);
    if (rates.isEmpty) await db.insert('rate', {'valueRate': '2000'});
    await addCompany();
    // Anciennes dates au format "2026-01-10 00:00:00" -> ISO "2026-01-10T00:00:00"
    // pour que les comparaisons d'échéances soient justes.
    await db.rawUpdate(
      "UPDATE debts SET dueDate = REPLACE(dueDate, ' ', 'T') WHERE dueDate LIKE '% %'",
    );
    await db.rawUpdate('''
      UPDATE debts SET status = CASE
        WHEN borrowedAmount - COALESCE(
          (SELECT SUM(amount) FROM avance WHERE avance.debtId = debts.id), 0
        ) <= $kMoneyEpsilon THEN 'true' ELSE 'false' END
    ''');
  }

  // ============================== ENTREPRISE ==============================

  Future<List<Map<String, dynamic>>?> getCompany() async {
    final db = await database;
    return db.query('company');
  }

  Future<void> updateCompany(int id, String name) async {
    final db = await database;
    await db.update('company', {'nom': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addCompany() async {
    final db = await database;
    final rows = await db.query('company', limit: 1);
    if (rows.isEmpty) await db.insert('company', {'nom': 'LIPALINK'});
  }

  // ================================ TAUX ================================

  Future<List<Rate>> getRate() async {
    final db = await database;
    final maps = await db.query('rate');
    return maps.map((m) => Rate.fromMap(m)).toList();
  }

  /// Taux du jour (CDF pour 1 USD). Retourne null s'il est absent ou invalide.
  Future<double?> getRateValue() async {
    final rates = await getRate();
    if (rates.isEmpty) return null;
    final value = parseAmount(rates.first.valueRate);
    return (value != null && value > 0) ? value : null;
  }

  Future<void> updateRate(String newRate) async {
    final db = await database;
    await db.update('rate', {'valueRate': newRate});
  }

  // ============================== CLIENTS ==============================

  /// Clients avec leurs soldes (une seule requête pour toute la liste).
  Future<List<Map<String, Object?>>> getCustomersWithBalances() async {
    final db = await database;
    return db.rawQuery('''
      SELECT c.id, c.fullname, c.phone, c.email, $_balanceColumnsSql
      FROM customers c
      LEFT JOIN ($_debtBalancesSql) b ON b.customerId = c.id
      GROUP BY c.id
      ORDER BY c.fullname COLLATE NOCASE ASC
    ''');
  }

  Future<CustomerBalance> getCustomerBalance(int customerId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT $_balanceColumnsSql
      FROM ($_debtBalancesSql) b
      WHERE b.customerId = ?
    ''',
      [customerId],
    );
    return rows.isEmpty
        ? const CustomerBalance()
        : CustomerBalance.fromRow(rows.first);
  }

  Future<void> createCustomer(Customer customer) async {
    final db = await database;
    await db.insert('customers', customer.toMap());
  }

  Future<void> updateCustomerPhone(String phone, int id) async {
    final db = await database;
    await db.update(
      'customers',
      {'phone': phone},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateCustomername(String fullname, int id) async {
    final db = await database;
    await db.update(
      'customers',
      {'fullname': fullname},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Supprime un client avec tout son historique (dettes et avances).
  /// Refusé tant qu'il reste une dette non réglée, dans un sens ou dans l'autre.
  Future<DebtResult> deleteCustomer(int id) async {
    final db = await database;
    final balance = await getCustomerBalance(id);
    if (!balance.isEmpty) {
      return const DebtResult(
        false,
        "Impossible : ce client a encore des dettes non réglées.",
      );
    }
    await db.transaction((txn) async {
      await txn.delete('avance', where: 'customerId = ?', whereArgs: [id]);
      await txn.delete('debts', where: 'customerId = ?', whereArgs: [id]);
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
    return const DebtResult(true, "Client supprimé");
  }

  // ============================== DETTES ==============================

  Future<int?> insertDebt(Debt debt) async {
    final db = await database;
    return db.insert('debts', debt.toMap());
  }

  /// Dettes d'un client, avec le total payé et le reste, les plus récentes d'abord.
  Future<List<Map<String, dynamic>>> getDebtsOptimized(
    int customerId,
    int offset,
    int limit,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT d.*,
             COALESCE(a.total_avance, 0) AS total_avance,
             d.borrowedAmount - COALESCE(a.total_avance, 0) AS reste_a_payer
      FROM debts d
      LEFT JOIN (
        SELECT debtId, SUM(amount) AS total_avance FROM avance GROUP BY debtId
      ) a ON d.id = a.debtId
      WHERE d.customerId = ?
      ORDER BY d.id DESC
      LIMIT ? OFFSET ?
    ''',
      [customerId, limit, offset],
    );
  }

  /// Montant, total payé et reste d'une dette. Null si elle n'existe pas.
  Future<Map<String, Object?>?> getDebtBalance(int debtId) async {
    final db = await database;
    return _debtBalance(db, debtId);
  }

  Future<Map<String, Object?>?> _debtBalance(
    DatabaseExecutor db,
    int debtId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT * FROM ($_debtBalancesSql) WHERE id = ?',
      [debtId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Met le statut de la dette en accord avec ses avances.
  /// Retourne true si la dette est réglée.
  Future<bool> _syncDebtStatus(DatabaseExecutor db, int debtId) async {
    final balance = await _debtBalance(db, debtId);
    if (balance == null) return false;
    final settled = toAmount(balance['rest']) <= kMoneyEpsilon;
    await db.update(
      'debts',
      {'status': settled ? 'true' : 'false'},
      where: 'id = ?',
      whereArgs: [debtId],
    );
    return settled;
  }

  Future<void> deleteDebtAndAvances(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('avance', where: 'debtId = ?', whereArgs: [id]);
      await txn.delete('debts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int?> changeDue(int id, String dueDate) async {
    final db = await database;
    return db.update(
      'debts',
      {'dueDate': dueDate},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Modifie le montant d'une dette. Refusé si le nouveau montant est
  /// inférieur à ce qui a déjà été payé. Le statut est recalculé.
  Future<DebtResult> changeAmount(int id, double newAmount) async {
    if (newAmount <= 0) {
      return const DebtResult(false, "Le montant doit être supérieur à 0");
    }
    final db = await database;
    return db.transaction((txn) async {
      final balance = await _debtBalance(txn, id);
      if (balance == null) {
        return const DebtResult(false, "Dette introuvable");
      }
      final paid = toAmount(balance['paid']);
      if (newAmount + kMoneyEpsilon < paid) {
        return DebtResult(
          false,
          "Montant trop bas : ${formatMoney(paid, balance['devise'].toString())} ont déjà été payés.",
        );
      }
      await txn.update(
        'debts',
        {'borrowedAmount': roundMoney(newAmount)},
        where: 'id = ?',
        whereArgs: [id],
      );
      final closed = await _syncDebtStatus(txn, id);
      return DebtResult(true, "Montant modifié", closed: closed);
    });
  }

  // ============================== AVANCES ==============================

  Future<List<Avance>> getAvance(int debtId) async {
    final db = await database;
    final maps = await db.query(
      'avance',
      where: 'debtId = ?',
      whereArgs: [debtId],
      orderBy: 'paidDate DESC, id DESC',
    );
    return maps.map((m) => Avance.fromMap(m)).toList();
  }

  /// Enregistre un paiement sur une dette.
  /// Vérifie que le montant est positif et ne dépasse pas le reste à payer,
  /// puis clôture la dette si elle est entièrement payée.
  Future<DebtResult> addAvance(int debtId, double amount) async {
    if (amount <= 0) {
      return const DebtResult(false, "Le montant doit être supérieur à 0");
    }
    final db = await database;
    return db.transaction((txn) async {
      final balance = await _debtBalance(txn, debtId);
      if (balance == null) {
        return const DebtResult(false, "Dette introuvable");
      }
      final rest = toAmount(balance['rest']);
      final devise = balance['devise'].toString();
      if (rest <= kMoneyEpsilon) {
        return const DebtResult(false, "Cette dette est déjà réglée");
      }
      if (amount > rest + kMoneyEpsilon) {
        return DebtResult(
          false,
          "Le montant dépasse le reste à payer (${formatMoney(rest, devise)})",
        );
      }
      final avance = Avance(
        amount: roundMoney(amount),
        paidDate: DateTime.now(),
        debtId: debtId,
        customerId: balance['customerId'] as int?,
        devise: devise,
        own: balance['own'].toString(),
      );
      await txn.insert('avance', avance.toMap());
      final closed = await _syncDebtStatus(txn, debtId);
      return DebtResult(
        true,
        closed ? "Dette entièrement réglée" : "Avance enregistrée",
        closed: closed,
      );
    });
  }

  /// Supprime une avance et rouvre la dette si elle n'est plus soldée.
  Future<void> deleteAvance(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'avance',
        columns: ['debtId'],
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete('avance', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty && rows.first['debtId'] != null) {
        await _syncDebtStatus(txn, rows.first['debtId'] as int);
      }
    });
  }

  // ============================== RAPPELS ==============================

  /// Nombre de dettes non réglées dont l'échéance est dépassée.
  Future<int> countOverdueDebts() async {
    final db = await database;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final rows = await db.rawQuery('''
      SELECT b.dueDate FROM ($_debtBalancesSql) b
      INNER JOIN customers c ON c.id = b.customerId
      WHERE b.rest > $kMoneyEpsilon
    ''');
    var count = 0;
    for (final row in rows) {
      final due = DateTime.tryParse(row['dueDate'].toString());
      if (due != null && due.isBefore(startOfToday)) count++;
    }
    return count;
  }

  Future<void> checkExpiredDebt() async {
    final count = await countOverdueDebts();
    if (count > 0) {
      NotificationClass.openNotif(
        "Échéance",
        count == 1
            ? "Attention ! 1 dette a dépassé son échéance."
            : "Attention ! $count dettes ont dépassé leur échéance.",
      );
    }
  }

  // ============================== RELEVÉS ==============================

  Future<List<Map<String, Object?>>?> getDEBTDetails(customerId, debtId) async {
    final result = await getMultipleDEBTDetails(customerId, [
      int.parse(debtId.toString()),
    ]);
    return (result == null || result.isEmpty) ? null : result;
  }

  Future<List<Map<String, Object?>>?> getMultipleDEBTDetails(
    customerId,
    List<int> debtIds,
  ) async {
    if (debtIds.isEmpty) return null;
    final db = await database;
    final placeholders = debtIds.map((_) => '?').join(',');
    return db.rawQuery(
      '''
      SELECT customers.fullname AS customerName, customers.phone AS telephone,
             debts.id AS debtId, debts.todayDate, debts.dueDate AS dueDate,
             debts.borrowedAmount, debts.devise AS debtDevise, debts.motif,
             debts.status, debts.own,
             avance.amount AS advanceAmount, avance.paidDate,
             avance.devise AS advanceDevise
      FROM customers
      INNER JOIN debts ON customers.id = debts.customerId
      LEFT JOIN avance ON debts.id = avance.debtId
      WHERE customers.id = ? AND debts.id IN ($placeholders)
      ORDER BY debts.id, avance.paidDate
    ''',
      [int.parse(customerId.toString()), ...debtIds],
    );
  }

  // =========================== TABLEAU DE BORD ===========================

  /// Soldes de tous les clients réunis.
  Future<CustomerBalance> getGlobalBalance() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT $_balanceColumnsSql
      FROM ($_debtBalancesSql) b
      INNER JOIN customers c ON c.id = b.customerId
    ''');
    return rows.isEmpty
        ? const CustomerBalance()
        : CustomerBalance.fromRow(rows.first);
  }

  /// Dettes non réglées les plus urgentes (en retard ou échéance proche),
  /// avec le nom du client, de l'échéance la plus ancienne à la plus proche.
  Future<List<Map<String, Object?>>> getWatchlist({
    int withinDays = 7,
    int limit = 6,
  }) async {
    final db = await database;
    // withinDays = -1 : seulement les dettes en retard (échéance avant aujourd'hui).
    final now = DateTime.now();
    final limitDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: withinDays + 1)).toIso8601String();
    return db.rawQuery(
      '''
      SELECT b.*, c.fullname
      FROM ($_debtBalancesSql) b
      INNER JOIN customers c ON c.id = b.customerId
      WHERE b.rest > $kMoneyEpsilon AND b.dueDate < ?
      ORDER BY b.dueDate ASC
      LIMIT ?
    ''',
      [limitDate, limit],
    );
  }

  /// Reste à payer par client, pour un sens ('false' = on me doit,
  /// 'true' = je dois) et une devise. Seules les dettes non soldées comptent.
  Future<List<Map<String, Object?>>> getOutstandingByCustomer(
    String own,
    String devise,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT c.fullname, SUM(b.rest) AS total
      FROM ($_debtBalancesSql) b
      INNER JOIN customers c ON c.id = b.customerId
      WHERE b.own = ? AND b.devise = ? AND b.rest > $kMoneyEpsilon
      GROUP BY c.id
      ORDER BY total DESC
    ''',
      [own, devise],
    );
  }

  // ========================== SAUVEGARDE EN LIGNE ==========================

  /// Tables copiées vers le serveur (sauvegarde et synchronisation).
  static const cloudTables = ['customers', 'debts', 'avance'];

  /// Instantané complet des données locales, prêt à être envoyé.
  Future<Map<String, Object?>> exportSnapshot() async {
    final db = await database;
    final company = await db.query('company', limit: 1);
    return {
      for (final t in cloudTables) t: await db.query(t, orderBy: 'id'),
      'rate': await getRateValue(),
      'companyName': company.isEmpty ? null : company.first['nom'],
    };
  }

  /// Remplace toutes les données locales par celles d'une sauvegarde.
  /// Tout se fait dans une transaction : en cas d'erreur, rien n'est modifié.
  Future<void> restoreSnapshot(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final t in cloudTables.reversed) {
        await txn.delete(t);
      }
      for (final t in cloudTables) {
        // On n'insère que les colonnes connues de la table locale.
        final columns = (await txn.rawQuery('PRAGMA table_info($t)'))
            .map((c) => c['name'] as String)
            .toSet();
        for (final row in (data[t] as List? ?? const [])) {
          final map = Map<String, Object?>.from(row as Map)
            ..removeWhere((k, _) => !columns.contains(k));
          await txn.insert(t, map);
        }
      }
      final rate = data['rate'];
      if (rate != null) {
        await txn.update('rate', {'valueRate': rate.toString()});
      }
      final name = data['company']?['name'] ?? data['companyName'];
      if (name != null) {
        await txn.update('company', {'nom': name.toString()});
      }
    });
    await ensureInitialData();
  }
}
