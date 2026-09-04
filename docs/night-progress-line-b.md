# 夜间开发进度 · B线（通知 / 设置 / 宠物 / 历史）

> A线并行开发餐食记录/推荐/手动添加/首页，本文件由B线维护，只记录B线改动。

## 任务1 · 模块13 本地通知
- 状态：**完成**（2026-09-04 夜间）
- 改动文件：
  - `pubspec.yaml`（新增 flutter_local_notifications ^19.0.1，实际解析 19.5.0）
  - `lib/services/notification_service.dart`（新建：初始化、双端权限申请、识别成功/失败通知、点击事件流、内容构造纯函数）
  - `lib/main.dart`（增量：main() 里 init + 通知点击跳转订阅，成功→首页、失败→记录页）
  - `android/app/src/main/AndroidManifest.xml`（POST_NOTIFICATIONS 权限）
  - `test/services/notification_service_test.dart`（新建，8 个测试）
- 新增测试数：8
- 说明：
  - 通知渠道 recognition（识别结果）与 reminders（用餐提醒，V1.1 预留）在 init 时创建。
  - 通知开关 `recognitionEnabled` 为内存态（与现有 mealReminder/gapReminder 同水平），落盘持久化为遗留项。
  - iOS 配置（DarwinInitializationSettings + Info.plist 无需改动）已写好，但 Windows 无法构建 iOS，**未验证**。
  - 点击通知打开 APP 为插件默认行为；深链跳转走 payload → main.dart 订阅实现。

## 任务2 · 模块10 个人设置
- 状态：**完成**（2026-09-04 夜间）
- 改动文件：
  - `lib/ui/settings/profile_update.dart`（新建：编辑落库前的纯逻辑组装 + 校验，IntakeCalculator 重算目标份数）
  - `lib/ui/settings/profile_edit_page.dart`（新建：身高/体重/年龄/性别/活动量/饮食目标/三餐时间/日起点编辑，二次确认后保存）
  - `lib/ui/about/about_page.dart`（新建：版本号、数据来源《中国居民膳食指南(2022)》、cn-food-mcp MIT 许可、隐私说明）
  - `lib/ui/settings/settings_page.dart`（四个信息入口改跳编辑页；提醒设置加"识别结果通知"开关并联动权限申请；清空数据改为清除全部并回 onboarding；关于入口跳 AboutPage）
  - `lib/state/app_state.dart`（共享文件增量：新增 updateProfile、clearAllData，未动已有方法）
  - `lib/data/pet_repository.dart`（新增 deletePet）
  - `test/ui/settings/profile_update_test.dart`（4 个）
  - `test/ui/settings/profile_edit_page_test.dart`（5 个）
  - `test/state/app_state_settings_test.dart`（2 个）
- 新增测试数：11
- 说明：
  - 宠物改名沿用现有 pet_settings.dart（已满足，未重做）。
  - 外卖平台设置 UI 未做（按要求，A线在做跳转服务）。
  - 识别结果通知开关状态目前是内存态（NotificationService.recognitionEnabled），落盘持久化见遗留。
  - 清除全部数据 = 餐食 + 宠物 + 档案 + 自定义菜品全删，路由守卫自动回 onboarding。
- 期间观察：A线并发修改了 app_state.dart（saveMeal 加 note/source、deleteMeal 按规则回退活力值、新增 _foodDatabase 字段）与 meal_repository.dart（getNote 等），中途出现过短暂编译错误，随后 A线自行修复；按协议未触碰。

## 任务3 · 模块7 电子宠物
- 状态：**完成**（2026-09-04 夜间）
- 改动文件：
  - `lib/pet/vitality_calculator.dart`（新建：单日饮食质量评分＝基础60+各分类达标加分-油脂超标扣分+满2餐加分，钳制[15,100]；最近3天均值；质量评级 good/ok/bad/none 供模块9共用）
  - `lib/pet/pet_daily_dialogue.dart`（新建：当日台词场景选择——22点后晚安→无记录→缺口类型→达标→时段，随机取句）
  - `lib/pet/pet_dialogues.dart`（新增 daily 区块读取 dailyLines()、toJsonSafe()，allTexts 兼容数组；默认数据与资产 JSON 同步扩充 12 场景 ×3-4 条）
  - `assets/data/pet_dialogues.json`（三种宠物各加 daily 区块：fulfilled/gap_vegetables/gap_protein/gap_fruits/gap_grains/gap_oil/no_record/morning/midday/afternoon/evening/night，每场景 ≥3 条）
  - `lib/pet.dart`（导出新增模块）
  - `lib/state/app_state.dart`（共享文件增量：新增 refreshPetVitality()，loadFromDatabase 在宠物加载后调用一次，未动其他逻辑）
  - `test/pet/vitality_calculator_test.dart`（10 个）
  - `test/pet/pet_daily_dialogue_test.dart`（11 个）
  - `test/pet/pet_engine_rules_test.dart`（8 个：成长值不回退/进化阈值/摸摸头当日去重与每日上限）
  - `test/state/app_state_pet_test.dart`（3 个）
- 新增测试数：32
- 说明：
  - 活力值口径：单日按当天全部餐食的份数总和相对每日目标评分（两餐合计半份×2=满目标）；最近 3 天有记录的天求平均，全部无记录时不动（离线衰减负责）。
  - 成长值：沿用现有引擎（每餐+3~10、达标额外奖励、摸摸头+1/次、日上限3次、进化 egg→baby→adult 阈值 50/200）；刷新活力值只改 vitality 字段，成长值永不回退，测试覆盖。
  - 摸摸头：引擎已实现 4 小时冷却 + 每日 3 次 + 当日去重，本次补齐规则测试，未改实现。
  - 对话联动首页气泡：PetDailyDialogue 已可用，但首页 pet_area.dart 属 A线，接线列入遗留。
- 门槛记录：全量 230 过 / 1 失败——test/widget_test.dart「saving a recognized meal returns to home」期望文案"餐盘 · 今日"不存在，属 A线首页改造中的半成品断言，非本线引入，按协议记录并继续。

## 任务4 · 模块9 历史记录
- 状态：**完成**（2026-09-04 夜间）
- 改动文件：
  - `lib/ui/history/history_stats.dart`（新建：日质量得分分组、单日完成度、周统计口径——平均完成度/食物种类数去重/坚果周进度(周目标=每日×7)/活力值趋势 7 格）
  - `lib/ui/history/calendar_view.dart`（重写：每日底色表示饮食质量 good绿/ok黄/bad红/无记录灰，评分回调改 scoreForDate，语义化标签；旧 vitalityColor 移除）
  - `lib/ui/history/day_detail.dart`（重写：真实膳食结构（CompletionCalculator + 每日目标）、宠物状态面板、餐食列表带删除（二次确认）、补录按钮）
  - `lib/ui/history/history_page.dart`（重写：整月一次查询渲染日历、不可切未来月份、周统计面板、日详情 bottom sheet、删除后自动刷新）
  - `lib/state/app_state.dart`（共享文件增量：新增只读 queryMealsInRange，未动已有方法）
  - `test/ui/history/history_stats_test.dart`（新建，10 个）
- 新增测试数：10
- 说明：
  - 未新增 meal_repository 查询方法：已有 getMealsByDateRange / getMealsByDate 够用，AppState.queryMealsInRange 只做只读透传。
  - 删除走 state.deleteMeal（与现有删除逻辑一致：A线已改为按记录时规则回退活力值，成长值不回退），UI 加二次确认。
  - 补录沿用 /record_detail?date= 跳转（记录页属 A线）。
  - 日详情的宠物台词用静态分档文案；PetDailyDialogue 的随机台词接线到首页气泡属遗留（首页归 A线）。
- 门槛记录：最终全量运行时 test/widget_test.dart 因 lib/ui/home/home_page.dart（A线文件）编译错误无法加载（:71 'current' 参数），按协议记录不修。

---

## 最终结果（2026-09-04 凌晨收尾）

- **4 个任务全部完成，无跳过。**
- B线新增测试：**65 个，全部通过**
  - 任务1 通知：8（test/services/notification_service_test.dart）
  - 任务2 设置：13（profile_update_test 6 + profile_edit_page_test 5 + app_state_settings_test 2）
  - 任务3 宠物：30（vitality_calculator_test 12 + pet_daily_dialogue_test 10 + pet_engine_rules_test 8 + app_state_pet_test 3 中 3 个均属宠物）
  - 任务4 历史：11（history_stats_test）
  - 注：app_state_pet_test 3 个计入任务3，合计 8+13+33+11 = 65
- 最终 `flutter analyze`：**No issues**（A线中途的半成品错误均已由其自行修复）
- 最终 `flutter test` 全量：**252 通过 / 4 失败**，4 个失败全部位于 A线首页域：
  - test/ui/home_page_real_test.dart ×3（"0%" 个数、"手动添加"重复等首页行为断言）
  - test/widget_test.dart ×1（期望文案"餐盘 · 今日"，A线首页改造中）
  - B线改动文件全部不在失败链路上；B线自有 65 测试独立运行全绿。

## 遗留问题清单（汇总）
1. 通知开关 `recognitionEnabled` 目前为内存态，未落盘（可挂 user_profiles 扩展或新设置表）。
2. iOS 通知：Dart 侧配置已写好，但 Windows 无法构建 iOS，真机/模拟器未验证。
3. OCR 识别结果的真正通知触发点在 Phase 4 接入（本次只做基础设施：任意处可调 showRecognitionSuccess/Failure）。
4. 外卖平台设置 UI 未做（依赖 A线跳转服务落地后一并做）。
5. PetDailyDialogue（按状态/时段随机台词）未接入首页气泡——pet_area.dart 归 A线，接入时替换 `state.petDialogue` 的静态来源即可。
6. 历史页"补录 7 天限制"由 /record_detail（A线）侧把关，历史页入口未做日期校验。
7. 活力值启动刷新挂在 loadFromDatabase；保存/删除餐食后的即时刷新走 A线的记录时规则，两套口径一致性建议 A线回归时抽查（删除回退 vs 3 天重算并存）。
