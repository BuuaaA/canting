import 'package:canting/core_engine.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// 手动添加餐食（模块 15）。
///
/// 简单模式：选餐次 → 搜菜名 → 选分量（小/常规/大）→ 添加；
/// 详细模式：克重↔份数双向联动（ServingEstimator 口径）、选分类、
/// 标记自制、备注。自定义菜优先展示并按使用次数排序；用过的分量
/// 下次默认带出（纯本地）。
class ManualAddPage extends StatefulWidget {
  const ManualAddPage({super.key});

  @override
  State<ManualAddPage> createState() => _ManualAddPageState();
}

class _ManualAddPageState extends State<ManualAddPage> {
  bool _detailed = false;
  late String _mealType = _mealTypeFor(DateTime.now().hour);
  String _portion = 'normal';

  final _searchController = TextEditingController();
  final _gramsController = TextEditingController();
  final _servingsController = TextEditingController();
  final _noteController = TextEditingController();

  List<StandardDish> _results = const [];
  StandardDish? _selectedDish;

  /// 详细模式的最新换算结果（克重↔份数联动产物）。
  ManualServingLink? _link;
  bool _linkSyncing = false;
  String? _categoryId;
  bool _homemade = false;
  bool _saving = false;

  @override
  void dispose() {
    _searchController.dispose();
    _gramsController.dispose();
    _servingsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 当前要添加的菜名：选中结果优先，否则用输入框里的字。
  String get _dishName => _selectedDish?.name ?? _searchController.text.trim();

  static String _mealTypeFor(int hour) {
    if (hour < 10) return 'breakfast';
    if (hour < 15) return 'lunch';
    if (hour < 21) return 'dinner';
    return 'snack';
  }

  static const _mealTypeLabels = {
    'breakfast': '早餐',
    'lunch': '午餐',
    'dinner': '晚餐',
    'snack': '加餐',
  };

  Future<void> _search(String query) async {
    final results = await context.read<AppState>().searchDishesForManualAdd(
      query,
    );
    if (mounted) {
      setState(() => _results = results);
    }
  }

  Future<void> _selectDish(StandardDish dish) async {
    final state = context.read<AppState>();
    final usage = await state.manualDishUsage(dish.name);
    // 分量偏好带出：用户上次用的分量做默认值。
    var grams = '';
    if (_detailed) {
      final unit = state.resolveManualGrams(
        dish.name,
        servings: 1,
        categoryId: dish.category,
      );
      if (unit != null) {
        grams = unit.round().toString();
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedDish = dish;
      _portion = usage?.preferredPortion ?? 'normal';
      _homemade = dish.tags.contains('homemade');
      _categoryId ??= dish.category;
      _link = null;
      _gramsController.text = grams;
      _servingsController.text = '';
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedDish = null;
      _link = null;
      _gramsController.text = '';
      _servingsController.text = '';
      _noteController.text = '';
      _homemade = false;
    });
  }

  /// 克重 → 份数（联动方向一）。
  void _onGramsChanged(String value) {
    if (_linkSyncing) {
      return;
    }
    final grams = double.tryParse(value);
    final name = _dishName;
    if (grams == null || name.isEmpty) {
      return;
    }
    final link = context.read<AppState>().resolveManualServings(
      name,
      grams: grams,
      categoryId: _categoryId,
    );
    _linkSyncing = true;
    _servingsController.text = link == null
        ? ''
        : link.servings.toStringAsFixed(2);
    _linkSyncing = false;
    setState(() => _link = link);
  }

  /// 份数 → 克重（联动方向二）。
  void _onServingsChanged(String value) {
    if (_linkSyncing) {
      return;
    }
    final servings = double.tryParse(value);
    final name = _dishName;
    if (servings == null || servings <= 0 || name.isEmpty) {
      return;
    }
    final state = context.read<AppState>();
    final grams = state.resolveManualGrams(
      name,
      servings: servings,
      categoryId: _categoryId,
    );
    if (grams == null) {
      setState(() => _link = null);
      return;
    }
    _linkSyncing = true;
    _gramsController.text = grams.round().toString();
    _linkSyncing = false;
    _onGramsChanged(_gramsController.text);
  }

  Future<void> _add() async {
    final state = context.read<AppState>();
    final name = _dishName;
    if (_saving) {
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先搜索或输入菜名')));
      return;
    }

    MealDish dish;
    String registeredPortion = _portion;
    if (_detailed) {
      final grams = double.tryParse(_gramsController.text);
      final link =
          _link ??
          (grams == null
              ? null
              : state.resolveManualServings(
                  name,
                  grams: grams,
                  categoryId: _categoryId,
                ));
      if (link == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('算不出这份的份数：请选择分类并填写克重')),
        );
        return;
      }
      // 详细模式的克重就是绝对量，分量固定按常规记，避免再乘系数。
      dish = MealDish(
        name: name,
        portionSize: 'normal',
        matchedDishId: link.matchedDishId,
        matchConfidence: link.matchedDishId == null ? 0 : 1,
        portions: link.portions,
      );
      registeredPortion = 'normal';
    } else {
      dish = MealDish(name: name, portionSize: _portion);
    }

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    _saving = true;
    try {
      final meal = state.buildMealRecord(
        mealType: _mealType,
        timestamp: DateTime.now(),
        dishes: [dish],
      );
      await state.saveMeal(
        meal,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        source: 'manual',
      );
      await state.registerManualDish(
        name: name,
        portionSize: registeredPortion,
        manualPortions: _link?.portions,
        category: _link?.categoryId ?? _categoryId,
        homemade: _homemade,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('已记下这顿${_mealTypeLabels[_mealType]}')),
      );
      router.pop();
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = context.watch<AppState>();
    final categories = state.dishCategories;

    return Scaffold(
      appBar: PixelAppBar(
        title: '手动添加',
        leading: const BackButton(),
        actions: [
          TextButton(
            onPressed: () => setState(() => _detailed = !_detailed),
            child: Text(_detailed ? '简单模式' : '详细填写'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('餐次', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'breakfast', label: Text('早餐')),
                    ButtonSegment(value: 'lunch', label: Text('午餐')),
                    ButtonSegment(value: 'dinner', label: Text('晚餐')),
                    ButtonSegment(value: 'snack', label: Text('加餐')),
                  ],
                  selected: {_mealType},
                  onSelectionChanged: (value) =>
                      setState(() => _mealType = value.first),
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索菜名，或直接输入新菜名',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            _clearSelection();
                            setState(() => _results = const []);
                          },
                        ),
                ),
                onChanged: (value) {
                  _clearSelection();
                  _search(value);
                },
              ),
              const SizedBox(height: 10),
              if (_selectedDish != null)
                _SelectedDishChip(
                  dish: _selectedDish!,
                  onRemove: _clearSelection,
                )
              else if (_results.isNotEmpty)
                _SearchResults(
                  results: _results,
                  onSelect: _selectDish,
                )
              else if (_searchController.text.trim().isNotEmpty)
                PixelPanel(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '没有搜到「${_searchController.text.trim()}」，'
                    '可以直接用这个名字添加；详细模式下选好分类、填好克重更准确。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              if (!_detailed) ...[
                Text('分量', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'small', label: Text('小份')),
                      ButtonSegment(value: 'normal', label: Text('常规')),
                      ButtonSegment(value: 'large', label: Text('大份')),
                    ],
                    selected: {_portion},
                    onSelectionChanged: (value) =>
                        setState(() => _portion = value.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '小份约 80% · 常规为标准 · 大份约 130%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                _DetailedSection(
                  gramsController: _gramsController,
                  servingsController: _servingsController,
                  categories: categories,
                  categoryId: _categoryId,
                  homemade: _homemade,
                  noteController: _noteController,
                  canLink: _link != null,
                  onGramsChanged: _onGramsChanged,
                  onServingsChanged: _onServingsChanged,
                  onCategoryChanged: (value) {
                    setState(() {
                      _categoryId = value;
                      _link = null;
                    });
                  },
                  onHomemadeChanged: (value) =>
                      setState(() => _homemade = value),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.check),
                  label: Text('添加这顿${_mealTypeLabels[_mealType]}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.onSelect});

  final List<StandardDish> results;
  final ValueChanged<StandardDish> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 264),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, index) {
            final dish = results[index];
            final isCustom = dish.id.startsWith('custom') ||
                dish.searchKeywords.contains(dish.name);
            return ListTile(
              dense: true,
              onTap: () => onSelect(dish),
              title: Text(dish.name),
              subtitle: Text(
                [
                  if (isCustom) '常用',
                  if (dish.tags.contains('homemade')) '自制',
                  dish.tags
                      .where((tag) => const {
                            'breakfast',
                            'lunch',
                            'dinner',
                          }.contains(tag))
                      .map((tag) => _mealTypeLabelOf(tag))
                      .join('、'),
                ]
                    .where((part) => part.isNotEmpty)
                    .join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.add),
            );
          },
        ),
      ),
    );
  }

  static String _mealTypeLabelOf(String tag) => switch (tag) {
    'breakfast' => '适合早餐',
    'lunch' => '适合午餐',
    'dinner' => '适合晚餐',
    _ => '',
  };
}

class _SelectedDishChip extends StatelessWidget {
  const _SelectedDishChip({required this.dish, required this.onRemove});

  final StandardDish dish;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PixelPanel(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(
        children: [
          PixelIconTile(
            icon: Icons.restaurant_outlined,
            size: 34,
            color: scheme.primaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(dish.name)),
          IconButton(
            tooltip: '换一道',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _DetailedSection extends StatelessWidget {
  const _DetailedSection({
    required this.gramsController,
    required this.servingsController,
    required this.categories,
    required this.categoryId,
    required this.homemade,
    required this.noteController,
    required this.canLink,
    required this.onGramsChanged,
    required this.onServingsChanged,
    required this.onCategoryChanged,
    required this.onHomemadeChanged,
  });

  final TextEditingController gramsController;
  final TextEditingController servingsController;
  final List<FoodCategory> categories;
  final String? categoryId;
  final bool homemade;
  final TextEditingController noteController;
  final bool canLink;
  final ValueChanged<String> onGramsChanged;
  final ValueChanged<String> onServingsChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<bool> onHomemadeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('详细填写', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '克重和份数填一个就行，另一个会自动算出来。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: gramsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '重量（克）',
                    hintText: '如 200',
                  ),
                  onChanged: onGramsChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Icon(
                  Icons.sync_alt,
                  color: canLink ? scheme.primary : scheme.outline,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: servingsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '份数',
                    hintText: '如 1.5',
                  ),
                  onChanged: onServingsChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: categoryId,
            decoration: const InputDecoration(
              labelText: '菜品分类（库外的菜选一个）',
            ),
            items: [
              for (final category in categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: onCategoryChanged,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('这是自己做的'),
            value: homemade,
            onChanged: (value) => onHomemadeChanged(value ?? false),
          ),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: '备注（选填）',
              hintText: '如：少油少盐',
            ),
          ),
        ],
      ),
    );
  }
}
