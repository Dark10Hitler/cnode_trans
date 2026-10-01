import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/combination.dart';
import '../../models/power_unit.dart';
import '../../models/trailer.dart';
import '../../state/app_state.dart';
import '../../state/hos_section_widget.dart'; // Подключаем наш новый виджет РТиО
import '../../theme/app_theme.dart';
import 'combination_form_screen.dart';
import 'power_unit_form_screen.dart';
import 'trailer_form_screen.dart';

class VehicleHomeScreen extends StatelessWidget {
  const VehicleHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // Увеличили количество вкладок до 4
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Транспорт'),
          bottom: const TabBar(
            isScrollable: true, // Позволяет вкладкам скроллиться на узких экранах
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'РТиО'), // Новая вкладка Тахографа
              Tab(text: 'Тягачи/машины'),
              Tab(text: 'Прицепы'),
              Tab(text: 'Связки'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Баннер активного ТС закреплен сверху и виден на всех вкладках
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: _ActiveRigBanner(),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _HosTab(), // Наша новая вкладка со справочником и таймером
                  const _PowerUnitsTab(),
                  const _TrailersTab(),
                  const _CombinationsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Новая вкладка: Режим труда и отдыха (Тахограф)
class _HosTab extends StatelessWidget {
  const _HosTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      children: const [
        // Тот самый виджет, который мы создали на предыдущем шаге
        HosSectionWidget(),
      ],
    );
  }
}

class _ActiveRigBanner extends StatelessWidget {
  const _ActiveRigBanner();

  @override
  Widget build(BuildContext context) {
    final rig = context.watch<AppState>().activeRig;
    if (rig == null) {
      return const Text(
        'Активный борт не выбран — отметь «Активный» у тягача/машины или свяжи с прицепом ниже.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Активный борт: ${rig.label}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Вкладка 2: Тягачи и Машины
class _PowerUnitsTab extends StatelessWidget {
  const _PowerUnitsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: appState.powerUnits.isEmpty
          ? const _EmptyHint(text: 'Нет ни одного тягача/грузовика/машины. Добавь первый.')
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        itemCount: appState.powerUnits.length,
        itemBuilder: (context, index) {
          final unit = appState.powerUnits[index];
          return Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Text(unit.category.icon, style: const TextStyle(fontSize: 26)),
              title: Text(unit.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${unit.category.label} · ${unit.height.toStringAsFixed(2)}/${unit.width.toStringAsFixed(2)}/'
                    '${unit.length.toStringAsFixed(2)} м'
                    '${unit.hazmat ? ' · ⚠️ ADR' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unit.isActive)
                    const Icon(Icons.check_circle, color: AppColors.primary)
                  else
                    TextButton(
                      onPressed: () => context.read<AppState>().setActivePowerUnit(unit.id!),
                      child: const Text('Выбрать'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Редактировать',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PowerUnitFormScreen(unit: unit)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                    tooltip: 'Удалить',
                    onPressed: () => _confirmDeletePowerUnit(context, unit),
                  ),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PowerUnitFormScreen(unit: unit)),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'power_units_fab',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PowerUnitFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
    );
  }

  void _confirmDeletePowerUnit(BuildContext context, PowerUnit unit) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить ТС?'),
        content: Text('«${unit.displayName}» и связанные с ним данные будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              await context.read<AppState>().deletePowerUnit(unit.id!);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// Вкладка 3: Прицепы
class _TrailersTab extends StatelessWidget {
  const _TrailersTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: appState.trailers.isEmpty
          ? const _EmptyHint(text: 'Нет ни одного прицепа/полуприцепа. Добавь первый.')
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        itemCount: appState.trailers.length,
        itemBuilder: (context, index) {
          final trailer = appState.trailers[index];
          return Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(
                trailer.kind == TrailerKind.semiTrailer ? Icons.rv_hookup : Icons.airline_seat_legroom_reduced,
                color: AppColors.primary,
              ),
              title: Text(trailer.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${trailer.kind.label} · ${trailer.length.toStringAsFixed(2)} м'
                    '${trailer.axleCount != null ? ' · ${trailer.axleCount} ос.' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Редактировать',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TrailerFormScreen(trailer: trailer)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                    tooltip: 'Удалить',
                    onPressed: () => _confirmDeleteTrailer(context, trailer),
                  ),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TrailerFormScreen(trailer: trailer)),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'trailers_fab',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TrailerFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
    );
  }

  void _confirmDeleteTrailer(BuildContext context, Trailer trailer) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить прицеп?'),
        content: Text('«${trailer.displayName}» и все связанные с ним данные будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              await context.read<AppState>().deleteTrailer(trailer.id!);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// Вкладка 4: Связки (Тягач + Прицеп)
class _CombinationsTab extends StatelessWidget {
  const _CombinationsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canCreate = appState.powerUnits.any((u) => u.category.canCoupleSemiTrailer || u.category.canTowLightTrailer) &&
        appState.trailers.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: appState.combinations.isEmpty
          ? _EmptyHint(
        text: canCreate
            ? 'Связок пока нет. Свяжи тягач/машину с прицепом.'
            : 'Чтобы создать связку, нужен хотя бы один тягач (или легковая) и один совместимый прицеп.',
      )
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        itemCount: appState.combinations.length,
        itemBuilder: (context, index) {
          final combo = appState.combinations[index];
          final unit = appState.powerUnits.where((u) => u.id == combo.powerUnitId).firstOrNull;
          final trailer = appState.trailers.where((t) => t.id == combo.trailerId).firstOrNull;
          final label = combo.label?.isNotEmpty == true
              ? combo.label!
              : '${unit?.displayName ?? '—'} + ${trailer?.displayName ?? '—'}';
          return Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.link, color: AppColors.primary),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: unit != null && trailer != null
                  ? Text('${unit.category.label} + ${trailer.kind.label}')
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (combo.isActive)
                    const Icon(Icons.check_circle, color: AppColors.primary)
                  else
                    TextButton(
                      onPressed: () => context.read<AppState>().setActiveCombination(combo.id!),
                      child: const Text('Выбрать'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Редактировать',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CombinationFormScreen(combo: combo)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_off, size: 20, color: AppColors.danger),
                    tooltip: 'Расцепить',
                    onPressed: () => _confirmDeleteCombination(context, combo, label),
                  ),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CombinationFormScreen(combo: combo)),
              ),
            ),
          );
        },
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
        heroTag: 'combinations_fab',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CombinationFormScreen()),
        ),
        icon: const Icon(Icons.add_link),
        label: const Text('Связать'),
      )
          : null,
    );
  }

  void _confirmDeleteCombination(BuildContext context, VehicleCombination combo, String label) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Расцепить связку?'),
        content: Text('Связка «$label» будет удалена. Сами ТС и прицеп останутся в базе.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              await context.read<AppState>().deleteCombination(combo.id!);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }
}