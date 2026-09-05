# 0.9.0-beta 测试发布，非 V1 正式封版

包名：com.canting.canting。versionName：0.9.0-beta。
主包 arm64 仅含 arm64-v8a；备用 universal 含 arm64-v8a / armeabi-v7a / x86_64。
两个 APK 的实际 versionCode 均为 5003，构建显式 force-version-code-ignoring-abi=true。
它们使用现有 Android Debug 测试证书，SHA-256：`336e3f94c188e3a5452475abaf0db1c2bd56a0d1986b5cf36cbdb3cbb6b2bd03`。
旧 beta 实测 versionCode=1；P5 arm64=2001，P5 universal=1。
同包名/同证书且旧版本码不高于5003时具备覆盖前提；不代表真实升级或数据保留已验收。
已安装高于5003的包时停止，不降级、不卸载。主备包同版本码可满足互相覆盖的版本条件，但必须匹配设备ABI。
此测试证书不是正式发行身份；以后更换证书不能假定可无损覆盖。

每个 APK 的字节数、时间、SHA-256、ABI 和证书见 package-analysis.json；构建命令及源码哈希见源码仓库 dev-docs/p6a-evidence/beta-20260906/ 下的 split/universal 文件。
