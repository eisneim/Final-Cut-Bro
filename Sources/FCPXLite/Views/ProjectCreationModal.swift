import SwiftUI

/// 创建项目弹窗:设名称 + 分辨率(720/1080/4K/自定义)+ 方向(横/竖)。
/// 自定义宽高须为 2 的倍数。确认 → dispatch(.createProject)。
struct ProjectCreationModal: View {
    let store: DocumentStore

    @State private var name = t("未命名项目")
    @State private var preset: ResPreset = .p1080
    @State private var portrait = false
    @State private var customW = "1920"
    @State private var customH = "1080"
    @State private var fps: Double = 25

    enum ResPreset: String, CaseIterable, Identifiable {
        case p720, p1080, p2160, custom
        var id: String { rawValue }
        var label: String { switch self { case .p720: return "720p"; case .p1080: return "1080p"; case .p2160: return "4K"; case .custom: return t("自定义") } }
        /// 横屏基准尺寸(竖屏时宽高对调)。custom 返回 nil。
        var landscape: (Int, Int)? {
            switch self {
            case .p720: return (1280, 720)
            case .p1080: return (1920, 1080)
            case .p2160: return (3840, 2160)
            case .custom: return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t("创建项目")).font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Button { store.dispatch(.setShowProjectModal(false)) } label: {
                    Image(systemName: "xmark").foregroundStyle(Tokens.Palette.textMuted)
                }.buttonStyle(.plain)
            }

            field(t("名称")) { TextField(t("项目名"), text: $name).textFieldStyle(.plain)
                .padding(7).background(Tokens.Palette.elevated).cornerRadius(5) }

            field(t("分辨率")) {
                Picker("", selection: $preset) {
                    ForEach(ResPreset.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().pickerStyle(.segmented)
            }

            if preset == .custom {
                HStack(spacing: 8) {
                    Text(t("宽")).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
                    TextField(t("宽"), text: $customW).textFieldStyle(.plain).frame(width: 70)
                        .padding(6).background(Tokens.Palette.elevated).cornerRadius(5)
                    Text(t("高")).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
                    TextField(t("高"), text: $customH).textFieldStyle(.plain).frame(width: 70)
                        .padding(6).background(Tokens.Palette.elevated).cornerRadius(5)
                    Text(t("(须为2的倍数)")).font(.system(size: 9)).foregroundStyle(Tokens.Palette.textMuted)
                }
            } else {
                Toggle(isOn: $portrait) {
                    Text(t("竖屏(宽高对调)")).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                }.toggleStyle(.checkbox)
            }

            field(t("帧率")) {
                Picker("", selection: $fps) {
                    Text("24").tag(24.0); Text("25").tag(25.0); Text("30").tag(30.0); Text("60").tag(60.0)
                }.labelsHidden().pickerStyle(.segmented)
            }

            Text(sizeSummary).font(.system(size: 11)).foregroundStyle(Tokens.Palette.textMuted)
            if let err = validationError {
                Text(err).font(.system(size: 11)).foregroundStyle(Tokens.Palette.windowClose)
            }

            HStack {
                Spacer()
                Button(t("创建")) { create() }
                    .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 6)
                    .background(validationError == nil ? Tokens.Palette.clipBlue : Tokens.Palette.elevated)
                    .foregroundStyle(Tokens.Palette.onAccent).cornerRadius(6)
                    .disabled(validationError != nil)
            }
        }
        .padding(18).frame(width: 380).background(Tokens.Palette.chrome)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            content()
        }
    }

    private var resolvedSize: (w: Int, h: Int)? {
        if preset == .custom {
            guard let w = Int(customW), let h = Int(customH) else { return nil }
            return (w, h)
        }
        guard let (lw, lh) = preset.landscape else { return nil }
        return portrait ? (lh, lw) : (lw, lh)
    }

    private var sizeSummary: String {
        guard let s = resolvedSize else { return t("尺寸无效") }
        return "输出尺寸:\(s.w) × \(s.h) @ \(Int(fps))fps"
    }

    private var validationError: String? {
        guard let s = resolvedSize else { return t("宽高必须是数字") }
        guard s.w >= 2, s.h >= 2 else { return t("宽高太小") }
        guard s.w % 2 == 0, s.h % 2 == 0 else { return t("宽高必须是 2 的倍数") }
        return nil
    }

    private func create() {
        guard let s = resolvedSize, validationError == nil else { return }
        let p = Project(name: name.isEmpty ? t("未命名项目") : name,
                        formatWidth: s.w, formatHeight: s.h, frameRate: fps)
        store.dispatch(.createProject(p))
        store.dispatch(.setShowProjectModal(false))
    }
}
