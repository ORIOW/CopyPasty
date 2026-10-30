//
//  SensitiveDetector.swift
//  CopyPasty
//
//  Created by 邓家炜 on 2026/10/31.
//

import Foundation
import CryptoKit

/// 敏感内容类型（rawValue 用于 UI 文案）
enum SensitivityKind: String, Codable {
    case password = "密码"
    case secretKey = "密钥"
    case bankCard = "银行卡号"
}

/// 简单敏感字符串检测器：识别用户拷贝文本中的密码、密钥、银行卡号等
enum SensitiveDetector {
    /// 常见服务的密钥前缀
    private static let secretPrefixes = [
        "sk-", "sk-proj-", "sk-ant-",          // OpenAI / Anthropic
        "ghp_", "gho_", "ghu_", "ghs_", "github_pat_",  // GitHub
        "AKIA", "ASIA",                         // AWS
        "xoxb-", "xoxp-", "xoxa-",              // Slack
        "glpat-",                               // GitLab
        "AIza",                                 // Google
        "npm_"                                  // npm
    ]

    /// 检测文本是否疑似敏感内容，返回类型
    static func detect(_ text: String) -> SensitivityKind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4096 else { return nil }
        if detectBankCard(trimmed) { return .bankCard }
        if detectSecretKey(trimmed) { return .secretKey }
        if detectPassword(trimmed) { return .password }
        return nil
    }

    /// 银行卡号：13-19 位 ASCII 数字（允许空格/短横线分隔），通过 Luhn 校验
    private static func detectBankCard(_ text: String) -> Bool {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard digits.count >= 13, digits.count <= 19 else { return false }
        // 只允许数字、空格、短横线，且分隔符不连续
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == " " || $0 == "-") }),
              !text.contains("  "), !text.contains("--") else { return false }
        return luhnCheck(digits)
    }

    /// Luhn 校验
    private static func luhnCheck(_ digits: String) -> Bool {
        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            guard let digit = char.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// 密钥：私钥块、已知前缀、长十六进制串、高熵随机串
    private static func detectSecretKey(_ text: String) -> Bool {
        if text.contains("PRIVATE KEY") { return true }
        for prefix in secretPrefixes where text.hasPrefix(prefix) { return true }

        // 单个无空白的 token 才按随机串判断；排除 URL（含 ://）
        guard !text.contains(where: { $0.isWhitespace }), !text.contains("://") else { return false }
        // 32 位以上纯 ASCII 十六进制（API 密钥、证书指纹等）
        if text.count >= 32, text.allSatisfy({ $0.isASCII && $0.isHexDigit }) { return true }
        // 24 字符以上、至少 3 类字符、含数字、字符分布接近均匀的随机串
        // （熵密度上界是 log2(不同字符数)，固定阈值对短串数学上不可达，故用比率 + 不同字符数下限）
        // 要求含数字：真实 API 密钥几乎必有数字，可排除文件路径等纯字母混排文本
        let distinct = distinctCharacterCount(text)
        if text.count >= 24, characterClassCount(text) >= 3, distinct >= 16,
           text.contains(where: { $0.isASCII && $0.isNumber }),
           shannonEntropyPerChar(text) / log2(Double(distinct)) >= 0.9 {
            return true
        }
        return false
    }

    /// 密码：8-64 字符、无空白、四类字符齐全、含强符号（排除 . _ 这类常见于版本号/标识符的分隔符）、
    /// 字符分布接近均匀且不同字符数达标
    private static func detectPassword(_ text: String) -> Bool {
        guard text.count >= 8, text.count <= 64 else { return false }
        guard !text.contains(where: { $0.isWhitespace }) else { return false }
        guard characterClassCount(text) == 4 else { return false }
        guard text.contains(where: { strongPunctuationSymbols.contains($0) }) else { return false }
        let distinct = distinctCharacterCount(text)
        guard distinct >= 8 else { return false }
        return shannonEntropyPerChar(text) / log2(Double(distinct)) >= 0.85
    }

    /// 强符号集（密码检测用，不含 . 和 _ 以避免命中版本号、标识符）
    private static let strongPunctuationSymbols: Set<Character> = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "-", "+", "=", "[", "]", "{", "}", "|", ";", ":", "'", "\"", ",", "<", ">", "?", "/", "~", "`"]

    /// 字符种类数：小写 / 大写 / 数字 / 其他
    private static func characterClassCount(_ text: String) -> Int {
        var hasLower = false, hasUpper = false, hasDigit = false, hasOther = false
        for char in text {
            if char.isLowercase { hasLower = true }
            else if char.isUppercase { hasUpper = true }
            else if char.isNumber { hasDigit = true }
            else { hasOther = true }
        }
        return [hasLower, hasUpper, hasDigit, hasOther].filter { $0 }.count
    }

    /// 不同字符数
    private static func distinctCharacterCount(_ text: String) -> Int {
        Set(text).count
    }

    /// 香农熵密度（每字符比特数；上界为 log2(不同字符数)）
    private static func shannonEntropyPerChar(_ text: String) -> Double {
        var frequencies: [Character: Int] = [:]
        for char in text {
            frequencies[char, default: 0] += 1
        }
        let length = Double(text.count)
        var entropy = 0.0
        for count in frequencies.values {
            let p = Double(count) / length
            entropy -= p * log2(p)
        }
        return entropy
    }
}

/// 历史记录加密器：AES-GCM，密钥保存在钥匙串（仅主线程访问）
@MainActor
enum HistoryCrypto {
    private static var cachedKey: SymmetricKey?
    private static var cachedHMACKey: SymmetricKey?

    /// 加密原文，返回 AES-GCM combined 数据
    static func encrypt(_ plaintext: String) -> Data? {
        guard let key = currentKey,
              let sealed = try? AES.GCM.seal(Data(plaintext.utf8), using: key) else { return nil }
        return sealed.combined
    }

    /// 解密 AES-GCM combined 数据
    static func decrypt(_ data: Data) -> String? {
        guard let key = currentKey,
              let sealed = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(sealed, using: key) else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }

    /// 带密钥的 HMAC-SHA256 摘要（防低熵内容被离线爆破，用于敏感记录去重）
    static func hmacHex(_ text: String) -> String? {
        guard let key = currentKey else { return nil }
        if cachedHMACKey == nil {
            // 用 HKDF 从主密钥派生独立子密钥，与加密用途隔离
            cachedHMACKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data("dedup-hmac".utf8), outputByteCount: 32)
        }
        let auth = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: cachedHMACKey!)
        return auth.map { String(format: "%02x", $0) }.joined()
    }

    /// 从钥匙串加载密钥，首次使用时生成
    private static var currentKey: SymmetricKey? {
        if let cachedKey { return cachedKey }
        if let existing = loadKeyFromKeychain() {
            cachedKey = existing
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        guard saveKeyToKeychain(newKey) else { return nil }
        cachedKey = newKey
        return newKey
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PD.CopyPasty",
            kSecAttrAccount as String: "history-encryption-key",
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private static func loadKeyFromKeychain() -> SymmetricKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery() as CFDictionary, &item)
        guard status == errSecSuccess, let keyData = item as? Data else { return nil }
        return SymmetricKey(data: keyData)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }
        var attributes = keychainQuery()
        attributes[kSecValueData as String] = keyData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return true }
        // 已存在（极端并发）时尝试再读一次
        if status == errSecDuplicateItem { return loadKeyFromKeychain() != nil }
        return false
    }
}
