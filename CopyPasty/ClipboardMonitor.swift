//
//  ClipboardMonitor.swift
//  CopyPasty
//
//  Created by 邓家炜 on 2024/06/10.
//

import Foundation
import AppKit

/// 剪贴板监听器
class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private weak var history: ClipboardHistory?

    /// 初始化
    init(history: ClipboardHistory) {
        self.history = history
    }

    /// 开始监听剪贴板
    func startMonitoring() {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    /// 停止监听
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// 同步 changeCount（本应用自己回写剪贴板后调用，避免把自己复制的内容再次记录）
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// 检查剪贴板内容
    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // 网页链接也是 NSURL，先按 file:// 与 http(s) 分流，避免网址被误记成文件
        let pasteboardURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL]) ?? []
        let fileURLs = pasteboardURLs.filter { $0.isFileURL }

        if !fileURLs.isEmpty {
            var thumbnailData: Data? = nil
            var displayName = ""
            var itemType: ClipboardItem.ClipboardType = .file
            var totalFileSize: Int64? = nil

            if fileURLs.count == 1, let fileURL = fileURLs.first {
                displayName = fileURL.lastPathComponent
                let fileExtension = fileURL.pathExtension.lowercased()
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp"]
                if imageExtensions.contains(fileExtension), let image = NSImage(contentsOf: fileURL) {
                    thumbnailData = generateThumbnailData(from: image)
                    itemType = .image
                }
                // 获取文件大小
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 {
                    totalFileSize = fileSize
                }
            } else {
                displayName = fileURLs.map { $0.lastPathComponent }.joined(separator: ", ")
                // 计算总文件大小
                var size: Int64 = 0
                for fileURL in fileURLs {
                    if let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 {
                        size += fileSize
                    }
                }
                if size > 0 {
                    totalFileSize = size
                }
            }

            let filePaths = fileURLs.map { $0.path }.joined(separator: "\n")
            DispatchQueue.main.async { [weak self] in
                self?.history?.addItem(filePaths, type: itemType, thumbnailData: thumbnailData, displayName: displayName, fileSize: totalFileSize)
            }
        } else if let webURL = pasteboardURLs.first(where: { Self.isWebURL($0) }) {
            DispatchQueue.main.async { [weak self] in
                self?.history?.addItem(webURL.absoluteString, type: .url)
            }
        } else if let image = NSImage(pasteboard: pasteboard) {
            // 直接复制的图片数据（没有文件名）；content 用唯一值，避免不同图片按内容互相去重覆盖
            let thumbnailData = generateThumbnailData(from: image)
            let imageData = image.tiffRepresentation
            DispatchQueue.main.async { [weak self] in
                self?.history?.addItem(UUID().uuidString, type: .image, thumbnailData: thumbnailData, imageData: imageData, displayName: "图片")
            }
        } else if let string = pasteboard.string(forType: .string) {
            DispatchQueue.main.async { [weak self] in
                self?.history?.addItem(string, type: Self.clipboardType(for: string))
            }
        }
    }

    /// 判断是否为网页链接
    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return ["http", "https"].contains(scheme)
    }

    /// 识别文本类型：合法的 http/https 链接记为 url，其余记为文本
    private static func clipboardType(for string: String) -> ClipboardItem.ClipboardType {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), isWebURL(url) {
            return .url
        }
        return .text
    }

    /// 生成缩略图数据
    private func generateThumbnailData(from image: NSImage) -> Data? {
        let maxSize: CGFloat = 60
        guard image.size.width > 0, image.size.height > 0 else { return image.tiffRepresentation }
        let aspectRatio = image.size.width / image.size.height
        var newSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        if newSize.height > maxSize {
            newSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resizedImage.unlockFocus()

        return resizedImage.tiffRepresentation
    }
}
