import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var keyMonitor: Any?
    private let store = DocumentStore(document: Document(
        formatWidth: 1920, formatHeight: 1080, frameRate: 25,
        assetLibrary: [], sequence: Sequence(spine: [])))

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "FCPX-lite"
        window.contentView = NSHostingView(rootView: RootView(store: store))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyboardShortcuts()
    }

    /// 全局快捷键(无修饰键时):空格=播放/暂停;QWED=编辑动作;ATPRBZH=工具。
    /// 在文本编辑(如聊天输入框)聚焦时不拦截。
    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.window?.firstResponder is NSText { return event }            // 文本输入中,放行
            if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                return event                                                       // 带修饰键的留给系统/其它处理
            }
            if event.keyCode == 49 {                                              // 空格
                self.store.dispatch(.togglePlay); return nil
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": self.store.connectAtPlayhead(); return nil
            case "w": self.store.insertAtPlayhead(); return nil
            case "e": self.store.appendSelected(); return nil
            case "d": self.store.overwriteAtPlayhead(); return nil
            case "a": self.store.dispatch(.setTool(.select)); return nil
            case "t": self.store.dispatch(.setTool(.trim)); return nil
            case "p": self.store.dispatch(.setTool(.position)); return nil
            case "r": self.store.dispatch(.setTool(.range)); return nil
            case "b": self.store.dispatch(.setTool(.blade)); return nil
            case "z": self.store.dispatch(.setTool(.zoom)); return nil
            case "h": self.store.dispatch(.setTool(.hand)); return nil
            default:  return event
            }
        }
    }
}
