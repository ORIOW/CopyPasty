//
//  StatusBarManager.swift
//  CopyPasty
//
//  Created by 邓家炜 on 2024/06/10.
//

import SwiftUI
import AppKit
import ServiceManagement

/// 菜单栏管理器
class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private let history: ClipboardHistory
    private let onboardingSeenKey = "com.CopyPasty.hasSeenOnboarding"

    /// 初始化
    init(history: ClipboardHistory) {
        self.history = history
        super.init()
        setupPopover()
        setupStatusBar()
        setupEventMonitor()
    }

    /// 设置弹出框（hosting 控制器把 SwiftUI 内容的理想尺寸同步给 Popover，实现高度自适应）
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(
            rootView: HistoryView(
                history: history,
                onSelect: { [weak self] in
                    self?.popover.close()
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onOpenAbout: { [weak self] in
                    self?.openAbout()
                }
            )
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    /// 设置菜单栏图标
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "heart.text.clipboard.fill", accessibilityDescription: "CopyPasty")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    /// 设置点击外部关闭的监听器
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    /// 切换弹出框显示/隐藏
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// 需要时显示首次引导页
    func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: onboardingSeenKey) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.openOnboarding()
        }
    }

    /// 创建按 SwiftUI 内容自适应大小的窗口（避免手动 layoutSubtreeIfNeeded 与 NSHostingView 布局重入）
    private func makeWindow<Content: View>(title: String, styleMask: NSWindow.StyleMask, @ViewBuilder rootView: () -> Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView()))
        window.styleMask = styleMask
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// 打开首次引导页
    private func openOnboarding() {
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(title: "欢迎使用 CopyPasty", styleMask: [.titled, .closable]) {
            OnboardingView { [weak self] in
                self?.markOnboardingAsSeen()
                self?.onboardingWindow?.close()
            }
        }

        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 标记首次引导页已显示
    private func markOnboardingAsSeen() {
        UserDefaults.standard.set(true, forKey: onboardingSeenKey)
    }

    /// 打开设置窗口
    private func openSettings() {
        popover.close()

        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(title: "CopyPasty 设置", styleMask: [.titled, .closable, .miniaturizable]) {
            SettingsView(
                history: history,
                onOpenOnboarding: { [weak self] in
                    self?.openOnboarding()
                }
            )
        }

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 打开关于窗口
    private func openAbout() {
        popover.close()

        if let existingWindow = aboutWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(title: "关于", styleMask: [.titled, .closable, .miniaturizable]) {
            AboutView()
        }

        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// 窗口代理
extension StatusBarManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window === settingsWindow {
                settingsWindow = nil
            } else if window === aboutWindow {
                aboutWindow = nil
            } else if window === onboardingWindow {
                markOnboardingAsSeen()
                onboardingWindow = nil
            }
        }
    }
}

/// 设置窗口视图
struct SettingsView: View {
    @ObservedObject var history: ClipboardHistory
    let onOpenOnboarding: () -> Void
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("clearOnExit") private var clearOnExit = false
    @AppStorage("encryptSensitive") private var encryptSensitive = true
    @State private var isRestartButtonPressed = false
    @State private var loginItemNeedsApproval = false
    @State private var loginItemError: String?
    @State private var isSyncingLoginItem = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("如何使用")
                    .multilineTextAlignment(.leading)
                Spacer()
                Button(action: {
                    onOpenOnboarding()
                }) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $encryptSensitive) {
                    HStack {
                        Text("敏感内容加密")
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: encryptSensitive) { _, newValue in
                    // 切换时对存量记录同步生效，保持列表状态与设置一致
                    if newValue {
                        history.encryptAll()
                    } else {
                        history.decryptAll()
                    }
                }
                Text("开启后，检测为密码、密钥、银行卡号的拷贝记录会自动打码，原文用 AES-GCM 加密后存储，加解密密钥保存在系统钥匙串中；点击记录仍可正常复制，也可用记录末尾的按钮打码/取消打码。关闭后按原文存储，现有已打码记录也会恢复明文。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("🔐 首次加密时 macOS 可能弹出 1–2 次钥匙串授权框（读取与写入各一次），点击「始终允许」后同一构建不再出现，App 更新后可能再次询问。该授权仅针对 CopyPasty 自行创建的那一条加密密钥条目，不会访问你钥匙串中的其他任何内容。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $clearOnExit) {
                HStack {
                    Text("退出时清除剪贴板历史")
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $launchAtLogin) {
                HStack {
                    Text("开机自启动")
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .onChange(of: launchAtLogin) { _, newValue in
                // onAppear 按系统实际状态纠正开关时不触发注册/注销
                guard !isSyncingLoginItem else { return }
                setLoginItemEnabled(newValue)
            }
            .onAppear {
                syncLoginItemState()
            }
            if let loginItemError {
                Text(loginItemError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if loginItemNeedsApproval {
                Text("需要在 系统设置 → 通用 → 登录项 中允许 CopyPasty 后才会生效。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("重启CopyPasty") {
                restartApp()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(isRestartButtonPressed ? .red : .accentColor)
            .onLongPressGesture(minimumDuration: .infinity) {
            } onPressingChanged: { isPressed in
                isRestartButtonPressed = isPressed
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    /// 以系统登录项的实际注册状态为准纠正开关显示，避免与用户在系统设置中的手动操作脱节
    private func syncLoginItemState() {
        let status = SMAppService.mainApp.status
        let shouldEnable = (status == .enabled || status == .requiresApproval)
        loginItemNeedsApproval = (status == .requiresApproval)
        guard launchAtLogin != shouldEnable else { return }
        isSyncingLoginItem = true
        launchAtLogin = shouldEnable
        // onChange 在下一轮视图更新后才触发，需等它处理完再解除保护
        DispatchQueue.main.async { self.isSyncingLoginItem = false }
    }

    /// 设置开机自启动
    private func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
            loginItemNeedsApproval = (SMAppService.mainApp.status == .requiresApproval)
        } catch {
            // 注册失败时以系统实际状态回拨开关，避免显示与实际不符
            loginItemError = "设置失败：\(error.localizedDescription)"
            NSLog("CopyPasty: 登录项设置失败 %@", String(describing: error))
            syncLoginItemState()
        }
    }

    /// 重启应用
    private func restartApp() {
        if clearOnExit {
            history.clearAll()
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.terminate(nil)
        }
    }
}

/// 关于窗口视图
struct AboutView: View {
    /// 版本号来自工程配置（MARKETING_VERSION / CURRENT_PROJECT_VERSION），避免手写不同步
    static let versionText: String = {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? marketing : "\(marketing) (\(build))"
    }()

    var body: some View {
        HStack(spacing: 30) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .cornerRadius(20)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("CopyPasty")
                    .font(.system(size: 36, weight: .bold))

                Text("Developed by：家炜 邓")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Version \(Self.versionText)")
                        .font(.system(size: 10, weight: .semibold))
                    Text("✅ 敏感内容检测：自动打码 + AES-GCM 加密，可在设置中开关")
                        .font(.system(size: 10))
                    Text("✅ 音频波形图 / 视频缩略图预览")
                        .font(.system(size: 10))
                    Text("✅ 深浅色自动跟随系统")
                        .font(.system(size: 10))
                    Text("🔐 首次加密可能弹出钥匙串授权（1–2 次），仅涉及 CopyPasty 自建的密钥条目，点「始终允许」即可")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(40)
        .frame(width: 550)
    }
}

/// 剪贴板历史主视图
struct HistoryView: View {
    @ObservedObject var history: ClipboardHistory
    let onSelect: () -> Void
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void
    @AppStorage("clearOnExit") private var clearOnExit = false

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if history.items.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    // 限制列表最大高度，超出部分滚动，避免面板超过屏幕
                    ScrollView(.vertical) {
                        listView
                    }
                    .frame(maxHeight: 480)
                    hintView
                }
            }

            footerView
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 头部视图
    private var headerView: some View {
        HStack {
            Image(systemName: "heart.text.clipboard.fill")
                .foregroundStyle(.blue)
            Text("CopyPasty")
                .font(.headline)
            Spacer()
            
            Button(action: {
                onOpenSettings()
            }) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                onOpenAbout()
            }) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 提示信息视图
    private var hintView: some View {
        let isFull = history.items.count >= ClipboardHistory.maxItems
        return Group {
            VStack(spacing: 2) {
                Text(isFull ? "放不下啦，继续拷贝来覆盖旧内容" : "鼠标单击来选取要粘贴的内容")
                    .fontWeight(.semibold)
                Text(isFull ? "或点击～清空～来清除所有内容" : "或继续拷贝吧～")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    /// 历史记录列表视图
    private var listView: some View {
        VStack(spacing: 1) {
            ForEach(history.items) { item in
                HistoryRowWrapper(item: item, onSelect: {
                    // 解密失败等复制不成功时保持面板打开，让用户看到没有复制成功
                    if history.copyToClipboard(item) {
                        onSelect()
                    }
                }, onDelete: {
                    history.removeItem(item)
                }, onUnmask: { target in
                    history.unmaskItem(target)
                }, onLock: {
                    history.reencryptItem(item)
                })
            }
        }
        .padding(.vertical, 4)
    }

    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有内容")
                .foregroundStyle(.secondary)
            Text("拷贝点东西～")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(height: 150)
    }

    /// 底部视图
    private var footerView: some View {
        HStack {
            Button("清空") {
                history.clearAll()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)

            Spacer()

            Button("退出CopyPasty") {
                if clearOnExit {
                    history.clearAll()
                }
                // 先关闭 Popover 并等动画结束再退出，避免 terminate 时 AppKit 关闭它自己创建的窗口产生警告
                onSelect()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 历史记录行包装器，处理点击交互
struct HistoryRowWrapper: View {
    let item: ClipboardItem
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onUnmask: (ClipboardItem) -> Bool
    let onLock: () -> Void
    @State private var isClicked = false
    @State private var showUnmaskConfirm = false
    @State private var unmaskFailed = false

    /// 视图主体
    var body: some View {
        Group {
            // 附加 isSensitive 条件：确认期间记录被批量解密/去重移除时自动退出确认态
            if showUnmaskConfirm && item.isSensitive {
                unmaskConfirmView
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            } else {
                HistoryRow(item: item, isClicked: isClicked, onQuestionMark: {
                    showUnmaskConfirm = true
                }, onLock: onLock)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isClicked = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isClicked = false
                        onSelect()
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// 取消打码确认（行内展开：外层面板本身是 Popover，嵌套弹窗会被系统自动关闭）
    private var unmaskConfirmView: some View {
        HStack(spacing: 10) {
            Text(unmaskFailed ? "无法解密（密钥可能已更换）" : "不是敏感信息？")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(unmaskFailed ? Color.red : Color.primary)
            Spacer()
            // 返回打码状态（解密失败时也保留，作为唯一退出途径）
            Button {
                showUnmaskConfirm = false
                unmaskFailed = false
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("返回")

            if !unmaskFailed {
                Button("取消打码") {
                    if onUnmask(item) {
                        showUnmaskConfirm = false
                    } else {
                        unmaskFailed = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
}

/// 单条历史记录行视图
struct HistoryRow: View {
    let item: ClipboardItem
    let isClicked: Bool
    var onQuestionMark: () -> Void = {}
    var onLock: () -> Void = {}

    /// 视图主体
    var body: some View {
        // 波形图只解码一次，供图片分支与 lineLimit 判断共用
        let waveform = item.waveformImage
        return HStack(alignment: .center, spacing: 10) {
            if item.isSensitive {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 20)
            } else if let waveform {
                // 音频文件：显示整条波形图
                Image(nsImage: waveform)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 36)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            } else if let image = item.thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(4)
                    // 描边避免白色/浅色图片在浅色模式行背景上隐形
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: iconForType(item.itemType))
                    .foregroundStyle(.blue)
                    .frame(width: 20)
            }

            Text(item.displayContent)
                .lineLimit(waveform != nil ? 1 : 2)
                .font(.system(size: 13))

            Spacer()

            Text(item.sizeOrTypeDisplay)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if item.isSensitive {
                Button(action: onQuestionMark) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("不是敏感信息？")
            } else if item.itemType == .text || item.itemType == .other {
                // 文本记录可手动恢复打码（与实时检测的类型范围一致）
                Button(action: onLock) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("打码此记录")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isClicked ? Color.blue.opacity(0.3) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    /// 根据类型获取图标
    private func iconForType(_ type: ClipboardItem.ClipboardType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        case .other: return "doc.text"
        }
    }
}
