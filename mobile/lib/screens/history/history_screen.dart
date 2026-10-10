import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/sales_history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/csv_export.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Port of `src/pages/SalesHistoryPage.tsx`.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with WidgetsBindingObserver {
  String _dateFilter = '30d';
  String _selectedMonth = 'all';

  // The tab stays alive in the background, so "Today"/"Yesterday" and the
  // date ranges are refreshed at midnight and when the app is reopened.
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _scheduleMidnight();
    }
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnight();
    });
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<Sale> _filtered(SalesHistoryProvider history) {
    final now = DateTime.now();
    final days = switch (_dateFilter) { '7d' => 7, '30d' => 30, '90d' => 90, _ => null };
    if (days == null) return history.sales;
    return history.getSalesByDateRange(now.subtract(Duration(days: days)), now);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final history = context.watch<SalesHistoryProvider>();
    final settings = context.watch<SettingsProvider>();
    final formatPrice = settings.formatPrice;

    final sales = history.sales;
    final monthly = history.getMonthlySalesData();
    final now = DateTime.now();
    final todays = sales.where((s) => _sameDay(s.date, now)).toList();
    final yesterdays = sales.where((s) => _sameDay(s.date, now.subtract(const Duration(days: 1)))).toList();
    final filtered = _filtered(history);
    final totalRevenue = filtered.fold(0, (s, x) => s + x.total);
    final avgOrder = filtered.isNotEmpty ? (totalRevenue / filtered.length).round() : 0;

    MonthlySalesData? best = monthly.isEmpty ? null : monthly.first;
    for (final m in monthly) {
      if (m.total > best!.total) best = m;
    }

    final List<ProductSalesData> topProducts;
    if (_selectedMonth == 'all') {
      topProducts = history.getTopProductsAllTime(5);
    } else {
      final parts = _selectedMonth.split('-').map(int.parse).toList();
      topProducts = history.getTopProductsByMonth(parts[0], parts[1]).take(5).toList();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: FadeIn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              icon: LucideIcons.chartColumn,
              gradient: p.gradientHero,
              shadow: p.shadowGlow,
              title: 'Sales History',
              subtitle: plural(sales.length, 'total transaction'),
              action: Row(mainAxisSize: MainAxisSize.min, children: [
                AppSelect<String>(
                  value: _dateFilter,
                  width: 160,
                  leading: LucideIcons.calendar,
                  options: const [
                    SelectOption('7d', 'Last 7 days'),
                    SelectOption('30d', 'Last 30 days'),
                    SelectOption('90d', 'Last 90 days'),
                    SelectOption('all', 'All time'),
                  ],
                  onChanged: (v) => setState(() => _dateFilter = v),
                ),
                const SizedBox(width: 12),
                AppButton(
                  label: 'Export CSV',
                  icon: LucideIcons.download,
                  variant: ButtonVariant.outline,
                  onPressed: () async {
                    try {
                      await exportSalesCsv(filtered);
                    } catch (_) {
                      if (context.mounted) {
                        showToast(context, title: 'Error', description: 'Could not export CSV', destructive: true);
                      }
                    }
                  },
                ),
              ]),
            ),
            const SizedBox(height: 32),
            _DayCard(
              title: "Today's Sales",
              icon: LucideIcons.sun,
              color: p.primary,
              sales: todays,
              formatPrice: formatPrice,
            ),
            const SizedBox(height: 16),
            _DayCard(
              title: "Yesterday's Sales",
              icon: LucideIcons.clock,
              color: p.accent,
              sales: yesterdays,
              formatPrice: formatPrice,
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _StatCard(
                  label: 'Total Revenue',
                  stripe: p.gradientPrimary,
                  value: Text(formatPrice(totalRevenue), style: _statStyle(p.primary)),
                ),
                _StatCard(
                  label: 'Total Orders',
                  stripe: p.gradientAccent,
                  value: Text('${filtered.length}', style: _statStyle(p.accent)),
                ),
                _StatCard(
                  label: 'Avg Order Value',
                  stripe: p.gradientSuccess,
                  value: Text(formatPrice(avgOrder), style: _statStyle(p.success)),
                ),
                _StatCard(
                  label: 'Best Month',
                  icon: LucideIcons.trendingUp,
                  stripeColor: p.warning,
                  value: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(best != null ? '${best.month} ${best.year}' : 'N/A',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.foreground)),
                    if (best != null)
                      Text(formatPrice(best.total), style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 32),
            AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _CardTitle(icon: LucideIcons.chartColumn, iconColor: p.primary, text: 'Monthly Sales Trend'),
                const SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  child: monthly.isEmpty
                      ? Center(child: Text('No sales data yet', style: TextStyle(color: p.mutedForeground)))
                      : _MonthlyChart(data: monthly, symbol: settings.settings.currencySymbol, formatPrice: formatPrice),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _CardTitle(icon: LucideIcons.package, iconColor: p.accent, text: 'Top Selling Products'),
                    AppSelect<String>(
                      value: _selectedMonth,
                      width: 150,
                      placeholder: 'Select month',
                      options: [
                        const SelectOption('all', 'All Time'),
                        for (final m in monthly) SelectOption(m.key, '${m.month} ${m.year}'),
                      ],
                      onChanged: (v) => setState(() => _selectedMonth = v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (topProducts.isEmpty)
                  SizedBox(
                    height: 200,
                    child: Center(child: Text('No product data', style: TextStyle(color: p.mutedForeground))),
                  )
                else
                  for (var i = 0; i < topProducts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: chartColors[i % chartColors.length],
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                          ),
                          child: Text('${i + 1}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(topProducts[i].productName,
                                style: TextStyle(fontWeight: FontWeight.w500, color: p.foreground)),
                            Text('${topProducts[i].quantity} sold',
                                style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                          ]),
                        ),
                        Text(formatPrice(topProducts[i].revenue),
                            style: TextStyle(fontWeight: FontWeight.w600, color: p.foreground)),
                      ]),
                    ),
              ]),
            ),
            const SizedBox(height: 32),
            AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Recent Transactions', style: display(22, color: p.foreground)),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No transactions found', style: TextStyle(color: p.mutedForeground))),
                  )
                else
                  _TransactionsTable(sales: filtered.take(20).toList(), formatPrice: formatPrice),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _statStyle(Color c) => TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c);
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.iconColor, required this.text});
  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Text(text, style: display(20, color: context.palette.foreground)),
      ]);
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.sales,
    required this.formatPrice,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Sale> sales;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = sales.fold(0, (s, x) => s + x.total);
    return AppCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(color.withValues(alpha: 0.1), p.card),
          Color.alphaBlend(color.withValues(alpha: 0.05), p.card),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.mutedForeground)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(
            child: Text(formatPrice(total), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: color)),
          ),
          Text(plural(sales.length, 'order'), style: TextStyle(fontSize: 14, color: p.mutedForeground)),
        ]),
        if (sales.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final s in sales.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(timeHm.format(s.date), style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                Text(formatPrice(s.total),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.foreground)),
              ]),
            ),
          if (sales.length > 5)
            Text('+${sales.length - 5} more', style: TextStyle(fontSize: 12, color: p.mutedForeground)),
        ],
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.stripe, this.stripeColor, this.icon});
  final String label;
  final Widget value;
  final Gradient? stripe;
  final Color? stripeColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      stripe: stripe,
      stripeColor: stripeColor,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: p.mutedForeground), const SizedBox(width: 6)],
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.mutedForeground)),
          ),
        ]),
        const SizedBox(height: 12),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
      ]),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.data, required this.symbol, required this.formatPrice});
  final List<MonthlySalesData> data;
  final String symbol;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tick = TextStyle(fontSize: 12, color: p.mutedForeground);
    final grid = FlLine(color: p.border, strokeWidth: 1, dashArray: [3, 3]);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: data[i].total / 100, // chart axis in major units
                color: p.primary,
                width: data.length > 6 ? 16 : 32,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ]),
        ],
        gridData: FlGridData(getDrawingHorizontalLine: (_) => grid, getDrawingVerticalLine: (_) => grid),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: p.border), left: BorderSide(color: p.border)),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) =>
                  SideTitleWidget(meta: meta, child: Text(data[v.toInt()].month, style: tick)),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text('$symbol${formatAxis(v)}', style: tick),
              ),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => p.card,
            tooltipBorder: BorderSide(color: p.border),
            tooltipBorderRadius: BorderRadius.circular(12),
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${data[group.x].month}\n',
              TextStyle(color: p.foreground, fontWeight: FontWeight.w500),
              children: [
                TextSpan(text: 'Revenue : ${formatPrice(data[group.x].total)}', style: TextStyle(color: p.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionsTable extends StatelessWidget {
  const _TransactionsTable({required this.sales, required this.formatPrice});
  final List<Sale> sales;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final head = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.mutedForeground);
    final cell = TextStyle(fontSize: 14, color: p.foreground);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        horizontalMargin: 0,
        columnSpacing: 20,
        headingRowHeight: 48,
        dividerThickness: 1,
        border: TableBorder(horizontalInside: BorderSide(color: p.border)),
        columns: [
          DataColumn(label: Text('Date', style: head)),
          DataColumn(label: Text('Items', style: head)),
          DataColumn(label: Text('Qty', style: head)),
          DataColumn(label: Text('Total', style: head), numeric: true),
        ],
        rows: [
          for (final s in sales)
            DataRow(cells: [
              DataCell(Text(dateTable.format(s.date), style: cell.copyWith(fontWeight: FontWeight.w500))),
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(s.items.map((i) => i.product.name).join(', '),
                    overflow: TextOverflow.ellipsis, style: cell),
              )),
              DataCell(Text('${s.itemCount}', style: cell)),
              DataCell(Text(formatPrice(s.total),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.primary))),
            ]),
        ],
      ),
    );
  }
}
