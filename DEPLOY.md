# Pinyintone iOS 上线指南（TestFlight / App Store）

你已是 Apple Developer。论文采数据建议走 **TestFlight**（内测无需完整审核，最快），正式上架可后续再做。

## 已配置（无需再处理）
- ✅ 麦克风用途说明 `NSMicrophoneUsageDescription`（录音 App 必需，否则会被拒/闪退）
- ✅ `ITSAppUsesNonExemptEncryption = NO`（仅 HTTPS，跳过每次上传的出口合规问答）
- ✅ 后端已上线：`https://pinyintone-backend.onrender.com`，App 通过 `APIConfig.plist` 连接
- ✅ 版本 `MARKETING_VERSION = 1.0`，构建号 `CURRENT_PROJECT_VERSION = 1`
- Bundle ID：`Joy.PinYintone`（建议改成反向域名如 `com.weijiezhuo.pinyintone` 更规范；非必须）

## 一、一次性设置（在 Xcode 里）
1. 打开 `PinYintone.xcodeproj`，选 **PinYintone** target → **Signing & Capabilities**。
2. 勾选 **Automatically manage signing**，**Team** 选你的开发者账号（Xcode 会自动注册 Bundle ID）。
3. 确认 Bundle ID 唯一；若提示已被占用，改成自己的反向域名。

## 二、归档上传（TestFlight）
1. 顶部设备选 **Any iOS Device (arm64)**（不能选模拟器）。
2. 菜单 **Product → Archive**，等待归档完成。
3. Organizer 窗口 → 选中归档 → **Distribute App** → **App Store Connect** → **Upload** → 一路 Next。
   - 出口合规已配 NO，不会再问加密问题。
4. 上传后约 5–15 分钟，构建在 App Store Connect 处理完成。

## 三、App Store Connect 配置
1. 登录 [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **我的 App → +新建 App**：
   - 平台 iOS、名称（如 Pinyintone）、主语言、Bundle ID 选 `Joy.PinYintone`、SKU 任意。
2. **TestFlight** 标签页：
   - 处理完的构建会出现；首次需填 **测试信息** + **出口合规**（已配，确认即可）。
   - **内部测试**：加你 App Store Connect 团队成员（最多 100 人），即时可用、无需审核。
   - **外部测试**：建测试组、加被试邮箱（最多 10000 人），首个构建需 Apple 轻量审核（通常 1 天内）。
   - 被试装 **TestFlight** App，用邀请链接/邮件即可安装。
3. **App 隐私（App Privacy）**：必须如实填写数据收集。本 App：
   - 设备标识 `deviceID`（`identifierForVendor`，非 PII）、训练用量数据（DTW 分数/F0/触发率）上报后端。
   - 原始录音**不上传**（仅本地分析）。按"用于 App 功能/分析"勾选即可。

## 四、正式上架（可选，论文期一般不需要）
TestFlight 验证无误后，在 App Store Connect 填商店页（截图、描述、分级、隐私），提交 **App 审核**。
首次审核通常 1–3 天。

## 分组（无需发码）
- 被试注册时**只填名字**，后端**均衡随机**分配 A/B，无需发码。
- 数据按 `group_assignment` 从 Neon 导出，按 `nickname` 对回个人。

## 可选完善
- **麦克风用途多语言**：当前为英文，可加各 `*.lproj/InfoPlist.strings` 提供法语/阿拉伯语本地化（提升被试体验，非上架必需）。
- **App 图标**：确认 `Assets.xcassets/AppIcon` 已填满所需尺寸，否则上传会被拦。
