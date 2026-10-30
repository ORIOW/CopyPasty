//
//  OnboardingView.swift
//  CopyPasty
//
//  Created by 邓家炜 on 2026/06/13.
//

import SwiftUI

/// 首次打开引导页
struct OnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerView
            featuresView
            Divider()
            footerView
        }
        .padding(32)
        .frame(width: 520)
    }

    /// 头部介绍
    private var headerView: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "heart.text.clipboard.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 8) {
                Text("欢迎使用 CopyPasty")
                    .font(.system(size: 28, weight: .bold))

                Text("你的轻量剪贴板历史工具，常驻菜单栏，随时找回刚拷贝过的内容。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 功能说明
    private var featuresView: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingFeatureRow(
                icon: "doc.on.clipboard",
                title: "自动记录拷贝的内容",
                description: "拷贝文本、链接、图片或文件后，CopyPasty 会自动保存最近记录。"
            )

            OnboardingFeatureRow(
                icon: "menubar.rectangle",
                title: "从菜单栏快速取回",
                description: "点击屏幕顶部菜单栏中的 CopyPasty 图标，选择一条历史记录即可重新拷贝。"
            )

            OnboardingFeatureRow(
                icon: "lock.shield",
                title: "安全可控",
                description: "你可以随时清空历史，也可以在设置中开启退出时自动清除。"
            )
        }
    }

    /// 底部提示和操作
    private var footerView: some View {
        HStack(alignment: .center, spacing: 20) {
            Text("CopyPasty 已在菜单栏运行。之后可以通过菜单栏图标打开历史、设置和关于窗口。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("开始使用") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

/// 引导页功能说明行
struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
