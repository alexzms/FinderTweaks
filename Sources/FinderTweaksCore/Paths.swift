import AppKit

/// Pure path helpers: display formatting, parsing what the user typed or pasted, Tab completion.
public enum Paths {
    public static var home: String { NSHomeDirectory() }

    /// "/Users/me/Downloads" → "~/Downloads"
    public static func abbreviate(_ path: String) -> String {
        let h = home
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + String(path.dropFirst(h.count)) }
        return path
    }

    /// Splits a display path into the dimmed parent part and the emphasized last component.
    public static func split(_ shown: String) -> (parent: String, last: String) {
        guard shown != "/", shown != "~", let slash = shown.lastIndex(of: "/") else { return ("", shown) }
        return (String(shown[...slash]), String(shown[shown.index(after: slash)...]))
    }

    /// Normalizes what people paste: surrounding quotes, file:// URLs, shell-escaped spaces.
    public static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, let first = s.first, first == s.last, first == "\"" || first == "'" {
            s = String(s.dropFirst().dropLast())
        }
        if s.lowercased().hasPrefix("file://") {
            if let url = URL(string: s), url.isFileURL {
                s = url.path
            } else {
                s = String(s.dropFirst("file://".count))
            }
        }
        if s.contains("\\"), !FileManager.default.fileExists(atPath: (s as NSString).expandingTildeInPath) {
            var out = ""
            var escaping = false
            for c in s {
                if escaping { out.append(c); escaping = false }
                else if c == "\\" { escaping = true }
                else { out.append(c) }
            }
            s = out
        }
        return s
    }

    /// Expands ~ and resolves relative input against `base` (the folder currently shown).
    public static func absolute(_ s: String, base: String?) -> String {
        var p = (s as NSString).expandingTildeInPath
        if !p.hasPrefix("/") { p = ((base ?? home) as NSString).appendingPathComponent(p) }
        let standardized = (p as NSString).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }

    public static func isDirectory(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    /// A folder Finder can show as a window target (packages such as .app count as files).
    public static func isBrowsableFolder(_ path: String) -> Bool {
        isDirectory(path) && !NSWorkspace.shared.isFilePackage(atPath: path)
    }

    public struct Target: Equatable {
        public let path: String
        public let isFolder: Bool
    }

    public static func resolve(_ raw: String, base: String?) -> Target? {
        let s = clean(raw)
        guard !s.isEmpty else { return nil }
        let p = absolute(s, base: base)
        guard FileManager.default.fileExists(atPath: p) else { return nil }
        return Target(path: p, isFolder: isBrowsableFolder(p))
    }

    public enum Completion: Equatable {
        case replaced(String)
        case ambiguous([String])
        case none
    }

    /// Shell-style completion of the last path component. Keeps whatever the user typed
    /// before the last "/" (so "~" stays "~") and only rewrites the part being completed.
    public static func complete(_ text: String, base: String?) -> Completion {
        if !text.contains("/") && text.hasPrefix("~") {
            return isDirectory(absolute(text, base: base)) ? .replaced(text + "/") : .none
        }
        let rawDir: String
        let prefix: String
        if let slash = text.lastIndex(of: "/") {
            rawDir = String(text[...slash])
            prefix = String(text[text.index(after: slash)...])
        } else {
            rawDir = ""
            prefix = text
        }
        let dir = rawDir.isEmpty ? (base ?? home) : absolute(rawDir, base: base)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return .none }
        let matches = names.filter { name in
            (prefix.hasPrefix(".") || !name.hasPrefix(".")) &&
                (prefix.isEmpty || name.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil)
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !matches.isEmpty else { return .none }
        if matches.count == 1 {
            let name = matches[0]
            let slash = isBrowsableFolder((dir as NSString).appendingPathComponent(name)) ? "/" : ""
            let out = rawDir + name + slash
            return out == text ? .none : .replaced(out)
        }
        let common = commonPrefix(matches)
        if common.count > prefix.count { return .replaced(rawDir + common) }
        return .ambiguous(matches)
    }

    /// Case-insensitive longest common prefix, spelled like the first candidate.
    public static func commonPrefix(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        var prefix = Array(first)
        for name in names.dropFirst() {
            let chars = Array(name)
            var i = 0
            while i < prefix.count, i < chars.count,
                  String(prefix[i]).caseInsensitiveCompare(String(chars[i])) == .orderedSame {
                i += 1
            }
            prefix = Array(prefix[..<i])
        }
        return String(prefix)
    }
}
