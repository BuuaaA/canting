# 餐盘 0.9.0-beta

用户已授权发布的 beta 测试版，非V1正式封版。新增橘猫餐盘App图标；修复Widget跨日过期显示及App回前台同步；合并重复搜索和自定义菜品写入代码，保留现有功能与分层。

提供arm64主包和universal备用包。versionCode均为5003，沿用com.canting.canting包名及原有Android Debug测试签名。设备ABI未确认时先阅读安装指南。

有重要旧数据时暂停升级：JSON导出不等于已验证可恢复备份，目前没有完整恢复入口。不得通过卸载、清数据或强制降级解决安装问题。

自动化：Flutter静态零问题、501项完整回归通过（含终审新增真实查询失败恢复测试）、38项Kotlin测试通过；两种release APK重新构建并核验图标、签名、版本和权限。
小米真机、真实升级、原生首次离线/无GMS OCR、系统备份及完整真实图评估仍not_run。宠物美术更新延后V1.1。

先阅读START-HERE.md、package-info.md、known-limitations.md，并校验SHA256SUMS.txt。上传仅在独立产品经理复核通过后执行；此文档不预填审核结论。
