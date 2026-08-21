import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/courier.dart';
import '../orders/orders_screen.dart' show formatOrderDate;
import '../theme/colors.dart';
import '../theme/formatters.dart';
import '../theme/theme.dart';

/// Раздел «Заработок»: суммы today/week/total + история доставок.
class CourierEarningsScreen extends StatefulWidget {
  const CourierEarningsScreen({super.key});

  @override
  State<CourierEarningsScreen> createState() => _CourierEarningsScreenState();
}

class _CourierEarningsScreenState extends State<CourierEarningsScreen> {
  CourierEarnings? _earnings;
  List<CourierOrder>? _history;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _earnings == null;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final earnings = await api.fetchCourierEarnings();
      final history = await api.fetchCourierHistory();
      if (!mounted) return;
      setState(() {
        _earnings = earnings;
        _history = history.results;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Заработок')),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return _CenteredScrollable(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style:
                  ElevatedButton.styleFrom(minimumSize: const Size(160, 44)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    final earnings = _earnings!;
    final history = _history!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Row(
          children: [
            _EarningsCard(label: 'Сегодня', value: earnings.today),
            const SizedBox(width: 10),
            _EarningsCard(label: 'Неделя', value: earnings.week),
            const SizedBox(width: 10),
            _EarningsCard(label: 'Всего', value: earnings.total),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'История доставок',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Доставок пока не было',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          for (final order in history) ...[
            _HistoryCard(order: order),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kCardShadow,
        ),
        child: Column(
          children: [
            Text(
              formatSomoni(value),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.order});

  final CourierOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: kCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.number,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '+${formatSomoni(order.fee ?? 0)}',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.address.addressText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatOrderDate(order.deliveredAt),
            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

/// Обертка для состояния ошибки, чтобы работал pull-to-refresh.
class _CenteredScrollable extends StatelessWidget {
  const _CenteredScrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
