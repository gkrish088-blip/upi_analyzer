import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/transaction_models.dart';

class DatabaseHelper {
  // ─── Singleton setup ────────────────────────────────────────────────────── // sp that all the instances point to same instance .

  static final DatabaseHelper _instance = DatabaseHelper._internal(); //  creates an instance using the constructor names internal
  DatabaseHelper._internal(); // here we define the connstructor named internal
  factory DatabaseHelper() => _instance; //this is the unnamed constructor which just returns the instance

  // the actual database connection — null until first use
  static Database? _database; //A Database object represents an open connection to a SQLite database.

  // getter: if db exists return it, else initialize it
  Future<Database> get database async {
    if (_database != null) return _database!; // exclamtion is used to tell "I know this isn't null right now. Trust me"
    _database = await _initDatabase();
    return _database!;
  }

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<Database> _initDatabase() async {
    // get the path where Android stores app databases
    // result looks like: /data/data/com.yourname.upi_analyzer/databases/upi_analyzer.db
    // in which the /data/data/com.yourname.upi_analyzer/databases/ this part is returned by the getDatabasesPath() function
    // and upi_analyzer.db is joined by the join() function
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'upi_analyzer.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate:
      _createTable, //when the uper opens app after install there will be no db tables , so we will need to create the tables
    );
  }

  Future<void> _createTable(Database db, int version) async {
    // our CREATE TABLE SQL here
    await db.execute('''
      CREATE TABLE transactions(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        rawSms TEXT NOT NULL,
        merchant TEXT,
        upiRef TEXT,
        bankAccount TEXT,
        availableBalance REAL,
        source TEXT,
        isVerified INTEGER NOT NULL DEFAULT 0 
      )
    ''');
  }

  // ─── Write operations ─────────────────────────────────────────────────────

  Future<void> insertTransaction(Transaction transaction) async {
    // hint:
    final db = await database;   //calls the getter function  database()
    await db.insert('transactions', transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTransaction(String id) async {
    final db = await database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllTransactions() async {
    final db = await database;
    await db.delete('transactions');
  }

  // ─── Read operations ──────────────────────────────────────────────────────

  Future<List<Transaction>> getAllTransactions() async {
    final db = await database;

   
    final maps = await db.query('transactions', orderBy: 'timestamp DESC');
    return maps.map((map) => Transaction.fromMap(map)).toList();
    
  }

  Future<List<Transaction>> getTransactionsByMonth(int year, int month) async {
    final db = await database;
    // get first and last millisecond of the given month
    // use those as range for WHERE timestamp BETWEEN ? AND ?
    // hint:
    final start = DateTime(year, month, 1).millisecondsSinceEpoch;
    final end = DateTime(year, month + 1, 1).millisecondsSinceEpoch;
    final maps = await db.query('transactions',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [start, end],
      orderBy: 'timestamp DESC');
    return maps.map((map) => Transaction.fromMap(map)).toList();

  }

  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => Transaction.fromMap(map)).toList();
  }
}
