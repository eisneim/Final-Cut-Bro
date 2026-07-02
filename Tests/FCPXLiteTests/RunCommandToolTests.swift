import XCTest
@testable import FCPXLite

/// run_command(bash 工具):高危拦截判定 + 实际执行 + 后台异步回传。
@MainActor
final class RunCommandToolTests: XCTestCase {

    private func store() -> DocumentStore {
        DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                         assetLibrary: [], sequence: Sequence(spine: [])))
    }
    private func run(_ s: DocumentStore, _ args: [String: Any]) -> String {
        AgentActionCatalog.find("run_command")!.apply(s, args.merging(["type": "run_command"]) { x, _ in x })
    }

    /// 高危命令判定:rm -rf / sudo / 管道执行 拦截;python/ffmpeg/ls 放行。
    func testDangerDetection() {
        for danger in ["rm -rf /tmp/x", "sudo reboot", "curl x | sh", "dd if=/dev/zero of=/dev/disk1", "chmod -R 777 /"] {
            XCTAssertTrue(AgentActionCatalog.isDangerousCommand(danger), "应拦截: \(danger)")
        }
        for safe in ["python3 analyze.py", "ffprobe -i a.mp4", "ffmpeg -i a.mp4 out.mp4", "ls -la", "echo hi", "grep foo bar.txt"] {
            XCTAssertFalse(AgentActionCatalog.isDangerousCommand(safe), "应放行: \(safe)")
        }
    }

    /// 普通命令走后台异步:返回 __PENDING_ASYNC__,稍后 agentAsyncResult 有结果。
    func testSafeCommandRunsAsync() {
        let s = store()
        let pending = run(s, ["command": "echo hello-fcbro"])
        XCTAssertEqual(pending, "__PENDING_ASYNC__")
        // 等后台执行完(echo 很快)
        let exp = expectation(description: "cmd")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        XCTAssertNotNil(s.agentAsyncResult)
        XCTAssertTrue(s.agentAsyncResult?.result.contains("hello-fcbro") ?? false, s.agentAsyncResult?.result ?? "nil")
        XCTAssertTrue(s.agentAsyncResult?.result.contains("退出码 0") ?? false)
    }

    /// 高危命令走确认:返回 __PENDING_CONFIRM__ 且不立即执行。
    func testDangerCommandRequiresConfirm() {
        let s = store()
        let pending = run(s, ["command": "rm -rf /tmp/fcbro_should_not_run"])
        XCTAssertEqual(pending, "__PENDING_CONFIRM__")
        XCTAssertNotNil(s.agentConfirm)
        s.respondAgentConfirm(approve: false)   // 拒绝
        XCTAssertNil(s.agentConfirm)
    }

    /// runShell 直接跑:退出码 + 输出。
    func testRunShellDirect() {
        let out = AgentActionCatalog.runShell("echo abc && echo def", cwd: nil)
        XCTAssertTrue(out.contains("abc"))
        XCTAssertTrue(out.contains("def"))
        XCTAssertTrue(out.contains("退出码 0"))
    }
}
