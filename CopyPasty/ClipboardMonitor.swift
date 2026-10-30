//
//  ClipboardMonitor.swift
//  CopyPasty
//
//  Created by 邓家炜 on 2024/06/10.
//

import Foundation
import AppKit
import AVFoundation

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
            var audioFileURL: URL? = nil

            if fileURLs.count == 1, let fileURL = fileURLs.first {
                displayName = fileURL.lastPathComponent
                let fileExtension = fileURL.pathExtension.lowercased()
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp"]
                if imageExtensions.contains(fileExtension), let image = NSImage(contentsOf: fileURL) {
                    thumbnailData = generateThumbnailData(from: image)
                    itemType = .image
                } else if Self.audioExtensions.contains(fileExtension) {
                    audioFileURL = fileURL
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
            if let audioFileURL {
                // 音频文件：后台解码生成波形图，完成后记录
                Self.loadWaveformData(for: audioFileURL) { [weak self] waveformData in
                    self?.history?.addItem(filePaths, type: itemType, waveformData: waveformData, displayName: displayName, fileSize: totalFileSize)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.history?.addItem(filePaths, type: itemType, thumbnailData: thumbnailData, displayName: displayName, fileSize: totalFileSize)
                }
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

    /// 支持生成波形图的音频扩展名
    static let audioExtensions = ["mp3", "wav", "aiff", "aif", "m4a", "aac", "flac", "caf"]

    /// 后台解码音频，均匀采样各区间峰值后回主线程绘制波形 PNG
    private static func loadWaveformData(for fileURL: URL, completion: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let peaks = computeWaveformPeaks(for: fileURL, bins: 80)
            DispatchQueue.main.async {
                guard let peaks else {
                    completion(nil)
                    return
                }
                completion(renderWaveformPNG(peaks: peaks, size: NSSize(width: 150, height: 36)))
            }
        }
    }

    /// 均匀采样 bins 个区间的峰值（每个区间只读一小段，避免长音频整文件解码）
    private static func computeWaveformPeaks(for fileURL: URL, bins: Int) -> [CGFloat]? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL),
              audioFile.length > 0 else { return nil }

        let totalFrames = audioFile.length
        let channelCount = min(audioFile.processingFormat.channelCount, 2)
        var peaks: [CGFloat] = []

        for bin in 0..<bins {
            let binStart = totalFrames * Int64(bin) / Int64(bins)
            let binEnd = max(binStart + 1, totalFrames * Int64(bin + 1) / Int64(bins))
            let readCount = min(binEnd - binStart, 4096)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(readCount)) else { return nil }
            audioFile.framePosition = binStart
            do {
                try audioFile.read(into: buffer, frameCount: AVAudioFrameCount(readCount))
            } catch {
                return peaks.isEmpty ? nil : peaks
            }
            guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else { continue }

            // 取前两个声道的最大绝对值作为该区间峰值
            var peak: Float = 0
            for channel in 0..<Int(min(channelCount, buffer.format.channelCount)) {
                let samples = channelData[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(samples[frame]))
                }
            }
            peaks.append(CGFloat(peak))
        }
        return peaks.isEmpty ? nil : peaks
    }

    /// 把峰值序列绘制成对称波形条 PNG
    private static func renderWaveformPNG(peaks: [CGFloat], size: NSSize) -> Data? {
        guard let maxPeak = peaks.max(), maxPeak > 0 else { return nil }

        let image = NSImage(size: size)
        image.lockFocus()

        // 固定蓝色在深浅色背景下都清晰
        NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.95, alpha: 1).setFill()
        let gap: CGFloat = 1.5
        let barWidth = max((size.width - gap * CGFloat(peaks.count - 1)) / CGFloat(peaks.count), 1)
        let drawableHeight = size.height - 4

        for (index, peak) in peaks.enumerated() {
            let normalized = peak / maxPeak
            let barHeight = max(drawableHeight * normalized, 1.5)
            let x = CGFloat(index) * (barWidth + gap)
            let y = (size.height - barHeight) / 2
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight), xRadius: 1, yRadius: 1).fill()
        }

        image.unlockFocus()
        return image.tiffRepresentation
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
