import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pet_data.dart';

class PetSpriteWidget extends StatefulWidget {
  const PetSpriteWidget({
    super.key,
    required this.petType,
    required this.growthStage,
    required this.vitalityState,
    this.size = 64,
    this.animate = true,
  }) : assert(size > 0);

  static const frameDuration = Duration(milliseconds: 200);
  static const supportedGrowthStages = {'egg', 'baby', 'adult'};
  static const supportedVitalityStates = {
    'energetic',
    'good',
    'low',
    'expecting',
  };
  static final Future<Set<String>> _availableSpriteAssets =
      _loadAvailableSpriteAssets();

  final String petType;
  final String growthStage;
  final String vitalityState;
  final double size;
  final bool animate;

  static Future<Set<String>> _loadAvailableSpriteAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest
          .listAssets()
          .where((path) => path.startsWith('assets/sprites/'))
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  static int frameCountFor(String growthStage) {
    return switch (growthStage) {
      'egg' => 2,
      'baby' => 4,
      'adult' => 5,
      _ => throw ArgumentError.value(
        growthStage,
        'growthStage',
        'Unsupported growth stage',
      ),
    };
  }

  static String assetPath({
    required String petType,
    required String growthStage,
    required String vitalityState,
    required int frame,
  }) {
    _validateConfiguration(
      petType: petType,
      growthStage: growthStage,
      vitalityState: vitalityState,
    );
    if (frame < 0 || frame >= frameCountFor(growthStage)) {
      throw RangeError.range(frame, 0, frameCountFor(growthStage) - 1, 'frame');
    }
    return 'assets/sprites/'
        'pet_${petType}_${growthStage}_${vitalityState}_$frame.png';
  }

  static void _validateConfiguration({
    required String petType,
    required String growthStage,
    required String vitalityState,
  }) {
    if (!PetData.supportedPetTypes.contains(petType)) {
      throw ArgumentError.value(petType, 'petType', 'Unsupported pet type');
    }
    if (!supportedGrowthStages.contains(growthStage)) {
      throw ArgumentError.value(
        growthStage,
        'growthStage',
        'Unsupported growth stage',
      );
    }
    if (!supportedVitalityStates.contains(vitalityState)) {
      throw ArgumentError.value(
        vitalityState,
        'vitalityState',
        'Unsupported vitality state',
      );
    }
  }

  @override
  State<PetSpriteWidget> createState() => _PetSpriteWidgetState();
}

class _PetSpriteWidgetState extends State<PetSpriteWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _motionAllowed = true;

  int get _frameCount => PetSpriteWidget.frameCountFor(widget.growthStage);

  @override
  void initState() {
    super.initState();
    PetSpriteWidget._validateConfiguration(
      petType: widget.petType,
      growthStage: widget.growthStage,
      vitalityState: widget.vitalityState,
    );
    _controller = AnimationController(
      vsync: this,
      duration: PetSpriteWidget.frameDuration * _frameCount,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motionAllowed = !MediaQuery.disableAnimationsOf(context);
    if (_motionAllowed == motionAllowed && _controller.isAnimating) return;
    _motionAllowed = motionAllowed;
    _syncPlayback(reset: !motionAllowed);
  }

  @override
  void didUpdateWidget(covariant PetSpriteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    PetSpriteWidget._validateConfiguration(
      petType: widget.petType,
      growthStage: widget.growthStage,
      vitalityState: widget.vitalityState,
    );
    final spriteChanged =
        oldWidget.petType != widget.petType ||
        oldWidget.growthStage != widget.growthStage ||
        oldWidget.vitalityState != widget.vitalityState;
    if (spriteChanged) {
      _controller.duration = PetSpriteWidget.frameDuration * _frameCount;
    }
    if (spriteChanged || oldWidget.animate != widget.animate) {
      _syncPlayback(reset: spriteChanged || !widget.animate);
    }
  }

  void _syncPlayback({required bool reset}) {
    if (reset) {
      _controller.value = 0;
    }
    if (widget.animate && _motionAllowed) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final frame = widget.animate && _motionAllowed
            ? (_controller.value * _frameCount).floor() % _frameCount
            : 0;
        final assetPath = PetSpriteWidget.assetPath(
          petType: widget.petType,
          growthStage: widget.growthStage,
          vitalityState: widget.vitalityState,
          frame: frame,
        );

        return Semantics(
          label: '${widget.petType} ${widget.vitalityState}',
          image: true,
          child: SizedBox.square(
            key: ValueKey('pet-sprite-frame-$frame'),
            dimension: widget.size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _PetSpritePlaceholder(
                  petType: widget.petType,
                  growthStage: widget.growthStage,
                  vitalityState: widget.vitalityState,
                  size: widget.size,
                ),
                FutureBuilder<Set<String>>(
                  future: PetSpriteWidget._availableSpriteAssets,
                  builder: (context, snapshot) {
                    if (!(snapshot.data?.contains(assetPath) ?? false)) {
                      return const SizedBox.shrink();
                    }
                    return Image.asset(
                      assetPath,
                      width: widget.size,
                      height: widget.size,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox.shrink();
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PetSpritePlaceholder extends StatelessWidget {
  const _PetSpritePlaceholder({
    required this.petType,
    required this.growthStage,
    required this.vitalityState,
    required this.size,
  });

  final String petType;
  final String growthStage;
  final String vitalityState;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('pet-sprite-placeholder'),
      size: Size.square(size),
      painter: _PixelPetPainter(
        petType: petType,
        growthStage: growthStage,
        vitalityState: vitalityState,
      ),
    );
  }
}

class _PixelPetPainter extends CustomPainter {
  const _PixelPetPainter({
    required this.petType,
    required this.growthStage,
    required this.vitalityState,
  });

  final String petType;
  final String growthStage;
  final String vitalityState;

  static const _outline = Color(0xFF4E3524);
  static const _cream = Color(0xFFFFE7AD);
  static const _blush = Color(0xFFE98A6A);
  static const _shadow = Color(0x55332B24);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 16;
    final left = (size.width - unit * 16) / 2;
    final top = (size.height - unit * 16) / 2;
    final paint = Paint()..isAntiAlias = false;

    void pixel(double x, double y, double width, double height, Color color) {
      paint.color = color;
      canvas.drawRect(
        Rect.fromLTWH(
          left + x * unit,
          top + y * unit,
          width * unit,
          height * unit,
        ),
        paint,
      );
    }

    pixel(3, 14, 10, 1, _shadow);
    if (growthStage == 'egg') {
      _paintEgg(pixel);
      return;
    }

    final base = _petColor();
    final light = Color.lerp(base, Colors.white, 0.28)!;
    final dark = Color.lerp(base, _outline, 0.22)!;
    final isAdult = growthStage == 'adult';

    if (petType == 'cat') {
      pixel(3, 2, 3, 3, _outline);
      pixel(10, 2, 3, 3, _outline);
      pixel(4, 3, 2, 2, base);
      pixel(10, 3, 2, 2, base);
      pixel(12, 10, 2, 1, _outline);
      pixel(13, 8, 1, 3, _outline);
      pixel(12, 8, 1, 1, base);
    } else if (petType == 'dog') {
      pixel(2, 4, 3, 5, _outline);
      pixel(11, 4, 3, 5, _outline);
      pixel(3, 5, 2, 3, dark);
      pixel(11, 5, 2, 3, dark);
      pixel(13, 11, 2, 2, _outline);
      pixel(13, 10, 1, 1, base);
    } else {
      pixel(3, 3, 3, 3, _outline);
      pixel(10, 3, 3, 3, _outline);
      pixel(4, 4, 1, 1, _blush);
      pixel(11, 4, 1, 1, _blush);
    }

    pixel(3, 4, 10, 8, _outline);
    pixel(4, 5, 8, 6, base);
    pixel(5, 10, 6, 4, _outline);
    pixel(6, 10, 4, 3, dark);
    if (isAdult) {
      pixel(3, 11, 2, 3, _outline);
      pixel(11, 11, 2, 3, _outline);
      pixel(4, 11, 1, 2, base);
      pixel(11, 11, 1, 2, base);
    }

    pixel(5, 5, 6, 1, light);
    final tired = vitalityState == 'low' || vitalityState == 'expecting';
    if (tired) {
      pixel(5, 7, 2, 1, _outline);
      pixel(9, 7, 2, 1, _outline);
    } else {
      pixel(5, 7, 2, 2, _outline);
      pixel(9, 7, 2, 2, _outline);
      pixel(5, 7, 1, 1, Colors.white);
      pixel(9, 7, 1, 1, Colors.white);
    }
    pixel(7, 9, 2, 1, _outline);
    pixel(6, 10, 1, 1, _blush);
    pixel(10, 10, 1, 1, _blush);

    if (vitalityState == 'energetic') {
      pixel(1, 2, 1, 2, const Color(0xFFF2C66D));
      pixel(14, 3, 1, 2, const Color(0xFFF2C66D));
    }
  }

  void _paintEgg(void Function(double, double, double, double, Color) pixel) {
    pixel(6, 2, 4, 1, _outline);
    pixel(4, 3, 8, 2, _outline);
    pixel(3, 5, 10, 6, _outline);
    pixel(4, 11, 8, 2, _outline);
    pixel(6, 13, 4, 1, _outline);
    pixel(6, 3, 4, 1, _cream);
    pixel(5, 4, 6, 2, _cream);
    pixel(4, 6, 8, 5, _cream);
    pixel(5, 11, 6, 1, _cream);
    pixel(5, 6, 2, 2, const Color(0xFF78A554));
    pixel(9, 9, 2, 2, const Color(0xFFC75B45));
  }

  Color _petColor() {
    final base = switch (petType) {
      'cat' => const Color(0xFFE59A57),
      'dog' => const Color(0xFFD8AF68),
      _ => const Color(0xFFC99069),
    };
    return switch (vitalityState) {
      'energetic' => base,
      'good' => Color.lerp(base, const Color(0xFF78A554), 0.12)!,
      'low' => Color.lerp(base, const Color(0xFF7C91A4), 0.36)!,
      _ => Color.lerp(base, const Color(0xFF9B8AA7), 0.28)!,
    };
  }

  @override
  bool shouldRepaint(covariant _PixelPetPainter oldDelegate) {
    return oldDelegate.petType != petType ||
        oldDelegate.growthStage != growthStage ||
        oldDelegate.vitalityState != vitalityState;
  }
}
