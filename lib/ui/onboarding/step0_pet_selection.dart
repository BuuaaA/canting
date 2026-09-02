import 'package:canting/pet.dart';
import 'package:canting/state/onboarding_draft.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class Step0PetSelection extends StatefulWidget {
  const Step0PetSelection({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  State<Step0PetSelection> createState() => _Step0PetSelectionState();
}

class _Step0PetSelectionState extends State<Step0PetSelection> {
  late final TextEditingController _nameController;

  static const _pets = [
    (type: 'cat', name: '小猫', color: Color(0xFFFFD7C2)),
    (type: 'dog', name: '小狗', color: Color(0xFFFFE5A8)),
    (type: 'hamster', name: '仓鼠', color: Color(0xFFD8E9CE)),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.draft.petName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final length = widget.draft.petName.trim().runes.length;
    final hasError = length < 1 || length > 6;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
      children: [
        Text('选择伙伴', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '它会陪你记录每一餐，慢慢长大。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            for (var index = 0; index < _pets.length; index++) ...[
              Expanded(
                child: _PetChoice(
                  pet: _pets[index],
                  selected: widget.draft.petType == _pets[index].type,
                  onTap: () {
                    setState(() => widget.draft.petType = _pets[index].type);
                  },
                ),
              ),
              if (index != _pets.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 30),
        Text('给伙伴起个名字', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          maxLength: 6,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '1-6 个字符',
            prefixIcon: const Icon(Icons.edit_outlined),
            errorText: hasError ? '昵称需要 1-6 个字符' : null,
          ),
          onChanged: (value) {
            setState(() => widget.draft.petName = value);
          },
        ),
        const SizedBox(height: 20),
        PixelPanel(
          color: theme.colorScheme.secondaryContainer,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.favorite_outline,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '记录饮食会增加活力与成长值，忘记记录也不会受到责备。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PetChoice extends StatelessWidget {
  const _PetChoice({
    required this.pet,
    required this.selected,
    required this.onTap,
  });

  final ({String type, String name, Color color}) pet;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PixelPanel(
      color: pet.color.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.8,
      ),
      borderColor: selected ? scheme.primary : scheme.outline,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
      child: Column(
        children: [
          PetSpriteWidget(
            petType: pet.type,
            growthStage: 'baby',
            vitalityState: 'energetic',
            size: 64,
          ),
          const SizedBox(height: 8),
          Text(
            pet.name,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          Icon(
            selected ? Icons.check_box : Icons.check_box_outline_blank,
            color: selected ? scheme.primary : scheme.outline,
            size: 20,
          ),
        ],
      ),
    );
  }
}
