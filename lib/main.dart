import 'package:flutter/material.dart';
import 'package:posaic_app/views/map_view.dart';
import 'package:posaic_app/views/permit_qr_view.dart';
import 'package:posaic_app/views/sos_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PosaicApp());
}

class PosaicApp extends StatelessWidget {
  const PosaicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POSAIC Tourist Safety',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _views = const [
    MapView(),
    PermitQrView(),
    SosView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _views,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Corridor',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'Permit Pass',
          ),
          NavigationDestination(
            icon: Icon(Icons.emergency_outlined),
            selectedIcon: Icon(Icons.emergency),
            label: 'Mesh SOS',
          ),
        ],
      ),
    );
  }
}