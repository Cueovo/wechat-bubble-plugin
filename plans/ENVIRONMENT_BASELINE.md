# 环境基线记录

- 检查日期：2026-08-03
- 对应阶段：[阶段 00：环境与基线](./00-environment-baseline.md)
- 当前状态：原生 RootHide 0.0.2 已通过 CI；等待无需 Convert 安装并读取微信 build、主可执行文件和气泡候选类诊断

## 真机基线

| 项目 | 当前值 | 状态 |
|---|---|---|
| 设备 | iPhone 14 Pro Max（iPhone15,3，A16） | 已确认 |
| 设备 ABI | arm64e | 已确认 |
| iOS | 16.5 | 已确认 |
| 越狱 | Dopamine 2.4.9 RootHide | 已确认 |
| Tweak Loader | ElleKit 1.2 | 已确认 |
| 微信 | 8.0.60 (`CFBundleVersion` `8.0.60.35`) | 0.0.2 诊断已确认 |
| Bundle ID | `com.tencent.xin` | 0.0.2 诊断已确认 |
| 主可执行文件 | `WeChat` | 0.0.2 诊断已确认 |
| Artifact 安装 | Sileo/Filza 手工安装 | 0.0.1 经 RootHide Patcher Convert 后安装成功；原生包待验证 |

## GitHub/CI 基线

| 项目 | 当前值 | 状态 |
|---|---|---|
| Remote | `https://github.com/Cueovo/wechat-bubble-plugin` | `main` 已推送 |
| 可见性 | 公开 | 已确认 |
| Package ID | `com.bi8bo.wechat.bubble` | 已确认 |
| Runner | `macos-15` | 原生 RootHide Run 5 已通过 |
| RootHide Theos | `88506b2c22e9e07dd4ed055f23c9e398a117a2c7` | Run 5 验证通过 |
| 已验证旧 Artifact | `wechat-bubble-rootless-7dfe77e3a2b261fc3507e3cb200591309b7f0114` | 0.0.1，需 Convert，不作为后续发布包 |
| 原生 RootHide Artifact | `wechat-bubble-roothide-532012e25446abfe4c97b3a3abed65104f9a03bc` | 0.0.2，8,056 bytes，待真机安装 |
| RootHide Artifact digest | `sha256:3be70a96e8d1db534cc9796943fc3f68955c45e9410dec8f6034cda7590fa68b` | GitHub artifact digest |
| RootHide Artifact 到期 | 2026-08-16 18:04:28 UTC | 14 天保留策略 |
| 旧 Artifact digest | `sha256:66483f14d19d8da5fa19dfb8612579672e8ff8b86cdf7720e6a5048bc70c3ef3` | 仅保留历史记录 |

## Windows 主机检查

| 项目 | 结果 |
|---|---|
| Git | 已安装：`D:\Git\cmd\git.exe` |
| Windows OpenSSH | 已安装：`C:\Windows\System32\OpenSSH\ssh.exe` |
| `wsl.exe` | 文件存在，但 `wsl --status`、`wsl --list --verbose` 和 `wsl --version` 均失败 |
| 可用 WSL Linux 发行版 | 未发现 |
| Make | 未发现 |
| Clang | 未发现 |
| ldid | 未发现 |
| dpkg-deb | 未发现 |
| Perl | 未发现 |
| Theos | 常见路径和 `THEOS` 环境变量中未发现 |

## 构建环境决策

当前 Windows 主机不承担 Theos 编译。阶段 00 已选择 GitHub Actions macOS runner：

1. Windows 主机仅用于编辑、Git 操作和静态检查。
2. GitHub Actions 负责安装固定 revision 的 `roothide/theos`、编译和生成原生 RootHide `.deb` artifact。
3. 工作流记录 runner、Xcode、SDK、Clang、ldid、dpkg 和 `roothide/theos` revision。
4. CI 不保存测试机 IP、SSH 密码或私钥；artifact 由用户人工安装到设备。
5. 普通 rootless 构建链已验证，但实际目标已切换到无需设备端 Convert 的原生 RootHide 构建。

## 阶段 00 待完成

- [x] 确认 GitHub Actions macOS runner 构建路线。
- [x] 建立本地 Git 和 GitHub remote；`main` 已推送。
- [x] 创建 CI 并锁定 Theos commit。
- [x] 提交并 push 后完成首次 GitHub Actions 运行。
- [ ] 从 artifact 的 `build-manifest.txt` 抄录 runner 的 iOS SDK、Xcode、Clang、ldid 和 dpkg 精确版本。
- [x] 记录 Dopamine 2.4.9 RootHide。
- [x] 记录 ElleKit 1.2。
- [x] 确认 artifact 采用 Sileo/Filza 手工安装。
- [x] 完成普通 rootless 0.0.1 经 Convert 后的首次安装和微信启动验证。
- [ ] 完成原生 RootHide 0.0.2 无需 Convert 的安装和卸载验证。
- [x] 确认微信 Bundle ID 为 `com.tencent.xin`。
- [x] 确认微信 `CFBundleVersion` 为 `8.0.60.35`、主可执行文件为 `WeChat`。
- [x] 由 CI 构建并上传普通 rootless 0.0.1 基线 artifact。
- [x] 由 CI 构建并上传原生 RootHide 0.0.2 诊断 artifact。
- [ ] 下载、无需 Convert 安装并卸载原生 RootHide 测试包。
