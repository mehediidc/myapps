import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Expenses',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ExpenseHomePage(),
    );
  }
}

class ExpenseHomePage extends StatefulWidget {
  const ExpenseHomePage({super.key});

  @override
  State<ExpenseHomePage> createState() => _ExpenseHomePageState();
}

class _ExpenseHomePageState extends State<ExpenseHomePage> {
  final List<Map<String, dynamic>> _expenses = [
    {'title': 'Groceries', 'amount': 45.50},
    {'title': 'Utilities', 'amount': 120.00},
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  void _addExpense() {
    final title = _titleController.text;
    final amount = double.tryParse(_amountController.text) ?? 0.0;

    if (title.isNotEmpty && amount > 0) {
      setState(() {
        _expenses.add({'title': title, 'amount': amount});
      });
      _titleController.clear();
      _amountController.clear();
    }
  }

  // Fixed Line 63: Enclosed single-line 'for' loop in curly braces
  double _calculateTotal() {
    double total = 0.0;
    for (var expense in _expenses) {
      total += (expense['amount'] as double);
    }
    return total;
  }

  // Fixed Line 137 & Line 150:
  // - Removed unused 'dir' variable declaration
  // - Added context.mounted check across async gap before showing SnackBar
  Future<void> _exportData() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/expenses_backup.json');

    final jsonString = jsonEncode(_expenses);
    await file.writeAsString(jsonString);

    if (!mounted) return;

    await Share.shareXFiles([XFile(file.path)], text: 'My Expenses Backup');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Data exported successfully!')),
    );
  }

  // Fixed Line 165: Enclosed single-line 'if' condition in curly braces
  void _deleteExpense(int index) {
    if (index >= 0 && index < _expenses.length) {
      setState(() {
        _expenses.removeAt(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportData,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Expense Title'),
            ),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addExpense,
              child: const Text('Add Expense'),
            ),
            const SizedBox(height: 20),
            Text(
              'Total: \$${_calculateTotal().toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _expenses.length,
                itemBuilder: (context, index) {
                  final item = _expenses[index];
                  return ListTile(
                    title: Text(item['title']),
                    trailing: Text('\$${item['amount']}'),
                    onLongPress: () => _deleteExpense(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
