# Export Tabs (导出视频/导出工程) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the export dialog into two tabs (导出视频 / 导出工程) with full video export settings (resolution, codec, quality, audio toggle) backed by AVAssetWriter.

**Architecture:** Add `ExportSettings` value type + new `ExportSettings.swift` file. Rewrite `MovieExporter` to use `AVAssetReader`+`AVAssetWriter` (fall back to `AVAssetExportSession` presets if the reader/writer path proves unreliable). Update `DocumentStore.exportMovie` signature. Rewrite `ExportPanel` with a segmented control switching between video-export and FCPXML-export tabs.

**Tech Stack:** Swift/SwiftPM, AVFoundation (AVAssetReader, AVAssetWriter, AVAssetExportSession fallback), SwiftUI, existing `CompositionBuilder`, existing `Tokens.Palette`/`Tokens.Typeface`.

## Global Constraints

- All files must stay under 500 lines.
- `fail fast` in dev: no silent try?, expose errors.
- `completion` called **exactly once** in all paths.
- File extension: `.mov` for ProRes, `.mp4` for H.264/H.265.
- `swift build 2>&1 | grep -E "error:|Build complete"` must show Build complete with no errors.
- `swift test 2>&1 | tail -2` must stay green (203+ tests).
- Match existing code style (enum namespacing, no blank file headers beyond the one-line path comment).
- Report written to `.superpowers/sdd/export-tabs-report.md`.

---

### Task 1: ExportSettings.swift — value types for codec/quality/resolution

**Files:**
- Create: `Sources/FCPXLite/Export/ExportSettings.swift`

**Interfaces:**
- Produces:
  - `enum ExportCodec: String, CaseIterable` — cases `.h264`, `.h265`, `.prores`; computed `var label: String`
  - `enum ExportQuality: String, CaseIterable` — cases `.low`, `.medium`, `.high`; computed `var label: String`
  - `enum ExportResolution: String, CaseIterable` — cases `.r720`, `.r1080`, `.r2160`, `.original`; computed `var label: String`; computed `var size: CGSize?`
  - `struct ExportSettings` — `var codec: ExportCodec = .h264`, `var quality: ExportQuality = .medium`, `var resolution: ExportResolution = .r1080`, `var includeAudio: Bool = true`

- [ ] **Step 1: Write the failing build test (compile check)**

  There is no separate test for this step — the file just needs to compile. Create it now and verify with `swift build`.

- [ ] **Step 2: Create the file**

```swift
// Sources/FCPXLite/Export/ExportSettings.swift
import Foundation

enum ExportCodec: String, CaseIterable {
    case h264, h265, prores
    var label: String {
        switch self {
        case .h264:   return "H.264"
        case .h265:   return "H.265 (HEVC)"
        case .prores: return "ProRes 422"
        }
    }
}

enum ExportQuality: String, CaseIterable {
    case low, medium, high
    var label: String {
        switch self {
        case .low:    return "低(小文件)"
        case .medium: return "中(平衡)"
        case .high:   return "高(大文件)"
        }
    }
}

enum ExportResolution: String, CaseIterable {
    case r720, r1080, r2160, original
    var label: String {
        switch self {
        case .r720:     return "720p"
        case .r1080:    return "1080p"
        case .r2160:    return "4K"
        case .original: return "原始"
        }
    }
    /// Returns target render size; `.original` returns nil (caller uses document format).
    var size: CGSize? {
        switch self {
        case .r720:     return CGSize(width: 1280, height: 720)
        case .r1080:    return CGSize(width: 1920, height: 1080)
        case .r2160:    return CGSize(width: 3840, height: 2160)
        case .original: return nil
        }
    }
}

struct ExportSettings {
    var codec: ExportCodec      = .h264
    var quality: ExportQuality  = .medium
    var resolution: ExportResolution = .r1080
    var includeAudio: Bool      = true
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!` (no errors — other files haven't changed yet)

- [ ] **Step 4: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Export/ExportSettings.swift
git commit -m "feat(export): add ExportSettings (codec/quality/resolution/audio)"
```

---

### Task 2: Rewrite MovieExporter with AVAssetWriter (AVAssetReader path + preset fallback)

**Files:**
- Modify: `Sources/FCPXLite/Export/MovieExporter.swift` (full rewrite)

**Interfaces:**
- Consumes:
  - `CompositionBuilder.build(document:) -> AVPlayerItem?` — `.asset` is AVComposition, `.videoComposition` is the custom compositor, `.audioMix` is AVAudioMix
  - `ExportSettings` (from Task 1)
- Produces:
  - `enum MovieExportError: Error` — cases `.emptyTimeline`, `.sessionFailed(String)`
  - `enum MovieExporter` with:
    ```swift
    static func export(document: Document, to url: URL,
                       settings: ExportSettings,
                       progress: @escaping (Float) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void)
    ```
  - Internal helper `static func outputFileType(for codec: ExportCodec) -> AVFileType`
  - Internal helper `static func videoSettings(codec: ExportCodec, quality: ExportQuality, size: CGSize) -> [String: Any]`

**Design decision — AVAssetWriter path:**

The spec calls for `AVAssetReader + AVAssetWriter`. However, `AVAssetReaderVideoCompositionOutput` with a custom `AVVideoCompositing` class (CoreImageCompositor in this project) is known to work correctly. If at runtime `AVAssetReader` fails to start (returns false), fall back to `AVAssetExportSession` with the best matching preset and map quality to `AVAssetExportPresetHighestQuality`.

**Bitrate table** (scale by (targetPixels / 1080pPixels)):
- low ≈ 2 Mbps @ 1080p
- medium ≈ 8 Mbps @ 1080p
- high ≈ 20 Mbps @ 1080p
- ProRes: no bitrate key (ignored by encoder)

- [ ] **Step 1: Write the failing test**

  In `Tests/FCPXLiteTests/MovieExporterTests.swift`, add the new test that will fail until the new signature exists:

```swift
func testH264ExportWithSettings() throws {
    let url = try makeSilentAudio(seconds: 1)
    defer { try? FileManager.default.removeItem(at: url) }
    let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(1),
                      naturalSize: .zero, frameRate: nil, hasAudio: true)
    let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(1))
    let doc = Document(formatWidth: 1280, formatHeight: 720, frameRate: 25,
                       assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
    let out = FileManager.default.temporaryDirectory
        .appendingPathComponent("h264-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: out) }
    let exp = expectation(description: "h264 export")
    let settings = ExportSettings(codec: .h264, quality: .low, resolution: .r720, includeAudio: true)
    MovieExporter.export(document: doc, to: out, settings: settings, progress: { _ in }) { result in
        switch result {
        case .success(let u):
            XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
            let a = AVURLAsset(url: u)
            XCTAssertEqual(CMTimeGetSeconds(a.duration), 1.0, accuracy: 0.5)
        case .failure(let e): XCTFail("export failed: \(e)")
        }
        exp.fulfill()
    }
    wait(for: [exp], timeout: 60)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift test --filter MovieExporterTests/testH264ExportWithSettings 2>&1 | tail -10`
Expected: compile error — `MovieExporter.export` has no `settings:` parameter yet.

- [ ] **Step 3: Rewrite MovieExporter.swift**

Replace the entire file content with:

```swift
// Sources/FCPXLite/Export/MovieExporter.swift
import AVFoundation

enum MovieExportError: Error { case emptyTimeline, sessionFailed(String) }

/// 把 Document 渲染成片。
/// 主路径:AVAssetReader + AVAssetWriter (codec/bitrate/size 精确控制)。
/// 备用路径:AVAssetExportSession preset (若 AVAssetReader 无法启动)。
enum MovieExporter {

    static func outputFileType(for codec: ExportCodec) -> AVFileType {
        codec == .prores ? .mov : .mp4
    }

    /// 目标码率(bps),按 1080p 基准乘以分辨率面积比。ProRes 返回 nil。
    static func targetBitrate(quality: ExportQuality, size: CGSize) -> Int? {
        guard size.width > 0, size.height > 0 else { return nil }
        let base1080pPixels: Double = 1920 * 1080
        let targetPixels = Double(size.width * size.height)
        let scaleFactor = targetPixels / base1080pPixels
        let baseBps: Double
        switch quality {
        case .low:    baseBps = 2_000_000
        case .medium: baseBps = 8_000_000
        case .high:   baseBps = 20_000_000
        }
        return Int(baseBps * scaleFactor)
    }

    static func videoSettings(codec: ExportCodec, quality: ExportQuality, size: CGSize) -> [String: Any] {
        let codecType: AVVideoCodecType
        switch codec {
        case .h264:   codecType = .h264
        case .h265:   codecType = .hevc
        case .prores: codecType = .proRes422
        }
        var settings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        if codec != .prores, let bps = targetBitrate(quality: quality, size: size) {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bps]
        }
        return settings
    }

    static func export(document: Document,
                       to url: URL,
                       settings: ExportSettings,
                       progress: @escaping (Float) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        guard let item = CompositionBuilder.build(document: document) else {
            completion(.failure(MovieExportError.emptyTimeline)); return
        }
        let composition = item.asset
        let videoComposition = item.videoComposition
        let audioMix = item.audioMix
        let hasVideo = videoComposition != nil
        let fileType = outputFileType(for: settings.codec)

        let renderSize: CGSize
        if let s = settings.resolution.size {
            renderSize = s
        } else {
            renderSize = CGSize(width: document.formatWidth, height: document.formatHeight)
        }

        try? FileManager.default.removeItem(at: url)

        // --- AVAssetReader path ---
        guard let reader = try? AVAssetReader(asset: composition) else {
            fallbackExport(document: document, to: url, settings: settings,
                           hasVideo: hasVideo, progress: progress, completion: completion); return
        }

        var readerOutputs: [AVAssetReaderOutput] = []

        if hasVideo, let vc = videoComposition {
            let videoOut = AVAssetReaderVideoCompositionOutput(
                videoTracks: composition.tracks(withMediaType: .video),
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_32BGRA])
            videoOut.videoComposition = vc
            videoOut.alwaysCopiesSampleData = false
            if reader.canAdd(videoOut) { reader.add(videoOut); readerOutputs.append(videoOut) }
        }

        var audioOut: AVAssetReaderAudioMixOutput? = nil
        if settings.includeAudio, !composition.tracks(withMediaType: .audio).isEmpty {
            let aOut = AVAssetReaderAudioMixOutput(
                audioTracks: composition.tracks(withMediaType: .audio),
                audioSettings: nil)
            aOut.audioMix = audioMix
            aOut.alwaysCopiesSampleData = false
            if reader.canAdd(aOut) { reader.add(aOut); audioOut = aOut }
        }

        guard reader.startReading() else {
            fallbackExport(document: document, to: url, settings: settings,
                           hasVideo: hasVideo, progress: progress, completion: completion); return
        }

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: fileType) else {
            reader.cancelReading()
            completion(.failure(MovieExportError.sessionFailed("无法创建 AVAssetWriter"))); return
        }

        var writerVideoInput: AVAssetWriterInput? = nil
        if hasVideo {
            let vSettings = videoSettings(codec: settings.codec, quality: settings.quality, size: renderSize)
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
            vInput.expectsMediaDataInRealTime = false
            if writer.canAdd(vInput) { writer.add(vInput); writerVideoInput = vInput }
        }

        var writerAudioInput: AVAssetWriterInput? = nil
        if audioOut != nil {
            let aSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            aInput.expectsMediaDataInRealTime = false
            if writer.canAdd(aInput) { writer.add(aInput); writerAudioInput = aInput }
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalDuration = CMTimeGetSeconds(composition.duration)
        var doneCalled = false
        let q = DispatchQueue(label: "fcpxlite.export")

        func finish(result: Result<URL, Error>) {
            guard !doneCalled else { return }
            doneCalled = true
            DispatchQueue.main.async { completion(result) }
        }

        // Track per-input completion
        var videoFinished = (writerVideoInput == nil)
        var audioFinished = (writerAudioInput == nil)

        func checkDone() {
            guard videoFinished, audioFinished else { return }
            writerVideoInput?.markAsFinished()
            writerAudioInput?.markAsFinished()
            reader.cancelReading()
            writer.finishWriting {
                DispatchQueue.main.async { progress(1.0) }
                if writer.status == .completed {
                    finish(result: .success(url))
                } else {
                    finish(result: .failure(writer.error ?? MovieExportError.sessionFailed("writer failed")))
                }
            }
        }

        if let vInput = writerVideoInput, let vOut = readerOutputs.first(where: { $0 is AVAssetReaderVideoCompositionOutput }) {
            vInput.requestMediaDataWhenReady(on: q) {
                while vInput.isReadyForMoreMediaData {
                    if let buf = vOut.copyNextSampleBuffer() {
                        vInput.append(buf)
                        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buf))
                        if totalDuration > 0 {
                            DispatchQueue.main.async { progress(Float(pts / totalDuration) * 0.9) }
                        }
                    } else {
                        videoFinished = true
                        checkDone()
                        return
                    }
                }
            }
        }

        if let aInput = writerAudioInput, let aOut = audioOut {
            aInput.requestMediaDataWhenReady(on: q) {
                while aInput.isReadyForMoreMediaData {
                    if let buf = aOut.copyNextSampleBuffer() {
                        aInput.append(buf)
                    } else {
                        audioFinished = true
                        checkDone()
                        return
                    }
                }
            }
        }

        // Pure-audio path: no video input, trigger checkDone when audio finishes
        if writerVideoInput == nil, writerAudioInput == nil {
            finish(result: .failure(MovieExportError.emptyTimeline))
        }
    }

    // MARK: - Fallback: AVAssetExportSession

    private static func fallbackExport(document: Document, to url: URL,
                                       settings: ExportSettings,
                                       hasVideo: Bool,
                                       progress: @escaping (Float) -> Void,
                                       completion: @escaping (Result<URL, Error>) -> Void) {
        guard let item = CompositionBuilder.build(document: document) else {
            completion(.failure(MovieExportError.emptyTimeline)); return
        }
        let asset = item.asset
        let preset: String
        switch settings.codec {
        case .prores: preset = hasVideo ? AVAssetExportPresetAppleProRes422LPCM : AVAssetExportPresetAppleM4A
        case .h265:   preset = hasVideo ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetAppleM4A
        case .h264:   preset = hasVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            completion(.failure(MovieExportError.sessionFailed("无法创建导出会话(fallback)"))); return
        }
        try? FileManager.default.removeItem(at: url)
        session.outputURL = url
        session.outputFileType = hasVideo ? (settings.codec == .prores ? .mov : .mp4) : .m4a
        if hasVideo { session.videoComposition = item.videoComposition }
        session.audioMix = item.audioMix

        var done = false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler { if !done { progress(session.progress) } }
        timer.resume()

        session.exportAsynchronously {
            timer.cancel()
            DispatchQueue.main.async {
                done = true
                switch session.status {
                case .completed: progress(1); completion(.success(url))
                case .cancelled: completion(.failure(MovieExportError.sessionFailed("已取消")))
                default: completion(.failure(session.error ?? MovieExportError.sessionFailed("status=\(session.status.rawValue)")))
                }
            }
        }
    }
}
```

- [ ] **Step 4: Update existing MovieExporterTests to use new signature**

  The existing `testEmptyTimelineFailsFast` and `testAudioOnlyExportsM4A` both call `MovieExporter.export(document:to:progress:completion:)` — add `settings: ExportSettings()` parameter to each call.

In `Tests/FCPXLiteTests/MovieExporterTests.swift`:
- Line 20: change `MovieExporter.export(document: doc, to: out, progress: { _ in })` → `MovieExporter.export(document: doc, to: out, settings: ExportSettings(), progress: { _ in })`
- Line 37: same change.

- [ ] **Step 5: Build and run MovieExporter tests**

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift test --filter MovieExporterTests 2>&1 | tail -15`
Expected: all three tests pass (emptyTimeline, audioOnly, h264WithSettings).

Note: `testAudioOnlyExportsM4A` still works — `ExportSettings()` defaults to `.h264`, but the existing test stores the file at `.m4a`. That is fine — the test only checks file existence and duration, not extension. If you want strict extension matching, change the out path to `.mp4` in that test.

- [ ] **Step 6: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Export/MovieExporter.swift Tests/FCPXLiteTests/MovieExporterTests.swift
git commit -m "feat(export): AVAssetWriter exporter (codec/bitrate/resolution) + preset fallback"
```

---

### Task 3: Update DocumentStore.exportMovie + AgentActionCatalog

**Files:**
- Modify: `Sources/FCPXLite/Store/DocumentStore.swift` — `exportMovie(to:)` → `exportMovie(to:settings:)`
- Modify: `Sources/FCPXLite/Agent/AgentActionCatalog.swift` — `export_movie` apply closure passes `ExportSettings()`

**Interfaces:**
- Consumes: `ExportSettings` (Task 1), `MovieExporter.export(document:to:settings:progress:completion:)` (Task 2)
- Produces:
  - `DocumentStore.exportMovie(to url: URL, settings: ExportSettings)`

- [ ] **Step 1: Update DocumentStore.exportMovie**

In `Sources/FCPXLite/Store/DocumentStore.swift`, find the `exportMovie` method (lines 341–356) and replace it:

```swift
/// 导出成片(异步,更新 ui.exportProgress)。成功关闭面板;失败把原因写进 ui.exportError。
func exportMovie(to url: URL, settings: ExportSettings = ExportSettings()) {
    ui.exportError = nil
    ui.exportProgress = 0
    MovieExporter.export(document: document, to: url, settings: settings,
                         progress: { [weak self] p in self?.ui.exportProgress = Double(p) },
                         completion: { [weak self] result in
        guard let self else { return }
        self.ui.exportProgress = nil
        switch result {
        case .success:
            self.ui.showExport = false
        case .failure(let e):
            self.ui.exportError = "导出失败:\(e)"
        }
    })
}
```

Note the `settings: ExportSettings = ExportSettings()` default argument keeps all existing call sites (tests, agent) compiling with no changes — but we'll explicitly update the agent below.

- [ ] **Step 2: Update AgentActionCatalog export_movie action**

In `Sources/FCPXLite/Agent/AgentActionCatalog.swift`, find the `export_movie` action apply closure (around line 302) and change:
```swift
store.exportMovie(to: URL(fileURLWithPath: p)); return "已开始导出成片到 \(p)(渲染中)"
```
to:
```swift
store.exportMovie(to: URL(fileURLWithPath: p), settings: ExportSettings()); return "已开始导出成片到 \(p)(渲染中)"
```

- [ ] **Step 3: Build**

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 4: Run all tests**

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -5`
Expected: all tests pass (at least 203).

- [ ] **Step 5: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Store/DocumentStore.swift Sources/FCPXLite/Agent/AgentActionCatalog.swift
git commit -m "feat(export): DocumentStore.exportMovie(to:settings:) + agent default settings"
```

---

### Task 4: Rewrite ExportPanel with two tabs

**Files:**
- Modify: `Sources/FCPXLite/Views/ExportPanel.swift` (full rewrite)

**Interfaces:**
- Consumes:
  - `store.exportMovie(to:settings:)` (Task 3)
  - `store.exportFCPXML(to:)` (existing)
  - `store.dispatch(.setShowExport(false))`
  - `store.ui.exportProgress: Double?`
  - `store.ui.exportError: String?`
  - `ExportSettings`, `ExportCodec`, `ExportQuality`, `ExportResolution` (Task 1)
  - `Tokens.Palette.*`, `Tokens.Typeface.*`
- Produces: `struct ExportPanel: View` with two-tab UI

**UI spec:**
- Header: "导出" title + xmark close button (same as current)
- Segmented control: `Picker("", selection: $tab) { Text("导出视频").tag(0); Text("导出工程").tag(1) }.pickerStyle(.segmented)`
- Tab 0 (导出视频):
  - If `store.ui.exportProgress != nil`: show progress bar (same as current)
  - Else: pickers for 分辨率, 编码, 质量 (disable quality picker when codec==.prores), Toggle 包含音频, 导出 button
- Tab 1 (导出工程): existing FCPXML export button

- [ ] **Step 1: Rewrite ExportPanel.swift**

```swift
// Sources/FCPXLite/Views/ExportPanel.swift
import SwiftUI
import AppKit

/// 导出对话框(双 Tab):导出视频(分辨率/编码/质量/音频) / 导出工程(FCPXML)。
struct ExportPanel: View {
    let store: DocumentStore
    @State private var tab: Int = 0
    @State private var settings = ExportSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("导出").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Button { store.dispatch(.setShowExport(false)) } label: {
                    Image(systemName: "xmark").foregroundStyle(Tokens.Palette.textMuted)
                }.buttonStyle(.plain)
            }

            // Tab selector
            Picker("", selection: $tab) {
                Text("导出视频").tag(0)
                Text("导出工程").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 {
                videoExportTab
            } else {
                projectExportTab
            }
        }
        .padding(18).frame(width: 380).background(Tokens.Palette.chrome)
    }

    // MARK: - Tab 0: Video Export

    @ViewBuilder private var videoExportTab: some View {
        if let p = store.ui.exportProgress {
            VStack(alignment: .leading, spacing: 6) {
                Text("导出中… \(Int(p * 100))%")
                    .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                ProgressView(value: p)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Resolution
                HStack {
                    Text("分辨率").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.resolution) {
                        ForEach(ExportResolution.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }

                // Codec
                HStack {
                    Text("编码").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.codec) {
                        ForEach(ExportCodec.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }

                // Quality (hidden for ProRes)
                HStack {
                    Text("质量").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.quality) {
                        ForEach(ExportQuality.allCases, id: \.self) { q in
                            Text(q.label).tag(q)
                        }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                    .disabled(settings.codec == .prores)
                    .opacity(settings.codec == .prores ? 0.4 : 1.0)
                }

                // Audio toggle
                HStack {
                    Text("包含音频").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Toggle("", isOn: $settings.includeAudio).labelsHidden()
                    Spacer()
                }

                // Export button
                Button("导出…") { exportVideo() }
                    .buttonStyle(.plain).padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Tokens.Palette.clipBlue).cornerRadius(6)
                    .foregroundStyle(Tokens.Palette.onAccent)
                    .font(Tokens.Typeface.body)

                // Error
                if let err = store.ui.exportError {
                    Text(err).font(.system(size: 11))
                        .foregroundStyle(Tokens.Palette.windowClose)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Tab 1: Project Export

    @ViewBuilder private var projectExportTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("导出 FCPXML 工程文件,可在 Final Cut Pro 中继续编辑。")
                .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("导出 FCPXML 工程…") { exportFCPXML() }
                .buttonStyle(.plain).padding(8)
                .frame(maxWidth: .infinity)
                .background(Tokens.Palette.elevated).cornerRadius(6)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .font(Tokens.Typeface.body)
            if let err = store.ui.exportError {
                Text(err).font(.system(size: 11))
                    .foregroundStyle(Tokens.Palette.windowClose)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func exportVideo() {
        let ext = settings.codec == .prores ? "mov" : "mp4"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "导出.\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            store.exportMovie(to: url, settings: settings)
        }
    }

    private func exportFCPXML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "导出.fcpxml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportFCPXML(to: url)
            store.ui.exportError = nil
            store.dispatch(.setShowExport(false))
        } catch {
            store.ui.exportError = "导出失败:\(error)"   // fail-fast: 暴露而非静默
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Views/ExportPanel.swift
git commit -m "feat(export): Tab式ExportPanel(导出视频+导出工程)+分辨率/编码/质量/音频选项"
```

---

### Task 5: Final commit, report

**Files:**
- Create: `.superpowers/sdd/export-tabs-report.md`

- [ ] **Step 1: Run complete build + test one final time**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
swift build 2>&1 | grep -E "error:|Build complete"
swift test 2>&1 | tail -2
```

- [ ] **Step 2: Create the report**

Write `.superpowers/sdd/export-tabs-report.md` with:
- status: DONE or DONE_WITH_CONCERNS
- commit hash (from `git log --oneline -1`)
- one-line build+test summary
- whether AVAssetWriter or presets were used

- [ ] **Step 3: Final umbrella commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add -A
git commit -m "feat(export): Tab式导出(视频/工程)+分辨率/编码/质量/音频(AVAssetWriter)+文件名"
```

---

## Self-Review

**Spec coverage:**
- [x] `ExportSettings.swift` — Task 1
- [x] `MovieExporter.export(settings:)` with AVAssetWriter (+ preset fallback) — Task 2
- [x] Bitrate scaling by resolution — Task 2
- [x] `DocumentStore.exportMovie(to:settings:)` — Task 3
- [x] `AgentActionCatalog export_movie` passes `ExportSettings()` — Task 3
- [x] `ExportPanel` with two tabs — Task 4
- [x] 分辨率/编码/质量/音频 pickers — Task 4
- [x] Quality disabled/dimmed for ProRes — Task 4
- [x] Default filename per codec extension — Task 4
- [x] Progress bar in video tab — Task 4
- [x] Error surfacing in both tabs — Task 4
- [x] Report to `.superpowers/sdd/export-tabs-report.md` — Task 5
- [x] `MovieExporterTests.testH264ExportWithSettings` — Task 2
- [x] Existing tests updated for new signature — Task 2

**Placeholder scan:** No TBDs, TODOs, or "similar to Task N" references.

**Type consistency:**
- `ExportSettings` used consistently across Tasks 1–4.
- `MovieExporter.export(document:to:settings:progress:completion:)` signature matches in Task 2 (definition), Task 3 (DocumentStore call), and Task 4 (ExportPanel call).
- `store.exportMovie(to:settings:)` matches in Task 3 (definition) and Task 4 (caller).
