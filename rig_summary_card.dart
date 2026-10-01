import 'package:flutter/material.dart';

import '../models/rig_profile.dart';
import '../models/power_unit.dart';
import '../theme/app_theme.dart';

/// Карточка "текущий борт" — показывает, под какой именно транспорт
/// (или связку) сейчас считается маршрут.
class RigSummaryCard extends StatelessWidget {
  final RigProfile rig;
  const RigSummaryCard({super.key, required this.rig});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Text(rig.powerUnit.category.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rig.label,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${rig.height.toStringAsFixed(2)}м × ${rig.width.toStringAsFixed(2)}м × '
                  '${rig.length.toStringAsFixed(2)}м · ${rig.weight.toStringAsFixed(1)}т'
                  '${rig.hazmat ? ' · ⚠️ ADR' : ''}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
