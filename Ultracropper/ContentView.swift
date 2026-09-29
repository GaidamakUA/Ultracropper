import AppKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum EditorMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case preview = "Preview"

    var id: Self { self }
}

enum Corner: CaseIterable, Identifiable {
    case topLeft, topRight, bottomRight, bottomLeft

    var id: Self { self }

    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        }
    }
}

struct NormalizedPoint: Equatable {
    var x: CGFloat
    var y: CGFloat
}

struct NormalizedQuad: Equatable {
    var topLeft = NormalizedPoint(x: 0, y: 0)
    var topRight = NormalizedPoint(x: 1, y: 0)
    var bottomRight = NormalizedPoint(x: 1, y: 1)
    var bottomLeft = NormalizedPoint(x: 0, y: 1)

    subscript(corner: Corner) -> NormalizedPoint {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomRight: bottomRight
            case .bottomLeft: bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }

    var points: [NormalizedPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }
}

struct ImageQuad {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
}

enum PerspectiveGeometry {
    static func isValid(_ quad: NormalizedQuad) -> Bool {
        let points = quad.points
        var direction: CGFloat = 0

        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let c = points[(index + 2) % points.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)

            guard abs(cross) > 0.0001 else { return false }
            if direction == 0 {
                direction = cross
            } else if direction * cross < 0 {
                return false
            }
        }

        return abs(signedArea(points)) > 0.0001
    }

    static func imageQuad(from quad: NormalizedQuad, extent: CGRect) -> ImageQuad {
        func point(_ value: NormalizedPoint) -> CGPoint {
            CGPoint(
                x: extent.minX + value.x * extent.width,
                y: extent.maxY - value.y * extent.height
            )
        }

        return ImageQuad(
            topLeft: point(quad.topLeft),
            topRight: point(quad.topRight),
            bottomRight: point(quad.bottomRight),
            bottomLeft: point(quad.bottomLeft)
        )
    }

    static func fittedRect(imageSize: CGSize, in container: CGSize, scale: CGFloat = 1) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }

        let fittedScale = min(container.width / imageSize.width, container.height / imageSize.height) * scale
        let size = CGSize(width: imageSize.width * fittedScale, height: imageSize.height * fittedScale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func viewPoint(_ point: NormalizedPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    static func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint {
        guard rect.width > 0, rect.height > 0 else { return NormalizedPoint(x: 0, y: 0) }
        return NormalizedPoint(
            x: min(max((point.x - rect.minX) / rect.width, 0), 1),
            y: min(max((point.y - rect.minY) / rect.height, 0), 1)
        )
    }

    static func outputFilename(for sourceURL: URL) -> String {
        sourceURL.deletingPathExtension().lastPathComponent + "_fixed.jpg"
    }

    private static func signedArea(_ points: [NormalizedPoint]) -> CGFloat {
        points.indices.reduce(0) { area, index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            return area + current.x * next.y - next.x * current.y
        } / 2
    }
}

@MainActor
final class ImageEditorModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var sourcePreview: NSImage?
    @Published var correctedPreview: NSImage?
    @Published var quad = NormalizedQuad()
    @Published var mode = EditorMode.edit
    @Published var errorMessage: String?

    private var sourceImage: CIImage?
    private let context = CIContext()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    var hasImage: Bool { sourceImage != nil }

    func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let loaded = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                throw EditorError.unreadableImage
            }

            let normalized = loaded.transformed(by: CGAffineTransform(
                translationX: -loaded.extent.minX,
                y: -loaded.extent.minY
            ))
            guard let preview = render(normalized) else { throw EditorError.renderFailed }

            sourceURL = url
            sourceImage = normalized
            sourcePreview = preview
            correctedPreview = nil
            quad = NormalizedQuad()
            mode = .edit
        } catch {
            show(error)
        }
    }

    func update(_ corner: Corner, to point: NormalizedPoint) {
        quad[corner] = point
        correctedPreview = nil
    }

    func selectMode(_ newMode: EditorMode) {
        guard newMode == .preview else {
            mode = .edit
            return
        }

        do {
            let image = try correctedImage()
            guard let preview = render(image) else { throw EditorError.renderFailed }
            correctedPreview = preview
            mode = .preview
        } catch {
            mode = .edit
            show(error)
        }
    }

    func save() {
        do {
            guard let sourceURL else { return }
            let image = try correctedImage()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.jpeg]
            panel.canCreateDirectories = true
            panel.directoryURL = sourceURL.deletingLastPathComponent()
            panel.nameFieldStringValue = PerspectiveGeometry.outputFilename(for: sourceURL)

            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try writeJPEG(image, to: destination)
        } catch {
            show(error)
        }
    }

    private func correctedImage() throws -> CIImage {
        guard let sourceImage else { throw EditorError.noImage }
        guard PerspectiveGeometry.isValid(quad) else { throw EditorError.invalidCorners }

        let points = PerspectiveGeometry.imageQuad(from: quad, extent: sourceImage.extent)
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = sourceImage
        filter.topLeft = points.topLeft
        filter.topRight = points.topRight
        filter.bottomRight = points.bottomRight
        filter.bottomLeft = points.bottomLeft

        guard let output = filter.outputImage, !output.extent.isEmpty, !output.extent.isInfinite else {
            throw EditorError.renderFailed
        }

        let translated = output.transformed(by: CGAffineTransform(
            translationX: -output.extent.minX,
            y: -output.extent.minY
        ))
        let background = CIImage(color: .white).cropped(to: translated.extent)
        return translated.composited(over: background)
    }

    private func render(_ image: CIImage) -> NSImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: image.extent.size)
    }

    private func writeJPEG(_ image: CIImage, to url: URL) throws {
        guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw EditorError.renderFailed
        }

        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { throw EditorError.saveFailed }
    }

    private func show(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

enum EditorError: LocalizedError {
    case noImage
    case unreadableImage
    case invalidCorners
    case renderFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noImage: "Open an image first."
        case .unreadableImage: "This image could not be opened."
        case .invalidCorners: "The four corners must form a non-crossing shape."
        case .renderFailed: "The corrected image could not be rendered."
        case .saveFailed: "The JPEG could not be saved."
        }
    }
}

struct ContentView: View {
    @StateObject private var editor = ImageEditorModel()
    @State private var isImporting = false
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        Group {
            if editor.hasImage {
                editorCanvas
            } else {
                ContentUnavailableView {
                    Label("Open an Image", systemImage: "photo")
                } description: {
                    Text("Choose an image, then drag its four corners.")
                } actions: {
                    Button("Open Image…") { isImporting = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .toolbar {
            ToolbarItemGroup {
                Button("Open", systemImage: "folder") { isImporting = true }
                    .keyboardShortcut("o")

                if editor.hasImage {
                    Picker("View", selection: Binding(
                        get: { editor.mode },
                        set: { editor.selectMode($0) }
                    )) {
                        ForEach(EditorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Button("Save", systemImage: "square.and.arrow.down") { editor.save() }
                        .keyboardShortcut("s")
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): open(url)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    editor.errorMessage = error.localizedDescription
                }
            }
        }
        .onOpenURL(perform: open)
        .alert("Ultracropper", isPresented: Binding(
            get: { editor.errorMessage != nil },
            set: { if !$0 { editor.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var editorCanvas: some View {
        GeometryReader { geometry in
            let scale = min(max(zoom * magnification, 1), 8)

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if editor.mode == .preview, let image = editor.correctedPreview {
                    fittedImage(image, in: geometry.size, scale: scale)
                } else if let image = editor.sourcePreview {
                    editView(image, in: geometry.size, scale: scale)
                }
            }
            .coordinateSpace(name: "canvas")
            .clipped()
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($magnification) { value, state, _ in
                        state = value.magnification
                    }
                    .onEnded { value in
                        zoom = min(max(zoom * value.magnification, 1), 8)
                    }
            )
        }
        .padding()
    }

    private func fittedImage(_ image: NSImage, in size: CGSize, scale: CGFloat) -> some View {
        let rect = PerspectiveGeometry.fittedRect(imageSize: image.size, in: size, scale: scale)
        return Image(nsImage: image)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func editView(_ image: NSImage, in size: CGSize, scale: CGFloat) -> some View {
        let rect = PerspectiveGeometry.fittedRect(imageSize: image.size, in: size, scale: scale)

        return ZStack {
            Image(nsImage: image)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            Path { path in
                let points = editor.quad.points.map { PerspectiveGeometry.viewPoint($0, in: rect) }
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
            }
            .stroke(.blue, style: StrokeStyle(lineWidth: 1, lineJoin: .round))

            ForEach(Corner.allCases) { corner in
                ZStack {
                    Circle()
                        .stroke(.blue, lineWidth: 1.5)
                    Circle()
                        .fill(.blue)
                        .frame(width: 4, height: 4)
                }
                    .frame(width: 18, height: 18)
                    .contentShape(Circle().inset(by: -8))
                    .position(PerspectiveGeometry.viewPoint(editor.quad[corner], in: rect))
                    .gesture(
                        DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                editor.update(
                                    corner,
                                    to: PerspectiveGeometry.normalizedPoint(value.location, in: rect)
                                )
                            }
                    )
                    .accessibilityLabel(corner.label)
                    .accessibilityHint("Drag to position this corner")
            }
        }
    }

    private func open(_ url: URL) {
        zoom = 1
        editor.load(url)
    }
}

#Preview {
    ContentView()
}
