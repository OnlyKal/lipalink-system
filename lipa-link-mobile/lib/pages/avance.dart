import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '/classes/Avance.dart';
import '../func/export.dart';

/// Paiements (avances) d'une dette.
/// Retourne `true` à l'écran précédent si quelque chose a changé.
class AvanceList extends StatefulWidget {
  final int debtId;
  final String debtDevise;
  final int customerId;
  final String? own;
  final String? customer;

  const AvanceList({
    super.key,
    required this.debtId,
    required this.debtDevise,
    required this.customerId,
    this.own,
    this.customer,
  });

  @override
  State<AvanceList> createState() => _AvanceListState();
}

class _AvanceListState extends State<AvanceList> {
  final DatabaseHelper dbHelper = DatabaseHelper();
  late final ConfettiController _confetti = ConfettiController(
    duration: const Duration(seconds: 2),
  );

  List<Avance> avances = [];
  Map<String, Object?>? debt;
  double? rate;
  bool changed = false;

  String get devise => widget.debtDevise;
  double get amount => toAmount(debt?['borrowedAmount']);
  double get paid => toAmount(debt?['paid']);
  double get rest => math.max(0, toAmount(debt?['rest']));
  bool get isSettled => debt != null && rest <= kMoneyEpsilon;
  bool get iOwe => (debt?['own'] ?? widget.own).toString() == kIOweThem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      dbHelper.getAvance(widget.debtId),
      dbHelper.getDebtBalance(widget.debtId),
      dbHelper.getRateValue(),
    ]);
    if (!mounted) return;
    setState(() {
      avances = results[0] as List<Avance>;
      debt = results[1] as Map<String, Object?>?;
      rate = results[2] as double?;
    });
  }

  Future<void> _addAvance(double value) async {
    final result = await dbHelper.addAvance(widget.debtId, value);
    if (!mounted) return;
    messageInfo(context, result.message, !result.ok);
    if (result.ok) {
      changed = true;
      if (result.closed) _confetti.play();
      await _load();
    }
  }

  Future<void> _deleteAvance(Avance avance) async {
    final ok = await confirmAction(
      context,
      title: 'Supprimer ce paiement ?',
      message:
          '${formatMoney(avance.amount, avance.devise)} du ${convertDate(avance.paidDate)}.\n'
          'Le reste à payer augmentera d\'autant'
          '${isSettled ? ' et la dette sera rouverte' : ''}.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    await dbHelper.deleteAvance(avance.id!);
    changed = true;
    await _load();
    if (mounted) messageInfo(context, 'Paiement supprimé', false);
  }

  void _close() => Navigator.pop(context, changed);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        body: AmbientBackground(
          child: Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverSafeArea(
                    bottom: false,
                    sliver: SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: _close,
                              icon: const Icon(CupertinoIcons.back),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                capitalizeString(widget.customer ?? ''),
                                style: context.text.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (debt == null)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      sliver: SliverList.list(
                        children: [
                          FadeSlideIn(child: _hero()),
                          const SizedBox(height: 14),
                          FadeSlideIn(index: 1, child: _figures()),
                          SectionTitle(
                            avances.isEmpty
                                ? 'Paiements'
                                : 'Paiements · ${avances.length}',
                          ),
                        ],
                      ),
                    ),
                    if (avances.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: FadeSlideIn(
                            index: 2,
                            child: GlassCard(
                              child: Row(
                                children: [
                                  IconBadge(
                                    CupertinoIcons.hourglass,
                                    color: context.app.muted,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Aucun paiement pour l\'instant.',
                                      style: context.text.bodyMedium?.copyWith(
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          MediaQuery.paddingOf(context).bottom + 110,
                        ),
                        sliver: SliverList.builder(
                          itemCount: avances.length,
                          itemBuilder: (context, i) => FadeSlideIn(
                            key: ValueKey(avances[i].id),
                            index: 2 + i,
                            child: _timelineItem(
                              avances[i],
                              first: i == 0,
                              last: i == avances.length - 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confetti,
                  blastDirectionality: BlastDirectionality.explosive,
                  numberOfParticles: 28,
                  gravity: 0.25,
                  colors: [
                    context.app.success,
                    context.app.receivable,
                    context.colors.primary,
                    context.app.warning,
                    context.app.payable,
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          scale: debt != null && !isSettled ? 1 : 0,
          child: FloatingActionButton.extended(
            heroTag: 'add-payment',
            onPressed: _showAddSheet,
            icon: const Icon(CupertinoIcons.add),
            label: const Text('Ajouter un paiement'),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Héros

  Widget _hero() {
    final app = context.app;
    final progress = amount <= 0 ? 0.0 : (paid / amount).clamp(0.0, 1.0);
    final color = isSettled
        ? app.success
        : (iOwe ? app.payable : app.receivable);
    final days = daysUntil(debt!['dueDate']);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _ProgressRing(progress: progress, color: color, settled: isSettled),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sentenceCase(debt!['motif']?.toString() ?? ''),
                  style: context.text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(
                      label: iOwe ? 'Vous devez' : 'On vous doit',
                      color: iOwe ? app.payable : app.receivable,
                      icon: iOwe
                          ? CupertinoIcons.arrow_up_right
                          : CupertinoIcons.arrow_down_left,
                    ),
                    StatusPill(
                      label: isSettled ? 'Réglée' : dueLabel(days),
                      color: isSettled
                          ? app.success
                          : days < 0
                          ? app.danger
                          : days <= 3
                          ? app.warning
                          : context.colors.primary,
                      icon: isSettled
                          ? CupertinoIcons.checkmark_seal_fill
                          : CupertinoIcons.clock,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Échéance : ${convertDate(debt!['dueDate'])}',
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Créée le ${convertDate(debt!['todayDate'])}',
                  style: context.text.labelMedium?.copyWith(
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

  Widget _figures() {
    final app = context.app;
    return Row(
      children: [
        Expanded(child: _figure('Montant', amount, context.colors.primary)),
        const SizedBox(width: 10),
        Expanded(child: _figure('Payé', paid, app.success)),
        const SizedBox(width: 10),
        Expanded(
          child: _figure('Reste', rest, isSettled ? app.success : app.danger),
        ),
      ],
    );
  }

  Widget _figure(String label, double value, Color color) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              key: ValueKey('$label${value.toStringAsFixed(2)}'),
              value: value,
              devise: devise,
              style: context.text.titleMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Frise

  Widget _timelineItem(
    Avance avance, {
    required bool first,
    required bool last,
  }) {
    final app = context.app;
    final line = context.colors.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: first ? Colors.transparent : line,
                  ),
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: app.success,
                    boxShadow: [
                      BoxShadow(
                        color: app.success.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: last ? Colors.transparent : line,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: Slidable(
                  key: ValueKey(avance.id),
                  endActionPane: ActionPane(
                    motion: const BehindMotion(),
                    extentRatio: 0.32,
                    children: [
                      SlidableAction(
                        onPressed: (_) => _deleteAvance(avance),
                        backgroundColor: app.danger,
                        foregroundColor: Colors.white,
                        icon: CupertinoIcons.trash,
                        label: 'Supprimer',
                      ),
                    ],
                  ),
                  child: GlassCard(
                    onLongPress: () => _deleteAvance(avance),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                convertDate(avance.paidDate),
                                style: context.text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'à ${DateFormat('HH:mm', 'fr').format(avance.paidDate)}',
                                style: context.text.labelSmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '+ ${formatMoney(avance.amount, avance.devise)}',
                          style: context.text.titleMedium?.copyWith(
                            color: app.success,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Ajout

  void _showAddSheet() {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String equivalent(String text) {
      final value = parseAmount(text);
      if (value == null || value <= 0 || rate == null) return '';
      return devise == 'USD'
          ? '≈ ${formatMoney(value * rate!, 'CDF')}'
          : '≈ ${formatMoney(value / rate!, 'USD')}';
    }

    showAppSheet(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                'Nouveau paiement',
                subtitle: 'Reste à payer : ${formatMoney(rest, devise)}',
              ),
              AmountField(
                controller: controller,
                devise: devise,
                autofocus: true,
                helper: equivalent(controller.text),
                onChanged: (_) => setSheetState(() {}),
                validator: (value) {
                  final parsed = parseAmount(value);
                  if (parsed == null) return 'Montant invalide';
                  if (parsed <= 0) return 'Le montant doit être positif';
                  if (parsed > rest + kMoneyEpsilon) {
                    return 'Maximum : ${formatMoney(rest, devise)}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final (label, ratio) in const [
                    ('25 %', 0.25),
                    ('50 %', 0.5),
                    ('Tout le reste', 1.0),
                  ])
                    ActionChip(
                      label: Text(label),
                      onPressed: () => setSheetState(() {
                        controller.text = roundMoney(rest * ratio).toString();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final value = parseAmount(controller.text)!;
                  Navigator.pop(sheetContext);
                  _addAvance(value);
                },
                icon: const Icon(CupertinoIcons.check_mark),
                label: const Text('Enregistrer le paiement'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Anneau de progression animé avec le pourcentage au centre.
class _ProgressRing extends StatelessWidget {
  final double progress;
  final Color color;
  final bool settled;

  const _ProgressRing({
    required this.progress,
    required this.color,
    required this.settled,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox(
        width: 104,
        height: 104,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 10,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: context.colors.onSurface.withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            settled
                ? Icon(CupertinoIcons.checkmark_alt, size: 40, color: color)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(value * 100).round()}%',
                        style: context.text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'payé',
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
