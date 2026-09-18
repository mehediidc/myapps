
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
  Entry({this.id, required this.particular, required this.amount, required this.type, required this.date, this.note = ''});
  Map<String, dynamic> toMap() => {
    'id': id, 'particular': particular, 'amount': amount, 'type': type,
    'date': DateFormat('yyyy-MM-dd').format(date), 'created_at': date.millisecondsSinceEpoch, 'note': note
  };
  factory Entry.fromMap(Map<String,dynamic> m) => Entry(
    id: m['id'] as int?, particular: m['particular'] ?? '', amount: (m['amount'] as num).toDouble(),
    type: m['type'] ?? 'expense', date: DateTime.parse(m['date']), note: m['note'] ?? ''
  );
}

class DB {
  static Database? _db;
  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(p.join(dir, 'myexpenses.db'), version: 1,
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE entries (id INTEGER PRIMARY KEY AUTOINCREMENT, particular TEXT NOT NULL, amount REAL NOT NULL, type TEXT NOT NULL, date TEXT NOT NULL, created_at INTEGER NOT NULL, note TEXT)');
      });
    return _db!;
  }
  static Future<List<Entry>> all() async {
    final d = await db;
    final rows = await d.query('entries', orderBy: 'date DESC, created_at DESC');
    return rows.map(Entry.fromMap).toList();
  }
  static Future<int> insert(Entry e) async => (await db).insert('entries', e.toMap());
  static Future<int> update(Entry e) async => (await db).update('entries', e.toMap(), where:'id=?', whereArgs:[e.id]);
  static Future<int> delete(int id) async => (await db).delete('entries', where:'id=?', whereArgs:[id]);
  static Future<void> replaceAll(List<Entry> entries) async {
    final d = await db;
    await d.transaction((tx) async {
      await tx.delete('entries');
      for (final e in entries) await tx.insert('entries', e.toMap());
    });
  }
}

class MyExpensesApp extends StatefulWidget {
  const MyExpensesApp({super.key});
  @override State<MyExpensesApp> createState()=>_MyExpensesAppState();
}
class _MyExpensesAppState extends State<MyExpensesApp> {
  bool dark=false;
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async { final p=await SharedPreferences.getInstance(); setState(()=>dark=p.getBool('dark')??false); }
  void toggle(){setState(()=>dark=!dark); SharedPreferences.getInstance().then((p)=>p.setBool('dark',dark));}
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false, title:'MyExpenses',
    themeMode: dark?ThemeMode.dark:ThemeMode.light,
    theme: ThemeData(useMaterial3:true, colorSchemeSeed:Colors.indigo, brightness:Brightness.light),
    darkTheme: ThemeData(useMaterial3:true, colorSchemeSeed:Colors.indigo, brightness:Brightness.dark),
    home: Home(onDarkToggle:toggle, dark:dark),
  );
}

class Home extends StatefulWidget {
  final VoidCallback onDarkToggle; final bool dark;
  const Home({super.key, required this.onDarkToggle, required this.dark});
  @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> {
  int tab=0; String type='expense'; String particular=''; final amount=TextEditingController(); final note=TextEditingController();
  List<String> cats=['Salary','Food','Transport','Shopping','Bills','Health','Entertainment','Investment','Others'];
  List<Entry> entries=[]; bool loading=true;

  @override void initState(){super.initState(); _refresh(); _loadCats();}
  Future<void> _loadCats() async { final p=await SharedPreferences.getInstance(); final c=p.getStringList('cats'); if(c!=null&&c.isNotEmpty)setState(()=>cats=c); }
  Future<void> _saveCats(){return SharedPreferences.getInstance().then((p)=>p.setStringList('cats',cats));}
  Future<void> _refresh() async { final e=await DB.all(); if(mounted)setState(()=>entries=e..sort((a,b)=>b.date.compareTo(a.date))); }
  double get income=>entries.where((e)=>e.type=='income').fold(0,(s,e)=>s+e.amount);
  double get expense=>entries.where((e)=>e.type=='expense').fold(0,(s,e)=>s+e.amount);
  double get balance=>income-expense;
  double today(String t)=>entries.where((e)=>DateFormat('yyyy-MM-dd').format(e.date)==DateFormat('yyyy-MM-dd').format(DateTime.now())&&e.type==t).fold(0,(s,e)=>s+e.amount);

  Future<void> addEntry() async {
    final p=particular.trim(); final a=double.tryParse(amount.text.trim());
    if(p.isEmpty || a==null || a<=0){_msg('Enter category and amount.');return;}
    await DB.insert(Entry(particular:p,amount:a,type:type,date:DateTime.now(),note:note.text.trim()));
    amount.clear(); note.clear(); setState(()=>particular=''); await _refresh(); _msg('Saved ✓');
  }
  void _msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));

  Future<void> edit(Entry e) async {
    final pc=TextEditingController(text:e.particular), ac=TextEditingController(text:e.amount.toStringAsFixed(2)), nc=TextEditingController(text:e.note);
    String et=e.type; DateTime date=e.date;
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Edit Entry'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        SegmentedButton<String>(segments:const [ButtonSegment(value:'income',label:Text('Income')),ButtonSegment(value:'expense',label:Text('Expense'))],selected:{et},onSelectionChanged:(s)=>et=s.first),
        TextField(controller:pc,decoration:const InputDecoration(labelText:'Particular')),
        TextField(controller:nc,decoration:const InputDecoration(labelText:'Note')),
        TextField(controller:ac,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount')),
        ListTile(title:Text('Date: ${DateFormat('yyyy-MM-dd').format(date)}'),trailing:const Icon(Icons.calendar_today),onTap:()async{final d=await showDatePicker(context:c,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(d!=null)date=d;})
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Update'))],
    ));
    if(ok==true){await DB.update(Entry(id:e.id,particular:pc.text.trim(),amount:double.tryParse(ac.text)??e.amount,type:et,date:date,note:nc.text.trim()));await _refresh();}
  }
  Future<void> remove(Entry e) async { if(await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete entry?'),content:Text(e.particular),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]))==true){await DB.delete(e.id!);await _refresh();}}

  Future<Map<String,dynamic>> makeBackup() async => {
    'app':'MyExpenses','version':5,'created_at':DateTime.now().toIso8601String(),
    'categories':cats,'entries':entries.map((e)=>e.toMap()).toList()
  };
  Future<void> backup() async {
    final data=const JsonEncoder.withIndent('  ').convert(await makeBackup());
    final dir=Directory('/data/user/0/${Platform.environment['ANDROID_APP_PACKAGE'] ?? 'com.mhdigitalpoint.myexpenses'}/files');
    // Android file picker is used below, so no direct Downloads permission is required.
    final bytes=Uint8List.fromList(utf8.encode(data));
    final path=await FilePicker.platform.saveFile(dialogTitle:'Save MyExpenses Backup',fileName:'MyExpenses_Backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json',bytes:bytes,type:FileType.custom,allowedExtensions:['json']);
    if(path!=null)_msg('Backup saved ✓');
  }
  Future<void> restore() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json'],withData:true);
    if(r==null)return;
    try {
      final bytes=r.files.single.bytes ?? await File(r.files.single.path!).readAsBytes();
      final j=jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>;
      final list=(j['entries'] as List).map((x)=>Entry.fromMap(Map<String,dynamic>.from(x))).toList();
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Restore backup?'),content:Text('${list.length} entries will replace current data.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Restore'))]));
      if(ok==true){await DB.replaceAll(list); if(j['categories'] is List){cats=List<String>.from(j['categories']);await _saveCats();} await _refresh();_msg('Backup restored ✓');}
    }catch(e){_msg('Invalid backup file.');}
  }
  Future<void> shareBackup() async {
    final data=const JsonEncoder.withIndent('  ').convert(await makeBackup());
    final dir=await getTemporaryDirectoryCompat();
    final f=File(p.join(dir.path,'MyExpenses_Backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json'));
    await f.writeAsString(data); await SharePlus.instance.share(ShareParams(files:[XFile(f.path)],text:'MyExpenses backup'));
  }
  Future<void> printLedger() async {
    final doc=pw.Document();
    final rows=<List<String>>[];
    double run=0;
    final sorted=[...entries]..sort((a,b)=>a.date.compareTo(b.date));
    for(final e in sorted){if(e.type=='income')run+=e.amount;else run-=e.amount;rows.add([DateFormat('yyyy-MM-dd').format(e.date),e.particular,e.type=='income'?e.amount.toStringAsFixed(2):'',e.type=='expense'?e.amount.toStringAsFixed(2):'',run.toStringAsFixed(2)]);}
    doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,build:(ctx)=>[
      pw.Header(level:0,child:pw.Text('MyExpenses - Account Ledger')),
      pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
      pw.SizedBox(height:10),
      pw.Table.fromTextArray(headers:['Date','Category','Receive','Expense','Balance'],data:rows),
    ]));
    await Printing.layoutPdf(onLayout:(format)async=>doc.save());
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('MyExpenses'),actions:[IconButton(onPressed:widget.onDarkToggle,icon:Icon(widget.dark?Icons.light_mode:Icons.dark_mode))]),
    body: IndexedStack(index:tab,children:[entryPage(),historyPage(),reportPage()]),
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
      NavigationDestination(icon:Icon(Icons.add_circle_outline),selectedIcon:Icon(Icons.add_circle),label:'Entry'),
      NavigationDestination(icon:Icon(Icons.history),label:'History'),
      NavigationDestination(icon:Icon(Icons.assessment_outlined),label:'Report')]),
  );

  Widget entryPage()=>ListView(padding:const EdgeInsets.all(16),children:[
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
      SegmentedButton<String>(segments:const[ButtonSegment(value:'expense',label:Text('Expense')),ButtonSegment(value:'income',label:Text('Income'))],selected:{type},onSelectionChanged:(s)=>setState(()=>type=s.first)),
      const SizedBox(height:12),
      Align(alignment:Alignment.centerLeft,child:Text('Particular / Category',style:Theme.of(context).textTheme.titleMedium)),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:cats.map((c)=>ChoiceChip(label:Text(c),selected:particular==c,onSelected:(_)=>setState(()=>particular=c)).toList()),
      const SizedBox(height:12),
      TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(prefixText:'৳ ',labelText:'Amount',border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:note,decoration:const InputDecoration(labelText:'Note (optional)',border:OutlineInputBorder())),
      const SizedBox(height:12),
      SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:addEntry,icon:const Icon(Icons.save),label:const Text('Save Entry'))),
    ]))),
    Card(child:ListTile(title:const Text('Manage Categories'),trailing:const Icon(Icons.chevron_right),onTap:manageCategories)),
  ]);
  Widget historyPage()=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      Expanded(child:summaryCard('Today Income',today('income'))),const SizedBox(width:6),
      Expanded(child:summaryCard('Today Expense',today('expense'))),const SizedBox(width:6),
      Expanded(child:summaryCard('Today Balance',today('income')-today('expense'))),
    ])),
    Expanded(child:entries.isEmpty?const Center(child:Text('No entries yet.')):ListView.builder(itemCount:entries.length,itemBuilder:(c,i){final e=entries[i];return ListTile(
      leading:CircleAvatar(child:Icon(e.type=='income'?Icons.arrow_downward:Icons.arrow_upward)),
      title:Text(e.particular),subtitle:Text('${DateFormat('yyyy-MM-dd').format(e.date)}${e.note.isEmpty?'':' • '+e.note}'),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('${e.type=='income'?'+':'-'} ৳${e.amount.toStringAsFixed(2)}'),IconButton(icon:const Icon(Icons.edit),onPressed:()=>edit(e)),IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>remove(e))])
    );})),
    Card(child:ListTile(title:const Text('Account Ledger'),subtitle:const Text('Native Android print dialog'),trailing:FilledButton(onPressed:printLedger,child:const Text('Print')))),
    backupSection(),
  ]);
  Widget backupSection()=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Text('Backup & Restore',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    const Text('Backup uses the Android file picker, so the file can be saved to your chosen phone storage location.'),
    const SizedBox(height:8),
    FilledButton.icon(onPressed:backup,icon:const Icon(Icons.save_alt),label:const Text('Save Backup File')),
    OutlinedButton.icon(onPressed:restore,icon:const Icon(Icons.restore),label:const Text('Restore From File')),
    OutlinedButton.icon(onPressed:shareBackup,icon:const Icon(Icons.share),label:const Text('Share Backup')),
  ])));
  Widget reportPage()=>ListView(padding:const EdgeInsets.all(16),children:[
    Row(children:[Expanded(child:summaryCard('Income',income)),Expanded(child:summaryCard('Expense',expense)),Expanded(child:summaryCard('Balance',balance))]),
    const SizedBox(height:12),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Particular-wise Summary',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      ...cats.map((c){final x=entries.where((e)=>e.particular==c&&e.type=='expense').fold(0.0,(s,e)=>s+e.amount);final pct=expense==0?0:x/expense*100;return ListTile(title:Text(c),subtitle:LinearProgressIndicator(value:pct/100),trailing:Text('৳${x.toStringAsFixed(2)}\\n${pct.toStringAsFixed(1)}%'));})
    ]))),
  ]);
  Widget summaryCard(String title,double value)=>Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)),const SizedBox(height:3),Text('৳${value.toStringAsFixed(2)}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:14))])));
  Future<void> manageCategories() async {
    final c=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('Manage Categories'),content:SizedBox(width:400,child:Column(mainAxisSize:MainAxisSize.min,children:[
      ...cats.map((x)=>ListTile(title:Text(x),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:(){setD(()=>cats.remove(x));}))),
      TextField(controller:c,decoration:const InputDecoration(labelText:'New category'))
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){if(c.text.trim().isNotEmpty)cats.add(c.text.trim());_saveCats();Navigator.pop(ctx);setState((){});},child:const Text('Save'))]));
  }
}

Future<Directory> getTemporaryDirectoryCompat() async {
  // Avoid adding another dependency; use app cache directory on Android.
  final d=Directory('/data/data/com.mhdigitalpoint.myexpenses/cache');
  if(!await d.exists()) await d.create(recursive:true);
  return d;
}
