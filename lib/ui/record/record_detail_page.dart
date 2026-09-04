import 'package:canting/core_engine.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/record/dish_edit_list.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class RecordDetailPage extends StatefulWidget {
  const RecordDetailPage({
    super.key,
    this.mealId,
    this.initialDate,
    this.returnLocation = '/home',
    this.isSharedRecognition = false,
  });

  final String? mealId;
  final DateTime? initialDate;
  final String returnLocation;
  final bool isSharedRecognition;

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  late final TextEditingController _merchantController;
  late List<MealDish> _dishes;
  late String _mealType;
  late DateTime _mealTime;
  MealRecord? _originalMeal;
  RecognitionDraft? _appliedRecognitionDraft;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    final recognitionDraft = widget.isSharedRecognition
        ? state.recognitionDraft
        : null;
    if (_initialized) {
      if (recognitionDraft != null &&
          !identical(recognitionDraft, _appliedRecognitionDraft)) {
        _appliedRecognitionDraft = recognitionDraft;
        _merchantController.text = recognitionDraft.merchant;
        _dishes = recognitionDraft.dishes
            .map((dish) => dish.copyWith())
            .toList(growable: true);
      }
      return;
    }
    _initialized = true;
    _appliedRecognitionDraft = recognitionDraft;

    _originalMeal = widget.mealId == null
        ? null
        : state.mealById(widget.mealId!);
    final now = DateTime.now();
    final baseDate = widget.initialDate ?? now;
    _mealTime =
        _originalMeal?.timestamp ??
        DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          now.hour,
          now.minute,
        );
    _mealType = _originalMeal?.mealType ?? _mealTypeFor(_mealTime.hour);
    _dishes =
        _originalMeal?.dishes
            .map((dish) => dish.copyWith())
            .toList(growable: true) ??
        recognitionDraft?.dishes
            .map((dish) => dish.copyWith())
            .toList(growable: true) ??
        (widget.isSharedRecognition ? [] : []);
    _merchantController = TextEditingController(
      text: _originalMeal?.merchant ?? recognitionDraft?.merchant ?? '',
    );
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  void _updateDish(int index, MealDish dish) {
    setState(() => _dishes[index] = dish);
  }

  Future<void> _addDish() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _DishSearchDialog(),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _dishes.add(MealDish(name: result)));
    }
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _mealTime,
    );
    if (result != null) {
      setState(() {
        _mealTime = DateTime(
          result.year,
          result.month,
          result.day,
          _mealTime.hour,
          _mealTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_mealTime),
    );
    if (result != null) {
      setState(() {
        _mealTime = DateTime(
          _mealTime.year,
          _mealTime.month,
          _mealTime.day,
          result.hour,
          result.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    final merchant = _merchantController.text.trim();
    final validDishes = _dishes
        .where((dish) => dish.name.trim().isNotEmpty)
        .toList(growable: false);
    if (validDishes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少添加一道菜')));
      return;
    }

    final appState = context.read<AppState>();
    final meal = appState.buildMealRecord(
      mealType: _mealType,
      timestamp: _mealTime,
      dishes: validDishes,
      merchant: merchant.isEmpty ? null : merchant,
      mealId: _originalMeal?.mealId,
    );
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    await appState.saveMeal(
      meal,
      source: widget.isSharedRecognition ? 'ocr' : 'manual',
    );
    appState.clearSharedRecognition();
    router.go(widget.returnLocation);
    messenger.showSnackBar(const SnackBar(content: Text('这顿已经保存好啦')));
  }

  Future<void> _delete() async {
    final meal = _originalMeal;
    if (meal == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除后会重新计算完成度，并回退伙伴活力值。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final appState = context.read<AppState>();
      final router = GoRouter.of(context);
      await appState.deleteMeal(meal.mealId);
      router.go(widget.returnLocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recognitionDraft = widget.isSharedRecognition
        ? context.watch<AppState>().recognitionDraft
        : null;
    final recognitionLoading = recognitionDraft?.isLoading ?? false;
    final recognitionError = recognitionDraft?.error;
    return Scaffold(
      appBar: PixelAppBar(
        title: _originalMeal == null ? '识别结果' : '记录详情',
        leading: const BackButton(),
        actions: [
          if (_originalMeal != null)
            IconButton(
              tooltip: '删除记录',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            children: [
              PixelPanel(
                color: recognitionError == null
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.errorContainer,
                borderColor: recognitionError == null
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    PixelIconTile(
                      icon: recognitionLoading
                          ? Icons.hourglass_top
                          : recognitionError == null
                          ? Icons.check
                          : Icons.image_not_supported_outlined,
                      size: 38,
                      color: recognitionError == null
                          ? theme.colorScheme.secondaryContainer
                          : theme.colorScheme.errorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recognitionLoading
                                ? '正在识别'
                                : recognitionError == null
                                ? '识别完成'
                                : '识别失败',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            recognitionLoading
                                ? '正在读取图片中的菜单文字'
                                : recognitionError ??
                                      '找到 ${_dishes.length} 道菜，请核对菜名和分量',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const PixelSectionHeader(
                title: '订单信息',
                icon: Icons.storefront_outlined,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _merchantController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.storefront_outlined),
                  hintText: '商家名称',
                ),
              ),
              const SizedBox(height: 22),
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
                  onSelectionChanged: (value) {
                    setState(() => _mealType = value.first);
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        '${_mealTime.year}-${_mealTime.month.toString().padLeft(2, '0')}-'
                        '${_mealTime.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        '${_mealTime.hour.toString().padLeft(2, '0')}:'
                        '${_mealTime.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  const Expanded(
                    child: PixelSectionHeader(
                      title: '菜品与分量',
                      icon: Icons.restaurant_menu,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addDish,
                    icon: const Icon(Icons.add),
                    label: const Text('添加'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_dishes.isEmpty)
                const PixelPanel(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('没有识别出菜品，请手动添加')),
                )
              else
                DishEditList(
                  dishes: _dishes,
                  onChanged: _updateDish,
                  onDelete: (index) => setState(() => _dishes.removeAt(index)),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outline, width: 2),
          ),
        ),
        child: SafeArea(
          child: PixelContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存并更新今日结构'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _mealTypeFor(int hour) {
    if (hour < 10) return 'breakfast';
    if (hour < 15) return 'lunch';
    if (hour < 21) return 'dinner';
    return 'snack';
  }
}

/// 添加菜品对话框：实时搜索（自定义菜优先、按使用次数排序），
/// 也可以直接用输入的菜名。
class _DishSearchDialog extends StatefulWidget {
  const _DishSearchDialog();

  @override
  State<_DishSearchDialog> createState() => _DishSearchDialogState();
}

class _DishSearchDialogState extends State<_DishSearchDialog> {
  final _controller = TextEditingController();
  List<StandardDish> _results = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final results = await context
        .read<AppState>()
        .searchDishesForManualAdd(query);
    if (mounted) {
      setState(() => _results = results);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typedName = _controller.text.trim();
    return AlertDialog(
      title: const Text('添加菜品'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索或输入菜名',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {});
                _search(value);
              },
              onSubmitted: (value) =>
                  Navigator.pop(context, value.trim()),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _results.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_results[index].name),
                        trailing: const Icon(Icons.add),
                        onTap: () =>
                            Navigator.pop(context, _results[index].name),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: typedName.isEmpty
              ? null
              : () => Navigator.pop(context, typedName),
          child: const Text('添加'),
        ),
      ],
    );
  }
}
