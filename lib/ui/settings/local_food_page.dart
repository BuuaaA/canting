import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../core/models/local_food.dart';
import '../record/food_confirmation_sheet.dart';

import 'dart:convert';

class LocalFoodPage extends StatelessWidget {
  const LocalFoodPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('本机商品记忆'),
        actions: [
          IconButton(
            tooltip: '导出记忆 JSON',
            icon: const Icon(Icons.download),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: const JsonEncoder.withIndent(
                    '  ',
                  ).convert(state.localFoods.map((p) => p.toJson()).toList()),
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('记忆 JSON 已复制')));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('修改仅影响未来匹配，历史餐食保留当时快照。上次规格只是建议。'),
          if (state.localFoods.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无记忆，在识别结果中确认商品后会保存在这里。'),
            ),
          for (final profile in state.localFoods)
            Card(
              child: ListTile(
                title: Text(
                  '${profile.facts.brand.isEmpty ? "无品牌" : profile.facts.brand} · ${profile.facts.name}',
                ),
                subtitle: Text(
                  '${foodCategories[profile.facts.category] ?? profile.facts.category} · ${preparationLabels[profile.facts.preparation]}\n使用 ${profile.useCount} 次 · ${profile.updatedAt.toLocal().toString().substring(0, 16)}\n用户本机确认 · 贡献未知',
                ),
                onTap: () async {
                  final result = await showFoodConfirmation(
                    context,
                    FoodObservation(
                      facts: profile.facts,
                      spec: profile.lastSpec,
                    ),
                    rawName: profile.facts.name,
                    memoryOnly: true,
                  );
                  if (result == null) return;
                  try {
                    await state.editLocalFood(
                      profile.facts.key,
                      LocalFoodProfile(
                        facts: result.facts,
                        createdAt: profile.createdAt,
                        updatedAt: DateTime.now(),
                        useCount: profile.useCount,
                        lastSpec: profile.lastSpec,
                        rawNames: profile.rawNames,
                      ),
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('记忆未修改：$e')));
                    }
                  }
                },
                trailing: IconButton(
                  tooltip: '删除记忆',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('删除这条记忆？'),
                        content: const Text('历史餐食不受影响，下次恢复普通匹配。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      try {
                        await state.deleteLocalFood(profile.facts.key);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('删除失败：$e')));
                        }
                      }
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
