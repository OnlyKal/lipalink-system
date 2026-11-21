import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/func/export.dart';
import 'add_client_page.dart';

/// Tableau de bord : vue d'ensemble de ce qu'on vous doit et de ce que vous devez.
class DashboardScreen extends StatefulWidget {
  /// Permet d'ouvrir un autre onglet (1 = Clients, 2 = Réglages).
  final ValueChanged<int>? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseHelper dbHelper = DatabaseHelper();

  bool loading = true;
  String devise = 'USD';
  CustomerBalance balance = const CustomerBalance();
  int overdue = 0;
  double? rate;
  String company = '';
  List<Map<String, Object?>> watchlist = [];
  Map<String, List<Map<String, Object?>>> ranking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      dbHelper.getGlobalBalance(),
      dbHelper.countOverdueDebts(),
      dbHelper.getRateValue(),
      dbHelper.getCompany(),
      dbHelper.getWatchlist(),
      dbHelper.getOutstandingByCustomer(kTheyOweMe, 'USD'),
      dbHelper.getOutstandingByCustomer(kTheyOweMe, 'CDF'),
      dbHelper.getOutstandingByCustomer(kIOweThem, 'USD'),
      dbHelper.getOutstandingByCustomer(kIOweThem, 'CDF'),
    ]);
    if (!mounted) return;
    final companyRows = results[3] as List<Map<String, dynamic>>?;
    setState(() {
      balance = results[0] as CustomerBalance;
      overdue = results[1] as int;
      rate = results[2] as double?;
      company = (companyRows != null && companyRows.isNotEmpty)
          ? companyRows.first['nom'].toString()
          : '';
      watchlist = results[4] as List<Map<String, Object?>>;
      ranking = {
        'false|USD': results[5] as List<Map<String, Object?>>,
        'false|CDF': results[6] as List<Map<String, Object?>>,
        'true|USD': results[7] as List<Map<String, Object?>>,
        'true|CDF': results[8] as List<Map<String, Object?>>,
      };
      // Affiche par défaut la devise qui a des montants.
      if (loading &&
          balance.theyOweUSD + balance.iOweUSD <= kMoneyEpsilon &&
          balance.theyOweCDF + balance.iOweCDF > kMoneyEpsilon) {
        devise = 'CDF';
      }
      loading = false;
    });
  }

  double get receivable =>
      devise == 'USD' ? balance.theyOweUSD : balance.theyOweCDF;
  double get payable => devise == 'USD' ? balance.iOweUSD : balance.iOweCDF;

  Future<void> _openCustomer(Map<String, Object?> row) async {
    await goTox(
      context,
      DebtList(
        customerId: row['customerId'] as int,
        customer: row['fullname'].toString(),
      ),
    );
    _load();
  }

  Future<void> _addClient() async {
    final added = await goTox<bool>(context, const AddClientPage());
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 96;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(child: _header()),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottom),
              sliver: SliverList.list(
                children: [
                  FadeSlideIn(child: _heroCard()),
                  if (overdue > 0) ...[
                    const SizedBox(height: 14),
                    FadeSlideIn(index: 1, child: _overdueBanner()),
                  ],
                  const SizedBox(height: 14),
                  FadeSlideIn(index: 2, child: _quickActions()),
                  if (watchlist.isNotEmpty) ...[
                    const SectionTitle('À surveiller'),
                    for (var i = 0; i < watchlist.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FadeSlideIn(
                          index: 3 + i,
                          child: _watchItem(watchlist[i]),
                        ),
                      ),
                  ],
                  _rankingSection(
                    'Ils vous doivent le plus',
                    ranking['false|$devise'] ?? [],
                    context.app.receivable,
                  ),
                  _rankingSection(
                    'Vous leur devez le plus',
                    ranking['true|$devise'] ?? [],
                    context.app.payable,
                  ),
                  if (!loading && balance.isEmpty && watchlist.isEmpty) ...[
                    const SizedBox(height: 24),
                    FadeSlideIn(index: 3, child: _emptyHint()),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Sections

  Widget _header() {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Bonjour'
        : now.hour < 18
        ? 'Bon après-midi'
        : 'Bonsoir';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE d MMMM', 'fr').format(now).toUpperCase(),
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(greeting, style: context.text.headlineMedium),
              if (company.isNotEmpty)
                Text(
                  capitalizeString(company.toLowerCase()),
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const ThemeToggleButton(),
      ],
    );
  }

  Widget _heroCard() {
    final app = context.app;
    final net = receivable - payable;
    final total = receivable + payable;
    const payableOnGradient = Color(0xFFC4B5FD);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDark
              ? const [Color(0xFF312E81), Color(0xFF1E1B4B), Color(0xFF0C4A6E)]
              : const [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF0EA5E9)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.28),
            blurRadius: 32,
            spreadRadius: -10,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SOLDE NET',
                style: context.text.labelMedium?.copyWith(
                  color: Colors.white70,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              _CurrencySwitch(
                value: devise,
                onChanged: (v) => setState(() => devise = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedAmount(
            key: ValueKey('net$devise${net.toStringAsFixed(2)}'),
            value: net,
            devise: devise,
            style: context.text.displaySmall?.copyWith(color: Colors.white),
            deviseStyle: context.text.titleMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            total <= kMoneyEpsilon
                ? 'Aucune dette en cours en $devise'
                : net >= 0
                ? 'On vous doit plus que vous ne devez'
                : 'Vous devez plus que ce qu\'on vous doit',
            style: context.text.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          if (total > kMoneyEpsilon) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  if (receivable > kMoneyEpsilon)
                    Expanded(
                      flex: (receivable / total * 1000).round().clamp(1, 1000),
                      child: Container(height: 8, color: app.receivable),
                    ),
                  if (receivable > kMoneyEpsilon && payable > kMoneyEpsilon)
                    const SizedBox(width: 3),
                  if (payable > kMoneyEpsilon)
                    Expanded(
                      flex: (payable / total * 1000).round().clamp(1, 1000),
                      child: Container(height: 8, color: payableOnGradient),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: _heroFigure(
                  'On vous doit',
                  receivable,
                  app.receivable,
                  CupertinoIcons.arrow_down_left,
                ),
              ),
              Container(width: 1, height: 44, color: Colors.white24),
              const SizedBox(width: 16),
              Expanded(
                child: _heroFigure(
                  'Vous devez',
                  payable,
                  payableOnGradient,
                  CupertinoIcons.arrow_up_right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroFigure(String label, double value, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedAmount(
          key: ValueKey('$label$devise${value.toStringAsFixed(2)}'),
          value: value,
          devise: devise,
          style: context.text.titleLarge?.copyWith(color: Colors.white),
          deviseStyle: context.text.labelSmall?.copyWith(color: Colors.white60),
        ),
      ],
    );
  }

  Widget _overdueBanner() {
    final danger = context.app.danger;
    return GlassCard(
      tint: danger,
      border: Border.all(color: danger.withValues(alpha: 0.35)),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconBadge(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: danger,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overdue == 1
                      ? '1 dette en retard'
                      : '$overdue dettes en retard',
                  style: context.text.titleMedium?.copyWith(color: danger),
                ),
                Text(
                  'Leur échéance est dépassée : relancez ou ajustez la date.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: CupertinoIcons.person_badge_plus,
            label: 'Nouveau',
            caption: 'client',
            color: context.colors.primary,
            onTap: _addClient,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickAction(
            icon: CupertinoIcons.person_2,
            label: 'Mes clients',
            caption: 'Dettes, paiements',
            color: context.app.receivable,
            onTap: () => widget.onNavigate?.call(1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickAction(
            icon: CupertinoIcons.arrow_2_squarepath,
            label: rate == null ? 'Taux' : formatAmount(rate!),
            caption: 'CDF / USD',
            color: context.app.warning,
            onTap: () => widget.onNavigate?.call(2),
          ),
        ),
      ],
    );
  }

  Widget _watchItem(Map<String, Object?> row) {
    final app = context.app;
    final days = daysUntil(row['dueDate']);
    final iOwe = row['own'].toString() == kIOweThem;
    final color = days < 0 ? app.danger : app.warning;

    return GlassCard(
      onTap: () => _openCustomer(row),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          InitialsAvatar(row['fullname'].toString(), size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  capitalizeString(row['fullname'].toString()),
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  sentenceCase(row['motif'].toString()),
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                StatusPill(
                  label: dueLabel(days),
                  color: color,
                  icon: CupertinoIcons.clock,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatAmount(toAmount(row['rest'])),
                style: context.text.titleMedium?.copyWith(
                  color: iOwe ? app.payable : app.receivable,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '${row['devise']} · ${iOwe ? 'à payer' : 'à recevoir'}',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rankingSection(
    String title,
    List<Map<String, Object?>> rows,
    Color color,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final top = rows.take(5).toList();
    final max = toAmount(top.first['total']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title,
          trailing: StatusPill(label: devise, color: color),
        ),
        FadeSlideIn(
          index: 4,
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Column(
              children: [
                for (final row in top)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                capitalizeString(row['fullname'].toString()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              formatAmount(toAmount(row['total'])),
                              style: context.text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ProgressBar(
                          value: max <= 0 ? 0 : toAmount(row['total']) / max,
                          color: color,
                          height: 6,
                        ),
                      ],
                    ),
                  ),
                if (rows.length > top.length)
                  TextButton(
                    onPressed: () => widget.onNavigate?.call(1),
                    child: Text('Voir les ${rows.length} clients'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyHint() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          IconBadge(
            CupertinoIcons.sparkles,
            color: context.colors.primary,
            size: 56,
          ),
          const SizedBox(height: 14),
          Text('Tout est à jour', style: context.text.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Aucune dette en cours. Ajoutez un client pour enregistrer votre première dette.',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _addClient,
            icon: const Icon(CupertinoIcons.person_badge_plus),
            label: const Text('Ajouter un client'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Widgets

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, color: color, size: 40),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencySwitch extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _CurrencySwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in const ['USD', 'CDF'])
            GestureDetector(
              onTap: () => onChanged(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: value == d ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  d,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: value == d ? const Color(0xFF312E81) : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
