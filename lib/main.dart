import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyExpensesApp());
}

class Entry {
  final int? id;
  final String particular;
  final double amount;
  final String type;
  final DateTime date;
  final String note;

  Entry({
    this.id,
    required this.particular,
    required this.amount,
    required this.type,
    required this.date,
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'particular': particular,
        'amount': amount,
        'type': type,
        'date': DateFormat('yyyy-MM-dd').format(date),
        'created_at': date.millisecondsSinceEpoch,
        'note': note,
      };

  factory Entry.fromMap(Map<String, dynamic> map) => Entry(
        id: map['id'] as int?,
        particular: map['particular'] ?? '',
        amount: (map['amount'] as num).toDouble(),
        type: map['type'] ?? 'expense',
        date: DateTime.parse(map['date']),
        note: map['note'] ?? '',
      );
}

class DB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'myexpenses.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE entries (id INTEGER PRIMARY KEY AUTOINCREMENT, particular TEXT NOT NULL, amount REAL NOT NULL, type TEXT NOT NULL, date TEXT NOT NULL, created_at INTEGER NOT NULL, note TEXT DEFAULT "")',
        );
      },
    );
    return _db!;
  }

  static Future<List<Entry>> all() async {
    final d = await db;
    final rows = await d.query('entries', orderBy: 'date DESC, created_at DESC');
    return rows.map(Entry.fromMap).toList();
  }

  static Future<int> insert(Entry e) async => (await db).insert('entries', e.toMap());

  static Future<int> update(Entry e) async =>
      (await db).update('entries', e.toMap(), where: 'id=?', whereArgs: [e.id]);

  static Future<int> delete(int id) async =>
      (await db).delete('entries', where: 'id=?', whereArgs: [id]);

  static Future<void> replaceAll(List<Entry> entries) async {
    final d = await db;
    await d.transaction((tx) async {
      await tx.delete('entries');
      for (final e in entries) {
        await tx.insert('entries', e.toMap());
      }
    });
  }
}

class MyExpensesApp extends StatefulWidget {
  const MyExpensesApp({super.key});

  @override
  State<MyExpensesApp> createState() => _MyExpensesAppState();
}

class _MyExpensesAppState extends State<MyExpensesApp> {
  bool dark = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => dark = prefs.getBool('dark') ?? false);
  }

  void toggle() {
    setState(() => dark = !dark);
    SharedPreferences.getInstance().then((prefs) => prefs.setBool('dark', dark));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MyExpenses',
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: Home(onDarkToggle: toggle, dark: dark),
      );
}

class Home extends StatefulWidget {
  final VoidCallback onDarkToggle;
  final bool dark;

  const Home({
    super.key,
    required this.onDarkToggle,
    required this.dark,
  });

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  String type = 'expense';
  String particular = '';
  final amount = TextEditingController();
  final note = TextEditingController();

  List<String> cats = [
    'Salary',
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Health',
    'Entertainment',
    'Investment',
    'Others',
  ];
  List<Entry> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadCats();
  }

  Future<void> _loadCats() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('cats');
    if (saved != null && saved.isNotEmpty) {
      setState(() => cats = saved);
    }
  }

  Future<void> _saveCats() {
    return SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList('cats', cats));
  }

  Future<void> _refresh() async {
    final data = await DB.all();
    if (mounted) {
      setState(() => entries = data..sort((a, b) => b.date.compareTo(a.date)));
    }
  }

  double get income =>
      entries.where((e) => e.type == 'income').fold(0.0, (sum, e) => sum + e.amount);

  double get expense =>
      entries.where((e) => e.type == 'expense').fold(0.0, (sum, e) => sum + e.amount);

  double get balance => income - expense;

  double today(String typeName) {
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return entries
        .where((e) =>
            DateFormat('yyyy-MM-dd').format(e.date) == now && e.type == typeName)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> addEntry() async {
    final category = particular.trim();
    final value = double.tryParse(amount.text.trim());

    if (category.isEmpty || value == null || value <= 0) {
      _msg('Enter category and amount.');
      return;
    }

    await DB.insert(
      Entry(
        particular: category,
        amount: value,
        type: type,
        date: DateTime.now(),
        note: note.text.trim(),
      ),
    );

    amount.clear();
    note.clear();
    setState(() => particular = '');
    await _refresh();
    _msg('Saved ✓');
  }

  void _msg(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> edit(Entry e) async {
    final pc = TextEditingController(text: e.particular);
    final ac = TextEditingController(text: e.amount.toStringAsFixed(2));
    final nc = TextEditingController(text: e.note);

    String et = e.type;
    DateTime date = e.date;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'income', label: Text('Income')),
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                ],
                selected: {et},
                onSelectionChanged: (s) => et = s.first,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pc,
                decoration: const InputDecoration(labelText: 'Particular'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nc,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ac,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: Text('Date: ${DateFormat('yyyy-MM-dd').format(date)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(
                    context: c,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) {
                    date = d;
                    (c as Element).markNeedsBuild();
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DB.update(
        Entry(
          id: e.id,
          particular: pc.text.trim(),
          amount: double.tryParse(ac.text) ?? e.amount,
          type: et,
          date: date,
          note: nc.text.trim(),
        ),
      );
      await _refresh();
    }
  }

  Future<void> remove(Entry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(e.particular),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DB.delete(e.id!);
      await _refresh();
    }
  }

  Future<Map<String, dynamic>> makeBackup() async => {
        'app': 'MyExpenses',
        'version': 5,
        'created_at': DateTime.now().toIso8601String(),
        'categories': cats,
        'entries': entries.map((e) => e.toMap()).toList(),
      };

  Future<void> backup() async {
    final data =
        const JsonEncoder.withIndent('  ').convert(await makeBackup());

    final dir = Directory(
      '/data/user/0/${Platform.environment['ANDROID_APP_PACKAGE'] ?? 'com.mhdigitalpoint.myexpenses'}/files',
    );

    final bytes = Uint8List.fromList(utf8.encode(data));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save MyExpenses Backup',
      fileName:
          'MyExpenses_Backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (path != null) {
      _msg('Backup saved ✓');
    }
  }

  Future<void> restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null) return;

    try {
      final bytes =
          result.files.single.bytes ?? await File(result.files.single.path!).readAsBytes();
      final jsonData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final list = (jsonData['entries'] as List)
          .map((x) => Entry.fromMap(Map<String, dynamic>.from(x)))
          .toList();

      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Restore backup?'),
          content:
              Text('${list.length} entries will replace current data.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (ok == true) {
        await DB.replaceAll(list);

        if (jsonData['categories'] is List) {
          cats = List<String>.from(jsonData['categories']);
          await _saveCats();
        }

        await _refresh();
        _msg('Backup restored ✓');
      }
    } catch (_) {
      _msg('Invalid backup file.');
    }
  }

  Future<void> shareBackup() async {
    final data =
        const JsonEncoder.withIndent('  ').convert(await makeBackup());
    final dir = await getTemporaryDirectoryCompat();
    final file = File(
      p.join(dir.path, 'MyExpenses_Backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json'),
    );
    await file.writeAsString(data);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'MyExpenses backup',
      ),
    );
  }

  Future<void> printLedger() async {
    final doc = pw.Document();
    final rows = <List<String>>[];
    double runningBalance = 0;

    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));

    for (final e in sorted) {
      if (e.type == 'income') {
        runningBalance += e.amount;
      } else {
        runningBalance -= e.amount;
      }

      rows.add([
        DateFormat('yyyy-MM-dd').format(e.date),
        e.particular,
        e.type == 'income' ? e.amount.toStringAsFixed(2) : '',
        e.type == 'expense' ? e.amount.toStringAsFixed(2) : '',
        runningBalance.toStringAsFixed(2),
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Header(level: 0, child: pw.Text('MyExpenses - Account Ledger')),
          pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: ['Date', 'Category', 'Receive', 'Expense', 'Balance'],
            data: rows,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('MyExpenses'),
          actions: [
            IconButton(
              onPressed: widget.onDarkToggle,
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
        ),
        body: IndexedStack(
          index: tab,
          children: [
            entryPage(),
            historyPage(),
            reportPage(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (index) => setState(() => tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'Entry',
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.assessment_outlined),
              label: 'Report',
            ),
          ],
        ),
      );

  Widget entryPage() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        label: Text('Expense'),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text('Income'),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setState(() => type = s.first),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Particular / Category',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: cats
                        .map(
                          (c) => ChoiceChip(
                            label: Text(c),
                            selected: particular == c,
                            onSelected: (_) => setState(() => particular = c),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      prefixText: '৳ ',
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: addEntry,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Entry'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Manage Categories'),
              trailing: const Icon(Icons.chevron_right),
              onTap: manageCategories,
            ),
          ),
        ],
      );

  Widget history](#)

