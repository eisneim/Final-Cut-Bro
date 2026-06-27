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
        #if DEBUG
        debugServer = DebugControlServer(store: store, window: window)
        debugServer?.start()
        #endif
    }

    #if DEBUG
    private var debugServer: DebugControlServer?
    #endif

    /// 全局快捷键(对照 FCP 官方键位):
    /// 空格=播放/暂停;QWED=连接/插入/追加/覆盖;ATPRBZH=工具;
    /// ←/→=播放头±1帧(⇧±10帧);Home/End=头/尾;Delete=删除选中(ripple);
    /// ⌘+/⌘−=缩放;⌘B=在播放头切割。文本输入聚焦时不拦截。
    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.window?.firstResponder is NSText { return event }
            let store = self.store
            let mods = event.modifierFlags
            let hasCmd = mods.contains(.command)
            let hasOptCtrl = !mods.intersection([.option, .control]).isEmpty

            // ⌘ 组合
            if hasCmd && !hasOptCtrl {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "=", "+": store.dispatch(.setZoom(store.ui.pxPerSecond * 1.5)); return nil
                case "-":      store.dispatch(.setZoom(store.ui.pxPerSecond / 1.5)); return nil
                case "b":      store.bladeAtPlayhead(); return nil
                case "i":      ImportPanel.present(into: store); return nil
                default:       return event
                }
            }
            if hasCmd || hasOptCtrl { return event }   // 其它带修饰键放行

            // 方向键 / Home / End / 空格 / Delete(允许 Shift)
            switch event.keyCode {
            case 123: store.nudgePlayhead(frames: mods.contains(.shift) ? -10 : -1); return nil  // ←
            case 124: store.nudgePlayhead(frames: mods.contains(.shift) ?  10 :  1); return nil  // →
            case 115: store.playheadToStart(); return nil   // Home
            case 119: store.playheadToEnd(); return nil      // End
            case 49:  store.dispatch(.togglePlay); return nil // 空格
            case 51:  store.deleteSelected(); return nil      // Delete
            default:  break
            }

            if mods.contains(.shift) { return event }   // 大写字母放行,工具键用无修饰小写
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": store.connectAtPlayhead(); return nil
            case "w": store.insertAtPlayhead(); return nil
            case "e": store.appendSelected(); return nil
            case "d": store.overwriteAtPlayhead(); return nil
            case "a": store.dispatch(.setTool(.select)); return nil
            case "t": store.dispatch(.setTool(.trim)); return nil
            case "p": store.dispatch(.setTool(.position)); return nil
            case "r": store.dispatch(.setTool(.range)); return nil
            case "b": store.dispatch(.setTool(.blade)); return nil
            case "z": store.dispatch(.setTool(.zoom)); return nil
            case "h": store.dispatch(.setTool(.hand)); return nil
            case "n": store.dispatch(.toggleSnapping); return nil
            default:  return event
            }
        }
    }
}
