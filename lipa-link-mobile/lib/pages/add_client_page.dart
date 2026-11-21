import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../func/export.dart';

/// Création d'un client. Retourne `true` si un client a été ajouté.
class AddClientPage extends StatefulWidget {
  const AddClientPage({super.key});

  @override
  State<AddClientPage> createState() => _AddClientPageState();
}

class _AddClientPageState extends State<AddClientPage> {
  final DatabaseHelper dbHelper = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    try {
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      final full = await FlutterContacts.getContact(contact.id);
      if (full == null || !mounted) return;
      setState(() {
        nameController.text = full.displayName;
        if (full.phones.isNotEmpty) {
          phoneController.text = full.phones.first.number.replaceAll(' ', '');
        }
      });
    } catch (e) {
      if (mounted) {
        messageInfo(context, "Impossible d'ouvrir les contacts", true);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    try {
      final name = nameController.text.trim();
      await dbHelper.createCustomer(
        Customer(fullname: name, phone: phoneController.text.trim(), email: ''),
      );
      if (!mounted) return;
      messageInfo(context, '${capitalizeString(name)} ajouté', false);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        messageInfo(context, "Erreur lors de l'ajout du client", true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = nameController.text.trim();
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
                      const SizedBox(width: 12),
                      Text('Nouveau client', style: context.text.titleLarge),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    children: [
                      FadeSlideIn(
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, a) =>
                                ScaleTransition(scale: a, child: child),
                            child: name.isEmpty
                                ? Container(
                                    key: const ValueKey('empty'),
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                      color: context.app.glass,
                                      borderRadius: BorderRadius.circular(32),
                                      border: Border.all(
                                        color: context.app.glassBorder,
                                      ),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.person,
                                      size: 40,
                                      color: context.colors.onSurfaceVariant,
                                    ),
                                  )
                                : InitialsAvatar(
                                    name,
                                    key: ValueKey(name.substring(0, 1)),
                                    size: 96,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FadeSlideIn(
                        index: 1,
                        child: GlassCard(
                          onTap: isLoading ? null : _pickContact,
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              IconBadge(
                                CupertinoIcons.person_crop_circle_badge_plus,
                                color: context.colors.primary,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Importer depuis mes contacts',
                                      style: context.text.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Nom et numéro remplis automatiquement',
                                      style: context.text.bodySmall?.copyWith(
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                CupertinoIcons.chevron_right,
                                size: 18,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SectionTitle('Informations'),
                      FadeSlideIn(
                        index: 2,
                        child: TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Nom complet',
                            prefixIcon: Icon(CupertinoIcons.person),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Le nom est obligatoire'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        index: 3,
                        child: TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _save(),
                          decoration: const InputDecoration(
                            labelText: 'Téléphone',
                            hintText: '+243 …',
                            prefixIcon: Icon(CupertinoIcons.phone),
                          ),
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isEmpty) {
                              return 'Le téléphone est obligatoire';
                            }
                            if (value.length > 15) {
                              return '15 caractères maximum';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: FilledButton.icon(
                    onPressed: isLoading ? null : _save,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.check_mark),
                    label: const Text('Enregistrer le client'),
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
