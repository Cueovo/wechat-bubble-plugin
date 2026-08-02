# 阶段 02：微信 8.0.60 气泡视图定位

## 目标

在不修改气泡外观的前提下，确认微信 8.0.60 文字消息 Cell、气泡视图和可用生命周期切入点，形成第一个版本适配器事实。

## 前置条件

- 阶段 01 已通过，最小 Tweak 可稳定注入。
- 真机环境仍为 iPhone 14 Pro Max / iOS 16.5 / Dopamine 2.4.9 RootHide / ElleKit 1.2 / 微信 8.0.60。
- 已准备包含单行、多行、Emoji、链接和群聊文字的测试会话。

## 候选而非契约

`CommonMessageCellView` 已在微信 8.0.60.35 真机确认存在，但它是多个消息视图的公共父类，不作为首选 Hook 面。`TextMessageCellView` 已确认继承自 `CommonMessageCellView`，并实现 `layoutContentView`、`getBgImageView` 和 `getRichTextView`，因此当前调查只观察 `TextMessageCellView.layoutContentView`。

## 实施步骤

1. CapabilityRegistry 已确认 `BaseChatCellView`、`ChatTableViewCell`、`CommonMessageCellView` 和 `TextMessageCellView` 均存在。
2. 已确认 `TextMessageCellView` 实现 `layoutContentView`，并提供 `getBgImageView`、`getRichTextView` 窄接口。
3. 临时 Debug 观察只 Hook `TextMessageCellView.layoutContentView`，先调用原实现，再采集匿名结构。
4. 只记录当前 Cell 的气泡背景、富文本视图和直接子视图特征：类名、尺寸、左右位置、可拉伸图片属性和 layer 特征。
5. 不记录 UILabel 文本、会话名称、头像内容、图片路径、消息模型或对象完整描述。
6. 比较发送/接收、单聊/群聊、单行/多行、复用滚动后的稳定特征。
7. 选出最窄切入点和气泡定位规则，并定义最低置信度。
8. 确认未支持消息类型能够被可靠排除。
9. 将临时广泛观察逻辑从 Release 路径删除，仅保留必要能力探测。

## 0.0.3 真机观察事实

- 精确环境：微信 `8.0.60.35`，主可执行文件 `WeChat`。
- `TextMessageCellView.layoutContentView` Hook 安装成功，观察窗口内触发 44 次，获得 16 个去重样本。
- `getBgImageView` 稳定返回可见的 `YYAsyncImageView`；`getRichTextView` 稳定返回 `RichTextView`。
- 单行样本中气泡高 40、文本高 20；多行样本中气泡高 60、文本高 40。
- 气泡宽度稳定约为文本宽度加 29，气泡高度稳定为文本高度加 20；文本在局部气泡坐标中约为 `x=12, y=10`。
- 气泡的 `UIImageView.image` 为 nil，未得到可用 `capInsets`，后续不能假设气泡由普通 `UIImage` 属性直接呈现。
- 气泡局部坐标的 `x` 接近 0，不能用于发送/接收判断；直接子视图 `MMHeadImageView` 的水平位置可区分左右，已观察到约 `x=9` 和 `x=375` 两组。
- 非文字消息不会进入 `TextMessageCellView` Hook；仍需用混合消息会话确认未命中和复用稳定性。

## 0.0.4 真机观察事实

- 精确环境仍为微信 `8.0.60.35`，观察窗口内触发 43 次布局，获得 24 个去重样本。
- 24 个样本均通过 `MMHeadImageView` 判定方向，其中接收方向 15 个、发送方向 9 个。
- 稳定头像几何为接收侧约 `x=9, y=2`、发送侧约 `x=375, y=2`；早期 `(0, 0)` 布局必须视为未知并失败关闭。
- `YYAsyncImageView` 的普通、动画和高亮图片 getter 均未提供气泡图像；`layer.contents` 随异步绘制由不存在变为存在。
- 样式层应覆盖异步 `layer.contents`，但不得清空微信图片状态、读取私有图片 ivar 或修改布局。
- 0.1.0 已从构建源列表移除 `WBBubbleDiscoveryHook`，Release 路径不再收集布局样本。

## 适配器记录

阶段完成时必须记录：

- 微信精确版本和 build。
- 候选宿主类和已验证方法签名。
- 原实现调用顺序。
- 发送/接收方向的 UI 结构判定。
- 文字气泡的组合识别条件。
- 明确排除的消息类型和失败条件。
- Cell 复用后是否需要重新定位。

## 验证清单

- [x] 能稳定识别发送文字气泡。
- [x] 能稳定识别接收文字气泡。
- [ ] 单聊和群聊方向判断一致。
- [ ] 单行、多行、Emoji、链接均能定位。
- [ ] 快速滚动和 Cell 复用后不串位。
- [ ] 图片、语音、视频、文件、位置、转账等被跳过。
- [x] 找不到类、方法、稳定方向或气泡时保持微信原样。
- [x] 日志中无聊天正文、账号、联系人或完整视图树。
- [x] Release 构建无临时探索 Hook。

## 产物

- `WeChat 8.0.60` 版本适配器设计记录。
- BubbleHookAdapter 与 BubbleLocator 的最小接口。
- 匿名化的能力诊断字段。

## 退出门槛

发送和接收文字气泡在全部测试场景中识别正确，非文字消息全部保持未命中，并且移除探索逻辑后微信仍稳定，才进入阶段 03。
