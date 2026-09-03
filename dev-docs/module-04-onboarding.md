# 模块 04：初始设置流程

**预估工时**：2h
**依赖**：模块 01
**优先级**：P0

## 功能描述

6 步初始设置流程，用户首次打开 APP 时完成：宠物选择 → 基本信息 → 饮食目标 → 活动量 → 作息习惯 → 完成。

## 涉及文件

```
lib/ui/onboarding/
  ├── welcome_page.dart           — 欢迎页
  ├── pet_selection_page.dart     — Step 0: 宠物选择
  ├── basic_info_page.dart        — Step 1: 基本信息
  ├── diet_goal_page.dart         — Step 2: 饮食目标
  ├── activity_page.dart          — Step 3: 活动量
  ├── schedule_page.dart          — Step 4: 作息习惯
  └── complete_page.dart          — Step 5: 完成
lib/ui/onboarding/
  └── onboarding_controller.dart  — 流程控制（PageView）
```

## 页面结构

### WelcomePage（欢迎页）

```
[产品 Logo]
「外卖党的轻量饮食结构助手」

✓ 截图就能记
✓ 不数卡路里
✓ 有宠物陪你

[ 开始使用 ] → 进入 Step 0
```

### PetSelectionPage（Step 0）

```
选一个小伙伴一起吃饭吧！

  🐱      🐶      🐹
小挑食   小干饭   小囤囤
傲娇     热情     软萌

可以给它起个名字：
[ 小挑食         ]

[      下一步       ]
```

**交互**：
- 三只宠物横向排列，默认选中第一个
- 点击切换，播放选中动画
- 昵称输入框默认填入宠物默认名
- 昵称限制 1-6 字符

### BasicInfoPage（Step 1）

```
告诉我一些基本信息

性别：[○ 男  ○ 女]
年龄：[  25  ] 岁
身高：[ 170  ] cm
体重：[  65  ] kg

[      下一步       ]
```

**校验规则**：
- 性别必选
- 年龄：12-80 整数
- 身高：120-220 整数
- 体重：30-200 整数
- 全部填完才能点下一步

### DietGoalPage（Step 2）

```
你的饮食目标是什么？

◉ 均衡饮食（推荐）
  不做特殊调整，按膳食指南标准

○ 多吃蔬菜
  蔬菜目标增加 20%

○ 多蛋白质
  蛋白质目标增加 20%

○ 控制主食
  主食目标减少 20%

[      下一步       ]
```

### ActivityPage（Step 3）

```
平时的活动量怎么样？

◉ 久坐
  几乎不运动，办公室工作

○ 轻度活动
  每周 1-3 次轻运动

○ 中等活动
  每周 3-5 次中等运动

○ 重度活动
  每周 6-7 次高强度运动

[      下一步       ]
```

### SchedulePage（Step 4）

```
你的作息习惯

早餐时间：[ 07:30 ⌄ ]
午餐时间：[ 12:30 ⌄ ]
晚餐时间：[ 18:30 ⌄ ]

日期切换时间：
○ 凌晨 0:00 — 标准自然日
◉ 凌晨 1:00 — 稍微熬夜也不怕（推荐）
○ 凌晨 4:00 — 夜猫子友好

[      下一步       ]
```

### CompletePage（Step 5）

```
    🐱 大图
「你好呀！我是小挑食，
  以后一起好好吃饭吧～」

[   开启餐盘   ] → 进入首页
```

## 流程控制

```dart
class OnboardingController extends ChangeNotifier {
  int currentStep = 0; // 0-5
  final PageController pageController = PageController();

  // 各步骤暂存数据
  String? selectedPetType;
  String petName = '';
  String? gender;
  int age = 25;
  double heightCm = 170;
  double weightKg = 65;
  String dietGoal = 'balanced';
  String activityLevel = 'sedentary';
  String breakfastTime = '07:30';
  String lunchTime = '12:30';
  String dinnerTime = '18:30';
  String dayStartTime = '01:00';

  void nextStep() {
    if (currentStep < 5) {
      currentStep++;
      pageController.nextPage(...);
      notifyListeners();
    }
  }

  void prevStep() { ... }

  // 完成设置，写入数据库
  Future<void> complete(AppState appState) async {
    final intake = IntakeCalculator.calculate(...);
    final profile = UserProfile(
      gender: gender!,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      dietGoal: dietGoal,
      activityLevel: activityLevel,
      breakfastTime: breakfastTime,
      lunchTime: lunchTime,
      dinnerTime: dinnerTime,
      dayStartTime: dayStartTime,
      onboardingCompleted: true,
      dailyIntake: intake.targetServings,
      ...
    );
    final pet = PetState(
      petType: selectedPetType!,
      name: petName,
      stage: 'baby',
      vitality: 60,
      growth: 0,
      ...
    );
    await appState.completeOnboarding(profile, pet);
  }
}
```

## 验收标准

- [ ] 6 步流程完整可走通
- [ ] 每步数据暂存，返回上一步数据不丢失
- [ ] 必填项未填时，下一步按钮置灰
- [ ] 输入数值超出范围时有错误提示
- [ ] 完成设置后数据正确写入数据库
- [ ] 完成设置后跳转到首页
- [ ] 已完成设置的用户再次打开直接进首页
- [ ] 中途退出后重新打开从欢迎页开始
