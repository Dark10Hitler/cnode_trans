import 'package:flutter/material.dart';

import '../services/offline_assets_service.dart';
import 'assistant/assistant_screen.dart';
import 'documents/documents_screen.dart';
import 'maps/maps_screen.dart';
import 'offline_maps/offline_maps_screen.dart';
import 'trips/trips_list_screen.dart';
import 'vehicle/vehicle_home_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Флаг: был ли хоть раз открыт раздел с ИИ-помощником
  bool _wasAssistantOpened = false;

  @override
  void initState() {
    super.initState();
    // Распаковываем карты и heavy-ресурсы фоном ПОСЛЕ того, как UI отрисовался
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initOfflineAssets();
    });
  }

  Future<void> _initOfflineAssets() async {
    final offlineFiles = await OfflineAssetsService.initAll();
    debugPrint('[HomeShell] Фоново загружены офлайн-ресурсы: $offlineFiles');
  }

  void _openOfflineMaps() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OfflineMapsScreen(),
      ),
    );
  }

  void _onTabTapped(int i) {
    setState(() {
      _index = i;
      // Включаем загрузку Помощника только тогда, когда пользователь реально кликнул на его вкладку
      if (i == 4 && !_wasAssistantOpened) {
        _wasAssistantOpened = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          // 0. Карта
          MapsScreen(onOpenOfflineMaps: _openOfflineMaps),

          // 1. Транспорт
          const VehicleHomeScreen(),

          // 2. Документы
          const DocumentsScreen(),

          // 3. Расчёты
          const TripsListScreen(),

          // 4. Помощник (монтируется в дерево ТОЛЬКО после первого клика на вкладку)
          _wasAssistantOpened
              ? const AssistantScreen()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index > 4 ? 0 : _index,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Карта',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping_outlined),
            activeIcon: Icon(Icons.local_shipping),
            label: 'Транспорт',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined),
            activeIcon: Icon(Icons.description),
            label: 'Документы',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calculate_outlined),
            activeIcon: Icon(Icons.calculate),
            label: 'Расчёты',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy_outlined),
            activeIcon: Icon(Icons.smart_toy),
            label: 'Помощник',
          ),
        ],
      ),
    );
  }
}