import 'package:canting/pet.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/state/onboarding_draft.dart';
import 'package:canting/ui/onboarding/step0_pet_selection.dart';
import 'package:canting/ui/onboarding/step1_basic_info.dart';
import 'package:canting/ui/onboarding/step2_diet_goal.dart';
import 'package:canting/ui/onboarding/step3_activity.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _stepNames = ['欢迎', '身体信息', '活动水平', '饮食目标', '选择伙伴'];

  final _controller = PageController();
  final _draft = OnboardingDraft();
  int _step = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int target) {
    setState(() => _step = target);
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_step < _stepNames.length - 1) {
      _goTo(_step + 1);
      return;
    }

    final name = _draft.petName.trim();
    if (name.runes.isEmpty || name.runes.length > 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('宠物昵称需要 1-6 个字符')));
      return;
    }

    context.read<AppState>().completeOnboarding(
      setupProfile: SetupProfile(
        gender: _draft.gender,
        heightCm: _draft.heightCm,
        weightKg: _draft.weightKg,
        age: _draft.age,
        activityLevel: _draft.activityLevel,
        dietGoal: _draft.dietGoal,
        breakfast: _draft.breakfast,
        lunch: _draft.lunch,
        dinner: _draft.dinner,
        dayBoundaryHour: _draft.dayBoundaryHour,
      ),
      petType: _draft.petType,
      petName: name,
    );
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _step > 0) _goTo(_step - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: PixelBackdrop(
            child: PixelContentWidth(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 20, 10),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 48,
                          child: _step > 0
                              ? IconButton(
                                  tooltip: '上一步',
                                  onPressed: () => _goTo(_step - 1),
                                  icon: const Icon(Icons.arrow_back),
                                )
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${_step + 1} / ${_stepNames.length}  ${_stepNames[_step]}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              _PixelStepTracker(
                                count: _stepNames.length,
                                current: _step,
                                activeColor: scheme.primary,
                                inactiveColor: scheme.surfaceContainerHighest,
                                borderColor: scheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _controller,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        const _WelcomeStep(),
                        Step1BasicInfo(draft: _draft),
                        Step3Activity(draft: _draft),
                        Step2DietGoal(draft: _draft),
                        Step0PetSelection(draft: _draft),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline, width: 2)),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 632),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _next,
                    icon: Icon(
                      _step == _stepNames.length - 1
                          ? Icons.check
                          : Icons.arrow_forward,
                    ),
                    label: Text(
                      _step == 0
                          ? '开始设置'
                          : _step == _stepNames.length - 1
                          ? '一起开始'
                          : '下一步',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelStepTracker extends StatelessWidget {
  const _PixelStepTracker({
    required this.count,
    required this.current,
    required this.activeColor,
    required this.inactiveColor,
    required this.borderColor,
  });

  final int count;
  final int current;
  final Color activeColor;
  final Color inactiveColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < count; index++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              height: index == current ? 10 : 7,
              decoration: BoxDecoration(
                color: index <= current ? activeColor : inactiveColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (index != count - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  static const _features = [
    (
      icon: Icons.ios_share_outlined,
      title: '截图分享即记录',
      text: '点完外卖截个图，分享给餐盘，自动帮你记下来',
    ),
    (icon: Icons.donut_large, title: '吃得怎么样一眼知道', text: '不用算卡路里，看看今天各类食物够不够'),
    (
      icon: Icons.restaurant_menu,
      title: '下一顿吃什么帮你想',
      text: '还缺什么、几点吃、推荐什么，都告诉你',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 80),
      children: [
        Center(
          child: SizedBox(
            width: 148,
            child: PixelPanel(
              color: scheme.primaryContainer,
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: const Column(
                children: [
                  PixelBadge(label: '新伙伴'),
                  SizedBox(height: 4),
                  PetSpriteWidget(
                    petType: 'cat',
                    growthStage: 'baby',
                    vitalityState: 'energetic',
                    size: 92,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '餐盘',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '轻松看懂今天吃得怎么样',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: PixelDivider(),
        ),
        const SizedBox(height: 26),
        for (final feature in _features) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelIconTile(icon: feature.icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(feature.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      feature.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
