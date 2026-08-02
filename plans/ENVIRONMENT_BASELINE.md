# 环境基线记录

- 检查日期：2026-08-03
- 对应阶段：[阶段 00：环境与基线](./00-environment-baseline.md)
- 当前状态：进行中，本地骨架已就绪；用户选择暂不 push，首次 GitHub Actions 运行延期

## 真机基线

| 项目 | 当前值 | 状态 |
|---|---|---|
| 设备 | iPhone 14 Pro Max（iPhone15,3，A16） | 已确认 |
| 设备 ABI | arm64e | 已确认 |
| iOS | 16.5 | 已确认 |
| 越狱 | Dopamine 2.4.9 rootless | 已确认 |
| Tweak Loader | ElleKit 1.2 | 已确认 |
| 微信 | 8.0.60 | 已确认，`CFBundleVersion` 待真机读取 |
| Bundle ID | `com.tencent.xin` | 用户已提供 |
| 主可执行文件 | 未确认 | 待真机确认 |
| Artifact 安装 | Sileo/Filza 手工安装 | 路线已确认，待首次真机验证 |

## GitHub/CI 基线

| 项目 | 当前值 | 状态 |
|---|---|---|
| Remote | `https://github.com/Cueovo/wechat-bubble-plugin` | 已关联，远程为空 |
| 可见性 | 公开 | 已确认 |
| Package ID | `com.bi8bo.wechat.bubble` | 已确认 |
| Runner | `macos-15` | 已写入工作流，待首次运行验证 |
| Theos | `16362d3aa83a0acd56df4493d575d34306d42478` | 已固定，待 CI 验证 |
| Artifact | rootless `.deb` + SHA-256 + 工具链/包清单 | 已配置，待 CI 验证 |

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
2. GitHub Actions 负责安装固定 revision 的 Theos、编译和生成 rootless `.deb` artifact。
3. 工作流记录 runner、Xcode、SDK、Clang、ldid、dpkg 和 Theos revision。
4. CI 不保存测试机 IP、SSH 密码或私钥；artifact 由用户人工安装到设备。
5. 本地 Git 和空 GitHub remote 已建立；用户当前选择暂不 push，因此工作流尚未运行。

## 阶段 00 待完成

- [x] 确认 GitHub Actions macOS runner 构建路线。
- [x] 建立本地 Git 和 GitHub remote；远程仓库为空。
- [x] 创建 CI 并锁定 Theos commit。
- [ ] 提交并 push 后完成首次 GitHub Actions 运行；用户当前选择暂不 push。
- [ ] 记录 runner 的 iOS SDK、Xcode、Clang、ldid 和 dpkg。
- [x] 记录 Dopamine 2.4.9。
- [x] 记录 ElleKit 1.2。
- [x] 确认 artifact 采用 Sileo/Filza 手工安装。
- [ ] 完成首次 artifact 真机安装和卸载。
- [x] 确认微信 Bundle ID 为 `com.tencent.xin`。
- [ ] 确认微信 `CFBundleVersion` 和主可执行文件。
- [ ] 由 CI 构建并上传无 Hook 的最小测试包 artifact。
- [ ] 下载、安装并卸载最小测试包。
