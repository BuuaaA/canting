# P6-A 测试包准备报告

结论：P6-A 本地包与资料完成，可交 Owner 真机测试，尚未批准发布。P5仍为部分完成。
交付目录：`D:\dev\canting\build\p6a-delivery\run-20260905`。

本轮修复快照业务日期/UTC偏移有效性和前台恢复同步；旧快照缺字段按过期，旧数值隐藏，显示更新提示。同日记录仍区分未知、无记录、已知零值。日期来自App本地时钟，原生以本地日期/偏移校验；跨日回拨或时区偏移变化会失效。布局不无条件声称“今天”。无新权限、服务或轮询。

App图标母稿 `branding/canting-icon-v1.png`，1254×1254，不透明；SHA-256 `4c54e7cc0fb08e951c3a9ec372f630d3985dcc9539dd8379388ed43d461a6d1a`。保留原画，以76dp整图置于108dp前景上，配匹配背景；五密度launcher/round/foreground和v26 adaptive配置详见 icon-resources.json。Manifest增加roundIcon。48/72/96像素圆/圆角方预览已目检，猫耳/餐盘未裁切；真机仍not_run。

代码基线HEAD 6f1286d，含P3 ef1613c。开始时P5清单全部哈希匹配；所有P5工作保留，重叠 AppState、PetWidgetViews、完成度文案、布局、Manifest均为增量修改，修改前副本保存在证据 before/（.before后缀）。未修改宠物资源和玩法。

本轮 Flutter静态零问题，完整回归497通过；Kotlin 38通过；universal/split release构建成功。命令、真实时间、退出码、源码哈希、证书及权限检查在 `dev-docs/p6a-evidence/run-20260905/`。首次测试因新测试调用不存在的copyWith编译失败，修正后通过；首次静态因备份pubspec被识别为嵌套工程和冗余导入失败，改用.before并移除导入后通过，原始日志保留。Gradle既有弃用/JDK警告仍存在。

主包 35,839,121 字节，比P5 arm64变化 +400,408；备用 93,335,892 字节，比P5 universal变化 +400,412。这是整轮包体变化，不能全归因于图标。两包versionCode=5002，实际身份见 package-analysis.json；同证书同包名只是覆盖静态前提。

尚未连接/安装设备，未分发，未提交/推送。小米/真实升级/原生OCR/系统备份全部not_run。现有JSON导出无完整恢复入口，重要旧数据升级暂停。

恢复旧图标：逐项从before副本恢复原五密度ic_launcher；Manifest仅移除本轮roundIcon引用，再移走本轮新建round/foreground/v26/color资源。先检查后续改动，勿覆盖整个Manifest或reset。恢复源码不是APK降级授权，低版本码不得强制覆盖。已保留P5备份/隐私改动。

后续按任务书P6-B/P6-C准入推进。用户新授权后续ponytail精简与0.9.0-beta上传；本P6-A证据冻结，后续变更必须另行重新验证。
