# Ponytail 精简说明

采用已安装 ponytail 技能（D:/AI-App-Data/Codex/UserData/skills/ponytail/SKILL.md），来源 https://github.com/DietrichGebert/ponytail 。扫描了 lib 与 Android原生生产源码共 97 文件，优先处理确定重复，修改范围见下表。

| 文件 | P6-A行数 | beta行数 | 变化 |
|---|---:|---:|---:|
| lib\data\custom_dish_repository.dart | 207 | 172 | -35 |
| lib\data\database_helper.dart | 486 | 472 | -14 |
| lib\data\food_database.dart | 187 | 194 | +7 |
| lib\state\app_state.dart | 1478 | 1477 | -1 |
| lib\core\models\portions.dart | 106 | 99 | -7 |
| lib\ui\about\about_page.dart | 103 | 108 | +5 |

保留三套公开搜索入口，将完全相同的匹配谓词集中到现有 FoodDatabase；保持各自来源顺序、双向子串判断、空输入不访问数据库。
自定义菜品普通写入/带元数据写入共用一个私有写入方法；分类存在校验、异步错误、replace语义、元数据缺省键、时间字段与JSON格式保留。
Portions.byCategory复用toJson，每次仍返回独立Map；Widget重复的完整性和窗口判断只求值一次。About仅更新版本展示和反馈说明。

没有统一含义不同的历史/首页UI，没有改推荐安全门、置信度/份量规则、OCR状态机、事务、迁移和宠物玩法；这些不是无用复杂度。保留本地知识/指南/用户画像分层、桥接与存储注入接口，未来迭代沿既有边界扩展，无新增空壳接口或依赖。

test/data/ponytail_regression_test.dart 对照精简前搜索行为，覆盖三入口的结果和顺序、空查询/关闭数据库、元数据替换与缺失分类、Map独立性。既有完整回归和日期专项继续执行，实际结果汇总在最终交接报告。源码副本与简化专用diff位于 dev-docs/p6a-evidence/beta-20260906/，没有用行数下降代替行为验证。

精简不等于已证明所有设备行为完全相同；真机待验项目仍not_run。最终发布须产品经理独立审查。
