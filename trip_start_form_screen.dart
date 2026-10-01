import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/trip.dart';
import '../../state/trip_state.dart';
import '../../widgets/labeled_help_field.dart';
import 'trip_active_screen.dart';

/// Этап 1 — старт рейса. Заполняется за минуту перед выездом.
/// Под каждым полем — флажок с полной инструкцией (LabeledHelpField).
class TripStartFormScreen extends StatefulWidget {
  const TripStartFormScreen({super.key});

  @override
  State<TripStartFormScreen> createState() => _TripStartFormScreenState();
}

class _TripStartFormScreenState extends State<TripStartFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  final _odometerCtrl = TextEditingController();
  final _fuelCtrl = TextEditingController();
  final _cargoWeightCtrl = TextEditingController(text: '0');
  final _rateCtrl = TextEditingController();
  final _driverPayCtrl = TextEditingController(text: '0');
  final _perDiemCtrl = TextEditingController(text: '0');
  final _perDiemDaysCtrl = TextEditingController(text: '1');
  final _depreciationCtrl = TextEditingController(text: '0');
  final _baseFuelCtrl = TextEditingController(text: '18');
  final _fuelPerTonCtrl = TextEditingController(text: '0.47');
  String _currency = 'MDL';

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: 'Рейс от ${DateFormat('dd.MM.yyyy').format(DateTime.now())}');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _odometerCtrl.dispose();
    _fuelCtrl.dispose();
    _cargoWeightCtrl.dispose();
    _rateCtrl.dispose();
    _driverPayCtrl.dispose();
    _perDiemCtrl.dispose();
    _perDiemDaysCtrl.dispose();
    _depreciationCtrl.dispose();
    _baseFuelCtrl.dispose();
    _fuelPerTonCtrl.dispose();
    super.dispose();
  }

  String? _req(String? v) {
    if (v == null || v.trim().isEmpty) return 'Укажи значение';
    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Введи число';
    return null;
  }

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    final trip = TripRecord(
      label: _labelCtrl.text.trim().isEmpty ? 'Рейс' : _labelCtrl.text.trim(),
      currency: _currency,
      status: TripStatus.inProgress,
      startOdometerKm: _num(_odometerCtrl),
      startFuelLiters: _num(_fuelCtrl),
      cargoWeightTons: _num(_cargoWeightCtrl),
      agreedRate: _num(_rateCtrl),
      driverPayPerKm: _num(_driverPayCtrl),
      perDiemPerDay: _num(_perDiemCtrl),
      perDiemDays: _num(_perDiemDaysCtrl),
      depreciationPerKm: _num(_depreciationCtrl),
      baseFuelConsumption: _num(_baseFuelCtrl) > 0 ? _num(_baseFuelCtrl) : 18,
      fuelConsumptionPerTon: _num(_fuelPerTonCtrl),
      startedAt: DateTime.now(),
    );
    await context.read<TripState>().startTrip(trip);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const TripActiveScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Старт рейса')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LabeledHelpField(
              label: 'Название рейса',
              help: 'Например, город назначения или номер рейса — поможет быстро найти нужный '
                  'отчёт в списке рейсов. Можно оставить как есть.',
              child: TextFormField(controller: _labelCtrl),
            ),
            LabeledHelpField(
              label: 'Валюта расчёта',
              help: 'Валюта, в которой будет считаться вся отчётность по этому рейсу — '
                  'ставка, расходы, прибыль.',
              child: DropdownButtonFormField<String>(
                initialValue: _currency,
                items: const ['MDL', 'RON', 'EUR', 'USD', 'RUB']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _currency = v ?? _currency),
              ),
            ),
            LabeledHelpField(
              label: 'Одометр на старте, км',
              help: 'Показание одометра (общего пробега) на приборной панели прямо перед выездом. '
                  'От этого числа отсчитывается весь пробег рейса — общий, с грузом и порожняком.',
              child: TextFormField(
                controller: _odometerCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _req,
              ),
            ),
            LabeledHelpField(
              label: 'Остаток топлива в баке на старте, л',
              help: 'Сколько топлива в баке прямо сейчас — на глаз по датчику или точно, если '
                  'помнишь остаток с прошлого финиша. Это нужно, чтобы в конце рейса точно '
                  'посчитать реальный расход топлива (а не только "по паспорту").',
              child: TextFormField(
                controller: _fuelCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _req,
              ),
            ),
            LabeledHelpField(
              label: 'Вес груза, т',
              help: 'Вес груза, если уже загружен сейчас. Укажи 0, если сначала едешь порожняком '
                  'под погрузку. Это определяет, какой пробег в начале рейса посчитается '
                  '"с грузом", а какой — "порожняком", пока ты не отметишь смену статуса в пути.',
              child: TextFormField(
                controller: _cargoWeightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _req,
              ),
            ),
            LabeledHelpField(
              label: 'Согласованная ставка за рейс',
              help: 'Сумма, которую тебе заплатят за весь рейс (фрахт). Приложение разделит её '
                  'на километраж, чтобы показать доход на 1 км — как по общему пробегу, так и '
                  'только по пробегу с грузом.',
              child: TextFormField(
                controller: _rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _req,
              ),
            ),
            const Divider(height: 32),
            const Text(
              'Внутренние ставки (для владельца) — необязательно, но без них '
              'отчёт покажет только прямые расходы по чекам, без полной себестоимости.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            LabeledHelpField(
              label: 'Оплата водителю за 1 км',
              help: 'Сколько закладываешь на зарплату водителя за каждый километр пробега. '
                  'Это внутренний (косвенный) расход — на сумму, которую платит заказчик, не влияет.',
              child: TextFormField(
                controller: _driverPayCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: LabeledHelpField(
                    label: 'Суточные за 1 день',
                    help: 'Суточные водителю за один день в рейсе.',
                    child: TextFormField(
                      controller: _perDiemCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledHelpField(
                    label: 'Плановое кол-во суток',
                    help: 'Сколько дней займёт рейс. Суточные умножатся на это число — '
                        'можно будет поправить перед финишем, если рейс затянулся.',
                    child: TextFormField(
                      controller: _perDiemDaysCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
              ],
            ),
            LabeledHelpField(
              label: 'Амортизация за 1 км',
              help: 'Закладка на износ техники (шины, ТО, ремонт) за каждый километр пробега — '
                  'показывает настоящую себестоимость рейса, а не только расходы "по чекам".',
              child: TextFormField(
                controller: _depreciationCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const Divider(height: 32),
            const Text(
              'Модель расхода топлива — расход растёт с массой груза (Fuel = F₀ + k × масса). '
              'Значения по умолчанию подходят для обычной фуры, можно поправить под свой тягач.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LabeledHelpField(
                    label: 'Базовый расход F₀, л/100км',
                    help: 'Расход ПОРОЖНЕГО автомобиля на 100 км — то, что показывает бортовой '
                        'компьютер, когда кузов пустой. Именно от этого числа считается расход '
                        'на всех порожних участках рейса.',
                    child: TextFormField(
                      controller: _baseFuelCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _req,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledHelpField(
                    label: 'Прибавка k, л/100км на тонну',
                    help: 'Насколько увеличивается расход на каждые 100 км за каждую тонну груза. '
                        'Например, при F₀=18 и k=0.47: с грузом 15 т расход станет '
                        '18 + 0.47×15 = 25.05 л/100км. Значение по умолчанию — ориентировочное, '
                        'подходит для типовой фуры; можно уточнить по факту своего тягача.',
                    child: TextFormField(
                      controller: _fuelPerTonCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _start,
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Начать рейс')),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
