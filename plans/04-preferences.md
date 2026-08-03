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

## 0.6.3 原生 backing scale 位移贴图

- 0.6.2 真机确认活动 backdrop 链仅包含 `displacementMap`，磨砂已消失且没有运行时错误，但 1× 位移图传给 3× backdrop 后折射仍不明显。
- 位移图现在按 `UIScreen.scale` 生成原始 CGImage 像素，路径变换、SDF 边缘宽度和 padding 同步按 scale 换算；贴图与 backdrop backing scale 保持一致。
- 缓存键升级为 `v3-native`，输出和 padded 像素均有原生分辨率预算，继续保留串行异步生成、内存成本限制、共享等待者通知和失败时的进程级安全回退。
- 格式 16 诊断新增 `mapEncoding`、`mapScale`、`backdropScaleRequested`、`backdropScale` 读回值、`backdropContentsScale`、backdrop 尺寸、map 像素尺寸、`generationMilliseconds`、`inputAmountReadback` 和默认 `inputOffset` 读回值。

### 0.6.3 真机复测

1. 确认 `mapEncoding=rg-normal-native-backing-scale`，且 `mapScale` 与 `backdropScale` 相等。
2. 将 `mapPixelWidth/mapPixelHeight` 与气泡点尺寸对比，确认约为设备 scale 倍数。
3. 在文字气泡覆盖背景树枝、灯光边缘等高对比细节的位置观察边缘弯曲，并再次检查快速滚动性能。

## 0.6.4 显式位移偏移与圆弧折射曲线

- 0.6.3 真机确认 map/backdrop 均使用 3× backing scale，`inputAmount=20` 已成功读回且滤镜链只有 `displacementMap`，但背景仍无可见弯曲；`inputOffset` 因从未设置而不可读。
- 对照 GooseHyperGlassCDN 的 WebGL 实现，将边缘强度从 smoothstep 改为 `circleMap(1 - distance / refractionHeight)`，使折射集中在玻璃边缘；该项目使用自定义 WebGL backdrop 采样而非 UIKit `CAFilter`，这里只移植其折射剖面数学。
- 显式设置 `inputOffset=CGPointZero` 后再读回，确保私有位移滤镜完成输入初始化；缓存键升级为 `v4-circle`。
- 格式 17 诊断新增 `inputOffsetSet` 与 `inputOffsetMatchesRequested`，并在实际安装滤镜时以同一个气泡同时记录 map/backdrop 的逻辑尺寸、像素尺寸和比值，避免全局最后生成值与最后安装值来自不同气泡。

### 0.6.4 真机复测

1. 确认 `inputOffsetSet=true`、`inputOffsetReadable=true`、`inputOffsetMatchesRequested=true` 且 X/Y 均为 0。
2. 确认 `mapPixelWidth/backdropWidth` 与 `mapPixelHeight/backdropHeight` 的比值均约等于 `mapScale`。
3. 在月面纹理等高频背景上检查气泡边缘弯曲；若仍无位移，则停止继续猜测 `CAFilter` 贴图语义，转入显式 backdrop 捕获与 Metal/Core Image 自定义采样路线。

## 0.6.5 显式背景捕获与 Core Image 折射

- 0.6.4 真机诊断确认 `inputOffset` 已成功设置和读回、`inputAmount=20`、map/backdrop 逻辑尺寸一致、3× 像素比例一致、滤镜链只含 `displacementMap` 且无运行时错误，但画面仍只有透明效果；因此该私有滤镜在当前 iOS 16.5 目标环境中判定为操作上无效，不再继续猜测其贴图语义。
- 兼容后端改为 `compatibility-explicit-refraction`：在主线程只捕获气泡周围带 24pt 采样边距的窗口区域，捕获时临时排除当前 `CommonMessageCellView`，避免把气泡文字和覆盖层递归采回纹理。
- 捕获结果交给公开 `CIWarpKernel`，根据圆角矩形 signed-distance 边缘法线和 circle profile 将采样坐标向外偏移；气泡原有路径遮罩继续负责左右尾巴和多段轮廓裁切，高光与内阴影层保持不变。
- 滚动期间按窗口坐标变化进行 60ms debounce，只在位置稳定后刷新局部纹理；内核不可用、捕获失败或输出失败时保留超薄无色材质作为安全回退。
- 诊断格式升级到 18，新增 `glassCapabilities.explicitRefraction` 和 `styling.explicitRefractionRuntime`，记录捕获次数、失败原因、捕获/warp 耗时、scale 及输入输出像素尺寸。

### 0.6.5 真机复测

1. 在高对比月面、树枝或文字背景上停住滚动，确认气泡边缘附近出现明确的局部弯曲，中心背景基本保持原位置，且不再只是透明。
2. 导出格式 18 诊断，确认 `resolvedMaterialBackend=compatibility-explicit-refraction`、`explicitRefractionRuntime.applicationSucceeded=true`、`captureCount>0`、`lastFailure=none`，输入宽高应分别比输出宽高多约 `48×captureScale` 像素。
3. 快速连续滚动后停住，确认折射纹理会更新到当前位置，不出现旧消息文字、头像或气泡自身的递归残影；比较 `captureMilliseconds` 与 `warpMilliseconds` 并观察是否有明显掉帧。
4. 覆盖收发方向、单段和连续消息分段、浅色/深色、切换纯色与关闭插件；捕获失败时气泡仍应显示透明兼容材质而不是消失或崩溃。

## 0.7.0 低版本实时 Metal 液态玻璃重写

- 0.6.5 的 60ms debounce 只会在位置稳定后更新气泡纹理，本质仍是静态快照，不满足滚动和动画期间实时折射要求；该路线从发布候选中否决，`CIWarpKernel` 不再进入构建。
- 新后端为 `compatibility-realtime-metal`。每个窗口只维护一个 `CADisplayLink`、一个背景捕获缓冲区和一张 IOSurface-backed `CVMetalTexture`；一帧只捕获窗口一次，所有可见文字气泡共享同一背景纹理，不再逐气泡创建 `UIImage` 或执行 Core Image 输出。
- 捕获事务会同步排除所有已注册的 `CommonMessageCellView`，得到不含气泡文字、头像和插件覆盖层的底层聊天背景，并在同一 Core Animation 事务提交前恢复 opacity，避免屏幕闪烁和递归残影。
- 每个气泡使用透明 `CAMetalLayer`，在共享命令缓冲区中按窗口坐标采样背景；fragment shader 持续计算圆角 SDF 法线、边缘折射、中心透镜放大、RGB 色散、低成本软化、背景亮度 tint、内侧暗边和方向性 rim highlight。现有气泡路径 mask 继续精确裁切左右尾巴和多段轮廓。
- 同一窗口最多保留一帧 GPU 工作；上一帧尚未完成时直接丢弃新帧，避免覆盖 GPU 正在读取的 CVPixelBuffer。无可见气泡时销毁显示链路；Metal pipeline、背景捕获或 drawable 不可用时继续显示无色 UIKit 材质回退。
- 诊断格式升级到 19，新增 `glassCapabilities.realtimeMetal` 和 `styling.realtimeMetalRuntime`，记录共享捕获次数、实际渲染气泡帧数、丢帧、捕获/编码耗时、捕获 scale、像素尺寸和 Metal 错误。

### 0.7.0 真机复测

1. 在高对比聊天背景上持续拖动和惯性滚动，确认背景弯曲与气泡位置逐帧同步，不能等停止后才跳到新纹理。
2. 停住后缓慢移动列表，检查边缘折射、轻微色散、方向性亮边和暗边；气泡中心保持接近原背景，不应退化成整块模糊或整体静态放大。
3. 导出格式 19 诊断，确认 `resolvedMaterialBackend=compatibility-realtime-metal`、`realtimeMetalRuntime.applicationSucceeded=true`、`captureCount` 持续增长、`renderedFrameCount` 大于捕获次数且 `lastFailure=none`。
4. 快速滚动 30 秒并记录 `captureMilliseconds`、`encodeMilliseconds`、`droppedFrameCount`；确认没有明显持续掉帧、内存增长、文字/头像递归残影和 Cell 复用串位。
5. 覆盖长消息、多段消息、左右尾巴、浅色/深色、前后台切换、切换纯色和关闭插件；任何 Metal/capture 失败都只能回退到无色 UIKit 材质，不能导致气泡消失或微信崩溃。

## 0.7.1 坐标校准与捕获卡顿修复

- 0.7.0 真机诊断记录到 11 个活动气泡、`captureMilliseconds=51.219`、`encodeMilliseconds=0.585`。卡顿根因不是 Metal，而是主线程以 1.25× 每帧执行一次完整 `window.layer renderInContext:`；约 51ms 的捕获成本不可能达到 60 FPS。
- 0.7.1 不再逐帧重新展平窗口。进入聊天并等待当前可见气泡注册稳定 50ms 后只生成一张排除文字 Cell 的干净窗口背景；后续每个显示帧只按气泡实时窗口坐标更新 Metal UV，静态聊天壁纸下滚动仍逐帧同步，但不再承担全窗口 CPU 捕获。
- 窗口尺寸变化、当前聊天的全部气泡离开后重新进入时会使缓存失效并重新捕获；同一窗口、同一聊天滚动和 Cell 复用继续共享已有干净背景。
- 第一次捕获会在不提交到屏幕的 Core Animation 事务中绘制顶部红色和底部绿色校准标记，并直接检查 BGRA 缓冲区的上下行，自动确定 `renderInContext:` 输出相对 Metal 纹理是否需要 Y 翻转。无法可靠识别时按 0.7.0 真机错位表现启用 Y 翻转回退。
- 诊断格式升级到 20，增加 `capturePolicy=capture-once-reuse-with-live-window-uv`、`backdropReuseCount`、`textureYFlipped`、`orientationCalibrated` 和 `orientationFallbackUsed`。正常滚动时 `captureCount` 应保持不变，`backdropReuseCount` 和 `renderedFrameCount` 持续增长。

### 0.7.1 真机复测

1. 用具有明显上下差异的聊天背景检查气泡内图案与气泡外同一窗口位置一致；诊断中确认 `orientationCalibrated=true`，并记录 `textureYFlipped`。
2. 连续拖动和惯性滚动 30 秒，确认 `captureCount` 不随每帧增加、`backdropReuseCount` 持续增加，且不再出现约 51ms 的逐帧主线程停顿。
3. 切出聊天再进入、切换横竖屏或窗口尺寸后确认会产生一次新捕获，随后继续复用；新气泡不得采到旧消息文字或头像。
4. 如果仍有坐标错位，导出格式 20 诊断并附一张能同时看到气泡内外相同背景特征的截图，用于区分 Y 翻转、窗口原点或壁纸 contentMode 问题。

## 0.7.2 壁纸隔离与方向检测修复

- 0.7.1 真机诊断证明性能修复有效：`captureCount=1`、`renderedFrameCount=624`、`backdropReuseCount=624`，不存在每帧重新捕获；但同时记录到 `orientationCalibrated=false`、`orientationFallbackUsed=true`、`textureYFlipped=true`。单像素校准失败后强制翻转导致错误窗口区域进入气泡，截图中表现为输入栏表情按钮出现在消息气泡右上角。
- 0.7.2 将方向校准改为扫描纹理左侧完整标记带，分别统计顶部红色和底部绿色标记的像素数量及平均行号；只有两个标记均达到阈值才接受检测结果，失败时不再盲目强制 Y 翻转。
- 捕获时优先识别覆盖聊天区域的大型、非消息 Cell `UIImageView` 作为壁纸源，并在捕获事务中隐藏通向该壁纸分支之外的兄弟视图。这样输入栏按钮、头像、导航栏和消息内容不会进入共享折射纹理；无法识别独立壁纸视图时才回退到排除消息 Cell 的窗口捕获。
- Metal 输出在气泡 mask 内改为完全不透明，避免成功渲染后底层 UIKit backdrop 仍以 2%–10% 混入错误位置的系统控件。
- 诊断格式升级到 21，新增 `redMarkerPixels`、`greenMarkerPixels`、`redMarkerRow`、`greenMarkerRow`、`captureSourceClass`、`captureSourceFrame` 和 `lastSurfaceFrames`。这些字段可以直接核对每个气泡的窗口坐标、实际采样 Y 区间和捕获源。

### 0.7.2 真机复测

1. 同一月球壁纸下确认“我”气泡右上角不再出现输入栏表情按钮，气泡内外陨石坑纹理位置连续。
2. 诊断中优先应看到 `capturePolicy=isolated-wallpaper-capture-once-live-window-uv`、`captureSourceClass` 为背景图视图、`orientationCalibrated=true` 且 `orientationFallbackUsed=false`。
3. 如果方向检测仍回退，检查红绿标记像素数和平均行号；`lastSurfaceFrames` 应显示该气泡 `frameY` 与屏幕实际位置一致，`sampledTop`/`sampledBottom` 不得指向底部输入栏。
4. 连续滚动 30 秒，`captureCount` 仍应保持不变，`backdropReuseCount` 和 `renderedFrameCount` 持续增长。

## 后续实时 Metal 优化路线（已确认）

### 0.7.3：按需渲染与自适应光学

目标是在不改变已验证正确的背景坐标链路前提下，降低静止页面 GPU 消耗并减少固定参数带来的塑料感。

实现状态：已与 0.8.0 合并进入当前 0.8.0 源码，待 CI 和真机诊断验收。

- 显示链路改为按需运行：拖动、惯性滚动、Cell 复用、窗口变化、路径或布局变化时恢复 60 FPS；连续若干帧气泡窗口坐标和滚动偏移稳定后暂停 `CADisplayLink`，保留最后一帧 drawable。
- 当前 shader 没有依赖持续时间的内部动画，因此静止时不得继续无意义地为每个气泡申请 drawable 和编码 render pass。
- 使用气泡短边计算 `edgeWidth`、`refraction`、`dispersion` 和 `zoom`，避免单字小气泡折射过重、长消息气泡边缘过弱。
- 降低固定 RGB 色散；色散只应在高对比边缘轻微可见，不应形成持续彩虹描边。
- 将折射剖面分成稳定中心、平滑过渡和边缘强折射三个区域；中心背景尽量保持原位，主要位移集中在玻璃边缘。
- Metal 首帧成功后收敛 Core Animation 的 `shadeLayer`、`borderLayer` 和 `highlightLayer`，避免 Metal 高光与 CA 高光叠加产生白色塑料描边；Metal 尚未成功或失败时仍保留完整 UIKit 回退层。
- 诊断增加 display-link 唤醒/暂停次数、稳定帧数、活动/静止状态、可见气泡数和本帧是否实际编码。

验收标准：

1. 连续滚动时背景采样逐帧跟随，无停止后跳变；停止滚动后 display link 自动暂停。
2. 静止 30 秒时 `renderedFrameCount` 不再持续增长；再次拖动后立即恢复。
3. 小、中、长气泡的中心背景稳定，边缘折射强度视觉一致；色散只在高对比边缘出现。
4. Metal 成功后不出现双层白边，Metal 失败时 UIKit 镜片仍完整可见。

### 0.8.0：真实气泡路径 SDF

目标是让气泡主体、左右尾巴和连续消息分段轮廓真正参与折射法线计算，而不再只用圆角矩形 SDF 后再由 `CAShapeLayer` 裁切。

实现状态：R8 SDF、轮廓缓存、真实路径法线、圆角回退和诊断字段已接入当前 0.8.0 源码，待 CI 和真机验证尾巴方向、生成耗时与缓存命中。

- `applyToView:path:bounds:` 接收的真实 `UIBezierPath` 在路径或尺寸变化时栅格化为二值 mask，并生成单通道有符号距离场纹理。
- SDF 纹理按尺寸、方向、尾巴、消息分段、圆角和路径签名缓存；相同轮廓复用，避免 Cell 复用和滚动期间重复生成。
- 根据气泡尺寸选择有限的 SDF 分辨率档位，小气泡约 `64×64`，中等气泡约 `128×64`，长消息上限约 `256×128`，兼顾尾巴细节和内存。
- Shader 从 SDF 邻域梯度计算稳定法线，同一距离场统一控制 alpha、边缘抗锯齿、折射、色散、高光和暗边。
- 尾巴尖端、尾巴与主体连接处、连续消息顶部/中部/底部轮廓必须使用真实法线；移除 `sdRoundBox` 作为活动光学轮廓。
- 首版保留 `CAShapeLayer` mask 作为安全裁切，真机确认 Metal SDF alpha 与路径完全一致后再评估删除，避免亚像素边缘泄漏。
- SDF 生成失败、纹理创建失败或路径为空时继续使用现有圆角近似/无色 UIKit 材质，不得导致气泡消失或微信崩溃。
- 诊断增加 SDF 缓存命中/未命中、生成耗时、纹理尺寸、活动 SDF 数量以及回退原因。

验收标准：

1. 左右尾巴内的折射方向与尾巴边界垂直，不再沿圆角矩形主体方向偏移。
2. 连续消息不同分段的直边、圆角和尾巴均有一致边缘厚度。
3. SDF 生成只发生在轮廓首次出现或布局改变时，滚动期间缓存命中且无明显主线程停顿。
4. 高对比壁纸下 mask 外无采样泄漏，细小气泡尾巴不被截断。

### 0.8.1：显式壁纸源与 UV 矩阵

- 找到聊天壁纸视图后直接渲染该壁纸分支到共享纹理，不再依赖隐藏整棵窗口兄弟视图树。
- 显式记录 `backdropRectInWindow`、图片 content mode 和实际裁剪区域，向 shader 传入窗口坐标到背景纹理坐标的 UV 变换矩阵。
- 覆盖 `aspectFill`、导航栏/安全区偏移、横竖屏和窗口 transform；无法识别独立壁纸源时保留当前窗口捕获安全回退。

### 0.9.0：单 Metal surface 批量渲染

- 将每气泡一个 `CAMetalLayer` 收敛为聊天页面一个共享 Metal surface。
- 单个 drawable、单个 render pass 中使用 instance buffer 和 SDF atlas 渲染所有可见气泡。
- 共享层必须位于壁纸之上、文字和头像之下，只在气泡 SDF 区域输出，不能覆盖非气泡 UI。
- 该阶段属于高风险结构调整，必须在 0.7.3 和 0.8.x 真机稳定后单独实施。

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
