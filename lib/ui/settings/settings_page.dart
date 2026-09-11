/// 设置页：账户、分类、偏好与数据管理。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_x.dart';
import '../../core/result.dart';
import '../../data/import_export.dart';
import '../../data/ledger_data.dart';
import '../../data/ledger_importer.dart';
import '../../data/ledger_repository.dart';
import '../../data/storage/ledger_storage.dart';
import '../../domain/category.dart';
import '../../domain/enums.dart';
import '../../state/settings_controller.dart';
import '../accounts/accounts_page.dart';
import '../common/icon_map.dart';
import '../common/widgets.dart';

/// 设置页。
class SettingsPage extends StatelessWidget {
  /// 构造。
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final SettingsController settings = context.watch<SettingsController>();
    final int accountCount = repository.data.activeAccounts.length;
    final int categoryCount = repository.data.activeCategories.length;
    final int archivedCategoryCount =
        repository.data.categories.where((Category c) => c.isArchived).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: <Widget>[
        SectionCard(
          title: '账本',
          child: Column(
            children: <Widget>[
              _NavTile(
                icon: Icons.account_balance_wallet_outlined,
                title: '账户管理',
                subtitle: '$accountCount 个账户 · 净资产与余额',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const AccountsPage(),
                  ),
                ),
              ),
              const Divider(),
              _NavTile(
                icon: Icons.category_outlined,
                title: '分类管理',
                subtitle: archivedCategoryCount > 0
                    ? '$categoryCount 个分类 · $archivedCategoryCount 个已归档'
                    : '$categoryCount 个分类',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const CategoryManagerPage(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '偏好',
          child: Column(
            children: <Widget>[
              _ChoiceTile<AppThemeMode>(
                label: '主题',
                value: settings.themeMode,
                options: AppThemeMode.values,
                labelOf: (AppThemeMode mode) => mode.label,
                onChanged: (AppThemeMode mode) =>
                    unawaited(settings.setThemeMode(mode)),
              ),
              const Divider(),
              _ChoiceTile<String>(
                label: '货币符号',
                value: settings.currencySymbol,
                options: const <String>['¥', '￥', '\$', '€'],
                labelOf: (String symbol) => symbol,
                onChanged: (String symbol) =>
                    unawaited(settings.setCurrencySymbol(symbol)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '数据',
          child: Column(
            children: <Widget>[
              _NavTile(
                icon: Icons.upload_file_outlined,
                title: '导出 JSON 备份',
                subtitle: '完整数据，可用于恢复',
                onTap: () => _exportJson(context, repository),
              ),
              const Divider(),
              _NavTile(
                icon: Icons.table_chart_outlined,
                title: '导出 CSV 流水',
                subtitle: '可在 Excel 中查看整理',
                onTap: () => _exportCsv(context, repository),
              ),
              const Divider(),
              _NavTile(
                icon: Icons.download_outlined,
                title: '导入数据',
                subtitle: '粘贴备份内容，合并或覆盖',
                onTap: () => _import(context, repository),
              ),
              const Divider(),
              _NavTile(
                icon: Icons.delete_forever_outlined,
                title: '清空全部数据',
                subtitle: '删除所有流水与自定义内容',
                destructive: true,
                onTap: () => _clearAll(context, repository),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '关于',
          child: Column(
            children: <Widget>[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('记账本'),
                subtitle: Text('版本 1.0.0 · 数据全部保存在本机'),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '所有数据仅存储在本设备，不会上传到任何服务器。'
                  '卸载应用前请先导出备份。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportJson(
    BuildContext context,
    LedgerRepository repository,
  ) async {
    final ExportResult export = LedgerTransfer.exportJson(repository.data);
    await _writeExport(context, repository, export);
  }

  Future<void> _exportCsv(
    BuildContext context,
    LedgerRepository repository,
  ) async {
    final SettingsController settings = context.read<SettingsController>();
    final ExportResult export = LedgerTransfer.exportCsv(
      repository.data,
      currencySymbol: settings.currencySymbol,
    );
    await _writeExport(context, repository, export);
  }

  Future<void> _writeExport(
    BuildContext context,
    LedgerRepository repository,
    ExportResult export,
  ) async {
    final LedgerStorage storage = repository.storage;
    final Result<File> written =
        await storage.writeExport(export.fileName, export.content);
    if (!context.mounted) {
      return;
    }
    if (written.isErr) {
      showAppSnackBar(context, written.error!.message);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('导出完成'),
        content: SelectableText('文件已保存到：\n${written.value.path}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _import(
    BuildContext context,
    LedgerRepository repository,
  ) async {
    final LedgerImporter importer = LedgerImporter(repository);
    final String? raw = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _ImportDialog(),
    );
    if (raw == null || !context.mounted) {
      return;
    }

    final Result<({LedgerData data, ImportPreview preview})> prepared =
        importer.prepare(raw);
    if (prepared.isErr) {
      showAppSnackBar(context, prepared.error!.message);
      return;
    }
    if (!context.mounted) {
      return;
    }

    final ImportStrategy? strategy = await showDialog<ImportStrategy>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认导入'),
        content: Text(
          '备份时间：${prepared.value.preview.meta.exportedAtUtc.toLocal().dateTimeText}\n'
          '数据版本：${prepared.value.preview.meta.schemaVersion}\n\n'
          '${prepared.value.preview.summary}\n\n'
          '「合并」保留现有数据并以备份为准覆盖同一条记录；'
          '「覆盖」会清空现有数据后写入备份。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ImportStrategy.merge),
            child: const Text('合并'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ImportStrategy.replace),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    if (strategy == null || !context.mounted) {
      return;
    }

    final Result<ImportOutcome> applied = await importer.apply(
      prepared.value.data,
      strategy,
      preview: prepared.value.preview,
    );
    if (!context.mounted) {
      return;
    }
    if (applied.isErr) {
      showAppSnackBar(context, applied.error!.message);
      return;
    }
    final ImportOutcome outcome = applied.value;
    showAppSnackBar(
      context,
      '导入完成：流水 +${outcome.addedTransactions}/覆盖${outcome.overwrittenTransactions}，'
      '账户 +${outcome.addedAccounts}/覆盖${outcome.overwrittenAccounts}',
    );
  }

  Future<void> _clearAll(
    BuildContext context,
    LedgerRepository repository,
  ) async {
    final bool confirmed = await confirmDialog(
      context,
      title: '清空全部数据？',
      message: '将删除所有流水、账户与分类，恢复到初始状态。此操作不可撤销，建议先导出备份。',
      confirmText: '清空',
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final Result<Unit> cleared = await repository.storage.deleteAll();
    if (!context.mounted) {
      return;
    }
    if (cleared.isErr) {
      showAppSnackBar(context, cleared.error!.message);
      return;
    }
    final Result<Unit> reloaded = await repository.load();
    if (!context.mounted) {
      return;
    }
    showAppSnackBar(
      context,
      reloaded.isErr ? reloaded.error!.message : '已清空并恢复初始账户与分类',
    );
  }
}

/// 触发并忽略返回的异步调用（用于 fire-and-forget 场景）。
void unawaited(Future<void> future) {
  future.ignore();
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: destructive ? scheme.error : null),
      title: Text(
        title,
        style: destructive ? TextStyle(color: scheme.error) : null,
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: <DropdownMenuItem<T>>[
          for (final T option in options)
            DropdownMenuItem<T>(value: option, child: Text(labelOf(option))),
        ],
        onChanged: (T? next) {
          if (next != null) {
            onChanged(next);
          }
        },
      ),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入数据'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '把导出的 JSON 备份内容粘贴到下面，然后点击「解析」。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                // 8 行的输入框很高，键盘弹起时对话框空间不足，必须让内容可滚动，
                // 否则会出现 overflow 条纹。
                maxLines: 8,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                decoration: const InputDecoration(
                  hintText: '{"schemaVersion":1,...}',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('解析'),
        ),
      ],
    );
  }
}

/// 分类管理页。
class CategoryManagerPage extends StatelessWidget {
  /// 构造。
  const CategoryManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('分类管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: <Widget>[
          for (final CategoryKind kind in CategoryKind.values) ...<Widget>[
            Row(
              children: <Widget>[
                Text(
                  '${kind.label}分类',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _editCategory(context, repository, kind),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增'),
                ),
              ],
            ),
            Card(
              child: Column(
                children: <Widget>[
                  for (final Category category in repository.data.categories
                      .where((Category c) => c.kind == kind)
                      .toList()
                    ..sort((Category a, Category b) =>
                        a.sortOrder.compareTo(b.sortOrder)))
                    _CategoryTile(
                      category: category,
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
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
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
  const _CategoryTile({required this.category, required this.onEdit});

  final Category category;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      onTap: onEdit,
      leading: Icon(
        iconForName(category.iconName),
        color: colorFromHex(category.colorHex),
      ),
      title: Text(
        category.name,
        style: category.isArchived
            ? TextStyle(color: scheme.onSurfaceVariant)
            : null,
      ),
      subtitle: category.isArchived ? const Text('已归档') : null,
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

/// 分类新增/编辑对话框。
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.read<LedgerRepository>();
    return AlertDialog(
      title: Text(
        widget.existing == null ? '新增${widget.kind.label}分类' : '编辑分类',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              scrollPadding: const EdgeInsets.only(bottom: 160),
              decoration: const InputDecoration(labelText: '分类名称'),
            ),
            if (widget.existing != null) ...<Widget>[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : () => _delete(repository),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除分类'),
                ),
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
      iconName: widget.existing?.iconName ?? 'more',
      colorHex: widget.existing?.colorHex,
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
