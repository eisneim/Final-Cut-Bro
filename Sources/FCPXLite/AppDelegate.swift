import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
        _ = store // M1.0 外壳暂不绑定数据;占位以验证编译与启动

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "FCPX-lite"
        window.contentView = NSHostingView(rootView: RootView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
