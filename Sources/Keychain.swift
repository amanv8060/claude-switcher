import Foundation

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (-1, "", error.localizedDescription) }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
}

struct SwitcherError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Uses /usr/bin/security rather than SecItem APIs: Claude Code creates its item
/// with that tool, so it is already on the item's ACL and no access prompts appear.
enum Keychain {
    static func read(service: String, account: String? = nil) -> String? {
        var args = ["find-generic-password", "-s", service]
        if let account { args += ["-a", account] }
        args.append("-w")
        let r = run("/usr/bin/security", args)
        guard r.status == 0 else { return nil }
        let s = r.out.trimmingCharacters(in: .newlines)
        // `security -w` prints hex when the data isn't plain text.
        if !s.hasPrefix("{"), s.count % 2 == 0, s.allSatisfy(\.isHexDigit),
           let d = Data(hex: s), let text = String(data: d, encoding: .utf8) {
            return text
        }
        return s
    }

    static func write(service: String, account: String, value: String) throws {
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        let r = run("/usr/bin/security",
                    ["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        if r.status != 0 { throw SwitcherError("Keychain write failed: \(r.err)") }
    }

    static func delete(service: String, account: String) {
        run("/usr/bin/security", ["delete-generic-password", "-a", account, "-s", service])
    }
}

extension Data {
    init?(hex: String) {
        var d = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            d.append(b)
            i = j
        }
        self = d
    }
}

func parseJSONObject(_ s: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
}

func jsonString(_ obj: Any, pretty: Bool = false) throws -> String {
    var opts: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
    if pretty { opts.insert(.prettyPrinted) }
    return String(decoding: try JSONSerialization.data(withJSONObject: obj, options: opts), as: UTF8.self)
}
