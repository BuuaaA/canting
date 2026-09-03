# 模块 12：Android 分享扩展 + PaddleOCR

**预估工时**：6h
**依赖**：模块 01, 02
**优先级**：P0

## 功能描述

Android 端的分享扩展，用户在外卖 APP 截图后，通过系统分享面板选择「餐盘」，后台自动识别菜品并存入数据库，完成后发送本地通知。

OCR 使用 PaddleOCR Lite（离线中文识别）。

## 技术架构

- Intent Filter 接收图片分享
- PaddleOCR Lite（PP-OCRv4 轻量模型）
- 共享数据库（FileProvider / 内部存储）
- 本地通知（NotificationCompat）

## 涉及文件

```
android/app/src/main/
  ├── kotlin/com/canting/app/
  │   ├── ShareReceiverActivity.kt    — 分享接收 Activity
  │   ├── ocr/
  │   │   ├── PaddleOCRManager.kt     — PaddleOCR 管理
  │   │   └── DishMatcher.kt          — 菜品匹配（Kotlin 版）
  │   ├── data/
  │   │   ├── SharedDatabaseHelper.kt — 共享数据库
  │   │   └── MealRecorder.kt         — 记录写入
  │   └── notification/
  │       └── NotificationHelper.kt   — 通知工具
  ├── assets/
  │   └── paddleocr/                  — PaddleOCR 模型文件
  │       ├── ppocrv4_det.nb
  │       └── ppocrv4_rec.nb
  └── AndroidManifest.xml             — 修改：添加 Intent Filter
```

## PaddleOCR 集成

### 依赖

```gradle
dependencies {
    // PaddleOCR Lite（或使用第三方封装库）
    implementation 'com.baidu.paddle:paddle-lite:xxx'
}
```

### 模型选择

- PP-OCRv4 移动端超轻量版
- 中文识别
- 检测模型 + 识别模型
- 总大小约 10MB+

### PaddleOCRManager

```kotlin
class PaddleOCRManager(context: Context) {
    private var paddleOCR: PaddleOCR? = null

    fun init() {
        // 初始化模型
        paddleOCR = PaddleOCR.init(context.assets, "paddleocr/")
    }

    fun recognize(bitmap: Bitmap): List<String> {
        val result = paddleOCR?.detect(bitmap) ?: return emptyList()
        return result.map { it.text }
    }

    fun release() {
        paddleOCR?.release()
    }
}
```

## 分享接收流程

```kotlin
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val imageUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (imageUri == null) {
            finish()
            return
        }

        // 后台处理
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val bitmap = contentResolver.loadBitmap(imageUri)
                val textLines = PaddleOCRManager(this@ShareReceiverActivity)
                    .recognize(bitmap)
                val matchedDishes = DishMatcher.matchAll(textLines)

                if (matchedDishes.isNotEmpty()) {
                    // 写入数据库
                    MealRecorder.recordMeal(matchedDishes)
                    // 发成功通知
                    NotificationHelper.sendSuccess(matchedDishes.first().name)
                } else {
                    // 发失败通知
                    NotificationHelper.sendFailure()
                }
            } catch (e: Exception) {
                NotificationHelper.sendFailure()
            }

            finish()
        }
    }
}
```

## Intent Filter 配置

```xml
<activity
    android:name=".ShareReceiverActivity"
    android:exported="true"
    android:theme="@style/Theme.Transparent"
    android:excludeFromRecents="true">
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="image/*" />
    </intent-filter>
</activity>
```

## 数据共享方案

Android 端主 APP 和分享进程的数据共享方案：

**方案：共享内部存储 + ContentProvider**
- 数据库文件放在内部存储
- 分享进程通过 ContentProvider 访问数据库
- 或者直接使用 FileProvider 共享数据库文件路径

**简化方案（V1.0）**：
- 分享进程直接操作数据库文件（因为是同一个应用的两个进程，共享 uid）
- 使用 `Context.MODE_MULTI_PROCESS` 或 WAL 模式
- 通过 SharedPreferences（MODE_MULTI_PROCESS）传递"有新数据"标记

```kotlin
// 共享数据标记
val prefs = context.getSharedPreferences(
    "canting_shared",
    Context.MODE_MULTI_PROCESS
)
prefs.edit().putBoolean("hasNewData", true).apply()
```

## 通知

```kotlin
object NotificationHelper {
    private const val CHANNEL_ID = "recognition_results"

    fun createNotificationChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "识别结果通知",
            NotificationManager.IMPORTANCE_DEFAULT
        )
        // ...
    }

    fun sendSuccess(context: Context, dishName: String, mealType: String) {
        val intent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(context, 0, intent, ...)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("已记录$mealType")
            .setContentText(dishName)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        NotificationManagerCompat.from(context)
            .notify(System.currentTimeMillis().toInt(), notification)
    }

    fun sendFailure(context: Context) { ... }
}
```

## 菜品匹配（Kotlin 版）

同 iOS，需要用 Kotlin 实现简化版 DishMatcher：
- 精确匹配
- 包含匹配
- 关键词归类

菜品数据从 SQLite 数据库读取（和 Flutter 侧共用同一个数据库）。

## 边界情况处理

- 首次使用，模型未初始化 → 初始化模型（可能需要几秒）
- 模型初始化失败 → 发失败通知
- OCR 识别超时（>10秒） → 发失败通知
- 图片过大 → 先压缩再识别
- 低内存设备 → 模型加载失败，降级到手动添加

## 性能优化

- OCR 识别在后台线程执行
- 图片先压缩到合适大小（最长边 1280px）
- 模型懒加载，第一次使用时才加载
- 识别完成后释放资源

## 验收标准

- [ ] 美团外卖订单截图 → 分享到餐盘 → 收到成功通知
- [ ] 打开 APP → 首页显示新记录
- [ ] 识别成功率 ≥ 85%（主流平台订单截图）
- [ ] 识别成功通知显示正确
- [ ] 识别失败时发送失败通知
- [ ] 分享过程不打开主 APP
- [ ] 主 APP 从后台切到前台时数据刷新
- [ ] PaddleOCR 模型打包进 APK
- [ ] 首次使用模型初始化正常
- [ ] 低端机型不崩溃（识别失败降级）
