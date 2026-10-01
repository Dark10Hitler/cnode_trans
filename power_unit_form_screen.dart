import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/power_unit.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Форма тягача/грузовика/легковой/автобуса/велосипеда. Поля берутся
/// из типового техпаспорта; для велосипеда форма сильно короче
/// ([PowerUnitCategory.isSimpleProfile]) — не заставляем вводить VIN
/// и экокласс там, где их физически не существует.
class PowerUnitFormScreen extends StatefulWidget {
  final PowerUnit? unit;
  const PowerUnitFormScreen({super.key, this.unit});

  @override
  State<PowerUnitFormScreen> createState() => _PowerUnitFormScreenState();
}

class _PowerUnitFormScreenState extends State<PowerUnitFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late PowerUnitCategory _category;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _vinCtrl;
  late final TextEditingController _chassisVinCtrl;
  late final TextEditingController _engineCtrl;
  late final TextEditingController _grossWeightCtrl;
  late final TextEditingController _curbWeightCtrl;
  late final TextEditingController _payloadCtrl;
  late final TextEditingController _wheelFormulaCtrl;
  late final TextEditingController _cabinTypeCtrl;
  late final TextEditingController _envClassCtrl;
  late final TextEditingController _weightKgCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _lengthCtrl;
  late bool _hazmat;
  HazmatClass? _hazmatClass;

  bool get _isEditing => widget.unit != null;
  bool get _isSimple => _category.isSimpleProfile;

  @override
  void initState() {
    super.initState();
    final u = widget.unit;
    _category = u?.category ?? PowerUnitCategory.tractorUnit;
    _brandCtrl = TextEditingController(text: u?.brand ?? '');
    _modelCtrl = TextEditingController(text: u?.model ?? '');
    _yearCtrl = TextEditingController(text: u?.year?.toString() ?? '');
    _vinCtrl = TextEditingController(text: u?.vin ?? '');
    _chassisVinCtrl = TextEditingController(text: u?.chassisVin ?? '');
    _engineCtrl = TextEditingController(text: u?.engineType ?? '');
    _grossWeightCtrl = TextEditingController(text: u?.grossWeight?.toString() ?? '');
    _curbWeightCtrl = TextEditingController(text: u?.curbWeight?.toString() ?? '');
    _payloadCtrl = TextEditingController(text: u?.payloadCapacity?.toString() ?? '');
    _wheelFormulaCtrl = TextEditingController(text: u?.wheelFormula ?? '');
    _cabinTypeCtrl = TextEditingController(text: u?.cabinType ?? '');
    _envClassCtrl = TextEditingController(text: u?.environmentalClass ?? '');
    _weightKgCtrl = TextEditingController(text: u?.weightKg?.toString() ?? '');
    _heightCtrl = TextEditingController(text: u?.height.toString() ?? (_category.isSimpleProfile ? '1.10' : '4.00'));
    _widthCtrl = TextEditingController(text: u?.width.toString() ?? (_category.isSimpleProfile ? '0.60' : '2.55'));
    _lengthCtrl = TextEditingController(text: u?.length.toString() ?? (_category.isSimpleProfile ? '1.80' : '7.20'));
    _hazmat = u?.hazmat ?? false;
    _hazmatClass = u?.hazmatClass;
  }

  @override
  void dispose() {
    for (final c in [
      _brandCtrl, _modelCtrl, _yearCtrl, _vinCtrl, _chassisVinCtrl, _engineCtrl,
      _grossWeightCtrl, _curbWeightCtrl, _payloadCtrl, _wheelFormulaCtrl, _cabinTypeCtrl,
      _envClassCtrl, _weightKgCtrl, _heightCtrl, _widthCtrl, _lengthCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _requiredNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Укажи значение';
    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Введи число';
    return null;
  }

  String? _optionalNumber(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Введи число';
    return null;
  }

  double _num(TextEditingController c) => double.parse(c.text.replaceAll(',', '.'));
  double? _optNum(TextEditingController c) => c.text.trim().isEmpty ? null : _num(c);
  String? _optStr(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final unit = PowerUnit(
        id: widget.unit?.id,
        category: _category,
        brand: _brandCtrl.text.trim(),
        model: _optStr(_modelCtrl),
        year: _yearCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(_yearCtrl.text.trim()),
        vin: _optStr(_vinCtrl),
        chassisVin: _optStr(_chassisVinCtrl),
        engineType: _optStr(_engineCtrl),
        grossWeight: _isSimple ? null : _optNum(_grossWeightCtrl),
        curbWeight: _isSimple ? null : _optNum(_curbWeightCtrl),
        payloadCapacity: _isSimple ? null : _optNum(_payloadCtrl),
        wheelFormula: _isSimple ? null : _optStr(_wheelFormulaCtrl),
        cabinType: _isSimple ? null : _optStr(_cabinTypeCtrl),
        environmentalClass: _isSimple ? null : _optStr(_envClassCtrl),
        weightKg: _isSimple ? _optNum(_weightKgCtrl) : null,
        height: _num(_heightCtrl),
        width: _num(_widthCtrl),
        length: _num(_lengthCtrl),
        hazmat: _isSimple ? false : _hazmat,
        hazmatClass: _isSimple
            ? null
            : (_hazmat ? _hazmatClass : null),
        isActive: widget.unit?.isActive ?? false,
        createdAt: widget.unit?.createdAt ?? DateTime.now(),
      );

      final appState = context.read<AppState>();

      if (_isEditing) {
        await appState.updatePowerUnit(unit);
      } else {
        await appState.addPowerUnit(unit);
      }

      if (mounted) {
        Navigator.of(context).pop(); // закрываем загрузку
        Navigator.of(context).pop(); // закрываем форму
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // закрываем загрузку

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать ТС' : 'Новое ТС')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Тип', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PowerUnitCategory.values.map((cat) {
                final selected = cat == _category;
                return ChoiceChip(
                  label: Text('${cat.icon} ${cat.label}'),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = cat),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surfaceHigh,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.onPrimary : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _Field('Марка', _brandCtrl, validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи марку' : null),
            _Field('Модель (необязательно)', _modelCtrl),
            if (!_isSimple) ...[
              _Field('Год выпуска (необязательно)', _yearCtrl, keyboardType: TextInputType.number),
              _Field('VIN-номер (необязательно)', _vinCtrl),
              _Field('VIN-номер шасси (необязательно)', _chassisVinCtrl),
              _Field('Тип и модель двигателя (необязательно)', _engineCtrl),
              Row(children: [
                Expanded(child: _Field('Разрешённая макс. масса, т', _grossWeightCtrl, keyboardType: TextInputType.number, validator: _optionalNumber)),
                const SizedBox(width: 12),
                Expanded(child: _Field('Масса без нагрузки, т', _curbWeightCtrl, keyboardType: TextInputType.number, validator: _optionalNumber)),
              ]),
              _Field('Грузоподъёмность, т', _payloadCtrl, keyboardType: TextInputType.number, validator: _optionalNumber),
              Row(children: [
                Expanded(child: _Field('Колёсная формула (напр. 4x2)', _wheelFormulaCtrl)),
                const SizedBox(width: 12),
                Expanded(child: _Field('Тип кабины', _cabinTypeCtrl)),
              ]),
              _Field('Экологический класс (напр. Euro 6)', _envClassCtrl),
            ] else
              _Field('Масса, кг (необязательно)', _weightKgCtrl, keyboardType: TextInputType.number, validator: _optionalNumber),
            const SizedBox(height: 6),
            const Text('Габариты (для маршрутизации)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _Field('Высота, м', _heightCtrl, keyboardType: TextInputType.number, validator: _requiredNumber)),
              const SizedBox(width: 12),
              Expanded(child: _Field('Ширина, м', _widthCtrl, keyboardType: TextInputType.number, validator: _requiredNumber)),
            ]),
            _Field('Длина, м', _lengthCtrl, keyboardType: TextInputType.number, validator: _requiredNumber),
            if (!_isSimple) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primary,
                title: const Text('Опасный груз (ADR) сертифицирован на этом ТС'),
                value: _hazmat,
                onChanged: (v) => setState(() => _hazmat = v),
              ),
              if (_hazmat) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<HazmatClass>(
                  initialValue: _hazmatClass,
                  decoration: const InputDecoration(hintText: 'Класс опасности ADR'),
                  dropdownColor: AppColors.surfaceHigh,
                  items: HazmatClass.values
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.label, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _hazmatClass = v),
                ),
              ],
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_isEditing ? 'Сохранить изменения' : 'Сохранить ТС'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field(this.label, this.controller, {this.keyboardType, this.validator});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          TextFormField(controller: controller, keyboardType: keyboardType, validator: validator),
        ],
      ),
    );
  }
}
