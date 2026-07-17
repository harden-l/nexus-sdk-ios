import CommonCrypto
import Foundation

public enum APIRequestEncryption {
    public static func prepareBody(_ jsonBody: String, config: CoreUserConfig, encrypt: Bool? = nil) throws -> Data {
        let shouldEncrypt = encrypt ?? config.encrypt
        guard shouldEncrypt else { return Data(jsonBody.utf8) }
        return try encryptString(jsonBody, key: requiredKey(config))
    }

    public static func readResponse(_ data: Data, config: CoreUserConfig, encrypt: Bool? = nil) throws -> String {
        let shouldEncrypt = encrypt ?? config.encrypt
        guard shouldEncrypt else { return String(data: data, encoding: .utf8) ?? "" }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return "" }
        return try decryptString(text, key: requiredKey(config))
    }

    public static func encryptString(_ plainText: String, key: String) throws -> Data {
        let encrypted = try crypt(data: Data(plainText.utf8), key: key, operation: CCOperation(kCCEncrypt))
        return Data(encrypted.base64EncodedString().utf8)
    }

    public static func decryptString(_ base64Text: String, key: String) throws -> String {
        guard let cipher = Data(base64Encoded: base64Text) else { throw CoreUserError.encryptionFailed }
        let plain = try crypt(data: cipher, key: key, operation: CCOperation(kCCDecrypt))
        return String(data: plain, encoding: .utf8) ?? ""
    }

    private static func requiredKey(_ config: CoreUserConfig) throws -> String {
        guard let key = config.encryptionKey, !key.isEmpty else { throw CoreUserError.encryptionKeyRequired }
        return key
    }

    private static func crypt(data: Data, key: String, operation: CCOperation) throws -> Data {
        guard let keyData = key.data(using: .utf8), keyData.count == kCCKeySizeAES256 else {
            throw CoreUserError.invalidConfig("encryptionKey must be 32 bytes for AES-256")
        }
        let ivData = Data(key.utf8.prefix(kCCBlockSizeAES128))
        let outputCapacity = data.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            keyData.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CoreUserError.encryptionFailed }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}
