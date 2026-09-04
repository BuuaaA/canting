# 菜库蒸馏与交叉校验报告

生成时间：2026-09-04 · 蒸馏器：`tools/distill/distill_dishes.py`（+ `curated_extra.py`）

## 1. nutridata 数据可用性说明（重要）

- 已按要求克隆 `sunw80910/nutridata_data` 到 **d:\dev\nutridata_data**（canting 仓库之外，未提交本仓库）。
- 实查该仓库**未提交数据表本体**：仅含 4 个 selenium 爬虫脚本 + 2 个清洗 notebook；notebook 引用的
  `my_h_dish_info_all.xlsx`（25668 道菜）不在仓库内，git 历史亦无。
- nutridata.cn 菜肴详情页需注册登录（爬虫脚本含账号登录流程），无凭据无法爬取。
- 依据「数据格式问题自行判断处理」，本管线：
  1. **兼容 nutridata composition 格式**（`配料名：克重` 逐行），解析器与未来全量蒸馏路径
     （`--nutridata-xlsx`）已就绪，拿到原始表即可重跑；
  2. 以 notebook 输出中可见的 **5 道真实 nutridata 菜肴**作为真蒸馏样例；
  3. 其余 999 道全部为**菜谱常识估算**（`estimated=true`），配料宏量参照 cn-food-mcp（MIT）。

## 2. 样例来源与 estimated 标记

| dish_id | dish_name | nutridata 实测 kcal/总重 | estimated | 说明 |
|---|---|---|---|---|
| tong_hao_ban_dou_fu | 茼蒿拌豆腐 | 82 / 150g | false | 成分完整可见（豆腐50g+茼蒿100g，香油按宏量脂肪反推） |
| zhu_rou_wan_zi | 猪肉丸子 | 198.6 / 60g | false | 成分完整可见（猪肉 fat30 代表值 60g） |
| mei_wei_zhu_rou_jiao_zi | 美味猪肉饺子 | 355 / 165g | true | 成分被截断，按 df1 配料表+宏量重建 |
| zhu_rou_hui_xiang_jiao_zi | 猪肉茴香饺子 | 307 / 180g | true | 成分被截断，同上 |
| da_cong_zhu_rou_xian_bing | 大葱猪肉馅饼 | 245 / 115g | false | 成分完整可见 |

## 3. 蒸馏口径（与 lib/core 契约一致）

- 交换份：grains 50g 生谷薯（熟饭150/馒头75/生面条→按熟重150 折算）、vegetables 80g、
  fruits 100g、protein 50g 肉蛋当量、protein_soy 15g 大豆当量、oil 10g。
- 与 `dietary_guidelines.json` 的 food_exchange 有两处偏离（已记录）：
  1. `noodles_raw: 75g/份` 为该表离群值（能量 261kcal ≠ 1 份 173kcal），管线按能量一致口径
     50g 生/150g 熟折算；
  2. 红薯/紫薯/土豆等根茎按能量一致折算（红薯 190g/份），food_exchange 的 sweet_potato 125g
     能量 112kcal 与 serving_reference 50g 谷（173kcal）自相矛盾，取后者。
- 蛋白换算：肉蛋按克重（50g/份）但以 80kcal/份能量压顶（虾、白鱼等低脂水产不虚标）；
  奶类按蛋白质当量（250ml 牛奶 ≈ 1.1 份）。
- 油脂：纯油按克重；坚果/含脂乳酱按脂肪含量折油当量（1 份油 = 10g 脂肪）。
- 钠估算：盐 393mg/g、酱油类 ~60mg/g、酱类/咸菜按 KB 或 cn-food-mcp 数值；**≥800mg/份**
  （≈2g 盐 ≈ 40% NRV）判 high_sodium。

## 4. 质量标签与 recommendable 规则（与任务一致）

- whole_grain：全谷物/杂豆配料占谷类 ≥30%（杂粮饭、玉米、燕麦、荞麦、绿豆等）。
- light：蒸/煮/白灼/凉拌/清炒/汆/涮 且 油 ≤8g/份 且无负面标签。
- fried：油炸/干煸/糖醋/拔丝/脆皮 等；high_sodium：钠≥800 或名称特征（红烧/卤/腊/腌/麻辣…）；
  high_sugar：含糖饮料/甜点/拔丝/蜜制。
- **recommendable = 无 fried/high_sodium/high_sugar 且非垃圾食品名单**。

## 5. 产出统计（1004 道）

- 总数 **1004**（旧库升级 29 + nutridata 样例 5 + gap-fill 970，estimated=true 共 1001）。
- recommendable：**true 707 / false 297**。
- 标签分布：whole_grain 67、light 215、fried 58、high_sodium 204、high_sugar 44。
- 六类含 >0 份数的菜数：grains 641、vegetables 657、fruits 134、protein 627、
  protein_soy 104、oil 784（无全零份数菜）。
- 类别分布：stir_fry 184、dessert_sweet 95、congee_soup 85、breakfast_set 78、salad_light 75、
  fruit 74、braised 70、stir_fry 系列模板与川湘家常均已计入；combo_set 7、protein_dish 37 等。

## 6. 交叉校验（cn-food-mcp，20 道确定性抽样 seed=42）

方法：kcal_recipe = Σ 配料克重 × cn-food-mcp 每 100g 能量；kcal_portions = Σ 六类份数 ×
交换份热量（grains 173 / veg 16 / fruit 50 / protein 80 / soy 55 / oil 90 kcal）。
5 道 nutridata 样例同时给出 nutridata 官方实测值对比。

| dish | kcal_recipe | kcal_portions | 偏差 | nutridata 真值 |
|---|---|---|---|---|
| 茼蒿拌豆腐 | 108.4 | 90.5 | 16.6% | 82 |
| 猪肉丸子 | 192.0 | 177.9 | 7.3% | 198.6 |
| 美味猪肉饺子 | 369.1 | 350.1 | 5.2% | 355 |
| 猪肉茴香饺子 | 321.4 | 309.4 | 3.7% | 307 |
| 大葱猪肉馅饼 | 282.5 | 272.6 | 3.5% | 245 |
| 杀猪菜 | 539.7 | 502.3 | 6.9% | — |
| 茶叶蛋 | 85.1 | 90.0 | 5.8% | — |
| 披萨 | 636.6 | 671.6 | 5.5% | — |
| 冬阴功汤 | 171.0 | 142.7 | 16.5% | — |
| 柠檬红茶 | 67.1 | 59.4 | 11.5% | — |
| 薯饼 | 278.3 | 282.8 | 1.6% | — |
| 木瓜 | 58.0 | 58.0 | 0.0% | — |
| 宽粉 | 120.0 | 115.9 | 3.4% | — |
| 鸡丝焖面 | 401.2 | 398.5 | 0.7% | — |
| 手抓羊肉 | 292.6 | 308.2 | 5.3% | — |
| 隆江猪脚饭 | 473.4 | 456.4 | 3.6% | — |
| 糖拌西红柿 | 75.2 | 76.0 | 1.1% | — |
| 关东煮 | 111.8 | 98.0 | 12.3% | — |
| 蒸紫薯 | 190.8 | 190.3 | 0.3% | — |
| 剁椒蒸芋头 | 192.6 | 184.7 | 4.1% | — |

**20/20 偏差 ≤30%（最大 16.6%），无 >30% 需人工降级项。**

人工复核过程中修正过 5 处系统性偏差（当时 >30%）：
椰浆/椰奶按脂肪折油、水果能量压顶、根茎类份重能量一致化、低卡蔬菜 per_portion=0 被
回退 bug（饮用水曾计入蔬菜份数）、含脂酱类折算。

## 7. 与旧库/匹配器的兼容决策

- **词条所有权**：旧库 29 道菜的名称/别名/关键词归旧菜所有，新菜的别名与搜索关键词一律
  剔除这些词条（如 白切鸡饭 不得携带 白斩鸡），保证 `searchDishes(...).single` 类断言与
  匹配唯一性。
- **「黄闷鸡米饭」不落精确别名**：契约示例含该错字别名，但 test/core/dish_matcher_test 明确
  要求 OCR 错字走 Levenshtein 模糊路径（0.8 置信度）。hsm_rice 仅补「黄焖鸡」别名，错字由
  模糊匹配兜底——两者兼得。
- 旧 29 道 dish_id 全部保留；螺蛳粉/黄焖鸡米饭等旧菜版本优先，蒸馏重名条目跳过。

## 8. 已知局限

- 除 5 道 nutridata 样例外全部为菜谱估算，克重按常规外卖/家常一份；同菜不同店差异大。
- 钠为配料推算值，未含隐含钠（如高汤底）；阈值 800mg/份 偏保守，部分外卖重口菜实际更高。
- cn-food-mcp 仅 1235 项有效名称索引，未命中配料回退 KB 内置均值。
- 垃圾食品（薯条/可乐/炸鸡等）保留入库仅供识别记账，recommendable=false。
