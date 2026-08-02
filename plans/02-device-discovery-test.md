# 阶段 01/02 真机诊断记录

## 构建目标

- Package ID：`com.bi8bo.wechat.bubble`
- 版本：`0.0.3`
- 环境：Dopamine 2.4.9 RootHide / ElleKit 1.2
- Package scheme：`roothide`
- Debian architecture：`iphoneos-arm64e`
- 微信：8.0.60 (`CFBundleVersion` `8.0.60.35`)
- 主可执行文件：`WeChat`

## 安装验证

1. 从 GitHub Actions 下载最新名称以 `wechat-bubble-roothide-` 开头的 artifact。
2. 解压并核对其中的 `SHA256SUMS`。
3. 使用 Sileo/Filza 直接安装 `packages` 目录中的 `.deb`。
4. 若再次出现 RootHide Patcher 的 Convert 提示，取消安装并记录包名，不执行 Convert。
5. 完全结束微信进程后重新打开微信，不需要重启 SpringBoard。
6. 进入准备好的文字测试会话，连续显示并滚动经过发送/接收、单行/多行、Emoji、链接和群聊文字。
7. 第一条文字 Cell 完成布局后继续操作至少 8 秒，再读取诊断文件。
8. 验证前后台切换、聊天列表和测试会话均无闪退。

## 加载与发现结果

插件成功进入微信主进程后，会一次性写入：

```text
微信数据容器/Library/Caches/WeChatBubble/diagnostics.plist
```

可在 Filza 的应用管理器中进入微信数据目录，再打开：

```text
Library/Caches/WeChatBubble/diagnostics.plist
```

预期字段：

- `diagnosticsFormat`：应为 `2`。
- `pluginVersion`：应为 `0.0.3`。
- `buildStage`：应为 `bubble-discovery`。
- `process.isWeChatMainProcess`：应为 `true`。
- `process.bundleIdentifier`：应为 `com.tencent.xin`。
- `process.bundleExecutable`：应为 `WeChat`。
- `versionGate.shortVersion`：应为 `8.0.60`。
- `versionGate.buildVersion`：应为 `8.0.60.35`。
- `versionGate.support`：应为 `supported`。
- `versionGate.uiModificationAllowed`：必须为 `false`。
- `discovery.candidateClasses`：四个已验证候选类的能力记录。
- `discovery.hookInstalled`：应为 `true`。
- `discovery.recursiveViewTreeScanned`：必须为 `false`。
- `discovery.observation.mode`：应为 `TextMessageCellView.layoutContentView-post-original`。
- `discovery.observation.samples`：最多 16 个匿名、去重后的文字 Cell 局部几何样本。
- `discovery.observation.messageDataRead`、`textRead` 和 `recursiveViewTreeScanned`：必须全部为 `false`；`directSubviewsScanned` 应为 `true`。

诊断不包含消息正文、会话名称、联系人、账号、头像、媒体路径、消息模型或完整视图树。反馈结果时只需提供 `versionGate`、`discovery.hookInstalled` 和 `discovery.observation`。

## 验收表

| 项目 | 结果 | 备注 |
|---|---|---|
| Sileo 无 Convert 提示 | 待验证 | |
| 原生 RootHide 包安装 | 待验证 | |
| 微信冷启动 | 0.0.2 已通过；0.0.3 待验证 | |
| 前后台切换 | 待验证 | |
| `diagnostics.plist` 生成 | 0.0.2 已通过；0.0.3 待验证 | |
| 主可执行文件 | 已确认 | `WeChat` |
| `CFBundleVersion` | 已确认 | `8.0.60.35` |
| 候选类快照 | 已确认 | 四个候选类均存在 |
| 匿名布局观察样本 | 待诊断 | |
| 卸载后微信正常 | 待验证 | |

## 回退

若微信无法启动，先在 Sileo 中卸载 `com.bi8bo.wechat.bubble`，再彻底结束微信并重新打开。不要尝试 Convert、Patch 或安装普通 rootless 旧包来覆盖原生 RootHide 包。
