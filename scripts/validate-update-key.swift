import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("需要指定公钥文件") }
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let text = String(data: input, encoding: .utf8),
      let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      seed.count == 32 else {
    fail("CI 密钥必须为 Sparkle 导出的 Base64 32 字节种子")
}
do {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    let expected = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard key.publicKey.rawRepresentation.base64EncodedString() == expected else {
        fail("CI 私钥与应用公钥不匹配，拒绝签名")
    }
    print("CI 签名密钥与应用公钥匹配")
} catch {
    fail("签名密钥或公钥文件无法读取")
}
