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
    @State private var isRestartButtonPressed = false

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
            .onChange(of: launchAtLogin) { oldValue, newValue in
                setLoginItemEnabled(newValue)
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

    /// 设置开机自启动
    private func setLoginItemEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update login item: \(error)")
            }
        } else {
            let jobDict = [
                "Label": "com.CopyPasty.launcher",
                "ProgramArguments": [Bundle.main.executablePath ?? ""],
                "RunAtLoad": enabled
            ] as [String: Any]

            if let plistPath = appSupportPlistPath() {
                (jobDict as NSDictionary).write(toFile: plistPath, atomically: true)
            }
        }
    }

    /// 获取启动项 plist 路径
    private func appSupportPlistPath() -> String? {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let launchAgentsDir = appSupportDir.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LaunchAgents")
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        return launchAgentsDir.appendingPathComponent("com.CopyPasty.launcher.plist").path
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
                    Text("🔧 修复网址被误识别为文件的问题")
                        .font(.system(size: 10))
                    Text("🔧 历史面板高度恢复随内容自适应")
                        .font(.system(size: 10))
                    Text("🔧 复制文件/图片记录时粘贴得到文件本身")
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
                    history.copyToClipboard(item)
                    onSelect()
                }, onDelete: {
                    history.removeItem(item)
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
    @State private var isClicked = false

    /// 视图主体
    var body: some View {
        HistoryRow(item: item, isClicked: isClicked)
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

/// 单条历史记录行视图
struct HistoryRow: View {
    let item: ClipboardItem
    let isClicked: Bool

    /// 视图主体
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let image = item.thumbnailImage {
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
                .lineLimit(2)
                .font(.system(size: 13))

            Spacer()

            Text(item.sizeOrTypeDisplay)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
