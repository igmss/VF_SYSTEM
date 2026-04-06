import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────

const _kBlue  = Color(0xFF4CC9F0);
const _kGreen = Color(0xFF4ADE80);
const _kRed   = Color(0xFFE63946);
const _kAmber = Color(0xFFFBBF24);

// ─── Period filter options ────────────────────────────────────────────────────

enum _Period { today, week, month, all }

extension _PeriodLabel on _Period {
  String get label {
    switch (this) {
      case _Period.today: return 'Today';
      case _Period.week:  return '7D';
      case _Period.month: return '30D';
      case _Period.all:   return 'All';
    }
  }

  DateTime? get cutoff {
    final now = DateTime.now();
    switch (this) {
      case _Period.today:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        return now.subtract(const Duration(days: 7));
      case _Period.month:
        return now.subtract(const Duration(days: 30));
      case _Period.all:
        return null;
    }
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _PricePoint {
  final double price;
  final String side; // 'buy' or 'sell'
  final DateTime time;
  _PricePoint({required this.price, required this.side, required this.time});
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ExchangeRateScreen extends StatefulWidget {
  const ExchangeRateScreen({Key? key}) : super(key: key);

  @override
  State<ExchangeRateScreen> createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends State<ExchangeRateScreen> {
  final _db = FirebaseDatabase.instance;

  /// All loaded points (unfiltered)
  List<_PricePoint> _allPoints = [];

  bool _loading = true;
  String? _error;
  _Period _period = _Period.week;

  // ── derived filtered list ──────────────────────────────────────────────────
  List<_PricePoint> get _points {
    final cutoff = _period.cutoff;
    if (cutoff == null) return _allPoints;
    return _allPoints.where((p) => p.time.isAfter(cutoff)).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _db.ref('financial_ledger').get();
      if (!snap.exists || snap.value == null) {
        setState(() => _loading = false);
        return;
      }

      final map = Map<String, dynamic>.from(snap.value as Map);
      final list = <_PricePoint>[];

      for (final v in map.values) {
        if (v is! Map) continue;
        final row = Map<String, dynamic>.from(v);

        final type = row['type']?.toString() ?? '';
        if (type != 'BUY_USDT' && type != 'SELL_USDT') continue;

        final rawPrice = row['usdtPrice'];
        if (rawPrice == null) continue;
        final price = (rawPrice as num).toDouble();
        if (price <= 0) continue;

        final ts = row['timestamp'];
        DateTime time;
        if (ts is int) {
          time = DateTime.fromMillisecondsSinceEpoch(ts);
        } else {
          time = DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
        }

        list.add(_PricePoint(
          price: price,
          side: type == 'BUY_USDT' ? 'buy' : 'sell',
          time: time,
        ));
      }

      list.sort((a, b) => a.time.compareTo(b.time));

      setState(() {
        _allPoints = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isEmbedded = auth.isAdmin || auth.isFinance;

    final bodyContent = _loading
        ? const Center(child: CircularProgressIndicator(color: _kBlue))
        : _error != null
            ? _buildError()
            : _buildContent();

    if (isEmbedded) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        body: bodyContent,
      );
    } else {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.surfaceColor(context),
          iconTheme: IconThemeData(color: AppTheme.textPrimaryColor(context)),
          title: Text(
            'EGP / USDT Rate',
            style: TextStyle(
                color: AppTheme.textPrimaryColor(context),
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh,
                  color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7)),
              onPressed: _loadHistory,
            ),
          ],
        ),
        body: bodyContent,
      );
    }
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: _kRed),
            const SizedBox(height: 12),
            Text('Could not load rate history.',
                style: TextStyle(color: AppTheme.textMutedColor(context))),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadHistory,
              child: const Text('Retry', style: TextStyle(color: _kBlue)),
            ),
          ],
        ),
      );

  // ── Period filter bar ─────────────────────────────────────────────────────

  Widget _buildPeriodBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: _Period.values.map((p) {
        final selected = p == _period;
        return GestureDetector(
          onTap: () => setState(() => _period = p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? _kBlue.withOpacity(0.18)
                  : AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? _kBlue.withOpacity(0.55)
                    : AppTheme.textPrimaryColor(context).withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              p.label,
              style: TextStyle(
                color: selected
                    ? _kBlue
                    : AppTheme.textMutedColor(context),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _buildContent() {
    final pts = _points;
    final fmt = NumberFormat('#,##0.00', 'en_US');

    // ── compute buy / sell averages ────────────────────────────────────
    final buyPts  = pts.where((p) => p.side == 'buy').toList();
    final sellPts = pts.where((p) => p.side == 'sell').toList();

    final avgBuy  = buyPts.isEmpty
        ? null
        : buyPts.map((p) => p.price).reduce((a, b) => a + b) / buyPts.length;
    final avgSell = sellPts.isEmpty
        ? null
        : sellPts.map((p) => p.price).reduce((a, b) => a + b) / sellPts.length;

    // ── overall stats ──────────────────────────────────────────────────
    final allPrices = pts.map((p) => p.price).toList();
    final hasData   = allPrices.isNotEmpty;
    final minP  = hasData ? allPrices.reduce((a, b) => a < b ? a : b) : 0.0;
    final maxP  = hasData ? allPrices.reduce((a, b) => a > b ? a : b) : 0.0;
    final lastP = hasData ? pts.last.price : 0.0;
    final lastSide = hasData ? pts.last.side : 'buy';

    // ── date range label ───────────────────────────────────────────────
    String rangeLabel = _period.label;
    if (hasData) {
      final daySpan = pts.last.time.difference(pts.first.time).inDays;
      if (_period == _Period.all) {
        rangeLabel = daySpan == 0 ? 'Today' : 'Last $daySpan days';
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: refresh + period filter ──────────────────────────
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16, color: _kBlue),
                label: const Text('Refresh',
                    style: TextStyle(color: _kBlue, fontSize: 12)),
                onPressed: _loadHistory,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Spacer(),
              _buildPeriodBar(),
            ],
          ),
          const SizedBox(height: 6),

          // ── Orders chip ───────────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBlue.withOpacity(0.25)),
              ),
              child: Text(
                '$rangeLabel — ${pts.length} orders',
                style: const TextStyle(
                    color: _kBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (!hasData) ...[
            _buildEmptyPeriod(),
          ] else ...[
            // ── Row 1: Current + High ──────────────────────────────────
            Row(children: [
              _StatCard('Current',
                  '${fmt.format(lastP)} EGP',
                  lastSide == 'buy' ? _kBlue : _kGreen,
                  Icons.attach_money),
              const SizedBox(width: 10),
              _StatCard('High',
                  '${fmt.format(maxP)} EGP',
                  _kGreen,
                  Icons.arrow_upward_rounded),
            ]),
            const SizedBox(height: 10),

            // ── Row 2: Low + Avg Buy ───────────────────────────────────
            Row(children: [
              _StatCard('Low',
                  '${fmt.format(minP)} EGP',
                  _kRed,
                  Icons.arrow_downward_rounded),
              const SizedBox(width: 10),
              _StatCard(
                'Avg Buy',
                avgBuy != null
                    ? '${fmt.format(avgBuy)} EGP'
                    : '— EGP',
                _kBlue,
                Icons.south_west_rounded,
              ),
            ]),
            const SizedBox(height: 10),

            // ── Row 3: Avg Sell (full width) ───────────────────────────
            Row(children: [
              _StatCard(
                'Avg Sell',
                avgSell != null
                    ? '${fmt.format(avgSell)} EGP'
                    : '— EGP',
                _kGreen,
                Icons.north_east_rounded,
              ),
              const SizedBox(width: 10),
              // Spread card (Avg Sell – Avg Buy)
              _StatCard(
                'Spread',
                (avgBuy != null && avgSell != null)
                    ? '${fmt.format((avgSell - avgBuy).abs())} EGP'
                    : '— EGP',
                _kAmber,
                Icons.swap_horiz_rounded,
              ),
            ]),

            const SizedBox(height: 24),

            // ── Chart ─────────────────────────────────────────────────
            Row(
              children: [
                Text('Price Chart',
                    style: TextStyle(
                        color: AppTheme.textPrimaryColor(context),
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(rangeLabel,
                    style: TextStyle(
                        color: AppTheme.textMutedColor(context), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: AppTheme.textPrimaryColor(context)
                        .withValues(alpha: 0.06)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: pts.length < 2
                  ? Center(
                      child: Text(
                        'Need at least 2 data points to draw a chart.',
                        style: TextStyle(
                            color: AppTheme.textMutedColor(context),
                            fontSize: 12),
                      ))
                  : CustomPaint(
                      size: const Size(double.infinity, double.infinity),
                      painter: _LinePainter(
                        points: pts,
                        minPrice: minP,
                        maxPrice: maxP,
                        avgBuy: avgBuy,
                        avgSell: avgSell,
                        textColor: AppTheme.textPrimaryColor(context),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            // X-axis labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('d MMM').format(pts.first.time),
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context)
                          .withValues(alpha: 0.6),
                      fontSize: 10),
                ),
                Text(
                  DateFormat('d MMM HH:mm').format(pts.last.time),
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context)
                          .withValues(alpha: 0.6),
                      fontSize: 10),
                ),
              ],
            ),

            // ── Chart legend ───────────────────────────────────────────
            const SizedBox(height: 8),
            Row(
              children: [
                _LegendDot(color: _kBlue,  label: 'Buy'),
                const SizedBox(width: 16),
                _LegendDot(color: _kGreen, label: 'Sell'),
                if (avgBuy != null) ...[
                  const SizedBox(width: 16),
                  _LegendDash(color: _kBlue.withOpacity(0.6), label: 'Avg Buy'),
                ],
                if (avgSell != null) ...[
                  const SizedBox(width: 16),
                  _LegendDash(color: _kGreen.withOpacity(0.6), label: 'Avg Sell'),
                ],
              ],
            ),

            const SizedBox(height: 28),

            // ── Recent Orders ──────────────────────────────────────────
            Text('Orders (${pts.length})',
                style: TextStyle(
                    color: AppTheme.textPrimaryColor(context),
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...pts.reversed.take(50).map((p) => _buildPriceRow(p, fmt)),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyPeriod() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.show_chart,
                  size: 60,
                  color: AppTheme.textPrimaryColor(context)
                      .withValues(alpha: 0.08)),
              const SizedBox(height: 16),
              Text('No data for this period.',
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 16)),
              const SizedBox(height: 6),
              Text('Try a wider period or sync more orders.',
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context)
                          .withValues(alpha: 0.6),
                      fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _buildPriceRow(_PricePoint p, NumberFormat fmt) {
    final isBuy = p.side == 'buy';
    final color = isBuy ? _kBlue : _kGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isBuy
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              color: color,
              size: 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBuy ? 'Buy USDT' : 'Sell USDT',
                  style: TextStyle(
                      color: AppTheme.textPrimaryColor(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(p.time),
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${fmt.format(p.price)} EGP/USDT',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Legend helpers ───────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: AppTheme.textMutedColor(context), fontSize: 10)),
        ],
      );
}

class _LegendDash extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDash({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 14, height: 2, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: AppTheme.textMutedColor(context), fontSize: 10)),
        ],
      );
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatCard(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: AppTheme.textMutedColor(context),
                          fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Smooth Line Chart ────────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  final List<_PricePoint> points;
  final double minPrice;
  final double maxPrice;
  final double? avgBuy;
  final double? avgSell;
  final Color textColor;

  _LinePainter({
    required this.points,
    required this.minPrice,
    required this.maxPrice,
    this.avgBuy,
    this.avgSell,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final range = (maxPrice - minPrice).abs();
    final priceRange = range == 0 ? 1.0 : range;
    const padding = 8.0;

    Offset toOffset(int i, double price) {
      final x = (i / (points.length - 1)) * (size.width - padding * 2) + padding;
      final y = (size.height - padding) -
          ((price - minPrice) / priceRange) * (size.height - padding * 2);
      return Offset(x, y);
    }

    double priceToY(double price) =>
        (size.height - padding) -
        ((price - minPrice) / priceRange) * (size.height - padding * 2);

    // ── Grid lines ────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = textColor.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (final yFrac in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final y = (size.height - padding) - yFrac * (size.height - padding * 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── Avg Buy dashed line ───────────────────────────────────────────
    if (avgBuy != null && avgBuy! >= minPrice && avgBuy! <= maxPrice) {
      _drawDashedHLine(
          canvas, size, priceToY(avgBuy!), _kBlue.withOpacity(0.55));
    }

    // ── Avg Sell dashed line ──────────────────────────────────────────
    if (avgSell != null && avgSell! >= minPrice && avgSell! <= maxPrice) {
      _drawDashedHLine(
          canvas, size, priceToY(avgSell!), _kGreen.withOpacity(0.55));
    }

    // ── Gradient fill ─────────────────────────────────────────────────
    final fillPath = Path()..moveTo(padding, size.height);
    for (int i = 0; i < points.length; i++) {
      final o = toOffset(i, points[i].price);
      if (i == 0) {
        fillPath.lineTo(o.dx, o.dy);
      } else {
        final prev = toOffset(i - 1, points[i - 1].price);
        final cx = (prev.dx + o.dx) / 2;
        fillPath.cubicTo(cx, prev.dy, cx, o.dy, o.dx, o.dy);
      }
    }
    fillPath.lineTo(size.width - padding, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [_kBlue.withOpacity(0.22), _kBlue.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // ── Line (coloured by side) ───────────────────────────────────────
    for (int i = 1; i < points.length; i++) {
      final isBuy = points[i].side == 'buy';
      final segColor = isBuy ? _kBlue : _kGreen;
      final prev = toOffset(i - 1, points[i - 1].price);
      final curr = toOffset(i, points[i].price);
      final cx = (prev.dx + curr.dx) / 2;
      final segPath = Path()
        ..moveTo(prev.dx, prev.dy)
        ..cubicTo(cx, prev.dy, cx, curr.dy, curr.dx, curr.dy);
      canvas.drawPath(
        segPath,
        Paint()
          ..color = segColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── Dot on last point ─────────────────────────────────────────────
    final lastColor =
        points.last.side == 'buy' ? _kBlue : _kGreen;
    final last = toOffset(points.length - 1, points.last.price);
    canvas.drawCircle(last, 5, Paint()..color = lastColor);
    canvas.drawCircle(
      last,
      5,
      Paint()
        ..color = textColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawDashedHLine(
      Canvas canvas, Size size, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0;
    const gapWidth = 5.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points ||
      old.minPrice != minPrice ||
      old.maxPrice != maxPrice ||
      old.avgBuy != avgBuy ||
      old.avgSell != avgSell;
}
