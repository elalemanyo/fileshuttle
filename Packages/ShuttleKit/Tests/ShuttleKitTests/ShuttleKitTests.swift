import Foundation
import Testing
@testable import ShuttleKit

@Suite struct FilenameStyleTests {
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func original() {
        #expect(FilenameStyle.original.remoteName(for: "My File.PNG", hash: "abc123") == "My-File.png")
    }

    @Test func originalWithHash() {
        #expect(FilenameStyle.originalWithHash.remoteName(for: "report?.pdf", hash: "abc123") == "report-abc123.pdf")
    }

    @Test func hashOnly() {
        #expect(FilenameStyle.hash.remoteName(for: "anything.tar.gz", hash: "abc123") == "abc123.gz")
    }

    @Test func noExtension() {
        #expect(FilenameStyle.originalWithHash.remoteName(for: "Makefile", hash: "abc123") == "Makefile-abc123")
    }

    @Test func dateStyle() {
        let name = FilenameStyle.date.remoteName(for: "x.jpg", hash: "abc123", date: date)
        #expect(name.hasSuffix("-abc.jpg"))
        #expect(name.count == "2026-09-21-123456-abc.jpg".count)
    }
}

@Suite struct ServerConfigTests {
    func config(path: String, url: String = "cloud.example.com/tmp") -> ServerConfig {
        ServerConfig(transferProtocol: .sftp, host: "h", port: 22, username: "u",
                     credentials: .password("p"), remotePath: path, publicURL: url)
    }

    @Test func relativePaths() {
        #expect(config(path: "./").remoteFilePath("a.png") == "a.png")
        #expect(config(path: "").remoteFilePath("a.png") == "a.png")
        #expect(config(path: "www/tmp/").remoteFilePath("a.png") == "www/tmp/a.png")
    }

    @Test func absolutePaths() {
        #expect(config(path: "/var/www/").remoteFilePath("a.png") == "/var/www/a.png")
        #expect(config(path: "/").remoteFilePath("a.png") == "/a.png")
    }

    @Test func shareURL() {
        #expect(config(path: "").shareURL(for: "a b.png")?.absoluteString == "https://cloud.example.com/tmp/a%20b.png")
        #expect(config(path: "", url: "http://x.de/").shareURL(for: "a.png")?.absoluteString == "http://x.de/a.png")
        #expect(config(path: "", url: "").shareURL(for: "a.png") == nil)
    }
}
