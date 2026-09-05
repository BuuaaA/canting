# P5 Android 发布候选交付

结论：**部分完成，供产品复评；未批准发布。** P3 已于 `ef1613c5f47fe089be6afbcd4ba491bccfbd0e82` 提交，本轮未重写；用户授权后 P4 按 168项清单加清单自身提交为 `6f1286daafa6d9e4d282bb0dabaf0a9db59cb317`，标题「P4 OCR 链路加固及 R1-R3 整改，真实验收待补」。没有 push。P5 以下变更保持未提交。

## 完成内容

- 生产入口 `lib/main.dart` 的 P4 基线与 P5 release universal/ABI拆分/AAB 均实际构建；内置中文 OCR `16.0.1`、包名 `com.canting.canting` 保持。构建产物在 `D:/dev/canting/build/p5-artifacts/`，未加入交付清单。
- 修正 Widget 将未知完成度显示成 0% 的问题：结构不完整时显示「记录不完整」并隐藏进度条；无记录时显示「今天还没有记录」；已知零值与历史百分数格式保留。Kotlin 纯逻辑测试加 Flutter 生产 AppState/SQLite 保存与重开测试覆盖；没有把这些测试称为 Android 桌面渲染验收。
- release 合并发现 ML Kit 传递依赖 datatransport 自动添加 INTERNET/ACCESS_NETWORK_STATE。主 Manifest 显式移除这两项，产物再次核对；debug/profile 开发联网配置沿用。此处为落实离线边界，未替换为动态下载 OCR，未增加依赖、云服务或遥测。
- 明确禁用自动备份，分别声明旧版 backup_rules 和 Android 12+ cloud-backup/device-transfer 排除规则，覆盖普通/设备保护存储域。只影响系统自动备份/转移，不删除本机数据，不妨碍同包覆盖升级。OEM 实际执行仍须真机验证。
- 本应用的错误诊断 `debugPrint` 限定 kDebugMode，避免 release 把异常内的业务字段或路径写入日志；不声称已审计第三方库所有运行时输出。应用显示名改为「餐盘」，品牌图标保持现状待最终素材。
- 测试采集路径使用 `CANTING_TEST_EVIDENCE_DIR`，Flutter 默认输出 build/test-evidence/latest 并拒绝写入冻结 P2/P3/P4 目录；Kotlin 回放默认写 build/test-evidence。历史语义回放仍读取冻结 P4 TSV，本轮不重写输入/标签。新运行输出全部位于本次 P5 目录。

## 包体实测

MB 按十进制 1,000,000 字节；ZIP entry 的压缩/解压字节不是安装占用或网络下载量。

| 产物 | 字节 | MB | SHA-256 |
|---|---:|---:|---|
| 旧 beta | 88,805,734 | 88.81 | `27a0ef8380a57a82b7266bff3a1798f232080d3c1df4074239faf39b1805987a` |
| baseline-offline/app-release.apk | 92,934,376 | 92.93 | `d078b0086fc1f3c185f9eb9255eecf72106283d84aac25f9020fed4e92e36cc0` |
| split/app-arm64-v8a-release.apk | 35,438,713 | 35.44 | `316ee514478f16750839f32697e9c5689bbf8ceeca72a9f2a4202a8921f6f0d2` |
| split/app-armeabi-v7a-release.apk | 28,813,207 | 28.81 | `0a5430db8eef535addec2b9329ef7bccf98d312afde6425a90249fa1ba4baa82` |
| split/app-x86_64-release.apk | 37,540,378 | 37.54 | `517ae1aed65c9778da93a7b61fb48795da152c27ba3973166b6c09fbc45c19c2` |
| universal/app-release.apk | 92,935,480 | 92.94 | `1b71753060f62a2d1b67c0620caa8d8b678965b00fb3d8d7b64cc556463d5c34` |
| bundle/app-release.aab | 74,044,411 | 74.04 | `cd38d39e77edf5a6e935a988e2c218ea992c20a35aedad7dcdc2e8b561f59464` |

P5 universal 相对同条件 P4 基线差 `+1,104` 字节。arm64 拆分包相对 P5 universal 减少 `57,496,767` 字节（61.9%），来自仅交付目标 ABI；这是分发形态差异，不是删减业务或OCR。最终设备 ABI 待核对。AAB 不能直接安装，其文件大小不能代表 Play 下载或设备安装大小，未测 bundletool/device delivered size。

体积构成（P5 universal）：

| 类别 | ZIP解压字节 | ZIP压缩字节 |
|---|---:|---:|
| Android resources/metadata | 489,311 | 376,021 |
| DEX | 2,092,772 | 931,304 |
| Dart AOT | 25,119,064 | 25,119,064 |
| Other native libraries | 347,544 | 347,544 |
| Flutter engine | 33,415,188 | 33,415,188 |
| OCR native libraries | 29,472,612 | 29,472,612 |
| Flutter assets/data | 1,728,541 | 1,091,789 |
| Fonts | 133,308 | 49,435 |
| OCR models/resources | 2,490,560 | 1,924,291 |

前20项按 ZIP解压大小排序；另有压缩前20、按ABI汇总、内容相同条目组，见 artifact-analysis.json。跨 ABI native 库为不同机器码，不按重复资产删除。字体裁剪、R8和资源缩减构建任务已执行；未证明可安全删除的模型、字体或库保持。当前没有引入额外源码缩包技巧。

| 条目 | 解压字节 | 压缩字节 | 分类 |
|---|---:|---:|---|
| `lib/x86_64/libflutter.so` | 13,051,424 | 13,051,424 | Flutter engine |
| `lib/arm64-v8a/libflutter.so` | 11,747,864 | 11,747,864 | Flutter engine |
| `lib/x86_64/libmlkit_google_ocr_pipeline.so` | 11,626,128 | 11,626,128 | OCR native libraries |
| `lib/arm64-v8a/libmlkit_google_ocr_pipeline.so` | 11,064,544 | 11,064,544 | OCR native libraries |
| `lib/armeabi-v7a/libapp.so` | 8,864,328 | 8,864,328 | Dart AOT |
| `lib/armeabi-v7a/libflutter.so` | 8,615,900 | 8,615,900 | Flutter engine |
| `lib/x86_64/libapp.so` | 8,258,440 | 8,258,440 | Dart AOT |
| `lib/arm64-v8a/libapp.so` | 7,996,296 | 7,996,296 | Dart AOT |
| `lib/armeabi-v7a/libmlkit_google_ocr_pipeline.so` | 6,781,940 | 6,781,940 | OCR native libraries |
| `classes.dex` | 1,902,628 | 851,457 | DEX |
| `assets/mlkit-google-ocr-models/gocr/gocr_models/line_recognition_legacy_mobile/Hani_ctc/optical/lstm_model.fb` | 891,872 | 599,499 | OCR models/resources |
| `assets/flutter_assets/assets/data/dishes.json` | 639,757 | 52,875 | Flutter assets/data |
| `assets/mlkit-google-ocr-models/taser/detector/rpn_text_detector_mobile_space_to_depth_quantized_mbv2_v1.tflite` | 340,760 | 340,760 | OCR models/resources |
| `assets/flutter_assets/assets/sprites/pet_hamster_adult_good_0.png` | 338,767 | 338,767 | Flutter assets/data |
| `assets/mlkit-google-ocr-models/gocr/gocr_models/line_recognition_legacy_mobile/tflite_langid.tflite` | 315,520 | 315,520 | OCR models/resources |
| `assets/mlkit-google-ocr-models/gocr/gocr_models/line_recognition_legacy_mobile/Latn_ctc/optical/lstm_model.fb` | 309,568 | 181,609 | OCR models/resources |
| `assets/flutter_assets/assets/sprites/pet_cat_adult_good_0.png` | 302,015 | 302,015 | Flutter assets/data |
| `assets/flutter_assets/assets/sprites/pet_dog_adult_good_0.png` | 278,365 | 278,365 | Flutter assets/data |
| `resources.arsc` | 251,112 | 251,112 | Android resources/metadata |
| `classes2.dex` | 190,144 | 79,847 | DEX |

## 环境和验证

Flutter 3.47.2 / Dart 3.13.2；AGP 9.1.0、Kotlin 2.4.0、Gradle 9.3.1；Android Studio JBR 25.0.3，源码/JVM目标17；compile/target SDK36，minSDK24，NDK28.2.13676358，build-tools36.0.0。全部具体命令、起止时间、退出码见同目录 command.json 与原始 txt。每次构建前保存源文件 SHA-256 和 Git 状态。生产源码/资产与发布模式、三个ABI一致后比较。

构建命令在 android 目录：`gradlew.bat :app:assembleRelease --offline --no-daemon --max-workers=1 "-Dorg.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G" -Ptarget=lib/main.dart -Ptarget-platform=android-arm,android-arm64,android-x64 -Ptree-shake-icons=true`。拆分增加 `-Psplit-per-abi=true`；AAB替换任务为 `:app:bundleRelease`。JAVA_HOME 指向 Android Studio jbr。测试命令为 `flutter --no-version-check test --no-pub --concurrency=1 --reporter expanded`（实际调用已安装 dart.exe + flutter_tools.snapshot，见JSON）。

| 验证 | 本轮结果 | 限制 |
|---|---|---|
| Flutter静态 | analyze-2.txt 零问题 | 首次10条格式/导入info已修复，首次日志保留 |
| Flutter完整回归 | 496通过，0失败 | 组件/真实SQLite，不是真机 |
| Kotlin JVM | 32通过，0失败/错误 | 含Widget完成度6项；不等于RemoteViews渲染或ML Kit原生执行 |
| release构建 | 基线、universal、split、AAB成功 | 都是本地候选，不代表可发布 |
| 权限/备份/provider配置 | configuration-validation.json | 基于合并Manifest及配置；设备实际行为未测 |
| P4输入/原始证据保护 | 原始字节校验通过 | P4业务/测试文件中本轮明确改动见P5清单，不要求它们仍等于P4哈希 |
| Xiaomi/真实截图/旧beta升级 | not_run | 无在线设备与授权真实图片 |

首次 Flutter build 被本轮主动停止：Gradle Lint 长时间等待外网版本查询，线程栈已定位；改用 --offline 后通过。不能将此记录写成无原因的运行崩溃。构建仍有 Gradle/AGP DSL 弃用与 JDK native-access 警告，未顺手升级插件；完整静态检查零问题与这些构建工具警告分别报告。未启动模拟器并行占用内存。

## 签名、升级、图标和 Widget

候选 APK 证书在各 signature.txt 核验；旧beta证书 SHA-256 为 `336e3f94c188e3a5452475abaf0db1c2bd56a0d1986b5cf36cbdb3cbb6b2bd03`，本轮所有候选包与之相同。release仍用 Android Debug 签名。旧包文件名带v0.1.0-beta，包内实际1.0.0+1；universal版本码1，armeabi-v7a/arm64-v8a/x86_64拆分分别1001/2001/4001。相同包名/证书仅证明覆盖升级的静态前提，不证明迁移与用户数据保留通过。正式密钥缺失，不生成或提交密钥，不任意改身份。签名方案及完整设备矩阵见 p5-device-checklist.md。

AAB 的 jarsigner 返回 `jar verified`，同时报告自签名证书链不受信、无时间戳、POSIX属性不受签名保护，以及 JarInputStream 与 JarFile 读取时因 Manifest 顺序产生的签名视图不一致；原始中文及英文日志均保留。未完成 bundletool/商店验证，不将成功构建或该检查当正式发行验证。AAB 的 BUNDLE-METADATA 调试符号与mapping单独统计，不计入可安装业务资产。

Widget 已有一个私有receiver、私有数据通道、250dp宽度选小/中布局和30分钟系统更新；单provider不表示有两个列表条目。点击仍通过广播记录本机点击并启动MainActivity，桌面兼容性待真机。默认中布局及40dp最小调整高度需确认不裁切。快照无业务日期，App长期未打开时跨日字段可能陈旧，此风险尚未做设备复现，不宣称已解决。当前launcher是默认Flutter位图，无adaptive/round最终品牌素材。

## 遗留、回退与边界

P4 R1–R3 已闭环，不重开原整改。真实平台图片仍为0，独立留出、完整危险场景、真实分享/拍照权限、飞行模式/无GMS、数据集化跨重启复用与临时副本设备边界仍未完成。移除依赖合并权限后还须在目标机执行首次/重复OCR、后台任务和release异常日志检查。

完成真机验证需要用户确认型号/系统/测试数据，提供最终图标、许可脱敏截图及正式签名决策。未做安装、卸载、清数据、分发、push或P6。没有上架批准。

代码回退基线为本地P4提交 `6f1286daafa6d9e4d282bb0dabaf0a9db59cb317`，由Owner选择需要回退的P5路径；不要直接reset覆盖后续修改。数据库schema与包名未变；禁止以卸载或删数据做回退。对已安装的高版本码split包，先检查安装规则，不能承诺低版本码universal可直接覆盖。保留测试/审核证据。

本报告是开发交付，需产品复评确认限定范围。参考：[Android自动备份](https://developer.android.com/identity/data/autobackup)、[ML Kit内置中文识别](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)、[Widget更新](https://developer.android.com/develop/ui/views/appwidgets/advanced)。第三方SDK声明与本包实际权限分开判断；不根据“离线API”名称推断所有依赖天然不联网。
