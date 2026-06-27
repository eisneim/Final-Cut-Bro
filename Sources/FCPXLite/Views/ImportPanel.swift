import AppKit
import UniformTypeIdentifiers

/// 导入面板:NSOpenPanel 选媒体 → MediaImporter 读元数据 → dispatch(.importAsset)。
/// 由素材池「导入」按钮与 ⌘I 快捷键共用。
enum ImportPanel {
    /// 调用方应在主线程(SwiftUI 按钮 / AppKit 键盘回调均如此)。
    static func present(into store: DocumentStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        var types: [UTType] = []
        for ext in MediaImporter.allowedExtensions {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task { @MainActor in
                    do {
                        let asset = try MediaImporter.importAsset(from: url)
                        store.dispatch(.importAsset(asset))
                    } catch {
                        print("[ImportPanel] 导入失败: \(error)")
                    }
                }
            }
        }
    }
}
