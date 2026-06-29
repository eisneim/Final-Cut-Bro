import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var keyMonitor: Any?
    private var keyUpMonitor: Any?
    private var spring = SpringTool()
    private let store = DocumentStore(document: Document(
        assetLibrary: [], projects: [], currentProjectID: nil))   // 启动无项目 → 时间轴门控

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 默认占满主显示器可用区域(扣掉菜单栏/Dock)。
        let initial = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(
            contentRect: initial,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "FCPX-lite"
        window.contentView = NSHostingView(rootView: RootView(store: store))
        window.setFrame(initial, display: true)   // 占满可用屏幕
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installMenu()
        installKeyboardShortcuts()
        #if DEBUG
        debugServer = DebugControlServer(store: store, window: window)
        debugServer?.start()
        #endif
    }

    #if DEBUG
    private var debugServer: DebugControlServer?
    #endif

    /// 标准菜单栏(裸 NSApplication 默认没有)→ ⌘C/V/X/A/Z 在文本框里才能工作。
    private func installMenu() {
        let mainMenu = NSMenu()
        // App 菜单
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "隐藏 FCPX-lite", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "退出 FCPX-lite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let exportItem = NSMenuItem(title: "导出…", action: #selector(showExportMenu), keyEquivalent: "e")
        exportItem.target = self
        appMenu.addItem(exportItem)
        appItem.submenu = appMenu
        // 编辑菜单(复制/粘贴等走响应链)
        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]; editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    /// 是否正在文本框里编辑(此时所有快捷键放行,让打字/复制粘贴正常)。
    private var isEditingText: Bool {
        guard let r = window?.firstResponder else { return false }
        if r is NSText || r is NSTextView { return true }
        if String(describing: type(of: r)).contains("Text") { return true }
        if NSTextInputContext.current != nil { return true }
        return false
    }

    /// 全局快捷键(对照 FCP 官方键位):
    /// 空格=播放/暂停;QWED=连接/插入/追加/覆盖;ATPRBZH=工具;
    /// ←/→=播放头±1帧(⇧±10帧);Home/End=头/尾;Delete=删除选中(ripple);
    /// ⌘+/⌘−=缩放;⌘B=在播放头切割。文本输入聚焦时不拦截。
    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.isEditingText { return event }   // 文本编辑中:全部放行(打字/复制粘贴)
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
                case "z":      mods.contains(.shift) ? store.redo() : store.undo(); return nil
                case "a":      store.dispatch(.selectAllAssets); return nil
                case "c":      store.copySelected(); return nil
                case "v":      store.pasteAtPlayhead(); return nil
                case "5":      store.dispatch(.setShowEffects(!store.ui.showEffects)); return nil
                default:       return event
                }
            }
            // ⌥[ / ⌥] : 快速 trim 删左 / 删右(只 option,无 cmd/ctrl)
            if mods.contains(.option) && !hasCmd && !mods.contains(.control) {
                switch event.charactersIgnoringModifiers {
                case "[": store.trimLeftOfPlayhead();  return nil
                case "]": store.trimRightOfPlayhead(); return nil
                default: break
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
            let char = event.charactersIgnoringModifiers?.lowercased()
            // 编辑动作 / 吸附
            switch char {
            case "q": store.connectAtPlayhead(); return nil
            case "w": store.insertAtPlayhead(); return nil
            case "e":
                // 多选时批量追加;单/零选时走原路径
                if store.ui.selectedAssetIDs.count > 1 {
                    store.appendAllSelected()
                } else {
                    store.appendSelected()
                }
                return nil
            case "d": store.overwriteAtPlayhead(); return nil
            case "n": store.dispatch(.toggleSnapping); return nil
            case "v": store.toggleSelectedEnabled(); return nil
            default: break
            }
            // 工具键 → 弹簧:按下临时切;短按=永久,长按=松开还原
            if let tool = Self.toolForKey(char) {
                if let t = self.spring.keyDown(tool: tool, current: store.ui.currentTool,
                                               time: event.timestamp, isRepeat: event.isARepeat) {
                    store.dispatch(.setTool(t))
                }
                return nil
            }
            return event
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            if self.isEditingText { return event }
            let char = event.charactersIgnoringModifiers?.lowercased()
            // 只在松开的是当前持有的工具键时处理
            guard let held = self.spring.heldShortcut, held == char else { return event }
            if let revert = self.spring.keyUp(time: event.timestamp) {
                self.store.dispatch(.setTool(revert))   // 长按 → 还原
            }
            return event
        }
    }

    private static func toolForKey(_ char: String?) -> EditTool? {
        switch char {
        case "a": return .select
        case "t": return .trim
        case "p": return .position
        case "r": return .range
        case "b": return .blade
        case "z": return .zoom
        case "h": return .hand
        default:  return nil
        }
    }

    @objc private func showExportMenu() { store.dispatch(.setShowExport(true)) }
}
