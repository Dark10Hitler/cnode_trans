import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../models/trip.dart';
import '../../state/trip_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/labeled_help_field.dart';
import 'trip_report_screen.dart';

/// Этап 2 — "в дороге". Два действия по 10 секунд на остановках/АЗС:
/// "+ Заправка" и "Смена статуса" (плечо гружёный/порожний), плюс
/// "+ Расход" для прочих трат (платные дороги, стоянка, ремонт).
class TripActiveScreen extends StatelessWidget {
  const TripActiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tripState = context.watch<TripState>();
    final trip = tripState.openTrip;
    if (trip == null) {
      return const Scaffold(body: Center(child: Text('Рейс не найден')));
    }

    return Scaffold(
      appBar: AppBar(title: Text(trip.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Старт: ${DateFormat('dd.MM.yyyy HH:mm').format(trip.startedAt)}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Одометр на старте: ${trip.startOdometerKm.toStringAsFixed(0)} км · '
                    'бак: ${trip.startFuelLiters.toStringAsFixed(0)} л'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showRefuelDialog(context),
                  icon: const Icon(Icons.local_gas_station_outlined),
                  label: const Text('+ Заправка'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showLegDialog(context),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Смена статуса'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showExpenseDialog(context),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('+ Расход (дорога, стоянка, ремонт…)'),
            ),
          ),
          const SizedBox(height: 20),
          if (tripState.openRefuels.isNotEmpty) ...[
            const Text('Заправки', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...tripState.openRefuels.map((r) => _EventTile(
                  icon: Icons.local_gas_station_outlined,
                  title: '${r.liters.toStringAsFixed(0)} л · ${r.amount.toStringAsFixed(0)} ${trip.currency}',
                  subtitle: DateFormat('dd.MM HH:mm').format(r.createdAt),
                  hasPhoto: r.photoPath != null,
                )),
            const SizedBox(height: 16),
          ],
          if (tripState.openLegs.isNotEmpty) ...[
            const Text('Плечи (смены статуса)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...tripState.openLegs.map((l) => _EventTile(
                  icon: Icons.swap_horiz,
                  title: '${l.odometerKm.toStringAsFixed(0)} км → ${l.cargoState.label}'
                      '${l.cargoState == CargoState.loaded && l.cargoWeightTons != null ? ' · ${l.cargoWeightTons!.toStringAsFixed(1)} т' : ''}'
                      '${l.endpointType != null ? ' · ${l.endpointType!.label}${l.endpointDistanceKm != null ? " (~${l.endpointDistanceKm!.toStringAsFixed(0)} км)" : ""}' : ''}',
                  subtitle: DateFormat('dd.MM HH:mm').format(l.createdAt),
                )),
            const SizedBox(height: 16),
          ],
          if (tripState.openExpenses.isNotEmpty) ...[
            const Text('Прочие расходы', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...tripState.openExpenses.map((e) => _EventTile(
                  icon: Icons.receipt_long_outlined,
                  title: '${e.label} · ${e.amount.toStringAsFixed(0)} ${trip.currency}',
                  subtitle: DateFormat('dd.MM HH:mm').format(e.createdAt),
                )),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _showFinishDialog(context, trip),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Завершить рейс'),
          ),
        ),
      ),
    );
  }

  Future<void> _showRefuelDialog(BuildContext context) async {
    final litersCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String? photoPath;
    final tripId = context.read<TripState>().openTrip!.id!;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Заправка', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              LabeledHelpField(
                label: 'Литры',
                help: 'Сколько литров залил на этой заправке — бери число по чеку с колонки.',
                child: TextField(controller: litersCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ),
              LabeledHelpField(
                label: 'Сумма',
                help: 'Сколько заплатил за эту заправку — тоже по чеку.',
                child: TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final path = await _capturePhoto();
                  if (path != null) setSheetState(() => photoPath = path);
                },
                icon: Icon(photoPath != null ? Icons.check_circle : Icons.camera_alt_outlined),
                label: Text(photoPath != null ? 'Фото чека добавлено' : 'Фото чека (опционально)'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final liters = double.tryParse(litersCtrl.text.replaceAll(',', '.'));
                    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                    if (liters == null || amount == null) return;
                    context.read<TripState>().addRefuel(TripRefuel(
                          tripId: tripId,
                          liters: liters,
                          amount: amount,
                          photoPath: photoPath,
                          createdAt: DateTime.now(),
                        ));
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Сохранить заправку'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _capturePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
      if (photo == null) return null;
      final appDir = await getApplicationDocumentsDirectory();
      final receiptsDir = Directory(p.join(appDir.path, 'cargonode_receipts'));
      if (!await receiptsDir.exists()) await receiptsDir.create(recursive: true);
      final savedPath = p.join(receiptsDir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(photo.path).copy(savedPath);
      return savedPath;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showLegDialog(BuildContext context) async {
    final odometerCtrl = TextEditingController();
    final massCtrl = TextEditingController();
    final endpointDistanceCtrl = TextEditingController();
    CargoState state = CargoState.empty;
    TripEndpointType? endpointType;
    String? error;
    final tripId = context.read<TripState>().openTrip!.id!;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Смена статуса (плечо)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                LabeledHelpField(
                  label: 'Одометр сейчас, км',
                  help: 'Показание одометра в момент погрузки/разгрузки — например, выгрузился '
                      'в пункте Б или загрузился обратно в пункте В.',
                  child: TextField(controller: odometerCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                ),
                LabeledHelpField(
                  label: 'Что начинается с этой точки',
                  help: 'Выбери, что начинается дальше от этого километра: пробег "с грузом" или '
                      '"порожняком". Приложение само разобьёт весь путь на участки по всем твоим '
                      'отметкам и посчитает расход для каждого отдельно (с грузом расход выше).',
                  child: SegmentedButton<CargoState>(
                    segments: const [
                      ButtonSegment(value: CargoState.loaded, label: Text('С грузом')),
                      ButtonSegment(value: CargoState.empty, label: Text('Порожняком')),
                    ],
                    selected: {state},
                    onSelectionChanged: (v) => setSheetState(() {
                      state = v.first;
                      error = null;
                    }),
                  ),
                ),
                if (state == CargoState.loaded)
                  LabeledHelpField(
                    label: 'Масса груза, т',
                    help: 'Обязательно для гружёного участка: расход топлива растёт с массой '
                        'груза (модель Fuel = F₀ + k×масса). Без массы этот участок нельзя '
                        'посчитать точнее, чем "как порожний".',
                    child: TextField(controller: massCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  ),
                if (state == CargoState.empty) ...[
                  LabeledHelpField(
                    label: 'Конечный пункт рейса (если это возврат после разгрузки)',
                    help: 'Если этот порожний участок начинается сразу после разгрузки — укажи, '
                        'куда едешь дальше. Если это просто промежуточная отметка не после '
                        'разгрузки — оставь "не указано".',
                    child: DropdownButtonFormField<TripEndpointType?>(
                      initialValue: endpointType,
                      dropdownColor: AppColors.surfaceHigh,
                      hint: const Text('Не указано'),
                      items: [
                        const DropdownMenuItem<TripEndpointType?>(value: null, child: Text('Не указано')),
                        ...TripEndpointType.values
                            .map((t) => DropdownMenuItem<TripEndpointType?>(value: t, child: Text(t.label))),
                      ],
                      onChanged: (v) => setSheetState(() => endpointType = v),
                    ),
                  ),
                  if (endpointType != null)
                    LabeledHelpField(
                      label: 'Расстояние порожнего возврата, км (если знаешь)',
                      help: 'Например, "Разгрузка → База = 150 км". Если пока не знаешь точно — '
                          'оставь пустым: как только внесёшь одометр на финише или следующее '
                          'плечо, расстояние посчитается автоматически по факту.',
                      child: TextField(
                        controller: endpointDistanceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final odometer = double.tryParse(odometerCtrl.text.replaceAll(',', '.'));
                      if (odometer == null) {
                        setSheetState(() => error = 'Укажи одометр');
                        return;
                      }
                      double? mass;
                      if (state == CargoState.loaded) {
                        mass = double.tryParse(massCtrl.text.replaceAll(',', '.'));
                        if (mass == null || mass <= 0) {
                          setSheetState(() => error = 'Укажи массу груза для гружёного участка');
                          return;
                        }
                      }
                      final endpointDistance =
                          endpointDistanceCtrl.text.trim().isEmpty ? null : double.tryParse(endpointDistanceCtrl.text.replaceAll(',', '.'));
                      context.read<TripState>().addLeg(TripLeg(
                            tripId: tripId,
                            odometerKm: odometer,
                            cargoState: state,
                            cargoWeightTons: mass,
                            endpointType: endpointType,
                            endpointDistanceKm: endpointDistance,
                            createdAt: DateTime.now(),
                          ));
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showExpenseDialog(BuildContext context) async {
    final labelCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final tripId = context.read<TripState>().openTrip!.id!;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Прочий расход', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            LabeledHelpField(
              label: 'Что за расход',
              help: 'Например: "Платные дороги", "Стоянка", "Мойка", "Мелкий ремонт", '
                  '"Доливка масла" — любая прямая трата в этом рейсе, кроме топлива.',
              child: TextField(controller: labelCtrl),
            ),
            LabeledHelpField(
              label: 'Сумма',
              help: 'Сколько потратил — по чеку или квитанции.',
              child: TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                  if (amount == null || labelCtrl.text.trim().isEmpty) return;
                  context.read<TripState>().addExpense(TripExpense(
                        tripId: tripId,
                        label: labelCtrl.text.trim(),
                        amount: amount,
                        createdAt: DateTime.now(),
                      ));
                  Navigator.of(sheetContext).pop();
                },
                child: const Text('Сохранить расход'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFinishDialog(BuildContext context, TripRecord trip) async {
    final odometerCtrl = TextEditingController();
    final fuelCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Финиш рейса', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            LabeledHelpField(
              label: 'Одометр на финише, км',
              help: 'Показание одометра по прибытии в гараж/на базу. Разница со стартовым '
                  'значением — это общий пробег рейса.',
              child: TextField(controller: odometerCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ),
            LabeledHelpField(
              label: 'Остаток топлива на финише, л',
              help: 'Сколько осталось в баке по возвращении. Вместе со стартовым остатком и '
                  'заправками в пути по этому числу точно посчитается реальный расход.',
              child: TextField(controller: fuelCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final odometer = double.tryParse(odometerCtrl.text.replaceAll(',', '.'));
                  final fuel = double.tryParse(fuelCtrl.text.replaceAll(',', '.'));
                  if (odometer == null || fuel == null) return;
                  Navigator.of(sheetContext).pop(true);
                  context.read<TripState>().finishTrip(finishOdometerKm: odometer, finishFuelLiters: fuel);
                },
                child: const Text('Завершить и сформировать отчёт'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const TripReportScreen()));
    }
  }
}

class _EventTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool hasPhoto;

  const _EventTile({required this.icon, required this.title, required this.subtitle, this.hasPhoto = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          if (hasPhoto) const Icon(Icons.photo_outlined, size: 16, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
