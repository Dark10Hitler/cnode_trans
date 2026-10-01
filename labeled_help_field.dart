import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Поле ввода с "флажком-подсказкой": нажал — под полем разворачивается
/// полная инструкция, для чего именно эта ячейка. Используется в
/// разделе "Расчёты", где каждый ввод должен быть объяснён.
class LabeledHelpField extends StatefulWidget {
  final String label;
  final String help;
  final Widget child;

  const LabeledHelpField({super.key, required this.label, required this.help, required this.child});

  @override
  State<LabeledHelpField> createState() => _LabeledHelpFieldState();
}

class _LabeledHelpFieldState extends State<LabeledHelpField> {
  bool _showHelp = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _showHelp = !_showHelp),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  _showHelp ? Icons.flag : Icons.outlined_flag,
                  size: 18,
                  color: _showHelp ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        widget.child,
        if (_showHelp)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
              child: Text(widget.help, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}
