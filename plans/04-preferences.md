# 阶段 04：设置与持久化

## 目标

为文字气泡核心加入微信内本地设置、浅色/深色主题配置和可靠的恢复默认能力。

## 前置条件

- 阶段 03 已通过。
- BubbleStyler 能基于 ThemeProvider 更新并恢复当前可见气泡。
- 已确认微信 8.0.60 中最稳的设置入口候选。

## 设置范围

- 总开关。
- 发送方和接收方颜色。
- 透明度。
- 圆角。
- 描边颜色和宽度。
- 阴影开关及有限参数；若阶段 03 未通过性能验证则不暴露。
- 浅色与深色模式分别配置。
- 恢复微信默认样式。
- 版本、能力状态和安全模式入口占位。

## 0.5.0 材质扩展

- 设置页新增“气泡材质”，可在“纯色”和“Liquid Glass”之间切换，默认保持纯色以避免升级后外观突变。
- 偏好 schema 升级到 3；schema 2 的颜色和外观参数原样保留，仅补充默认材质。
- iOS 26 运行时能力完整时动态创建真正的 `UIGlassEffect`；旧 SDK 不产生静态符号依赖。iOS 15–25 使用 `UIBlurEffectStyleSystemUltraThinMaterial` 和 tint 的兼容玻璃后端，设置页明确显示“兼容”。
- 两种玻璃后端共用现有气泡路径、方向色、深浅色、透明度、描边和 Cell 复用清理。诊断记录 requested material、resolved backend 和原生 API 可用性。

### 0.5.0 双平台测试

1. 当前 RootHide 设备选择 Liquid Glass，确认设置显示“Liquid Glass（兼容）”，发送/接收气泡均有模糊和 tint，滚动复用无残留；切回纯色后立即恢复现有渲染。
2. iOS 26 设备选择 Liquid Glass，确认设置显示“Liquid Glass（原生）”，诊断为 `native-uiglass-effect`，并目视确认系统折射、高光和背景适应。
3. 两个平台分别测试浅色/深色、长消息多段、快速滚动、前后台切换、降低透明度和降低动态效果。
4. iOS 26 原生路径未完成真机验证前，不将“原生 Liquid Glass”标记为发布验收通过。

## 0.5.1 无色玻璃修正

- 玻璃材质与纯色主题完全分离：玻璃模式不读取发送/接收填充色、描边色或纯色透明度，设置页隐藏这些纯色参数。
- iOS 26 原生后端将 `UIGlassEffect.tintColor` 设为 `nil`；iOS 15–25 兼容后端改为无色背景采样模糊、轻微镜片放大、方向性边缘高光和内侧暗边。
- 对 `YYAsyncImageView` 的静态 `image`、动态 `animatedImage`、`layer.contents` 和背景色分别捕获与清理；为异步图片更新安装 ABI 校验后的窄范围 setter Hook，只在当前已关联的玻璃气泡上拦截，并在切换纯色或 Cell 复用时恢复最新素材。
- 兼容后端借鉴 AndroidLiquidGlass/GooseHyperGlass 的背景采样、镜片、rim highlight 和 inner shadow 分层，但公开 UIKit 后端没有其 SDF shader 级色散折射；诊断名称使用 `compatibility-colorless-lens`，不冒充 iOS 26 原生实现。

### 0.5.1 真机测试

1. 从自定义紫色/蓝色纯色主题切换到玻璃，确认两种主题色完全消失，发送和接收玻璃本身不再有不同 tint。
2. 等待异步气泡图片加载、快速滚动并反复进入聊天，确认微信绿色/白色素材不会在玻璃下重新出现；诊断确认 `artworkHooksInstalled=true`。
3. 切回纯色并关闭插件，确认最新微信原始气泡素材能恢复，且纯色参数原值仍保留。
4. 在有聊天背景细节的位置检查无色背景采样、轻微镜片放大、亮边和暗边；纯白背景无法充分展示折射层次，不作为唯一视觉样本。

## 0.6.0 SDF 实时折射

- iOS 15–25 优先动态探测 `CABackdropLayer` 和 `CAFilter(displacementMap)`，能力完整时使用 `compatibility-sdf-displacement`；探测或应用异常会在当前微信进程内禁用该路径并回退 `compatibility-colorless-lens`。
- 位移图从现有气泡主体、圆角、尾巴和分段路径栅格化生成，使用二维欧氏距离变换构造 signed distance field，再从梯度编码 RG 折射方向；图像按尺寸、尾巴方向、分段位置和圆角缓存。
- 折射滤镜直接作用于 `UIVisualEffectView` 内部 backdrop layer，并保留 UIKit 原有轻模糊滤镜链以及方向性 rim highlight 和 inner shading，不读取纯色主题参数。
- 诊断格式 13 新增 `glassCapabilities.sdfDisplacement`，记录能力探测、当前进程降级状态和原因；后端实际生效后应为 `compatibility-sdf-displacement`。
- 该实现动态使用私有 Core Animation API，适用于当前 RootHide 注入环境，并保持业务渲染代码不依赖 RootHide 路径；重签名 IPA 仍需要独立的注入、Hook runtime 和签名构建目标。

### 0.6.0 真机测试

1. 使用包含线条、文字或图片细节的聊天背景，确认细节经过气泡边缘时发生局部方向性弯曲，而不是整体等比放大。
2. 检查诊断为 `resolvedMaterialBackend=compatibility-sdf-displacement`、`glassCapabilities.sdfDisplacement.available=true`、`probeReason=available`；若回退，结合 `probeReason` 和 `lastRuntimeFailure` 定位缺失能力。
3. 覆盖左右尾巴、单段和多段气泡、极短与极长文字、浅色和深色外观，确认折射方向随轮廓变化且没有矩形边界。
4. 快速滚动并反复进出聊天，检查首次生成缓存时无明显卡顿、内存不持续增长、Cell 复用无旧位移图串位。
5. 切换纯色、关闭插件并重新开启，确认 backdrop filters 被移除、微信原始素材恢复、再次进入玻璃后折射可重建。
6. 模拟私有滤镜不可用或应用异常，确认只回退基础兼容后端，不导致微信启动崩溃或气泡消失。

## 0.6.1 真机输入探测修正

- 0.6.0 真机诊断确认 `displacementMap` 可以创建，但 iOS 16.5 的 `inputKeys` 未完整列出已知的 `inputMaskImage` 和 `inputAmount`，导致后端在实际 KVC 应用前被错误回退。
- `inputKeys` 改为只记录到 `reportedInputKeys`，不再作为硬门控；渲染时在异常保护内依次写入位移图和强度，实际 KVC 或 backdrop 安装失败才在当前进程回退。
- 诊断格式升级到 14，新增 `inputValidationMode=guarded-kvc-runtime`；`lastRuntimeFailure` 会精确标记失败步骤，例如 `set-input-mask-image`、`set-input-amount` 或 `install-backdrop-filters`。首次实际应用或失败后会异步写入 `styling.sdfRuntime`，避免启动快照早于聊天渲染而遗漏结果。

### 0.6.1 真机复测

1. 冷启动后先确认 `resolvedMaterialBackend=compatibility-sdf-displacement`、`probeReason=available`，并记录 `reportedInputKeys`。
2. 打开有可见聊天背景的文字会话并等待首批异步 SDF 生成；重新导出诊断，确认 `disabledForProcess=false`、`lastRuntimeFailure=none`。
3. 若再次回退基础兼容，提供格式 14 诊断；精确失败步骤将决定是否需要替换键名、图像值类型或 backdrop filter 安装方式。

## 0.6.2 折射可见性与滚动性能修正

- 0.6.1 真机确认 `displacementMap` 已实际安装且没有运行时失败，但原滤镜顺序会在位移后继续执行 UIKit 高斯模糊，使折射被磨砂效果冲淡。
- SDF 活跃时临时使用只包含 `displacementMap` 的最小 backdrop 滤镜链，避免未知 UIKit 材质滤镜继续产生磨砂；退出或降级时仍按事务规则恢复完整原滤镜链和原始 scale，若外部链已变化则只移除插件持有的位移实例。
- 位移强度从 11 调整到 20，并在格式 15 诊断中记录 `originalFilterTypes` 和 `installedFilterTypes`，用于确认真机最终滤镜顺序。
- Cell 重复布局不再无条件同步执行 overlay layout；只有尺寸、方向、尾巴、分段、主题或实际 backdrop 滤镜链变化时才重建路径并重新安装滤镜，降低滚动期间主线程负担。

### 0.6.2 真机复测

1. 检查 `styling.sdfRuntime.filterChainInstalled=true`，且 `installedFilterTypes` 仅包含 `displacementMap`；该字段只证明滤镜链安装成功，最终折射仍以画面为准。
2. 在高细节聊天背景上确认气泡边缘发生明显局部弯曲，中心区域保持接近透明，不再主要表现为均匀磨砂。
3. 快速上下滚动相同会话并与 0.6.1 对比掉帧；覆盖相同尺寸 Cell 复用、长消息和连续消息分段。

## 实施步骤

1. 实现独立命名空间的 PreferenceStore。
2. 配置增加 schema version；读取异常或未知 schema 时回退安全默认值。
3. 所有值做类型和范围校验，不信任损坏的偏好数据。
4. 实现 UIKit 设置控制器，不引入 SwiftUI/Swift Runtime。
5. 优先接入经真机确认的微信设置入口；若私有设置结构不稳定，使用最小降级入口。
6. 设置变化只刷新当前可见消息和后续复用 Cell，不全局扫描整个应用视图树。
7. 监听系统 appearance 变化，选择对应浅色/深色主题。
8. “恢复插件默认主题”清除插件主题偏好并保持启用；“恢复微信原始外观”持久关闭总开关但保留主题参数；两者都不删除微信数据。
9. 设置入口失效时不影响气泡 Hook 的安全关闭和偏好读取。

## 0.3.0 实现状态

- Release 构建清单已加入 `WBBubbleSettingsHook` 和 `WBBubbleSettingsViewController`，并在白名单微信启动及镜像晚加载时尝试安装设置 Hook。
- 微信 `NewSettingViewController` 满足运行时能力条件时，设置页增加唯一的“聊天气泡”入口；入口能力缺失时跳过，不影响文字气泡 Hook。
- 偏好 schema 升级到版本 2，分别保存浅色/深色的发送与接收填充色、描边色，以及圆角、描边宽度、透明度和总开关。
- schema 1 的旧发送/接收颜色迁移为浅色主题；未知 schema 清理插件键并回退安全默认值；损坏类型和越界数值在读取时校验。
- `ThemeProvider` 已改为从偏好读取实际颜色和外观参数；系统深浅色变化会触发覆盖层重新布局并选择对应主题。
- 偏好变化通过进程内通知刷新当前可见 `CommonMessageCellView`；关闭总开关会移除当前覆盖层，后续布局也保持微信原始样式。
- 设置页区分“恢复插件默认主题”和“恢复微信原始外观”：前者重置参数并保持启用，后者仅关闭样式且保留已保存主题。
- 诊断格式升级为 6，记录偏好快照和设置 Hook 能力；插件版本和包版本升级为 `0.3.0`。
- 阴影未进入 0.3.0；只有阶段 03/04 的真机滚动性能通过后才评估。

## 0.3.1–0.3.3 设置入口修复

- Build #32 真机验证确认气泡主题生效、`NewSettingViewController` 存在且设置 Hook 安装成功，但设置界面未显示“聊天气泡”入口。
- 0.3.1 将 Hook 从 `viewDidLoad` 改到 `reloadTableData` 并刷新表格；Build #35/#36 构建成功，但真机复测仍无入口。
- 对照 `RsLuna7/WeChat_tweak` 及其新版微信头文件后确认，8.0.60 设置页实际显示模型由 `m_tableViewMgr`、`WCTableViewManager`、`WCTableViewSectionManager` 和 `WCTableViewNormalCellManager` 管理；旧 `m_tableViewInfo` 即使存在并接受 section，也不是当前可见表格的有效模型。
- 0.3.2 在设置页生命周期中检测 `_pluginCellInfo` 或“插件/插件管理”后注册 `WCPluginsMgr`，否则向 `m_tableViewMgr` 的第 0 个位置插入唯一 section 并刷新其 TableView。
- 直接插入路径会扫描 `getAllSections`/`getAllCells` 的 cell 标题防止重复；现代模型不可用或 ABI 不匹配时，才回退旧 `m_tableViewInfo` 路径。
- 诊断格式升级为 8，新增 `tableManagerAvailable`、`pluginsPortalAvailable`、`pluginsPortalRegistered`、`duplicateEntryFound`、`modelPath` 和 `insertionMethod`，区分插件归纳、现代表模型和旧模型回退。

- 诊断格式 8 的 0.3.2 真机文件仍停留在 `reason=waiting-for-settings-screen`，且 `tableManagerAvailable=false`，证明进入设置页时 `reloadTableData` Hook 未回调，插件归纳和现代表模型路径均未执行。
- 0.3.3 同时 Hook 已验证签名的 `reloadTableData`、`willAppear` 和 UIKit `viewWillAppear:`；前三者都不可用时才回退 `viewDidLoad`。可见性 Hook 可覆盖设置 Controller 或表模型在 Hook 安装前已创建并缓存的情况。
- 0.3.3 改为启动期无条件探测 `WCPluginsMgr`：只要 `sharedInstance` 与 `registerControllerWithTitle:version:controller:` ABI 合法，就立即将“聊天气泡”注册到插件归纳，不再要求设置页先出现其他插件入口；只有管理器不可用或 ABI 不匹配时才使用 `m_tableViewMgr` 直接插入兜底。

- 诊断格式升级为 9，新增 `pluginsManagerAvailable`；`lifecycleSelector` 记录已安装的 Hook 列表，`lastLifecycleSelector` 记录真机实际命中的生命周期。

### 0.3.3 真机复测重点

1. 完全结束微信、安装 0.3.3 并冷启动。
2. 进入“我 → 设置”，优先确认出现“插件/插件管理”，再进入其中确认“聊天气泡”；只有诊断显示 `pluginsManagerAvailable=false` 时才接受设置页直接入口兜底。
3. 退出并重复进入设置页至少 5 次，确认入口不消失、不重复。
4. 若入口仍未出现，进入设置页后重新读取诊断文件，重点提供 `settings.lifecycleSelector`、`lastLifecycleSelector`、`reason`、`pluginsManagerAvailable`、`tableManagerAvailable`、`pluginsPortalAvailable`、`pluginsPortalRegistered`、`modelPath`、`insertionMethod`、`apiSignaturesValid`、`entryModelAdded` 和 `tableReloaded`。

### 0.3.0 预期效果

1. 微信设置页出现一个“聊天气泡”入口，重复进入不会出现多个入口。
2. 可分别配置浅色和深色模式下发送/接收气泡的填充色与描边色。
3. 可调整 4–24pt 圆角、0–3pt 描边宽度和 35%–100% 透明度。
4. 设置变化后，当前可见文字气泡立即更新；返回聊天页或加载新 Cell 时继续使用相同设置。
5. 关闭开关或选择“恢复微信原始外观”后，总开关持久化为关闭；当前及后续文字气泡恢复微信原样，重新开启后继续使用已保存主题。
6. 选择“恢复插件默认主题”后，恢复阶段 03 的浅紫/浅蓝、深紫/深蓝主题并保持插件开启。
7. 完全结束并重新打开微信后，设置保持不变；微信版本或设置入口能力不匹配时安全跳过。

阶段 03/04 已通过。0.3.3 RootHide 包已在微信 8.0.60（8.0.60.35）真机确认插件归纳入口可见、设置页可打开且数值调整生效；后续安全模式、冲突检测和性能验收转入阶段 05。

## 验证清单

- [ ] 设置页可重复进入退出，无重复入口。
- [ ] 所有设置在微信重启后保持。
- [ ] 损坏、缺失或旧 schema 配置回退到安全默认值。
- [ ] 设置变更能刷新当前可见文字气泡。
- [ ] 深浅色切换使用正确主题。
- [ ] 恢复默认后微信原始外观完整恢复。
- [ ] 总开关关闭后不继续修改新复用的 Cell。
- [ ] 设置入口失败不会导致微信启动失败。
- [ ] 不读取或展示账号、联系人、消息正文和数据库；仅瞬时读取阶段 03 已披露的收发方向与消息 ID 元数据。

## 产物

- PreferenceStore 和 schema 迁移框架。
- UIKit 设置页及经验证的微信 8.0.60 入口适配。
- 浅色/深色主题配置。
- 即时刷新与恢复默认流程。

## 退出门槛

设置持久化、即时刷新、深浅色切换和恢复默认全部通过真机测试，设置入口异常也不会影响微信启动，才进入阶段 05。
