import 'package:flutter/material.dart';

import 'pet_sprite_widget.dart';

class EvolutionAnimationWidget extends StatefulWidget {
  const EvolutionAnimationWidget({
    super.key,
    required this.petType,
    required this.fromStage,
    required this.toStage,
    required this.petName,
    this.onFinished,
  }) : assert(
         (fromStage == 'egg' && toStage == 'baby') ||
             (fromStage == 'baby' && toStage == 'adult'),
       );

  static const duration = Duration(seconds: 2);

  final String petType;
  final String fromStage;
  final String toStage;
  final String petName;
  final VoidCallback? onFinished;

  @override
  State<EvolutionAnimationWidget> createState() =>
      _EvolutionAnimationWidgetState();
}

class _EvolutionAnimationWidgetState extends State<EvolutionAnimationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: EvolutionAnimationWidget.duration,
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.75,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1), weight: 45),
    ]).animate(_controller);
    _controller.addStatusListener(_handleStatus);
    _controller.forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _visible = false);
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink(
        key: ValueKey('evolution-animation-finished'),
      );
    }

    // 遮罩颜色根据主题亮度自适应：浅色用半透明白，深色用半透明深蓝黑
    // 浅色：0xD8FFFFFF = 白色 85% 不透明（原 0xEF 太亮 94%）
    // 深色：0xE01A1F2E = 深蓝黑 88% 不透明，避免白色遮罩在暗背景上过曝刺眼
    final brightness = Theme.of(context).brightness;
    final overlayColor = brightness == Brightness.dark
        ? const Color(0xE01A1F2E)
        : const Color(0xD8FFFFFF);

    return IgnorePointer(
      child: SizedBox.expand(
        key: const ValueKey('evolution-animation'),
        child: ColoredBox(
          color: overlayColor,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final currentStage = _controller.value < 0.5
                  ? widget.fromStage
                  : widget.toStage;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: _scale.value,
                      child: PetSpriteWidget(
                        key: ValueKey('evolution-$currentStage'),
                        petType: widget.petType,
                        growthStage: currentStage,
                        vitalityState: 'energetic',
                        size: 128,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '${widget.petName}长大了！',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
