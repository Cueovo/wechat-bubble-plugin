# iOS 微信聊天气泡插件技术路线（MVP）

- 决策日期：2026-08-03
- 文档状态：阶段 01/02 已完成，阶段 03 固定主题 MVP 实施中
- 项目阶段：MVP
- 目标：仅修改本机 iOS 微信聊天界面的消息气泡外观
- 计划分发：公开分发

## 1. 结论摘要

### 1.1 推荐路线

采用以下组合：

1. **语言与 UI：Objective-C（ARC）+ UIKit**。
2. **构建与打包：Theos**，最低目标 iOS 15.0。
3. **Hook：只 Hook 微信聊天消息相关的 Objective-C 私有类；业务核心不依赖特定注入器。**
4. **主交付形态：原生 RootHide `.deb`**，面向已确认的 Dopamine 2.4.9 RootHide / ElleKit 1.2 环境。
5. **次交付形态：可由 TrollFools 导入的 `.deb`/`.zip` 或独立 `.dylib`**，面向 TrollStore 支持的设备。
6. **普通未越狱重签名 IPA：仅作为实验性备选，不作为“最稳”公开发行路线。**
7. **兼容策略：微信版本白名单 + 运行时能力探测 + 未知版本默认关闭 + 本地安全模式。**
8. **MVP 只改变视觉，不读取消息内容、联系人、数据库，不 Hook 网络，不修改发送逻辑。**

### 1.2 为什么这是 2026 年 8 月最稳的组合

- 当前 App Store 微信要求 iOS 15.0 或更高版本，因此 MVP 没有必要背负 iOS 14 及更早系统的兼容成本。
- `roothide/theos` 是当前锁定真机环境的构建方案，可直接生成 `iphoneos-arm64e` RootHide 包，避免依赖设备端 Patcher Convert。
- 微信界面主体仍可通过 Objective-C Runtime/UIKit 观察和定点修改。Objective-C 对私有类、动态 Selector 和旧式 UIKit 视图树的适配成本低于纯 Swift。
- Dopamine RootHide 让微信保持 App Store 官方安装形态，不需要修改微信 Bundle ID、签名和 entitlements；相较重签名 IPA，推送、Keychain、URL Scheme、应用更新及数据容器更少受到影响。
- TrollStore/TrollFools 可以复用同一业务核心，但只覆盖有限系统，不应被描述为面向所有 iPhone 的通用方案。

## 2. 一个核心不等于三条路线同样稳定

同一个 Objective-C 气泡修改核心可以用于不同载体，但最终稳定性由注入和签名链决定。

| 路线 | 微信安装形态 | 覆盖范围 | 开发调试 | 用户安装 | 更新影响 | 稳定性判断 |
|---|---|---:|---:|---:|---:|---|
| Dopamine RootHide Tweak | 官方微信 + 独立 Tweak | 当前锁定测试机 | 成熟 | 需要越狱 | 更新 Tweak 即可 | **主路线** |
| TrollStore + TrollFools | 官方微信被原位注入 | TrollStore 支持的特定系统 | 较方便 | 无完整越狱，但门槛仍高 | 微信更新后通常要重新注入 | **次路线** |
| 普通侧载/重签名 IPA | 修改后的微信 IPA | 理论上较广，实际受签名限制 | 复杂 | 证书、续签和安装复杂 | 每次更新都要重新改包和签名 | **实验路线，不稳定** |
| App Store 正式应用 | 独立应用 | 普通 iPhone | 不可实现跨 App 修改 | 简单 | 不适用 | **不可行** |

TrollStore 官方目前列出的支持版本为 iOS 14.0 beta 2–16.6.1、16.7 RC（20H18）和 17.0；16.7.x（除 RC）及 17.0.1 以上不会因现有 CoreTrust 漏洞获得支持。因此它不能承担“公开分发给现代普通 iPhone 用户”的主路线。

## 3. 产品边界

### 3.1 MVP 包含

- 接收方与发送方气泡分别设置颜色。
- 可选圆角、描边、阴影和透明度。
- 浅色/深色模式分别配置。
- 总开关和“恢复微信默认样式”。
- 微信内的本地设置入口。
- 本地能力诊断、安全模式和冲突提示。
- 首版至少覆盖文字消息；其他消息类型按测试结果逐类开放。

### 3.2 MVP 不包含

- 不读取、保存或上传聊天内容。
- 不访问微信数据库、联系人、账号凭据或 Keychain。
- 不 Hook 请求、响应、登录、支付、消息收发和反撤回逻辑。
- 不做自动化操作、抢红包、虚拟定位、步数修改或多开。
- 不改变气泡布局尺寸、消息 Cell 高度、点击区域和无障碍语义。
- 不支持从服务器下发脚本、Selector、Hook 规则或可执行代码。
- 不实现越狱/插件检测规避或账号风控绕过。
- 不承诺所有微信版本自动兼容，也不承诺“零封号风险”。

将范围严格限制在 UI 表现层，不能消除微信协议风险，但能显著减少崩溃面、隐私风险和版本适配成本。

## 4. 推荐技术栈

| 层级 | 选择 | 决策理由 |
|---|---|---|
| 语言 | Objective-C + ARC | 与 UIKit、Objective-C Runtime 和微信私有类交互直接；避免 MVP 引入 Swift/Orion 运行时与桥接复杂度 |
| UI | UIKit | 微信当前聊天界面兼容路线的基础；无需引入 SwiftUI |
| 构建 | `roothide/theos` | 直接生成当前真机所需的原生 RootHide 包 |
| Hook 表达 | 定点 Objective-C Runtime Hook；可在 RootHide 入口薄层使用 Logos | 核心不依赖大范围 UIKit Hook，失败时可以能力门控关闭 |
| 偏好存储 | `NSUserDefaults`，插件独立命名空间 | 设置简单、本地、无数据库依赖；必须做 schema 版本迁移 |
| 资源 | 独立 `.bundle` | 主题资源与逻辑分离；同时适配 `.deb` 和 TrollFools 导入 |
| 主包 | 原生 RootHide `.deb` | `roothide` scheme、源码 `arm64`、Debian 架构 `iphoneos-arm64e`，无需设备端 Convert |
| 次包 | 注入用 `.dylib` + `.bundle`，或 TrollFools 可导入包 | 复用核心，覆盖 TrollStore 设备 |
| CI | 固定 Theos commit、固定 SDK/Xcode 的 macOS 构建机 | 构建可复现；Windows 本地环境不作为发布产物的唯一来源 |

### 4.1 为什么 MVP 不首选 Swift/Orion

Swift/Orion 可以开发 Tweak，但本项目主要面对动态 Objective-C 私有类，并且需要同时考虑 RootHide 与独立 dylib 注入。Objective-C 的依赖更少、二进制更直接、动态 Runtime 操作更成熟。设置页也没有复杂到需要 SwiftUI。

这不是否定 Swift，而是 MVP 阶段以兼容和可诊断性优先。后续独立管理 App 可以使用 SwiftUI，但不应让微信进程内的核心依赖它。

### 4.2 开发环境

当前仓库位于 Windows。建议：

- 日常编辑和静态检查：Windows + WSL2 + Theos。
- 真机逆向观察、发布构建和签名验证：macOS + 固定版本 Xcode/SDK。
- 发布包：由固定 macOS CI 生成并附带哈希；禁止开发者本机随意产出正式包。
- 真实测试必须使用专用测试机和测试微信账号，不能依赖模拟器判断私有 UI 兼容性。

Theos 可以在 Windows/WSL 构建 App Store 应用目标的 Tweak；Theos 文档也说明，App Store App 本身不要求 arm64e slice。MVP 仍应在 arm64 和 arm64e 设备上分别做真机验证，但不要无必要地为微信插件引入系统二进制 Hook。

## 5. 总体架构

```text
Bootstrap
  ├─ ProcessGuard           仅允许微信主进程
  ├─ VersionGate            iOS/微信/插件版本门控
  ├─ CapabilityRegistry     运行时检查类、方法和视图能力
  └─ SafeMode               启动哨兵与本地安全模式

BubbleFeature
  ├─ BubbleHookAdapter      只负责挂接候选消息视图生命周期
  ├─ BubbleLocator          在目标消息 Cell 内定位真正气泡视图
  ├─ MessageDirection       只依据 UI 结构判断收/发方向
  ├─ BubbleStyler           幂等地应用或恢复样式
  └─ ThemeProvider          提供本地静态主题

Preferences
  ├─ SettingsViewController 微信内设置页
  ├─ PreferenceStore        带 schema 版本的本地设置
  └─ DiagnosticsExporter    不含账号和消息内容的诊断信息

Distribution
  ├─ RootlessPackage        主发行 `.deb`
  └─ InjectPackage          TrollFools 用 dylib/bundle 或导入包
```

### 5.1 模块原则

- **注入层薄，业务层纯。** 注入器变化时，不重写主题、定位和配置逻辑。
- **能力探测优先于版本判断。** 版本白名单决定是否启动，类/Selector/视图形态探测决定某个功能是否开启。
- **失败关闭。** 找不到候选类或气泡视图时保持微信原样，不猜测、不强转、不崩溃。
- **幂等。** Cell 会复用且频繁布局，同一视图重复执行不能叠加子视图、阴影或手势。
- **可恢复。** 关闭插件后必须移除自有图层并恢复原属性，不能要求重装微信。

## 6. Hook 与气泡定位策略

### 6.1 切入点

公开项目显示，微信 8.0.x 的聊天区域可观察到 `CommonMessageCellView` 等候选类，但私有类名不是稳定 API。该名称只能作为首个适配器候选，不能写成永久契约。

推荐顺序：

1. 微信启动完成并进入前台后延迟初始化，而不是在 dylib 构造阶段立即遍历 UI。
2. 检查候选类是否存在、生命周期方法签名是否匹配。
3. 只挂接候选消息视图的 `layoutSubviews`/配置完成等窄生命周期点。
4. 必须先执行原实现，再在当前消息 Cell 的局部视图树中定位气泡。
5. 通过类名、视图类型、图片拉伸属性、层级关系、尺寸和位置的组合评分识别气泡，不依赖单一固定下标。
6. 只修改识别置信度达到阈值的视图；否则跳过。

具体类名和 Selector 必须在开发阶段通过合法持有的测试设备动态观察后写入版本适配器，本文不把未经验证的私有接口写死为实现事实。

### 6.2 收发方向判断

优先根据局部 UI 结构判断，例如气泡中心相对于 Cell 中线的位置，以及头像与气泡的相对关系。不要为了判断方向而读取消息模型、账号 ID 或聊天数据库。

### 6.3 样式实现

最稳顺序：

1. **纯色/透明度：** 修改已定位气泡容器的背景或专用自有图层。
2. **圆角/描边：** 使用目标视图的 layer 或单个关联样式层。
3. **阴影：** 独立外层样式层；不能破坏微信原有 `masksToBounds` 和内容裁剪。
4. **图片主题：** 后续版本才引入可拉伸图片；必须正确设置 cap insets，避免尖角和边缘变形。
5. **材质/模糊：** 不进入首版默认功能，因为滚动性能和层级冲突风险更高。

首版不得改动 Auto Layout 约束、frame 计算和 Cell 高度。气泡修改必须是纯视觉覆写。

### 6.4 Cell 复用

每个被处理的视图通过关联对象记录：

- 插件样式层引用；
- 上一次主题 ID；
- 上一次方向；
- 微信原始属性快照；
- 当前适配器版本。

复用到不同消息或方向改变时重新应用；插件关闭或识别失败时恢复原状并清理插件对象。

## 7. 版本兼容策略

### 7.1 支持口径

不要宣称“支持最新版微信”。公开发布只能声明经过测试的精确组合：

```text
iPhone 型号 / SoC + iOS 精确版本 + 越狱/注入环境版本 + 微信精确版本 + 插件版本
```

截至本文调研时，App Store 页面显示微信版本为 8.0.75，要求 iOS 15.0 或更高；它应作为首轮调研候选，而不是在没有真机验证前直接标记为支持。

### 7.2 白名单和能力门控

- `Supported`：完整回归通过，默认可开启。
- `Compatible`：关键能力探测通过，但未完成全矩阵回归；默认关闭并显示实验提示。
- `Unknown`：版本未知，气泡 Hook 不注册。
- `Blocked`：已知崩溃、黑屏或严重布局问题，强制关闭。

版本白名单随插件新版本发布，不从服务器下发运行时代码或动态 Hook 规则。远程最多提供纯文本版本提示；MVP 建议连远程提示也暂不实现。

### 7.3 适配器

按微信版本族划分适配器，而不是在一个 Hook 中堆叠大量判断。每个适配器声明：

- 候选宿主类；
- 候选生命周期方法；
- 气泡识别规则；
- 支持的消息类型；
- 已验证版本区间；
- 必须满足的能力断言。

微信版本变化时优先新增/调整适配器，核心样式层保持不变。

## 8. 稳定性设计

### 8.1 安全模式

采用启动哨兵：

- 插件开始初始化时写入“本次启动未完成”。
- 微信稳定进入前台并保持一段观察窗口后标记成功。
- 连续多次未完成才进入安全模式，避免用户正常强制结束微信被误判。
- 安全模式保留设置和诊断入口，但不注册气泡修改 Hook。
- 用户可在设置中关闭功能、恢复默认、清理状态，无需卸载微信。

阈值需经测试确定；可参考公开 UI Tweak 使用的“90 秒窗口、连续五次”思路，但不能未经验证直接照搬数值。

### 8.2 冲突处理

- 维护已知冲突插件标识列表。
- 检测到另一个插件也修改聊天气泡时显示明确警告。
- 不静默篡改、禁用或卸载其他插件。
- Hook 时保存并调用当时的前序实现，避免假设自己是唯一 Hook。
- 发布说明列出不建议共存的插件和恢复步骤。

### 8.3 性能预算

聊天列表滚动是高频路径：

- 每次布局只在当前 Cell 的局部树中搜索。
- 对已识别的视图做关联缓存，并在层级变化后才重新定位。
- 不在布局回调中读文件、写日志、解析 JSON、创建图片或访问网络。
- 主题对象预计算并缓存。
- Release 默认不输出逐消息日志。

验收时以“开启前后滚动无肉眼掉帧、内存不随滚动持续增长”为底线，并用 Instruments 的 Time Profiler、Core Animation 和 Allocations 做对比。

### 8.4 诊断信息

允许导出的字段：

- 插件版本；
- iOS 版本和设备型号；
- 微信版本；
- 注入形态和 Hook backend；
- 候选类/Selector 是否存在；
- 适配器选择结果；
- 安全模式和冲突状态；
- 最近一次不含内容的内部错误码。

禁止导出：微信号、手机号、联系人、聊天名称、消息正文、媒体路径、数据库路径、Cookie、Token、Keychain 内容和完整视图树文本。

## 9. 打包与分发

### 9.1 RootHide 主包

- Bundle Filter 仅匹配微信主 Bundle（`com.tencent.xin`），并增加主可执行文件守卫。
- 使用固定 revision 的 `roothide/theos` 和 `THEOS_PACKAGE_SCHEME=roothide`，源码目标 `arm64`，Debian 架构 `iphoneos-arm64e`。
- `.deb` 明确声明最低固件和 Tweak Loader 兼容依赖，必须可由 RootHide Sileo 直接安装，不能依赖 Patcher Convert。
- 安装/升级后只结束微信进程，不重启 SpringBoard，除非实际验证要求如此。
- 应用数据使用系统容器 API；若后续访问 jailbreak 文件，必须使用 RootHide 提供的路径 API，禁止硬编码 `/var/jb` 或 `/Library`。

### 9.2 TrollStore/TrollFools 次包

- 复用 BubbleFeature、Preferences 和 Runtime Capability 代码。
- 输出不依赖 RootHide 绝对路径的 dylib 和资源 bundle。
- 注入包不得假设设备已安装 ElleKit/Substrate；如果使用 Hook backend，必须明确声明并验证依赖，或使用独立 Objective-C Runtime 入口。
- 微信每次升级后，将“重新注入并重新跑兼容检测”视为标准流程。
- 只支持 TrollStore 官方列明的系统，不宣传支持 17.0.1+ 的普通设备。

### 9.3 不推荐的重签名 IPA

普通侧载会修改微信包并重新签名，可能影响：

- Bundle ID、App Groups 与数据容器；
- Keychain access groups；
- APNs 推送 entitlement；
- Universal Links、URL Scheme 与分享扩展；
- Apple Watch/扩展组件；
- 证书吊销和 7 天/年度续签；
- 微信自身完整性与账号风控。

因此不发布“内置插件微信 IPA”，也不分发微信二进制。若后续保留实验支持，只发布自主编写的 dylib/资源和用户自行操作的说明，不将其标记为稳定版。

### 9.4 App Store 不可行

Apple 的沙箱和强制代码签名不允许普通第三方应用修改另一个已安装 App；App Review Guideline 2.5.2 也禁止下载、安装或执行改变应用功能的代码。该项目不能作为正常 App Store 插件发布。

## 10. 测试矩阵与发布门槛

### 10.1 建议首轮矩阵

| 维度 | 最低组合 | 主组合 | 补充组合 |
|---|---|---|---|
| iOS | 15.x 可用越狱版本 | 16.x 可用越狱版本 | TrollStore 支持的 17.0 |
| SoC | arm64 老设备 | arm64e 设备 | 不同屏幕宽度设备 |
| 环境 | Dopamine RootHide + ElleKit | 同一精确 RootHide 基线 | TrollStore + TrollFools |
| 微信 | 8.0.60 精确 build | 后续候选版本，经验证后加入 | 前一支持版本 |
| 外观 | 浅色 | 深色 | 大字体/关怀模式 |
| 会话 | 单聊 | 群聊 | 公众号/服务通知只做不崩溃验证 |

具体越狱可支持的 iOS 小版本和设备范围以 Dopamine/palera1n 等上游发布说明为准，不在插件文档中用一个宽泛区间替代真实矩阵。

### 10.2 消息场景

必须覆盖：

- 发送与接收文字；
- 单行、多行、超长文字、链接和 Emoji；
- Cell 快速复用、连续滚动和回到历史消息；
- 群聊昵称、头像、时间分隔、引用/回复状态；
- 图片、语音、视频、文件、位置、转账等未支持类型保持微信原样；
- 横竖屏/分屏（如适用）、字体缩放、深浅色切换；
- 插件开关即时恢复；
- 多插件冲突、安全模式、未知微信版本。

### 10.3 Release Gate

以下条件全部满足才发布：

1. 支持矩阵中的每个组合均无启动崩溃、黑屏和崩溃循环。
2. 未知微信版本默认不启用 Hook。
3. 未支持消息类型保持原样，点击和长按行为不变。
4. 连续滚动和反复进入会话后，插件对象与内存不持续增长。
5. 开启/关闭前后的布局、辅助功能和消息操作回归通过。
6. 诊断包经人工检查，不含账号及聊天数据。
7. rootless 和 TrollStore 产物来自同一源码 tag，可校验哈希。
8. 安装、升级、降级、卸载和安全模式恢复流程均通过真机测试。

## 11. 开发阶段

### 阶段 0：可行性验证

- 在专用测试机确认目标微信版本、消息 Cell 候选类和气泡子视图。
- 验证只修改视觉属性即可覆盖文字收发气泡。
- 记录版本适配器事实，不提交微信二进制、解密产物、私有数据或完整头文件。

### 阶段 1：最小核心

- Bootstrap、ProcessGuard、VersionGate、CapabilityRegistry。
- 单一已验证微信版本。
- 仅文字消息、两种纯色、总开关和恢复默认。
- 原生 RootHide `.deb` 单路线先达到稳定。

### 阶段 2：稳定性

- 安全模式、诊断、Cell 复用、内存和滚动性能验证。
- 深浅色模式、圆角/描边/阴影。
- 未知版本失败关闭与冲突提示。

### 阶段 3：第二交付形态

- 抽离注入入口，输出 TrollFools 可用包。
- 跑独立 TrollStore 测试矩阵。
- 不因第二路线破坏 RootHide 主路线。

### 阶段 4：公开发布准备

- 精确支持矩阵、变更记录、包哈希、卸载与恢复说明。
- 隐私说明和风险提示。
- 建立新微信版本的隔离验证流程，通过后才扩展白名单。

## 14. 最终决策记录

### 采用

- Objective-C（ARC）+ UIKit。
- Theos 作为统一构建/打包系统。
- 注入方式无关的气泡核心和窄范围 Runtime Hook。
- 原生 RootHide `.deb` 作为主发行物。
- TrollStore/TrollFools 作为有限设备的次发行物。
- 微信版本白名单、能力探测、未知版本关闭、安全模式。
- 首版只做纯视觉和本地设置。

### 暂不采用

- Swift/Orion 作为微信进程内 MVP 主技术。
- SwiftUI 设置页。
- 全局 Hook `UIView`、`UIImageView` 或 `layoutSubviews`。
- 修改消息模型、数据库或网络层。
- 远程脚本/远程 Hook 规则。
- 普通侧载重签名 IPA 作为主路线。
- App Store 分发。

### 一句话架构

> 用 `roothide/theos` 构建一个 Objective-C/UIKit 的窄范围 UI Tweak，以原生 RootHide `.deb` 为稳定主包，用同一业务核心派生 TrollFools 注入包；对未知微信版本默认不工作，而不是冒险 Hook。

## 15. 调研来源

访问日期均为 2026-08-03：

1. Theos 文档首页：<https://theos.dev/docs/>
2. RootHide Developer：<https://github.com/roothide/Developer>
3. `roothide/theos`：<https://github.com/roothide/theos>
4. Theos Packaging：<https://theos.dev/docs/packaging.html>
5. Theos Swift：<https://theos.dev/docs/Swift.html>
6. TrollStore README：<https://github.com/opa334/TrollStore/blob/main/README.md>
7. TrollFools README：<https://github.com/Lessica/TrollFools/blob/main/README.md>
8. ElleKit：<https://github.com/tealbathingsuit/ellekit>
9. 微信 App Store 页面：<https://apps.apple.com/cn/app/%E5%BE%AE%E4%BF%A1/id414478124>
10. 腾讯微信软件许可及服务协议：<https://weixin.qq.com/agreement?lang=zh_CN>
11. Apple App Code Signing：<https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web>
12. Apple Runtime Process Security：<https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web>
13. Apple App Review Guidelines：<https://developer.apple.com/app-store/review/guidelines/>
14. WeChatGlass（用于观察公开的现代微信 UI Tweak 工程实践，不作为兼容性保证）：<https://github.com/RayrenSX/WeChatGlass>

> 注：微信私有类和社区项目不是稳定官方 API；引用它们只用于评估可行性和工程实践。真正的支持范围必须以本项目真机测试矩阵为准。
