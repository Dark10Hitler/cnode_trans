import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'hos_guide_data.dart';
import 'hos_timer_state.dart';
import '../theme/app_theme.dart';

class HosSectionWidget extends StatelessWidget {
  const HosSectionWidget({super.key});

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours ч $minutes мин';
  }

  @override
  Widget build(BuildContext context) {
    final hos = context.watch<HosTimerState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Шапка раздела с тумблером
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: AppColors.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Режим труда и отдыха (AETR / ЕС)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            'Справочный таймер и напоминания',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: hos.enabled,
                      onChanged: (val) => hos.setEnabled(val),
                    ),
                  ],
                ),

                // Блок таймера (отображается только если РТиО включён)
                if (hos.enabled) ...[
                  const Divider(height: 24),
                  if (!hos.isRunning)
                    ElevatedButton.icon(
                      onPressed: () => hos.startShift(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Запустить смену / Начать движение'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildTimeInfo(
                          'В пути',
                          _formatDuration(hos.elapsed),
                          AppColors.primary,
                        ),
                        _buildTimeInfo(
                          'До перерыва (4:30)',
                          _formatDuration(hos.timeUntilBreak),
                          hos.timeUntilBreak.inMinutes < 30 ? Colors.orange : Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => hos.stopShift(),
                      icon: const Icon(Icons.stop),
                      label: const Text('Завершить смену / На отдых'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        minimumSize: const Size.fromHeight(40),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Text(
          'Справочник водителя и Тахограф',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),

        // Интерактивный список инструкций
        ...HosGuideData.topics.map((topic) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: Text(topic.icon, style: const TextStyle(fontSize: 22)),
            title: Text(
              topic.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              topic.summary,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: topic.details
                      .map((detail) => Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      detail,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ))
                      .toList(),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildTimeInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}