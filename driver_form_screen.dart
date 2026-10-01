import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/driver_profile.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Создание и редактирование профиля водителя (в MVP один на приложение).
class DriverFormScreen extends StatefulWidget {
  final DriverProfile? profile;

  const DriverFormScreen({super.key, this.profile});

  @override
  State<DriverFormScreen> createState() => _DriverFormScreenState();
}

class _DriverFormScreenState extends State<DriverFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _licenseCtrl;
  late final TextEditingController _categoriesCtrl;
  late final TextEditingController _expiryCtrl;
  DateTime? _licenseExpiry;

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p?.fullName ?? '');
    _licenseCtrl = TextEditingController(text: p?.licenseNumber ?? '');
    _categoriesCtrl = TextEditingController(text: p?.licenseCategories ?? '');
    _licenseExpiry = p?.licenseExpiry;
    _expiryCtrl = TextEditingController(
      text: _licenseExpiry == null ? '' : _licenseExpiry!.toLocal().toString().split(' ').first,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _licenseCtrl.dispose();
    _categoriesCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _licenseExpiry ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (date != null) {
      setState(() {
        _licenseExpiry = date;
        _expiryCtrl.text = date.toLocal().toString().split(' ').first;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = DriverProfile(
      id: DriverProfile.singletonId,
      fullName: _nameCtrl.text.trim(),
      licenseNumber: _licenseCtrl.text.trim().isEmpty ? null : _licenseCtrl.text.trim(),
      licenseCategories:
          _categoriesCtrl.text.trim().isEmpty ? null : _categoriesCtrl.text.trim(),
      licenseExpiry: _licenseExpiry,
    );
    await context.read<AppState>().saveDriverProfile(profile);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать водителя' : 'Профиль водителя')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('ФИО', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи ФИО' : null,
              decoration: const InputDecoration(hintText: 'Иванов Иван Иванович'),
            ),
            const SizedBox(height: 16),
            const Text('Номер водительского удостоверения',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _licenseCtrl,
              decoration: const InputDecoration(hintText: 'Необязательно'),
            ),
            const SizedBox(height: 16),
            const Text('Категории (напр. B, C, CE)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _categoriesCtrl,
              decoration: const InputDecoration(hintText: 'Необязательно'),
            ),
            const SizedBox(height: 16),
            const Text('Срок действия ВУ',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              readOnly: true,
              controller: _expiryCtrl,
              decoration: InputDecoration(
                hintText: 'Дата истечения (необязательно)',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_licenseExpiry != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() {
                          _licenseExpiry = null;
                          _expiryCtrl.clear();
                        }),
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      onPressed: _pickExpiry,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_isEditing ? 'Сохранить изменения' : 'Сохранить профиль'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'После сохранения на этой вкладке можно добавлять и править документы водителя.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
