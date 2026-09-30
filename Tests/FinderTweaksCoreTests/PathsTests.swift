import Foundation
import Testing
@testable import FinderTweaksCore

struct PathsTests {
    let home = NSHomeDirectory()

    @Test func abbreviatesHome() {
        #expect(Paths.abbreviate(home + "/Downloads") == "~/Downloads")
        #expect(Paths.abbreviate(home) == "~")
        #expect(Paths.abbreviate(home + "x/y") == home + "x/y")
        #expect(Paths.abbreviate("/tmp") == "/tmp")
    }

    @Test func splitsParentAndLastComponent() {
        #expect(Paths.split("~/Library/Application Support") == ("~/Library/", "Application Support"))
        #expect(Paths.split("/Users") == ("/", "Users"))
        #expect(Paths.split("/") == ("", "/"))
        #expect(Paths.split("~") == ("", "~"))
    }

    @Test func cleansPastedPaths() {
        #expect(Paths.clean("  \"/tmp\"  ") == "/tmp")
        #expect(Paths.clean("'/tmp'") == "/tmp")
        #expect(Paths.clean("file:///Users/x/My%20Folder/") == "/Users/x/My Folder")
        #expect(Paths.clean("/nonexistent/My\\ Folder") == "/nonexistent/My Folder")
    }

    @Test func makesPathsAbsolute() {
        #expect(Paths.absolute("..", base: "/usr/local") == "/usr")
        #expect(Paths.absolute("bin", base: "/usr") == "/usr/bin")
        #expect(Paths.absolute("~/Downloads", base: "/usr") == home + "/Downloads")
        #expect(Paths.absolute("/usr/bin/", base: nil) == "/usr/bin")
        #expect(Paths.absolute("/", base: nil) == "/")
    }

    @Test func resolvesTargets() {
        #expect(Paths.resolve("/usr/bin", base: nil) == Paths.Target(path: "/usr/bin", isFolder: true))
        #expect(Paths.resolve("/usr/bin/true", base: nil) == Paths.Target(path: "/usr/bin/true", isFolder: false))
        #expect(Paths.resolve("/System/Applications/Calculator.app", base: nil)?.isFolder == false)
        #expect(Paths.resolve("/definitely/not/here", base: nil) == nil)
        #expect(Paths.resolve("   ", base: nil) == nil)
        #expect(Paths.resolve("..", base: "/usr/bin") == Paths.Target(path: "/usr", isFolder: true))
    }

    @Test func completesLikeAShell() throws {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "finder-tweaks-tests-\(UUID().uuidString)"
        for name in ["Alpha", "Alphabet", "Documents", ".hidden"] {
            try fm.createDirectory(atPath: dir + "/" + name, withIntermediateDirectories: true)
        }
        fm.createFile(atPath: dir + "/beta.txt", contents: Data())
        defer { try? fm.removeItem(atPath: dir) }

        #expect(Paths.complete(dir + "/al", base: nil) == .replaced(dir + "/Alpha"))
        #expect(Paths.complete(dir + "/Alpha", base: nil) == .ambiguous(["Alpha", "Alphabet"]))
        #expect(Paths.complete(dir + "/Alphab", base: nil) == .replaced(dir + "/Alphabet/"))
        #expect(Paths.complete(dir + "/b", base: nil) == .replaced(dir + "/beta.txt"))
        #expect(Paths.complete(dir + "/.h", base: nil) == .replaced(dir + "/.hidden/"))
        #expect(Paths.complete(dir + "/Alphabet/", base: nil) == .none)
        #expect(Paths.complete(dir + "/zzz", base: nil) == .none)
        #expect(Paths.complete("doc", base: dir) == .replaced("Documents/"))
        #expect(Paths.complete("~", base: nil) == .replaced("~/"))
        #expect(Paths.commonPrefix(["Foo", "foobar", "FOOd"]) == "Foo")
    }
}
