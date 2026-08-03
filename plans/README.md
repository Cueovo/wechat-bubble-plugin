# MVP 实施计划索引

## 目标

按可验证、可回退的阶段实现 iOS 微信聊天气泡 MVP。每次只推进一个阶段；当前阶段通过退出门槛后，才能开始下一阶段。

## 锁定测试基线

| 项目 | 基线 |
|---|---|
| 设备 | iPhone 14 Pro Max（iPhone15,3，A16，arm64e 设备） |
| iOS | 16.5 |
| 越狱 | Dopamine 2.4.9 RootHide |
| Tweak Loader | ElleKit 1.2 |
| 微信 | 8.0.60 |
| 微信 Bundle ID | `com.tencent.xin`，须在阶段 00 真机确认 |
| 最低部署目标 | iOS 15.0 |
| 源码目标架构 | `arm64`，微信是 App Store App，不因设备为 arm64e 而强制增加 arm64e slice |
| Debian 包架构 | `iphoneos-arm64e` |
| 包方案 | Theos `roothide` |
| 构建 | GitHub Actions `macos-15` runner |
| GitHub | `https://github.com/Cueovo/wechat-bubble-plugin`（公开） |
| Package ID | `com.bi8bo.wechat.bubble` |

首个 MVP 只把上述精确组合列为 `Supported`。其他微信或环境版本保持 `Unknown`，默认不注册气泡 Hook。

## 固定技术决策

- Objective-C（ARC）+ UIKit + Theos。
- 仅注入微信主进程，只 Hook 经真机确认的消息视图私有类。
- 首版仅修改文字消息气泡的本地视觉表现。
- 不读取消息模型、聊天数据库、联系人或账号数据。
- 不 Hook 网络、登录、支付、发送和接收逻辑。
- 不全局 Hook `UIView`、`UIImageView` 或所有 `layoutSubviews`。
- 不在热路径执行文件 I/O、网络访问、JSON 解析或逐消息日志。
- 原生 RootHide `.deb` 是 MVP 唯一必须完成的交付物；普通 rootless 转换包和 TrollStore 不在本轮发布范围内。

## 阶段顺序

| 阶段 | 文档 | 结果 | 状态 |
|---:|---|---|---|
| 00 | [环境与基线](./00-environment-baseline.md) | 可复现的工具链和真机记录 | 已完成 |
| 01 | [Theos 骨架与注入](./01-theos-bootstrap.md) | 无功能、可安全加载的原生 RootHide Tweak | 已完成 |
| 02 | [气泡视图定位](./02-bubble-discovery.md) | 微信 8.0.60 的最小适配事实 | 已完成 |
| 03 | [文字气泡核心](./03-text-bubble-core.md) | 固定主题可正确应用和恢复 | 进行中 |
| 04 | [设置与持久化](./04-preferences.md) | 微信内设置、深浅色主题和恢复默认 | 进行中（0.3.0 待构建与真机验收） |
| 05 | [安全与兼容](./05-safety-compatibility.md) | 安全模式、版本门控、诊断和性能达标 | 未开始 |
| 06 | [发布候选](./06-release-candidate.md) | 可安装、升级、卸载的 MVP RootHide `.deb` | 未开始 |

依赖链：`00 → 01 → 02 → 03 → 04 → 05 → 06`，不并行修改同一个 Hook 路径。

阶段 01/02 当前真机步骤：[RootHide 安装与气泡发现诊断](./02-device-discovery-test.md)。

## 执行规则

1. 开始阶段前，把该阶段状态改为“进行中”。
2. 先实现该阶段的最小失败测试或可观察基线，再改功能。
3. 每个阶段只提交该阶段明确列出的产物，不提前塞入后续功能。
4. 真机发生启动崩溃或黑屏时立即停用/卸载 Tweak，先恢复微信，再分析原因。
5. 每次真机测试记录：插件 commit、包哈希、设备/iOS、Dopamine、ElleKit、微信版本和结果。
6. 不将微信二进制、解密产物、完整私有头文件、聊天数据或设备凭据提交到仓库。
7. 新微信版本先进入阶段 02 的独立验证，不直接扩大版本白名单。

## MVP 完成定义

- iPhone 14 Pro Max / iOS 16.5 / Dopamine 2.4.9 RootHide / ElleKit 1.2 / 微信 8.0.60 上无启动崩溃和黑屏。
- 发送与接收文字气泡可分别配置浅色、深色样式。
- 单行、多行、长文本、Emoji、链接、群聊文字和 Cell 快速复用无样式串位。
- 图片、语音、视频、文件、位置、转账等非目标消息保持微信原样。
- 插件关闭后可恢复微信默认外观，无需重装微信。
- 未知微信版本默认不注册气泡 Hook。
- 连续滚动后无持续内存增长，开启前后无明显掉帧。
- 安装、升级、降级、卸载和安全模式恢复均完成真机验证。
- 最终产物只包含自主编写的 dylib、资源和包元数据。
