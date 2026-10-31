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

    /// 诊断用统计（不含原文），用于排查漏检
    static func debugStats(_ text: String) -> String {
        let collapsed = text.filter { !$0.isWhitespace }
        let digits = collapsed.filter { $0.isASCII && $0.isNumber }.count
        let distinct = Set(collapsed).count
        let digitRatio = collapsed.isEmpty ? 0 : Double(digits) / Double(collapsed.count)
        let entropyRatio = distinct > 1 ? shannonEntropyPerChar(collapsed) / log2(Double(distinct)) : 0
        return "len=\(text.count) collapsed=\(collapsed.count) distinct=\(distinct) digitRatio=\(String(format: "%.2f", digitRatio)) entropyRatio=\(String(format: "%.2f", entropyRatio)) hasWhitespace=\(text.contains(where: { $0.isWhitespace }))"
    }

    /// 检测文本是否疑似敏感内容，返回类型
    static func detect(_ text: String) -> SensitivityKind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4096 else { return nil }
        // 拷贝时常混入换行/空格（终端折行、表格复制），折叠空白后再判断；
        // 命中时加密与去重仍用原文，取消打码后恢复原样
        let collapsed = trimmed.filter { !$0.isWhitespace }
        if detectBankCard(collapsed) { return .bankCard }
        if detectSecretKey(collapsed) { return .secretKey }
        if detectPassword(collapsed) { return .password }
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

    /// 密钥：私钥块、已知前缀、长十六进制串、高熵随机串（传入文本已折叠空白）
    private static func detectSecretKey(_ text: String) -> Bool {
        if text.contains("PRIVATE KEY") || text.contains("PRIVATEKEY") { return true }
        for prefix in secretPrefixes where text.hasPrefix(prefix) { return true }

        // 单个无空白的 token 才按随机串判断；排除 URL（含 ://）
        guard !text.contains(where: { $0.isWhitespace }), !text.contains("://") else { return false }
        // 32 位以上纯 ASCII 十六进制（API 密钥、证书指纹等）
        if text.count >= 32, text.allSatisfy({ $0.isASCII && $0.isHexDigit }) { return true }
        // 24 字符以上、至少 3 类字符、字符分布较均匀的随机串
        // （熵密度上界是 log2(不同字符数)；hex 类密钥字母表仅 16 字符，比值天然偏低，
        //   故阈值取 0.85 并叠加数字占比判据——随机密钥数字占比 ~15-55%，
        //   而拼接单词/SQL 等文本折叠后 ~4%，这是区分两者的有效特征）
        let distinct = distinctCharacterCount(text)
        let digitCount = text.filter { $0.isASCII && $0.isNumber }.count
        if text.count >= 24, characterClassCount(text) >= 3, distinct >= 16,
           Double(digitCount) / Double(text.count) >= 0.12,
           shannonEntropyPerChar(text) / log2(Double(distinct)) >= 0.85 {
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

    /// 从钥匙串加载密钥，首次使用时生成。
    /// 历史构建可能把密钥写在 data protection 或传统钥匙串之一，两处都找；
    /// 保存时两处都试（不同签名形态可用的钥匙串不同），避免共享可变状态导致静默失败。
    private static var currentKey: SymmetricKey? {
        if let cachedKey { return cachedKey }
        for useDP in [true, false] {
            if let existing = loadKeyFromKeychain(useDP: useDP) {
                cachedKey = existing
                return existing
            }
        }
        let newKey = SymmetricKey(size: .bits256)
        for useDP in [true, false] {
            if saveKeyToKeychain(newKey, useDP: useDP) {
                cachedKey = newKey
                return newKey
            }
        }
        return nil
    }

    private static func keychainQuery(useDP: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PD.CopyPasty",
            kSecAttrAccount as String: "history-encryption-key"
        ]
        if useDP {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func loadKeyFromKeychain(useDP: Bool) -> SymmetricKey? {
        var query = keychainQuery(useDP: useDP)
        // 必须显式要求返回数据，否则传统钥匙串返回的类型无法转成 Data
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let keyData = item as? Data else {
            #if DEBUG
            if status != errSecItemNotFound {
                NSLog("CopyPasty: 钥匙串读取失败 useDP=%d status=%d", useDP ? 1 : 0, status)
            }
            #endif
            return nil
        }
        return SymmetricKey(data: keyData)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey, useDP: Bool) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }
        var attributes = keychainQuery(useDP: useDP)
        attributes[kSecValueData as String] = keyData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return true }
        // 已存在（其他会话先写入）时回读
        if status == errSecDuplicateItem { return loadKeyFromKeychain(useDP: useDP) != nil }
        #if DEBUG
        NSLog("CopyPasty: 钥匙串 SecItemAdd 失败 useDP=%d status=%d", useDP ? 1 : 0, status)
        #endif
        return false
    }
}
