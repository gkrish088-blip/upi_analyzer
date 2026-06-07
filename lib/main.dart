import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:upi_analyzer/ask_ai_screen.dart';
import 'package:upi_analyzer/home_screen.dart';
import 'package:upi_analyzer/insights_screen.dart';
import 'package:upi_analyzer/transactions_screen.dart';
import 'bloc/transaction_bloc.dart';
import 'bloc/transaction_event.dart';
import 'bloc/chat_bloc.dart';
import 'repository/transaction_repository.dart';

void main() {
  runApp(const UpiAnalyserApp());
}

class UpiAnalyserApp extends StatelessWidget {
  const UpiAnalyserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UPI Analyser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7B61FF),
          surface: Color(0xFF1A1A1A),
        ),
        useMaterial3: true,
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TransactionBloc>(
            create: (context) => TransactionBloc(
              repository: TransactionRepository(),
            )..add(TransactionLoadRequested(
                year: DateTime.now().year,
                month: DateTime.now().month,
              )),
          ),
          BlocProvider<ChatBloc>(
            create: (context) => ChatBloc(),
          ),
        ],
        child: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    HomeScreen(),
    TransactionsScreen(),
    InsightsScreen(),
    AskAIScreen(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: const Color(0xFF1A1A1A),
        indicatorColor: const Color(0xFF7B61FF),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Insights',
            ),
            NavigationDestination(
              icon: Icon(Icons.smart_toy_outlined),
              selectedIcon: Icon(Icons.smart_toy),
              label: 'Ask AI',
            ),
        ],
      ),
    );
  }
}
