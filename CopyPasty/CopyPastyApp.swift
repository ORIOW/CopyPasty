//
//  CopyPastyApp.swift
//  CopyPasty
//
//  Created by 邓家炜 on 2026/6/10.
//

import SwiftUI
import AppKit

/// CopyPasty 主应用入口
@main
struct CopyPastyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    private var history: ClipboardHistory!
    private var monitor: ClipboardMonitor!
    private var statusBarManager: StatusBarManager!
    @AppStorage("clearOnExit") private var clearOnExit = false

    /// 应用启动完成
    func applicationDidFinishLaunching(_ notification: Notification) {
        history = ClipboardHistory()
        monitor = ClipboardMonitor(history: history)
        statusBarManager = StatusBarManager(history: history)
        history.onPasteboardWrite = { [weak monitor] in
            monitor?.syncChangeCount()
        }

        monitor.startMonitoring()

        NSApp.setActivationPolicy(.accessory)
        statusBarManager.showOnboardingIfNeeded()
    }

    /// 应用即将终止
    func applicationWillTerminate(_ notification: Notification) {
        if clearOnExit {
            history.clearAll()
        }
        monitor.stopMonitoring()
    }
}
