import 'package:canting/services/delivery_jump_service.dart';
import 'package:flutter/material.dart';

/// 外卖平台跳转按钮组：品牌色背景 + 白字，最多显示 3 个（文档口径）。
class PlatformButtons extends StatelessWidget {
  const PlatformButtons({
    super.key,
    required this.platforms,
    required this.keyword,
    required this.onJump,
    this.maxVisible = 3,
  });

  final List<DeliveryPlatform> platforms;
  final String keyword;
  final void Function(DeliveryPlatform platform, String keyword) onJump;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final visible = platforms.take(maxVisible).toList(growable: false);
    return Row(
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _PlatformButton(
              platform: visible[index],
              onTap: () => onJump(visible[index], keyword),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlatformButton extends StatelessWidget {
  const _PlatformButton({required this.platform, required this.onTap});

  final DeliveryPlatform platform;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(platform.brandColor);
    return SizedBox(
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Text(
                platform.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
