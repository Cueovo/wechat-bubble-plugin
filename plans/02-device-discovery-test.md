# 阶段 01/02 真机诊断记录

## 构建目标

- Package ID：`com.bi8bo.wechat.bubble`
- 版本：`0.0.2`
- 环境：Dopamine 2.4.9 RootHide / ElleKit 1.2
- Package scheme：`roothide`
- Debian architecture：`iphoneos-arm64e`
- 微信：8.0.60

## 安装验证

1. 从 GitHub Actions 下载名称以 `wechat-bubble-roothide-` 开头的 artifact。
2. 解压并核对其中的 `SHA256SUMS`。
3. 使用 Sileo/Filza 直接安装 `packages` 目录中的 `.deb`。
4. 若再次出现 RootHide Patcher 的 Convert 提示，取消安装并记录包名，不执行 Convert。
5. 完全结束微信进程后重新打开微信，不需要重启 SpringBoard。
6. 验证冷启动、前后台切换、聊天列表和测试会话均无闪退。

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

- `pluginVersion`：应为 `0.0.2`。
- `buildStage`：应为 `bubble-discovery`。
- `process.isWeChatMainProcess`：应为 `true`。
- `process.bundleIdentifier`：应为 `com.tencent.xin`。
- `process.bundleExecutable`：记录微信主可执行文件名。
- `versionGate.shortVersion`：应为 `8.0.60`。
- `versionGate.buildVersion`：记录精确 `CFBundleVersion`。
- `versionGate.support`：当前应为 `candidate`。
- `versionGate.uiModificationAllowed`：必须为 `false`。
- `discovery.candidateClasses`：记录四个窄候选类是否存在及筛选后的生命周期方法名。
- `discovery.hookInstalled`：必须为 `false`。
- `discovery.viewTreeScanned`：必须为 `false`。

诊断不包含消息正文、会话名称、联系人、账号、头像、媒体路径、消息模型或完整视图树。反馈结果时只需提供 `process`、`versionGate` 和 `discovery.candidateClasses`。

## 验收表

| 项目 | 结果 | 备注 |
|---|---|---|
| Sileo 无 Convert 提示 | 待验证 | |
| 原生 RootHide 包安装 | 待验证 | |
| 微信冷启动 | 待验证 | |
| 前后台切换 | 待验证 | |
| `diagnostics.plist` 生成 | 待验证 | |
| 主可执行文件 | 待诊断 | |
| `CFBundleVersion` | 待诊断 | |
| 候选类快照 | 待诊断 | |
| 卸载后微信正常 | 待验证 | |

## 回退

若微信无法启动，先在 Sileo 中卸载 `com.bi8bo.wechat.bubble`，再彻底结束微信并重新打开。不要尝试 Convert、Patch 或安装普通 rootless 旧包来覆盖原生 RootHide 包。
