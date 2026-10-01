import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/trip.dart';
import '../../services/trip_calculator.dart';
import '../../services/trip_pdf_service.dart';
import '../../state/trip_state.dart';
import '../../theme/app_theme.dart';

/// Этап 4 — бухгалтерский отчёт по рейсу. Печатается ИМЕННО как
/// структурированный финансовый отчёт (моноширинный текст с блоками
/// [ ЗАГОЛОВОК ]), а не как набор отдельных карточек — так его удобно
/// сверять с бумажным аналогом и читать целиком.
class TripReportScreen extends StatefulWidget {
  const TripReportScreen({super.key});

  @override
  State<TripReportScreen> createState() => _TripReportScreenState();
}

class _TripReportScreenState extends State<TripReportScreen> {
  bool _exporting = false;
  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5, color: AppColors.textPrimary);
  static final _num = NumberFormat('#,##0', 'ru');
  static final _dec = NumberFormat('#,##0.0', 'ru');
  static final _dec2 = NumberFormat('#,##0.00', 'ru');

  Future<void> _exportPdf(TripState tripState) async {
    setState(() => _exporting = true);
    try {
      final result = TripCalculator.calculate(
        trip: tripState.openTrip!,
        refuels: tripState.openRefuels,
        legs: tripState.openLegs,
        expenses: tripState.openExpenses,
      );
      final file = await TripPdfService().buildReport(
        trip: tripState.openTrip!,
        result: result,
        refuels: tripState.openRefuels,
        expenses: tripState.openExpenses,
      );
      await TripPdfService().share(file);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripState = context.watch<TripState>();
    final trip = tripState.openTrip;
    if (trip == null) {
      return const Scaffold(body: Center(child: Text('Рейс не найден')));
    }

    final result = TripCalculator.calculate(
      trip: trip,
      refuels: tripState.openRefuels,
      legs: tripState.openLegs,
      expenses: tripState.openExpenses,
    );
    final cur = trip.currency;

    final lines = <String>[];
    void ln([String s = '']) => lines.add(s);
    void rule([String ch = '─']) => ln(ch * 46);
    void kv(String label, String value, {bool bold = false}) {
      final pad = 34 - label.length;
      final gap = pad > 1 ? ' ' * pad : '  ';
      ln('${bold ? '★ ' : '• '}$label:$gap$value');
    }

    ln('=' * 46);
    ln('ОТЧЁТ ПО РЕЙСУ №${trip.id ?? '—'}');
    ln(trip.label);
    ln('=' * 46);
    ln();
    ln('[ ДИСТАНЦИЯ И ПРОБЕГ ]');
    kv('Начало рейса (одометр)', '${_num.format(trip.startOdometerKm)} км');
    kv('Конец рейса (одометр)', '${_num.format(trip.finishOdometerKm ?? trip.startOdometerKm)} км');
    rule();
    kv('ОБЩИЙ ПРОБЕГ (Total KM)', '${_num.format(result.totalDistanceKm)} км', bold: true);
    final loadedPct = result.totalDistanceKm > 0 ? result.loadedDistanceKm / result.totalDistanceKm * 100 : 0;
    final emptyPct = result.totalDistanceKm > 0 ? result.emptyDistanceKm / result.totalDistanceKm * 100 : 0;
    ln('  ├─ Пробег с грузом (Loaded, оплачиваемый): ${_num.format(result.loadedDistanceKm)} км (${_dec.format(loadedPct)}%)');
    ln('  └─ Пробег порожняком (Empty, холостой):    ${_num.format(result.emptyDistanceKm)} км (${_dec.format(emptyPct)}%)');
    kv('  из них Deadhead (порожние перегоны)', '${_num.format(result.deadheadDistanceKm)} км');
    ln();
    ln('[ ТОПЛИВНЫЙ БАЛАНС ]');
    final refuelLiters = tripState.openRefuels.fold<double>(0, (s, r) => s + r.liters);
    kv('Остаток на старте', '${_dec.format(trip.startFuelLiters)} л');
    kv('Куплено по чекам (${tripState.openRefuels.length})', '${_dec.format(refuelLiters)} л (${_num.format(result.fuelCost)} $cur)');
    kv('Остаток на финише', '${_dec.format(trip.finishFuelLiters ?? 0)} л');
    rule();
    kv('ФАКТИЧЕСКИ СОЖЖЕНО', '${_dec.format(result.fuelBurnedLiters)} л', bold: true);
    kv('СРЕДНИЙ РАСХОД (факт)', '${_dec.format(result.avgConsumptionPer100km)} л/100км', bold: true);
    kv('Расчётный расход (по модели)', '${_dec.format(result.calculatedFuelLiters)} л');
    kv('Отклонение факт/расчёт', '${result.fuelDeviationLiters >= 0 ? '+' : ''}${_dec.format(result.fuelDeviationLiters)} л');
    ln();
    ln('[ РАСХОД ПО ЗАГРУЗКЕ ]');
    kv('Порожний расход', '${_dec.format(result.emptyConsumptionPer100km)} л/100км');
    kv('Расход с грузом', '${_dec.format(result.loadedConsumptionPer100km)} л/100км');
    kv('Увеличение расхода', '+${_dec.format(result.consumptionIncreasePer100km)} л/100км');
    kv('Увеличение в процентах', '+${_dec.format(result.consumptionIncreasePercent)} %');
    kv('Порожняком', '${_num.format(result.emptyDistanceKm)} км → ${_dec.format(result.emptyFuelLiters)} л');
    kv('С грузом', '${_num.format(result.loadedDistanceKm)} км → ${_dec.format(result.loadedFuelLiters)} л');
    if (result.segments.isNotEmpty) {
      ln();
      ln('[ МАРШРУТ И СТАТУСЫ ]');
      for (final s in result.segments) {
        ln('• ${_num.format(s.startOdometerKm)} → ${_num.format(s.endOdometerKm)} км  (${_num.format(s.distanceKm)} км)');
        final tag = s.cargoState == CargoState.loaded
            ? 'Груз: ${_dec.format(s.cargoWeightTons)} т · ${_dec.format(s.consumptionPer100km)} л/100км'
            : 'Порожняком${s.endpointType != null ? ' · возврат → ${s.endpointType!.label}' : ''}';
        ln('  └─ $tag');
      }
    }
    if (result.endpointType != null) {
      ln();
      ln('[ КОНЕЧНЫЙ ПУНКТ ]');
      kv('Тип', result.endpointType!.label);
      kv('Порожний возврат', result.endpointDistanceKm != null ? '${_num.format(result.endpointDistanceKm)} км' : 'не указано');
    }
    ln();
    ln('[ ДОХОДЫ И СТАВКА ]');
    kv('Фрахт / ставка за рейс', '${_num.format(trip.agreedRate)} $cur', bold: true);
    kv('Доход на 1 км (общий пробег)', '${_dec2.format(result.incomePerKmTotal)} $cur/км');
    kv('Доход на 1 км (только с грузом)', '${_dec2.format(result.incomePerKmLoaded)} $cur/км');
    ln();
    ln('[ ПРЯМЫЕ РАСХОДЫ В ПУТИ ]');
    var idx = 1;
    ln('  ${idx++}. Топливо (по чекам): ${_num.format(result.fuelCost)} $cur');
    for (final e in tripState.openExpenses) {
      ln('  ${idx++}. ${e.label}: ${_num.format(e.amount)} $cur');
    }
    rule();
    kv('ИТОГО РАСХОДОВ В ДОРОГЕ', '${_num.format(result.directExpensesTotal)} $cur', bold: true);
    ln();
    ln('[ КОСВЕННЫЕ РАСХОДЫ И КОПИЛКИ ]');
    kv('ЗП водителя', '${_num.format(result.driverPay)} $cur');
    kv('Суточные', '${_num.format(result.perDiemTotal)} $cur');
    kv('Амортизация', '${_num.format(result.depreciationTotal)} $cur');
    rule();
    kv('ИТОГО РАСПРЕДЕЛЕНИЕ', '${_num.format(result.indirectExpensesTotal)} $cur', bold: true);
    ln('=' * 46);
    ln('[ ФИНАНСОВЫЙ ИТОГ РЕЙСА ]');
    kv('ОБЩИЕ РАСХОДЫ', '${_num.format(result.totalExpenses)} $cur', bold: true);
    kv('СЕБЕСТОИМОСТЬ 1 КМ', '${_dec2.format(result.costPerKm)} $cur/км', bold: true);
    rule();
    ln('💰 ЧИСТАЯ ПРИБЫЛЬ ВЛАДЕЛЬЦА: ${_num.format(result.netProfit)} $cur');
    ln('📈 РЕНТАБЕЛЬНОСТЬ (МАРЖА): ${_dec.format(result.marginPercent)} %');
    ln('=' * 46);

    return Scaffold(
      appBar: AppBar(title: Text('Отчёт: ${trip.label}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: SelectableText(lines.join('\n'), style: _mono),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _exporting ? null : () => _exportPdf(tripState),
            icon: _exporting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_exporting ? 'Готовим PDF…' : 'Скачать / поделиться PDF'),
          ),
        ),
      ),
    );
  }
}
