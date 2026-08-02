# 阶段 00：环境与基线

## 目标

建立可复现的 Theos rootless 开发环境，并记录唯一首发真机的精确软件基线。本阶段不创建 Hook，不修改微信界面。

## 前置条件

- 代码托管在启用 GitHub Actions 的 GitHub 仓库。
- 发布构建使用 GitHub Actions macOS runner；Windows 主机只负责编辑和静态检查。
- iPhone 14 Pro Max 已运行 iOS 16.5、Dopamine 2.4.9 rootless 和 ElleKit 1.2。
- 测试微信为 8.0.60。
- 使用专用测试账号和可恢复的设备备份。

## 待确认记录

在实施记录中填写，不把设备地址或凭据提交到仓库：

- Dopamine 2.4.9 的安装方式。
- Sileo/Zebra 精确版本。
- OpenSSH/设备连接方式是否可用。
- 微信 `CFBundleIdentifier`、`CFBundleShortVersionString`、build number 和主可执行文件名。
- 当前 Theos commit、iOS SDK、Clang、ldid 和 dpkg 版本。
- 发布构建使用的 Xcode/SDK 版本。

## 技术参数

- `TARGET`：iPhone clang，最低部署 iOS 15.0。
- 源码架构：`arm64`。
- Package scheme：`rootless`。
- Debian architecture：`iphoneos-arm64`。
- Package ID：`com.bi8bo.wechat.bubble`。
- GitHub remote：`https://github.com/Cueovo/wechat-bubble-plugin`。
- 目标进程：只允许微信主 Bundle/主可执行文件，精确值以真机记录为准。

这里的 `arm64` 是微信 App dylib 的目标 ABI；设备和系统支持 arm64e，不代表本项目需要 Hook arm64e 系统进程。

## 实施步骤

1. 建立 GitHub 仓库并启用 GitHub Actions。
2. 使用固定 macOS runner 基线，记录预装 Xcode、iOS SDK、Clang、ldid 和 dpkg 版本。
3. 在工作流中安装并锁定 Theos commit，不从漂移的分支生成发布包。
4. 使用 runner 自带的 iOS 15+ SDK 能力验证 Objective-C ARC 编译链。
5. 确认 `dpkg-deb`/Theos 能生成 rootless 包并上传 CI artifact。
6. 建立从 CI artifact 到测试机的人工安装通道，不把设备 IP、密码或私钥放入 GitHub Secrets 或仓库。
7. 从微信“关于微信”和只读 Bundle 元数据记录 8.0.60 的精确 build。
8. 记录 Sileo/Zebra 版本和 Dopamine 2.4.9 的安装方式。
9. 创建测试记录，后续每个安装包都引用源码 revision、CI run 和 artifact 哈希。

## 验证清单

- [ ] Theos 能编译一个不注入微信的最小 Objective-C 动态库。
- [ ] 能生成 `iphoneos-arm64` 的 rootless `.deb`。
- [ ] 能检查包内路径位于 rootless 前缀，没有错误硬编码 rootful 路径。
- [ ] 能将测试包安装到设备并正常卸载。
- [ ] 微信在未安装功能 Hook 时正常启动、登录、收发消息。
- [ ] 精确环境版本已记录，仓库中不存在设备凭据或微信私有数据。

## 产物

- 锁定的工具链决策。
- 真机环境基线记录模板。
- 已验证的 rootless 打包与安装通道。

## 退出门槛

只有在“CI 构建、artifact 下载、安装、卸载、微信正常启动”五项都通过后，才进入阶段 01。GitHub Actions 发布工作流必须固定 Theos revision并记录 runner/Xcode 版本，不通过降低签名或安全配置解决构建失败。
