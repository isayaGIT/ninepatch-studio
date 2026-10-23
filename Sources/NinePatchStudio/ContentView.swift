import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

struct SliceInsets: Codable, Equatable {
    var top: Double = 24
    var left: Double = 24
    var bottom: Double = 24
    var right: Double = 24
}

struct AnimationFrameConfig: Codable {
    var fileName: String
    var duration: Double
}

struct AnimationExport: Codable {
    var format = "ninepatch-studio/animation-v1"
    var sourceFileName: String
    var sourceWidth: Int
    var sourceHeight: Int
    var frameCount: Int
    var totalDuration: Double
    var frames: [AnimationFrameConfig]
    var stretchInsets: SliceInsets
    var contentInsets: SliceInsets
    var integrationNote = "Exported PNG frames. Add them to the app asset catalog and map frame file names to NinePatchFrameAnimation frameNames."
}

struct LoadedFrame {
    var image: NSImage
    var cgImage: CGImage
    var duration: Double
}

struct ContentView: View {
    @State private var frames: [LoadedFrame] = []
    @State private var imageURL: URL?
    @State private var pixelSize = CGSize(width: 1, height: 1)
    @State private var insets = SliceInsets()
    @State private var contentInsets = SliceInsets(top: 12, left: 14, bottom: 12, right: 14)
    @State private var previewWidth: Double = 360
    @State private var previewHeight: Double = 180
    @State private var previewText = "This is a nine-slice preview. Resize it to check whether the corners and edges remain intact."
    @State private var showImporter = false
    @State private var currentFrame = 0
    @State private var isPlaying = true
    @State private var status = "Drop a GIF to begin · PNG/JPEG also supported"
    @State private var showContentInsets = true

    private var currentImage: NSImage? { frames.indices.contains(currentFrame) ? frames[currentFrame].image : nil }
    private var totalDuration: Double { frames.reduce(0) { $0 + $1.duration } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("ANIMATED SOURCE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !frames.isEmpty {
                            Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px · \(frames.count) frames")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    sourceCanvas
                    if !frames.isEmpty {
                        HStack(spacing: 10) {
                            Button { isPlaying.toggle() } label: { Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") }
                                .buttonStyle(.bordered)
                            Slider(value: Binding(get: { Double(currentFrame) }, set: { currentFrame = min(frames.count - 1, max(0, Int($0))) }), in: 0...Double(max(0, frames.count - 1)), step: 1)
                            Text("\(currentFrame + 1)/\(frames.count)").font(.caption.monospacedDigit()).frame(width: 55, alignment: .trailing)
                        }
                    }
                    HStack(spacing: 8) {
                        Label("Stretch boundary", systemImage: "arrow.left.and.right").foregroundStyle(.cyan)
                        if showContentInsets { Label("Content safe area", systemImage: "text.alignleft").foregroundStyle(.orange) }
                    }.font(.caption2)
                    Text("The same nine-slice boundaries apply to every frame. GIF frame timing is preserved in export metadata.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector.frame(width: 340).padding(18).background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            }
            Divider()
            HStack {
                Circle().fill(frames.isEmpty ? Color.secondary : Color.green).frame(width: 7, height: 7)
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("NinePatch Studio · GIF-first editor").font(.caption2).foregroundStyle(.tertiary)
            }.padding(.horizontal, 16).padding(.vertical, 9)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadBundledCatBubbleIfNeeded() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gif, .png, .jpeg, .tiff, .webP, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                if urls.count > 1 { loadPNGSequence(urls) }
                else if let url = urls.first { loadAnimation(url) }
            case .failure(let error): status = "Import failed: \(error.localizedDescription)"
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard !providers.isEmpty else { return false }
            let group = DispatchGroup()
            let urlsLock = NSLock()
            var urls: [URL] = []
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { urlsLock.lock(); urls.append(url); urlsLock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                if sorted.count > 1 { loadPNGSequence(sorted) }
                else if let url = sorted.first { loadAnimation(url) }
            }
            return true
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled && frames.count > 1 {
                let delay = frames.indices.contains(currentFrame) ? frames[currentFrame].duration : 0.1
                try? await Task.sleep(for: .seconds(max(0.02, delay)))
                if Task.isCancelled { break }
                currentFrame = (currentFrame + 1) % frames.count
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("NinePatch Studio").font(.headline)
                Text("Animated bubble · nine-slice editor").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showImporter = true } label: { Label("Drop / Import GIF", systemImage: "film") }.buttonStyle(.bordered)
            Button { resetInsets() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }.disabled(frames.isEmpty)
            Button { exportFrames() } label: { Label("Export Frames + JSON", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent).disabled(frames.isEmpty)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var sourceCanvas: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
                if let image = currentImage {
                    let fitted = fittedRect(imageSize: pixelSize, in: geo.size)
                    Image(nsImage: image).resizable().interpolation(.high).frame(width: fitted.width, height: fitted.height).position(x: fitted.midX, y: fitted.midY)
                    guideOverlay(in: fitted, canvas: geo.size)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "film.stack").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text("Drop an animated bubble GIF").font(.title3.weight(.medium))
                        Text("Animated WebP or multiple PNG frames also work when supported").font(.callout).foregroundStyle(.secondary)
                        Button("Choose Animation…") { showImporter = true }.buttonStyle(.borderedProminent)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12)).coordinateSpace(name: "sourceCanvas")
        }.frame(minHeight: 350)
    }

    @ViewBuilder private func guideOverlay(in rect: CGRect, canvas: CGSize) -> some View {
        let sx = rect.width / max(1, pixelSize.width), sy = rect.height / max(1, pixelSize.height)
        let x1 = rect.minX + insets.left * sx, x2 = rect.maxX - insets.right * sx
        let y1 = rect.minY + insets.top * sy, y2 = rect.maxY - insets.bottom * sy
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: x1, y: rect.minY)); p.addLine(to: CGPoint(x: x1, y: rect.maxY))
                p.move(to: CGPoint(x: x2, y: rect.minY)); p.addLine(to: CGPoint(x: x2, y: rect.maxY))
                p.move(to: CGPoint(x: rect.minX, y: y1)); p.addLine(to: CGPoint(x: rect.maxX, y: y1))
                p.move(to: CGPoint(x: rect.minX, y: y2)); p.addLine(to: CGPoint(x: rect.maxX, y: y2))
            }.stroke(.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            if showContentInsets {
                let cx1 = rect.minX + contentInsets.left * sx, cx2 = rect.maxX - contentInsets.right * sx
                let cy1 = rect.minY + contentInsets.top * sy, cy2 = rect.maxY - contentInsets.bottom * sy
                Path { p in
                    p.move(to: CGPoint(x: cx1, y: rect.minY)); p.addLine(to: CGPoint(x: cx1, y: rect.maxY))
                    p.move(to: CGPoint(x: cx2, y: rect.minY)); p.addLine(to: CGPoint(x: cx2, y: rect.maxY))
                    p.move(to: CGPoint(x: rect.minX, y: cy1)); p.addLine(to: CGPoint(x: rect.maxX, y: cy1))
                    p.move(to: CGPoint(x: rect.minX, y: cy2)); p.addLine(to: CGPoint(x: rect.maxX, y: cy2))
                }.stroke(.orange.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            dragHandle(position: CGPoint(x: x1, y: rect.midY)) { p in insets.left = pixelValue(p.x - rect.minX, scale: sx, limit: pixelSize.width - insets.right) }
            dragHandle(position: CGPoint(x: x2, y: rect.midY)) { p in insets.right = pixelValue(rect.maxX - p.x, scale: sx, limit: pixelSize.width - insets.left) }
            dragHandle(position: CGPoint(x: rect.midX, y: y1)) { p in insets.top = pixelValue(p.y - rect.minY, scale: sy, limit: pixelSize.height - insets.bottom) }
            dragHandle(position: CGPoint(x: rect.midX, y: y2)) { p in insets.bottom = pixelValue(rect.maxY - p.y, scale: sy, limit: pixelSize.height - insets.top) }
        }.frame(width: canvas.width, height: canvas.height)
    }

    private func dragHandle(position: CGPoint, onDrag: @escaping (CGPoint) -> Void) -> some View {
        Circle().fill(.cyan).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 1.5))
            .position(position).contentShape(Rectangle().inset(by: -12))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("sourceCanvas")).onChanged { onDrag($0.location) })
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                groupTitle("STRETCH INSETS", subtitle: "Shared across every animation frame")
                insetEditor(title: "Top", value: $insets.top, max: pixelSize.height)
                insetEditor(title: "Left", value: $insets.left, max: pixelSize.width)
                insetEditor(title: "Bottom", value: $insets.bottom, max: pixelSize.height)
                insetEditor(title: "Right", value: $insets.right, max: pixelSize.width)
                Divider()
                Toggle("Show content safe area", isOn: $showContentInsets).font(.subheadline)
                if showContentInsets {
                    groupTitle("CONTENT SAFE AREA", subtitle: "Suggested text padding in source pixels")
                    insetEditor(title: "Top", value: $contentInsets.top, max: pixelSize.height)
                    insetEditor(title: "Left", value: $contentInsets.left, max: pixelSize.width)
                    insetEditor(title: "Bottom", value: $contentInsets.bottom, max: pixelSize.height)
                    insetEditor(title: "Right", value: $contentInsets.right, max: pixelSize.width)
                }
                Divider()
                groupTitle("LIVE PREVIEW", subtitle: "Animation plays at original frame timing")
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text("Width"); Spacer(); Text("\(Int(previewWidth)) pt").monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: $previewWidth, in: 120...520, step: 10)
                    HStack { Text("Height"); Spacer(); Text("\(Int(previewHeight)) pt").monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: $previewHeight, in: 60...320, step: 10)
                }.font(.caption)
                TextField("Preview text", text: $previewText, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .underPageBackgroundColor))
                    if let image = currentImage {
                        Image(nsImage: image).resizable(capInsets: EdgeInsets(top: points(insets.top, vertical: true), leading: points(insets.left, vertical: false), bottom: points(insets.bottom, vertical: true), trailing: points(insets.right, vertical: false)), resizingMode: .stretch)
                            .frame(width: previewWidth, height: previewHeight)
                            .overlay {
                                Text(previewText).font(.system(size: 13)).foregroundStyle(.primary)
                                    .padding(.horizontal, points(contentInsets.left, vertical: false) + 8)
                                    .padding(.vertical, points(contentInsets.top, vertical: true) + 4)
                                    .frame(width: previewWidth, height: previewHeight).clipped()
                            }
                    } else { Text("Import an animation to preview").font(.caption).foregroundStyle(.secondary) }
                }.frame(height: min(340, previewHeight + 24)).frame(maxWidth: .infinity).clipped()
                Text("Export creates numbered PNG frames plus JSON containing dimensions, frame timing and slice insets.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func groupTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func insetEditor(title: String, value: Binding<Double>, max: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).frame(width: 58, alignment: .leading)
            Slider(value: value, in: 0...Swift.max(0, Double(max)), step: 1)
            TextField("0", value: value, format: .number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder).frame(width: 54).multilineTextAlignment(.trailing)
        }
    }

    private func fittedRect(imageSize: CGSize, in size: CGSize) -> CGRect {
        let padding: CGFloat = 24
        let scale = min((size.width - padding * 2) / max(1, imageSize.width), (size.height - padding * 2) / max(1, imageSize.height))
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func pixelValue(_ coordinate: CGFloat, scale: CGFloat, limit: CGFloat) -> Double {
        min(max(0, Double(coordinate / max(0.0001, scale))), max(0, Double(limit)))
    }

    private func points(_ pixels: Double, vertical: Bool) -> CGFloat {
        let dimension = vertical ? pixelSize.height : pixelSize.width
        let pointDimension = vertical ? (currentImage?.size.height ?? dimension) : (currentImage?.size.width ?? dimension)
        return CGFloat(pixels) * pointDimension / max(1, dimension)
    }

    private func loadBundledCatBubbleIfNeeded() {
        guard frames.isEmpty else { return }
        guard let files = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: "DefaultCatBubbleFrames")?
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }),
              !files.isEmpty else {
            status = "Default cat bubble sample missing from app bundle. Rebuild the app."
            return
        }
        loadPNGSequence(files)
        if !frames.isEmpty {
            status = "Default cat bubble loaded · \(files.count) frames"
        }
    }

    private func loadAnimation(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            status = "Could not decode this file. Try GIF, WebP, PNG or JPEG."; return
        }
        var decoded: [LoadedFrame] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gif?[kCGImagePropertyGIFDelayTime] as? Double
            let delay = max(0.02, (unclamped ?? clamped).flatMap { $0 > 0 ? $0 : nil } ?? 0.1)
            decoded.append(LoadedFrame(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), cgImage: cg, duration: delay))
        }
        guard let first = decoded.first else { status = "No readable frames found."; return }
        frames = decoded; currentFrame = 0; imageURL = url
        pixelSize = CGSize(width: first.cgImage.width, height: first.cgImage.height)
        setDefaultInsets()
        status = "Loaded \(url.lastPathComponent) · \(decoded.count) frames · \(String(format: "%.2f", decoded.reduce(0) { $0 + $1.duration })) sec"
    }

    private func loadPNGSequence(_ urls: [URL]) {
        var decoded: [LoadedFrame] = []
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            decoded.append(LoadedFrame(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), cgImage: cg, duration: 0.1))
        }
        guard let first = decoded.first else { status = "No readable images found in selection."; return }
        guard decoded.allSatisfy({ $0.cgImage.width == first.cgImage.width && $0.cgImage.height == first.cgImage.height }) else {
            status = "PNG sequence frames must all have the same dimensions."; return
        }
        frames = decoded; currentFrame = 0; imageURL = urls.first
        pixelSize = CGSize(width: first.cgImage.width, height: first.cgImage.height)
        setDefaultInsets()
        status = "Loaded PNG sequence · \(decoded.count) frames · 0.10 sec/frame"
    }

    private func setDefaultInsets() {
        insets = SliceInsets(top: min(24, Double(pixelSize.height) / 4), left: min(24, Double(pixelSize.width) / 4), bottom: min(24, Double(pixelSize.height) / 4), right: min(24, Double(pixelSize.width) / 4))
        contentInsets = SliceInsets(top: min(12, Double(pixelSize.height) / 8), left: min(14, Double(pixelSize.width) / 8), bottom: min(12, Double(pixelSize.height) / 8), right: min(14, Double(pixelSize.width) / 8))
    }

    private func resetInsets() { setDefaultInsets(); status = "Stretch boundaries reset" }

    private func exportFrames() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for exported animation frames"
        panel.message = "A new folder named NinePatchExport will be created inside the selected folder."
        panel.prompt = "Export Here"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let destination = parent.appendingPathComponent("NinePatchExport-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var configs: [AnimationFrameConfig] = []
            for (index, frame) in frames.enumerated() {
                let name = String(format: "frame_%04d.png", index)
                guard let rep = NSBitmapImageRep(cgImage: frame.cgImage).representation(using: .png, properties: [:]) else { throw NSError(domain: "NinePatchStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode frame \(index + 1) as PNG."]) }
                try rep.write(to: destination.appendingPathComponent(name), options: .atomic)
                configs.append(AnimationFrameConfig(fileName: name, duration: frame.duration))
            }
            let config = AnimationExport(sourceFileName: imageURL?.lastPathComponent ?? "animation", sourceWidth: Int(pixelSize.width), sourceHeight: Int(pixelSize.height), frameCount: frames.count, totalDuration: totalDuration, frames: configs, stretchInsets: insets, contentInsets: contentInsets)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: destination.appendingPathComponent("ninepatch-config.json"), options: .atomic)
            status = "Exported \(frames.count) PNG frames + JSON to \(destination.path)"
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }
}
