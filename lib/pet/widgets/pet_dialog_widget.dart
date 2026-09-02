import 'dart:async';

import 'package:flutter/material.dart';

class PetDialogWidget extends StatefulWidget {
  const PetDialogWidget({
    super.key,
    required this.text,
    this.duration = const Duration(seconds: 3),
    this.onDismissed,
  });

  final String text;
  final Duration duration;
  final VoidCallback? onDismissed;

  @override
  State<PetDialogWidget> createState() => _PetDialogWidgetState();
}

class _PetDialogWidgetState extends State<PetDialogWidget> {
  static const _fadeDuration = Duration(milliseconds: 160);

  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant PetDialogWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.duration != widget.duration) {
      _visible = true;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.duration, () {
      if (!mounted) return;
      setState(() => _visible = false);
      widget.onDismissed?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _fadeDuration,
      child: _visible
          ? Semantics(
              key: ValueKey(widget.text),
              liveRegion: true,
              label: widget.text,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.9),
                    border: Border.all(color: scheme.outline, width: 2),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.outline.withValues(alpha: 0.42),
                        blurRadius: 0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      widget.text,
                      softWrap: true,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('pet-dialog-hidden')),
    );
  }
}
