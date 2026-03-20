import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0F0F1A);
const _kSurface = Color(0xFF16162A);
const _kBlue    = Color(0xFF4CC9F0);
const _kGreen   = Color(0xFF4ADE80);
const _kRed     = Color(0xFFE63946);
const _kAmber   = Color(0xFFFBBF24);

class _PricePoint {
  final double price;
  final String side; // 'buy' or 'sell'
  final DateTime time;
  _PricePoint({required this.price, required this.side, required this.time});
}

class ExchangeRateScreen extends StatefulWidget {
  const ExchangeRateScreen({Key? key}) : super(key: key);

  @override
  State<ExchangeRateScreen> createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends State<ExchangeRateScreen> {
  final _db = FirebaseDatabase.instance;
  List<_PricePoint> _points = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = null; });
    try {
      // ── Read from financial_ledger — all BUY_USDT and SELL_USDT entries
      // that have a usdtPrice. This uses existing data immediately.
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

        // Must have a usdtPrice
        final rawPrice = row['usdtPrice'];
        if (rawPrice == null) continue;
        final price = (rawPrice as num).toDouble();
        if (price <= 0) continue;

        // Parse timestamp
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

      // Sort chronologically
      list.sort((a, b) => a.time.compareTo(b.time));

      // Take last 7 days only
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final filtered = list.where((p) => p.time.isAfter(cutoff)).toList();

      setState(() {
        // If last 7 days is empty, show all available data instead
        _points = filtered.isNotEmpty ? filtered : list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'EGP / USDT Rate',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kBlue))
          : _error != null
              ? _buildError()
              : _points.isEmpty
                  ? _buildEmpty()
                  : _buildContent(),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: _kRed),
            const SizedBox(height: 12),
            const Text('Could not load rate history.',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadHistory,
              child: const Text('Retry', style: TextStyle(color: _kBlue)),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 60, color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 16),
            const Text('No price data found.',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Sync a Bybit order to start tracking.',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ),
      );

  Widget _buildContent() {
    final prices = _points.map((p) => p.price).toList();
    final minP   = prices.reduce((a, b) => a < b ? a : b);
    final maxP   = prices.reduce((a, b) => a > b ? a : b);
    final avgP   = prices.reduce((a, b) => a + b) / prices.length;
    final lastP  = _points.last.price;
    final lastSide = _points.last.side;
    final fmt = NumberFormat('#,##0.00', 'en_US');

    // Date range label
    final earliest = _points.first.time;
    final latest   = _points.last.time;
    final daySpan  = latest.difference(earliest).inDays;
    final rangeLabel = daySpan == 0 ? 'Today' : 'Last $daySpan day${daySpan == 1 ? '' : 's'}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Data range chip ──────────────────────────────────────────
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
                '$rangeLabel — ${_points.length} orders',
                style: const TextStyle(color: _kBlue, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Stats Row ─────────────────────────────────────────────────
          Row(children: [
            _StatCard('Current', '${fmt.format(lastP)} EGP',
                lastSide == 'buy' ? _kBlue : _kGreen, Icons.attach_money),
            const SizedBox(width: 10),
            _StatCard('High', '${fmt.format(maxP)} EGP',
                _kGreen, Icons.arrow_upward_rounded),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _StatCard('Low', '${fmt.format(minP)} EGP',
                _kRed, Icons.arrow_downward_rounded),
            const SizedBox(width: 10),
            _StatCard('Avg', '${fmt.format(avgP)} EGP',
                _kAmber, Icons.analytics_outlined),
          ]),

          const SizedBox(height: 24),

          // ── Chart ─────────────────────────────────────────────────────
          Row(
            children: [
              const Text('Price Chart',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(rangeLabel,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: _points.length < 2
                ? const Center(
                    child: Text(
                      'Need at least 2 data points to draw a chart.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ))
                : CustomPaint(
                    size: const Size(double.infinity, double.infinity),
                    painter: _LinePainter(
                      points: _points,
                      minPrice: minP,
                      maxPrice: maxP,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          // X-axis labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('d MMM').format(_points.first.time),
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
              Text(DateFormat('d MMM HH:mm').format(_points.last.time),
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),

          const SizedBox(height: 28),

          // ── Recent Orders ─────────────────────────────────────────────
          Text('Recent Orders (${_points.length})',
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._points.reversed.take(30).map((p) => _buildPriceRow(p, fmt)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPriceRow(_PricePoint p, NumberFormat fmt) {
    final isBuy = p.side == 'buy';
    final color = isBuy ? _kBlue : _kGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _kSurface,
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
              isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: color, size: 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBuy ? 'Buy USDT' : 'Sell USDT',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(p.time),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${fmt.format(p.price)} EGP/USDT',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
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
          color: _kSurface,
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
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold, fontSize: 13),
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

// ─── Smooth Line Chart ─────────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  final List<_PricePoint> points;
  final double minPrice;
  final double maxPrice;

  _LinePainter({required this.points, required this.minPrice, required this.maxPrice});

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

    // ── Grid lines (min / max / mid) ──────────────────────────────────
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    for (final yFrac in [0.0, 0.5, 1.0]) {
      final y = (size.height - padding) - yFrac * (size.height - padding * 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
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
          colors: [
            _kBlue.withOpacity(0.28),
            _kBlue.withOpacity(0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // ── Line ──────────────────────────────────────────────────────────
    final linePath = Path();
    for (int i = 0; i < points.length; i++) {
      final o = toOffset(i, points[i].price);
      if (i == 0) {
        linePath.moveTo(o.dx, o.dy);
      } else {
        final prev = toOffset(i - 1, points[i - 1].price);
        final cx = (prev.dx + o.dx) / 2;
        linePath.cubicTo(cx, prev.dy, cx, o.dy, o.dx, o.dy);
      }
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = _kBlue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Dot on last point ─────────────────────────────────────────────
    final last = toOffset(points.length - 1, points.last.price);
    canvas.drawCircle(last, 5, Paint()..color = _kBlue);
    canvas.drawCircle(
      last, 5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points || old.minPrice != minPrice || old.maxPrice != maxPrice;
}
