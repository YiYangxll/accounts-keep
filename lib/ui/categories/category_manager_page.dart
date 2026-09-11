/// 分类管理页与分类编辑对话框。
///
/// 独立成文件的原因：记账页需要一个直达「分类管理」的入口。如果它继续留在
/// `settings_page.dart` 里，就会出现「记账页 import 设置页」这种别扭依赖，
/// 也与「每个页面一个文件」的结构不一致。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../data/ledger_repository.dart';
import '../../domain/category.dart';
import '../../domain/enums.dart';
import '../common/icon_map.dart';
import '../common/widgets.dart';

/// 分类管理页：分类的增删改、归档查看与恢复。
class CategoryManagerPage extends StatelessWidget {
  /// 构造。
  const CategoryManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('分类管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: <Widget>[
          Text(
            '这些分类会出现在「记一笔」页面。被流水使用过的分类删除时会改为归档，'
            '历史记录不受影响，随时可以恢复。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final CategoryKind kind in CategoryKind.values) ...<Widget>[
            Row(
              children: <Widget>[
                Text('${kind.label}分类', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _editCategory(context, repository, kind),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增'),
                ),
              ],
            ),
            ..._buildGroup(context, repository, kind),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  /// 渲染某一收支类型下的活跃分类 + 折叠的归档分类。
  static List<Widget> _buildGroup(
    BuildContext context,
    LedgerRepository repository,
    CategoryKind kind,
  ) {
    final ThemeData theme = Theme.of(context);
    final List<Category> all = repository.data.categories
        .where((Category c) => c.kind == kind)
        .toList()
      ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));
    final List<Category> active =
        all.where((Category c) => !c.isArchived).toList();
    final List<Category> archived =
        all.where((Category c) => c.isArchived).toList();

    if (all.isEmpty) {
      return <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.label_off_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '暂无${kind.label}分类，点右上角「新增」添加',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      Card(
        child: Column(
          children: <Widget>[
            for (final Category category in active)
              _CategoryTile(
                category: category,
                transactionCount:
                    repository.data.transactionCountForCategory(category.id),
                onEdit: () => _editCategory(
                  context,
                  repository,
                  kind,
                  existing: category,
                ),
              ),
          ],
        ),
      ),
      if (archived.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: EdgeInsets.zero,
            title: Text(
              '已归档（${archived.length}）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            children: <Widget>[
              for (final Category category in archived)
                _CategoryTile(
                  category: category,
                  transactionCount:
                      repository.data.transactionCountForCategory(category.id),
                  onEdit: () => _editCategory(
                    context,
                    repository,
                    kind,
                    existing: category,
                  ),
                  onRestore: () => unawaited(
                    repository.restoreCategory(category.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  static Future<void> _editCategory(
    BuildContext context,
    LedgerRepository repository,
    CategoryKind kind, {
    Category? existing,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => CategoryEditorDialog(
        kind: kind,
        existing: existing,
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.transactionCount,
    this.onEdit,
    this.onRestore,
  });

  final Category category;
  final int transactionCount;
  final VoidCallback? onEdit;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color =
        colorFromHex(category.colorHex) ?? scheme.onSurfaceVariant;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      onTap: onEdit,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        child: Icon(iconForName(category.iconName), size: 20, color: color),
      ),
      title: Text(
        category.name,
        style: category.isArchived
            ? TextStyle(color: scheme.onSurfaceVariant)
            : null,
      ),
      subtitle: Text(
        <String>[
          if (category.isArchived) '已归档',
          // 笔数让用户在删除前知道影响范围。
          if (transactionCount > 0) '$transactionCount 笔流水' else '未被使用',
        ].join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: onRestore == null
          ? const Icon(Icons.chevron_right, size: 18)
          : TextButton(onPressed: onRestore, child: const Text('恢复')),
    );
  }
}

/// 分类新增/编辑对话框。
///
/// 支持自定义**名称、图标与配色**：分类在「记一笔」页面以彩色图标芯片呈现，
/// 所以这三项都要可调，否则用户新增的分类只能是一堆同色的默认图标。
class CategoryEditorDialog extends StatefulWidget {
  /// 构造。
  const CategoryEditorDialog({required this.kind, this.existing, super.key});

  /// 分类所属收支类型。
  final CategoryKind kind;

  /// 要编辑的分类。
  final Category? existing;

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  late final TextEditingController _nameController;
  late String _iconName;
  late String _colorHex;
  bool _saving = false;

  /// 新增时的默认图标：按收支类型给一个不那么像占位符的默认值。
  static const String _defaultExpenseIcon = 'shopping';
  static const String _defaultIncomeIcon = 'salary';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    final String fallbackIcon = widget.kind == CategoryKind.expense
        ? _defaultExpenseIcon
        : _defaultIncomeIcon;
    _iconName = widget.existing?.iconName ?? fallbackIcon;
    if (!isKnownCategoryIcon(_iconName)) {
      // 存量数据里的图标名可能不在受控集合内，落到一个可见的默认值。
      _iconName = 'more';
    }
    _colorHex = widget.existing?.colorHex ?? _defaultColorFor(widget.kind);
  }

  /// 新增分类时的默认配色：支出偏暖、收入偏绿，避免一屏全是同一个颜色。
  static String _defaultColorFor(CategoryKind kind) =>
      kind == CategoryKind.expense ? '#FF7043' : '#1F9D55';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.read<LedgerRepository>();
    final ThemeData theme = Theme.of(context);
    final Color previewColor =
        colorFromHex(_colorHex) ?? theme.colorScheme.primary;
    final Color onPreview = readableOn(previewColor);

    return AlertDialog(
      title: Text(
        widget.existing == null ? '新增${widget.kind.label}分类' : '编辑分类',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              scrollPadding: const EdgeInsets.only(bottom: 260),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: '分类名称',
                hintText: '如：宠物、房租、副业收入',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            // 键盘会一直停在屏幕上挡住下面的图标/颜色区，给一个明确的收起入口。
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => FocusScope.of(context).unfocus(),
                icon: const Icon(Icons.keyboard_hide_outlined, size: 18),
                label: const Text('收起键盘'),
              ),
            ),

            // 实时预览：直接展示它在「记一笔」页面里的样子。
            Text('预览', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(iconForName(_iconName), size: 18, color: onPreview),
              backgroundColor: previewColor,
              label: Text(
                _nameController.text.trim().isEmpty
                    ? '分类名称'
                    : _nameController.text.trim(),
                style: TextStyle(color: onPreview),
              ),
            ),
            const SizedBox(height: 16),

            Text('图标', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // 固定高度 + 内部滚动：46 个图标不滚动的话，对话框会长到无法操作。
            SizedBox(
              height: 132,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final IconChoice choice in kCategoryIconChoices)
                      _IconSwatch(
                        choice: choice,
                        selected: _iconName == choice.name,
                        color: previewColor,
                        onTap: () {
                          setState(() => _iconName = choice.name);
                          // 键盘会一直停在屏幕上挡住下面的图标/颜色区，选完就收起。
                          FocusScope.of(context).unfocus();
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('颜色', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (int i = 0; i < kCategoryColorChoices.length; i++)
                  _ColorSwatch(
                    index: i,
                    hex: kCategoryColorChoices[i],
                    selected: _colorHex.toUpperCase() ==
                        kCategoryColorChoices[i].toUpperCase(),
                    onTap: () {
                      setState(() => _colorHex = kCategoryColorChoices[i]);
                      FocusScope.of(context).unfocus();
                    },
                  ),
              ],
            ),

            if (widget.existing != null) ...<Widget>[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _saving ? null : () => _delete(repository),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除分类'),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _save(repository),
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  Future<void> _save(LedgerRepository repository) async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(context, '请填写分类名称');
      return;
    }
    setState(() => _saving = true);
    final Category draft = Category(
      id: widget.existing?.id ?? repository.newId('cat'),
      name: name,
      kind: widget.kind,
      iconName: _iconName,
      colorHex: _colorHex,
      sortOrder: widget.existing?.sortOrder ?? _nextSortOrder(repository),
      archivedAt: widget.existing?.archivedAt,
    );
    final Result<Category> result = widget.existing == null
        ? await repository.addCategory(draft)
        : await repository.updateCategory(draft);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (result.isErr) {
      showAppSnackBar(context, result.error!.message);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete(LedgerRepository repository) async {
    final Category category = widget.existing!;
    final int used = repository.data.transactionCountForCategory(category.id);
    final bool ok = await confirmDialog(
      context,
      title: '删除分类「${category.name}」？',
      message: used > 0
          ? '该分类已被 $used 条流水使用，删除后会改为「归档」，历史记录仍可查看。'
          : '该分类没有被任何流水使用，将被彻底删除。',
      confirmText: '确定',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    final Result<bool> result = await repository.deleteCategory(category.id);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      showAppSnackBar(context, result.error!.message);
      return;
    }
    Navigator.of(context).pop();
    showAppSnackBar(
      context,
      result.value ? '分类已删除' : '分类已归档',
      action: result.value
          ? null
          : SnackBarAction(
              label: '恢复',
              onPressed: () =>
                  unawaited(repository.restoreCategory(category.id)),
            ),
    );
  }

  int _nextSortOrder(LedgerRepository repository) {
    final List<int> orders = repository.data.categories
        .where((Category c) => c.kind == widget.kind)
        .map((Category c) => c.sortOrder)
        .toList();
    if (orders.isEmpty) {
      return 0;
    }
    return orders.reduce((int a, int b) => a > b ? a : b) + 1;
  }
}

/// 图标选择项：选中时用分类当前配色高亮。
class _IconSwatch extends StatelessWidget {
  const _IconSwatch({
    required this.choice,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconChoice choice;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '图标：${choice.label}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(
            choice.icon,
            size: 22,
            color: selected ? color : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 颜色选择项。
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.index,
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = colorFromHex(hex) ?? Colors.grey;
    return Semantics(
      label: '颜色 ${index + 1}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 18, color: readableOn(color))
              : null,
        ),
      ),
    );
  }
}
