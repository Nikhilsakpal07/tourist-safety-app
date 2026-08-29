import 'package:flutter/material.dart';
import 'services/dtn_database.dart';
import 'services/mesh_service.dart';
import 'services/map_service.dart';
import 'views/sos_view.dart';
import 'views/map_view.dart';

void main() async {
  // Ensure Flutter bindings are initialized before doing async work in main()
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize the Core Database
  final dbService = DtnDatabaseService();
  await dbService.initDatabase();

  // 2. Initialize the Services
  final meshService = MeshService(dbService);
  final mapService = MapService(dbService);

  runApp(TouristMeshApp(
    meshService: meshService,
    mapService: mapService,
  ));
}

class TouristMeshApp extends StatelessWidget {
  final MeshService meshService;
  final MapService mapService;

  const TouristMeshApp({
    Key? key,
    required this.meshService,
    required this.mapService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tourist Mesh',
      theme: ThemeData(
        primarySwatch: Colors.red,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
      ),
      themeMode: ThemeMode.system,
      home: AppMainScaffold(
        meshService: meshService,
        mapService: mapService,
      ),
    );
  }
}

class AppMainScaffold extends StatefulWidget {
  final MeshService meshService;
  final MapService mapService;

  const AppMainScaffold({
    Key? key,
    required this.meshService,
    required this.mapService,
  }) : super(key: key);

  @override
  _AppMainScaffoldState createState() => _AppMainScaffoldState();
}

class _AppMainScaffoldState extends State<AppMainScaffold> {
  int _currentIndex = 0;

  late final List<Widget> _views;

  @override
  void initState() {
    super.initState();
    // Initialize our views and pass in the required services
    _views = [
      SosView(meshService: widget.meshService),
      HazardMapView(mapService: widget.mapService),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _views,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.emergency),
            label: 'SOS Mesh',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Hazard Map',
          ),
        ],
      ),
    );
  }
}
