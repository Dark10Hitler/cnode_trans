import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/power_unit.dart';
import '../../models/trailer.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class TrailerFormScreen extends StatefulWidget {
  final Trailer? trailer;
  const TrailerFormScreen({super.key, this.trailer});

  @override
  State<TrailerFormScreen> createState() => _TrailerFormScreenState();
}

class _TrailerFormScreenState extends State<TrailerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TrailerKind _kind;
  SemiTrailerType? _semiType;
  late final TextEditingController _lightTypeCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _vinCtrl;
  late final TextEditingController _axleCountCtrl;
  late final TextEditingController _axleTypeCtrl;
  late final TextEditingController _maxAxleLoadCtrl;
  late final TextEditingController _payloadCtrl;
  late final TextEditingController _emptyWeightCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _lengthCtrl;
  late bool _hazmat;
  HazmatClass? _hazmatClass;

  bool get _isEditing => widget.trailer != null;
  bool get _isSemi => _kind == TrailerKind.semiTrailer;

  @override
  void initState() {
    super.initState();
    final t = widget.trailer;
    _kind = t?.kind ?? TrailerKind.semiTrailer;
    _semiType = t?.semiTrailerType ?? SemiTrailerType.curtainSided;
    _lightTypeCtrl = TextEditingController(text: t?.lightTrailerType ?? '');
    _brandCtrl = TextEditingController(text: t?.brand ?? '');
    _modelCtrl = TextEditingController(text: t?.model ?? '');
    _vinCtrl = TextEditingController(text: t?.vin ?? '');
    _axleCountCtrl = TextEditingController(text: t?.axleCount?.toString() ?? (_isSemi ? '3' : '1'));
    _axleTypeCtrl = TextEditingController(text: t?.axleType ?? '');
    _maxAxleLoadCtrl = TextEditingController(text: t?.maxAxleLoad?.toString() ?? '');
    _payloadCtrl = TextEditingController(text: t?.payloadCapacity?.toString() ?? '');
    _emptyWeightCtrl = TextEditingController(text: t?.emptyWeight?.toString() ?? '');
    _heightCtrl = TextEditingController(text: t?.height.toString() ?? (_isSemi ? '2.70' : '1.20'));
    _widthCtrl = TextEditingController(text: t?.width.toString() ?? (_isSemi ? '2.55' : '1.60'));
    _lengthCtrl = TextEditingController(text: t?.length.toString() ?? (_isSemi ? '13.60' : '2.50'));
    _hazmat = t?.hazmat ?? false;
    _hazmatClass = t?.hazmatClass;
  }

  @override
  void dispose() {
    for (final c in [
      _lightTypeCtrl, _brandCtrl, _modelCtrl, _vinCtrl, _axleCountCtrl, _axleTypeCtrl,
      _maxAxleLoadCtrl, _payloadCtrl, _emptyWeightCtrl, _heightCtrl, _widthCtrl, _lengthCtrl,
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final trailer = Trailer(
        id: widget.trailer?.id,
        kind: _kind,
        semiTrailerType: _isSemi ? _semiType : null,
        lightTrailerType: _isSemi ? null : _optStr(_lightTypeCtrl),
        brand: _optStr(_brandCtrl),
        model: _optStr(_modelCtrl),
        vin: _optStr(_vinCtrl),
        axleCount: _axleCountCtrl.text.trim().isEmpty ? null : int.tryParse(_axleCountCtrl.text.trim()),
        axleType: _optStr(_axleTypeCtrl),
        maxAxleLoad: _optNum(_maxAxleLoadCtrl),
        payloadCapacity: _optNum(_payloadCtrl),
        emptyWeight: _optNum(_emptyWeightCtrl),
        height: _num(_heightCtrl),
        width: _num(_widthCtrl),
        length: _num(_lengthCtrl),
        hazmat: _hazmat,
        hazmatClass: _hazmat ? _hazmatClass : null,
        createdAt: widget.trailer?.createdAt ?? DateTime.now(),
      );

      final appState = context.read<AppState>();
      if (_isEditing) {
        await appState.updateTrailer(trailer);
      } else {
        await appState.addTrailer(trailer);
      }

      if (mounted) {
        Navigator.of(context).pop(); // закрываем индикатор загрузки
        Navigator.of(context).pop(); // возвращаемся назад
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // закрываем индикатор загрузки
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать прицеп' : 'Новый прицеп')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Вид', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TrailerKind.values.map((k) {
                final selected = k == _kind;
                return ChoiceChip(
                  label: Text(k.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _kind = k),
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
            if (_isSemi) ...[
              const Text('Тип кузова', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<SemiTrailerType>(
                initialValue: _semiType,
                dropdownColor: AppColors.surfaceHigh,
                items: SemiTrailerType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (v) => setState(() => _semiType = v),
              ),
              const SizedBox(height: 16),
            ] else
              _Field('Тип прицепа (напр. закрытый, для лодки)', _lightTypeCtrl),
            _Field('Марка (необязательно)', _brandCtrl),
            _Field('Модель (необязательно)', _modelCtrl),
            _Field('VIN-номер (необязательно)', _vinCtrl),
            Row(children: [
              Expanded(child: _Field('Кол-во осей', _axleCountCtrl, keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _Field('Тип осей (необязательно)', _axleTypeCtrl)),
            ]),
            Row(children: [
              Expanded(child: _Field('Макс. осевая нагрузка, т', _maxAxleLoadCtrl, keyboardType: TextInputType.number, validator: _optionalNumber)),
              const SizedBox(width: 12),
              Expanded(child: _Field('Грузоподъёмность, т', _payloadCtrl, keyboardType: TextInputType.number, validator: _optionalNumber)),
            ]),
            _Field('Масса без груза, т (необязательно)', _emptyWeightCtrl, keyboardType: TextInputType.number, validator: _optionalNumber),
            const SizedBox(height: 6),
            const Text('Габариты', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _Field('Высота, м', _heightCtrl, keyboardType: TextInputType.number, validator: _requiredNumber)),
              const SizedBox(width: 12),
              Expanded(child: _Field('Ширина, м', _widthCtrl, keyboardType: TextInputType.number, validator: _requiredNumber)),
            ]),
            _Field('Длина, м', _lengthCtrl, keyboardType: TextInputType.number, validator: _requiredNumber),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              title: const Text('Опасный груз (ADR) сертифицирован на этом прицепе'),
              subtitle: const Text('Частый случай для цистерн', style: TextStyle(fontSize: 11)),
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
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_isEditing ? 'Сохранить изменения' : 'Сохранить прицеп'),
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