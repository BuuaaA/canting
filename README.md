# 餐盘

Flutter 应用，包含 Android 图片分享接收、中文 OCR 和桌面小组件原生集成。

## 验证

在 PowerShell 中运行完整验证：

```powershell
.\tool\verify_android_native.ps1
```

后台运行并在全部检查通过后提交当前改动：

```powershell
.\tool\start_unattended_android_build.ps1
```

进度和错误日志写入 `build/reports/unattended/`。完整流程依次执行依赖下载、格式检查、静态分析、Flutter 测试、Android 单元测试和 Debug APK 构建；下载及 APK 构建失败时会自动重试。
