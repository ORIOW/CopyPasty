# CopyPasty

[English](README_EN.md) | 简体中文

你的轻量 macOS 剪贴板历史工具，常驻菜单栏，随时找回刚拷贝过的内容。

![平台](https://img.shields.io/badge/platform-macOS%2026+-lightgrey) ![框架](https://img.shields.io/badge/framework-SwiftUI%20%2B%20AppKit-blue) ![依赖](https://img.shields.io/badge/dependencies-none-success)

## 功能

### 剪贴板历史
- 常驻菜单栏，自动记录拷贝的**文本、链接、图片、文件**
- 最多保留 20 条，点击即复制回剪贴板，右键删除，支持一键清空
- 面板高度随内容自适应，超出部分滚动；深浅色自动跟随系统

### 媒体预览
- **图片**：缩略图显示，点击复制原图
- **音频**（mp3 / wav / m4a / aac / flac / aiff / caf）：显示整条波形图 + 文件名
- **视频**（mp4 / mov / m4v / avi / mkv / webm 等）：显示视频帧缩略图 + 播放按键

### 敏感信息保护
- 自动识别**密码、API 密钥、银行卡号**（含 `KEY=sk-xxx` 配置行、JWT、长十六进制、高熵随机串等形态）
- 命中的记录**自动打码**，原文以 **AES-GCM 加密**存储，密钥保存在系统钥匙串
- 记录末尾问号按钮确认后可取消打码，🔒 按钮可恢复打码
- 设置页可整体开关加密，切换时存量记录同步处理
- 点击打码记录仍可正常复制原文

### 其他
- 开机自启动（系统设置内管理）、退出时清空历史、应用内重启
- 首次启动引导页（可在设置中重新查看）

## 安装

从 [Releases](https://github.com/ORIOW/CopyPasty/releases) 下载最新 DMG，打开后将 CopyPasty 拖入 Applications。

**首次打开**：若提示"无法验证开发者"，右键点击 App → 打开（或在 系统设置 → 隐私与安全性 中点"仍要打开"）。本应用未做公证（无 Apple Developer Program），属正常现象，放行一次即可。

**钥匙串授权**：开启敏感内容加密后，首次加密时 macOS 可能弹出 1–2 次钥匙串授权框，点击「始终允许」即可。

## 隐私

- **所有数据仅存本机**：历史记录在本机偏好设置，图片/波形图在本机应用目录，加密密钥在本机钥匙串
- **零网络访问**：应用完全离线运行
- 钥匙串授权仅涉及 CopyPasty 自行创建的那一条加密密钥条目，不会访问钥匙串中的其他任何内容

## 从源码构建

要求：macOS 26+、Xcode（含 macOS 26 SDK）。

```bash
git clone https://github.com/ORIOW/CopyPasty.git
open CopyPasty.xcodeproj   # Xcode 中 Cmd+R 运行
```

打包 DMG（自动读取工程版本号，产物输出到 `build/`）：

```bash
./Scripts/make_dmg.sh
```

技术栈：SwiftUI + AppKit + AVFoundation + CryptoKit，**无任何第三方依赖**。

## 项目结构

```
CopyPasty/
├── CopyPastyApp.swift      # 应用入口与生命周期
├── ClipboardMonitor.swift  # 剪贴板监听（轮询 changeCount）、媒体预览生成
├── ClipboardHistory.swift  # 数据模型、历史管理、图片磁盘存储
├── SensitiveDetector.swift # 敏感信息检测器 + AES-GCM 加密器
├── StatusBarManager.swift  # 菜单栏交互、历史/设置/关于界面
└── OnboardingView.swift    # 首次启动引导页
```

## 版本历史

见 [CHANGELOG.md](CHANGELOG.md)。版本号规则：`主.子.阶段.YYMMDD_阶段名`。
