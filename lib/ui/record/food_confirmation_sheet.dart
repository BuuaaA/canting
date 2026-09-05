import 'package:flutter/material.dart';

import '../../core/models/local_food.dart';

const foodCategories = {
  'unknown': '未知',
  'milk_tea': '奶茶',
  'coffee': '咖啡',
  'beverage': '其他饮品',
  'burger': '汉堡',
  'sandwich': '三明治',
  'dessert': '甜品',
  'grains': '主食',
  'vegetables': '蔬菜',
  'fruits': '水果',
  'protein': '肉蛋豆类',
  'dairy': '奶类',
  'nuts': '坚果',
  'water': '水',
  'protein_soy': '豆制品',
  'mixed': '混合菜',
  'condiment': '调味品',
  'other': '其他食品',
};
const sugarLabels = {
  'unknown': '未知 / 待确认',
  'none': '无糖选项',
  'low': '低糖',
  'regular': '常规糖',
  'high': '高糖',
};
const cupLabels = {
  'unknown': '未知 / 待确认',
  'small': '小杯',
  'medium': '中杯',
  'large': '大杯',
};
const sizeLabels = {
  'unknown': '未知 / 待确认',
  'small': '小份',
  'normal': '正常份',
  'large': '大份',
};
const preparationLabels = {
  'unknown': '未知',
  'fried': '油炸',
  'grilled': '烤制',
  'steamed': '清蒸',
  'boiled': '水煮',
  'stir_fried': '炒制',
  'mixed': '多种做法',
  'pan_fried': '煎制',
  'raw': '生食',
  'stewed': '炖煮',
};
const sauceLabels = {
  'unknown': '未知',
  'none': '无酱',
  'light': '少酱',
  'regular': '常规酱料',
};

Future<FoodObservation?> showFoodConfirmation(
  BuildContext context,
  FoodObservation initial, {
  required String rawName,
  bool memoryOnly = false,
}) => showModalBottomSheet<FoodObservation>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FoodConfirmationSheet(
    initial: initial,
    rawName: rawName,
    memoryOnly: memoryOnly,
  ),
);

class FoodConfirmationSheet extends StatefulWidget {
  const FoodConfirmationSheet({
    super.key,
    required this.initial,
    required this.rawName,
    this.memoryOnly = false,
  });
  final FoodObservation initial;
  final String rawName;
  final bool memoryOnly;
  @override
  State<FoodConfirmationSheet> createState() => _FoodConfirmationSheetState();
}

class _FoodConfirmationSheetState extends State<FoodConfirmationSheet> {
  late final brand = TextEditingController(text: widget.initial.facts.brand);
  late final name = TextEditingController(text: widget.initial.facts.name);
  late String category = widget.initial.facts.category;
  late String preparation = widget.initial.facts.preparation;
  late String sauce = widget.initial.facts.sauce;
  late String sugar = widget.initial.spec.sugar;
  late String cup = widget.initial.spec.cup;
  late String size = widget.initial.spec.size;
  bool brandEdited = false;
  bool get drink => ['milk_tea', 'coffee', 'beverage'].contains(category);
  @override
  void dispose() {
    brand.dispose();
    name.dispose();
    super.dispose();
  }

  Widget select(
    String title,
    String value,
    Map<String, String> options,
    ValueChanged<String> update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: options.containsKey(value) ? value : 'unknown',
      key: ValueKey('$title-$value'),
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => update(v));
      },
    ),
  );
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        children: [
          Text(
            widget.memoryOnly ? '编辑本机记忆' : '归类与本次规格',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('原始商品：${widget.rawName}'),
          if (widget.initial.candidateName != null)
            Text('候选：${widget.initial.candidateName}；请确认品牌和做法，未自动套用'),
          const SizedBox(height: 12),
          select('商品类别', category, foodCategories, (v) => category = v),
          TextField(
            controller: brand,
            onChanged: (_) => brandEdited = true,
            decoration: const InputDecoration(labelText: '品牌（不确定可留空）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '标准化商品名'),
          ),
          const SizedBox(height: 12),
          if (!widget.memoryOnly) ...[
            if (widget.initial.suggestion != null)
              Text(
                '上次选择（仅建议）：${sugarLabels[widget.initial.suggestion!.sugar] ?? "不适用"} / ${cupLabels[widget.initial.suggestion!.cup] ?? "不适用"} / ${sizeLabels[widget.initial.suggestion!.size] ?? "未知"}。本次未填写的规格仍为未知。',
              ),
            if (widget.initial.suggestion?.conflicts(widget.initial.spec) ==
                true)
              const Text('本次规格与上次不同，采用本次输入。'),
            if (drink) ...[
              select('本次糖型', sugar, sugarLabels, (v) => sugar = v),
              select('本次杯型', cup, cupLabels, (v) => cup = v),
              const Text('无糖选项不代表总糖为零；杯型不换算为固定毫升。'),
            ] else
              select('实际食用份量', size, sizeLabels, (v) => size = v),
            if (RegExp(r'\d+\s*寸').hasMatch(widget.rawName))
              const Text('蛋糕尺寸是整只商品大小，请确认实际食用部分；不确定可保留未知。'),
          ],
          if ([
            'burger',
            'sandwich',
            'protein',
            'other',
          ].contains(category)) ...[
            select(
              '适用于此商品的做法',
              preparation,
              preparationLabels,
              (v) => preparation = v,
            ),
            select('适用于此商品的酱料', sauce, sauceLabels, (v) => sauce = v),
          ],
          const SizedBox(height: 12),
          const Text('已记录，饮食结构估算不完整。归类不会生成营养数值，也不会自动加入推荐。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                FoodObservation(
                  rawName: widget.rawName,
                  facts: FoodFacts(
                    brand: brand.text.trim(),
                    name: name.text.trim(),
                    category: category,
                    preparation: preparation,
                    sauce: sauce,
                  ),
                  spec: widget.memoryOnly
                      ? widget.initial.spec
                      : OrderSpec(sugar: sugar, cup: cup, size: size),
                  confirmed: true,
                  confirmedAt: DateTime.now(),
                  matchedBy: 'user_edit',
                  brandOrigin: brandEdited
                      ? 'explicit'
                      : widget.initial.brandOrigin,
                  merchantContext: widget.initial.merchantContext,
                  decision: FoodDecision.autoFill,
                ),
              );
            },
            child: Text(widget.memoryOnly ? '保存记忆修改' : '确认本次商品'),
          ),
        ],
      ),
    ),
  );
}
