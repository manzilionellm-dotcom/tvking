// =========================================================
//  category_order_screen.dart — Réorganiser ses catégories
// =========================================================
//  L'utilisateur glisse une catégorie pour la MONTER ou la DESCENDRE
//  (ex. remonter « Français » tout en haut). L'ordre est enregistré
//  (CategoryOrderStore) et appliqué partout (téléphone + TV).
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/category_order_store.dart';

class CategoryOrderScreen extends StatefulWidget {
  const CategoryOrderScreen({super.key, required this.categories});

  /// Catégories dans l'ordre ACTUELLEMENT affiché (déjà trié). L'utilisateur
  /// part de là pour réorganiser.
  final List<String> categories;

  @override
  State<CategoryOrderScreen> createState() => _CategoryOrderScreenState();
}

class _CategoryOrderScreenState extends State<CategoryOrderScreen> {
  late final List<String> _items = List<String>.from(widget.categories);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.categoryOrderTitle),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await CategoryOrderStore.instance.reset();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(context.l10n.categoryOrderReset),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              context.l10n.categoryOrderHint,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
              itemCount: _items.length,
              onReorder: (int oldIndex, int newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final String moved = _items.removeAt(oldIndex);
                  _items.insert(newIndex, moved);
                });
              },
              itemBuilder: (BuildContext context, int index) {
                final String name = _items[index];
                return Padding(
                  key: ValueKey<String>(name),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Text(
                        '${index + 1}',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textTertiary),
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLarge
                            .copyWith(color: AppColors.textPrimary),
                      ),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle_rounded,
                            color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.royalGold,
        foregroundColor: AppColors.background,
        onPressed: () async {
          await CategoryOrderStore.instance.setOrder(_items);
          if (context.mounted) Navigator.of(context).pop();
        },
        icon: const Icon(Icons.check_rounded),
        label: Text(context.l10n.categoryOrderSave),
      ),
    );
  }
}
