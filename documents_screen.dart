import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';
import '../../models/document.dart';
import '../../models/driver_profile.dart';
import '../../models/trailer.dart';
import 'driver_form_screen.dart';

/// Вкладка "Документы": профиль водителя и документы транспорта.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Документы'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Водитель'),
              Tab(text: 'Тягачи/машины'),
              Tab(text: 'Прицепы'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DriverDocumentsTab(),
            _PowerUnitDocumentsTab(),
            _TrailerDocumentsTab(),
          ],
        ),
      ),
    );
  }
}

class _DriverDocumentsTab extends StatelessWidget {
  const _DriverDocumentsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final profile = appState.driverProfile;
    final driverDocs = appState.documents
        .where((d) =>
    d.ownerType == DocumentOwnerType.driver &&
        d.ownerId == DriverProfile.singletonId)
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          if (profile == null)
            Card(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Профиль водителя ещё не заполнен. Сначала укажи ФИО и данные ВУ — после этого можно добавлять документы.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DriverFormScreen()),
                      ),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Заполнить профиль'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: AppColors.surface,
              child: ListTile(
                leading: const Icon(Icons.badge_outlined, color: AppColors.primary),
                title: Text(profile.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [
                    if (profile.licenseNumber != null) 'ВУ ${profile.licenseNumber}',
                    if (profile.licenseCategories != null) profile.licenseCategories,
                    if (profile.licenseExpiry != null)
                      'до ${profile.licenseExpiry!.toLocal().toString().split(' ').first}',
                  ].join(' · ').ifEmpty('Данные удостоверения не указаны'),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Редактировать профиль',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DriverFormScreen(profile: profile)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (profile != null && driverDocs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Нет документов у водителя',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ...driverDocs.map((doc) => _DocumentTile(doc: doc)),
        ],
      ),
      floatingActionButton: profile == null
          ? null
          : FloatingActionButton.extended(
        heroTag: 'driver_docs_fab',
        onPressed: () => _showDocumentEditor(
          context,
          ownerType: DocumentOwnerType.driver,
          ownerId: DriverProfile.singletonId,
          ownerLabel: profile.fullName,
        ),
        icon: const Icon(Icons.add),
        label: const Text('Добавить документ'),
      ),
    );
  }
}

class _PowerUnitDocumentsTab extends StatelessWidget {
  const _PowerUnitDocumentsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.powerUnits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Нет ни одного тягача/грузовика. Добавь в разделе «Транспорт».',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: appState.powerUnits.length,
      itemBuilder: (context, index) {
        final unit = appState.powerUnits[index];
        final unitDocs = appState.documents
            .where((d) =>
        d.ownerType == DocumentOwnerType.powerUnit && d.ownerId == unit.id)
            .toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_shipping,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      unit.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: unit.id == null
                        ? null
                        : () => _showDocumentEditor(
                      context,
                      ownerType: DocumentOwnerType.powerUnit,
                      ownerId: unit.id!,
                      ownerLabel: unit.displayName,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (unitDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Нет документов',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                )
              else
                ...unitDocs.map((doc) => _DocumentTile(doc: doc)),
            ],
          ),
        );
      },
    );
  }
}

class _TrailerDocumentsTab extends StatelessWidget {
  const _TrailerDocumentsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.trailers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Нет ни одного прицепа/полуприцепа. Добавь в разделе «Транспорт».',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: appState.trailers.length,
      itemBuilder: (context, index) {
        final trailer = appState.trailers[index];
        final trailerDocs = appState.documents
            .where((d) =>
        d.ownerType == DocumentOwnerType.trailer && d.ownerId == trailer.id)
            .toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    trailer.kind == TrailerKind.semiTrailer
                        ? Icons.rv_hookup
                        : Icons.airline_seat_legroom_reduced,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trailer.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: trailer.id == null
                        ? null
                        : () => _showDocumentEditor(
                      context,
                      ownerType: DocumentOwnerType.trailer,
                      ownerId: trailer.id!,
                      ownerLabel: trailer.displayName,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (trailerDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Нет документов',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                )
              else
                ...trailerDocs.map((doc) => _DocumentTile(doc: doc)),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final AppDocument doc;

  const _DocumentTile({required this.doc});

  void _openImagePreview(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(doc.name, style: const TextStyle(color: Colors.white, fontSize: 16)),
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = doc.isExpired;
    final expiringSoon = doc.isExpiringSoon;
    final hasPhoto = doc.filePath.isNotEmpty && File(doc.filePath).existsSync();

    return Card(
      color: isExpired ? AppColors.danger.withOpacity(0.1) : AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () {
          if (hasPhoto) {
            _openImagePreview(context, doc.filePath);
          } else {
            _showDocumentEditor(
              context,
              ownerType: doc.ownerType,
              ownerId: doc.ownerId,
              ownerLabel: doc.name,
              existing: doc,
            );
          }
        },
        leading: hasPhoto
            ? ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(doc.filePath),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        )
            : Icon(
          Icons.description_outlined,
          color: isExpired
              ? AppColors.danger
              : expiringSoon
              ? AppColors.warning
              : AppColors.primary,
        ),
        title: Text(
          doc.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doc.category.label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (doc.expiryDate != null)
              Text(
                'Истекает: ${doc.expiryDate!.toLocal().toString().split(' ')[0]}'
                    '${isExpired ? ' ⚠️ ИСТЁК' : expiringSoon ? ' ⏰ СКОРО' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: isExpired
                      ? AppColors.danger
                      : expiringSoon
                      ? AppColors.warning
                      : AppColors.textSecondary,
                  fontWeight:
                  isExpired || expiringSoon ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Редактировать',
              onPressed: () => _showDocumentEditor(
                context,
                ownerType: doc.ownerType,
                ownerId: doc.ownerId,
                ownerLabel: doc.name,
                existing: doc,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text('«${doc.name}» будет удален.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteDocument(doc);
              Navigator.pop(dialogContext);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

void _showDocumentEditor(
    BuildContext context, {
      required DocumentOwnerType ownerType,
      required int ownerId,
      required String ownerLabel,
      AppDocument? existing,
    }) {
  showDialog(
    context: context,
    builder: (dialogContext) => _DocumentEditorDialog(
      ownerType: ownerType,
      ownerId: ownerId,
      ownerLabel: ownerLabel,
      existing: existing,
    ),
  );
}

class _DocumentEditorDialog extends StatefulWidget {
  final DocumentOwnerType ownerType;
  final int ownerId;
  final String ownerLabel;
  final AppDocument? existing;

  const _DocumentEditorDialog({
    required this.ownerType,
    required this.ownerId,
    required this.ownerLabel,
    this.existing,
  });

  @override
  State<_DocumentEditorDialog> createState() => _DocumentEditorDialogState();
}

class _DocumentEditorDialogState extends State<_DocumentEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _expiryDateCtrl;
  late DocumentCategory _selectedCategory;
  DateTime? _expiryDate;
  String? _filePath;

  bool get _isEditing => widget.existing != null;

  List<DocumentCategory> get _categories => DocumentCategoryX.forOwner(widget.ownerType);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedCategory = existing != null && _categories.contains(existing.category)
        ? existing.category
        : _categories.first;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _expiryDate = existing?.expiryDate;
    _filePath = existing?.filePath;
    _expiryDateCtrl = TextEditingController(
      text: _expiryDate == null ? '' : _expiryDate!.toLocal().toString().split(' ').first,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _expiryDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, imageQuality: 85);
      if (pickedFile == null) return;

      // Сохраняем фото в локальное постоянное хранилище приложения
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'doc_${DateTime.now().millisecondsSinceEpoch}${p.extension(pickedFile.path)}';
      final localImage = await File(pickedFile.path).copy('${appDir.path}/$fileName');

      setState(() {
        _filePath = localImage.path;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при выборе фото: $e')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 10),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date != null) {
      setState(() {
        _expiryDate = date;
        _expiryDateCtrl.text = date.toLocal().toString().split(' ').first;
      });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажи название документа')),
      );
      return;
    }

    final appState = context.read<AppState>();
    final path = _filePath ?? '';

    if (_isEditing) {
      await appState.updateDocument(
        widget.existing!.copyWith(
          category: _selectedCategory,
          name: _nameCtrl.text.trim(),
          filePath: path,
          expiryDate: _expiryDate,
          clearExpiryDate: _expiryDate == null,
        ),
      );
    } else {
      await appState.addDocument(
        AppDocument(
          ownerType: widget.ownerType,
          ownerId: widget.ownerId,
          category: _selectedCategory,
          name: _nameCtrl.text.trim(),
          fileType: DocumentFileType.jpg,
          expiryDate: _expiryDate,
          filePath: path,
          createdAt: DateTime.now(),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _filePath != null && _filePath!.isNotEmpty && File(_filePath!).existsSync();

    return AlertDialog(
      title: Text(_isEditing
          ? 'Редактировать документ'
          : 'Добавить документ к ${widget.ownerLabel}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<DocumentCategory>(
              value: _selectedCategory,
              isExpanded: true,
              dropdownColor: AppColors.surfaceHigh,
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedCategory = v);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: 'Название документа (напр. «СТС Волга»)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expiryDateCtrl,
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'Дата истечения (необязательно)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  onPressed: _pickDate,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Блок выбора и превью фото
            if (hasPhoto)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_filePath!),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                    onPressed: () => setState(() => _filePath = null),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('Камера'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Галерея'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Сохранить' : 'Добавить'),
        ),
      ],
    );
  }
}

extension _EmptyString on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}