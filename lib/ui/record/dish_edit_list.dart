import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class DishEditList extends StatelessWidget {
  const DishEditList({
    super.key,
    required this.dishes,
    required this.onChanged,
    required this.onDelete,
  });

  final List<MockDish> dishes;
  final void Function(int index, MockDish dish) onChanged;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < dishes.length; index++) ...[
          _DishEditRow(
            key: ValueKey('dish-row-$index'),
            dish: dishes[index],
            onChanged: (dish) => onChanged(index, dish),
            onDelete: () => onDelete(index),
          ),
          if (index != dishes.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _DishEditRow extends StatefulWidget {
  const _DishEditRow({
    super.key,
    required this.dish,
    required this.onChanged,
    required this.onDelete,
  });

  final MockDish dish;
  final ValueChanged<MockDish> onChanged;
  final VoidCallback onDelete;

  @override
  State<_DishEditRow> createState() => _DishEditRowState();
}

class _DishEditRowState extends State<_DishEditRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.dish.name);
  }

  @override
  void didUpdateWidget(covariant _DishEditRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dish.name != widget.dish.name &&
        _controller.text != widget.dish.name) {
      _controller.text = widget.dish.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PixelPanel(
      padding: const EdgeInsets.all(14),
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: '菜名',
                    prefixIcon: Icon(Icons.restaurant_outlined),
                  ),
                  onChanged: (name) {
                    widget.onChanged(widget.dish.copyWith(name: name));
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '删除菜品',
                onPressed: widget.onDelete,
                color: scheme.error,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'small', label: Text('小份')),
                ButtonSegment(value: 'normal', label: Text('正常')),
                ButtonSegment(value: 'large', label: Text('大份')),
              ],
              selected: {widget.dish.portionSize},
              onSelectionChanged: (value) {
                widget.onChanged(
                  widget.dish.copyWith(portionSize: value.first),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
