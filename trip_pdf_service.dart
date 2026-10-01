import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/trip.dart';
import 'trip_calculator.dart';

/// Генерация PDF-отчёта по рейсу прямо на устройстве (без интернета).
///
/// Важно: стандартные PDF-шрифты (Courier/Helvetica) НЕ содержат
/// кириллицу, поэтому шрифт встраивается из assets (RobotoMono —
/// полное покрытие кириллического блока, проверено). Вёрстка —
/// моноширинный текстовый блок, зеркалящий экран отчёта 1:1.
class TripPdfService {
  Future<pw.Font> _loadFont(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return pw.Font.ttf(data);
  }

  Future<File> buildReport({
    required TripRecord trip,
    required TripCalculationResult result,
    required List<TripRefuel> refuels,
    required List<TripExpense> expenses,
  }) async {
    final num0 = NumberFormat('#,##0', 'ru');
    final dec1 = NumberFormat('#,##0.0', 'ru');
    final dec2 = NumberFormat('#,##0.00', 'ru');
    final cur = trip.currency;
    final doc = pw.Document();

    final regular = await _loadFont('assets/fonts/RobotoMono-Regular.ttf');
    final bold = await _loadFont('assets/fonts/RobotoMono-Bold.ttf');

    pw.Widget line(String text, {bool bold_ = false}) {
      return pw.Text(text, style: pw.TextStyle(font: bold_ ? bold : regular, fontSize: 9));
    }

    final widgets = <pw.Widget>[];
    void ln(String text, {bool bold = false}) => widgets.add(line(text, bold_: bold));
    void gap([double h = 6]) => widgets.add(pw.SizedBox(height: h));
    void rule() => ln('-' * 58);

    // Моноширинный шрифт => выравнивание пробелами работает корректно.
    void kv(String label, String value, {bool bold = false}) {
      final pad = 38 - label.length;
      final spacer = pad > 1 ? ' ' * pad : '  ';
      ln('${bold ? '* ' : '. '}$label:$spacer$value', bold: bold);
    }

    ln('=' * 58, bold: true);
    ln('ОТЧЁТ ПО РЕЙСУ №${trip.id ?? '-'}', bold: true);
    ln(trip.label, bold: true);
    ln('=' * 58, bold: true);
    gap();

    ln('[ ДИСТАНЦИЯ И ПРОБЕГ ]', bold: true);
    kv('Начало рейса (одометр)', '${num0.format(trip.startOdometerKm)} км');
    kv('Конец рейса (одометр)', '${num0.format(trip.finishOdometerKm ?? trip.startOdometerKm)} км');
    rule();
    kv('ОБЩИЙ ПРОБЕГ (Total KM)', '${num0.format(result.totalDistanceKm)} км', bold: true);
    final loadedPct = result.totalDistanceKm > 0 ? result.loadedDistanceKm / result.totalDistanceKm * 100 : 0;
    final emptyPct = result.totalDistanceKm > 0 ? result.emptyDistanceKm / result.totalDistanceKm * 100 : 0;
    ln('   Пробег с грузом (Loaded):  ${num0.format(result.loadedDistanceKm)} км (${dec1.format(loadedPct)}%)');
    ln('   Пробег порожняком (Empty): ${num0.format(result.emptyDistanceKm)} км (${dec1.format(emptyPct)}%)');
    kv('   из них Deadhead', '${num0.format(result.deadheadDistanceKm)} км');
    gap();

    ln('[ ТОПЛИВНЫЙ БАЛАНС ]', bold: true);
    final refuelLiters = refuels.fold<double>(0, (s, r) => s + r.liters);
    kv('Остаток на старте', '${dec1.format(trip.startFuelLiters)} л');
    kv('Куплено по чекам (${refuels.length})', '${dec1.format(refuelLiters)} л (${num0.format(result.fuelCost)} $cur)');
    kv('Остаток на финише', '${dec1.format(trip.finishFuelLiters ?? 0)} л');
    rule();
    kv('ФАКТИЧЕСКИ СОЖЖЕНО', '${dec1.format(result.fuelBurnedLiters)} л', bold: true);
    kv('СРЕДНИЙ РАСХОД (факт)', '${dec1.format(result.avgConsumptionPer100km)} л/100км', bold: true);
    kv('Расчётный расход (модель)', '${dec1.format(result.calculatedFuelLiters)} л');
    kv('Отклонение факт/расчёт', '${result.fuelDeviationLiters >= 0 ? '+' : ''}${dec1.format(result.fuelDeviationLiters)} л');
    gap();

    ln('[ РАСХОД ПО ЗАГРУЗКЕ ]', bold: true);
    kv('Порожний расход', '${dec1.format(result.emptyConsumptionPer100km)} л/100км');
    kv('Расход с грузом', '${dec1.format(result.loadedConsumptionPer100km)} л/100км');
    kv('Увеличение расхода', '+${dec1.format(result.consumptionIncreasePer100km)} л/100км');
    kv('Увеличение в процентах', '+${dec1.format(result.consumptionIncreasePercent)} %');
    kv('Порожняком', '${num0.format(result.emptyDistanceKm)} км -> ${dec1.format(result.emptyFuelLiters)} л');
    kv('С грузом', '${num0.format(result.loadedDistanceKm)} км -> ${dec1.format(result.loadedFuelLiters)} л');

    if (result.segments.isNotEmpty) {
      gap();
      ln('[ МАРШРУТ И СТАТУСЫ ]', bold: true);
      for (final s in result.segments) {
        ln('${num0.format(s.startOdometerKm)} -> ${num0.format(s.endOdometerKm)} км (${num0.format(s.distanceKm)} км)');
        final tag = s.cargoState == CargoState.loaded
            ? '   Груз: ${dec1.format(s.cargoWeightTons)} т, ${dec1.format(s.consumptionPer100km)} л/100км'
            : '   Порожняком${s.endpointType != null ? ', возврат -> ${s.endpointType!.label}' : ''}';
        ln(tag);
      }
    }

    if (result.endpointType != null) {
      gap();
      ln('[ КОНЕЧНЫЙ ПУНКТ ]', bold: true);
      kv('Тип', result.endpointType!.label);
      kv('Порожний возврат', result.endpointDistanceKm != null ? '${num0.format(result.endpointDistanceKm)} км' : 'не указано');
    }

    gap();
    ln('[ ДОХОДЫ И СТАВКА ]', bold: true);
    kv('Фрахт / ставка за рейс', '${num0.format(trip.agreedRate)} $cur', bold: true);
    kv('Доход на 1 км (общий пробег)', '${dec2.format(result.incomePerKmTotal)} $cur/км');
    kv('Доход на 1 км (только с грузом)', '${dec2.format(result.incomePerKmLoaded)} $cur/км');

    gap();
    ln('[ ПРЯМЫЕ РАСХОДЫ В ПУТИ ]', bold: true);
    var idx = 1;
    ln('  ${idx++}. Топливо (по чекам): ${num0.format(result.fuelCost)} $cur');
    for (final e in expenses) {
      ln('  ${idx++}. ${e.label}: ${num0.format(e.amount)} $cur');
    }
    rule();
    kv('ИТОГО РАСХОДОВ В ДОРОГЕ', '${num0.format(result.directExpensesTotal)} $cur', bold: true);

    gap();
    ln('[ КОСВЕННЫЕ РАСХОДЫ И КОПИЛКИ ]', bold: true);
    kv('ЗП водителя', '${num0.format(result.driverPay)} $cur');
    kv('Суточные', '${num0.format(result.perDiemTotal)} $cur');
    kv('Амортизация', '${num0.format(result.depreciationTotal)} $cur');
    rule();
    kv('ИТОГО РАСПРЕДЕЛЕНИЕ', '${num0.format(result.indirectExpensesTotal)} $cur', bold: true);

    gap();
    ln('=' * 58, bold: true);
    ln('[ ФИНАНСОВЫЙ ИТОГ РЕЙСА ]', bold: true);
    kv('ОБЩИЕ РАСХОДЫ', '${num0.format(result.totalExpenses)} $cur', bold: true);
    kv('СЕБЕСТОИМОСТЬ 1 КМ', '${dec2.format(result.costPerKm)} $cur/км', bold: true);
    rule();
    ln('ЧИСТАЯ ПРИБЫЛЬ ВЛАДЕЛЬЦА: ${num0.format(result.netProfit)} $cur', bold: true);
    ln('РЕНТАБЕЛЬНОСТЬ (МАРЖА): ${dec1.format(result.marginPercent)} %', bold: true);
    ln('=' * 58, bold: true);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => widgets,
      ),
    );

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'cargonode_reports'));
    if (!await reportsDir.exists()) await reportsDir.create(recursive: true);
    final file = File(p.join(reportsDir.path, 'trip_${trip.id}_${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> share(File file) async {
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: p.basename(file.path));
  }
}
