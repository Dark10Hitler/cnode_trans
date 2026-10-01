import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/combination.dart';
import '../../models/power_unit.dart';
import '../../models/trailer.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Создание связки: выбираешь тягач/машину + совместимый прицеп.
class CombinationFormScreen extends StatefulWidget {
  final VehicleCombination? combo;
  const CombinationFormScreen({super.key, this.combo});

  @override
  State<CombinationFormScreen> createState() => _CombinationFormScreenState();
}

class _CombinationFormScreenState extends State<CombinationFormScreen> {
  int? _unitId;
  int? _trailerId;
  final _labelCtrl = TextEditingController();
  final _grossOverrideCtrl = TextEditingController();
  final _axleOverrideCtrl = TextEditingController();
  bool _initialized = false;

  bool get _isEditing => widget.combo != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final combo = widget.combo;
    if (combo == null) return;

    _unitId = combo.powerUnitId;
    _trailerId = combo.trailerId;
    _labelCtrl.text = combo.label ?? '';
    _grossOverrideCtrl.text = combo.combinedGrossWeightOverride?.toString() ?? '';
    _axleOverrideCtrl.text = combo.combinedAxleLoadOverride?.toString() ?? '';
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _grossOverrideCtrl.dispose();
    _axleOverrideCtrl.dispose();
    super.dispose();
  }

  List<Trailer> _compatibleTrailers(List<Trailer> all, PowerUnit unit) {
    if (unit.category.canCoupleSemiTrailer) {
      return all.where((t) => t.kind == TrailerKind.semiTrailer).toList();
    }
    if (unit.category.canTowLightTrailer) {
      return all.where((t) => t.kind == TrailerKind.lightTrailer).toList();
    }
    return const [];
  }

  void _save() async {
    if (_unitId == null || _trailerId == null) return;
    final combo = VehicleCombination(
      id: widget.combo?.id,
      powerUnitId: _unitId!,
      trailerId: _trailerId!,
      label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
      combinedGrossWeightOverride:
      _grossOverrideCtrl.text.trim().isEmpty ? null : double.tryParse(_grossOverrideCtrl.text.replaceAll(',', '.')),
      combinedAxleLoadOverride:
      _axleOverrideCtrl.text.trim().isEmpty ? null : double.tryParse(_axleOverrideCtrl.text.replaceAll(',', '.')),
      isActive: widget.combo?.isActive ?? false,
      createdAt: widget.combo?.createdAt ?? DateTime.now(),
    );
    final appState = context.read<AppState>();
    if (_isEditing) {
      await appState.updateCombination(combo);
    } else {
      await appState.addCombination(combo);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final eligibleUnits = appState.powerUnits
        .where((u) => u.category.canCoupleSemiTrailer || u.category.canTowLightTrailer)
        .toList();

    // Проверяем, существует ли выбранный _unitId в актуальном списке
    final selectedUnit = eligibleUnits.where((u) => u.id == _unitId).firstOrNull;
    final activeUnitId = selectedUnit?.id;

    final trailers = selectedUnit != null ? _compatibleTrailers(appState.trailers, selectedUnit) : const <Trailer>[];

    // Проверяем, существует ли выбранный _trailerId в списке совместимых
    final selectedTrailer = trailers.where((t) => t.id == _trailerId).firstOrNull;
    final activeTrailerId = selectedTrailer?.id;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать связку' : 'Новая связка')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Тягач / машина', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: activeUnitId,
            dropdownColor: AppColors.surfaceHigh,
            hint: const Text('Выбери тягач или легковую'),
            items: eligibleUnits
                .map((u) => DropdownMenuItem<int>(
              value: u.id,
              child: Text('${u.category.icon} ${u.displayName}'),
            ))
                .toList(),
            onChanged: (v) => setState(() {
              _unitId = v;
              _trailerId = null;
            }),
          ),
          const SizedBox(height: 20),
          const Text('Прицеп / полуприцеп', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: activeTrailerId,
            dropdownColor: AppColors.surfaceHigh,
            hint: Text(activeUnitId == null ? 'Сначала выбери тягач/машину' : 'Выбери совместимый прицеп'),
            items: trailers
                .map((t) => DropdownMenuItem<int>(
              value: t.id,
              child: Text(t.displayName),
            ))
                .toList(),
            onChanged: activeUnitId == null ? null : (v) => setState(() => _trailerId = v),
          ),
          if (activeUnitId != null && trailers.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Нет совместимого прицепа для этого типа ТС — добавь его на вкладке «Прицепы».',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Название связки (необязательно)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(controller: _labelCtrl, decoration: const InputDecoration(hintText: 'Напр. «Рейс на Констанцу»')),
          const SizedBox(height: 20),
          const Text(
            'Итоговая масса и осевая нагрузка (необязательно)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Если не заполнить — посчитаем приближённо из данных тягача и прицепа. '
                'Если знаешь точное разрешённое ОГМ связки — впиши его сюда.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _grossOverrideCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'ОГМ связки, т'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _axleOverrideCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Осевая нагрузка, т'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (activeUnitId != null && activeTrailerId != null) ? _save : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_isEditing ? 'Сохранить изменения' : 'Связать'),
            ),
          ),
        ],
      ),
    );
  }
}