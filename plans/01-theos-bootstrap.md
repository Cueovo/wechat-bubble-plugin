# 阶段 01：Theos 骨架与安全注入

## 目标

建立最小原生 RootHide Tweak：能够被加载进微信 8.0.60 主进程，但不 Hook 消息视图、不改变任何 UI。

## 前置条件

- 阶段 00 已通过。
- 微信 Bundle ID 和主可执行文件名已真机确认。
- RootHide 包安装、卸载和结束微信进程的流程可用。

## 计划结构

```text
Makefile
control
<PackageFilter>.plist
Sources/
  Bootstrap/
    ProcessGuard
    VersionGate
    CapabilityRegistry
  TweakEntry
Resources/
Tests/
```

实际名称在实施时统一确定；MVP 发布后不随意更换 package identifier。

## 实施步骤

1. 创建 Theos Tweak 项目和原生 RootHide 包元数据。
2. Filter 只匹配微信主 Bundle；入口再次校验主可执行文件，形成双重进程守卫。
3. 开启 ARC，只链接 MVP 必需的 Foundation/UIKit。
4. 入口只完成一次性、延迟的 Bootstrap，不在 dylib 构造阶段遍历视图树。
5. 加入微信版本读取；仅识别 8.0.60，其他版本返回 `Unknown`。
6. 加入最小 CapabilityRegistry 框架，但本阶段不探测或 Hook 气泡类。
7. Debug 构建只记录“插件版本、微信版本、入口是否完成”等无内容信息。
8. 安装后只彻底结束并重启微信，不重启 SpringBoard。

## 验证清单

- [ ] 包架构为 `iphoneos-arm64e`，由 `roothide/theos` 使用 `roothide` scheme 生成。
- [ ] dylib 仅加载到微信主进程，不加载到 SpringBoard、扩展或其他 App。
- [ ] 微信 8.0.60 冷启动、热启动、后台恢复均正常。
- [ ] 插件入口重复通知不会重复初始化。
- [ ] 未产生 UI、网络、数据库或消息相关行为。
- [ ] 卸载后微信恢复到完全未注入状态。
- [ ] Release 构建不输出敏感或高频日志。

## 故障回退

- 启动异常时先通过包管理器卸载 Tweak，再结束微信并重启。
- 若 Filter 过宽，先修正 Filter 和 ProcessGuard，不添加崩溃捕获掩盖问题。
- 若版本读取失败，保持 `Unknown` 且不执行后续能力逻辑。

## 产物

- 可安装且无需 RootHide Patcher 转换的原生 RootHide `.deb`。
- Bootstrap、ProcessGuard、VersionGate 和 CapabilityRegistry 骨架。
- 一份阶段 01 真机验证记录。

## 退出门槛

连续完成多次冷启动、前后台切换、安装和卸载，微信行为与未安装插件一致，才进入阶段 02。
