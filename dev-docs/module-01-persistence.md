# 模块 01：数据持久化层

**预估工时**：3h
**依赖**：无
**优先级**：P0（最先做）

## 功能描述

将所有用户数据从内存改为 SQLite 本地持久化，确保 APP 关闭后数据不丢失。这是 V1.0 的基础中的基础。

## 涉及文件

```
lib/data/
  ├── database_helper.dart      — 修改：扩展现有数据库
  ├── user_repository.dart      — 新建
  ├── meal_repository.dart      — 新建
  └── pet_repository.dart       — 新建
lib/state/
  └── app_state.dart            — 改造：从 Repository 加载/保存
pubspec.yaml                    — 添加 sqflite, shared_preferences, path_provider
```

## 数据模型

### 用户档案 (UserProfile)

```dart
class UserProfile {
  final int id; // 固定为 1
  final String gender; // male / female
  final int age;
  final double heightCm;
  final double weightKg;
  final String dietGoal; // balanced / more_veg / more_protein / less_carb
  final String activityLevel; // sedentary / light / moderate / heavy
  final String breakfastTime; // "07:30"
  final String lunchTime; // "12:30"
  final String dinnerTime; // "18:30"
  final String dayStartTime; // "01:00"
  final bool onboardingCompleted;
  final Map<String, double> dailyIntake; // 每日建议摄入量快照
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### 餐食记录 (MealRecord)

```dart
class MealRecord {
  final String id; // UUID
  final DateTime mealTime;
  final String mealType; // breakfast / lunch / dinner / snack
  final List<MealDish> dishes;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MealDish {
  final String dishId;
  final String dishName;
  final String size; // small / regular / large
  final Map<String, double> servings; // 分类->份数 快照
  final double confidence;
}
```

### 宠物状态 (PetState)

```dart
class PetState {
  final int id; // 固定为 1
  final String petType; // cat / dog / hamster
  final String name;
  final String stage; // baby / junior / adult
  final double vitality; // 0-100
  final double growth;
  final int petCountToday;
  final DateTime lastPetTime;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

## 数据库表设计

### user_profiles

```sql
CREATE TABLE user_profiles (
  id INTEGER PRIMARY KEY DEFAULT 1,
  gender TEXT NOT NULL,
  age INTEGER NOT NULL,
  height_cm REAL NOT NULL,
  weight_kg REAL NOT NULL,
  diet_goal TEXT NOT NULL,
  activity_level TEXT NOT NULL,
  breakfast_time TEXT NOT NULL,
  lunch_time TEXT NOT NULL,
  dinner_time TEXT NOT NULL,
  day_start_time TEXT NOT NULL,
  onboarding_completed INTEGER NOT NULL DEFAULT 0,
  daily_intake_json TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (id = 1) -- 保证只有一条记录
);
```

### meal_records

```sql
CREATE TABLE meal_records (
  id TEXT PRIMARY KEY,
  meal_time INTEGER NOT NULL,
  meal_type TEXT NOT NULL,
  dishes_json TEXT NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_meal_time ON meal_records(meal_time);
```

### pet_states

```sql
CREATE TABLE pet_states (
  id INTEGER PRIMARY KEY DEFAULT 1,
  pet_type TEXT NOT NULL,
  name TEXT NOT NULL,
  stage TEXT NOT NULL DEFAULT 'baby',
  vitality REAL NOT NULL DEFAULT 60.0,
  growth REAL NOT NULL DEFAULT 0.0,
  pet_count_today INTEGER NOT NULL DEFAULT 0,
  last_pet_time INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (id = 1)
);
```

## Repository 接口

### UserRepository

```dart
abstract class UserRepository {
  Future<UserProfile?> getProfile();
  Future<void> saveProfile(UserProfile profile);
  Future<void> updateProfile({
    String? gender,
    int? age,
    double? heightCm,
    double? weightKg,
    String? dietGoal,
    String? activityLevel,
    String? breakfastTime,
    String? lunchTime,
    String? dinnerTime,
    String? dayStartTime,
    bool? onboardingCompleted,
    Map<String, double>? dailyIntake,
  });
  Future<bool> hasCompletedOnboarding();
}
```

### MealRepository

```dart
abstract class MealRepository {
  Future<List<MealRecord>> getMealsByDate(DateTime date);
  Future<List<MealRecord>> getMealsByDateRange(DateTime start, DateTime end);
  Future<void> addMeal(MealRecord meal);
  Future<void> updateMeal(MealRecord meal);
  Future<void> deleteMeal(String mealId);
  Future<MealRecord?> getMealById(String id);
}
```

### PetRepository

```dart
abstract class PetRepository {
  Future<PetState?> getPet();
  Future<void> savePet(PetState pet);
  Future<void> updatePet({
    String? name,
    String? stage,
    double? vitality,
    double? growth,
    int? petCountToday,
    DateTime? lastPetTime,
  });
}
```

## AppState 改造

### 初始化流程

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.init();
  final appState = AppState();
  await appState.loadFromDatabase();
  runApp(MyApp(appState: appState));
}
```

### AppState 关键方法

```dart
class AppState extends ChangeNotifier {
  UserProfile? profile;
  List<MealRecord> todayMeals = [];
  PetState? pet;

  final UserRepository _userRepo = UserRepository();
  final MealRepository _mealRepo = MealRepository();
  final PetRepository _petRepo = PetRepository();

  // 启动时加载
  Future<void> loadFromDatabase() async {
    profile = await _userRepo.getProfile();
    pet = await _petRepo.getPet();
    if (profile?.onboardingCompleted == true) {
      await _loadTodayMeals();
      _recalculateDailyIntake();
      _recalculateVitality();
    }
    notifyListeners();
  }

  // 完成初始设置
  Future<void> completeOnboarding({
    required UserProfile newProfile,
    required PetState newPet,
  }) async {
    await _userRepo.saveProfile(newProfile);
    await _petRepo.savePet(newPet);
    profile = newProfile;
    pet = newPet;
    _recalculateDailyIntake();
    notifyListeners();
  }

  // 添加餐食
  Future<void> addMeal(MealRecord meal) async {
    await _mealRepo.addMeal(meal);
    await _loadTodayMeals();
    _recalculateVitality();
    _updateGrowth(added: true);
    notifyListeners();
  }

  // 删除餐食
  Future<void> deleteMeal(String mealId) async {
    await _mealRepo.deleteMeal(mealId);
    await _loadTodayMeals();
    _recalculateVitality();
    notifyListeners();
  }

  // 更新个人信息
  Future<void> updateProfile(UserProfile newProfile) async {
    await _userRepo.saveProfile(newProfile);
    profile = newProfile;
    _recalculateDailyIntake();
    _recalculateVitality();
    notifyListeners();
  }
}
```

## SharedPreferences 存储项

```dart
// 设置相关
class AppSettings {
  static const String notificationEnabled = 'notification_enabled';
  static const String selectedPlatforms = 'selected_platforms';
  static const String platformOrder = 'platform_order';
  static const String isFirstLaunch = 'is_first_launch';
  static const String notificationGuided = 'notification_guided';
}
```

## 验收标准

- [ ] 完成初始设置后，杀掉 APP 重开，设置数据还在
- [ ] 添加一条餐食记录，杀掉 APP 重开，记录还在
- [ ] 宠物状态（活力值、成长值）杀掉 APP 重开不丢失
- [ ] 修改个人信息后，重新打开 APP，修改生效
- [ ] 删除记录后，当日结构相应变化
- [ ] 数据库升级有迁移机制（版本号管理）
- [ ] 所有 JSON 序列化/反序列化有单元测试
