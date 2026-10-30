//
//  ClipboardHistory.swift
//  CopyPasty
//
//  Created by 邓家炜 on 2024/06/10.
//

import Foundation
import AppKit
import CryptoKit
internal import Combine

/// 剪贴板图片磁盘存储：图片以文件形式保存在 Application Support，避免 UserDefaults 膨胀
final class ClipboardImageStore {
    static let shared = ClipboardImageStore()

    private let imagesDirectory: URL
    private let cache = NSCache<NSString, NSImage>()

    /// 初始化，确保图片目录存在
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        imagesDirectory = appSupport.appendingPathComponent("CopyPasty/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    /// 保存图片数据（转为 PNG 减小体积），返回文件名；失败返回 nil
    func save(_ data: Data, id: UUID, kind: String) -> String? {
        let fileName = "\(id.uuidString)-\(kind).png"
        let output = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) ?? data
        do {
            try output.write(to: imagesDirectory.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    /// 从磁盘加载图片（带内存缓存，避免列表每次渲染都读盘）
    func load(_ fileName: String) -> NSImage? {
        if let cached = cache.object(forKey: fileName as NSString) {
            return cached
        }
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path), let image = NSImage(contentsOf: fileURL) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// 删除单个图片文件
    func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(fileName))
    }

    /// 清理未被任何记录引用的孤立图片文件
    func pruneOrphans(referenced: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
        for file in files where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
    }
}

/// 剪贴板历史记录项
struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    var content: String
    let displayName: String?
    let timestamp: Date
    let itemType: ClipboardType
    let fileSize: Int64?
    /// 敏感记录：UI 打码显示，原文加密存放
    var isSensitive: Bool
    var sensitivityKind: SensitivityKind?
    /// 加密后的原文（敏感记录专用；此时 content 存原文的 SHA-256 摘要用于去重）
    var encryptedContent: Data?
    /// 磁盘上的缩略图/原图/波形图文件名（持久化字段）
    var thumbnailFileName: String?
    var imageFileName: String?
    var waveformFileName: String?
    /// 内存中待落盘的图片数据（不持久化，写入磁盘后置空）
    var thumbnailData: Data?
    var imageData: Data?
    var waveformData: Data?

    /// 剪贴板内容类型
    enum ClipboardType: String, Codable {
        case text
        case image
        case url
        case file
        case other
    }

    /// 持久化键：图片二进制仅作旧数据迁移读取，不再写出
    enum CodingKeys: String, CodingKey {
        case id, content, displayName, timestamp, itemType, fileSize
        case isSensitive, sensitivityKind, encryptedContent
        case thumbnailFileName, imageFileName, waveformFileName
        case legacyThumbnailData = "thumbnailData"
        case legacyImageData = "imageData"
    }

    /// 初始化
    init(id: UUID = UUID(), content: String, timestamp: Date = Date(), itemType: ClipboardType = .text, isSensitive: Bool = false, sensitivityKind: SensitivityKind? = nil, encryptedContent: Data? = nil, thumbnailData: Data? = nil, imageData: Data? = nil, waveformData: Data? = nil, thumbnailFileName: String? = nil, imageFileName: String? = nil, waveformFileName: String? = nil, displayName: String? = nil, fileSize: Int64? = nil) {
        self.id = id
        self.content = content
        self.displayName = displayName
        self.timestamp = timestamp
        self.itemType = itemType
        self.isSensitive = isSensitive
        self.sensitivityKind = sensitivityKind
        self.encryptedContent = encryptedContent
        self.thumbnailData = thumbnailData
        self.imageData = imageData
        self.waveformData = waveformData
        self.thumbnailFileName = thumbnailFileName
        self.imageFileName = imageFileName
        self.waveformFileName = waveformFileName
        self.fileSize = fileSize
    }

    /// 从解码器恢复：兼容旧版本内联图片数据（迁移到磁盘由 ClipboardHistory 完成）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        itemType = try container.decode(ClipboardType.self, forKey: .itemType)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        // 未知类型值（如未来版本改了文案）置 nil 而不是让整条记录解码失败
        sensitivityKind = (try? container.decodeIfPresent(SensitivityKind.self, forKey: .sensitivityKind)) ?? nil
        encryptedContent = try container.decodeIfPresent(Data.self, forKey: .encryptedContent)
        thumbnailFileName = try container.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        waveformFileName = try container.decodeIfPresent(String.self, forKey: .waveformFileName)
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .legacyThumbnailData)
        imageData = try container.decodeIfPresent(Data.self, forKey: .legacyImageData)
    }

    /// 编码：只写文件名，不写图片二进制
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(itemType, forKey: .itemType)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encode(isSensitive, forKey: .isSensitive)
        try container.encodeIfPresent(sensitivityKind, forKey: .sensitivityKind)
        try container.encodeIfPresent(encryptedContent, forKey: .encryptedContent)
        try container.encodeIfPresent(thumbnailFileName, forKey: .thumbnailFileName)
        try container.encodeIfPresent(imageFileName, forKey: .imageFileName)
        try container.encodeIfPresent(waveformFileName, forKey: .waveformFileName)
    }

    /// 缩略图（优先内存数据，其次磁盘文件）
    var thumbnailImage: NSImage? {
        if let thumbnailData {
            return NSImage(data: thumbnailData)
        }
        if let thumbnailFileName {
            return ClipboardImageStore.shared.load(thumbnailFileName)
        }
        return nil
    }

    /// 原图（优先内存数据，其次磁盘文件）
    var originalImage: NSImage? {
        if let imageData {
            return NSImage(data: imageData)
        }
        if let imageFileName {
            return ClipboardImageStore.shared.load(imageFileName)
        }
        return nil
    }

    /// 音频波形图（优先内存数据，其次磁盘文件）
    var waveformImage: NSImage? {
        if let waveformData {
            return NSImage(data: waveformData)
        }
        if let waveformFileName {
            return ClipboardImageStore.shared.load(waveformFileName)
        }
        return nil
    }

    /// 记录关联的图片文件名集合
    var imageFileNames: Set<String> {
        Set([thumbnailFileName, imageFileName, waveformFileName].compactMap { $0 })
    }

    /// 显示内容（截断过长文本；敏感记录打码）
    var displayContent: String {
        if isSensitive {
            let kindLabel = sensitivityKind?.rawValue ?? "敏感信息"
            return "••••••••（疑似\(kindLabel)）"
        }
        if let displayName = displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "(空内容)"
            }
            if trimmed.count > 50 {
                return String(trimmed.prefix(50)) + "..."
            }
            return trimmed
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "(空内容)"
        }
        if trimmed.count > 50 {
            return String(trimmed.prefix(50)) + "..."
        }
        return trimmed
    }

    /// 显示文件大小或类型/后缀
    var sizeOrTypeDisplay: String {
        if let fileSize = fileSize {
            return formatFileSize(fileSize)
        }
        // 如果有文件名，尝试提取后缀名
        if let displayName = displayName {
            let fileExtension = (displayName as NSString).pathExtension.lowercased()
            if !fileExtension.isEmpty {
                return fileExtension.uppercased()
            }
        }
        return itemTypeDisplay
    }

    /// 显示类型名称
    var itemTypeDisplay: String {
        switch itemType {
        case .text: return "文本"
        case .image: return "图片"
        case .url: return "链接"
        case .file: return "文件"
        case .other: return "其他"
        }
    }

    /// 格式化文件大小
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 相对时间显示
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

/// 剪贴板历史管理器
class ClipboardHistory: ObservableObject {
    /// 历史记录条数上限
    static let maxItems = 20

    @Published var items: [ClipboardItem] = []
    /// 复制内容回写剪贴板后回调（用于同步监听器 changeCount，避免重复记录）
    var onPasteboardWrite: (() -> Void)?
    private let userDefaultsKey = "com.CopyPasty.history"

    /// 初始化，加载历史记录
    init() {
        loadHistory()
    }

    /// 添加剪贴板记录，返回新建的记录（媒体图片可稍后用 updateMediaImage 原地补充）
    @discardableResult
    func addItem(_ content: String, type: ClipboardItem.ClipboardType = .text, thumbnailData: Data? = nil, imageData: Data? = nil, waveformData: Data? = nil, displayName: String? = nil, fileSize: Int64? = nil) -> ClipboardItem? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }

        // 敏感内容检测：命中且加密/摘要成功时打码入库，content 只存 HMAC 摘要用于去重
        var isSensitive = false
        var sensitivityKind: SensitivityKind? = nil
        var storedContent = trimmedContent
        var encryptedContent: Data? = nil
        if type == .text || type == .other {
            if let detected = SensitiveDetector.detect(trimmedContent),
               let encrypted = HistoryCrypto.encrypt(trimmedContent),
               let hmac = HistoryCrypto.hmacHex(trimmedContent) {
                isSensitive = true
                sensitivityKind = detected
                storedContent = hmac
                encryptedContent = encrypted
            }
        }

        // 去重：明文相同或摘要相同（含重拷贝同一条敏感内容）都算同一条
        var newItem = ClipboardItem(content: storedContent, itemType: type, isSensitive: isSensitive, sensitivityKind: sensitivityKind, encryptedContent: encryptedContent, thumbnailData: thumbnailData, imageData: imageData, waveformData: waveformData, displayName: displayName, fileSize: fileSize)
        // 先把图片落盘（失败则保留内存数据待重试），成功后再清理被去重覆盖的旧文件
        if let data = newItem.thumbnailData {
            newItem.thumbnailFileName = ClipboardImageStore.shared.save(data, id: newItem.id, kind: "thumbnail")
            if newItem.thumbnailFileName != nil {
                newItem.thumbnailData = nil
            }
        }
        if let data = newItem.imageData {
            newItem.imageFileName = ClipboardImageStore.shared.save(data, id: newItem.id, kind: "original")
            if newItem.imageFileName != nil {
                newItem.imageData = nil
            }
        }
        if let data = newItem.waveformData {
            newItem.waveformFileName = ClipboardImageStore.shared.save(data, id: newItem.id, kind: "waveform")
            if newItem.waveformFileName != nil {
                newItem.waveformData = nil
            }
        }

        if let existingIndex = items.firstIndex(where: { $0.content == trimmedContent || $0.content == storedContent }) {
            deleteImageFiles(of: items.remove(at: existingIndex))
        }
        items.insert(newItem, at: 0)

        if items.count > Self.maxItems {
            deleteImageFiles(of: items.removeLast())
        }

        saveHistory()
        return newItem
    }

    /// 取消打码：解密并恢复原文显示；解密失败（如密钥已更换）返回 false
    @discardableResult
    func unmaskItem(_ item: ClipboardItem) -> Bool {
        guard item.isSensitive, let encryptedContent = item.encryptedContent,
              let plaintext = HistoryCrypto.decrypt(encryptedContent),
              let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        items[index].content = plaintext
        items[index].isSensitive = false
        items[index].sensitivityKind = nil
        items[index].encryptedContent = nil
        saveHistory()
        return true
    }

    /// 为已有记录原地补充媒体图片（音频波形/视频缩略图）；记录已被删除时静默放弃
    func updateMediaImage(id: UUID, kind: String, data: Data) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard let fileName = ClipboardImageStore.shared.save(data, id: id, kind: kind) else { return }
        switch kind {
        case "thumbnail":
            items[index].thumbnailFileName = fileName
        case "waveform":
            items[index].waveformFileName = fileName
        default:
            ClipboardImageStore.shared.delete(fileName)
            return
        }
        saveHistory()
    }

    /// 删除指定记录
    func removeItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        deleteImageFiles(of: item)
        saveHistory()
    }

    /// 清空所有记录
    func clearAll() {
        items.forEach { deleteImageFiles(of: $0) }
        items.removeAll()
        saveHistory()
    }

    /// 复制内容到剪贴板
    func copyToClipboard(_ item: ClipboardItem) {
        // 敏感记录：先解密出原文再动剪贴板；解密失败则保持剪贴板原样
        var payload = item.content
        if item.isSensitive {
            guard let encryptedContent = item.encryptedContent,
                  let plaintext = HistoryCrypto.decrypt(encryptedContent) else { return }
            payload = plaintext
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wrote = false
        switch item.itemType {
        case .image:
            // 优先原图数据，其次从文件路径取图片引用；都取不到时保持剪贴板不变，不用占位文本覆盖
            if let image = item.originalImage {
                pasteboard.writeObjects([image])
                wrote = true
            } else if item.content.hasPrefix("/"),
                      let first = item.content.components(separatedBy: "\n").first,
                      FileManager.default.isReadableFile(atPath: first) {
                pasteboard.writeObjects([URL(fileURLWithPath: first) as NSURL])
                wrote = true
            }
        case .file:
            // 写入文件引用，粘贴时可得到文件本身而非路径文本；文件不可读（已删除或沙盒外）则回退为文本
            let fileURLs = item.content.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
            if !fileURLs.isEmpty, fileURLs.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) {
                pasteboard.writeObjects(fileURLs as [NSURL])
                wrote = true
            }
        case .url, .text, .other:
            break
        }

        if !wrote {
            pasteboard.setString(payload, forType: .string)
        }
        onPasteboardWrite?()
    }

    /// 删除记录关联的图片文件
    private func deleteImageFiles(of item: ClipboardItem) {
        item.imageFileNames.forEach { ClipboardImageStore.shared.delete($0) }
    }

    /// 保存历史到 UserDefaults（图片二进制已在落盘前移除）
    private func saveHistory() {
        do {
            let encoded = try JSONEncoder().encode(items)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            print("CopyPasty: 保存历史记录失败: \(error)")
        }
    }

    /// 从 UserDefaults 加载历史
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        let decoded: [ClipboardItem]
        if let all = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            decoded = all
        } else if let fragments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // 个别记录损坏时逐条恢复，避免整表丢弃
            decoded = fragments.compactMap { fragment in
                guard let fragmentData = try? JSONSerialization.data(withJSONObject: fragment) else { return nil }
                return try? JSONDecoder().decode(ClipboardItem.self, from: fragmentData)
            }
        } else {
            return
        }
        items = decoded

        // 旧版本把图片二进制内联存在 UserDefaults，迁移到磁盘（落盘失败时保留原数据，下次启动重试）
        var migrated = false
        for index in items.indices {
            if let data = items[index].thumbnailData {
                items[index].thumbnailFileName = ClipboardImageStore.shared.save(data, id: items[index].id, kind: "thumbnail")
                if items[index].thumbnailFileName != nil {
                    items[index].thumbnailData = nil
                    migrated = true
                }
            }
            if let data = items[index].imageData {
                items[index].imageFileName = ClipboardImageStore.shared.save(data, id: items[index].id, kind: "original")
                if items[index].imageFileName != nil {
                    items[index].imageData = nil
                    migrated = true
                }
            }
        }
        if migrated {
            saveHistory()
        }

        // 清理磁盘上未被引用的孤立图片
        let referenced = Set(items.flatMap { $0.imageFileNames })
        ClipboardImageStore.shared.pruneOrphans(referenced: referenced)
    }
}
