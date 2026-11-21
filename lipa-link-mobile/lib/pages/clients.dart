import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../func/export.dart';
import 'add_client_page.dart';

enum _ClientFilter { all, theyOwe, iOwe, settled, late }

enum _ClientSort { name, amount }

/// Liste des clients avec leurs soldes.
class Clients extends StatefulWidget {
  /// true quand la page est un onglet de l'accueil (pas de bouton retour).
  final bool embedded;
  const Clients({super.key, this.embedded = false});

  @override
  State<Clients> createState() => _ClientsState();
}

class _ClientsState extends State<Clients> {
  final DatabaseHelper dbHelper = DatabaseHelper();
  final TextEditingController searchController = TextEditingController();

  List<Map<String, Object?>> clients = [];
  Set<int> lateClientIds = {};
  bool isLoading = true;
  _ClientFilter filter = _ClientFilter.all;
  _ClientSort sort = _ClientSort.name;

  @override
  void initState() {
    super.initState();
    NotificationClass.askPermission(context);
    loadClients();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadClients() async {
    final results = await Future.wait<Object>([
      dbHelper.getCustomersWithBalances(),
      dbHelper.getWatchlist(withinDays: -1, limit: 100000),
    ]);
    if (!mounted) return;
    setState(() {
      clients = results[0] as List<Map<String, Object?>>;
      lateClientIds = (results[1] as List<Map<String, Object?>>)
          .map((r) => r['customerId'] as int)
          .toSet();
      isLoading = false;
    });
  }

  CustomerBalance _balance(Map<String, Object?> c) =>
      CustomerBalance.fromRow(c);

  /// Montant total en jeu pour un client (pour le tri), converti grossièrement
  /// en « poids » : on additionne les USD et les CDF séparément.
  double _weight(Map<String, Object?> c) {
    final b = _balance(c);
    return b.theyOweUSD + b.iOweUSD + (b.theyOweCDF + b.iOweCDF) / 10000;
  }

  List<Map<String, Object?>> get visibleClients {
    final query = searchController.text.trim().toLowerCase();
    final list = clients.where((c) {
      if (query.isNotEmpty &&
          !c['fullname'].toString().toLowerCase().contains(query) &&
          !(c['phone'] ?? '').toString().contains(query)) {
        return false;
      }
      final b = _balance(c);
      return switch (filter) {
        _ClientFilter.all => true,
        _ClientFilter.theyOwe =>
          b.theyOweUSD > kMoneyEpsilon || b.theyOweCDF > kMoneyEpsilon,
        _ClientFilter.iOwe =>
          b.iOweUSD > kMoneyEpsilon || b.iOweCDF > kMoneyEpsilon,
        _ClientFilter.settled => b.isEmpty,
        _ClientFilter.late => lateClientIds.contains(c['id']),
      };
    }).toList();
    if (sort == _ClientSort.amount) {
      list.sort((a, b) => _weight(b).compareTo(_weight(a)));
    }
    return list;
  }

  Future<void> _openDebts(Map<String, Object?> client) async {
    await goTox(
      context,
      DebtList(
        customerId: client['id'] as int,
        customer: client['fullname'].toString(),
      ),
    );
    loadClients();
  }

  Future<void> _addClient() async {
    final added = await goTox<bool>(context, const AddClientPage());
    if (added == true) loadClients();
  }

  @override
  Widget build(BuildContext context) {
    final list = visibleClients;
    final bottom = MediaQuery.paddingOf(context).bottom + 96;

    final content = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(child: _header()),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedBar(height: 128, child: _searchAndFilters()),
        ),
        if (isLoading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: clients.isEmpty
                ? EmptyState(
                    title: 'Aucun client',
                    message:
                        'Ajoutez votre premier client pour commencer à suivre ses dettes.',
                    action: FilledButton.icon(
                      onPressed: _addClient,
                      icon: const Icon(CupertinoIcons.person_badge_plus),
                      label: const Text('Ajouter un client'),
                    ),
                  )
                : const EmptyState(
                    title: 'Aucun résultat',
                    message: 'Modifiez la recherche ou le filtre.',
                  ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, bottom),
            sliver: SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => FadeSlideIn(
                key: ValueKey(list[i]['id']),
                index: i,
                child: _clientCard(list[i]),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      body: widget.embedded
          ? RefreshIndicator(onRefresh: loadClients, child: content)
          : AmbientBackground(
              child: RefreshIndicator(onRefresh: loadClients, child: content),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-client',
        onPressed: _addClient,
        icon: const Icon(CupertinoIcons.person_badge_plus),
        label: const Text('Nouveau client'),
      ),
    );
  }

  // ------------------------------------------------------------- En-tête

  Widget _header() {
    final withDebt = clients.where((c) => !_balance(c).isEmpty).length;
    return Row(
      children: [
        if (!widget.embedded) ...[
          IconButton.filledTonal(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(CupertinoIcons.back),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Clients', style: context.text.headlineMedium),
              Text(
                isLoading
                    ? 'Chargement…'
                    : '${clients.length} client${clients.length > 1 ? 's' : ''} · $withDebt avec un solde en cours',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<_ClientSort>(
          tooltip: 'Trier',
          initialValue: sort,
          onSelected: (value) => setState(() => sort = value),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _ClientSort.name,
              child: Text('Trier par nom'),
            ),
            PopupMenuItem(
              value: _ClientSort.amount,
              child: Text('Trier par montant'),
            ),
          ],
          child: const GlassCard(
            radius: 16,
            padding: EdgeInsets.all(12),
            child: Icon(CupertinoIcons.arrow_up_arrow_down, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _searchAndFilters() {
    final chips = <(_ClientFilter, String)>[
      (_ClientFilter.all, 'Tous'),
      (_ClientFilter.theyOwe, 'Me doivent'),
      (_ClientFilter.iOwe, 'Je dois'),
      (_ClientFilter.late, 'En retard'),
      (_ClientFilter.settled, 'À jour'),
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rechercher un nom ou un numéro',
              prefixIcon: const Icon(CupertinoIcons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill),
                      onPressed: () => setState(searchController.clear),
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (value, label) = chips[i];
              return ChoiceChip(
                label: Text(label),
                selected: filter == value,
                showCheckmark: false,
                onSelected: (_) => setState(() => filter = value),
              );
            },
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- Carte

  Widget _clientCard(Map<String, Object?> client) {
    final app = context.app;
    final name = client['fullname'].toString();
    final phone = (client['phone'] ?? '').toString();
    final b = _balance(client);
    final late = lateClientIds.contains(client['id']);

    final pills = <Widget>[
      if (b.theyOweUSD > kMoneyEpsilon)
        _amountPill(b.theyOweUSD, 'USD', app.receivable, true),
      if (b.theyOweCDF > kMoneyEpsilon)
        _amountPill(b.theyOweCDF, 'CDF', app.receivable, true),
      if (b.iOweUSD > kMoneyEpsilon)
        _amountPill(b.iOweUSD, 'USD', app.payable, false),
      if (b.iOweCDF > kMoneyEpsilon)
        _amountPill(b.iOweCDF, 'CDF', app.payable, false),
    ];

    return GlassCard(
      onTap: () => _openDebts(client),
      onLongPress: () => _showClientOptions(client),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      child: Row(
        children: [
          InitialsAvatar(name, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        capitalizeString(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium,
                      ),
                    ),
                    if (late) ...[
                      const SizedBox(width: 6),
                      Icon(
                        CupertinoIcons.exclamationmark_circle_fill,
                        size: 16,
                        color: app.danger,
                      ),
                    ],
                  ],
                ),
                if (phone.isNotEmpty)
                  Text(
                    phone,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 8),
                if (pills.isEmpty)
                  StatusPill(
                    label: 'À jour',
                    color: app.success,
                    icon: CupertinoIcons.checkmark_seal_fill,
                  )
                else
                  Wrap(spacing: 6, runSpacing: 6, children: pills),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Options',
            onPressed: () => _showClientOptions(client),
            icon: Icon(Icons.more_vert, color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _amountPill(double value, String devise, Color color, bool theyOwe) {
    return StatusPill(
      label: formatMoney(value, devise),
      color: color,
      icon: theyOwe
          ? CupertinoIcons.arrow_down_left
          : CupertinoIcons.arrow_up_right,
    );
  }

  // ------------------------------------------------------------- Actions

  void _showClientOptions(Map<String, Object?> client) {
    final id = client['id'] as int;
    final name = client['fullname'].toString();
    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InitialsAvatar(name, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: SheetHeader(
                  capitalizeString(name),
                  subtitle: (client['phone'] ?? '').toString(),
                ),
              ),
            ],
          ),
          SheetAction(
            icon: CupertinoIcons.doc_text,
            label: 'Voir ses dettes',
            onTap: () {
              Navigator.pop(sheetContext);
              _openDebts(client);
            },
          ),
          SheetAction(
            icon: CupertinoIcons.pencil,
            label: 'Modifier le nom',
            onTap: () {
              Navigator.pop(sheetContext);
              _editField(
                title: 'Modifier le nom',
                label: 'Nom complet',
                initial: name,
                icon: CupertinoIcons.person,
                keyboard: TextInputType.name,
                onSave: (value) => dbHelper.updateCustomername(value, id),
              );
            },
          ),
          SheetAction(
            icon: CupertinoIcons.phone,
            label: 'Modifier le téléphone',
            onTap: () {
              Navigator.pop(sheetContext);
              _editField(
                title: 'Modifier le téléphone',
                label: 'Numéro',
                initial: (client['phone'] ?? '').toString(),
                icon: CupertinoIcons.phone,
                keyboard: TextInputType.phone,
                onSave: (value) => dbHelper.updateCustomerPhone(value, id),
              );
            },
          ),
          SheetAction(
            icon: CupertinoIcons.trash,
            label: 'Supprimer le client',
            subtitle: 'Possible seulement si tout est réglé',
            color: context.app.danger,
            onTap: () {
              Navigator.pop(sheetContext);
              _confirmDelete(id, name);
            },
          ),
        ],
      ),
    );
  }

  void _editField({
    required String title,
    required String label,
    required String initial,
    required IconData icon,
    required TextInputType keyboard,
    required Future<void> Function(String) onSave,
  }) {
    final controller = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();
    showAppSheet(
      context,
      builder: (sheetContext) => Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title),
            TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: keyboard,
              textCapitalization: keyboard == TextInputType.name
                  ? TextCapitalization.words
                  : TextCapitalization.none,
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ce champ est obligatoire'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(sheetContext);
                await onSave(controller.text.trim());
                await loadClients();
                if (mounted) {
                  messageInfo(context, 'Modification enregistrée', false);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int id, String name) async {
    final confirmed = await confirmAction(
      context,
      title: 'Supprimer ${capitalizeString(name)} ?',
      message:
          'Son historique de dettes réglées sera aussi supprimé. '
          'Impossible s\'il reste une dette en cours.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed) return;
    final result = await dbHelper.deleteCustomer(id);
    if (!mounted) return;
    messageInfo(context, result.message, !result.ok);
    if (result.ok) loadClients();
  }
}

/// Barre de recherche et filtres qui restent visibles en haut au défilement.
class _PinnedBar extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _PinnedBar({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: overlaps
            ? context.colors.surface.withValues(alpha: 0.92)
            : Colors.transparent,
        border: overlaps
            ? Border(bottom: BorderSide(color: context.app.glassBorder))
            : null,
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_PinnedBar old) => true;
}
