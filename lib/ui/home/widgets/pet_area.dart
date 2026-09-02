import 'dart:async';

import 'package:canting/pet.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PetArea extends StatefulWidget {
  const PetArea({super.key});

  @override
  State<PetArea> createState() => _PetAreaState();
}

class _PetAreaState extends State<PetArea> {
  Timer? _restoreTimer;

  @override
  void dispose() {
    _restoreTimer?.cancel();
    super.dispose();
  }

  void _tapPet(AppState state) {
    final applied = state.tapPet();
    _restoreTimer?.cancel();
    _restoreTimer = Timer(
      Duration(seconds: applied ? 2 : 3),
      state.restorePetDialogue,
    );
  }

  void _showPetInfo(BuildContext context, AppState state) {
    final pet = state.pet;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(title: '${pet.petName}的状态', icon: Icons.pets),
              const SizedBox(height: 18),
              PixelPanel(
                child: Column(
                  children: [
                    _InfoRow(label: '伙伴', value: _petTypeLabel(pet.petType)),
                    const PixelDivider(),
                    _InfoRow(
                      label: '成长阶段',
                      value: _stageLabel(pet.growthStage),
                    ),
                    const PixelDivider(),
                    _InfoRow(label: '活力值', value: '${pet.vitality} / 100'),
                    const PixelDivider(),
                    _InfoRow(label: '成长值', value: '${pet.growth}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pet = state.pet;
    final scheme = Theme.of(context).colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final height = state.petAreaCollapsed
        ? 58.0
        : (screenHeight * 0.19).clamp(116.0, 152.0);

    return AnimatedContainer(
      key: const ValueKey('home-pet-area'),
      height: height,
      duration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline, width: 2),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: scheme.outline.withValues(alpha: 0.75),
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FarmScenePainter(
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
          if (state.petAreaCollapsed)
            _CollapsedPetArea(
              height: height,
              pet: pet,
              onTap: () => _tapPet(state),
              onLongPress: () => _showPetInfo(context, state),
            )
          else
            _ExpandedPetArea(
              height: height,
              pet: pet,
              dialogue: state.petDialogue,
              onTap: () => _tapPet(state),
              onLongPress: () => _showPetInfo(context, state),
            ),
          Positioned(
            right: 3,
            top: 3,
            child: IconButton(
              tooltip: state.petAreaCollapsed ? '展开伙伴区' : '收起伙伴区',
              onPressed: state.togglePetArea,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surfaceContainerLowest.withValues(
                  alpha: 0.88,
                ),
                side: BorderSide(color: scheme.outline),
                minimumSize: const Size.square(40),
              ),
              icon: Icon(
                state.petAreaCollapsed
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _petTypeLabel(String value) => switch (value) {
    'cat' => '小猫',
    'dog' => '小狗',
    _ => '仓鼠',
  };

  static String _stageLabel(GrowthStage value) => switch (value) {
    GrowthStage.egg => '萌芽期',
    GrowthStage.baby => '幼年期',
    GrowthStage.adult => '成年期',
  };
}

class _ExpandedPetArea extends StatelessWidget {
  const _ExpandedPetArea({
    required this.height,
    required this.pet,
    required this.dialogue,
    required this.onTap,
    required this.onLongPress,
  });

  final double height;
  final PetData pet;
  final String dialogue;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final growthTarget = switch (pet.growthStage) {
      GrowthStage.egg => 50,
      GrowthStage.baby => 200,
      GrowthStage.adult => 200,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 48, 6),
      child: Row(
        children: [
          SizedBox(
            width: (height * 0.66).clamp(82.0, 104.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '摸摸${pet.petName}，长按查看状态',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      onLongPress: onLongPress,
                      child: Center(
                        child: PetSpriteWidget(
                          petType: pet.petType,
                          growthStage: pet.growthStage.name,
                          vitalityState: pet.vitalityState.name,
                          size: (height - 50).clamp(72.0, 100.0),
                        ),
                      ),
                    ),
                  ),
                ),
                PixelBadge(
                  label: _PetAreaState._stageLabel(pet.growthStage),
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pet.petName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                PetDialogWidget(key: ValueKey(dialogue), text: dialogue),
                const SizedBox(height: 8),
                _SceneProgress(
                  label: 'VIT',
                  value: pet.vitality / 100,
                  trailing: '${pet.vitality}',
                  color: scheme.primary,
                ),
                const SizedBox(height: 5),
                _SceneProgress(
                  label: 'GROW',
                  value: pet.growth / growthTarget,
                  trailing: '${pet.growth}',
                  color: AppTheme.sun,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedPetArea extends StatelessWidget {
  const _CollapsedPetArea({
    required this.height,
    required this.pet,
    required this.onTap,
    required this.onLongPress,
  });

  final double height;
  final PetData pet;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 52, 5),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '摸摸${pet.petName}，长按查看状态',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: onLongPress,
              child: PetSpriteWidget(
                petType: pet.petType,
                growthStage: pet.growthStage.name,
                vitalityState: pet.vitalityState.name,
                size: height - 10,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${pet.petName} · 活力 ${pet.vitality}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneProgress extends StatelessWidget {
  const _SceneProgress({
    required this.label,
    required this.value,
    required this.trailing,
    required this.color,
  });

  final String label;
  final double value;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 37,
          child: Text(
            label,
            style: AppTheme.pixelText(
              context,
              fontSize: 7,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: PixelProgressBar(
            value: value,
            segments: 8,
            height: 8,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 24,
          child: Text(
            trailing,
            textAlign: TextAlign.end,
            style: AppTheme.pixelText(context, fontSize: 7),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FarmScenePainter extends CustomPainter {
  const _FarmScenePainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    final sky = dark ? const Color(0xFF29444A) : AppTheme.sky;
    final grass = dark ? const Color(0xFF31543A) : const Color(0xFF8DBB65);
    final grassDark = dark ? const Color(0xFF24432D) : const Color(0xFF5D8D46);
    final cloud = dark ? const Color(0xFF78959A) : const Color(0xFFF7F2DA);
    final fence = dark ? const Color(0xFF806348) : const Color(0xFFC69458);
    final fenceDark = dark ? const Color(0xFF553F33) : AppTheme.wood;

    paint.color = sky;
    canvas.drawRect(Offset.zero & size, paint);

    paint.color = cloud;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.08, 18, 34, 8), paint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.12, 12, 22, 8), paint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.61, 30, 42, 7), paint);

    final groundTop = size.height * 0.64;
    paint.color = grass;
    canvas.drawRect(
      Rect.fromLTWH(0, groundTop, size.width, size.height - groundTop),
      paint,
    );
    paint.color = grassDark;
    for (var x = 6.0; x < size.width; x += 18) {
      final y = groundTop + ((x / 18).round().isEven ? 15 : 27);
      canvas.drawRect(Rect.fromLTWH(x, y, 3, 8), paint);
      canvas.drawRect(Rect.fromLTWH(x + 3, y + 3, 3, 3), paint);
    }

    final fenceY = groundTop - 7;
    paint.color = fenceDark;
    canvas.drawRect(Rect.fromLTWH(0, fenceY + 7, size.width, 5), paint);
    paint.color = fence;
    canvas.drawRect(Rect.fromLTWH(0, fenceY + 3, size.width, 5), paint);
    for (var x = 8.0; x < size.width; x += 34) {
      paint.color = fenceDark;
      canvas.drawRect(Rect.fromLTWH(x, fenceY - 10, 8, 25), paint);
      paint.color = fence;
      canvas.drawRect(Rect.fromLTWH(x + 1, fenceY - 9, 6, 21), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FarmScenePainter oldDelegate) {
    return oldDelegate.dark != dark;
  }
}
