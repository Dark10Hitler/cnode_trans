import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/trip.dart';
import '../../state/trip_state.dart';
import '../../theme/app_theme.dart';
import 'trip_active_screen.dart';
import 'trip_report_screen.dart';
import 'trip_start_form_screen.dart';

/// Вкладка "Расчёты": список рейсов + быстрый доступ к активному рейсу.
/// Экспресс-бухгалтерия для небольшого перевозчика — без тетради и Excel.
class TripsListScreen extends StatefulWidget {
  const TripsListScreen({super.key});

  @override
  State<TripsListScreen> createState() => _TripsListScreenState();
}

class _TripsListScreenState extends State<TripsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<TripState>().loadTrips());
  }

  void _openTrip(TripRecord trip) async {
    await context.read<TripState>().openTripById(trip.id!);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => trip.status == TripStatus.inProgress ? const TripActiveScreen() : const TripReportScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tripState = context.watch<TripState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Расчёты')),
      body: tripState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : tripState.trips.isEmpty
              ? const _EmptyHint()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: tripState.trips.length,
                  itemBuilder: (context, index) {
                    final trip = tripState.trips[index];
                    final inProgress = trip.status == TripStatus.inProgress;
                    return Card(
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(
                          inProgress ? Icons.local_shipping : Icons.receipt_long_outlined,
                          color: inProgress ? AppColors.warning : AppColors.primary,
                        ),
                        title: Text(trip.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${DateFormat('dd.MM.yyyy').format(trip.startedAt)}'
                          ' · ${inProgress ? "в пути" : "завершён"}',
                        ),
                        trailing: inProgress
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => context.read<TripState>().deleteTrip(trip.id!),
                              ),
                        onTap: () => _openTrip(trip),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'trips_fab',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const TripStartFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Новый рейс'),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧮', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Рейсов пока нет', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Экспресс-расчёт перед рейсом: старт → заправки и плечи в пути → финиш → '
              'готовый PDF-отчёт для себя или бухгалтерии.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
