import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../func/export.dart';

enum _DebtFilter { open, late, settled, all }

/// Dettes d'un client (dans les deux sens).
class DebtList extends StatefulWidget {
  final int customerId;
  final String customer;
  const DebtList({super.key, required this.customerId, required this.customer});

  @override
  DebtListState createState() => DebtListState();
}

class DebtListState extends State<DebtList> {
  final DatabaseHelper dbHelper = DatabaseHelper();
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> debts = [];
  CustomerBalance balance = const CustomerBalance();
  double? rate;
  bool isLoading = true;
  bool showSearch = false;
  late var filter = operationIsMasked ? _DebtFilter.open : _DebtFilter.all;

  bool isMultiSelectMode = false;
  Set<int> selectedDebtIds = {};

  @override
  void initState() {
    super.initState();
    _loadDebts();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDebts() async {
    final results = await Future.wait<Object?>([
      dbHelper.getDebtsOptimized(widget.customerId, 0, -1),
      dbHelper.getRateValue(),
      dbHelper.getCustomerBalance(widget.customerId),
    ]);
    if (!mounted) return;
    setState(() {
      debts = List<Map<String, dynamic>>.from(results[0] as List);
      rate = results[1] as double?;
      balance = results[2] as CustomerBalance;
      isLoading = false;
    });
  }

  static bool _isSettled(Map<String, dynamic> debt) =>
      toAmount(debt['reste_a_payer']) <= kMoneyEpsilon;

  static bool _isLate(Map<String, dynamic> debt) =>
      !_isSettled(debt) && daysUntil(debt['dueDate']) < 0;

  int _count(_DebtFilter f) => debts.where((d) => _matches(d, f)).length;

  bool _matches(Map<String, dynamic> d, _DebtFilter f) => switch (f) {
    _DebtFilter.open => !_isSettled(d),
    _DebtFilter.late => _isLate(d),
    _DebtFilter.settled => _isSettled(d),
    _DebtFilter.all => true,
  };

  List<Map<String, dynamic>> get visibleDebts {
    final query = searchController.text.trim().toLowerCase();
    return debts.where((d) {
      if (!_matches(d, filter)) return false;
      return query.isEmpty ||
          d['motif'].toString().toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openAvances(Map<String, dynamic> debt) async {
    final changed = await goTox<bool>(
      context,
      AvanceList(
        debtId: debt['id'] as int,
        debtDevise: debt['devise'].toString(),
        customerId: widget.customerId,
        own: debt['own']?.toString(),
        customer: widget.customer,
      ),
    );
    if (changed == true) _loadDebts();
  }

  void _toggleSelection(int id) {
    setState(() {
      selectedDebtIds.contains(id)
          ? selectedDebtIds.remove(id)
          : selectedDebtIds.add(id);
      if (selectedDebtIds.isEmpty) isMultiSelectMode = false;
    });
  }

  void _exitSelection() => setState(() {
    isMultiSelectMode = false;
    selectedDebtIds.clear();
  });

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final list = visibleDebts;

    return PopScope(
      canPop: !isMultiSelectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
        body: AmbientBackground(
          child: RefreshIndicator(
            onRefresh: _loadDebts,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: isMultiSelectMode
                            ? _selectionBar(list)
                            : _topBar(),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverList.list(
                    children: [
                      FadeSlideIn(child: _identity()),
                      const SizedBox(height: 18),
                      FadeSlideIn(index: 1, child: _balanceCards()),
                      const SizedBox(height: 18),
                      if (showSearch) ...[
                        TextField(
                          controller: searchController,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Rechercher un motif',
                            prefixIcon: const Icon(CupertinoIcons.search),
                            suffixIcon: IconButton(
                              icon: const Icon(CupertinoIcons.xmark),
                              onPressed: () => setState(() {
                                showSearch = false;
                                searchController.clear();
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: _filters()),
                if (isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (list.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: debts.isEmpty
                        ? EmptyState(
                            title: 'Aucune dette',
                            message:
                                'Enregistrez une dette pour ${capitalizeString(widget.customer)}.',
                            action: FilledButton.icon(
                              onPressed: _showAddDebtSheet,
                              icon: const Icon(CupertinoIcons.add),
                              label: const Text('Nouvelle dette'),
                            ),
                          )
                        : EmptyState(
                            title: switch (filter) {
                              _DebtFilter.open => 'Aucune dette en cours',
                              _DebtFilter.late => 'Aucune dette en retard',
                              _DebtFilter.settled => 'Aucune dette réglée',
                              _DebtFilter.all => 'Aucun résultat',
                            },
                            message: filter == _DebtFilter.open
                                ? 'Tout est réglé avec ce client.'
                                : null,
                          ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      MediaQuery.paddingOf(context).bottom + 100,
                    ),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => FadeSlideIn(
                        key: ValueKey(list[i]['id']),
                        index: i,
                        child: _debtCard(list[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        floatingActionButton: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) =>
              ScaleTransition(scale: a, child: child),
          child: isMultiSelectMode
              ? FloatingActionButton.extended(
                  key: const ValueKey('print'),
                  heroTag: 'print',
                  onPressed: selectedDebtIds.isEmpty ? null : _printSelected,
                  icon: const Icon(CupertinoIcons.printer),
                  label: Text('Imprimer (${selectedDebtIds.length})'),
                )
              : FloatingActionButton.extended(
                  key: const ValueKey('add'),
                  heroTag: 'add-debt',
                  onPressed: _showAddDebtSheet,
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('Nouvelle dette'),
                ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      key: const ValueKey('top'),
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(CupertinoIcons.back),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Rechercher',
          onPressed: () => setState(() => showSearch = !showSearch),
          icon: const Icon(CupertinoIcons.search),
        ),
        IconButton(
          tooltip: 'Imprimer plusieurs dettes',
          onPressed: debts.isEmpty
              ? null
              : () {
                  setState(() => isMultiSelectMode = true);
                  messageInfo(context, 'Touchez les dettes à imprimer', false);
                },
          icon: const Icon(CupertinoIcons.printer),
        ),
      ],
    );
  }

  Widget _selectionBar(List<Map<String, dynamic>> list) {
    final ids = list.map((d) => d['id'] as int).toSet();
    final allSelected = ids.isNotEmpty && selectedDebtIds.containsAll(ids);
    return Row(
      key: const ValueKey('select'),
      children: [
        IconButton.filledTonal(
          onPressed: _exitSelection,
          icon: const Icon(CupertinoIcons.xmark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${selectedDebtIds.length} sélectionnée(s)',
            style: context.text.titleMedium,
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            selectedDebtIds = allSelected ? {} : ids;
          }),
          child: Text(allSelected ? 'Aucune' : 'Tout'),
        ),
      ],
    );
  }

  Widget _identity() {
    return Row(
      children: [
        InitialsAvatar(widget.customer, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                capitalizeString(widget.customer),
                style: context.text.headlineSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                isLoading
                    ? 'Chargement…'
                    : '${debts.length} dette${debts.length > 1 ? 's' : ''} · ${_count(_DebtFilter.open)} en cours',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _balanceCards() {
    final app = context.app;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _balanceCard(
              'Vous doit',
              CupertinoIcons.arrow_down_left,
              app.receivable,
              balance.theyOweUSD,
              balance.theyOweCDF,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _balanceCard(
              'Vous devez',
              CupertinoIcons.arrow_up_right,
              app.payable,
              balance.iOweUSD,
              balance.iOweCDF,
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(
    String label,
    IconData icon,
    Color color,
    double usd,
    double cdf,
  ) {
    final empty = usd <= kMoneyEpsilon && cdf <= kMoneyEpsilon;
    return GlassCard(
      tint: empty ? null : color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (empty)
            Text(
              'Rien',
              style: context.text.titleMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            )
          else ...[
            if (usd > kMoneyEpsilon)
              AnimatedAmount(
                value: usd,
                devise: 'USD',
                style: context.text.titleLarge,
              ),
            if (cdf > kMoneyEpsilon)
              AnimatedAmount(
                value: cdf,
                devise: 'CDF',
                style: usd > kMoneyEpsilon
                    ? context.text.titleSmall
                    : context.text.titleLarge,
              ),
          ],
        ],
      ),
    );
  }

  Widget _filters() {
    final items = <(_DebtFilter, String)>[
      (_DebtFilter.open, 'En cours'),
      (_DebtFilter.late, 'En retard'),
      (_DebtFilter.settled, 'Réglées'),
      (_DebtFilter.all, 'Toutes'),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (value, label) = items[i];
          final count = isLoading ? 0 : _count(value);
          return ChoiceChip(
            showCheckmark: false,
            selected: filter == value,
            onSelected: (_) => setState(() => filter = value),
            label: Text(count > 0 ? '$label · $count' : label),
          );
        },
      ),
    );
  }

  Widget _debtCard(Map<String, dynamic> debt) {
    final app = context.app;
    final id = debt['id'] as int;
    final devise = debt['devise'].toString();
    final amount = toAmount(debt['borrowedAmount']);
    final paid = toAmount(debt['total_avance']);
    final rest = toAmount(debt['reste_a_payer']);
    final settled = _isSettled(debt);
    final iOwe = debt['own'].toString() == kIOweThem;
    final days = daysUntil(debt['dueDate']);
    final selected = selectedDebtIds.contains(id);
    final sideColor = iOwe ? app.payable : app.receivable;

    final Color dueColor = settled
        ? app.success
        : days < 0
        ? app.danger
        : days <= 3
        ? app.warning
        : context.colors.primary;

    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: selected ? 0.97 : 1,
      child: GlassCard(
        tint: selected ? context.colors.primary : null,
        border: selected
            ? Border.all(color: context.colors.primary, width: 2)
            : null,
        onTap: () =>
            isMultiSelectMode ? _toggleSelection(id) : _openAvances(debt),
        onLongPress: () {
          if (!isMultiSelectMode) setState(() => isMultiSelectMode = true);
          _toggleSelection(id);
        },
        padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sentenceCase(debt['motif'].toString()),
                        style: context.text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      StatusPill(
                        label: iOwe ? 'Vous devez' : 'On vous doit',
                        color: sideColor,
                        icon: iOwe
                            ? CupertinoIcons.arrow_up_right
                            : CupertinoIcons.arrow_down_left,
                      ),
                    ],
                  ),
                ),
                if (isMultiSelectMode)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      selected
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                      color: selected
                          ? context.colors.primary
                          : context.colors.onSurfaceVariant,
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Options',
                    onPressed: () => _showDebtOptions(debt),
                    icon: Icon(
                      Icons.more_vert,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settled ? 'Montant réglé' : 'Reste à payer',
                              style: context.text.labelMedium?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              formatMoney(settled ? amount : rest, devise),
                              style: context.text.headlineSmall?.copyWith(
                                color: settled ? app.success : null,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!settled)
                        Text(
                          '${formatAmount(paid)} / ${formatAmount(amount)} payé',
                          style: context.text.labelMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ProgressBar(
                    value: amount <= 0 ? 0 : paid / amount,
                    color: settled ? app.success : sideColor,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      StatusPill(
                        label: settled ? 'Réglée' : dueLabel(days),
                        color: dueColor,
                        icon: settled
                            ? CupertinoIcons.checkmark_seal_fill
                            : CupertinoIcons.clock,
                      ),
                      const Spacer(),
                      Icon(
                        CupertinoIcons.calendar,
                        size: 14,
                        color: context.colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        convertDate(debt['dueDate']),
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Actions

  Future<void> _printSelected() async {
    final ok = await confirmAction(
      context,
      title: 'Imprimer ${selectedDebtIds.length} dette(s) ?',
      message: 'Un seul document PDF regroupera les dettes sélectionnées.',
      confirmLabel: 'Imprimer',
    );
    if (!ok || !mounted) return;
    generateMultipleReleveDettes(
      context,
      dbHelper,
      widget.customerId.toString(),
      selectedDebtIds.toList(),
    );
    _exitSelection();
  }

  void _showDebtOptions(Map<String, dynamic> debt) {
    final id = debt['id'] as int;
    final settled = _isSettled(debt);
    final devise = debt['devise'].toString();

    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            sentenceCase(debt['motif'].toString()),
            subtitle:
                '${formatMoney(toAmount(debt['borrowedAmount']), devise)} · créée le ${convertDate(debt['todayDate'])}',
          ),
          SheetAction(
            icon: CupertinoIcons.money_dollar_circle,
            label: settled ? 'Voir les paiements' : 'Enregistrer un paiement',
            color: context.app.success,
            onTap: () {
              Navigator.pop(sheetContext);
              _openAvances(debt);
            },
          ),
          SheetAction(
            icon: CupertinoIcons.pencil,
            label: 'Modifier le montant',
            onTap: () {
              Navigator.pop(sheetContext);
              _editAmount(debt);
            },
          ),
          if (!settled)
            SheetAction(
              icon: CupertinoIcons.calendar,
              label: "Modifier l'échéance",
              subtitle: convertDate(debt['dueDate']),
              onTap: () {
                Navigator.pop(sheetContext);
                _editDueDate(debt);
              },
            ),
          SheetAction(
            icon: CupertinoIcons.share,
            label: 'Envoyer le relevé',
            subtitle: 'WhatsApp, SMS…',
            onTap: () {
              Navigator.pop(sheetContext);
              sendReleve(dbHelper, widget.customerId, id);
            },
          ),
          SheetAction(
            icon: CupertinoIcons.doc_richtext,
            label: 'Relevé PDF',
            onTap: () {
              Navigator.pop(sheetContext);
              generateReleveDettes(
                context,
                dbHelper,
                widget.customerId.toString(),
                id.toString(),
              );
            },
          ),
          SheetAction(
            icon: CupertinoIcons.trash,
            label: 'Supprimer la dette',
            color: context.app.danger,
            onTap: () {
              Navigator.pop(sheetContext);
              _confirmDelete(debt);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> debt) async {
    final paid = toAmount(debt['total_avance']);
    final devise = debt['devise'].toString();
    final ok = await confirmAction(
      context,
      title: 'Supprimer cette dette ?',
      message:
          '« ${debt['motif']} » — ${formatMoney(toAmount(debt['borrowedAmount']), devise)}.'
          '${paid > 0 ? '\nLes paiements enregistrés (${formatMoney(paid, devise)}) seront aussi supprimés.' : ''}'
          '\nCette action est irréversible.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    await dbHelper.deleteDebtAndAvances(debt['id'] as int);
    await _loadDebts();
    if (mounted) messageInfo(context, 'Dette supprimée', false);
  }

  void _editAmount(Map<String, dynamic> debt) {
    final devise = debt['devise'].toString();
    final paid = toAmount(debt['total_avance']);
    final controller = TextEditingController(
      text: roundMoney(toAmount(debt['borrowedAmount'])).toString(),
    );
    final formKey = GlobalKey<FormState>();

    showAppSheet(
      context,
      builder: (sheetContext) => Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              'Modifier le montant',
              subtitle: paid > 0
                  ? 'Déjà payé : ${formatMoney(paid, devise)}. Le montant ne peut pas être inférieur.'
                  : null,
            ),
            AmountField(
              controller: controller,
              devise: devise,
              autofocus: true,
              validator: (value) {
                final parsed = parseAmount(value);
                if (parsed == null) return 'Montant invalide';
                if (parsed <= 0) return 'Le montant doit être positif';
                if (parsed + kMoneyEpsilon < paid) {
                  return 'Minimum : ${formatMoney(paid, devise)}';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(sheetContext);
                final result = await dbHelper.changeAmount(
                  debt['id'] as int,
                  parseAmount(controller.text)!,
                );
                await _loadDebts();
                if (mounted) {
                  messageInfo(
                    context,
                    result.closed
                        ? 'Montant modifié : la dette est réglée'
                        : result.message,
                    !result.ok,
                  );
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDueDate(Map<String, dynamic> debt) async {
    final current =
        DateTime.tryParse(debt['dueDate'].toString()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      helpText: 'Nouvelle échéance',
    );
    if (picked == null) return;
    await dbHelper.changeDue(debt['id'] as int, picked.toIso8601String());
    await _loadDebts();
    if (mounted) {
      messageInfo(context, 'Échéance : ${convertDate(picked)}', false);
    }
  }

  void _showAddDebtSheet() {
    showAppSheet(
      context,
      builder: (sheetContext) => _AddDebtForm(
        customer: widget.customer,
        rate: rate,
        onSubmit: (debt) async {
          Navigator.pop(sheetContext);
          await dbHelper.insertDebt(
            Debt(
              todayDate: DateTime.now(),
              dueDate: debt.dueDate,
              borrowedAmount: roundMoney(debt.amount),
              devise: debt.devise,
              status: 'false',
              motif: debt.motif,
              customerId: widget.customerId,
              own: debt.iOwe ? kIOweThem : kTheyOweMe,
            ),
          );
          setState(() => filter = _DebtFilter.open);
          await _loadDebts();
          if (mounted) messageInfo(context, 'Dette ajoutée', false);
        },
      ),
    );
  }
}

// ------------------------------------------------------- Nouvelle dette

class _NewDebt {
  final bool iOwe;
  final double amount;
  final String devise;
  final String motif;
  final DateTime dueDate;
  _NewDebt(this.iOwe, this.amount, this.devise, this.motif, this.dueDate);
}

class _AddDebtForm extends StatefulWidget {
  final String customer;
  final double? rate;
  final Future<void> Function(_NewDebt) onSubmit;

  const _AddDebtForm({
    required this.customer,
    required this.rate,
    required this.onSubmit,
  });

  @override
  State<_AddDebtForm> createState() => _AddDebtFormState();
}

class _AddDebtFormState extends State<_AddDebtForm> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final motifController = TextEditingController();
  bool iOwe = false;
  String devise = 'USD';
  DateTime dueDate = DateTime.now().add(const Duration(days: 7));
  int? quickDays = 7;

  @override
  void dispose() {
    amountController.dispose();
    motifController.dispose();
    super.dispose();
  }

  String get equivalent {
    final value = parseAmount(amountController.text);
    final rate = widget.rate;
    if (value == null || rate == null || value <= 0) return '';
    return devise == 'USD'
        ? '≈ ${formatMoney(value * rate, 'CDF')}'
        : '≈ ${formatMoney(value / rate, 'USD')}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final name = capitalizeString(widget.customer);
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader('Nouvelle dette'),
          Row(
            children: [
              Expanded(
                child: _SideOption(
                  selected: !iOwe,
                  color: app.receivable,
                  icon: CupertinoIcons.arrow_down_left,
                  title: '$name me doit',
                  caption: 'Je dois recevoir',
                  onTap: () => setState(() => iOwe = false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SideOption(
                  selected: iOwe,
                  color: app.payable,
                  icon: CupertinoIcons.arrow_up_right,
                  title: 'Je dois à $name',
                  caption: 'Je dois payer',
                  onTap: () => setState(() => iOwe = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'USD', label: Text('USD')),
              ButtonSegment(value: 'CDF', label: Text('CDF')),
            ],
            selected: {devise},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => devise = v.first),
          ),
          const SizedBox(height: 12),
          AmountField(
            controller: amountController,
            devise: devise,
            autofocus: true,
            helper: equivalent,
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final parsed = parseAmount(value);
              if (parsed == null) return 'Montant invalide';
              if (parsed <= 0) return 'Le montant doit être positif';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: motifController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motif',
              hintText: 'Ex. : 2 sacs de riz',
              prefixIcon: Icon(CupertinoIcons.text_alignleft),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Veuillez entrer un motif'
                : null,
          ),
          const SizedBox(height: 18),
          Text(
            'Échéance · ${convertDate(dueDate)}',
            style: context.text.labelLarge,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in const [7, 15, 30])
                ChoiceChip(
                  showCheckmark: false,
                  label: Text('+$d j'),
                  selected: quickDays == d,
                  onSelected: (_) => setState(() {
                    quickDays = d;
                    dueDate = DateTime.now().add(Duration(days: d));
                  }),
                ),
              ChoiceChip(
                showCheckmark: false,
                avatar: const Icon(CupertinoIcons.calendar, size: 16),
                label: const Text('Autre date'),
                selected: quickDays == null,
                onSelected: (_) async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dueDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2101),
                  );
                  if (picked != null) {
                    setState(() {
                      dueDate = picked;
                      quickDays = null;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              widget.onSubmit(
                _NewDebt(
                  iOwe,
                  parseAmount(amountController.text)!,
                  devise,
                  motifController.text.trim(),
                  dueDate,
                ),
              );
            },
            icon: const Icon(CupertinoIcons.check_mark),
            label: const Text('Enregistrer la dette'),
          ),
        ],
      ),
    );
  }
}

class _SideOption extends StatelessWidget {
  final bool selected;
  final Color color;
  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  const _SideOption({
    required this.selected,
    required this.color,
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.14)
            : context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? color : context.colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  caption,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
