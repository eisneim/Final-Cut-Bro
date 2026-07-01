import XCTest
@testable import FCPXLite

/// file_ops 工具端到端:真实读写本地文件 + 确认机制(write/edit 需 respondAgentConfirm)。
@MainActor
final class FileOpsToolTests: XCTestCase {

    private func store() -> DocumentStore {
        DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                          assetLibrary: [], sequence: Sequence(spine: [])))
    }
    private func run(_ s: DocumentStore, _ type: String, _ args: [String: Any]) -> String {
        AgentActionCatalog.find(type)!.apply(s, args.merging(["type": type]) { x, _ in x })
    }
    private var tmpDir: String { NSTemporaryDirectory() }

    func testReadFileReturnsContent() throws {
        let path = tmpDir + "fileops_read_\(UUID().uuidString).txt"
        try "第一行\n第二行\n第三行".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let s = store()
        let result = run(s, "read_file", ["path": path])
        XCTAssertTrue(result.contains("第一行"))
        XCTAssertTrue(result.contains("第三行"))
    }

    func testReadFileMissingErrors() {
        let s = store()
        let result = run(s, "read_file", ["path": tmpDir + "does_not_exist_\(UUID().uuidString).txt"])
        XCTAssertTrue(result.contains("错误"), result)
    }

    func testListDirectory() throws {
        let dir = tmpDir + "fileops_dir_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "x".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        try "y".write(toFile: dir + "/b.txt", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let s = store()
        let result = run(s, "list_directory", ["path": dir])
        XCTAssertTrue(result.contains("a.txt"))
        XCTAssertTrue(result.contains("b.txt"))
    }

    /// write_file 需确认:调用后返回 __PENDING_CONFIRM__ 且设置 agentConfirm;文件此时【尚未】写入。
    func testWriteFileRequiresConfirmation() {
        let path = tmpDir + "fileops_write_\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let s = store()
        let pending = run(s, "write_file", ["path": path, "content": "你好世界"])
        XCTAssertEqual(pending, "__PENDING_CONFIRM__")
        XCTAssertNotNil(s.agentConfirm)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "确认前不应写入")

        // 用户"允许" → 真正写入
        s.respondAgentConfirm(approve: true)
        XCTAssertNil(s.agentConfirm)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "确认后应写入")
        XCTAssertEqual(try? String(contentsOfFile: path, encoding: .utf8), "你好世界")
    }

    /// write_file 拒绝 → 文件不写入。
    func testWriteFileRejected() {
        let path = tmpDir + "fileops_reject_\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let s = store()
        _ = run(s, "write_file", ["path": path, "content": "不该写"])
        s.respondAgentConfirm(approve: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "拒绝后不应写入")
    }

    /// edit_file:查找替换,需确认。
    func testEditFileReplacesAfterConfirm() throws {
        let path = tmpDir + "fileops_edit_\(UUID().uuidString).txt"
        try "hello world foo".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let s = store()
        let pending = run(s, "edit_file", ["path": path, "oldText": "world", "newText": "地球"])
        XCTAssertEqual(pending, "__PENDING_CONFIRM__")
        // 确认前不变
        XCTAssertEqual(try? String(contentsOfFile: path, encoding: .utf8), "hello world foo")
        s.respondAgentConfirm(approve: true)
        XCTAssertEqual(try? String(contentsOfFile: path, encoding: .utf8), "hello 地球 foo")
    }

    /// confirm 消息进 chat:role 从 .confirm 变 .tool,并带确认结果文本。
    func testConfirmMessageInChat() {
        let path = tmpDir + "fileops_chat_\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let s = store()
        _ = run(s, "write_file", ["path": path, "content": "x"])
        XCTAssertEqual(s.agentMessages.last?.role, .confirm)
        s.respondAgentConfirm(approve: true)
        XCTAssertEqual(s.agentMessages.last?.role, .tool)   // 确认后变 tool
        XCTAssertNotNil(s.agentConfirmResult)
        XCTAssertTrue(s.agentConfirmResult?.result.contains("已写入") ?? false)
    }
}
