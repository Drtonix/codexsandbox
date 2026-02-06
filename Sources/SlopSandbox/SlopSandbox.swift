import AppKit
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }
}

struct WaveScreen: View {
    @StateObject private var wave = WaveModel()
    @State private var keyboardMonitor = KeyboardMonitor()
    @State private var panelCenter: CGPoint = .zero
    @State private var panelCollapsed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TimelineView(.animation(minimumInterval: wave.preferredRenderInterval, paused: false)) { _ in
                    Canvas(rendersAsynchronously: false) { context, size in
                        let samples = wave.samples
                        let bodies = wave.bodyDrawStates
                        let waterChunks = wave.waterChunkDrawStates
                        let glassShards = wave.glassShardDrawStates
                        let hasWaterSurface = wave.sceneLocation == .water
                        guard samples.count > 1 else { return }

                        let centerY = wave.surfaceBaselineY(in: size)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: centerY))

                        let step: CGFloat = 4
                        let width = max(size.width, 1)
                        let sampleCount = samples.count

                        for x in stride(from: CGFloat(0), through: size.width, by: step) {
                            let normalizedX = x / width
                            let sampleIndex = normalizedX * CGFloat(sampleCount - 1)
                            let leftIndex = min(Int(sampleIndex), sampleCount - 1)
                            let rightIndex = min(leftIndex + 1, sampleCount - 1)
                            let fraction = sampleIndex - CGFloat(leftIndex)
                            let left = samples[leftIndex]
                            let right = samples[rightIndex]
                            let displacement = hasWaterSurface ? (left + (right - left) * fraction) : 0
                            let y = centerY + displacement
                            path.addLine(to: CGPoint(x: x, y: y))
                        }

                        let fillOpacity: CGFloat = (wave.theme == .dark) ? 0.08 : 0.06
                        if hasWaterSurface {
                            var fillPath = path
                            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                            fillPath.closeSubpath()
                            context.fill(fillPath, with: .color(wave.accentColor.opacity(fillOpacity)))
                        } else {
                            let groundRect = CGRect(
                                x: 0,
                                y: centerY,
                                width: size.width,
                                height: max(1, size.height - centerY)
                            )
                            context.fill(Path(groundRect), with: .color(wave.accentColor.opacity(fillOpacity)))
                        }

                        let halfSquare = wave.squareSize * 0.5
                        let squarePath = Path(
                            CGRect(
                                x: -halfSquare,
                                y: -halfSquare,
                                width: wave.squareSize,
                                height: wave.squareSize
                            )
                        )
                        let circlePath = Path(
                            ellipseIn: CGRect(
                                x: -wave.circleRadius,
                                y: -wave.circleRadius,
                                width: wave.circleRadius * 2,
                                height: wave.circleRadius * 2
                            )
                        )

                        let glassTint: (CGFloat, CGFloat, CGFloat) = wave.theme == .dark ? (1, 1, 1) : (0, 0, 0)
                        let featureColors: [(key: (WaveModel.BodyDrawState) -> Bool, color: (CGFloat, CGFloat, CGFloat))] = [
                            ({ $0.isBouncy }, (0.25, 0.95, 0.45)),
                            ({ $0.isSlippery }, (0.2, 0.75, 1.0)),
                            ({ $0.isSticky }, (1.0, 0.85, 0.2)),
                            ({ $0.isGlass }, glassTint)
                        ]

                        func blendedFeatureColor(for body: WaveModel.BodyDrawState) -> Color? {
                            var r: CGFloat = 0
                            var g: CGFloat = 0
                            var b: CGFloat = 0
                            var count: CGFloat = 0

                            for entry in featureColors where entry.key(body) {
                                r += entry.color.0
                                g += entry.color.1
                                b += entry.color.2
                                count += 1
                            }

                            guard count > 0 else { return nil }
                            let alpha = min(0.3, 0.16 + 0.05 * (count - 1))
                            return Color(.sRGB, red: r / count, green: g / count, blue: b / count, opacity: alpha)
                        }

                        for body in bodies {
                            let baseFill = wave.accentColor.opacity(fillOpacity)
                            let featureFill = blendedFeatureColor(for: body)
                            var bodyContext = context
                            bodyContext.translateBy(x: body.center.x, y: body.center.y)
                            bodyContext.rotate(by: .radians(body.angle))
                            switch body.shape {
                            case .cube:
                                bodyContext.fill(squarePath, with: .color(baseFill))
                                if let featureFill {
                                    bodyContext.fill(squarePath, with: .color(featureFill))
                                }
                                bodyContext.stroke(
                                    squarePath,
                                    with: .color(wave.accentColor),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                                if body.isSelected {
                                    bodyContext.stroke(
                                        squarePath,
                                        with: .color(wave.selectionColor.opacity(0.7)),
                                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
                                    )
                                }
                            case .circle:
                                bodyContext.fill(circlePath, with: .color(baseFill))
                                if let featureFill {
                                    bodyContext.fill(circlePath, with: .color(featureFill))
                                }
                                bodyContext.stroke(
                                    circlePath,
                                    with: .color(wave.accentColor),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                                if body.isSelected {
                                    bodyContext.stroke(
                                        circlePath,
                                        with: .color(wave.selectionColor.opacity(0.7)),
                                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
                                    )
                                }
                            case .polygon:
                                if let vertices = body.localVertices, vertices.count > 1 {
                                    var polygonPath = Path()
                                    polygonPath.move(to: vertices[0])
                                    for vertex in vertices.dropFirst() {
                                        polygonPath.addLine(to: vertex)
                                    }
                                    polygonPath.closeSubpath()
                                    bodyContext.fill(polygonPath, with: .color(baseFill))
                                    if let featureFill {
                                        bodyContext.fill(polygonPath, with: .color(featureFill))
                                    }
                                    bodyContext.stroke(
                                        polygonPath,
                                        with: .color(wave.accentColor),
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                    )
                                    if body.isSelected {
                                        bodyContext.stroke(
                                            polygonPath,
                                            with: .color(wave.selectionColor.opacity(0.7)),
                                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
                                        )
                                    }
                                }
                            }

                            if body.isWheel {
                                let wheelMark = Path(
                                    ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12)
                                )
                                bodyContext.stroke(
                                    wheelMark,
                                    with: .color(wave.accentColor),
                                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                                )
                                bodyContext.fill(
                                    Path(ellipseIn: CGRect(x: -1.5, y: -1.5, width: 3, height: 3)),
                                    with: .color(wave.accentColor)
                                )
                            }

                        }

                        for chunk in waterChunks {
                            if chunk.tailLength > 0.1 {
                                let speed = sqrt(chunk.velocity.dx * chunk.velocity.dx + chunk.velocity.dy * chunk.velocity.dy)
                                if speed > 0.001 {
                                    let dir = CGVector(dx: chunk.velocity.dx / speed, dy: chunk.velocity.dy / speed)
                                    var tail = Path()
                                    tail.move(to: chunk.center)
                                    tail.addLine(
                                        to: CGPoint(
                                            x: chunk.center.x - dir.dx * chunk.tailLength,
                                            y: chunk.center.y - dir.dy * chunk.tailLength
                                        )
                                    )
                                    context.stroke(
                                        tail,
                                        with: .color(wave.accentColor.opacity(chunk.opacity * 0.55)),
                                        style: StrokeStyle(lineWidth: max(0.6, chunk.radius * 0.45), lineCap: .round)
                                    )
                                }
                            }

                            let rect = CGRect(
                                x: chunk.center.x - chunk.radius,
                                y: chunk.center.y - chunk.radius,
                                width: chunk.radius * 2,
                                height: chunk.radius * 2
                            )
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(wave.accentColor.opacity(chunk.opacity))
                            )
                            context.stroke(
                                Path(ellipseIn: rect),
                                with: .color(wave.accentColor.opacity(min(1, chunk.opacity + 0.18))),
                                style: StrokeStyle(lineWidth: max(0.5, chunk.radius * 0.22))
                            )
                        }

                        if !glassShards.isEmpty {
                            let shardBase = wave.theme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.62)
                            let shardEdge = wave.theme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.9)
                            for shard in glassShards {
                                var shardContext = context
                                let speed = sqrt(shard.velocity.dx * shard.velocity.dx + shard.velocity.dy * shard.velocity.dy)
                                if speed > 0.18 {
                                    let nx = shard.velocity.dx / max(0.001, speed)
                                    let ny = shard.velocity.dy / max(0.001, speed)
                                    var tail = Path()
                                    tail.move(to: shard.center)
                                    tail.addLine(
                                        to: CGPoint(
                                            x: shard.center.x - nx * shard.radius * shard.stretch * 2.4,
                                            y: shard.center.y - ny * shard.radius * shard.stretch * 2.4
                                        )
                                    )
                                    context.stroke(
                                        tail,
                                        with: .color(shardBase.opacity(shard.opacity * 0.45)),
                                        style: StrokeStyle(lineWidth: max(0.45, shard.radius * 0.35), lineCap: .round)
                                    )
                                }
                                shardContext.translateBy(x: shard.center.x, y: shard.center.y)
                                shardContext.rotate(by: .radians(shard.angle))
                                let w = shard.radius * (1.2 + shard.stretch * 0.9)
                                let h = shard.radius * (0.48 + shard.stretch * 0.35)
                                var path = Path()
                                switch shard.kind {
                                case 0:
                                    path.move(to: CGPoint(x: -w * 0.9, y: 0))
                                    path.addLine(to: CGPoint(x: w * 0.7, y: -h * 0.7))
                                    path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.78))
                                    path.closeSubpath()
                                case 1:
                                    path.move(to: CGPoint(x: 0, y: -h))
                                    path.addLine(to: CGPoint(x: w, y: 0))
                                    path.addLine(to: CGPoint(x: 0, y: h))
                                    path.addLine(to: CGPoint(x: -w, y: 0))
                                    path.closeSubpath()
                                default:
                                    let rect = CGRect(x: -w, y: -h * 0.42, width: w * 2, height: h * 0.84)
                                    path = Path(roundedRect: rect, cornerRadius: shard.radius * 0.18)
                                }

                                shardContext.fill(path, with: .color(shardBase.opacity(shard.opacity)))
                                shardContext.stroke(
                                    path,
                                    with: .color(shardEdge.opacity(min(1, shard.opacity + 0.18))),
                                    style: StrokeStyle(lineWidth: max(0.55, shard.radius * 0.2), lineCap: .round, lineJoin: .round)
                                )

                                var highlight = Path()
                                highlight.move(to: CGPoint(x: -w * 0.52, y: 0))
                                highlight.addLine(to: CGPoint(x: w * 0.55, y: 0))
                                shardContext.stroke(
                                    highlight,
                                    with: .color(shardEdge.opacity(shard.opacity * 0.55)),
                                    style: StrokeStyle(lineWidth: max(0.35, shard.radius * 0.14), lineCap: .round)
                                )
                            }
                        }

                        if let selectionRect = wave.selectionRect {
                            var selectionPath = Path()
                            selectionPath.addRect(selectionRect)
                            context.stroke(
                                selectionPath,
                                with: .color(wave.selectionColor.opacity(0.7)),
                                style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])
                            )
                        }

                        if wave.drawingPreviewPoints.count > 1 {
                            var drawPath = Path()
                            drawPath.move(to: wave.drawingPreviewPoints[0])
                            for point in wave.drawingPreviewPoints.dropFirst() {
                                drawPath.addLine(to: point)
                            }
                            if wave.drawingPreviewClosed {
                                drawPath.closeSubpath()
                            }
                            context.stroke(
                                drawPath,
                                with: .color(wave.accentColor.opacity(0.8)),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [6, 4])
                            )
                        }

                        if wave.weldToolEnabled, let cursor = wave.weldCursorPoint {
                            let markerRect = CGRect(x: cursor.x - 4, y: cursor.y - 4, width: 8, height: 8)
                            context.fill(Path(ellipseIn: markerRect), with: .color(wave.accentColor))
                        }

                        if wave.weldToolEnabled, let pending = wave.weldPendingPoint {
                            let pendingRect = CGRect(x: pending.x - 6, y: pending.y - 6, width: 12, height: 12)
                            context.stroke(
                                Path(ellipseIn: pendingRect),
                                with: .color(wave.accentColor),
                                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                            )
                            if let cursor = wave.weldCursorPoint {
                                var linkPath = Path()
                                linkPath.move(to: pending)
                                linkPath.addLine(to: cursor)
                                context.stroke(
                                    linkPath,
                                    with: .color(wave.accentColor.opacity(0.5)),
                                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [5, 5])
                                )
                            }
                        }

                        if wave.wheelToolEnabled, let cursor = wave.wheelCursorPoint {
                            let outerRect = CGRect(x: cursor.x - 7, y: cursor.y - 7, width: 14, height: 14)
                            let innerRect = CGRect(x: cursor.x - 2, y: cursor.y - 2, width: 4, height: 4)
                            context.stroke(
                                Path(ellipseIn: outerRect),
                                with: .color(wave.accentColor.opacity(0.9)),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                            )
                            context.fill(
                                Path(ellipseIn: innerRect),
                                with: .color(wave.accentColor.opacity(0.9))
                            )
                        }

                        context.stroke(
                            path,
                            with: .color(wave.accentColor),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .background(wave.backgroundColor)
                }

                MouseTrackingLayer(
                    onMove: { location, timestamp, isShiftPressed in
                        wave.pointerMoved(
                            to: location,
                            timestamp: timestamp,
                            in: geometry.size,
                            isShiftPressed: isShiftPressed
                        )
                    },
                    onLeftDown: { location, timestamp, isShiftPressed in
                        wave.pointerDown(
                            at: location,
                            button: .left,
                            timestamp: timestamp,
                            in: geometry.size,
                            isShiftPressed: isShiftPressed
                        )
                    },
                    onLeftUp: { location, timestamp, isShiftPressed in
                        wave.pointerUp(
                            at: location,
                            button: .left,
                            timestamp: timestamp,
                            in: geometry.size,
                            isShiftPressed: isShiftPressed
                        )
                    },
                    onRightDown: { location, timestamp, isShiftPressed in
                        wave.pointerDown(
                            at: location,
                            button: .right,
                            timestamp: timestamp,
                            in: geometry.size,
                            isShiftPressed: isShiftPressed
                        )
                    },
                    onRightUp: { location, timestamp, isShiftPressed in
                        wave.pointerUp(
                            at: location,
                            button: .right,
                            timestamp: timestamp,
                            in: geometry.size,
                            isShiftPressed: isShiftPressed
                        )
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

                FloatingControlPanel(
                    wave: wave,
                    canvasSize: geometry.size,
                    center: $panelCenter,
                    isCollapsed: $panelCollapsed
                )
            }
            .coordinateSpace(name: "wave-space")
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                wave.setViewportSize(geometry.size)
            }
            .onChange(of: geometry.size) { newSize in
                wave.setViewportSize(newSize)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            wave.applySystemDefaultsIfNeeded(colorScheme: colorScheme)
            keyboardMonitor.onKeyDown = { event in
                wave.handleKeyDown(event)
            }
            keyboardMonitor.onModifierChanged = { event in
                wave.handleModifierChange(event)
            }
            keyboardMonitor.start()
            wave.start()
        }
        .onDisappear {
            keyboardMonitor.stop()
            wave.stop()
        }
    }
}

struct FloatingControlPanel: View {
    @ObservedObject var wave: WaveModel
    let canvasSize: CGSize
    @Binding var center: CGPoint
    @Binding var isCollapsed: Bool
    @State private var dragPointerOffset: CGSize?
    @State private var dragStartLocation: CGPoint?
    @State private var dragMoved = false

    private let expandedSize = CGSize(width: 360, height: 620)
    private let collapsedSize = CGSize(width: 360, height: 36)
    private let expandedWidthRange: ClosedRange<CGFloat> = 300...380
    private let handleHeight: CGFloat = 36
    private let margin: CGFloat = 10

    private func tr(_ ru: String, _ en: String) -> String {
        wave.language == .ru ? ru : en
    }

    private var currentSize: CGSize {
        let width = min(max(expandedSize.width, expandedWidthRange.lowerBound), expandedWidthRange.upperBound)
        return CGSize(width: width, height: isCollapsed ? collapsedSize.height : expandedSize.height)
    }

    var body: some View {
        Group {
            if isCollapsed {
                collapsedView
            } else {
                expandedView
            }
        }
        .position(displayCenter)
        .onAppear {
            if center == .zero {
                center = defaultCenter(for: currentSize)
            }
            center = clamped(center, for: currentSize)
        }
        .onChange(of: canvasSize) { _ in
            center = clamped(center, for: currentSize)
        }
        .onChange(of: isCollapsed) { _ in
            center = clamped(center, for: currentSize)
            dragPointerOffset = nil
            dragStartLocation = nil
            dragMoved = false
        }
    }

    private var displayCenter: CGPoint {
        clamped(center, for: currentSize)
    }

    private var collapsedView: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
            Text(tr("Панель", "Panel"))
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .frame(width: currentSize.width, height: collapsedSize.height)
        .background(GlassPanelBackground(baseColor: wave.panelBackgroundColor))
        .foregroundStyle(wave.accentColor)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(wave.accentColor.opacity(0.2), lineWidth: 1))
        .gesture(
            dragGesture(for: CGSize(width: currentSize.width, height: collapsedSize.height)) {
                let expandedCenter = recentered(
                    center,
                    from: CGSize(width: currentSize.width, height: collapsedSize.height),
                    to: CGSize(width: currentSize.width, height: expandedSize.height),
                    anchorX: 0,
                    anchorY: 0
                )
                center = clamped(expandedCenter, for: CGSize(width: currentSize.width, height: expandedSize.height))
                isCollapsed = false
            }
        )
    }

    private var expandedView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                Text(tr("Переместить", "Move"))
                    .font(.caption2.weight(.semibold))
                Spacer()
                Button {
                    let collapsedCenter = recentered(
                        center,
                        from: expandedSize,
                        to: collapsedSize,
                        anchorX: 0,
                        anchorY: 0
                    )
                    center = clamped(collapsedCenter, for: collapsedSize)
                    isCollapsed = true
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: currentSize.width, height: handleHeight)
            .background(GlassPanelBackground(baseColor: wave.panelBackgroundColor))
            .foregroundStyle(wave.accentColor.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(wave.accentColor.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(for: currentSize))

            WaveControlsPanel(wave: wave, height: expandedSize.height - handleHeight - 6, width: currentSize.width)
        }
    }

    private func dragGesture(for panelSize: CGSize, tapAction: (() -> Void)? = nil) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("wave-space"))
            .onChanged { value in
                if dragPointerOffset == nil {
                    dragPointerOffset = CGSize(
                        width: center.x - value.startLocation.x,
                        height: center.y - value.startLocation.y
                    )
                    dragStartLocation = value.startLocation
                    dragMoved = false
                }

                if let start = dragStartLocation {
                    let dx = value.location.x - start.x
                    let dy = value.location.y - start.y
                    if abs(dx) > 0.8 || abs(dy) > 0.8 {
                        dragMoved = true
                    }
                }

                let offset = dragPointerOffset ?? .zero
                let proposed = CGPoint(
                    x: value.location.x + offset.width,
                    y: value.location.y + offset.height
                )
                center = clamped(proposed, for: panelSize)
            }
            .onEnded { _ in
                if !dragMoved {
                    tapAction?()
                }

                dragPointerOffset = nil
                dragStartLocation = nil
                dragMoved = false
            }
    }

    private func defaultCenter(for panelSize: CGSize) -> CGPoint {
        let halfW = panelSize.width * 0.5
        let halfH = panelSize.height * 0.5
        return CGPoint(
            x: max(halfW + margin, canvasSize.width - halfW - margin),
            y: halfH + margin
        )
    }

    private func clamped(_ point: CGPoint, for panelSize: CGSize) -> CGPoint {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return point }

        let halfW = panelSize.width * 0.5
        let halfH = panelSize.height * 0.5
        let minX = halfW + margin
        let maxX = max(minX, canvasSize.width - halfW - margin)
        let minY = halfH + margin
        let maxY = max(minY, canvasSize.height - halfH - margin)

        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    private func recentered(
        _ value: CGPoint,
        from fromSize: CGSize,
        to toSize: CGSize,
        anchorX: CGFloat,
        anchorY: CGFloat
    ) -> CGPoint {
        let dx = (anchorX - 0.5) * (fromSize.width - toSize.width)
        let dy = (anchorY - 0.5) * (fromSize.height - toSize.height)
        return CGPoint(x: value.x + dx, y: value.y + dy)
    }
}

struct WaveControlsPanel: View {
    @ObservedObject var wave: WaveModel
    var height: CGFloat = 580
    var width: CGFloat = 360

    private func tr(_ ru: String, _ en: String) -> String {
        wave.language == .ru ? ru : en
    }

    private func labeled(_ base: String, key: String) -> String {
        "\(base) (\(key))"
    }

    private func drawingToolLabel(_ tool: WaveModel.DrawingTool) -> String {
        switch tool {
        case .none:
            return labeled(tr("Нет", "Off"), key: "1")
        case .quadrilateral:
            return labeled(tr("4-угольник", "Quad"), key: "R")
        case .ellipse:
            return labeled(tr("Окружность", "Circle"), key: "T")
        case .triangle:
            return labeled(tr("Треугольник", "Triangle"), key: "Y")
        case .freeform:
            return labeled(tr("Рисунок [эксп]", "Drawing [exp]"), key: "U")
        }
    }

    private func sceneLocationLabel(_ location: WaveModel.SceneLocation) -> String {
        switch location {
        case .water:
            return tr("Вода", "Water")
        case .land:
            return tr("Суша", "Land")
        }
    }

    private func drawingToolButton(_ tool: WaveModel.DrawingTool) -> some View {
        let isActive = wave.drawingTool == tool
        return Button(action: { wave.toggleDrawingTool(tool) }) {
            Text(drawingToolLabel(tool))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(panelButtonBackground(isActive: isActive))
        .overlay(panelButtonStroke(isActive: isActive))
        .foregroundStyle(wave.accentColor)
    }

    private func panelButton(_ title: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        return Button(action: action) {
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(panelButtonBackground(isActive: isActive))
        .overlay(panelButtonStroke(isActive: isActive))
        .foregroundStyle(wave.accentColor)
    }

    private func panelButtonBackground(isActive: Bool) -> some View {
        let corner = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            if isActive {
                corner.fill(wave.accentColor.opacity(wave.theme == .dark ? 0.22 : 0.12))
            } else {
                corner.fill(Color.clear)
            }
        }
    }

    private func panelButtonStroke(isActive: Bool) -> some View {
        let corner = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return corner.stroke(isActive ? wave.accentColor : wave.accentColor.opacity(0.28), lineWidth: 1)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Text("FPS \(Int(wave.fps.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(wave.accentColor.opacity(0.7))
                        .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                    panelButton(tr("По умолчанию", "Defaults"), isActive: true) {
                        wave.resetAll()
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    panelButton(tr("Сброс Сцены", "Reset Scene")) {
                        wave.resetScene()
                    }
                    panelButton(labeled(tr("Куб", "Cube"), key: "Q")) {
                        wave.addCube()
                    }
                    panelButton(labeled(tr("Шар", "Ball"), key: "W")) {
                        wave.addCircle()
                    }
                    panelButton(labeled(tr("Треугольник", "Triangle"), key: "E")) {
                        wave.addTriangle()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        if wave.drawingTool == .none, !wave.weldToolEnabled, !wave.wheelToolEnabled, !wave.bounceToolEnabled, !wave.slipToolEnabled, !wave.stickyToolEnabled, !wave.glassToolEnabled {
                            panelButton(labeled(tr("Курсор: Вкл", "Cursor: On"), key: "1"), isActive: true) {
                                wave.selectCursorTool()
                            }
                        } else {
                            panelButton(labeled(tr("Курсор", "Cursor"), key: "1")) {
                                wave.selectCursorTool()
                            }
                        }

                        if wave.weldToolEnabled {
                            panelButton(labeled(tr("Сварка: Вкл", "Weld: On"), key: "2"), isActive: true) {
                                wave.toggleWeldTool()
                            }
                        } else {
                            panelButton(labeled(tr("Сварка", "Weld"), key: "2")) {
                                wave.toggleWeldTool()
                            }
                        }

                        if wave.wheelToolEnabled {
                            panelButton(labeled(tr("Колесо: Вкл", "Wheel: On"), key: "3"), isActive: true) {
                                wave.toggleWheelTool()
                            }
                        } else {
                            panelButton(labeled(tr("Колесо", "Wheel"), key: "3")) {
                                wave.toggleWheelTool()
                            }
                        }

                        if wave.bounceToolEnabled {
                            panelButton(labeled(tr("Прыгучесть: Вкл", "Bounce: On"), key: "4"), isActive: true) {
                                wave.toggleBounceTool()
                            }
                        } else {
                            panelButton(labeled(tr("Прыгучесть", "Bounce"), key: "4")) {
                                wave.toggleBounceTool()
                            }
                        }

                        if wave.slipToolEnabled {
                            panelButton(labeled(tr("Скользкость: Вкл", "Slip: On"), key: "5"), isActive: true) {
                                wave.toggleSlipTool()
                            }
                        } else {
                            panelButton(labeled(tr("Скользкость", "Slip"), key: "5")) {
                                wave.toggleSlipTool()
                            }
                        }

                        if wave.stickyToolEnabled {
                            panelButton(labeled(tr("Липкость: Вкл", "Sticky: On"), key: "6"), isActive: true) {
                                wave.toggleStickyTool()
                            }
                        } else {
                            panelButton(labeled(tr("Липкость", "Sticky"), key: "6")) {
                                wave.toggleStickyTool()
                            }
                        }

                        if wave.glassToolEnabled {
                            panelButton(labeled(tr("Стеклянность: Вкл", "Glass: On"), key: "7"), isActive: true) {
                                wave.toggleGlassTool()
                            }
                        } else {
                            panelButton(labeled(tr("Стеклянность", "Glass"), key: "7")) {
                                wave.toggleGlassTool()
                            }
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    let toolText = wave.weldToolEnabled
                        ? tr("Инструмент: Сварка", "Tool: Weld")
                        : wave.wheelToolEnabled
                            ? tr("Инструмент: Колесо", "Tool: Wheel")
                            : wave.bounceToolEnabled
                                ? tr("Инструмент: Прыгучесть", "Tool: Bounce")
                                : wave.slipToolEnabled
                                    ? tr("Инструмент: Скользкость", "Tool: Slip")
                                    : wave.stickyToolEnabled
                                        ? tr("Инструмент: Липкость", "Tool: Sticky")
                                        : wave.glassToolEnabled
                                            ? tr("Инструмент: Стекло", "Tool: Glass")
                                            : tr("Инструмент: Нет", "Tool: None")
                    Text(toolText)
                        .font(.caption2)
                        .foregroundStyle(wave.accentColor.opacity(0.7))
                        .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
                }

                Picker(tr("Локация", "Location"), selection: $wave.sceneLocation) {
                    Text(sceneLocationLabel(.water)).tag(WaveModel.SceneLocation.water)
                    Text(sceneLocationLabel(.land)).tag(WaveModel.SceneLocation.land)
                }
                .pickerStyle(.segmented)

                HStack {
                Text(labeled(tr("Произвольные Объекты", "Freeform Objects"), key: "R/T/Y/U"))
                    .font(.caption2)
                    .foregroundStyle(wave.accentColor.opacity(0.85))
                    .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                    Spacer()
                    Text(tr("Shift: Ровно", "Shift: Constrain"))
                        .font(.caption2)
                        .foregroundStyle(wave.accentColor.opacity(0.6))
                        .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 6, alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    drawingToolButton(.none)
                    drawingToolButton(.quadrilateral)
                    drawingToolButton(.ellipse)
                    drawingToolButton(.triangle)
                    drawingToolButton(.freeform)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                panelButton(
                    wave.isTimeFrozen
                        ? labeled(tr("Продолжить Время", "Resume Time"), key: "Space")
                        : labeled(tr("Заморозить Время", "Freeze Time"), key: "Space"),
                    isActive: wave.isTimeFrozen
                ) {
                    wave.toggleTimeFrozen()
                }

                HStack(spacing: 10) {
                    Text(tr("Язык", "Language"))
                        .font(.caption2)
                        .foregroundStyle(wave.accentColor.opacity(0.85))
                    Spacer()
                    LanguageToggle(language: $wave.language, accentColor: wave.accentColor, isDarkTheme: wave.theme == .dark)
                }

                HStack(spacing: 10) {
                    Text(tr("Тема", "Theme"))
                        .font(.caption2)
                        .foregroundStyle(wave.accentColor.opacity(0.85))
                        .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                    Spacer()
                    ThemeToggle(theme: $wave.theme, accentColor: wave.accentColor, language: wave.language, isDarkTheme: wave.theme == .dark)
                }

                ControlSlider(
                    tr("Лимит FPS", "FPS Limit"),
                    value: $wave.fpsLimit,
                    range: 20...480,
                    step: 1,
                    format: "%.0f",
                    accentColor: wave.accentColor
                )

                ControlSlider(
                    labeled(tr("Скорость Времени", "Time Scale"), key: "G/H"),
                    value: $wave.timeScale,
                    range: 0.2...2.5,
                    step: 0.05,
                    format: "%.2f",
                    accentColor: wave.accentColor
                )

                Group {
                    PanelSection(title: tr("Волна: Основа", "Wave Core"), color: wave.accentColor)
                    ControlSlider(tr("Жесткость База", "Stiffness Base"), value: $wave.stiffnessBase, range: 0.02...0.25, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Жесткость Активность", "Stiffness Activity"), value: $wave.stiffnessActivity, range: 0...0.2, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Затухание База", "Damping Base"), value: $wave.dampingBase, range: 0.97...0.9999, step: 0.0001, format: "%.4f", accentColor: wave.accentColor)
                    ControlSlider(tr("Затухание Активность", "Damping Activity"), value: $wave.dampingActivity, range: 0...0.02, step: 0.0001, format: "%.4f", accentColor: wave.accentColor)
                    ControlSlider(tr("Вязкость", "Viscosity"), value: $wave.viscosity, range: 0...0.08, step: 0.0005, format: "%.4f", accentColor: wave.accentColor)
                    ControlSlider(tr("Макс Скорость Волны", "Wave Max Speed"), value: $wave.maxVelocity, range: 2...30, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Ограничения Волны", "Wave Limits"), color: wave.accentColor)
                    ControlSlider(tr("Макс Амплитуда Вверх", "Max Up Amplitude"), value: $wave.maxUpDisplacement, range: 40...340, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Макс Амплитуда Вниз", "Max Down Amplitude"), value: $wave.maxDownDisplacement, range: 30...260, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Мягкий Лимит Вверх", "Soft Up Limit"), value: $wave.softUpLimitStart, range: 20...300, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Мягкий Лимит Вниз", "Soft Down Limit"), value: $wave.softDownLimitStart, range: 20...240, step: 1, format: "%.0f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Курсор / Клавиатура", "Pointer / Keyboard"), color: wave.accentColor)
                    ControlSlider(tr("Набор Активности Клавиш", "Key Activity Gain"), value: $wave.keyboardActivityGain, range: 0...0.8, step: 0.005, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Импульс Клавиш База", "Key Impulse Base"), value: $wave.keyboardImpulseBase, range: 0...20, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Импульс Клавиш Множитель", "Key Impulse Scale"), value: $wave.keyboardImpulseScale, range: 0...20, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Радиус Клавиш Мин", "Key Radius Min"), value: $wave.keyboardRadiusMin, range: 1...80, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Радиус Клавиш Макс", "Key Radius Max"), value: $wave.keyboardRadiusMax, range: 2...120, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Радиус Курсора База", "Pointer Radius Base"), value: $wave.pointerRadiusBase, range: 1...80, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Радиус Курсора Множитель", "Pointer Radius Scale"), value: $wave.pointerRadiusScale, range: 0...100, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Глубина Курсора База", "Pointer Depth Base"), value: $wave.pointerDepthBase, range: 0...3, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Глубина Курсора Множитель", "Pointer Depth Scale"), value: $wave.pointerDepthScale, range: 0...5, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Глубина Курсора Активность", "Pointer Depth Activity"), value: $wave.pointerDepthActivityScale, range: 0...2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сила Курсора База", "Pointer Force Base"), value: $wave.pointerForceBase, range: 0...0.2, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сила Курсора Множитель", "Pointer Force Scale"), value: $wave.pointerForceScale, range: 0...0.3, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сглаживание Курсора", "Pointer Smoothing"), value: $wave.pointerSmoothing, range: 0.01...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Подавление Старт", "Suppress Start"), value: $wave.pointerSuppressionStart, range: 1...300, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Подавление Пик", "Suppress Full"), value: $wave.pointerSuppressionFull, range: 2...360, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Подавление Мин", "Suppress Min"), value: $wave.pointerSuppressionMin, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Объекты / Вода", "Objects / Water"), color: wave.accentColor)
                    ControlSlider(tr("Масса Объекта", "Object Mass"), value: $wave.squareMass, range: 0.2...20, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Инерция Объекта", "Object Inertia"), value: $wave.squareInertia, range: 500...30000, step: 50, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Гравитация", "Gravity"), value: $wave.gravityForce, range: 0...2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Ускорение Падения", "Fall Acceleration"), value: $wave.fallAccelerationScale, range: 0.2...3, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Порог Контакта", "Contact Depth"), value: $wave.waterContactThreshold, range: 0...8, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Плавучесть База", "Buoyancy Base"), value: $wave.buoyancyBase, range: 0...0.2, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Плавучесть Множитель", "Buoyancy Scale"), value: $wave.buoyancyScale, range: 0...0.3, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сопротивление X База", "Drag X Base"), value: $wave.dragXBase, range: 0...0.2, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сопротивление X Множитель", "Drag X Scale"), value: $wave.dragXScale, range: 0...0.3, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сопротивление Y База", "Drag Y Base"), value: $wave.dragYBase, range: 0...0.2, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сопротивление Y Множитель", "Drag Y Scale"), value: $wave.dragYScale, range: 0...0.3, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Фактор Наклона Воды", "Water Slope Factor"), value: $wave.waterSlopeFactor, range: 0...3, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Реакция Воды", "Water Reaction"), value: $wave.reactionImpulseScale, range: 0...0.2, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Целевая Осадка Поверхности", "Surface Target Immersion"), value: $wave.surfaceTargetImmersion, range: -0.4...1.2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Пружина Поверхности", "Surface Spring"), value: $wave.surfaceSpring, range: 0...0.2, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Демпфер Поверхности", "Surface Damping"), value: $wave.surfaceDamping, range: 0...0.3, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Вода: Брызги", "Water: Spray"), color: wave.accentColor)
                    Toggle(tr("Брызги Включены", "Spray Enabled"), isOn: $wave.waterSprayEnabled)
                        .tint(wave.accentColor)
                        .foregroundStyle(wave.accentColor)
                        .font(.caption2)
                    ControlSlider(tr("Макс Кол-во Капель", "Max Droplet Count"), value: $wave.waterSprayMaxCount, range: 0...400, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Порог Импульса Брызг", "Spray Impulse Threshold"), value: $wave.waterSprayImpulseThreshold, range: 2...24, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Энергия Брызг От Импульса", "Spray Impulse Energy"), value: $wave.waterSprayImpulseEnergy, range: 0.001...0.1, step: 0.001, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Порог Удара Объекта", "Object Impact Threshold"), value: $wave.waterSprayImpactThreshold, range: 0...8, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Энергия Брызг От Удара", "Object Impact Energy"), value: $wave.waterSprayImpactEnergy, range: 0.01...1.2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Гравитация Капель", "Droplet Gravity"), value: $wave.waterSprayGravityScale, range: 0...1.8, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Демпфирование Капель", "Droplet Damping"), value: $wave.waterSprayLinearDamping, range: 0.9...0.9999, step: 0.0001, format: "%.4f", accentColor: wave.accentColor)
                    ControlSlider(tr("Глубина Поглощения", "Reabsorb Depth"), value: $wave.waterSprayAbsorbDepth, range: 0.02...0.8, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Радиус Капель Мин", "Droplet Radius Min"), value: $wave.waterSprayRadiusMin, range: 0.5...8, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Радиус Капель Макс", "Droplet Radius Max"), value: $wave.waterSprayRadiusMax, range: 0.6...12, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Время Жизни Мин", "Droplet Life Min"), value: $wave.waterSprayLifeMin, range: 8...240, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Время Жизни Макс", "Droplet Life Max"), value: $wave.waterSprayLifeMax, range: 9...420, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("База Прозрачности", "Opacity Base"), value: $wave.waterSprayOpacityBase, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Скалирование Прозрачности", "Opacity Scale"), value: $wave.waterSprayOpacityScale, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Длина Хвоста Капли", "Droplet Tail Length"), value: $wave.waterSprayTailScale, range: 0...5, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Локация: Суша", "Location: Land"), color: wave.accentColor)
                    ControlSlider(tr("Высота Земли", "Ground Height"), value: $wave.landSurfaceLevel, range: 0.55...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Отскок От Суши", "Ground Bounce"), value: $wave.landBounce, range: 0...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Трение На Суше", "Ground Friction"), value: $wave.landFriction, range: 0...2.0, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Демпфер Вращения На Суше", "Ground Angular Damping"), value: $wave.landAngularDamping, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Объекты: Столкновения", "Objects: Collisions"), color: wave.accentColor)
                    Toggle(tr("Столкновения Объектов", "Object Collisions"), isOn: $wave.cubeCollisionEnabled)
                        .tint(wave.accentColor)
                        .foregroundStyle(wave.accentColor)
                        .font(.caption2)
                    ControlSlider(tr("Упругость Столкновений", "Collision Restitution"), value: $wave.collisionRestitution, range: 0...0.95, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Трение Столкновений", "Collision Friction"), value: $wave.collisionFriction, range: 0...2.0, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Прыгучесть", "Bouncy Restitution"), value: $wave.bouncyRestitution, range: 0...1.2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сила Импульса", "Impulse Scale"), value: $wave.collisionImpulseScale, range: 0...2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Передача Вращения", "Angular Transfer"), value: $wave.collisionAngularTransfer, range: 0...2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Коррекция Проникновения", "Penetration Correction"), value: $wave.collisionPositionCorrection, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Допуск Проникновения", "Penetration Slop"), value: $wave.collisionSlop, range: 0...6, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Итерации Решателя", "Solver Iterations"), value: $wave.collisionIterations, range: 1...30, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Качество Коллизий", "Collision Quality"), value: $wave.collisionQuality, range: 0.2...1.0, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Сварка Объектов", "Object Welding"), color: wave.accentColor)
                    Toggle(labeled(tr("Режим Сварки", "Weld Mode"), key: "2"), isOn: $wave.weldToolEnabled)
                        .tint(wave.accentColor)
                        .foregroundStyle(wave.accentColor)
                        .font(.caption2)
                    panelButton(tr("Очистить Сварки", "Clear Welds")) {
                        wave.clearWelds()
                    }
                    ControlSlider(tr("Жесткость Сварки", "Weld Stiffness"), value: $wave.weldLinearStiffness, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Демпфер Сварки", "Weld Damping"), value: $wave.weldLinearDamping, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Жесткость Поворота", "Weld Angular Stiff"), value: $wave.weldAngularStiffness, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Демпфер Поворота", "Weld Angular Damp"), value: $wave.weldAngularDamping, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Итерации Сварки", "Weld Iterations"), value: $wave.weldIterations, range: 1...10, step: 1, format: "%.0f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Режим Колеса", "Wheel Mode"), color: wave.accentColor)
                    Toggle(labeled(tr("Режим Колеса", "Wheel Mode"), key: "3"), isOn: $wave.wheelToolEnabled)
                        .tint(wave.accentColor)
                        .foregroundStyle(wave.accentColor)
                        .font(.caption2)
                    Text(
                        tr(
                            "Клик по уже сваренному объекту: включить/выключить вращение.",
                            "Click a welded body to toggle free rotation."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(wave.accentColor.opacity(0.65))
                    panelButton(tr("Очистить Колеса", "Clear Wheels")) {
                        wave.clearWheels()
                    }
                }

                Group {
                    PanelSection(title: tr("Ограничения Объектов", "Object Limits"), color: wave.accentColor)
                    ControlSlider(tr("Скорость Объекта X", "Object Speed X"), value: $wave.squareVelocityLimitX, range: 0.5...40, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Скорость Объекта Y", "Object Speed Y"), value: $wave.squareVelocityLimitY, range: 0.5...40, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Угловая Скорость Объекта", "Object Angular Speed"), value: $wave.squareAngularLimit, range: 0.01...1, step: 0.005, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Инерция Броска", "Throw Inertia"), value: $wave.dragThrowLinearInertia, range: 0...8, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Инерция Броска Вращение", "Throw Angular Inertia"), value: $wave.dragThrowAngularInertia, range: 0...8, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Лимит Броска Множитель", "Throw Clamp Scale"), value: $wave.dragThrowClampScale, range: 0.5...4, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Ускорение Броска", "Throw Acceleration"), value: $wave.dragThrowAcceleration, range: 0...2.5, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Шаг Поворота Клавиш", "Keyboard Rotate Step"), value: $wave.keyboardRotateStepDegrees, range: 0.5...45, step: 0.5, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Шаг Поворота Shift", "Shift Rotate Step"), value: $wave.keyboardRotateSnapDegrees, range: 1...90, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Отскок Стен X", "Wall Bounce X"), value: $wave.wallBounceX, range: 0...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Отскок Потолок", "Wall Bounce Top"), value: $wave.wallBounceTop, range: 0...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Отскок Пол", "Wall Bounce Bottom"), value: $wave.wallBounceBottom, range: 0...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                }
            }
            .padding(12)
        }
        .frame(width: width, height: height)
        .background(GlassPanelBackground(baseColor: wave.panelBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(wave.accentColor.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, wave.theme == .dark ? .dark : .light)
    }
}

struct PanelSection: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(color.opacity(0.65))
            .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
            .textCase(.uppercase)
            .padding(.top, 6)
    }
}

// KeyHintOverlay removed: key bindings are now shown inline in labels.

struct GlassPanelBackground: View {
    let baseColor: Color

    var body: some View {
        baseColor
    }
}

struct ControlSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let format: String
    let accentColor: Color

    init(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        format: String,
        accentColor: Color
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.accentColor = accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(accentColor.opacity(0.9))
                Spacer()
                Text(String(format: format, Double(value)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(accentColor)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = CGFloat($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .tint(accentColor)
        }
    }
}

struct LanguageToggle: View {
    @Binding var language: AppLanguage
    let accentColor: Color
    let isDarkTheme: Bool

    private var isEnglish: Binding<Bool> {
        Binding(
            get: { language == .en },
            set: { language = $0 ? .en : .ru }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("RU")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(language == .ru ? accentColor : accentColor.opacity(0.6))
                .shadow(color: Color.black.opacity(0.45), radius: 1, x: 0, y: 1)
            Toggle("", isOn: isEnglish)
                .labelsHidden()
                .toggleStyle(GlassSwitchStyle(accent: accentColor, isDarkTheme: isDarkTheme))
            Text("EN")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(language == .en ? accentColor : accentColor.opacity(0.6))
                .shadow(color: Color.black.opacity(0.45), radius: 1, x: 0, y: 1)
        }
    }
}

struct ThemeToggle: View {
    @Binding var theme: AppTheme
    let accentColor: Color
    let language: AppLanguage
    let isDarkTheme: Bool

    private var isLight: Binding<Bool> {
        Binding(
            get: { theme == .light },
            set: { theme = $0 ? .light : .dark }
        )
    }

    private func tr(_ ru: String, _ en: String) -> String {
        language == .ru ? ru : en
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(tr("Тёмн", "Dark"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme == .dark ? accentColor : accentColor.opacity(0.6))
                .shadow(color: Color.black.opacity(0.45), radius: 1, x: 0, y: 1)
            Toggle("", isOn: isLight)
                .labelsHidden()
                .toggleStyle(GlassSwitchStyle(accent: accentColor, isDarkTheme: isDarkTheme))
            Text(tr("Свет", "Light"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme == .light ? accentColor : accentColor.opacity(0.6))
                .shadow(color: Color.black.opacity(0.45), radius: 1, x: 0, y: 1)
        }
    }
}

struct GlassSwitchStyle: ToggleStyle {
    let accent: Color
    let isDarkTheme: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        let trackFill = isOn
            ? accent.opacity(isDarkTheme ? 0.25 : 0.18)
            : (isDarkTheme ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
        let trackStroke = isOn
            ? accent.opacity(isDarkTheme ? 0.8 : 0.7)
            : (isDarkTheme ? Color.white.opacity(0.35) : Color.black.opacity(0.25))

        return Button(action: { configuration.isOn.toggle() }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(trackFill)
                    .overlay(
                        Capsule().stroke(trackStroke, lineWidth: 1)
                    )
                Circle()
                    .fill(Color.white.opacity(isDarkTheme ? 0.95 : 0.9))
                    .overlay(
                        Circle().stroke(Color.black.opacity(isDarkTheme ? 0.3 : 0.2), lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(isDarkTheme ? 0.4 : 0.2), radius: 2, x: 0, y: 1)
                    .padding(2)
            }
            .frame(width: 44, height: 24)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
    }
}

@MainActor
final class WaveModel: ObservableObject {
    enum MouseButton: Equatable {
        case left
        case right
    }

    enum DrawingTool: String, CaseIterable, Identifiable {
        case none
        case quadrilateral
        case ellipse
        case triangle
        case freeform

        var id: String { rawValue }
    }

    enum SceneLocation: String, CaseIterable, Identifiable {
        case water
        case land

        var id: String { rawValue }
    }

    enum BodyShape {
        case cube
        case circle
        case polygon
    }

    enum SpawnKind {
        case cube
        case circle
    }

    struct BodyDrawState: Identifiable {
        let id: UUID
        let shape: BodyShape
        let center: CGPoint
        let angle: CGFloat
        let localVertices: [CGPoint]?
        let isWheel: Bool
        let isSelected: Bool
        let isBouncy: Bool
        let isSlippery: Bool
        let isSticky: Bool
        let isGlass: Bool
    }

    struct WaterChunkDrawState: Identifiable {
        let id: UUID
        let center: CGPoint
        let radius: CGFloat
        let opacity: CGFloat
        let velocity: CGVector
        let tailLength: CGFloat
    }

    struct GlassShardDrawState: Identifiable {
        let id: UUID
        let center: CGPoint
        let radius: CGFloat
        let opacity: CGFloat
        let angle: CGFloat
        let stretch: CGFloat
        let kind: Int
        let velocity: CGVector
    }

    private struct Body {
        let id: UUID
        var shape: BodyShape
        var center: CGPoint
        var angle: CGFloat
        var velocity: CGVector
        var angularVelocity: CGFloat
        var localVertices: [CGPoint]?
        var collisionVertices: [CGPoint]?
        var collisionVertexCap: Int
        var isBouncy: Bool
        var isSlippery: Bool
        var isSticky: Bool
        var isGlass: Bool
    }

    private struct WaterChunk {
        let id: UUID
        var center: CGPoint
        var velocity: CGVector
        var radius: CGFloat
        var age: CGFloat
        var life: CGFloat
    }

    private struct GlassShard {
        let id: UUID
        var center: CGPoint
        var velocity: CGVector
        var radius: CGFloat
        var age: CGFloat
        var life: CGFloat
        var angle: CGFloat
        var angularVelocity: CGFloat
        var stretch: CGFloat
        var kind: Int
    }

    private struct GlassShatterRequest {
        let id: UUID
        let point: CGPoint
        let normal: CGVector
        let impulse: CGFloat
        let sourceVelocity: CGVector
    }

    private struct GlassBreakContact {
        let point: CGPoint
        let normal: CGVector
        let sourceVelocity: CGVector
    }

    private struct DragSample {
        let time: TimeInterval
        let position: CGPoint
    }

    private struct ContactPoint {
        var position: CGPoint
        var penetration: CGFloat
    }

    private struct CollisionManifold {
        var normal: CGVector
        var contacts: [ContactPoint]
    }

    private struct WeldConstraint {
        var firstID: UUID
        var secondID: UUID
        var firstLocalAnchor: CGPoint
        var secondLocalAnchor: CGPoint
        var restAngle: CGFloat
    }

    private struct GroundContact {
        var penetration: CGFloat
        var point: CGPoint
        var supportWidth: CGFloat
    }

    private struct CollisionPair: Hashable {
        let first: Int
        let second: Int
    }

    private(set) var samples: [CGFloat]
    private(set) var bodyDrawStates: [BodyDrawState]
    private(set) var weldCursorPoint: CGPoint?
    private(set) var weldPendingPoint: CGPoint?
    private(set) var wheelCursorPoint: CGPoint?
    private(set) var drawingPreviewPoints: [CGPoint] = []
    private(set) var drawingPreviewClosed: Bool = false
    private(set) var waterChunkDrawStates: [WaterChunkDrawState] = []
    private(set) var glassShardDrawStates: [GlassShardDrawState] = []
    @Published private(set) var selectionRect: CGRect?
    @Published var sceneLocation: SceneLocation = .land {
        didSet {
            if sceneLocation == .land {
                pointerX = nil
                pointerStrength = 0
                waterChunks.removeAll(keepingCapacity: true)
                waterChunkDrawStates = []
            }
        }
    }
    @Published var language: AppLanguage
    @Published var theme: AppTheme
    @Published var maxUpDisplacement: CGFloat = 235
    @Published var maxDownDisplacement: CGFloat = 142
    @Published var softUpLimitStart: CGFloat = 146
    @Published var softDownLimitStart: CGFloat = 104
    @Published var maxVelocity: CGFloat = 10.8
    @Published var stiffnessBase: CGFloat = 0.097
    @Published var stiffnessActivity: CGFloat = 0.05
    @Published var dampingBase: CGFloat = 0.9963
    @Published var dampingActivity: CGFloat = 0.0025
    @Published var viscosity: CGFloat = 0.012
    @Published var keyboardActivityGain: CGFloat = 0.14
    @Published var keyboardImpulseBase: CGFloat = 2.6
    @Published var keyboardImpulseScale: CGFloat = 6.4
    @Published var keyboardRadiusMin: CGFloat = 8
    @Published var keyboardRadiusMax: CGFloat = 26
    @Published var pointerRadiusBase: CGFloat = 12
    @Published var pointerRadiusScale: CGFloat = 20
    @Published var pointerDepthBase: CGFloat = 0.08
    @Published var pointerDepthScale: CGFloat = 0.48
    @Published var pointerDepthActivityScale: CGFloat = 0.12
    @Published var pointerForceBase: CGFloat = 0.011
    @Published var pointerForceScale: CGFloat = 0.04
    @Published var pointerSmoothing: CGFloat = 0.1
    @Published var pointerSuppressionStart: CGFloat = 70
    @Published var pointerSuppressionFull: CGFloat = 130
    @Published var pointerSuppressionMin: CGFloat = 0.18
    @Published var squareMass: CGFloat = 4.2
    @Published var squareInertia: CGFloat = 7600
    @Published var gravityForce: CGFloat = 0.6
    @Published var fallAccelerationScale: CGFloat = 1.2
    @Published var spawnKind: SpawnKind = .cube
    @Published var primarySelectionID: UUID?
    @Published var waterContactThreshold: CGFloat = 0.1
    @Published var buoyancyBase: CGFloat = 0.018
    @Published var buoyancyScale: CGFloat = 0.03
    @Published var dragXBase: CGFloat = 0.01
    @Published var dragXScale: CGFloat = 0.018
    @Published var dragYBase: CGFloat = 0.014
    @Published var dragYScale: CGFloat = 0.023
    @Published var waterSlopeFactor: CGFloat = 0.72
    @Published var reactionImpulseScale: CGFloat = 0.026
    @Published var surfaceTargetImmersion: CGFloat = 0.2
    @Published var surfaceSpring: CGFloat = 0.018
    @Published var surfaceDamping: CGFloat = 0.07
    @Published var squareVelocityLimitX: CGFloat = 10.0
    @Published var squareVelocityLimitY: CGFloat = 18.0
    @Published var squareAngularLimit: CGFloat = 0.095
    @Published var dragThrowLinearInertia: CGFloat = 3.0
    @Published var dragThrowAngularInertia: CGFloat = 2.2
    @Published var dragThrowClampScale: CGFloat = 2.6
    @Published var dragThrowAcceleration: CGFloat = 1.0
    @Published var keyboardRotateStepDegrees: CGFloat = 6.3
    @Published var keyboardRotateSnapDegrees: CGFloat = 15
    @Published var wallBounceX: CGFloat = 0.14
    @Published var wallBounceTop: CGFloat = 0.1
    @Published var wallBounceBottom: CGFloat = 0.09
    @Published var cubeCollisionEnabled: Bool = true
    @Published var collisionRestitution: CGFloat = 0.0
    @Published var collisionFriction: CGFloat = 1.3
    @Published var collisionImpulseScale: CGFloat = 1.0
    @Published var collisionAngularTransfer: CGFloat = 0.4
    @Published var collisionPositionCorrection: CGFloat = 0.8
    @Published var collisionSlop: CGFloat = 0.01
    @Published var collisionIterations: CGFloat = 22
    @Published var collisionQuality: CGFloat = 1.0 {
        didSet {
            let clamped = min(max(collisionQuality, 0.2), 1.0)
            if abs(clamped - collisionQuality) > 0.0001 {
                collisionQuality = clamped
                return
            }
            rebuildCollisionMeshes()
        }
    }
    @Published var waterSprayEnabled: Bool = true
    @Published var waterSprayMaxCount: CGFloat = 220
    @Published var waterSprayImpulseThreshold: CGFloat = 9.8
    @Published var waterSprayImpulseEnergy: CGFloat = 0.022
    @Published var waterSprayImpactThreshold: CGFloat = 0.9
    @Published var waterSprayImpactEnergy: CGFloat = 0.16
    @Published var waterSprayGravityScale: CGFloat = 0.17
    @Published var waterSprayLinearDamping: CGFloat = 0.994
    @Published var waterSprayAbsorbDepth: CGFloat = 0.16
    @Published var waterSprayRadiusMin: CGFloat = 2.0
    @Published var waterSprayRadiusMax: CGFloat = 4.6
    @Published var waterSprayLifeMin: CGFloat = 48
    @Published var waterSprayLifeMax: CGFloat = 130
    @Published var waterSprayOpacityBase: CGFloat = 0.25
    @Published var waterSprayOpacityScale: CGFloat = 0.62
    @Published var waterSprayTailScale: CGFloat = 1.6
    @Published var landSurfaceLevel: CGFloat = 0.72
    @Published var landBounce: CGFloat = 0.0
    @Published var landFriction: CGFloat = 1.3
    @Published var landAngularDamping: CGFloat = 0.99
    @Published var fpsLimit: CGFloat = 60 {
        didSet {
            let clamped = min(max(fpsLimit, 20), 480)
            if abs(clamped - fpsLimit) > 0.0001 {
                fpsLimit = clamped
                return
            }
            rescheduleTimerIfNeeded()
        }
    }
    @Published var timeScale: CGFloat = 1.0 {
        didSet {
            let clamped = min(max(timeScale, 0.2), 2.5)
            if abs(clamped - timeScale) > 0.0001 {
                timeScale = clamped
            }
        }
    }
    @Published var isTimeFrozen: Bool = false
    @Published private(set) var fps: CGFloat = 0
    @Published var drawingTool: DrawingTool = .none {
        didSet {
            if drawingTool != .none {
                weldToolEnabled = false
                wheelToolEnabled = false
                bounceToolEnabled = false
                slipToolEnabled = false
                stickyToolEnabled = false
                glassToolEnabled = false
            }
            clearDrawingState()
        }
    }
    @Published var weldToolEnabled: Bool = false {
        didSet {
            if weldToolEnabled {
                drawingTool = .none
                wheelToolEnabled = false
                bounceToolEnabled = false
                slipToolEnabled = false
                stickyToolEnabled = false
                glassToolEnabled = false
            } else {
                pendingWeldBodyID = nil
                pendingWeldAnchorLocal = nil
                weldPendingPoint = nil
                weldCursorPoint = nil
            }
        }
    }
    @Published var wheelToolEnabled: Bool = false {
        didSet {
            if wheelToolEnabled {
                drawingTool = .none
                weldToolEnabled = false
                bounceToolEnabled = false
                slipToolEnabled = false
                stickyToolEnabled = false
                glassToolEnabled = false
            } else {
                wheelCursorPoint = nil
            }
        }
    }
    @Published var weldLinearStiffness: CGFloat = 0.74
    @Published var weldLinearDamping: CGFloat = 0.24
    @Published var weldAngularStiffness: CGFloat = 0.58
    @Published var weldAngularDamping: CGFloat = 0.26
    @Published var weldIterations: CGFloat = 2
    @Published var bouncyRestitution: CGFloat = 0.85
    @Published var bounceToolEnabled: Bool = false {
        didSet {
            if bounceToolEnabled {
                drawingTool = .none
                weldToolEnabled = false
                wheelToolEnabled = false
                slipToolEnabled = false
                stickyToolEnabled = false
                glassToolEnabled = false
            }
        }
    }
    @Published var slipToolEnabled: Bool = false {
        didSet {
            if slipToolEnabled {
                drawingTool = .none
                weldToolEnabled = false
                wheelToolEnabled = false
                bounceToolEnabled = false
                stickyToolEnabled = false
                glassToolEnabled = false
            }
        }
    }
    @Published var stickyToolEnabled: Bool = false {
        didSet {
            if stickyToolEnabled {
                drawingTool = .none
                weldToolEnabled = false
                wheelToolEnabled = false
                bounceToolEnabled = false
                slipToolEnabled = false
                glassToolEnabled = false
            }
        }
    }

    @Published var glassToolEnabled: Bool = false {
        didSet {
            if glassToolEnabled {
                drawingTool = .none
                weldToolEnabled = false
                wheelToolEnabled = false
                bounceToolEnabled = false
                slipToolEnabled = false
                stickyToolEnabled = false
            }
        }
    }

    var accentColor: Color {
        theme == .dark ? .white : .black
    }

    var backgroundColor: Color {
        theme == .dark ? .black : .white
    }

    var panelBackgroundColor: Color {
        theme == .dark ? Color.black.opacity(0.72) : Color.white.opacity(0.84)
    }

    var selectionColor: Color {
        Color(red: 0.2, green: 0.7, blue: 1.0)
    }

    var preferredRenderInterval: Double {
        1.0 / Double(min(60, max(20, effectiveTickFPS())))
    }

    func surfaceBaselineY(in size: CGSize) -> CGFloat {
        if sceneLocation == .land {
            let clampedLevel = min(max(landSurfaceLevel, 0.55), 0.9)
            return size.height * clampedLevel
        }
        return size.height * 0.5
    }

    let squareSize: CGFloat = 56
    let circleRadius: CGFloat = 28

    private let pointCount = 320
    private let physicsStep: CGFloat = 1.0 / 60.0
    private var velocities: [CGFloat]
    private var timer: Timer?
    private var activity: CGFloat = 0
    private var pointerX: CGFloat?
    private var pointerStrength: CGFloat = 0
    private var surfaceSpread: CGFloat = 0
    private var viewportSize: CGSize = .zero
    private var bodies: [Body]
    private var draggingBodyIndex: Int?
    private var dragOffset: CGSize = .zero
    private var lastDragCenter: CGPoint?
    private var lastDragTimestamp: TimeInterval?
    private var recentDragVelocity: CGVector = .zero
    private var recentDragAngularVelocity: CGFloat = 0
    private var dragSamples: [DragSample] = []
    private var weldConstraints: [WeldConstraint] = []
    private var wheelBodies: Set<UUID> = []
    private var pendingWeldBodyID: UUID?
    private var pendingWeldAnchorLocal: CGPoint?
    private var bodyIndexByID: [UUID: Int] = [:]
    private var spawnedBodyHistory: [UUID] = []
    private var selectedBodyIDs: Set<UUID> = []
    private var selectionDragStart: CGPoint?
    private var selectionDragActive = false
    private var selectionMoveStart: CGPoint?
    private var selectionMoveCenters: [UUID: CGPoint] = [:]
    private var selectionMoveActive = false
    private var bodySplashCooldown: [UUID: CGFloat] = [:]
    private var throwCooldown: [UUID: Int] = [:]
    private var lastTickTimestamp: CFAbsoluteTime?
    private var tickInFlight = false
    private var simulationAccumulator: CFAbsoluteTime = 0
    private var smoothedFPS: CGFloat = 0
    private var fpsSampleTime: CFAbsoluteTime = 0
    private var fpsSampleSum: CGFloat = 0
    private var fpsSampleCount: Int = 0
    private var waterChunks: [WaterChunk] = []
    private var glassShards: [GlassShard] = []
    private var pendingGlassShatters: [UUID: GlassShatterRequest] = [:]
    private var glassDamage: [UUID: CGFloat] = [:]
    private var glassImpactInput: [UUID: CGFloat] = [:]
    private var glassBreakContact: [UUID: GlassBreakContact] = [:]
    private var glassGraceFrames: [UUID: Int] = [:]
    private var didApplySystemDefaults = false
    private var lastPointerLocation: CGPoint?
    private var wasShiftPressed = false
    private var drawingStartPoint: CGPoint?
    private var freeformPoints: [CGPoint] = []

    init() {
        let start = Array(repeating: CGFloat.zero, count: pointCount)
        self.samples = start
        self.velocities = start
        let firstBody = Body(
            id: UUID(),
            shape: .cube,
            center: .zero,
            angle: 0,
            velocity: .zero,
            angularVelocity: 0,
            localVertices: nil,
            collisionVertices: nil,
            collisionVertexCap: 0,
            isBouncy: false,
            isSlippery: false,
            isSticky: false,
            isGlass: false
        )
        self.bodies = [firstBody]
        self.bodyDrawStates = [
            BodyDrawState(
                id: firstBody.id,
                shape: firstBody.shape,
                center: firstBody.center,
                angle: firstBody.angle,
                localVertices: nil,
                isWheel: false,
                isSelected: false,
                isBouncy: false,
                isSlippery: false,
                isSticky: false,
                isGlass: false
            )
        ]
        self.weldCursorPoint = nil
        self.weldPendingPoint = nil
        self.wheelCursorPoint = nil
        self.language = Self.systemLanguage()
        self.theme = .dark
    }

    func start() {
        guard timer == nil else { return }
        scheduleTickTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTickTimestamp = nil
        tickInFlight = false
        simulationAccumulator = 0
        smoothedFPS = 0
        fpsSampleTime = 0
        fpsSampleSum = 0
        fpsSampleCount = 0
        fps = 0
        wasShiftPressed = false
    }

    private func scheduleTickTimer() {
        timer?.invalidate()
        lastTickTimestamp = nil
        tickInFlight = false
        simulationAccumulator = 0
        smoothedFPS = 0
        fpsSampleTime = 0
        fpsSampleSum = 0
        fpsSampleCount = 0

        let targetFPS = effectiveTickFPS()
        let interval = 1.0 / Double(max(20, targetFPS))
        let scheduledTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.tickInFlight { return }
                self.tickInFlight = true
                defer { self.tickInFlight = false }
                self.tick()
            }
        }
        scheduledTimer.tolerance = interval * 0.02
        timer = scheduledTimer
        RunLoop.main.add(scheduledTimer, forMode: .common)
    }

    private func rescheduleTimerIfNeeded() {
        guard timer != nil else { return }
        scheduleTickTimer()
    }

    private func effectiveTickFPS() -> CGFloat {
        min(max(fpsLimit, 20), 480)
    }

    func applySystemDefaultsIfNeeded(colorScheme: ColorScheme) {
        guard !didApplySystemDefaults else { return }
        didApplySystemDefaults = true

        language = Self.systemLanguage()
        theme = (colorScheme == .dark) ? .dark : .light
    }

    func resetTuning() {
        maxUpDisplacement = 235
        maxDownDisplacement = 142
        softUpLimitStart = 146
        softDownLimitStart = 104
        maxVelocity = 10.8
        stiffnessBase = 0.097
        stiffnessActivity = 0.05
        dampingBase = 0.9963
        dampingActivity = 0.0025
        viscosity = 0.012
        keyboardActivityGain = 0.14
        keyboardImpulseBase = 2.6
        keyboardImpulseScale = 6.4
        keyboardRadiusMin = 8
        keyboardRadiusMax = 26
        pointerRadiusBase = 12
        pointerRadiusScale = 20
        pointerDepthBase = 0.08
        pointerDepthScale = 0.48
        pointerDepthActivityScale = 0.12
        pointerForceBase = 0.011
        pointerForceScale = 0.04
        pointerSmoothing = 0.1
        pointerSuppressionStart = 70
        pointerSuppressionFull = 130
        pointerSuppressionMin = 0.18
        squareMass = 4.2
        squareInertia = 7600
        gravityForce = 0.6
        fallAccelerationScale = 1.2
        waterContactThreshold = 0.1
        buoyancyBase = 0.018
        buoyancyScale = 0.03
        dragXBase = 0.01
        dragXScale = 0.018
        dragYBase = 0.014
        dragYScale = 0.023
        waterSlopeFactor = 0.72
        reactionImpulseScale = 0.026
        surfaceTargetImmersion = 0.2
        surfaceSpring = 0.018
        surfaceDamping = 0.07
        squareVelocityLimitX = 10.0
        squareVelocityLimitY = 18.0
        squareAngularLimit = 0.095
        dragThrowLinearInertia = 3.0
        dragThrowAngularInertia = 2.2
        dragThrowClampScale = 2.6
        dragThrowAcceleration = 1.0
        keyboardRotateStepDegrees = 6.3
        keyboardRotateSnapDegrees = 15
        wallBounceX = 0.14
        wallBounceTop = 0.1
        wallBounceBottom = 0.09
        cubeCollisionEnabled = true
        collisionRestitution = 0.0
        collisionFriction = 1.3
        collisionImpulseScale = 1.0
        collisionAngularTransfer = 0.4
        collisionPositionCorrection = 0.8
        collisionSlop = 0.01
        collisionIterations = 22
        collisionQuality = 1.0
        waterSprayEnabled = true
        waterSprayMaxCount = 220
        waterSprayImpulseThreshold = 9.8
        waterSprayImpulseEnergy = 0.022
        waterSprayImpactThreshold = 0.9
        waterSprayImpactEnergy = 0.16
        waterSprayGravityScale = 0.17
        waterSprayLinearDamping = 0.994
        waterSprayAbsorbDepth = 0.16
        waterSprayRadiusMin = 2.0
        waterSprayRadiusMax = 4.6
        waterSprayLifeMin = 48
        waterSprayLifeMax = 130
        waterSprayOpacityBase = 0.25
        waterSprayOpacityScale = 0.62
        waterSprayTailScale = 1.6
        landSurfaceLevel = 0.72
        landBounce = 0.0
        landFriction = 1.3
        landAngularDamping = 0.99
        fpsLimit = 60
        timeScale = 1.0
        weldLinearStiffness = 0.74
        weldLinearDamping = 0.24
        weldAngularStiffness = 0.58
        weldAngularDamping = 0.26
        weldIterations = 2
        bouncyRestitution = 0.85
    }

    func resetAll() {
        resetTuning()
        isTimeFrozen = false
        drawingTool = .none
        weldToolEnabled = false
        wheelToolEnabled = false
        bounceToolEnabled = false
        glassToolEnabled = false
        resetScene()
    }

    func toggleTheme() {
        theme = (theme == .dark) ? .light : .dark
    }

    func toggleTimeFrozen() {
        isTimeFrozen.toggle()
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
            return false
        }

        let isSpace = event.keyCode == 49 || event.charactersIgnoringModifiers == " "
        if isSpace {
            toggleTimeFrozen()
            return true
        }

        let raw = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shiftPressed = event.modifierFlags.contains(.shift)
        let isUndoSpawn = event.keyCode == 6 || raw == "z"
        if isUndoSpawn {
            undoLastSpawnedBody()
            return true
        }

        if raw == "1" {
            selectCursorTool()
            return true
        }

        if raw == "2" {
            drawingTool = .none
            weldToolEnabled = true
            wheelToolEnabled = false
            bounceToolEnabled = false
            return true
        }

        if raw == "3" {
            drawingTool = .none
            weldToolEnabled = false
            wheelToolEnabled = true
            bounceToolEnabled = false
            return true
        }

        if raw == "4" {
            drawingTool = .none
            weldToolEnabled = false
            wheelToolEnabled = false
            bounceToolEnabled.toggle()
            return true
        }

        if raw == "5" {
            toggleSlipTool()
            return true
        }

        if raw == "6" {
            toggleStickyTool()
            return true
        }

        if raw == "7" {
            toggleGlassTool()
            return true
        }

        if event.keyCode == 5 || raw == "g" {
            timeScale = abs(timeScale - 0.5) < 0.01 ? 1.0 : 0.5
            return true
        }

        if event.keyCode == 4 || raw == "h" {
            timeScale = abs(timeScale - 2.0) < 0.01 ? 1.0 : 2.0
            return true
        }

        if event.keyCode == 12 || raw == "q" {
            spawnCube(at: lastPointerLocation)
            return true
        }

        if event.keyCode == 13 || raw == "w" {
            spawnCircle(at: lastPointerLocation)
            return true
        }

        if event.keyCode == 14 || raw == "e" {
            spawnTriangle(at: lastPointerLocation, regular: true)
            return true
        }

        if event.keyCode == 15 || raw == "r" {
            toggleDrawingTool(.quadrilateral)
            return true
        }

        if event.keyCode == 17 || raw == "t" {
            toggleDrawingTool(.ellipse)
            return true
        }

        if event.keyCode == 16 || raw == "y" {
            toggleDrawingTool(.triangle)
            return true
        }

        if event.keyCode == 32 || raw == "u" {
            toggleDrawingTool(.freeform)
            return true
        }

        let rotateLeft = event.keyCode == 0 || raw == "a"
        if rotateLeft {
            rotateObjectFromKeyboard(clockwise: false, snapped: shiftPressed)
            return true
        }

        let rotateRight = event.keyCode == 2 || raw == "d"
        if rotateRight {
            rotateObjectFromKeyboard(clockwise: true, snapped: shiftPressed)
            return true
        }

        registerKeyPress()
        return true
    }

    func handleModifierChange(_ event: NSEvent) {
        let shiftPressed = event.modifierFlags.contains(.shift)
        if shiftPressed, !wasShiftPressed {
            snapDraggedObjectToParallel()
        }
        wasShiftPressed = shiftPressed
    }

    func toggleDrawingTool(_ tool: DrawingTool) {
        drawingTool = (drawingTool == tool) ? .none : tool
    }

    func selectCursorTool() {
        drawingTool = .none
        weldToolEnabled = false
        wheelToolEnabled = false
        bounceToolEnabled = false
        slipToolEnabled = false
        stickyToolEnabled = false
        glassToolEnabled = false
        pendingWeldBodyID = nil
        pendingWeldAnchorLocal = nil
        weldPendingPoint = nil
        weldCursorPoint = nil
        wheelCursorPoint = nil
    }

    func toggleWeldTool() {
        weldToolEnabled.toggle()
        if weldToolEnabled {
            bounceToolEnabled = false
        }
        if !weldToolEnabled {
            pendingWeldBodyID = nil
            pendingWeldAnchorLocal = nil
            weldPendingPoint = nil
            weldCursorPoint = nil
        }
    }

    func toggleWheelTool() {
        wheelToolEnabled.toggle()
        if wheelToolEnabled {
            bounceToolEnabled = false
        }
        if !wheelToolEnabled {
            wheelCursorPoint = nil
        }
    }

    func toggleBounceTool() {
        bounceToolEnabled.toggle()
    }

    func toggleSlipTool() {
        slipToolEnabled.toggle()
    }

    func toggleStickyTool() {
        stickyToolEnabled.toggle()
    }

    func toggleGlassTool() {
        glassToolEnabled.toggle()
    }

    func clearWelds() {
        weldConstraints.removeAll(keepingCapacity: true)
        wheelBodies.removeAll(keepingCapacity: true)
        pendingWeldBodyID = nil
        pendingWeldAnchorLocal = nil
        weldPendingPoint = nil
        weldCursorPoint = nil
        syncBodyDrawStates()
    }

    func clearWheels() {
        wheelBodies.removeAll(keepingCapacity: true)
        wheelCursorPoint = nil
        syncBodyDrawStates()
    }

    private static func systemLanguage() -> AppLanguage {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return .en
        }

        if preferred.hasPrefix("ru") { return .ru }
        if preferred.hasPrefix("en") { return .en }
        return .en
    }

    func setViewportSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }

        let oldSize = viewportSize
        viewportSize = size

        if oldSize.width > 1, oldSize.height > 1 {
            for index in bodies.indices {
                let xRatio = bodies[index].center.x / oldSize.width
                let yRatio = bodies[index].center.y / oldSize.height
                bodies[index].center = CGPoint(x: xRatio * size.width, y: yRatio * size.height)
            }
        } else if !bodies.isEmpty {
            for index in bodies.indices where bodies[index].center == .zero {
                bodies[index].center = defaultBodyCenter(forIndex: index, in: size)
            }
        }

        clampAllBodiesInside()
        syncBodyDrawStates()
        syncWeldPreviewPoints()
    }

    func resetScene() {
        let zeros = Array(repeating: CGFloat.zero, count: pointCount)
        samples = zeros
        velocities = zeros
        activity = 0
        pointerX = nil
        pointerStrength = 0
        surfaceSpread = 0
        lastPointerLocation = nil
        waterChunks.removeAll(keepingCapacity: true)
        waterChunkDrawStates.removeAll(keepingCapacity: true)
        glassShards.removeAll(keepingCapacity: true)
        glassShardDrawStates.removeAll(keepingCapacity: true)
        pendingGlassShatters.removeAll(keepingCapacity: true)
        glassDamage.removeAll(keepingCapacity: true)
        glassImpactInput.removeAll(keepingCapacity: true)
        glassBreakContact.removeAll(keepingCapacity: true)
        glassGraceFrames.removeAll(keepingCapacity: true)
        bodySplashCooldown.removeAll(keepingCapacity: true)
        wasShiftPressed = false

        draggingBodyIndex = nil
        dragOffset = .zero
        lastDragCenter = nil
        lastDragTimestamp = nil
        recentDragVelocity = .zero
        recentDragAngularVelocity = 0
        dragSamples.removeAll(keepingCapacity: true)
        weldConstraints.removeAll(keepingCapacity: true)
        wheelBodies.removeAll(keepingCapacity: true)
        pendingWeldBodyID = nil
        pendingWeldAnchorLocal = nil
        weldPendingPoint = nil
        weldCursorPoint = nil
        wheelCursorPoint = nil
        spawnedBodyHistory.removeAll(keepingCapacity: true)
        clearDrawingState()
        selectedBodyIDs.removeAll(keepingCapacity: true)
        primarySelectionID = nil
        selectionRect = nil
        selectionDragStart = nil
        selectionDragActive = false
        selectionMoveStart = nil
        selectionMoveCenters.removeAll(keepingCapacity: true)
        selectionMoveActive = false

        let spawn = defaultBodyCenter(forIndex: 0, in: viewportSize)
        bodies = [makeBody(shape: .cube, center: spawn)]
        syncBodyDrawStates()
        syncWeldPreviewPoints()
    }

    func addCube() {
        guard bodies.count < 32 else { return }
        spawnKind = .cube

        let hasViewport = viewportSize.width > 1 && viewportSize.height > 1
        let size = hasViewport ? viewportSize : CGSize(width: 1000, height: 560)

        let radius = boundingRadius(for: .cube)
        let spawnX = min(
            max(
                size.width * 0.5 + CGFloat.random(in: -size.width * 0.18...size.width * 0.18),
                radius
            ),
            max(radius, size.width - radius)
        )

        let targetWaterY = hasViewport ? waveHeight(atX: spawnX) : size.height * 0.5
        let spawnY = min(
            max(targetWaterY - squareSize * 0.72 + CGFloat.random(in: -16...16), radius),
            max(radius, size.height - radius)
        )

        var body = makeBody(shape: .cube, center: CGPoint(x: spawnX, y: spawnY))
        body.angle = 0
        body.velocity = .zero
        body.angularVelocity = 0

        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
        syncBodyDrawStates()
    }

    func addCircle() {
        guard bodies.count < 32 else { return }
        spawnKind = .circle
        spawnKind = .circle

        let hasViewport = viewportSize.width > 1 && viewportSize.height > 1
        let size = hasViewport ? viewportSize : CGSize(width: 1000, height: 560)

        let radius = boundingRadius(for: .circle)
        let spawnX = min(
            max(
                size.width * 0.5 + CGFloat.random(in: -size.width * 0.2...size.width * 0.2),
                radius
            ),
            max(radius, size.width - radius)
        )

        let targetWaterY = hasViewport ? waveHeight(atX: spawnX) : size.height * 0.5
        let spawnY = min(
            max(targetWaterY - circleRadius * 1.5 + CGFloat.random(in: -14...14), radius),
            max(radius, size.height - radius)
        )

        var body = makeBody(shape: .circle, center: CGPoint(x: spawnX, y: spawnY))
        body.velocity = .zero
        body.angularVelocity = 0
        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
        syncBodyDrawStates()
    }

    func addTriangle() {
        guard bodies.count < 32 else { return }
        let hasViewport = viewportSize.width > 1 && viewportSize.height > 1
        let size = hasViewport ? viewportSize : CGSize(width: 1000, height: 560)
        let spawnX = size.width * 0.5 + CGFloat.random(in: -size.width * 0.18...size.width * 0.18)
        let targetWaterY = hasViewport ? waveHeight(atX: spawnX) : size.height * 0.5
        let spawnY = targetWaterY - squareSize * 0.5 + CGFloat.random(in: -10...10)
        let center = CGPoint(x: spawnX, y: spawnY)
        let vertices = baseTrianglePoints(center: center)
        addPolygonBody(
            fromWorldVertices: vertices,
            preserveTopology: true,
            targetMaxVertexCount: 3,
            collisionMaxVertexCount: 3
        )
        syncBodyDrawStates()
    }

    private func recordSpawn(_ id: UUID) {
        spawnedBodyHistory.removeAll { $0 == id }
        spawnedBodyHistory.append(id)
        if spawnedBodyHistory.count > 256 {
            spawnedBodyHistory.removeFirst(spawnedBodyHistory.count - 256)
        }
    }

    private func undoLastSpawnedBody() {
        while let id = spawnedBodyHistory.popLast() {
            guard let removeIndex = bodyIndex(forID: id), bodies.indices.contains(removeIndex) else { continue }
            removeBody(at: removeIndex)
            return
        }
    }

    private func removeBody(at index: Int) {
        guard bodies.indices.contains(index) else { return }
        let removedID = bodies[index].id
        bodies.remove(at: index)
        spawnedBodyHistory.removeAll { $0 == removedID }
        bodySplashCooldown.removeValue(forKey: removedID)
        throwCooldown.removeValue(forKey: removedID)
        glassDamage.removeValue(forKey: removedID)
        glassImpactInput.removeValue(forKey: removedID)
        glassBreakContact.removeValue(forKey: removedID)
        glassGraceFrames.removeValue(forKey: removedID)
        pendingGlassShatters.removeValue(forKey: removedID)
        selectedBodyIDs.remove(removedID)
        if primarySelectionID == removedID {
            primarySelectionID = nil
        }
        if selectedBodyIDs.count == 1 {
            primarySelectionID = selectedBodyIDs.first
        }

        if let draggingBodyIndex {
            if draggingBodyIndex == index {
                self.draggingBodyIndex = nil
                dragOffset = .zero
                lastDragCenter = nil
                lastDragTimestamp = nil
                recentDragVelocity = .zero
                recentDragAngularVelocity = 0
            } else if draggingBodyIndex > index {
                self.draggingBodyIndex = draggingBodyIndex - 1
            }
        }

        cleanupWeldState()
        syncBodyDrawStates()
        syncWeldPreviewPoints()
    }

    private func rotateObjectFromKeyboard(clockwise: Bool, snapped: Bool) {
        if selectedBodyIDs.count > 1 {
            rotateSelectedFromKeyboard(clockwise: clockwise, snapped: snapped)
            return
        }
        guard let targetIndex = keyboardRotationTargetIndex(), bodies.indices.contains(targetIndex) else { return }

        let freeStep = max(0.5, keyboardRotateStepDegrees) * .pi / 180
        let snapStep = max(1, keyboardRotateSnapDegrees) * .pi / 180
        let baseStep: CGFloat = snapped ? snapStep : freeStep
        let deltaAngle: CGFloat = clockwise ? baseStep : -baseStep
        applyAngularDelta(deltaAngle, toComponentContaining: targetIndex, zeroAngularVelocity: false)
    }

    private func rotateSelectedFromKeyboard(clockwise: Bool, snapped: Bool) {
        let indices = selectedBodyIDs.compactMap(bodyIndex(forID:))
        guard indices.count > 1 else { return }

        let freeStep = max(0.5, keyboardRotateStepDegrees) * .pi / 180
        let snapStep = max(1, keyboardRotateSnapDegrees) * .pi / 180
        let baseStep: CGFloat = snapped ? snapStep : freeStep
        let deltaAngle: CGFloat = clockwise ? baseStep : -baseStep

        let pivotIndex: Int
        if let primarySelectionID, let primaryIndex = bodyIndex(forID: primarySelectionID) {
            pivotIndex = primaryIndex
        } else if let draggingBodyIndex, indices.contains(draggingBodyIndex) {
            pivotIndex = draggingBodyIndex
        } else {
            pivotIndex = indices[0]
        }
        let pivot = bodies[pivotIndex].center

        let cosA = cos(deltaAngle)
        let sinA = sin(deltaAngle)

        for index in indices where bodies.indices.contains(index) {
            var body = bodies[index]
            let dx = body.center.x - pivot.x
            let dy = body.center.y - pivot.y
            body.center = CGPoint(
                x: pivot.x + dx * cosA - dy * sinA,
                y: pivot.y + dx * sinA + dy * cosA
            )
            body.angle = normalizedAngle(body.angle + deltaAngle)
            body.angularVelocity = 0
            bodies[index] = body
        }

        clampAllBodiesInside()
        syncBodyDrawStates()
        syncWeldPreviewPoints()
    }

    private func snapDraggedObjectToParallel() {
        guard let draggingBodyIndex, bodies.indices.contains(draggingBodyIndex) else { return }
        let targetAngle: CGFloat = 0
        let deltaAngle = normalizedAngle(targetAngle - bodies[draggingBodyIndex].angle)
        if abs(deltaAngle) < 0.0001 { return }
        applyAngularDelta(deltaAngle, toComponentContaining: draggingBodyIndex, zeroAngularVelocity: true)
    }

    private func applyAngularDelta(_ deltaAngle: CGFloat, toComponentContaining targetIndex: Int, zeroAngularVelocity: Bool) {
        let component = weldedComponentIndices(containing: targetIndex)
        let pivot = bodies[targetIndex].center
        let cosA = cos(deltaAngle)
        let sinA = sin(deltaAngle)

        for index in component where bodies.indices.contains(index) {
            var body = bodies[index]
            if index != targetIndex {
                let dx = body.center.x - pivot.x
                let dy = body.center.y - pivot.y
                body.center = CGPoint(
                    x: pivot.x + dx * cosA - dy * sinA,
                    y: pivot.y + dx * sinA + dy * cosA
                )
            }
            body.angle = normalizedAngle(body.angle + deltaAngle)
            if zeroAngularVelocity {
                body.angularVelocity = 0
            } else {
                body.angularVelocity = max(
                    -squareAngularLimit,
                    min(squareAngularLimit, body.angularVelocity + deltaAngle * 0.5)
                )
            }
            bodies[index] = body
        }

        clampAllBodiesInside()
        syncBodyDrawStates()
        syncWeldPreviewPoints()
    }

    private func recordDragSample(position: CGPoint, time: TimeInterval) {
        dragSamples.append(DragSample(time: time, position: position))
        if dragSamples.count > 8 {
            dragSamples.removeFirst(dragSamples.count - 8)
        }
    }

    private func smoothedDragVelocity(currentTime: TimeInterval) -> CGVector {
        let window = dragSamples.filter { currentTime - $0.time <= 0.18 }
        guard let first = window.first, let last = window.last, window.count >= 2 else { return .zero }

        let dt = max(CGFloat(last.time - first.time), 1.0 / 240.0)
        let vx = (last.position.x - first.position.x) / (dt * 60)
        let vy = (last.position.y - first.position.y) / (dt * 60)
        return CGVector(dx: vx, dy: vy)
    }

    private func stabilizedThrowVelocity(_ velocity: CGVector) -> CGVector {
        let absX = abs(velocity.dx)
        let absY = abs(velocity.dy)
        if absX > absY * 1.6 {
            let dampedY = absY < 0.6 ? 0 : velocity.dy * 0.2
            return CGVector(dx: velocity.dx, dy: dampedY)
        }
        if absY > absX * 1.6 {
            let dampedX = absX < 0.6 ? 0 : velocity.dx * 0.2
            return CGVector(dx: dampedX, dy: velocity.dy)
        }
        return velocity
    }

    private func keyboardRotationTargetIndex() -> Int? {
        if let primarySelectionID, let primaryIndex = bodyIndex(forID: primarySelectionID) {
            return primaryIndex
        }
        if selectedBodyIDs.count == 1, let id = selectedBodyIDs.first, let index = bodyIndex(forID: id) {
            return index
        }
        return nil
    }

    func registerKeyPress() {
        guard !isTimeFrozen else { return }
        guard sceneLocation == .water else { return }
        activity = min(1, activity + keyboardActivityGain)
        let drops = 1 + Int(activity * 2)
        let baseImpulse = keyboardImpulseBase + activity * keyboardImpulseScale

        for _ in 0..<drops {
            let direction: CGFloat = Bool.random() ? 1 : -1
            let intensityJitter = CGFloat.random(in: 0.82...1.2)
            addDropImpulse(impulse: baseImpulse * intensityJitter * direction)
        }
    }

    func pointerMoved(
        to location: CGPoint?,
        timestamp: TimeInterval,
        in size: CGSize,
        isShiftPressed: Bool = false
    ) {
        setViewportSize(size)
        lastPointerLocation = location
        weldCursorPoint = weldToolEnabled ? location : nil
        wheelCursorPoint = wheelToolEnabled ? location : nil
        syncWeldPreviewPoints()

        if selectionDragActive {
            if let location {
                updateSelectionRect(to: location, additive: isShiftPressed)
            }
            pointerX = nil
            pointerStrength = 0
            return
        }

        if selectionMoveActive {
            guard let location else { return }
            guard let start = selectionMoveStart else { return }
            let dx = location.x - start.x
            let dy = location.y - start.y
            for (id, center) in selectionMoveCenters {
                guard let index = bodyIndex(forID: id), bodies.indices.contains(index) else { continue }
                var body = bodies[index]
                body.center = clampedBodyCenter(
                    CGPoint(x: center.x + dx, y: center.y + dy),
                    for: body
                )
                body.velocity = .zero
                body.angularVelocity = 0
                bodies[index] = body
            }
            if isTimeFrozen {
                resolveWheelPinnedCenters()
                syncWeldPreviewPoints()
            }
            pointerX = nil
            pointerStrength = 0
            syncBodyDrawStates()
            return
        }

        if drawingTool != .none {
            if let location {
                updateDrawing(at: location, constrained: isShiftPressed)
            }
            pointerX = nil
            pointerStrength = 0
            return
        }

        if let draggingBodyIndex {
            guard let location else { return }
            guard bodies.indices.contains(draggingBodyIndex) else {
                self.draggingBodyIndex = nil
                return
            }

            let target = CGPoint(
                x: location.x + dragOffset.width,
                y: location.y + dragOffset.height
            )
            let clamped = clampedDragCenter(target, for: bodies[draggingBodyIndex])

            var body = bodies[draggingBodyIndex]

            if !isTimeFrozen {
                recordDragSample(position: clamped, time: timestamp)
                let velocity = stabilizedThrowVelocity(smoothedDragVelocity(currentTime: timestamp))
                let speed = hypot(velocity.dx, velocity.dy)
                let accelFactor = 1 + max(0, dragThrowAcceleration) * min(2.2, speed / 6)
                let linearScale = max(0, dragThrowLinearInertia) * accelFactor
                let angularScale = max(0, dragThrowAngularInertia) * accelFactor
                let scaledVelocity = CGVector(dx: velocity.dx * linearScale, dy: velocity.dy * linearScale)

                recentDragVelocity = scaledVelocity

                let lever = CGVector(dx: -dragOffset.width, dy: -dragOffset.height)
                let leverSq = max(1, lever.dx * lever.dx + lever.dy * lever.dy)
                let measuredAngular = cross(lever, velocity) / leverSq
                recentDragAngularVelocity = measuredAngular * angularScale

                body.velocity = scaledVelocity
                body.angularVelocity = measuredAngular * angularScale
            }

            body.center = clamped
            if isTimeFrozen {
                body.velocity = .zero
                body.angularVelocity = 0
            }
            bodies[draggingBodyIndex] = body
            lastDragCenter = clamped
            lastDragTimestamp = timestamp
            propagateDraggedWeldComponent(from: draggingBodyIndex)
            if isTimeFrozen {
                resolveWheelPinnedCenters()
            }

            pointerX = nil
            pointerStrength = 0
            syncBodyDrawStates()
            syncWeldPreviewPoints()
            return
        }

        if weldToolEnabled {
            pointerX = nil
            pointerStrength = 0
            return
        }

        if wheelToolEnabled {
            pointerX = nil
            pointerStrength = 0
            return
        }

        if bounceToolEnabled {
            pointerX = nil
            pointerStrength = 0
            return
        }

        updatePointer(at: location, in: size)
    }

    func pointerDown(
        at location: CGPoint,
        button: MouseButton,
        timestamp: TimeInterval,
        in size: CGSize,
        isShiftPressed: Bool = false
    ) {
        setViewportSize(size)
        lastPointerLocation = location
        weldCursorPoint = weldToolEnabled ? location : nil
        wheelCursorPoint = wheelToolEnabled ? location : nil

        switch button {
        case .left:
            selectionDragActive = false
            selectionRect = nil
            selectionDragStart = nil
            selectionMoveActive = false
            selectionMoveStart = nil
            selectionMoveCenters.removeAll(keepingCapacity: true)

            if drawingTool != .none {
                beginDrawing(at: location, constrained: isShiftPressed)
                pointerX = nil
                pointerStrength = 0
                return
            }

            if weldToolEnabled {
                handleWeldSelection(at: location)
                pointerX = nil
                pointerStrength = 0
                syncBodyDrawStates()
                return
            }

            if wheelToolEnabled {
                handleWheelSelection(at: location)
                pointerX = nil
                pointerStrength = 0
                syncBodyDrawStates()
                return
            }

            if bounceToolEnabled {
                handleBounceSelection(at: location)
                pointerX = nil
                pointerStrength = 0
                syncBodyDrawStates()
                return
            }

            if slipToolEnabled {
                handleSlipSelection(at: location)
                pointerX = nil
                pointerStrength = 0
                syncBodyDrawStates()
                return
            }

            if stickyToolEnabled {
                handleStickySelection(at: location)
                pointerX = nil
                pointerStrength = 0
                syncBodyDrawStates()
                return
            }

            if glassToolEnabled {
                handleGlassSelection(at: location)
                pointerX = nil
                pointerStrength = 0
                syncBodyDrawStates()
                return
            }

            if let index = bodyIndex(containing: location) {
                let bodyID = bodies[index].id
                if !selectedBodyIDs.contains(bodyID) {
                    selectedBodyIDs = [bodyID]
                }
                primarySelectionID = bodyID

                if isTimeFrozen, selectedBodyIDs.count > 1 {
                    selectionMoveActive = true
                    selectionMoveStart = location
                    selectionMoveCenters = [:]
                    for id in selectedBodyIDs {
                        if let idx = bodyIndex(forID: id), bodies.indices.contains(idx) {
                            selectionMoveCenters[id] = bodies[idx].center
                        }
                    }
                    pointerX = nil
                    pointerStrength = 0
                    syncBodyDrawStates()
                    return
                }

                draggingBodyIndex = index
                let center = bodies[index].center
                dragOffset = CGSize(
                    width: center.x - location.x,
                    height: center.y - location.y
                )
                lastDragCenter = center
                lastDragTimestamp = timestamp
                recentDragVelocity = .zero
                recentDragAngularVelocity = 0
                dragSamples = [DragSample(time: timestamp, position: center)]
                let weldedIndices = weldedComponentIndices(containing: index)
                for weldedIndex in weldedIndices {
                    bodies[weldedIndex].velocity = .zero
                    bodies[weldedIndex].angularVelocity *= 0.35
                }
                pointerX = nil
                pointerStrength = 0
                syncBodyDrawStates()
                syncWeldPreviewPoints()
                return
            }

            if !isShiftPressed {
                selectedBodyIDs.removeAll(keepingCapacity: true)
                primarySelectionID = nil
            }
            selectionDragStart = location
            selectionDragActive = true
            selectionRect = CGRect(origin: location, size: .zero)
            syncBodyDrawStates()
            pointerX = nil
            pointerStrength = 0
            return

        case .right:
            if weldToolEnabled || wheelToolEnabled || bounceToolEnabled || drawingTool != .none {
                return
            }

            if let index = bodyIndex(containing: location) {
                removeBody(at: index)
                pointerX = nil
                pointerStrength = 0
                return
            }

            if isTimeFrozen { return }
            updatePointer(at: location, in: size)
            registerPointerClick(at: location, in: size)
        }
    }

    func pointerUp(
        at location: CGPoint,
        button: MouseButton,
        timestamp: TimeInterval,
        in size: CGSize,
        isShiftPressed: Bool = false
    ) {
        setViewportSize(size)
        lastPointerLocation = location
        weldCursorPoint = weldToolEnabled ? location : nil
        wheelCursorPoint = wheelToolEnabled ? location : nil

        if button == .left, drawingTool != .none {
            endDrawing(at: location, constrained: isShiftPressed)
            pointerX = nil
            pointerStrength = 0
            return
        }

        if button == .left, selectionMoveActive {
            selectionMoveActive = false
            selectionMoveStart = nil
            selectionMoveCenters.removeAll(keepingCapacity: true)
            resolveWheelPinnedCenters()
            syncBodyDrawStates()
            syncWeldPreviewPoints()
            return
        }

        if button == .left, selectionDragActive {
            selectionDragActive = false
            selectionDragStart = nil
            if let rect = selectionRect, rect.width < 4, rect.height < 4, !isShiftPressed {
                selectedBodyIDs.removeAll(keepingCapacity: true)
                primarySelectionID = nil
            }
            selectionRect = nil
            if selectedBodyIDs.count == 1 {
                primarySelectionID = selectedBodyIDs.first
            }
            syncBodyDrawStates()
            return
        }

        if button == .left, let index = draggingBodyIndex {
            guard bodies.indices.contains(index) else {
                draggingBodyIndex = nil
                lastDragCenter = nil
                lastDragTimestamp = nil
                recentDragVelocity = .zero
                recentDragAngularVelocity = 0
                dragSamples.removeAll(keepingCapacity: true)
                return
            }

            if isTimeFrozen {
                draggingBodyIndex = nil
                lastDragCenter = nil
                lastDragTimestamp = nil
                recentDragVelocity = .zero
                recentDragAngularVelocity = 0
                dragSamples.removeAll(keepingCapacity: true)
                resolveWheelPinnedCenters()
                syncBodyDrawStates()
                syncWeldPreviewPoints()
                return
            }

            var root = bodies[index]
            let target = CGPoint(
                x: location.x + dragOffset.width,
                y: location.y + dragOffset.height
            )
            let clamped = clampedDragCenter(target, for: root)
            root.center = clamped
            bodies[index] = root

            // Preserve current velocity/rotation for true inertial release.
            propagateDraggedWeldComponent(from: index)
            let releasedIndices = weldedComponentIndices(containing: index)
            for releasedIndex in releasedIndices where bodies.indices.contains(releasedIndex) {
                throwCooldown[bodies[releasedIndex].id] = 14
            }
            draggingBodyIndex = nil
            lastDragCenter = nil
            lastDragTimestamp = nil
            recentDragVelocity = .zero
            recentDragAngularVelocity = 0
            dragSamples.removeAll(keepingCapacity: true)
            syncBodyDrawStates()
            syncWeldPreviewPoints()
        }
    }

    private func beginDrawing(at point: CGPoint, constrained: Bool) {
        drawingStartPoint = point
        switch drawingTool {
        case .none:
            clearDrawingState()
        case .quadrilateral, .ellipse, .triangle:
            updateDrawing(at: point, constrained: constrained)
        case .freeform:
            freeformPoints = [point]
            drawingPreviewPoints = freeformPoints
            drawingPreviewClosed = false
        }
    }

    private func updateDrawing(at point: CGPoint, constrained: Bool) {
        guard drawingTool != .none else { return }
        guard drawingStartPoint != nil else { return }
        let endPoint = constrainedDragEnd(from: drawingStartPoint ?? point, to: point, constrained: constrained)

        switch drawingTool {
        case .none:
            return
        case .quadrilateral:
            drawingPreviewPoints = rectanglePoints(from: drawingStartPoint ?? point, to: endPoint)
            drawingPreviewClosed = true
        case .ellipse:
            drawingPreviewPoints = ellipsePoints(from: drawingStartPoint ?? point, to: endPoint, segmentCount: 96)
            drawingPreviewClosed = true
        case .triangle:
            drawingPreviewPoints = trianglePoints(from: drawingStartPoint ?? point, to: endPoint)
            drawingPreviewClosed = true
        case .freeform:
            if let last = freeformPoints.last {
                let dx = point.x - last.x
                let dy = point.y - last.y
                if dx * dx + dy * dy >= 9 {
                    freeformPoints.append(point)
                } else {
                    freeformPoints[freeformPoints.count - 1] = point
                }
            } else {
                freeformPoints = [point]
            }
            drawingPreviewPoints = freeformPoints
            drawingPreviewClosed = false
        }
    }

    private func endDrawing(at point: CGPoint, constrained: Bool) {
        guard drawingTool != .none else { return }
        guard drawingStartPoint != nil else { return }
        let endPoint = constrainedDragEnd(from: drawingStartPoint ?? point, to: point, constrained: constrained)
        updateDrawing(at: point, constrained: constrained)

        switch drawingTool {
        case .none:
            break
        case .quadrilateral:
            addPolygonBody(
                fromWorldVertices: rectanglePoints(from: drawingStartPoint ?? point, to: endPoint),
                preserveTopology: true,
                targetMaxVertexCount: 4,
                collisionMaxVertexCount: 4
            )
        case .ellipse:
            addPolygonBody(
                fromWorldVertices: ellipsePoints(from: drawingStartPoint ?? point, to: endPoint, segmentCount: 84),
                preserveTopology: true,
                targetMaxVertexCount: 84,
                collisionMaxVertexCount: 32
            )
        case .triangle:
            addPolygonBody(
                fromWorldVertices: trianglePoints(from: drawingStartPoint ?? point, to: endPoint),
                preserveTopology: true,
                targetMaxVertexCount: 3,
                collisionMaxVertexCount: 3
            )
        case .freeform:
            addPolygonBody(
                fromWorldVertices: freeformPoints,
                preserveTopology: true,
                targetMaxVertexCount: 90,
                collisionMaxVertexCount: 18
            )
        }

        clearDrawingState()
        syncBodyDrawStates()
    }

    private func clearDrawingState() {
        drawingStartPoint = nil
        freeformPoints.removeAll(keepingCapacity: true)
        drawingPreviewPoints.removeAll(keepingCapacity: true)
        drawingPreviewClosed = false
    }

    private func spawnLocation(_ location: CGPoint?, shape: BodyShape) -> CGPoint {
        if let location {
            return clampedBodyCenter(location, for: makeBody(shape: shape, center: location))
        }
        let hasViewport = viewportSize.width > 1 && viewportSize.height > 1
        let size = hasViewport ? viewportSize : CGSize(width: 1000, height: 560)
        return CGPoint(x: size.width * 0.5, y: size.height * 0.4)
    }

    private func spawnCube(at location: CGPoint?) {
        guard bodies.count < 32 else { return }
        let center = spawnLocation(location, shape: .cube)
        var body = makeBody(shape: .cube, center: center)
        body.angle = 0
        body.velocity = .zero
        body.angularVelocity = 0
        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
        syncBodyDrawStates()
    }

    private func spawnCircle(at location: CGPoint?) {
        guard bodies.count < 32 else { return }
        let center = spawnLocation(location, shape: .circle)
        let body = makeBody(shape: .circle, center: center)
        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
        syncBodyDrawStates()
    }

    private func spawnTriangle(at location: CGPoint?, regular: Bool) {
        guard bodies.count < 32 else { return }
        let center = spawnLocation(location, shape: .polygon)
        if regular {
            let local = baseTriangleLocalPoints()
            var body = makeBody(
                shape: .polygon,
                center: center,
                localVertices: local,
                collisionVertices: local,
                collisionVertexCap: 3
            )
            body.velocity = .zero
            body.angularVelocity = 0
            bodies.append(body)
            recordSpawn(body.id)
            clampAllBodiesInside()
        } else {
            let vertices = randomTrianglePoints(center: center)
            addPolygonBody(
                fromWorldVertices: vertices,
                preserveTopology: true,
                targetMaxVertexCount: 3,
                collisionMaxVertexCount: 3
            )
        }
        syncBodyDrawStates()
    }

    private func spawnQuad(at location: CGPoint?) {
        guard bodies.count < 32 else { return }
        let center = spawnLocation(location, shape: .polygon)
        let half = squareSize * 0.5
        let vertices = [
            CGPoint(x: center.x - half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y + half),
            CGPoint(x: center.x - half, y: center.y + half)
        ]
        addPolygonBody(
            fromWorldVertices: vertices,
            preserveTopology: true,
            targetMaxVertexCount: 4,
            collisionMaxVertexCount: 4
        )
        syncBodyDrawStates()
    }

    private func spawnCirclePolygon(at location: CGPoint?) {
        guard bodies.count < 32 else { return }
        let center = spawnLocation(location, shape: .polygon)
        let radius = circleRadius
        let vertices = ellipsePoints(from: CGPoint(x: center.x - radius, y: center.y - radius), to: CGPoint(x: center.x + radius, y: center.y + radius), segmentCount: 84)
        addPolygonBody(
            fromWorldVertices: vertices,
            preserveTopology: true,
            targetMaxVertexCount: 84,
            collisionMaxVertexCount: 32
        )
        syncBodyDrawStates()
    }

    private func spawnFreeform(at location: CGPoint?) {
        guard bodies.count < 32 else { return }
        let center = spawnLocation(location, shape: .polygon)
        let half = squareSize * 0.5
        let vertices = [
            CGPoint(x: center.x - half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y + half),
            CGPoint(x: center.x - half, y: center.y + half),
            CGPoint(x: center.x - half * 0.7, y: center.y)
        ]
        addPolygonBody(
            fromWorldVertices: vertices,
            preserveTopology: true,
            targetMaxVertexCount: 8,
            collisionMaxVertexCount: 8
        )
        syncBodyDrawStates()
    }

    private func baseTrianglePoints(center: CGPoint) -> [CGPoint] {
        baseTriangleLocalPoints().map { CGPoint(x: center.x + $0.x, y: center.y + $0.y) }
    }

    private func baseTriangleLocalPoints() -> [CGPoint] {
        // Keep triangle in the same h x h box as square/circle:
        // base = h and height = h around the center.
        let height = squareSize
        let side = squareSize
        let topY = -height * 0.5
        let baseY = height * 0.5
        let halfSide = side * 0.5
        return [
            CGPoint(x: 0, y: topY),
            CGPoint(x: halfSide, y: baseY),
            CGPoint(x: -halfSide, y: baseY)
        ]
    }

    private func randomTrianglePoints(center: CGPoint) -> [CGPoint] {
        let r = squareSize * 0.65
        let angles = [
            CGFloat.random(in: 0..<(.pi * 2)),
            CGFloat.random(in: 0..<(.pi * 2)),
            CGFloat.random(in: 0..<(.pi * 2))
        ].sorted()
        var points = angles.map { angle in
            CGPoint(
                x: center.x + cos(angle) * r * CGFloat.random(in: 0.6...1),
                y: center.y + sin(angle) * r * CGFloat.random(in: 0.6...1)
            )
        }
        let centroid = polygonCentroid(points)
        let dx = center.x - centroid.x
        let dy = center.y - centroid.y
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return points
    }

    private func constrainedDragEnd(from start: CGPoint, to end: CGPoint, constrained: Bool) -> CGPoint {
        guard constrained else { return end }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        if side < 0.0001 { return end }
        return CGPoint(
            x: start.x + (dx < 0 ? -side : side),
            y: start.y + (dy < 0 ? -side : side)
        )
    }

    private func trianglePoints(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        let width = maxX - minX
        let height = maxY - minY
        // Keep editable triangle in an h x h box (base == height).
        let side = min(width, height)
        let triHeight = side
        let midX = (minX + maxX) * 0.5
        let apexY = minY + (height - triHeight) * 0.5
        let baseY = apexY + triHeight
        let halfSide = side * 0.5
        return [
            CGPoint(x: midX, y: apexY),
            CGPoint(x: midX + halfSide, y: baseY),
            CGPoint(x: midX - halfSide, y: baseY)
        ]
    }

    private func updatePointer(at location: CGPoint?, in size: CGSize) {
        guard sceneLocation == .water else {
            pointerX = nil
            pointerStrength = 0
            return
        }

        guard
            let location,
            size.width > 1,
            size.height > 1
        else {
            pointerX = nil
            pointerStrength = 0
            return
        }

        let normalizedX = max(0, min(1, location.x / size.width))
        let distanceToObject = bodies
            .map { hypot(location.x - $0.center.x, location.y - $0.center.y) - boundingRadius(for: $0) * 0.85 }
            .min() ?? .greatestFiniteMagnitude
        let squareInfluenceRadius = squareSize * 1.25
        if distanceToObject < squareInfluenceRadius {
            pointerX = nil
            pointerStrength = 0
            return
        }

        let centerY = size.height * 0.5
        let verticalDistance = abs(location.y - centerY)
        let maxDistance = max(size.height * 0.45, 1)
        let distanceFactor = min(1, verticalDistance / maxDistance)
        let proximity = 1 - distanceFactor

        pointerX = normalizedX
        let targetStrength = pow(proximity, 1.6)
        let smoothing = min(max(pointerSmoothing, 0.01), 1)
        pointerStrength = pointerStrength * (1 - smoothing) + targetStrength * smoothing
    }

    func registerPointerClick(at location: CGPoint, in size: CGSize) {
        guard sceneLocation == .water else { return }
        guard size.width > 1 else { return }

        updatePointer(at: location, in: size)
        let normalizedX = max(0, min(1, location.x / size.width))

        activity = min(1, activity + 0.28)

        let primaryRadius = Int(20 + activity * 28)
        let primaryImpulse = 12 + activity * 20
        addDropImpulse(
            centerNormalizedX: normalizedX,
            radius: primaryRadius,
            impulse: primaryImpulse
        )

        addDropImpulse(
            centerNormalizedX: normalizedX,
            radius: primaryRadius + 12,
            impulse: -primaryImpulse * 0.42
        )
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        let targetFPS = max(20, effectiveTickFPS())
        let fixedStep = Double(physicsStep)
        var elapsed = fixedStep

        if let lastTickTimestamp {
            elapsed = max(0.0, now - lastTickTimestamp)
        }
        lastTickTimestamp = now

        updateFPS(stepDelta: elapsed, targetFPS: targetFPS)
        guard samples.count > 2 else { return }
        guard !isTimeFrozen else { return }

        simulationAccumulator += min(elapsed, 0.1) * Double(max(0.2, timeScale))
        let maxSteps = 12
        var steps = Int(simulationAccumulator / fixedStep)
        if steps <= 0 { return }
        if steps > maxSteps {
            steps = maxSteps
            simulationAccumulator = fixedStep * Double(maxSteps)
        }

        for _ in 0..<steps {
            stepSimulation()
            simulationAccumulator -= fixedStep
        }
    }

    private func stepSimulation() {
        activity = max(0, activity * 0.996)

        let stiffness = max(0, stiffnessBase + activity * stiffnessActivity)
        let damping = min(max(0, dampingBase - activity * dampingActivity), 0.99999)
        let visc = max(0, viscosity)
        let waterMode = sceneLocation == .water

        let substeps = physicsSubsteps()
        let stepScale = 1.0 / CGFloat(substeps)
        if substeps <= 1 {
            updateBodiesPhysics(stepScale: 1.0)
        } else {
            for _ in 0..<substeps {
                updateBodiesPhysics(stepScale: stepScale)
            }
        }
        if waterMode {
            updateWaterChunks()
        } else {
            if !waterChunks.isEmpty {
                waterChunks.removeAll(keepingCapacity: true)
            }
            if !waterChunkDrawStates.isEmpty {
                waterChunkDrawStates = []
            }
        }
        updateGlassShards()
        var nextVelocities = velocities
        var nextSamples = samples

        if waterMode {
            applyPointerPull()
        }

        if waterMode {
            for i in 1..<(pointCount - 1) {
                let laplacian = samples[i - 1] - 2 * samples[i] + samples[i + 1]
                let viscousLaplacian = velocities[i - 1] - 2 * velocities[i] + velocities[i + 1]
                nextVelocities[i] += laplacian * stiffness + viscousLaplacian * visc
                nextVelocities[i] *= damping
                nextVelocities[i] = max(-maxVelocity, min(maxVelocity, nextVelocities[i]))
            }

            for i in 1..<(pointCount - 1) {
                nextSamples[i] = limitedDisplacement(samples[i] + nextVelocities[i])
            }
        } else {
            // Land mode keeps a flat line and quickly removes leftover water energy.
            for i in 1..<(pointCount - 1) {
                nextVelocities[i] = velocities[i] * 0.75
                nextSamples[i] = samples[i] * 0.68
                if abs(nextVelocities[i]) < 0.0005 { nextVelocities[i] = 0 }
                if abs(nextSamples[i]) < 0.0005 { nextSamples[i] = 0 }
            }
        }

        nextSamples[0] = 0
        nextSamples[pointCount - 1] = 0
        nextVelocities[0] = 0
        nextVelocities[pointCount - 1] = 0

        samples = nextSamples
        velocities = nextVelocities
        surfaceSpread = samples.reduce(0) { max($0, abs($1)) }
        syncBodyDrawStates()
        syncWaterChunkDrawStates()
        syncGlassShardDrawStates()
        syncWeldPreviewPoints()
    }

    private func updateFPS(stepDelta: CFAbsoluteTime, targetFPS: CGFloat) {
        guard stepDelta > 0.0001 else { return }
        let instantFPS = min(CGFloat(1.0 / stepDelta), targetFPS * 1.12)
        if smoothedFPS <= 0.1 {
            smoothedFPS = instantFPS
        } else {
            smoothedFPS = smoothedFPS * 0.88 + instantFPS * 0.12
        }
        fpsSampleTime += stepDelta
        fpsSampleSum += min(smoothedFPS, targetFPS * 1.05)
        fpsSampleCount += 1

        if fpsSampleTime >= 0.18 {
            fps = fpsSampleSum / CGFloat(max(1, fpsSampleCount))
            fpsSampleTime = 0
            fpsSampleSum = 0
            fpsSampleCount = 0
        }
    }

    private func updateWaterChunks() {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
        guard sceneLocation == .water else {
            if !waterChunks.isEmpty { waterChunks.removeAll(keepingCapacity: true) }
            if !waterChunkDrawStates.isEmpty { waterChunkDrawStates = [] }
            return
        }
        guard !waterChunks.isEmpty else { return }
        guard waterSprayEnabled else {
            waterChunks.removeAll(keepingCapacity: true)
            waterChunkDrawStates = []
            return
        }

        let maxChunkCount = max(0, Int(waterSprayMaxCount.rounded()))
        if maxChunkCount <= 0 {
            waterChunks.removeAll(keepingCapacity: true)
            waterChunkDrawStates = []
            return
        }

        if waterChunks.count > maxChunkCount {
            waterChunks.removeFirst(waterChunks.count - maxChunkCount)
        }

        var alive: [WaterChunk] = []
        alive.reserveCapacity(waterChunks.count)
        let sprayGravity = max(0, waterSprayGravityScale)
        let sprayDamping = min(max(waterSprayLinearDamping, 0.85), 0.9998)
        let absorbDepth = max(0.04, waterSprayAbsorbDepth)

        for var chunk in waterChunks {
            chunk.age += 1
            chunk.velocity.dy += gravityForce * sprayGravity
            chunk.velocity.dx *= sprayDamping
            chunk.velocity.dy *= sprayDamping
            chunk.center.x += chunk.velocity.dx
            chunk.center.y += chunk.velocity.dy

            if
                chunk.center.x < -120 || chunk.center.x > viewportSize.width + 120 ||
                chunk.center.y < -120 || chunk.center.y > viewportSize.height + 140 ||
                chunk.age > chunk.life
            {
                continue
            }

            let chunkX = min(max(0, chunk.center.x), viewportSize.width)
            let waterY = waveHeight(atX: chunkX)
            if chunk.center.y >= waterY + chunk.radius * absorbDepth, chunk.velocity.dy > 0 {
                let impact = min(20, abs(chunk.velocity.dy))
                let normalizedX = min(max(0, chunkX / viewportSize.width), 1)
                addDropImpulse(
                    centerNormalizedX: normalizedX,
                    radius: max(2, Int(2 + chunk.radius * 0.8)),
                    impulse: impact * 0.34
                )
                continue
            }

            collideWaterChunkWithBodies(&chunk)
            alive.append(chunk)
        }

        waterChunks = alive
    }

    private func updateGlassShards() {
        guard !glassShards.isEmpty else {
            if !glassShardDrawStates.isEmpty {
                glassShardDrawStates = []
            }
            return
        }

        var alive: [GlassShard] = []
        alive.reserveCapacity(glassShards.count)

        let gravity = gravityForce * max(0.2, fallAccelerationScale) * 0.02
        let damping: CGFloat = 0.9

        for var shard in glassShards {
            shard.age += 1
            shard.velocity.dy += gravity
            shard.velocity.dx *= damping
            shard.velocity.dy *= damping
            shard.center.x += shard.velocity.dx
            shard.center.y += shard.velocity.dy
            shard.angle = normalizedAngle(shard.angle + shard.angularVelocity)
            shard.angularVelocity *= 0.94

            if shard.center.x < -120 || shard.center.x > viewportSize.width + 120 ||
                shard.center.y < -120 || shard.center.y > viewportSize.height + 140 ||
                shard.age > shard.life
            {
                continue
            }

            alive.append(shard)
        }

        glassShards = alive
    }

    private func collideWaterChunkWithBodies(_ chunk: inout WaterChunk) {
        for body in bodies {
            let bodyRadius = boundingRadius(for: body)
            let broad = bodyRadius + chunk.radius + 2
            let dx = chunk.center.x - body.center.x
            let dy = chunk.center.y - body.center.y
            if dx * dx + dy * dy > broad * broad { continue }
            if !bodyContains(chunk.center, body: body) { continue }

            var normal = CGVector(dx: dx, dy: dy)
            let length = sqrt(normal.dx * normal.dx + normal.dy * normal.dy)
            if length > 0.0001 {
                normal.dx /= length
                normal.dy /= length
            } else {
                normal = CGVector(dx: 0, dy: -1)
            }

            chunk.center.x += normal.dx * (chunk.radius * 1.2)
            chunk.center.y += normal.dy * (chunk.radius * 1.2)

            let velocityAlongNormal = dot(chunk.velocity, normal)
            if velocityAlongNormal < 0 {
                let restitution: CGFloat = 0.28
                chunk.velocity.dx -= (1 + restitution) * velocityAlongNormal * normal.dx
                chunk.velocity.dy -= (1 + restitution) * velocityAlongNormal * normal.dy
            }

            // One-way interaction: chunk reacts to object, object mass/velocity remain untouched.
            let touchForceY = -chunk.velocity.dy * 0.01
            applyWaveReactionImpulse(
                atX: min(max(0, chunk.center.x), viewportSize.width),
                fromWaterForceY: touchForceY,
                spawnSpray: false
            )
            break
        }
    }

    private func spawnWaterChunks(atX x: CGFloat, count: Int, energy: CGFloat, sourceVelocity: CGVector = .zero) {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
        guard sceneLocation == .water else { return }
        guard count > 0 else { return }
        guard waterSprayEnabled else { return }

        let clampedX = min(max(0, x), viewportSize.width)
        let sourceY = waveHeight(atX: clampedX)
        let clampedCount = min(max(count, 1), 8)
        let impulseEnergy = min(max(energy, 0.02), 1.4)
        let maxChunkCount = max(0, Int(waterSprayMaxCount.rounded()))
        if maxChunkCount <= 0 { return }
        let minRadius = max(0.8, waterSprayRadiusMin)
        let maxRadius = max(minRadius + 0.05, waterSprayRadiusMax)
        let minLife = max(8, waterSprayLifeMin)
        let maxLife = max(minLife + 1, waterSprayLifeMax)

        for _ in 0..<clampedCount {
            if waterChunks.count >= maxChunkCount { break }

            let spreadX = CGFloat.random(in: -14...14)
            let startY = sourceY - CGFloat.random(in: 0...6)
            let lateral = sourceVelocity.dx * 0.14
            let vx = lateral + CGFloat.random(in: -0.95...0.95) * (0.7 + impulseEnergy * 4.4)
            let vy = -abs(sourceVelocity.dy) * 0.18 - CGFloat.random(in: 0.9...2.1) * (0.6 + impulseEnergy * 4.8)
            let radius = min(maxRadius, CGFloat.random(in: minRadius...maxRadius) + impulseEnergy * 0.8)
            let life = min(maxLife, CGFloat.random(in: minLife...maxLife) + impulseEnergy * 38)

            waterChunks.append(
                WaterChunk(
                    id: UUID(),
                    center: CGPoint(x: clampedX + spreadX, y: startY),
                    velocity: CGVector(dx: vx, dy: vy),
                    radius: radius,
                    age: 0,
                    life: life
                )
            )
        }
    }

    private func queueGlassShatter(id: UUID, point: CGPoint, normal: CGVector, impulse: CGFloat, sourceVelocity: CGVector) {
        if let existing = pendingGlassShatters[id], existing.impulse >= impulse { return }
        pendingGlassShatters[id] = GlassShatterRequest(
            id: id,
            point: point,
            normal: normal,
            impulse: impulse,
            sourceVelocity: sourceVelocity
        )
    }

    private func applyGlassShatters() {
        guard !pendingGlassShatters.isEmpty else { return }
        var toRemove: Set<UUID> = []

        for request in pendingGlassShatters.values {
            guard let index = bodyIndex(forID: request.id), bodies.indices.contains(index) else { continue }
            let body = bodies[index]
            spawnGlassShards(from: body, request: request)
            toRemove.insert(body.id)
        }

        pendingGlassShatters.removeAll(keepingCapacity: true)
        guard !toRemove.isEmpty else { return }

        let draggingID = draggingBodyIndex.flatMap { index in
            bodies.indices.contains(index) ? bodies[index].id : nil
        }

        bodies.removeAll { toRemove.contains($0.id) }
        weldConstraints.removeAll { toRemove.contains($0.firstID) || toRemove.contains($0.secondID) }
        wheelBodies = wheelBodies.filter { !toRemove.contains($0) }
        spawnedBodyHistory.removeAll { toRemove.contains($0) }
        selectedBodyIDs.subtract(toRemove)
        if let primary = primarySelectionID, toRemove.contains(primary) {
            primarySelectionID = nil
        }
        if let draggingID, toRemove.contains(draggingID) {
            draggingBodyIndex = nil
        }
        selectionMoveActive = false
        selectionMoveStart = nil
        selectionMoveCenters.removeAll(keepingCapacity: true)
        throwCooldown = throwCooldown.filter { !toRemove.contains($0.key) }
        glassDamage = glassDamage.filter { !toRemove.contains($0.key) }
        glassImpactInput = glassImpactInput.filter { !toRemove.contains($0.key) }
        glassBreakContact = glassBreakContact.filter { !toRemove.contains($0.key) }
        glassGraceFrames = glassGraceFrames.filter { !toRemove.contains($0.key) }

        cleanupWeldState()
        syncBodyDrawStates()
    }

    private func spawnGlassShards(from body: Body, request: GlassShatterRequest) {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
        let impulse = max(0.1, request.impulse)
        let energy = min(2.4, impulse * 0.16 + sqrt(impulse) * 0.1)
        let sizeScale = max(0.8, min(4.4, bodyCharacteristicSize(for: body) / max(1, squareSize)))
        let massScale = sqrt(max(0.2, bodyMass(for: body) / max(squareMass, 0.0001)))
        let shardScale = min(4.5, max(0.8, sizeScale * 0.6 + massScale * 0.4))
        let count = min(56, max(8, Int((energy * 5.2 + 4) * (0.75 + shardScale * 0.34))))
        let baseSpeed = (1.0 + min(0.32, energy * 0.15)) * (0.85 + sqrt(shardScale) * 0.2)

        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<(CGFloat.pi * 2))
            var dir = CGVector(dx: cos(angle), dy: sin(angle))
            dir.dx += CGFloat.random(in: -0.1...0.1)
            dir.dy += CGFloat.random(in: -0.1...0.1)
            let length = max(0.001, sqrt(dir.dx * dir.dx + dir.dy * dir.dy))
            dir.dx /= length
            dir.dy /= length

            let speed = baseSpeed * CGFloat.random(in: 0.86...1.2)
            let radius = CGFloat.random(in: 1.8...4.4) * (0.8 + shardScale * 0.42)
            let life = CGFloat.random(in: 10...20) + shardScale * 2.5
            let spin = CGFloat.random(in: -0.32...0.32)
            let stretch = CGFloat.random(in: 0.35...1.1)
            let kind = Int.random(in: 0...2)
            let velocity = CGVector(
                dx: dir.dx * speed,
                dy: dir.dy * speed
            )
            let spawnPoint = randomPointInsideBody(body) ?? request.point

            glassShards.append(
                GlassShard(
                    id: UUID(),
                    center: CGPoint(
                        x: spawnPoint.x + CGFloat.random(in: -radius * 0.18...radius * 0.18),
                        y: spawnPoint.y + CGFloat.random(in: -radius * 0.18...radius * 0.18)
                    ),
                    velocity: velocity,
                    radius: radius,
                    age: 0,
                    life: life,
                    angle: body.angle + CGFloat.random(in: -0.6...0.6),
                    angularVelocity: spin,
                    stretch: stretch,
                    kind: kind
                )
            )
        }
    }

    private func syncWaterChunkDrawStates() {
        guard !waterChunks.isEmpty else {
            if !waterChunkDrawStates.isEmpty {
                waterChunkDrawStates = []
            }
            return
        }

        waterChunkDrawStates = waterChunks.map { chunk in
            let lifeRatio = max(0, min(1, 1 - chunk.age / max(chunk.life, 1)))
            let speed = sqrt(chunk.velocity.dx * chunk.velocity.dx + chunk.velocity.dy * chunk.velocity.dy)
            return WaterChunkDrawState(
                id: chunk.id,
                center: chunk.center,
                radius: chunk.radius,
                opacity: min(1, max(0.05, waterSprayOpacityBase + lifeRatio * waterSprayOpacityScale)),
                velocity: chunk.velocity,
                tailLength: min(chunk.radius * 3.4, speed * waterSprayTailScale)
            )
        }
    }

    private func syncGlassShardDrawStates() {
        guard !glassShards.isEmpty else {
            if !glassShardDrawStates.isEmpty {
                glassShardDrawStates = []
            }
            return
        }

        glassShardDrawStates = glassShards.map { shard in
            let lifeRatio = max(0, min(1, 1 - shard.age / max(shard.life, 1)))
            let eased = lifeRatio * lifeRatio
            return GlassShardDrawState(
                id: shard.id,
                center: shard.center,
                radius: shard.radius,
                opacity: min(1, max(0.02, eased)),
                angle: shard.angle,
                stretch: shard.stretch,
                kind: shard.kind,
                velocity: shard.velocity
            )
        }
    }

    private func applyPointerPull() {
        guard sceneLocation == .water else { return }
        guard draggingBodyIndex == nil else { return }
        guard !weldToolEnabled else { return }
        guard !wheelToolEnabled else { return }
        guard let pointerX, pointerStrength > 0.0001 else { return }

        let suppression = pointerSuppressionFactor()
        if suppression < 0.08 { return }

        let center = Int(pointerX * CGFloat(pointCount - 1))
        let radius = Int(pointerRadiusBase + pointerStrength * pointerRadiusScale)
        let targetDepth = (
            pointerDepthBase +
            pointerStrength * pointerDepthScale +
            activity * pointerDepthActivityScale
        ) * suppression
        let leftBound = max(1, center - radius)
        let rightBound = min(pointCount - 2, center + radius)

        if leftBound > rightBound { return }

        for i in leftBound...rightBound {
            let distance = abs(CGFloat(i - center) / CGFloat(max(radius, 1)))
            let profile = cos(min(distance, 1) * .pi / 2)
            let target = -targetDepth * profile
            let correction = target - samples[i]
            velocities[i] += correction * (pointerForceBase + pointerStrength * pointerForceScale) * suppression
        }
    }

    private func addDropImpulse(
        centerNormalizedX: CGFloat? = nil,
        radius: Int? = nil,
        impulse: CGFloat? = nil
    ) {
        guard sceneLocation == .water else { return }
        let normalizedX = centerNormalizedX ?? CGFloat.random(in: 0.2...0.8)
        let center = Int(CGFloat(pointCount - 1) * normalizedX)
        let minRadius = max(1, keyboardRadiusMin)
        let maxRadius = max(minRadius + 1, keyboardRadiusMax)
        let radius = radius ?? Int(CGFloat.random(in: minRadius...maxRadius))
        let impulse = impulse ?? (keyboardImpulseBase + activity * keyboardImpulseScale)
        let leftBound = max(1, center - radius)
        let rightBound = min(pointCount - 2, center + radius)

        if leftBound > rightBound { return }

        for i in leftBound...rightBound {
            let distance = abs(CGFloat(i - center) / CGFloat(max(radius, 1)))
            let profile = cos(min(distance, 1) * .pi / 2)
            let shapedImpulse = impulse * profile
            velocities[i] += shapedImpulse
            velocities[i] = max(-maxVelocity, min(maxVelocity, velocities[i]))
            samples[i] = limitedDisplacement(samples[i] + shapedImpulse * 0.15)
        }

        if
            waterSprayEnabled,
            viewportSize.width > 1,
            impulse < -waterSprayImpulseThreshold
        {
            let excess = abs(impulse) - waterSprayImpulseThreshold
            let spawnCount = min(5, max(1, Int(excess / 5)))
            let spawnEnergy = max(0.03, excess * waterSprayImpulseEnergy)
            spawnWaterChunks(
                atX: normalizedX * viewportSize.width,
                count: spawnCount,
                energy: spawnEnergy,
                sourceVelocity: CGVector(dx: 0, dy: -abs(impulse) * 0.16)
            )
        }

    }

    private func updateBodiesPhysics(stepScale: CGFloat) {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
        guard !bodies.isEmpty else { return }
        glassImpactInput.removeAll(keepingCapacity: true)

        let fallScale = max(0, fallAccelerationScale)
        let wheelHostIDs: Set<UUID>
        let wheelGroundedHosts: Set<UUID>
        if wheelBodies.isEmpty {
            wheelHostIDs = []
            wheelGroundedHosts = []
        } else {
            var hosts: Set<UUID> = []
            var groundedHosts: Set<UUID> = []
            for weld in weldConstraints {
                if wheelBodies.contains(weld.firstID), !wheelBodies.contains(weld.secondID) {
                    hosts.insert(weld.secondID)
                    if let wheelIndex = bodyIndex(forID: weld.firstID), bodies.indices.contains(wheelIndex) {
                        let wheel = bodies[wheelIndex]
                        if sceneLocation != .water, groundContactInfo(for: wheel) != nil {
                            groundedHosts.insert(weld.secondID)
                        }
                    }
                } else if wheelBodies.contains(weld.secondID), !wheelBodies.contains(weld.firstID) {
                    hosts.insert(weld.firstID)
                    if let wheelIndex = bodyIndex(forID: weld.secondID), bodies.indices.contains(wheelIndex) {
                        let wheel = bodies[wheelIndex]
                        if sceneLocation != .water, groundContactInfo(for: wheel) != nil {
                            groundedHosts.insert(weld.firstID)
                        }
                    }
                }
            }
            wheelHostIDs = hosts
            wheelGroundedHosts = groundedHosts
        }

        if !bodySplashCooldown.isEmpty {
            for id in Array(bodySplashCooldown.keys) {
                let next = (bodySplashCooldown[id] ?? 0) - 1
                if next <= 0 {
                    bodySplashCooldown.removeValue(forKey: id)
                } else {
                    bodySplashCooldown[id] = next
                }
            }
        }
        if !throwCooldown.isEmpty {
            for id in Array(throwCooldown.keys) {
                let next = (throwCooldown[id] ?? 0) - 1
                if next <= 0 {
                    throwCooldown.removeValue(forKey: id)
                } else {
                    throwCooldown[id] = next
                }
            }
        }

        for index in bodies.indices {
            if draggingBodyIndex == index {
                bodies[index].center = clampedBodyCenter(bodies[index].center, for: bodies[index])
                bodies[index].angle = normalizedAngle(bodies[index].angle)
                continue
            }

            var body = bodies[index]
            let bodyMass = bodyMass(for: body)
            let bodyInertiaValue = bodyInertia(for: body)
            let waterMode = sceneLocation == .water
            let gravityAccel = gravityForce * fallScale
            var totalForce = CGVector(dx: 0, dy: gravityAccel * bodyMass)
            var totalTorque: CGFloat = 0
            if waterMode {
                var submergedSamples = 0
                let samplePoints = bodySamplePoints(for: body)
                let fluidScale = min(8.0, max(0.8, bodyMass / max(squareMass, 0.0001)))
                let sampleWeight: CGFloat = fluidScale / CGFloat(max(1, samplePoints.count))
                let characteristicSize = bodyCharacteristicSize(for: body)
                let bottomExtent = bodyBottomExtent(for: body)

                for localPoint in samplePoints {
                    let worldPoint = rotate(point: localPoint, by: body.angle, around: body.center)

                    let clampedX = min(max(0, worldPoint.x), viewportSize.width)
                    let waterY = waveHeight(atX: clampedX)
                    let depth = worldPoint.y - waterY
                    if depth <= waterContactThreshold { continue }

                    submergedSamples += 1
                    let submersion = min(1.4, depth / (characteristicSize * 0.75))

                    let rX = worldPoint.x - body.center.x
                    let rY = worldPoint.y - body.center.y

                    let pointVelocityX = body.velocity.dx - body.angularVelocity * rY
                    let pointVelocityY = body.velocity.dy + body.angularVelocity * rX

                    let waterVelocityX = waveSlope(atX: clampedX) * waterSlopeFactor
                    let waterVelocityY = waveVelocity(atX: clampedX)
                    let relativeX = pointVelocityX - waterVelocityX
                    let relativeY = pointVelocityY - waterVelocityY

                    let buoyancyY = -depth * (buoyancyBase + submersion * buoyancyScale) * sampleWeight
                    let dragX = -relativeX * (dragXBase + submersion * dragXScale) * sampleWeight
                    let dragY = -relativeY * (dragYBase + submersion * dragYScale) * sampleWeight

                    let forceX = dragX
                    let forceY = buoyancyY + dragY
                    totalForce.dx += forceX
                    totalForce.dy += forceY
                    totalTorque += rX * forceY - rY * forceX

                    applyWaveReactionImpulse(atX: clampedX, fromWaterForceY: forceY)
                }

                let centerWaterY = waveHeight(atX: body.center.x)
                let centerWaterVy = waveVelocity(atX: body.center.x)
                let immersion = (body.center.y + bottomExtent) - centerWaterY
                let immersionRatio = CGFloat(submergedSamples) / CGFloat(max(1, samplePoints.count))

                if
                    waterSprayEnabled,
                    draggingBodyIndex != index,
                    immersionRatio > 0.05,
                    immersionRatio < 0.78,
                    body.velocity.dy > waterSprayImpactThreshold,
                    (bodySplashCooldown[body.id] ?? 0) <= 0
                {
                    let impact = (body.velocity.dy - waterSprayImpactThreshold) * waterSprayImpactEnergy
                    if impact > 0.02 {
                        let spawnX = min(max(0, body.center.x + body.velocity.dx * 3.5), viewportSize.width)
                        let spawnCount = min(6, max(1, Int(impact * 12)))
                        spawnWaterChunks(
                            atX: spawnX,
                            count: spawnCount,
                            energy: impact,
                            sourceVelocity: body.velocity
                        )
                        bodySplashCooldown[body.id] = 8 + min(20, impact * 18)
                    }
                }

                if immersion > -18, immersion < characteristicSize {
                    let targetImmersion = characteristicSize * surfaceTargetImmersion
                    let springForce = (targetImmersion - immersion) * surfaceSpring
                    let dampingForce = -(body.velocity.dy - centerWaterVy) * surfaceDamping
                    totalForce.dy += springForce + dampingForce
                }

                if submergedSamples > 0 {
                    totalTorque += -sin(body.angle) * (0.016 + immersionRatio * 0.013)
                    let dampX = max(0.8, 0.992 - immersionRatio * 0.01)
                    let dampY = max(0.8, 0.992 - immersionRatio * 0.012)
                    let dampA = max(0.8, 0.991 - immersionRatio * 0.011)
                    body.velocity.dx *= pow(dampX, stepScale)
                    body.velocity.dy *= pow(dampY, stepScale)
                    body.angularVelocity *= pow(dampA, stepScale)
                } else {
                    body.velocity.dx *= pow(0.998, stepScale)
                    body.velocity.dy *= pow(0.9988, stepScale)
                    body.angularVelocity *= pow(0.996, stepScale)
                }
            } else {
                body.velocity.dx *= pow(0.9988, stepScale)
                body.velocity.dy *= pow(0.9991, stepScale)
                body.angularVelocity *= pow(0.997, stepScale)
            }

            body.velocity.dx += (totalForce.dx / bodyMass) * stepScale
            body.velocity.dy += (totalForce.dy / bodyMass) * stepScale
            body.angularVelocity += (totalTorque / bodyInertiaValue) * stepScale

            let throwBoost = (throwCooldown[body.id] ?? 0) > 0 ? max(1, dragThrowClampScale) : 1
            let maxVX = squareVelocityLimitX * throwBoost
            let maxVY = squareVelocityLimitY * max(1, fallScale) * throwBoost
            body.velocity.dx = max(-maxVX, min(maxVX, body.velocity.dx))
            body.velocity.dy = max(-maxVY, min(maxVY, body.velocity.dy))
            body.angularVelocity = max(-squareAngularLimit, min(squareAngularLimit, body.angularVelocity))

            body.center.x += body.velocity.dx * stepScale
            body.center.y += body.velocity.dy * stepScale
            body.angle = normalizedAngle(body.angle + body.angularVelocity * stepScale)
            applyWorldBounds(to: &body)

            bodies[index] = body
        }

        cleanupWeldState()
        let weldTopology = weldedTopology()

        if cubeCollisionEnabled, bodies.count > 1 {
            resolveBodyCollisions(groupLookup: weldTopology.lookup, stepScale: stepScale)
        }
        updateGlassFracture(stepScale: stepScale)
        applyGlassShatters()

        resolveWeldConstraints(components: weldTopology.components)

        if cubeCollisionEnabled, bodies.count > 1 {
            if !weldTopology.components.isEmpty {
                // Weld projection can reintroduce overlaps; run collision solve once more after welds.
                resolveBodyCollisions(groupLookup: weldTopology.lookup, stepScale: stepScale)
            }
            resolvePenetrationOnly(groupLookup: weldTopology.lookup, stepScale: stepScale)
        }

        for index in bodies.indices {
            bodies[index].angle = normalizedAngle(bodies[index].angle)
            let throwBoost = (throwCooldown[bodies[index].id] ?? 0) > 0 ? max(1, dragThrowClampScale) : 1
            let maxVX = squareVelocityLimitX * throwBoost
            let maxVY = squareVelocityLimitY * max(1, fallScale) * throwBoost
            bodies[index].velocity.dx = max(-maxVX, min(maxVX, bodies[index].velocity.dx))
            bodies[index].velocity.dy = max(-maxVY, min(maxVY, bodies[index].velocity.dy))
            bodies[index].angularVelocity = max(-squareAngularLimit, min(squareAngularLimit, bodies[index].angularVelocity))
            applyWorldBounds(to: &bodies[index])
            if sceneLocation != .water {
                if !wheelHostIDs.contains(bodies[index].id) || !wheelGroundedHosts.contains(bodies[index].id) {
                    applyLandSurfaceConstraint(to: &bodies[index])
                }
                if shouldSettleBodyAtRest(index: index) {
                    bodies[index].velocity = .zero
                    bodies[index].angularVelocity = 0
                }
            }
        }

        if cubeCollisionEnabled, bodies.count > 1 {
            resolveBodyCollisions(groupLookup: weldTopology.lookup, stepScale: stepScale)
            resolvePenetrationOnly(groupLookup: weldTopology.lookup, stepScale: stepScale)
        }

        if sceneLocation != .water {
            for index in bodies.indices {
                if let contact = groundContactInfo(for: bodies[index]), contact.penetration > 0 {
                    bodies[index].center.y -= contact.penetration
                    if bodies[index].velocity.dy > 0 {
                        bodies[index].velocity.dy = 0
                    }
                }
            }
        }

    }

    private func resolveBodyCollisions(groupLookup: [UUID: Int], stepScale: CGFloat) {
        let baseIterations = max(1, Int(collisionIterations.rounded()))
        let targetMinimum = bodies.count > 10 ? 18 : 14
        let iterations = max(baseIterations, wheelBodies.isEmpty ? targetMinimum : min(targetMinimum + 4, 24))
        guard bodies.count > 1 else { return }
        let candidatePairs = candidateCollisionPairs()
        if candidatePairs.isEmpty { return }
        for _ in 0..<iterations {
            var hadCollision = false

            for pair in candidatePairs {
                let first = pair.first
                let second = pair.second
                guard bodies.indices.contains(first), bodies.indices.contains(second) else { continue }

                let firstID = bodies[first].id
                let secondID = bodies[second].id
                if shouldSkipCollision(firstID: firstID, secondID: secondID, groupLookup: groupLookup) {
                    continue
                }

                let dx = bodies[second].center.x - bodies[first].center.x
                let dy = bodies[second].center.y - bodies[first].center.y
                let maxDistance = boundingRadius(for: bodies[first]) + boundingRadius(for: bodies[second]) + max(collisionSlop, 0) + 2
                if dx * dx + dy * dy > maxDistance * maxDistance {
                    continue
                }

                hadCollision = resolveCollisionPair(first, second, stepScale: stepScale) || hadCollision
            }

            if !hadCollision { break }
        }
    }

    private func registerGlassCollisionEvent(
        glass: Body,
        other: Body,
        point: CGPoint,
        normal: CGVector,
        impactImpulse: CGFloat,
        impactSpeed: CGFloat,
        relativeVelocity: CGVector
    ) {
        let glassMass = max(0.001, bodyMass(for: glass))
        let otherMass = max(0.001, bodyMass(for: other))
        let massRatio = min(3.2, max(0.25, otherMass / glassMass))
        let strength = glassStrengthScale(for: glass)
        let speedGate = 4.5 + max(0, strength - 1) * 0.8
        let impulseGate = 3.9 * strength

        let impact = max(0, impactSpeed - speedGate) * (0.24 + massRatio * 0.12) +
            max(0, impactImpulse - impulseGate) * (0.075 + massRatio * 0.05)
        if impact > 0.0001 {
            glassImpactInput[glass.id, default: 0] += min(1.3, impact / strength)
        }

        if impact > 0.0001 {
            glassBreakContact[glass.id] = GlassBreakContact(
                point: point,
                normal: normal,
                sourceVelocity: relativeVelocity
            )
        }
    }

    private func updateGlassFracture(stepScale: CGFloat) {
        guard !bodies.isEmpty else {
            glassDamage.removeAll(keepingCapacity: true)
            glassImpactInput.removeAll(keepingCapacity: true)
            glassBreakContact.removeAll(keepingCapacity: true)
            glassGraceFrames.removeAll(keepingCapacity: true)
            return
        }

        let activeGlass = Set(bodies.filter(\.isGlass).map(\.id))
        if activeGlass.isEmpty {
            glassDamage.removeAll(keepingCapacity: true)
            glassImpactInput.removeAll(keepingCapacity: true)
            glassBreakContact.removeAll(keepingCapacity: true)
            glassGraceFrames.removeAll(keepingCapacity: true)
            return
        }

        for id in Array(glassDamage.keys) where !activeGlass.contains(id) {
            glassDamage.removeValue(forKey: id)
        }
        for id in Array(glassBreakContact.keys) where !activeGlass.contains(id) {
            glassBreakContact.removeValue(forKey: id)
        }
        for id in Array(glassGraceFrames.keys) where !activeGlass.contains(id) {
            glassGraceFrames.removeValue(forKey: id)
        }

        let scale = max(0.2, stepScale)
        for glass in bodies where glass.isGlass {
            let id = glass.id
            if let frames = glassGraceFrames[id], frames > 0 {
                glassGraceFrames[id] = frames - 1
                glassDamage[id] = max(0, (glassDamage[id] ?? 0) - 0.08 * scale)
                continue
            }

            let impactInput = glassImpactInput[id] ?? 0
            let loadMass = transmittedGlassLoadMass(on: glass)
            let mass = max(0.001, bodyMass(for: glass))
            let strength = glassStrengthScale(for: glass)
            let loadCapacity = mass * (2.2 + 0.45 * max(0, strength - 1))
            let overloadRatio = max(0, loadMass / max(loadCapacity, 0.001) - 1)

            var damage = glassDamage[id] ?? 0
            damage += impactInput * 0.78
            if overloadRatio > 0 {
                damage += ((0.010 + overloadRatio * 0.10) * scale) / strength
            }

            if impactInput <= 0.0001, overloadRatio <= 0 {
                damage = max(0, damage - 0.12 * scale)
            } else if overloadRatio == 0 {
                damage = max(0, damage - 0.02 * scale)
            }

            let impactBreak = impactInput >= (2.08 + max(0, strength - 1) * 0.36)
            let overloadBreak = overloadRatio > (0.10 + max(0, strength - 1) * 0.02) && damage >= (0.74 + max(0, strength - 1) * 0.10)
            let fatigueBreak = damage >= (1.34 + max(0, strength - 1) * 0.26)
            if impactBreak || overloadBreak || fatigueBreak {
                let contact = glassBreakContact[id] ?? GlassBreakContact(
                    point: glass.center,
                    normal: CGVector(dx: 0, dy: -1),
                    sourceVelocity: .zero
                )
                let shatterImpulse = max(
                    4.0,
                    4.8 + impactInput * 4.6 + overloadRatio * 6.0 + damage * 2.8
                )
                queueGlassShatter(
                    id: id,
                    point: contact.point,
                    normal: contact.normal,
                    impulse: shatterImpulse,
                    sourceVelocity: contact.sourceVelocity
                )
                glassDamage.removeValue(forKey: id)
                glassBreakContact.removeValue(forKey: id)
                glassGraceFrames.removeValue(forKey: id)
                continue
            }

            if damage < 0.01 {
                glassDamage.removeValue(forKey: id)
            } else {
                glassDamage[id] = damage
            }
        }
    }

    private func transmittedGlassLoadMass(on base: Body) -> CGFloat {
        var visited: Set<UUID> = [base.id]
        return glassSupportedMass(above: base, depth: 0, maxDepth: 6, visited: &visited)
    }

    private func glassSupportedMass(
        above support: Body,
        depth: Int,
        maxDepth: Int,
        visited: inout Set<UUID>
    ) -> CGFloat {
        guard depth < maxDepth else { return 0 }
        let supportBounds = bodyBounds(support)
        let contactTolerance = max(1.0, min(2.8, bodyCharacteristicSize(for: support) * 0.05))
        var total: CGFloat = 0

        for other in bodies where other.id != support.id {
            if visited.contains(other.id) { continue }
            if other.center.y >= support.center.y - 0.5 { continue }

            let otherBounds = bodyBounds(other)
            let overlap = min(supportBounds.maxX, otherBounds.maxX) - max(supportBounds.minX, otherBounds.minX)
            if overlap <= 0 { continue }

            let overlapReference = max(1, min(supportBounds.width, otherBounds.width))
            let overlapRatio = overlap / overlapReference
            if overlapRatio < 0.2 { continue }

            let verticalGap = supportBounds.minY - otherBounds.maxY
            if verticalGap < -0.8 || verticalGap > contactTolerance { continue }

            visited.insert(other.id)
            let supportFactor = min(1, max(0, (overlapRatio - 0.2) / 0.8))
            if supportFactor <= 0 { continue }
            total += bodyMass(for: other) * supportFactor
            total += glassSupportedMass(above: other, depth: depth + 1, maxDepth: maxDepth, visited: &visited)
        }

        return total
    }

    private func resolvePenetrationOnly(groupLookup: [UUID: Int], stepScale: CGFloat) {
        let baseIterations = max(1, Int(collisionIterations.rounded()))
        let weldedBoost = groupLookup.isEmpty ? 0 : 2
        let targetMinimum = bodies.count > 10 ? 14 : 10
        let iterations = max(baseIterations + weldedBoost, targetMinimum)
        guard bodies.count > 1 else { return }
        let slop = max(0, collisionSlop * 0.6)
        let candidatePairs = candidateCollisionPairs()
        if candidatePairs.isEmpty { return }
        for _ in 0..<iterations {
            var separated = false
            for pair in candidatePairs {
                let first = pair.first
                let second = pair.second
                guard bodies.indices.contains(first), bodies.indices.contains(second) else { continue }

                let firstID = bodies[first].id
                let secondID = bodies[second].id
                if shouldSkipCollision(firstID: firstID, secondID: secondID, groupLookup: groupLookup) {
                    continue
                }

                var bodyA = bodies[first]
                var bodyB = bodies[second]
                guard let manifold = bodyCollisionManifold(bodyA, bodyB), !manifold.contacts.isEmpty else { continue }
                let maxPenetration = manifold.contacts.map(\.penetration).max() ?? 0
                if maxPenetration <= slop { continue }

                let invMassA: CGFloat = 1 / max(bodyMass(for: bodyA), 0.0001)
                let invMassB: CGFloat = 1 / max(bodyMass(for: bodyB), 0.0001)
                let invInertiaA: CGFloat = 1 / max(bodyInertia(for: bodyA), 0.0001)
                let invInertiaB: CGFloat = 1 / max(bodyInertia(for: bodyB), 0.0001)

                let correctionStrength = min(max(collisionPositionCorrection, 0), 0.95)
                let angularPositionTransfer: CGFloat = 0.0
                for contact in manifold.contacts {
                    if contact.penetration <= slop { continue }
                    let rA = CGVector(dx: contact.position.x - bodyA.center.x, dy: contact.position.y - bodyA.center.y)
                    let rB = CGVector(dx: contact.position.x - bodyB.center.x, dy: contact.position.y - bodyB.center.y)
                    let rACrossN = cross(rA, manifold.normal)
                    let rBCrossN = cross(rB, manifold.normal)
                    let denominator = invMassA + invMassB +
                        (rACrossN * rACrossN) * invInertiaA +
                        (rBCrossN * rBCrossN) * invInertiaB
                    if denominator <= 0.000001 { continue }
                    let correctionMagnitude = (contact.penetration - slop) * correctionStrength / denominator
                    let correction = CGVector(
                        dx: manifold.normal.dx * correctionMagnitude,
                        dy: manifold.normal.dy * correctionMagnitude
                    )
                    bodyA.center.x -= correction.dx * invMassA
                    bodyA.center.y -= correction.dy * invMassA
                    bodyA.angle = normalizedAngle(bodyA.angle - cross(rA, correction) * invInertiaA * angularPositionTransfer)
                    bodyB.center.x += correction.dx * invMassB
                    bodyB.center.y += correction.dy * invMassB
                    bodyB.angle = normalizedAngle(bodyB.angle + cross(rB, correction) * invInertiaB * angularPositionTransfer)
                }
                bodies[first] = bodyA
                bodies[second] = bodyB
                separated = true
            }
            if !separated { break }
        }
    }

    private func candidateCollisionPairs() -> [CollisionPair] {
        guard bodies.count > 1 else { return [] }
        var allPairs: [CollisionPair] = []
        allPairs.reserveCapacity(bodies.count * (bodies.count - 1) / 2)
        for first in 0..<(bodies.count - 1) {
            for second in (first + 1)..<bodies.count {
                allPairs.append(CollisionPair(first: first, second: second))
            }
        }
        return allPairs
    }

    private func shouldSkipCollision(firstID: UUID, secondID: UUID, groupLookup: [UUID: Int]) -> Bool {
        guard
            let groupA = groupLookup[firstID],
            let groupB = groupLookup[secondID],
            groupA == groupB
        else {
            return false
        }

        // Inside one welded component all bodies should behave as one rigid aggregate.
        return true
    }

    private func resolveCollisionPair(_ firstIndex: Int, _ secondIndex: Int, stepScale: CGFloat) -> Bool {
        var first = bodies[firstIndex]
        var second = bodies[secondIndex]

        guard let manifold = bodyCollisionManifold(first, second), !manifold.contacts.isEmpty else { return false }

        let maxPenetration = manifold.contacts.map(\.penetration).max() ?? 0
        if maxPenetration <= 0.0001 {
            return false
        }

        let firstIsDragging = draggingBodyIndex == firstIndex
        let secondIsDragging = draggingBodyIndex == secondIndex
        let invMassFirst: CGFloat = firstIsDragging ? 0 : 1 / max(bodyMass(for: first), 0.0001)
        let invMassSecond: CGFloat = secondIsDragging ? 0 : 1 / max(bodyMass(for: second), 0.0001)
        let invInertiaFirst: CGFloat = firstIsDragging ? 0 : 1 / max(bodyInertia(for: first), 0.0001)
        let invInertiaSecond: CGFloat = secondIsDragging ? 0 : 1 / max(bodyInertia(for: second), 0.0001)
        let invMassSum = invMassFirst + invMassSecond
        if invMassSum <= 0 {
            return false
        }

        let slop = max(0, collisionSlop)
        let correctionStrength = min(max(collisionPositionCorrection, 0), 0.8)
        let angularPositionTransfer: CGFloat = 0.0
        for contact in manifold.contacts.prefix(2) {
            if contact.penetration <= slop { continue }
            let rFirst = CGVector(dx: contact.position.x - first.center.x, dy: contact.position.y - first.center.y)
            let rSecond = CGVector(dx: contact.position.x - second.center.x, dy: contact.position.y - second.center.y)
            let rFirstCrossNormal = cross(rFirst, manifold.normal)
            let rSecondCrossNormal = cross(rSecond, manifold.normal)
            let denominator = invMassFirst + invMassSecond +
                (rFirstCrossNormal * rFirstCrossNormal) * invInertiaFirst +
                (rSecondCrossNormal * rSecondCrossNormal) * invInertiaSecond
            if denominator <= 0.000001 { continue }
            let correctionMagnitude = (contact.penetration - slop) * correctionStrength / denominator
            let correction = CGVector(
                dx: manifold.normal.dx * correctionMagnitude,
                dy: manifold.normal.dy * correctionMagnitude
            )
            if invMassFirst > 0 {
                first.center.x -= correction.dx * invMassFirst
                first.center.y -= correction.dy * invMassFirst
                first.angle = normalizedAngle(first.angle - cross(rFirst, correction) * invInertiaFirst * angularPositionTransfer)
            }
            if invMassSecond > 0 {
                second.center.x += correction.dx * invMassSecond
                second.center.y += correction.dy * invMassSecond
                second.angle = normalizedAngle(second.angle + cross(rSecond, correction) * invInertiaSecond * angularPositionTransfer)
            }
        }

        let normalImpulseScale = max(0, collisionImpulseScale)
        guard normalImpulseScale > 0 else {
            bodies[firstIndex] = first
            bodies[secondIndex] = second
            return true
        }

        let dt = max(stepScale, 0.0001)
        let restitutionBase = min(max(collisionRestitution, 0), 1)
        let bouncyBase = min(max(bouncyRestitution, 0), 1.2)
        let glassPair = first.isGlass || second.isGlass
        let useBouncy = first.isBouncy || second.isBouncy
        let restitutionBoost: CGFloat
        if useBouncy {
            restitutionBoost = max(restitutionBase, bouncyBase)
        } else if glassPair {
            restitutionBoost = min(restitutionBase, 0.02)
        } else {
            restitutionBoost = restitutionBase
        }
        let restitutionThreshold: CGFloat = 0.08
        let baumgarte: CGFloat = 0.16
        let effectiveMass = invMassSum > 0 ? (1 / invMassSum) : 0
        let baseFriction = max(0, collisionFriction)
        let slipperyActive = first.isSlippery || second.isSlippery
        let stickyActive = first.isSticky || second.isSticky
        let friction: CGFloat
        if stickyActive {
            friction = min(4.0, baseFriction * 2.8)
        } else if slipperyActive {
            friction = baseFriction * 0.08
        } else if glassPair {
            friction = baseFriction * 1.15
        } else {
            friction = baseFriction
        }
        let frictionScale: CGFloat = 1.0
        let staticFriction = stickyActive ? min(6.0, friction * 1.6) : min(3.2, friction * 1.5)
        let dynamicFriction = stickyActive ? min(4.5, friction * 1.15) : min(2.4, friction * 0.9)
        let adjustedStatic = staticFriction * frictionScale
        let adjustedDynamic = dynamicFriction * frictionScale
        let stickyAdhesion: CGFloat = stickyActive ? 0.42 : 0

        for contact in manifold.contacts.prefix(2) {
            let rFirst = CGVector(
                dx: contact.position.x - first.center.x,
                dy: contact.position.y - first.center.y
            )
            let rSecond = CGVector(
                dx: contact.position.x - second.center.x,
                dy: contact.position.y - second.center.y
            )

            let velocityFirst = velocityAtContact(for: first, offset: rFirst)
            let velocitySecond = velocityAtContact(for: second, offset: rSecond)
            var relativeVelocity = CGVector(
                dx: velocitySecond.dx - velocityFirst.dx,
                dy: velocitySecond.dy - velocityFirst.dy
            )

            let velocityAlongNormal = dot(relativeVelocity, manifold.normal)
            let restitution = abs(velocityAlongNormal) < restitutionThreshold ? 0 : restitutionBoost
            let rFirstCrossNormal = cross(rFirst, manifold.normal)
            let rSecondCrossNormal = cross(rSecond, manifold.normal)
            let denominator = invMassSum +
                (rFirstCrossNormal * rFirstCrossNormal) * invInertiaFirst +
                (rSecondCrossNormal * rSecondCrossNormal) * invInertiaSecond

            if denominator <= 0.000001 { continue }

            let penetrationBias = max(contact.penetration - slop, 0) * (baumgarte / dt)
            let impulseMagnitude = max(
                0,
                (-(1 + restitution) * velocityAlongNormal + penetrationBias) / denominator * normalImpulseScale
            )
            let impactImpulseMagnitude = velocityAlongNormal < 0
                ? max(0, (-(1 + restitution) * velocityAlongNormal) / denominator * normalImpulseScale)
                : 0
            let impulse = CGVector(
                dx: manifold.normal.dx * impulseMagnitude,
                dy: manifold.normal.dy * impulseMagnitude
            )

            let impactSpeed = max(0, -velocityAlongNormal)
            if first.isGlass {
                registerGlassCollisionEvent(
                    glass: first,
                    other: second,
                    point: contact.position,
                    normal: CGVector(dx: -manifold.normal.dx, dy: -manifold.normal.dy),
                    impactImpulse: impactImpulseMagnitude,
                    impactSpeed: impactSpeed,
                    relativeVelocity: CGVector(dx: -relativeVelocity.dx, dy: -relativeVelocity.dy)
                )
            }
            if second.isGlass {
                registerGlassCollisionEvent(
                    glass: second,
                    other: first,
                    point: contact.position,
                    normal: manifold.normal,
                    impactImpulse: impactImpulseMagnitude,
                    impactSpeed: impactSpeed,
                    relativeVelocity: relativeVelocity
                )
            }

            if invMassFirst > 0 {
                first.velocity.dx -= impulse.dx * invMassFirst
                first.velocity.dy -= impulse.dy * invMassFirst
                first.angularVelocity -= cross(rFirst, impulse) * invInertiaFirst * collisionAngularTransfer
            }
            if invMassSecond > 0 {
                second.velocity.dx += impulse.dx * invMassSecond
                second.velocity.dy += impulse.dy * invMassSecond
                second.angularVelocity += cross(rSecond, impulse) * invInertiaSecond * collisionAngularTransfer
            }

            if stickyAdhesion > 0, velocityAlongNormal > 0, contact.penetration < 1.2 {
                let adhesiveMax = stickyAdhesion * max(0.8, effectiveMass) * (1 + contact.penetration * 0.4)
                let adhesiveMag = min(adhesiveMax, velocityAlongNormal / max(denominator, 0.0001))
                if adhesiveMag > 0 {
                    let adhesiveImpulse = CGVector(
                        dx: -manifold.normal.dx * adhesiveMag,
                        dy: -manifold.normal.dy * adhesiveMag
                    )
                    if invMassFirst > 0 {
                        first.velocity.dx -= adhesiveImpulse.dx * invMassFirst
                        first.velocity.dy -= adhesiveImpulse.dy * invMassFirst
                    }
                    if invMassSecond > 0 {
                        second.velocity.dx += adhesiveImpulse.dx * invMassSecond
                        second.velocity.dy += adhesiveImpulse.dy * invMassSecond
                    }
                }
            }

            relativeVelocity = CGVector(
                dx: velocityAtContact(for: second, offset: rSecond).dx - velocityAtContact(for: first, offset: rFirst).dx,
                dy: velocityAtContact(for: second, offset: rSecond).dy - velocityAtContact(for: first, offset: rFirst).dy
            )

            let tangentCandidate = CGVector(
                dx: relativeVelocity.dx - manifold.normal.dx * dot(relativeVelocity, manifold.normal),
                dy: relativeVelocity.dy - manifold.normal.dy * dot(relativeVelocity, manifold.normal)
            )
            let tangentLengthSquared = tangentCandidate.dx * tangentCandidate.dx + tangentCandidate.dy * tangentCandidate.dy
            if tangentLengthSquared <= 0.000001 { continue }

            let tangentLength = sqrt(tangentLengthSquared)
            let tangent = CGVector(
                dx: tangentCandidate.dx / tangentLength,
                dy: tangentCandidate.dy / tangentLength
            )

            let rFirstCrossTangent = cross(rFirst, tangent)
            let rSecondCrossTangent = cross(rSecond, tangent)
            let tangentDenominator = invMassSum +
                (rFirstCrossTangent * rFirstCrossTangent) * invInertiaFirst +
                (rSecondCrossTangent * rSecondCrossTangent) * invInertiaSecond

            if tangentDenominator <= 0.000001 { continue }

            let tangentVelocity = dot(relativeVelocity, tangent)
            var tangentImpulseMagnitude = -tangentVelocity / tangentDenominator
            let penetrationSupport = max(contact.penetration - slop, 0) * max(0, baumgarte / dt) * effectiveMass
            let supportImpulse = max(impulseMagnitude, penetrationSupport)
            let staticLimit = supportImpulse * adjustedStatic
            if abs(tangentImpulseMagnitude) > staticLimit {
                let direction: CGFloat = tangentVelocity >= 0 ? 1 : -1
                tangentImpulseMagnitude = -direction * supportImpulse * adjustedDynamic
            }

            let tangentImpulse = CGVector(
                dx: tangent.dx * tangentImpulseMagnitude,
                dy: tangent.dy * tangentImpulseMagnitude
            )

            if invMassFirst > 0 {
                first.velocity.dx -= tangentImpulse.dx * invMassFirst
                first.velocity.dy -= tangentImpulse.dy * invMassFirst
                first.angularVelocity -= cross(rFirst, tangentImpulse) * invInertiaFirst * collisionAngularTransfer
            }
            if invMassSecond > 0 {
                second.velocity.dx += tangentImpulse.dx * invMassSecond
                second.velocity.dy += tangentImpulse.dy * invMassSecond
                second.angularVelocity += cross(rSecond, tangentImpulse) * invInertiaSecond * collisionAngularTransfer
            }
        }

        bodies[firstIndex] = first
        bodies[secondIndex] = second
        return true
    }

    private func bodyCollisionManifold(_ first: Body, _ second: Body) -> CollisionManifold? {
        if first.shape == .circle, second.shape == .circle {
            return circleCollisionManifold(first, second)
        }

        if second.shape == .circle {
            return polygonCircleCollisionManifold(polygon: first, circle: second)
        }

        if first.shape == .circle {
            guard var manifold = polygonCircleCollisionManifold(polygon: second, circle: first) else { return nil }
            manifold.normal = CGVector(dx: -manifold.normal.dx, dy: -manifold.normal.dy)
            return manifold
        }

        return polygonCollisionManifold(first, second)
    }

    private func polygonCollisionManifold(_ first: Body, _ second: Body) -> CollisionManifold? {
        guard
            let firstVertices = bodyWorldVertices(for: first, forCollision: true),
            let secondVertices = bodyWorldVertices(for: second, forCollision: true),
            firstVertices.count > 2,
            secondVertices.count > 2
        else {
            return nil
        }

        let separationA = maxSeparation(between: firstVertices, and: secondVertices)
        if separationA.separation > 0 { return nil }

        let separationB = maxSeparation(between: secondVertices, and: firstVertices)
        if separationB.separation > 0 { return nil }

        var referenceVertices = firstVertices
        var incidentVertices = secondVertices
        var referenceEdgeIndex = separationA.edgeIndex
        var referenceNormal = separationA.normal
        var flip = false

        if separationB.separation > separationA.separation {
            referenceVertices = secondVertices
            incidentVertices = firstVertices
            referenceEdgeIndex = separationB.edgeIndex
            referenceNormal = separationB.normal
            flip = true
        }

        let referenceV1 = referenceVertices[referenceEdgeIndex]
        let referenceV2 = referenceVertices[(referenceEdgeIndex + 1) % referenceVertices.count]
        let edge = CGVector(dx: referenceV2.x - referenceV1.x, dy: referenceV2.y - referenceV1.y)
        let edgeLength = sqrt(edge.dx * edge.dx + edge.dy * edge.dy)
        if edgeLength <= 0.000001 { return nil }

        let tangent = CGVector(dx: edge.dx / edgeLength, dy: edge.dy / edgeLength)
        let incidentEdge = incidentEdgeVertices(on: incidentVertices, withNormal: referenceNormal)
        var clipped = [incidentEdge.start, incidentEdge.end]

        let offset1 = dot(tangent, referenceV1)
        clipped = clipSegmentToLine(clipped, normal: CGVector(dx: -tangent.dx, dy: -tangent.dy), offset: -offset1)
        if clipped.count < 2 { return nil }

        let offset2 = dot(tangent, referenceV2)
        clipped = clipSegmentToLine(clipped, normal: tangent, offset: offset2)
        if clipped.isEmpty { return nil }

        var contacts: [ContactPoint] = []
        contacts.reserveCapacity(2)
        for point in clipped {
            let separation = dot(referenceNormal, point) - dot(referenceNormal, referenceV1)
            if separation <= 0 {
                contacts.append(ContactPoint(position: point, penetration: -separation))
            }
        }

        if contacts.isEmpty { return nil }

        let normal = flip ? CGVector(dx: -referenceNormal.dx, dy: -referenceNormal.dy) : referenceNormal
        return CollisionManifold(normal: normal, contacts: contacts)
    }

    private func circleCollisionManifold(_ first: Body, _ second: Body) -> CollisionManifold? {
        let firstRadius = boundingRadius(for: first)
        let secondRadius = boundingRadius(for: second)
        let dx = second.center.x - first.center.x
        let dy = second.center.y - first.center.y
        let distanceSquared = dx * dx + dy * dy
        let radiusSum = firstRadius + secondRadius
        if distanceSquared >= radiusSum * radiusSum {
            return nil
        }

        let distance = sqrt(max(distanceSquared, 0.000001))
        let normal = CGVector(dx: dx / distance, dy: dy / distance)
        let penetration = radiusSum - distance
        let contact = CGPoint(
            x: first.center.x + normal.dx * (firstRadius - penetration * 0.5),
            y: first.center.y + normal.dy * (firstRadius - penetration * 0.5)
        )
        return CollisionManifold(normal: normal, contacts: [ContactPoint(position: contact, penetration: penetration)])
    }

    private func polygonCircleCollisionManifold(polygon: Body, circle: Body) -> CollisionManifold? {
        guard circle.shape == .circle else { return nil }
        guard let vertices = bodyWorldVertices(for: polygon, forCollision: true), vertices.count > 2 else { return nil }

        let radius = boundingRadius(for: circle)
        let center = circle.center
        var closest = CGPoint.zero
        var minDistanceSquared = CGFloat.greatestFiniteMagnitude

        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            let point = closestPointOnSegment(
                point: center,
                segmentStart: vertices[index],
                segmentEnd: vertices[nextIndex]
            )
            let dx = center.x - point.x
            let dy = center.y - point.y
            let distSq = dx * dx + dy * dy
            if distSq < minDistanceSquared {
                minDistanceSquared = distSq
                closest = point
            }
        }

        let inside = pointInPolygon(center, vertices: vertices)
        if !inside && minDistanceSquared > radius * radius {
            return nil
        }

        let distance = sqrt(max(minDistanceSquared, 0.000001))
        var normal: CGVector
        if distance > 0.0001 {
            normal = CGVector(
                dx: (center.x - closest.x) / distance,
                dy: (center.y - closest.y) / distance
            )
        } else {
            let fallback = CGVector(
                dx: circle.center.x - polygon.center.x,
                dy: circle.center.y - polygon.center.y
            )
            let fallbackLength = sqrt(max(fallback.dx * fallback.dx + fallback.dy * fallback.dy, 0.000001))
            normal = CGVector(dx: fallback.dx / fallbackLength, dy: fallback.dy / fallbackLength)
        }
        if inside {
            normal = CGVector(dx: -normal.dx, dy: -normal.dy)
        }

        let penetration = inside ? (radius + distance) : (radius - distance)
        if penetration <= 0 { return nil }
        return CollisionManifold(normal: normal, contacts: [ContactPoint(position: closest, penetration: penetration)])
    }

    private func polygonAxes(for vertices: [CGPoint]) -> [CGVector] {
        guard vertices.count > 1 else { return [] }
        var axes: [CGVector] = []
        axes.reserveCapacity(vertices.count)

        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            let edge = CGVector(
                dx: vertices[nextIndex].x - vertices[index].x,
                dy: vertices[nextIndex].y - vertices[index].y
            )
            let length = sqrt(edge.dx * edge.dx + edge.dy * edge.dy)
            if length <= 0.000001 { continue }
            axes.append(CGVector(dx: -edge.dy / length, dy: edge.dx / length))
        }

        return axes
    }

    private struct SeparationResult {
        let edgeIndex: Int
        let separation: CGFloat
        let normal: CGVector
    }

    private struct EdgeSegment {
        let start: CGPoint
        let end: CGPoint
    }

    private func polygonEdgeNormals(_ vertices: [CGPoint]) -> [CGVector] {
        guard vertices.count > 1 else { return [] }
        let isCCW = polygonSignedArea(vertices) >= 0
        var normals: [CGVector] = []
        normals.reserveCapacity(vertices.count)

        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            let edge = CGVector(
                dx: vertices[nextIndex].x - vertices[index].x,
                dy: vertices[nextIndex].y - vertices[index].y
            )
            let length = sqrt(edge.dx * edge.dx + edge.dy * edge.dy)
            if length <= 0.000001 {
                normals.append(CGVector(dx: 0, dy: 0))
                continue
            }
            let nx = isCCW ? edge.dy / length : -edge.dy / length
            let ny = isCCW ? -edge.dx / length : edge.dx / length
            normals.append(CGVector(dx: nx, dy: ny))
        }
        return normals
    }

    private func maxSeparation(between first: [CGPoint], and second: [CGPoint]) -> SeparationResult {
        let normals = polygonEdgeNormals(first)
        var bestSeparation = -CGFloat.greatestFiniteMagnitude
        var bestIndex = 0
        var bestNormal = CGVector(dx: 1, dy: 0)

        for index in normals.indices {
            let normal = normals[index]
            if normal.dx * normal.dx + normal.dy * normal.dy < 0.5 { continue }
            let support = first[index]
            var minProjection = CGFloat.greatestFiniteMagnitude
            for vertex in second {
                let projection = dot(normal, vertex)
                if projection < minProjection {
                    minProjection = projection
                }
            }
            let separation = minProjection - dot(normal, support)
            if separation > bestSeparation {
                bestSeparation = separation
                bestIndex = index
                bestNormal = normal
            }
        }

        return SeparationResult(edgeIndex: bestIndex, separation: bestSeparation, normal: bestNormal)
    }

    private func incidentEdgeVertices(on vertices: [CGPoint], withNormal normal: CGVector) -> EdgeSegment {
        let normals = polygonEdgeNormals(vertices)
        var minDot = CGFloat.greatestFiniteMagnitude
        var index = 0
        for i in normals.indices {
            if normals[i].dx * normals[i].dx + normals[i].dy * normals[i].dy < 0.5 { continue }
            let value = dot(normals[i], normal)
            if value < minDot {
                minDot = value
                index = i
            }
        }
        let start = vertices[index]
        let end = vertices[(index + 1) % vertices.count]
        return EdgeSegment(start: start, end: end)
    }

    private func clipSegmentToLine(_ points: [CGPoint], normal: CGVector, offset: CGFloat) -> [CGPoint] {
        guard points.count == 2 else { return points }
        let distance0 = dot(normal, points[0]) - offset
        let distance1 = dot(normal, points[1]) - offset
        var result: [CGPoint] = []
        if distance0 <= 0 { result.append(points[0]) }
        if distance1 <= 0 { result.append(points[1]) }
        if distance0 * distance1 < 0 {
            let t = distance0 / (distance0 - distance1)
            let interpolated = CGPoint(
                x: points[0].x + (points[1].x - points[0].x) * t,
                y: points[0].y + (points[1].y - points[0].y) * t
            )
            result.append(interpolated)
        }
        return result
    }

    private func projectedInterval(vertices: [CGPoint], axis: CGVector) -> (min: CGFloat, max: CGFloat) {
        guard let firstVertex = vertices.first else { return (0, 0) }
        var minProjection = firstVertex.x * axis.dx + firstVertex.y * axis.dy
        var maxProjection = minProjection

        for vertex in vertices.dropFirst() {
            let projection = vertex.x * axis.dx + vertex.y * axis.dy
            minProjection = min(minProjection, projection)
            maxProjection = max(maxProjection, projection)
        }
        return (minProjection, maxProjection)
    }

    private func supportPoint(vertices: [CGPoint], direction: CGVector) -> CGPoint {
        guard let firstVertex = vertices.first else { return .zero }
        var best = firstVertex
        var bestProjection = firstVertex.x * direction.dx + firstVertex.y * direction.dy

        for vertex in vertices.dropFirst() {
            let projection = vertex.x * direction.dx + vertex.y * direction.dy
            if projection > bestProjection {
                bestProjection = projection
                best = vertex
            }
        }

        return best
    }

    private func velocityAtContact(for body: Body, offset: CGVector) -> CGVector {
        CGVector(
            dx: body.velocity.dx - body.angularVelocity * offset.dy,
            dy: body.velocity.dy + body.angularVelocity * offset.dx
        )
    }

    private func dot(_ lhs: CGVector, _ rhs: CGVector) -> CGFloat {
        lhs.dx * rhs.dx + lhs.dy * rhs.dy
    }

    private func dot(_ lhs: CGVector, _ rhs: CGPoint) -> CGFloat {
        lhs.dx * rhs.x + lhs.dy * rhs.y
    }

    private func cross(_ lhs: CGVector, _ rhs: CGVector) -> CGFloat {
        lhs.dx * rhs.dy - lhs.dy * rhs.dx
    }

    private func applyWorldBounds(to body: inout Body) {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }

        let bouncyBoost = min(max(bouncyRestitution, 0), 1.2)
        let bounceX = body.isBouncy ? max(wallBounceX, bouncyBoost) : wallBounceX
        let bounceTop = body.isBouncy ? max(wallBounceTop, bouncyBoost) : wallBounceTop
        let bounceBottom = body.isBouncy ? max(wallBounceBottom, bouncyBoost) : wallBounceBottom

        var bounds = bodyBounds(body)
        var hitLeft = false
        var hitRight = false
        var hitTop = false
        var hitBottom = false

        if bounds.width >= viewportSize.width {
            body.center.x = viewportSize.width * 0.5
            hitLeft = true
            hitRight = true
        } else {
            if bounds.minX < 0 {
                body.center.x += -bounds.minX
                hitLeft = true
            } else if bounds.maxX > viewportSize.width {
                body.center.x -= (bounds.maxX - viewportSize.width)
                hitRight = true
            }
        }

        bounds = bodyBounds(body)
        if bounds.height >= viewportSize.height {
            body.center.y = viewportSize.height * 0.5
            hitTop = true
            hitBottom = true
        } else {
            if bounds.minY < 0 {
                body.center.y += -bounds.minY
                hitTop = true
            } else if bounds.maxY > viewportSize.height {
                body.center.y -= (bounds.maxY - viewportSize.height)
                hitBottom = true
            }
        }

        if hitLeft || hitRight {
            body.velocity.dx *= -bounceX
            body.angularVelocity *= 0.92
        }
        if hitTop {
            body.velocity.dy *= -bounceTop
            body.angularVelocity *= 0.9
        }
        if hitBottom {
            body.velocity.dy *= -bounceBottom
            body.velocity.dx *= 0.95
            body.angularVelocity *= 0.89
        }
    }

    private func applyLandSurfaceConstraint(to body: inout Body) {
        guard let contact = groundContactInfo(for: body) else { return }

        body.center.y -= contact.penetration

        let mass = max(bodyMass(for: body), 0.0001)
        let inertia = max(bodyInertia(for: body), 0.0001)
        let invMass: CGFloat = 1 / mass
        let invInertia: CGFloat = 1 / inertia

        let r = CGVector(dx: contact.point.x - body.center.x, dy: contact.point.y - body.center.y)
        var contactVelocity = velocityAtContact(for: body, offset: r)
        let impactSpeed = max(0, contactVelocity.dy)
        var normalImpulse: CGFloat = 0

        if contactVelocity.dy > 0.0005 {
            let bouncyBoost = min(max(bouncyRestitution, 0), 1.2)
            let baseBounce = min(max(landBounce, 0), 0.95)
            let restitution = body.isBouncy ? min(0.95, max(baseBounce, bouncyBoost)) : baseBounce
            let normalDenominator = invMass + (r.dx * r.dx) * invInertia
            if normalDenominator > 0.000001 {
                normalImpulse = (1 + restitution) * contactVelocity.dy / normalDenominator
                body.velocity.dy -= normalImpulse * invMass
                body.angularVelocity -= r.dx * normalImpulse * invInertia
                contactVelocity = velocityAtContact(for: body, offset: r)
            }
        } else if abs(contactVelocity.dy) < 0.06 {
            body.velocity.dy = min(body.velocity.dy, 0)
        }

        if body.isGlass {
            let impulseEstimate = normalImpulse * max(1, mass)
            let strength = glassStrengthScale(for: body)
            let highImpact = impactSpeed > (6.4 + max(0, strength - 1) * 0.9) || impulseEstimate > mass * (5.4 + max(0, strength - 1) * 1.15)
            let impactContribution = max(0, impactSpeed - (5.9 + max(0, strength - 1) * 0.78)) * 0.28 +
                max(0, impulseEstimate - mass * (4.9 + max(0, strength - 1) * 0.98)) * 0.03
            if highImpact, impactContribution > 0 {
                glassImpactInput[body.id, default: 0] += min(1.55, impactContribution / strength)
                glassBreakContact[body.id] = GlassBreakContact(
                    point: contact.point,
                    normal: CGVector(dx: 0, dy: -1),
                    sourceVelocity: body.velocity
                )
            }
        }

        let baseFriction = min(max(landFriction, 0), 2.0)
        let frictionCoefficient: CGFloat
        if body.isSticky {
            frictionCoefficient = min(3.0, baseFriction * 2.6)
        } else if body.isSlippery {
            frictionCoefficient = baseFriction * 0.08
        } else {
            frictionCoefficient = baseFriction
        }
        if frictionCoefficient > 0.0001 {
            let tangentDenominator = invMass + (r.dy * r.dy) * invInertia
            if tangentDenominator > 0.000001 {
                var tangentImpulse = -contactVelocity.dx / tangentDenominator
                let supportFactor = min(1.6, max(0.15, contact.supportWidth / max(20, bodyCharacteristicSize(for: body))))
                let gravitySupport = gravityForce * max(0, fallAccelerationScale)
                let supportImpulse = max(normalImpulse, gravitySupport * mass)
                let tangentSpeed = abs(contactVelocity.dx)
                let dynamicCoefficient = body.isSticky ? frictionCoefficient * 0.9 : frictionCoefficient * 0.8
                let coefficient = tangentSpeed > 0.35 ? dynamicCoefficient : frictionCoefficient
                let frictionLimit = max(0.001, supportImpulse * coefficient * supportFactor)
                tangentImpulse = min(max(tangentImpulse, -frictionLimit), frictionLimit)
                body.velocity.dx += tangentImpulse * invMass
                body.angularVelocity += (-r.dy * tangentImpulse) * invInertia
            }
        }

        if body.isSticky, abs(contactVelocity.dy) < 0.22 {
            body.velocity.dy = min(body.velocity.dy, 0)
        } else if contact.penetration < 0.8, abs(body.velocity.dy) < 0.05 {
            body.velocity.dy = 0
        }

        if body.isSticky, abs(body.velocity.dx) < 0.15 {
            body.velocity.dx = 0
        } else if !body.isSlippery, (throwCooldown[body.id] ?? 0) == 0, abs(body.velocity.dx) < 0.03 {
            body.velocity.dx = 0
        }

        let angularDamping = min(max(landAngularDamping, 0), 1)
        if abs(contactVelocity.dy) < 0.24 {
            body.angularVelocity *= angularDamping
        }

        let supportRatio = contact.supportWidth / max(1, bodyCharacteristicSize(for: body))
        if supportRatio > 0.55 {
            if abs(contactVelocity.dy) < 0.3 {
                body.angularVelocity *= 0.5
            }
            if
                abs(body.angularVelocity) < 0.05,
                abs(body.velocity.dx) < 0.12,
                abs(body.velocity.dy) < 0.12
            {
                if body.shape == .cube {
                    let quarter = CGFloat.pi / 2
                    let snapped = (body.angle / quarter).rounded() * quarter
                    if abs(normalizedAngle(body.angle - snapped)) < 0.1 {
                        body.angle = snapped
                    }
                }
                body.angularVelocity = 0
            }
        }
        if abs(body.angularVelocity) < 0.0008 {
            body.angularVelocity = 0
        }
        if abs(body.velocity.dx) < 0.03 {
            body.velocity.dx = 0
        }
        if abs(body.angularVelocity) < 0.002 {
            body.angularVelocity = 0
        }
        if abs(body.velocity.dx) < 0.06, abs(contactVelocity.dy) < 0.06 {
            body.velocity.dx = 0
        }
    }

    private func resolveWeldConstraints(components: [[UUID]]) {
        guard !components.isEmpty else { return }

        let baseIterations = max(1, Int(weldIterations.rounded()))
        let heavyScene = bodies.count > 14
        let wheelBoost = heavyScene ? 4 : 6
        let iterations = wheelBodies.isEmpty ? baseIterations : max(baseIterations, wheelBoost)
        for _ in 0..<iterations {
            if !wheelBodies.isEmpty {
                resolveWheelPinnedCenters()
            }

            for component in components {
                guard component.count > 1 else { continue }
                let rootID: UUID
                if
                    let draggingBodyIndex,
                    bodies.indices.contains(draggingBodyIndex),
                    component.contains(bodies[draggingBodyIndex].id)
                {
                    let draggedID = bodies[draggingBodyIndex].id
                    if isWheelBodyID(draggedID), let nonWheelRoot = component.first(where: { !isWheelBodyID($0) }) {
                        rootID = nonWheelRoot
                    } else {
                        rootID = draggedID
                    }
                } else if let nonWheelRoot = component.first(where: { !isWheelBodyID($0) }) {
                    rootID = nonWheelRoot
                } else {
                    rootID = component[0]
                }
                applyRigidWeldProjection(componentIDs: component, rootID: rootID)
            }
        }

        for component in components {
            synchronizeRigidWeldVelocities(componentIDs: component)
        }
    }

    private func isWheelBodyID(_ id: UUID) -> Bool {
        wheelBodies.contains(id)
    }

    private func isWheelBody(_ index: Int) -> Bool {
        guard bodies.indices.contains(index) else { return false }
        return wheelBodies.contains(bodies[index].id)
    }

    private func applyRigidWeldProjection(componentIDs: [UUID], rootID: UUID) {
        guard componentIDs.count > 1 else { return }
        guard let rootIndex = bodyIndex(forID: rootID), bodies.indices.contains(rootIndex) else { return }

        let componentSet = Set(componentIDs)
        var visited: Set<UUID> = [rootID]
        var queue: [UUID] = [rootID]

        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            guard let currentIndex = bodyIndex(forID: currentID), bodies.indices.contains(currentIndex) else { continue }
            let currentBody = bodies[currentIndex]

            for weld in weldConstraints {
                if wheelBodies.contains(weld.firstID) || wheelBodies.contains(weld.secondID) {
                    continue
                }
                if weld.firstID == currentID, componentSet.contains(weld.secondID) {
                    let nextID = weld.secondID
                    guard !visited.contains(nextID), let nextIndex = bodyIndex(forID: nextID), bodies.indices.contains(nextIndex) else { continue }
                    let nextAngle = normalizedAngle(currentBody.angle + weld.restAngle)
                    let firstAnchorWorld = worldPoint(fromLocal: weld.firstLocalAnchor, in: currentBody)
                    if !isWheelBodyID(nextID), !isWheelBodyID(currentID) {
                        bodies[nextIndex].angle = nextAngle
                    }
                    let appliedAngle = bodies[nextIndex].angle
                    let secondOffset = rotateVector(
                        CGVector(dx: weld.secondLocalAnchor.x, dy: weld.secondLocalAnchor.y),
                        by: appliedAngle
                    )
                    bodies[nextIndex].center = CGPoint(
                        x: firstAnchorWorld.x - secondOffset.dx,
                        y: firstAnchorWorld.y - secondOffset.dy
                    )
                    visited.insert(nextID)
                    queue.append(nextID)
                } else if weld.secondID == currentID, componentSet.contains(weld.firstID) {
                    let nextID = weld.firstID
                    guard !visited.contains(nextID), let nextIndex = bodyIndex(forID: nextID), bodies.indices.contains(nextIndex) else { continue }
                    let nextAngle = normalizedAngle(currentBody.angle - weld.restAngle)
                    let secondAnchorWorld = worldPoint(fromLocal: weld.secondLocalAnchor, in: currentBody)
                    if !isWheelBodyID(nextID), !isWheelBodyID(currentID) {
                        bodies[nextIndex].angle = nextAngle
                    }
                    let appliedAngle = bodies[nextIndex].angle
                    let firstOffset = rotateVector(
                        CGVector(dx: weld.firstLocalAnchor.x, dy: weld.firstLocalAnchor.y),
                        by: appliedAngle
                    )
                    bodies[nextIndex].center = CGPoint(
                        x: secondAnchorWorld.x - firstOffset.dx,
                        y: secondAnchorWorld.y - firstOffset.dy
                    )
                    visited.insert(nextID)
                    queue.append(nextID)
                }
            }
        }
    }

    private func synchronizeRigidWeldVelocities(componentIDs: [UUID]) {
        let indices = componentIDs.compactMap(bodyIndex(forID:))
        guard indices.count > 1 else { return }

        let hasWheelInComponent = indices.contains { isWheelBody($0) }
        if hasWheelInComponent {
            guard let rootIndex = nonWheelRootIndex(for: indices) else { return }
            let root = bodies[rootIndex]
            let rootOmega: CGFloat = draggingBodyIndex == rootIndex ? 0 : root.angularVelocity

            for index in indices where index != rootIndex {
                if isWheelBody(index) { continue }
                let r = CGVector(
                    dx: bodies[index].center.x - root.center.x,
                    dy: bodies[index].center.y - root.center.y
                )
                bodies[index].velocity = CGVector(
                    dx: root.velocity.dx - rootOmega * r.dy,
                    dy: root.velocity.dy + rootOmega * r.dx
                )
                bodies[index].angularVelocity = rootOmega
            }
            return
        }

        if let draggingBodyIndex, indices.contains(draggingBodyIndex), bodies.indices.contains(draggingBodyIndex) {
            let root = bodies[draggingBodyIndex]
            let rootOmega: CGFloat = isWheelBodyID(root.id) ? 0 : root.angularVelocity
            for index in indices where index != draggingBodyIndex {
                let r = CGVector(
                    dx: bodies[index].center.x - root.center.x,
                    dy: bodies[index].center.y - root.center.y
                )
                bodies[index].velocity = CGVector(
                    dx: root.velocity.dx - rootOmega * r.dy,
                    dy: root.velocity.dy + rootOmega * r.dx
                )
                if !isWheelBody(index), !isWheelBodyID(root.id) {
                    bodies[index].angularVelocity = root.angularVelocity
                }
            }
            return
        }

        var totalMass: CGFloat = 0
        var centroid = CGPoint.zero
        for index in indices {
            let mass = bodyMass(for: bodies[index])
            totalMass += mass
            centroid.x += bodies[index].center.x * mass
            centroid.y += bodies[index].center.y * mass
        }

        guard totalMass > 0.000001 else { return }
        centroid.x /= totalMass
        centroid.y /= totalMass

        var linearMomentum = CGVector.zero
        var angularMomentum: CGFloat = 0
        var effectiveInertia: CGFloat = 0
        for index in indices {
            let mass = bodyMass(for: bodies[index])
            let inertia = bodyInertia(for: bodies[index])
            let r = CGVector(
                dx: bodies[index].center.x - centroid.x,
                dy: bodies[index].center.y - centroid.y
            )

            linearMomentum.dx += bodies[index].velocity.dx * mass
            linearMomentum.dy += bodies[index].velocity.dy * mass
            angularMomentum += mass * cross(r, bodies[index].velocity)
            if isWheelBody(index) {
                effectiveInertia += mass * (r.dx * r.dx + r.dy * r.dy)
            } else {
                angularMomentum += inertia * bodies[index].angularVelocity
                effectiveInertia += inertia + mass * (r.dx * r.dx + r.dy * r.dy)
            }
        }

        let centerVelocity = CGVector(
            dx: linearMomentum.dx / totalMass,
            dy: linearMomentum.dy / totalMass
        )
        let omega: CGFloat = effectiveInertia > 0.000001 ? (angularMomentum / effectiveInertia) : 0

        for index in indices {
            let r = CGVector(
                dx: bodies[index].center.x - centroid.x,
                dy: bodies[index].center.y - centroid.y
            )
            bodies[index].velocity = CGVector(
                dx: centerVelocity.dx - omega * r.dy,
                dy: centerVelocity.dy + omega * r.dx
            )
            if !isWheelBody(index) {
                bodies[index].angularVelocity = omega
            }
        }
    }

    private func nonWheelRootIndex(for indices: [Int]) -> Int? {
        if
            let draggingBodyIndex,
            indices.contains(draggingBodyIndex),
            bodies.indices.contains(draggingBodyIndex),
            !isWheelBody(draggingBodyIndex)
        {
            return draggingBodyIndex
        }

        if let firstNonWheel = indices.first(where: { !isWheelBody($0) }) {
            return firstNonWheel
        }

        return indices.first
    }

    private func resolveWheelPinnedCenters() {
        guard !wheelBodies.isEmpty else { return }

        var hostWheelMap: [UUID: [(wheelID: UUID, wheelIndex: Int, anchorLocal: CGPoint)]] = [:]

        for weld in weldConstraints {
            if wheelBodies.contains(weld.firstID), !wheelBodies.contains(weld.secondID) {
                if let wheelIndex = bodyIndex(forID: weld.firstID) {
                    hostWheelMap[weld.secondID, default: []].append(
                        (wheelID: weld.firstID, wheelIndex: wheelIndex, anchorLocal: weld.secondLocalAnchor)
                    )
                }
            } else if wheelBodies.contains(weld.secondID), !wheelBodies.contains(weld.firstID) {
                if let wheelIndex = bodyIndex(forID: weld.secondID) {
                    hostWheelMap[weld.firstID, default: []].append(
                        (wheelID: weld.secondID, wheelIndex: wheelIndex, anchorLocal: weld.firstLocalAnchor)
                    )
                }
            }
        }

        for (hostID, wheels) in hostWheelMap {
            guard let hostIndex = bodyIndex(forID: hostID), bodies.indices.contains(hostIndex) else { continue }
            var host = bodies[hostIndex]
            let dragHost = draggingBodyIndex == hostIndex

            var sumError = CGVector.zero
            var validCount: CGFloat = 0

            for item in wheels {
                guard bodies.indices.contains(item.wheelIndex) else { continue }
                let wheel = bodies[item.wheelIndex]
                let anchor = worldPoint(fromLocal: item.anchorLocal, in: host)
                sumError.dx += wheel.center.x - anchor.x
                sumError.dy += wheel.center.y - anchor.y
                validCount += 1
            }

            guard validCount > 0 else { continue }
            let avgError = CGVector(dx: sumError.dx / validCount, dy: sumError.dy / validCount)
            let positionBeta: CGFloat = wheels.count > 1 ? 0.85 : 0.9

            if dragHost {
                for item in wheels {
                    guard bodies.indices.contains(item.wheelIndex) else { continue }
                    var wheel = bodies[item.wheelIndex]
                    let anchor = worldPoint(fromLocal: item.anchorLocal, in: host)
                    wheel.center = anchor
                    wheel.velocity = host.velocity
                    bodies[item.wheelIndex] = wheel
                }
            } else {
                host.center.x += avgError.dx * positionBeta
                host.center.y += avgError.dy * positionBeta
                if wheels.count > 1 {
                    host.angularVelocity *= 0.4
                    if abs(host.angularVelocity) < 0.001 {
                        host.angularVelocity = 0
                    }
                }
            }

            bodies[hostIndex] = host
        }
    }

    private func cleanupWeldState() {
        let ids = Set(bodies.map(\.id))
        weldConstraints.removeAll { !ids.contains($0.firstID) || !ids.contains($0.secondID) || $0.firstID == $0.secondID }
        let weldedIDs = Set(weldConstraints.flatMap { [$0.firstID, $0.secondID] })
        wheelBodies = wheelBodies.filter { ids.contains($0) && weldedIDs.contains($0) }
        bodySplashCooldown = bodySplashCooldown.filter { ids.contains($0.key) }
        if let pendingID = pendingWeldBodyID, !ids.contains(pendingID) {
            pendingWeldBodyID = nil
            pendingWeldAnchorLocal = nil
            weldPendingPoint = nil
        }
    }

    private func weldedTopology() -> (components: [[UUID]], lookup: [UUID: Int]) {
        var adjacency: [UUID: Set<UUID>] = [:]
        for weld in weldConstraints {
            adjacency[weld.firstID, default: []].insert(weld.secondID)
            adjacency[weld.secondID, default: []].insert(weld.firstID)
        }

        var visited: Set<UUID> = []
        var components: [[UUID]] = []

        for id in adjacency.keys {
            if visited.contains(id) { continue }
            var queue: [UUID] = [id]
            var component: [UUID] = []
            visited.insert(id)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                component.append(current)
                for neighbor in adjacency[current] ?? [] where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }

            if component.count > 1 {
                components.append(component)
            }
        }

        var lookup: [UUID: Int] = [:]
        for (groupIndex, component) in components.enumerated() {
            for id in component {
                lookup[id] = groupIndex
            }
        }
        return (components, lookup)
    }

    private func weldedComponents() -> [[UUID]] {
        weldedTopology().components
    }

    private func weldGroupLookup() -> [UUID: Int] {
        weldedTopology().lookup
    }

    private func weldedComponentIndices(containing index: Int) -> [Int] {
        guard bodies.indices.contains(index) else { return [] }
        let sourceID = bodies[index].id
        let lookup = weldedTopology().lookup
        guard let group = lookup[sourceID] else { return [index] }

        return bodies.indices.filter { idx in
            guard let value = lookup[bodies[idx].id] else { return false }
            return value == group
        }
    }

    private func propagateDraggedWeldComponent(from rootIndex: Int) {
        guard bodies.indices.contains(rootIndex) else { return }
        let requestedRootID = bodies[rootIndex].id
        let lookup = weldedTopology().lookup
        guard let group = lookup[requestedRootID] else { return }
        let component = bodies.compactMap { body -> UUID? in
            guard let g = lookup[body.id], g == group else { return nil }
            return body.id
        }
        guard component.count > 1 else { return }

        let rootID: UUID
        if
            isWheelBodyID(requestedRootID),
            let nonWheel = component.first(where: { !isWheelBodyID($0) })
        {
            rootID = nonWheel
        } else {
            rootID = requestedRootID
        }

        applyRigidWeldProjection(componentIDs: component, rootID: rootID)
        synchronizeRigidWeldVelocities(componentIDs: component)
    }

    private func handleWeldSelection(at location: CGPoint) {
        guard let targetIndex = bodyIndex(containing: location), bodies.indices.contains(targetIndex) else { return }
        let targetBody = bodies[targetIndex]

        if let pendingID = pendingWeldBodyID {
            if pendingID == targetBody.id {
                pendingWeldBodyID = nil
                pendingWeldAnchorLocal = nil
                weldPendingPoint = nil
            } else {
                let alreadyLinked = weldConstraints.contains {
                    ($0.firstID == pendingID && $0.secondID == targetBody.id) ||
                    ($0.firstID == targetBody.id && $0.secondID == pendingID)
                }
                if !alreadyLinked, let firstIndex = bodyIndex(forID: pendingID) {
                    let firstBody = bodies[firstIndex]
                    let restCenterOffsetLocal = localPoint(fromWorld: targetBody.center, in: firstBody)
                    weldConstraints.append(
                        WeldConstraint(
                            firstID: pendingID,
                            secondID: targetBody.id,
                            firstLocalAnchor: restCenterOffsetLocal,
                            secondLocalAnchor: .zero,
                            restAngle: normalizedAngle(targetBody.angle - firstBody.angle)
                        )
                    )
                    if isWheelBodyID(pendingID) {
                        canonicalizeWheelWelds(for: pendingID)
                    }
                    if isWheelBodyID(targetBody.id) {
                        canonicalizeWheelWelds(for: targetBody.id)
                    }
                }
                pendingWeldBodyID = nil
                pendingWeldAnchorLocal = nil
                weldPendingPoint = nil
            }
        } else {
            pendingWeldBodyID = targetBody.id
            pendingWeldAnchorLocal = .zero
            weldPendingPoint = targetBody.center
        }
    }

    private func handleWheelSelection(at location: CGPoint) {
        guard let targetIndex = bodyIndex(containing: location), bodies.indices.contains(targetIndex) else { return }
        let targetID = bodies[targetIndex].id

        let topology = weldedTopology()
        guard let group = topology.lookup[targetID] else { return } // not welded -> no-op

        let groupBodies = topology.components[group]
        guard groupBodies.count > 1 else { return }

        if wheelBodies.contains(targetID) {
            wheelBodies.remove(targetID)
        } else {
            wheelBodies.insert(targetID)
            canonicalizeWheelWelds(for: targetID)
        }
        syncBodyDrawStates()
    }

    private func handleBounceSelection(at location: CGPoint) {
        guard let targetIndex = bodyIndex(containing: location), bodies.indices.contains(targetIndex) else { return }
        bodies[targetIndex].isBouncy.toggle()
        syncBodyDrawStates()
    }

    private func handleSlipSelection(at location: CGPoint) {
        guard let targetIndex = bodyIndex(containing: location), bodies.indices.contains(targetIndex) else { return }
        bodies[targetIndex].isSlippery.toggle()
        if bodies[targetIndex].isSlippery {
            bodies[targetIndex].isSticky = false
        }
        syncBodyDrawStates()
    }

    private func handleStickySelection(at location: CGPoint) {
        guard let targetIndex = bodyIndex(containing: location), bodies.indices.contains(targetIndex) else { return }
        bodies[targetIndex].isSticky.toggle()
        if bodies[targetIndex].isSticky {
            bodies[targetIndex].isSlippery = false
        }
        syncBodyDrawStates()
    }

    private func handleGlassSelection(at location: CGPoint) {
        guard let targetIndex = bodyIndex(containing: location), bodies.indices.contains(targetIndex) else { return }
        bodies[targetIndex].isGlass.toggle()
        let bodyID = bodies[targetIndex].id
        pendingGlassShatters.removeValue(forKey: bodyID)
        glassDamage.removeValue(forKey: bodyID)
        glassImpactInput.removeValue(forKey: bodyID)
        glassBreakContact.removeValue(forKey: bodyID)
        if bodies[targetIndex].isGlass {
            glassGraceFrames[bodyID] = 30
        } else {
            glassGraceFrames.removeValue(forKey: bodyID)
        }
        syncBodyDrawStates()
    }

    private func canonicalizeWheelWelds(for wheelID: UUID) {
        guard let wheelIndex = bodyIndex(forID: wheelID), bodies.indices.contains(wheelIndex) else { return }
        let wheelCenter = bodies[wheelIndex].center

        for idx in weldConstraints.indices {
            var weld = weldConstraints[idx]
            if weld.firstID == wheelID {
                guard let otherIndex = bodyIndex(forID: weld.secondID), bodies.indices.contains(otherIndex) else { continue }
                let otherBody = bodies[otherIndex]
                weld = WeldConstraint(
                    firstID: otherBody.id,
                    secondID: wheelID,
                    firstLocalAnchor: localPoint(fromWorld: wheelCenter, in: otherBody),
                    secondLocalAnchor: .zero,
                    restAngle: normalizedAngle(bodies[wheelIndex].angle - otherBody.angle)
                )
                weldConstraints[idx] = weld
            } else if weld.secondID == wheelID {
                guard let otherIndex = bodyIndex(forID: weld.firstID), bodies.indices.contains(otherIndex) else { continue }
                let otherBody = bodies[otherIndex]
                weld = WeldConstraint(
                    firstID: otherBody.id,
                    secondID: wheelID,
                    firstLocalAnchor: localPoint(fromWorld: wheelCenter, in: otherBody),
                    secondLocalAnchor: .zero,
                    restAngle: normalizedAngle(bodies[wheelIndex].angle - otherBody.angle)
                )
                weldConstraints[idx] = weld
            }
        }
    }

    private func applyWaveReactionImpulse(atX x: CGFloat, fromWaterForceY forceY: CGFloat, spawnSpray: Bool = false) {
        guard sceneLocation == .water else { return }
        guard viewportSize.width > 1 else { return }

        // Opposite force on water, distributed to neighboring samples.
        let reactionImpulse = -forceY * reactionImpulseScale
        if abs(reactionImpulse) < 0.0001 { return }

        let samplePosition = max(0, min(1, x / viewportSize.width)) * CGFloat(pointCount - 1)
        let center = Int(samplePosition)

        let spread = 3
        for offset in -spread...spread {
            let index = center + offset
            if index <= 0 || index >= pointCount - 1 { continue }
            let weight = exp(-CGFloat(offset * offset) / 3.8)
            velocities[index] += reactionImpulse * weight
            velocities[index] = max(-maxVelocity, min(maxVelocity, velocities[index]))
        }

        if spawnSpray, waterSprayEnabled, abs(reactionImpulse) > 0.08 {
            let chunkCount = min(2, max(1, Int(abs(reactionImpulse) * 18)))
            spawnWaterChunks(atX: x, count: chunkCount, energy: abs(reactionImpulse) * 0.9)
        }
    }

    private func pointerSuppressionFactor() -> CGFloat {
        let start = pointerSuppressionStart
        let full = max(start + 1, pointerSuppressionFull)
        if surfaceSpread <= start { return 1 }
        if surfaceSpread >= full { return pointerSuppressionMin }
        let t = (surfaceSpread - start) / (full - start)
        return 1 - t * (1 - pointerSuppressionMin)
    }

    private func physicsSubsteps() -> Int {
        guard !bodies.isEmpty else { return 1 }
        let maxSpeed = bodies.map { hypot($0.velocity.dx, $0.velocity.dy) }.max() ?? 0
        let speedSteps = Int(ceil(maxSpeed / 5))
        let densitySteps = bodies.count > 26 ? 3 : (bodies.count > 12 ? 2 : 1)
        var minimum = (sceneLocation == .land && bodies.count > 1) ? 2 : 1
        if bodies.count > 14 {
            minimum = max(minimum, 3)
        }
        let result = max(minimum, max(speedSteps, densitySteps))
        return min(6, result)
    }

    private func limitedDisplacement(_ value: CGFloat) -> CGFloat {
        let upMax = max(1, maxUpDisplacement)
        let downMax = max(1, maxDownDisplacement)
        let softUp = min(softUpLimitStart, upMax * 0.99)
        let softDown = min(softDownLimitStart, downMax * 0.99)

        if value < 0 {
            let magnitude = -value
            if magnitude <= softUp {
                return value
            }

            let overflow = magnitude - softUp
            let compressed = softUp + overflow * 0.62
            return -min(upMax, compressed)
        }

        if value <= softDown {
            return value
        }

        let overflow = value - softDown
        let compressed = softDown + overflow * 0.5
        return min(downMax, compressed)
    }

    private func rotate(point: CGPoint, by angle: CGFloat, around center: CGPoint) -> CGPoint {
        let cosA = cos(angle)
        let sinA = sin(angle)

        return CGPoint(
            x: center.x + point.x * cosA - point.y * sinA,
            y: center.y + point.x * sinA + point.y * cosA
        )
    }

    private func interpolatedValue(in array: [CGFloat], atX x: CGFloat) -> CGFloat {
        guard !array.isEmpty, viewportSize.width > 1 else { return 0 }

        let normalized = max(0, min(1, x / viewportSize.width))
        let samplePosition = normalized * CGFloat(array.count - 1)
        let left = min(Int(samplePosition), array.count - 1)
        let right = min(left + 1, array.count - 1)
        let fraction = samplePosition - CGFloat(left)
        return array[left] + (array[right] - array[left]) * fraction
    }

    private func waveHeight(atX x: CGFloat) -> CGFloat {
        let baseY = surfaceBaselineY()
        guard sceneLocation == .water else { return baseY }
        return baseY + interpolatedValue(in: samples, atX: x)
    }

    private func waveVelocity(atX x: CGFloat) -> CGFloat {
        guard sceneLocation == .water else { return 0 }
        return interpolatedValue(in: velocities, atX: x)
    }

    private func waveSlope(atX x: CGFloat) -> CGFloat {
        guard sceneLocation == .water else { return 0 }
        guard viewportSize.width > 1 else { return 0 }
        let deltaX = max(2, viewportSize.width / CGFloat(pointCount) * 2)
        let leftX = max(0, x - deltaX)
        let rightX = min(viewportSize.width, x + deltaX)
        let dy = waveHeight(atX: rightX) - waveHeight(atX: leftX)
        return dy / max(1, rightX - leftX)
    }

    private func surfaceBaselineY() -> CGFloat {
        surfaceBaselineY(in: viewportSize)
    }

    private func bodyIndex(containing point: CGPoint) -> Int? {
        for index in bodies.indices.reversed() {
            if bodyContains(point, body: bodies[index]) {
                return index
            }
        }
        return nil
    }

    private func bodyContains(_ point: CGPoint, body: Body) -> Bool {
        switch body.shape {
        case .cube:
            let dx = point.x - body.center.x
            let dy = point.y - body.center.y
            let cosA = cos(-body.angle)
            let sinA = sin(-body.angle)
            let localX = dx * cosA - dy * sinA
            let localY = dx * sinA + dy * cosA
            let half = squareSize * 0.5
            return abs(localX) <= half && abs(localY) <= half
        case .circle:
            let dx = point.x - body.center.x
            let dy = point.y - body.center.y
            return dx * dx + dy * dy <= circleRadius * circleRadius
        case .polygon:
            guard let vertices = body.localVertices ?? body.collisionVertices, vertices.count > 2 else { return false }
            let local = localPoint(fromWorld: point, in: body)
            return pointInPolygon(local, vertices: vertices)
        }
    }

    private func randomPointInsideBody(_ body: Body, attempts: Int = 36) -> CGPoint? {
        let bounds = bodyBounds(body)
        guard bounds.width > 0.001, bounds.height > 0.001 else { return body.center }

        var fallback: CGPoint?
        for _ in 0..<max(1, attempts) {
            let point = CGPoint(
                x: CGFloat.random(in: bounds.minX...bounds.maxX),
                y: CGFloat.random(in: bounds.minY...bounds.maxY)
            )
            if bodyContains(point, body: body) {
                return point
            }
            fallback = point
        }
        return fallback
    }

    private func groundY() -> CGFloat {
        surfaceBaselineY()
    }

    private func groundContactInfo(for body: Body) -> GroundContact? {
        let ground = groundY()

        switch body.shape {
        case .circle:
            let bottom = body.center.y + circleRadius
            let penetration = bottom - ground
            if penetration <= 0 { return nil }
            return GroundContact(
                penetration: penetration,
                point: CGPoint(x: body.center.x, y: ground),
                supportWidth: circleRadius * 2
            )
        case .cube, .polygon:
            guard let vertices = bodyWorldVertices(for: body, forCollision: false), !vertices.isEmpty else {
                return nil
            }
            guard let maxY = vertices.map(\.y).max() else { return nil }
            let penetration = maxY - ground
            if penetration <= 0 { return nil }

            let band = max(1.4, penetration + 0.8)
            var contactVertices = vertices.filter { maxY - $0.y <= band }
            if contactVertices.isEmpty, let deepest = vertices.max(by: { $0.y < $1.y }) {
                contactVertices = [deepest]
            }
            guard !contactVertices.isEmpty else { return nil }

            let avgX = contactVertices.map(\.x).reduce(0, +) / CGFloat(contactVertices.count)
            let minX = contactVertices.map(\.x).min() ?? avgX
            let maxX = contactVertices.map(\.x).max() ?? avgX
            let width = max(1, maxX - minX)
            return GroundContact(
                penetration: penetration,
                point: CGPoint(x: avgX, y: ground),
                supportWidth: width
            )
        }
    }

    private func shouldSettleBodyAtRest(index: Int) -> Bool {
        guard bodies.indices.contains(index) else { return false }
        let body = bodies[index]

        if abs(body.velocity.dx) > 0.12 { return false }
        if abs(body.velocity.dy) > 0.12 { return false }
        if abs(body.angularVelocity) > 0.01 { return false }

        if groundContactInfo(for: body) != nil {
            return true
        }

        return isSupportedByAnotherBodyFromBelow(body)
    }

    private func isSupportedByAnotherBodyFromBelow(_ body: Body) -> Bool {
        let halfWidth = bodyCharacteristicSize(for: body) * 0.3
        let probeOffsets: [CGFloat] = [0, -halfWidth, halfWidth]
        let probeY = bodyBottomY(body) + 1.2

        for offsetX in probeOffsets {
            let probe = CGPoint(x: body.center.x + offsetX, y: probeY)
            for other in bodies where other.id != body.id {
                guard other.center.y >= body.center.y - 3 else { continue }
                if bodyContains(probe, body: other) {
                    return true
                }
            }
        }

        return false
    }

    private func bodyBottomY(_ body: Body) -> CGFloat {
        switch body.shape {
        case .circle:
            return body.center.y + circleRadius
        case .cube, .polygon:
            guard let vertices = bodyWorldVertices(for: body, forCollision: false), !vertices.isEmpty else {
                return body.center.y + boundingRadius(for: body)
            }
            return vertices.map(\.y).max() ?? (body.center.y + boundingRadius(for: body))
        }
    }

    private func clampedBodyCenter(_ point: CGPoint, for body: Body) -> CGPoint {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return point }

        let radius = boundingRadius(for: body)
        let clampedX = min(max(radius, point.x), max(radius, viewportSize.width - radius))
        let clampedY = min(max(radius, point.y), max(radius, viewportSize.height - radius))
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func clampedDragCenter(_ point: CGPoint, for body: Body) -> CGPoint {
        var adjusted = clampedBodyCenter(point, for: body)
        guard sceneLocation == .land, viewportSize.width > 1, viewportSize.height > 1 else { return adjusted }
        let groundY = surfaceBaselineY(in: viewportSize)
        var temp = body
        temp.center = adjusted
        let bottom = bodyBottomY(temp)
        if bottom > groundY {
            adjusted.y -= (bottom - groundY)
        }
        return clampedBodyCenter(adjusted, for: temp)
    }

    private func clampAllBodiesInside() {
        for index in bodies.indices {
            bodies[index].center = clampedBodyCenter(bodies[index].center, for: bodies[index])
        }
    }

    private func bodyBounds(_ body: Body) -> CGRect {
        switch body.shape {
        case .circle:
            let r = circleRadius
            return CGRect(x: body.center.x - r, y: body.center.y - r, width: r * 2, height: r * 2)
        case .cube, .polygon:
            guard let vertices = bodyWorldVertices(for: body, forCollision: false), !vertices.isEmpty else {
                let r = boundingRadius(for: body)
                return CGRect(x: body.center.x - r, y: body.center.y - r, width: r * 2, height: r * 2)
            }
            let minX = vertices.map(\.x).min() ?? body.center.x
            let maxX = vertices.map(\.x).max() ?? body.center.x
            let minY = vertices.map(\.y).min() ?? body.center.y
            let maxY = vertices.map(\.y).max() ?? body.center.y
            return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        }
    }

    private func updateSelectionRect(to point: CGPoint, additive: Bool) {
        guard let start = selectionDragStart else { return }
        let minX = min(start.x, point.x)
        let minY = min(start.y, point.y)
        let maxX = max(start.x, point.x)
        let maxY = max(start.y, point.y)
        let rect = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        selectionRect = rect

        var nextSelection: Set<UUID> = additive ? selectedBodyIDs : []
        for body in bodies {
            if rect.intersects(bodyBounds(body)) {
                nextSelection.insert(body.id)
            }
        }
        selectedBodyIDs = nextSelection
        syncBodyDrawStates()
    }

    private func syncBodyDrawStates() {
        bodyIndexByID.removeAll(keepingCapacity: true)
        var snapshot: [BodyDrawState] = []
        snapshot.reserveCapacity(bodies.count)

        for (index, body) in bodies.enumerated() {
            bodyIndexByID[body.id] = index
            snapshot.append(
                BodyDrawState(
                    id: body.id,
                    shape: body.shape,
                    center: body.center,
                    angle: body.angle,
                    localVertices: body.localVertices,
                    isWheel: wheelBodies.contains(body.id),
                    isSelected: selectedBodyIDs.contains(body.id),
                    isBouncy: body.isBouncy,
                    isSlippery: body.isSlippery,
                    isSticky: body.isSticky,
                    isGlass: body.isGlass
                )
            )
        }
        bodyDrawStates = snapshot
    }

    private func syncWeldPreviewPoints() {
        guard weldToolEnabled else {
            weldPendingPoint = nil
            return
        }
        guard
            let pendingID = pendingWeldBodyID,
            let local = pendingWeldAnchorLocal,
            let index = bodyIndex(forID: pendingID)
        else {
            weldPendingPoint = nil
            return
        }
        weldPendingPoint = worldPoint(fromLocal: local, in: bodies[index])
    }

    private func makeBody(
        shape: BodyShape,
        center: CGPoint,
        localVertices: [CGPoint]? = nil,
        collisionVertices: [CGPoint]? = nil,
        collisionVertexCap: Int = 0
    ) -> Body {
        Body(
            id: UUID(),
            shape: shape,
            center: center,
            angle: 0,
            velocity: .zero,
            angularVelocity: 0,
            localVertices: localVertices,
            collisionVertices: collisionVertices,
            collisionVertexCap: collisionVertexCap,
            isBouncy: false,
            isSlippery: false,
            isSticky: false,
            isGlass: false
        )
    }

    private func defaultBodyCenter(forIndex index: Int, in size: CGSize) -> CGPoint {
        let targetSize = (size.width > 1 && size.height > 1) ? size : CGSize(width: 1000, height: 560)
        if index == 0 {
            return CGPoint(x: targetSize.width * 0.5, y: targetSize.height * 0.34)
        }

        let localIndex = index - 1
        let columns = 4
        let row = CGFloat(localIndex / columns)
        let column = CGFloat(localIndex % columns) - 1.5
        let x = targetSize.width * 0.5 + column * squareSize * 0.92
        let y = targetSize.height * 0.34 - row * squareSize * 0.65
        return CGPoint(x: x, y: y)
    }

    private func addPolygonBody(
        fromWorldVertices vertices: [CGPoint],
        preserveTopology: Bool = false,
        targetMaxVertexCount: Int = 22,
        collisionMaxVertexCount: Int = 14
    ) {
        guard bodies.count < 32 else { return }

        let cleaned = deduplicatedPoints(vertices)
        guard cleaned.count >= 3 else { return }

        let renderSourcePoints: [CGPoint]
        if preserveTopology {
            renderSourcePoints = cleaned
        } else {
            renderSourcePoints = convexHull(points: cleaned)
        }

        guard renderSourcePoints.count >= 3 else { return }
        let maxCount = max(3, targetMaxVertexCount)
        let renderDecimated = decimatePolygonVertices(renderSourcePoints, targetMaxCount: maxCount)
        guard renderDecimated.count >= 3 else { return }

        let area = abs(polygonSignedArea(renderDecimated))
        if area < 180 { return }

        let centroid = polygonCentroid(renderDecimated)
        var localRender = renderDecimated.map { CGPoint(x: $0.x - centroid.x, y: $0.y - centroid.y) }
        if polygonSignedArea(localRender) < 0 {
            localRender.reverse()
        }

        let radius = localRender.map { hypot($0.x, $0.y) }.max() ?? 0
        if radius < 9 { return }

        let collisionSourceWorld = isPolygonConvex(renderDecimated)
            ? renderDecimated
            : convexHull(points: renderDecimated)
        guard collisionSourceWorld.count >= 3 else { return }
        var collisionLocalRaw = collisionSourceWorld.map { CGPoint(x: $0.x - centroid.x, y: $0.y - centroid.y) }
        if polygonSignedArea(collisionLocalRaw) < 0 {
            collisionLocalRaw.reverse()
        }

        let collisionCap = max(3, collisionMaxVertexCount)
        let collisionBudget = collisionVertexBudget(localCount: collisionLocalRaw.count, cap: collisionCap)
        let collisionLocal: [CGPoint] =
            collisionBudget >= collisionLocalRaw.count
                ? collisionLocalRaw
                : decimatePolygonVertices(collisionLocalRaw, targetMaxCount: collisionBudget)

        var body = makeBody(
            shape: .polygon,
            center: centroid,
            localVertices: localRender,
            collisionVertices: collisionLocal,
            collisionVertexCap: collisionCap
        )
        body.center = clampedBodyCenter(body.center, for: body)
        body.velocity = .zero
        body.angularVelocity = 0
        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
        syncBodyDrawStates()
        syncWeldPreviewPoints()
    }

    private func rebuildCollisionMeshes() {
        guard !bodies.isEmpty else { return }
        var changed = false

        for index in bodies.indices {
            guard bodies[index].shape == .polygon else { continue }
            guard let local = bodies[index].localVertices, local.count >= 3 else { continue }
            let collisionSource = isPolygonConvex(local) ? local : convexHull(points: local)
            guard collisionSource.count >= 3 else { continue }
            let cap = max(3, bodies[index].collisionVertexCap > 0 ? bodies[index].collisionVertexCap : min(collisionSource.count, 18))
            let budget = collisionVertexBudget(localCount: collisionSource.count, cap: cap)
            var reduced = budget >= collisionSource.count ? collisionSource : decimatePolygonVertices(collisionSource, targetMaxCount: budget)
            if polygonSignedArea(reduced) < 0 {
                reduced.reverse()
            }
            bodies[index].collisionVertices = reduced
            changed = true
        }

        if changed {
            syncBodyDrawStates()
        }
    }

    private func collisionVertexBudget(localCount: Int, cap: Int) -> Int {
        let capped = max(3, min(localCount, cap))
        // Keep low-vertex primitives exact to avoid rectangle/corner loss.
        if capped <= 8 {
            return capped
        }
        let minimum = max(3, min(capped, Int(CGFloat(capped) * 0.35)))
        let value = CGFloat(minimum) + CGFloat(capped - minimum) * collisionQuality
        return max(3, min(localCount, Int(value.rounded())))
    }

    private func rectanglePoints(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        if (maxX - minX) < 10 || (maxY - minY) < 10 { return [] }
        return [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]
    }

    private func ellipsePoints(from start: CGPoint, to end: CGPoint, segmentCount: Int) -> [CGPoint] {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        let width = maxX - minX
        let height = maxY - minY
        if width < 10 || height < 10 { return [] }

        let center = CGPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
        let rx = width * 0.5
        let ry = height * 0.5
        let count = max(12, segmentCount)
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let t = CGFloat(index) / CGFloat(count) * .pi * 2
            points.append(
                CGPoint(
                    x: center.x + cos(t) * rx,
                    y: center.y + sin(t) * ry
                )
            )
        }
        return points
    }

    private func bodySamplePoints(for body: Body) -> [CGPoint] {
        switch body.shape {
        case .cube:
            let half = squareSize * 0.5
            let positions: [CGFloat] = [-0.65, 0, 0.65]
            var points: [CGPoint] = []
            points.reserveCapacity(9)
            for x in positions {
                for y in positions {
                    points.append(CGPoint(x: x * half, y: y * half))
                }
            }
            return points
        case .circle:
            let r = circleRadius
            let p = r * 0.78
            let d = r * 0.56
            return [
                .zero,
                CGPoint(x: p, y: 0),
                CGPoint(x: -p, y: 0),
                CGPoint(x: 0, y: p),
                CGPoint(x: 0, y: -p),
                CGPoint(x: d, y: d),
                CGPoint(x: -d, y: d),
                CGPoint(x: d, y: -d),
                CGPoint(x: -d, y: -d)
            ]
        case .polygon:
            guard let vertices = body.localVertices ?? body.collisionVertices, vertices.count > 2 else { return [.zero] }
            var points: [CGPoint] = [.zero]

            guard let first = vertices.first else { return points }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for v in vertices.dropFirst() {
                minX = min(minX, v.x)
                maxX = max(maxX, v.x)
                minY = min(minY, v.y)
                maxY = max(maxY, v.y)
            }
            let spanX = max(1, maxX - minX)
            let spanY = max(1, maxY - minY)
            let spacing = max(8, squareSize * 0.28)
            let cols = max(2, min(14, Int(ceil(spanX / spacing))))
            let rows = max(2, min(14, Int(ceil(spanY / spacing))))

            for ix in 0...cols {
                let tx = CGFloat(ix) / CGFloat(max(1, cols))
                let x = minX + spanX * tx
                for iy in 0...rows {
                    let ty = CGFloat(iy) / CGFloat(max(1, rows))
                    let y = minY + spanY * ty
                    let point = CGPoint(x: x, y: y)
                    if pointInPolygon(point, vertices: vertices) {
                        points.append(point)
                    }
                }
            }

            if points.count < 9 {
                let step = max(1, vertices.count / 8)
                var index = 0
                while index < vertices.count {
                    let vertex = vertices[index]
                    points.append(CGPoint(x: vertex.x * 0.75, y: vertex.y * 0.75))
                    let next = vertices[(index + step) % vertices.count]
                    points.append(
                        CGPoint(
                            x: (vertex.x + next.x) * 0.3,
                            y: (vertex.y + next.y) * 0.3
                        )
                    )
                    index += step
                }
            }

            if points.count > 52 {
                let strideStep = max(1, points.count / 52)
                var reduced: [CGPoint] = []
                reduced.reserveCapacity(52)
                for idx in stride(from: 0, to: points.count, by: strideStep) {
                    reduced.append(points[idx])
                }
                points = reduced
            }
            return points
        }
    }

    private func bodyCharacteristicSize(for body: Body) -> CGFloat {
        switch body.shape {
        case .cube: return squareSize
        case .circle: return circleRadius * 2
        case .polygon:
            guard let vertices = body.localVertices, !vertices.isEmpty else { return squareSize }
            let bounds = polygonBounds(vertices)
            return max(10, max(bounds.width, bounds.height))
        }
    }

    private func bodyBottomExtent(for body: Body) -> CGFloat {
        switch body.shape {
        case .cube: return squareSize * 0.5
        case .circle: return circleRadius
        case .polygon:
            guard let vertices = body.localVertices, !vertices.isEmpty else { return squareSize * 0.5 }
            return max(1, vertices.map(\.y).max() ?? (squareSize * 0.5))
        }
    }

    private func bodyMass(for body: Body) -> CGFloat {
        let base = max(squareMass, 0.0001)
        switch body.shape {
        case .cube:
            return base
        case .circle:
            // Circle with same diameter has ~78.5% area of a square.
            return base * 0.78539816
        case .polygon:
            let area = max(abs(polygonSignedArea(body.localVertices ?? [])), 1)
            let squareArea = max(squareSize * squareSize, 1)
            let ratio = min(20.0, max(0.12, area / squareArea))
            return base * ratio
        }
    }

    private func glassStrengthScale(for body: Body) -> CGFloat {
        let massScale = sqrt(max(0.12, bodyMass(for: body) / max(squareMass, 0.0001)))
        let sizeScale = sqrt(max(0.12, bodyCharacteristicSize(for: body) / max(squareSize, 1)))
        let scale = 0.58 + massScale * 0.56 + sizeScale * 0.36
        return min(6.0, max(1.0, scale))
    }

    private func bodyInertia(for body: Body) -> CGFloat {
        let base = max(squareInertia, 0.0001)
        let massRatio = bodyMass(for: body) / max(squareMass, 0.0001)
        switch body.shape {
        case .cube:
            return base * massRatio
        case .circle:
            // Disk inertia (1/2 mr^2) relative to square plate (1/6 ma^2) ~= 0.75 for equal mass.
            return base * massRatio * 0.75
        case .polygon:
            let mass = bodyMass(for: body)
            if
                let vertices = body.localVertices,
                vertices.count >= 3,
                let polygonInertia = polygonMomentOfInertia(vertices: vertices, mass: mass)
            {
                return max(20, polygonInertia)
            }
            return base * massRatio
        }
    }

    private func boundingRadius(for body: Body) -> CGFloat {
        switch body.shape {
        case .cube:
            return squareSize * 0.5 * 1.41421356
        case .circle:
            return circleRadius
        case .polygon:
            guard let vertices = body.localVertices, !vertices.isEmpty else {
                return squareSize * 0.5 * 1.41421356
            }
            return max(1, vertices.map { hypot($0.x, $0.y) }.max() ?? 1)
        }
    }

    private func boundingRadius(for shape: BodyShape) -> CGFloat {
        switch shape {
        case .cube: return squareSize * 0.5 * 1.41421356
        case .circle: return circleRadius
        case .polygon: return squareSize * 0.5 * 1.41421356
        }
    }

    private func bodyIndex(forID id: UUID) -> Int? {
        if let cached = bodyIndexByID[id], bodies.indices.contains(cached), bodies[cached].id == id {
            return cached
        }
        guard let found = bodies.firstIndex(where: { $0.id == id }) else { return nil }
        bodyIndexByID[id] = found
        return found
    }

    private func bodyLocalVertices(for body: Body, forCollision: Bool = false) -> [CGPoint]? {
        switch body.shape {
        case .cube:
            let half = squareSize * 0.5
            return [
                CGPoint(x: -half, y: -half),
                CGPoint(x: half, y: -half),
                CGPoint(x: half, y: half),
                CGPoint(x: -half, y: half)
            ]
        case .circle:
            return nil
        case .polygon:
            if forCollision {
                return body.collisionVertices ?? body.localVertices
            }
            return body.localVertices
        }
    }

    private func bodyWorldVertices(for body: Body, forCollision: Bool = false) -> [CGPoint]? {
        guard let localVertices = bodyLocalVertices(for: body, forCollision: forCollision), localVertices.count > 2 else { return nil }
        return localVertices.map { worldPoint(fromLocal: $0, in: body) }
    }

    private func closestPointOnSegment(point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint) -> CGPoint {
        let ab = CGVector(dx: segmentEnd.x - segmentStart.x, dy: segmentEnd.y - segmentStart.y)
        let ap = CGVector(dx: point.x - segmentStart.x, dy: point.y - segmentStart.y)
        let lengthSq = ab.dx * ab.dx + ab.dy * ab.dy
        if lengthSq <= 0.000001 { return segmentStart }
        let t = max(0, min(1, (ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq))
        return CGPoint(
            x: segmentStart.x + ab.dx * t,
            y: segmentStart.y + ab.dy * t
        )
    }

    private func pointInPolygon(_ point: CGPoint, vertices: [CGPoint]) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1

        for i in 0..<vertices.count {
            let a = vertices[i]
            let b = vertices[j]
            let dy = b.y - a.y
            let safeDy: CGFloat
            if abs(dy) < 0.000001 {
                safeDy = dy >= 0 ? 0.000001 : -0.000001
            } else {
                safeDy = dy
            }
            if
                ((a.y > point.y) != (b.y > point.y)) &&
                (point.x < (b.x - a.x) * (point.y - a.y) / safeDy + a.x)
            {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func deduplicatedPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            if let last = result.last {
                let dx = point.x - last.x
                let dy = point.y - last.y
                if dx * dx + dy * dy < 1 { continue }
            }
            result.append(point)
        }
        return result
    }

    private func decimatePolygonVertices(_ points: [CGPoint], targetMaxCount: Int) -> [CGPoint] {
        guard points.count > targetMaxCount, targetMaxCount >= 3 else { return points }
        let step = CGFloat(points.count) / CGFloat(targetMaxCount)
        var sampled: [CGPoint] = []
        sampled.reserveCapacity(targetMaxCount)
        for index in 0..<targetMaxCount {
            let source = Int((CGFloat(index) * step).rounded(.down)) % points.count
            sampled.append(points[source])
        }
        return sampled
    }

    private func convexHull(points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }

        if sorted.count < 3 { return sorted }

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        let hull = lower + upper
        return hull.count >= 3 ? hull : sorted
    }

    private func isPolygonConvex(_ vertices: [CGPoint]) -> Bool {
        guard vertices.count >= 4 else { return true }
        var sign: CGFloat = 0

        for index in vertices.indices {
            let a = vertices[index]
            let b = vertices[(index + 1) % vertices.count]
            let c = vertices[(index + 2) % vertices.count]
            let crossValue = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(crossValue) < 0.00001 { continue }
            if sign == 0 {
                sign = crossValue > 0 ? 1 : -1
            } else if (crossValue > 0 ? 1 : -1) != sign {
                return false
            }
        }

        return true
    }

    private func polygonSignedArea(_ vertices: [CGPoint]) -> CGFloat {
        guard vertices.count >= 3 else { return 0 }
        var area: CGFloat = 0
        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            area += vertices[index].x * vertices[nextIndex].y
            area -= vertices[nextIndex].x * vertices[index].y
        }
        return area * 0.5
    }

    private func polygonCentroid(_ vertices: [CGPoint]) -> CGPoint {
        guard vertices.count >= 3 else {
            let average = vertices.reduce(CGPoint.zero) { partial, value in
                CGPoint(x: partial.x + value.x, y: partial.y + value.y)
            }
            let divisor = CGFloat(max(vertices.count, 1))
            return CGPoint(x: average.x / divisor, y: average.y / divisor)
        }

        let area = polygonSignedArea(vertices)
        if abs(area) < 0.000001 {
            let average = vertices.reduce(CGPoint.zero) { partial, value in
                CGPoint(x: partial.x + value.x, y: partial.y + value.y)
            }
            let divisor = CGFloat(vertices.count)
            return CGPoint(x: average.x / divisor, y: average.y / divisor)
        }

        var cx: CGFloat = 0
        var cy: CGFloat = 0
        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            let crossValue = vertices[index].x * vertices[nextIndex].y - vertices[nextIndex].x * vertices[index].y
            cx += (vertices[index].x + vertices[nextIndex].x) * crossValue
            cy += (vertices[index].y + vertices[nextIndex].y) * crossValue
        }
        let factor = 1 / (6 * area)
        return CGPoint(x: cx * factor, y: cy * factor)
    }

    private func polygonBounds(_ vertices: [CGPoint]) -> CGSize {
        guard let first = vertices.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in vertices.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGSize(width: maxX - minX, height: maxY - minY)
    }

    private func polygonMomentOfInertia(vertices: [CGPoint], mass: CGFloat) -> CGFloat? {
        guard vertices.count >= 3 else { return nil }
        let area = polygonSignedArea(vertices)
        if abs(area) < 0.000001 { return nil }
        let density = mass / abs(area)
        var numerator: CGFloat = 0

        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            let a = vertices[index]
            let b = vertices[nextIndex]
            let crossValue = abs(a.x * b.y - b.x * a.y)
            let xx = a.x * a.x + a.x * b.x + b.x * b.x
            let yy = a.y * a.y + a.y * b.y + b.y * b.y
            numerator += crossValue * (xx + yy)
        }

        return max(1, density * numerator / 12)
    }

    private func localPoint(fromWorld point: CGPoint, in body: Body) -> CGPoint {
        let dx = point.x - body.center.x
        let dy = point.y - body.center.y
        let cosA = cos(-body.angle)
        let sinA = sin(-body.angle)
        return CGPoint(
            x: dx * cosA - dy * sinA,
            y: dx * sinA + dy * cosA
        )
    }

    private func worldPoint(fromLocal point: CGPoint, in body: Body) -> CGPoint {
        rotate(point: point, by: body.angle, around: body.center)
    }

    private func rotateVector(_ vector: CGVector, by angle: CGFloat) -> CGVector {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGVector(
            dx: vector.dx * cosA - vector.dy * sinA,
            dy: vector.dx * sinA + vector.dy * cosA
        )
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var value = angle.truncatingRemainder(dividingBy: .pi * 2)
        if value > .pi {
            value -= .pi * 2
        } else if value < -.pi {
            value += .pi * 2
        }
        return value
    }
}

struct MouseTrackingLayer: NSViewRepresentable {
    var onMove: (CGPoint?, TimeInterval, Bool) -> Void
    var onLeftDown: (CGPoint, TimeInterval, Bool) -> Void
    var onLeftUp: (CGPoint, TimeInterval, Bool) -> Void
    var onRightDown: (CGPoint, TimeInterval, Bool) -> Void
    var onRightUp: (CGPoint, TimeInterval, Bool) -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMove = onMove
        view.onLeftDown = onLeftDown
        view.onLeftUp = onLeftUp
        view.onRightDown = onRightDown
        view.onRightUp = onRightUp
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onMove = onMove
        nsView.onLeftDown = onLeftDown
        nsView.onLeftUp = onLeftUp
        nsView.onRightDown = onRightDown
        nsView.onRightUp = onRightUp
    }
}

final class MouseTrackingNSView: NSView {
    var onMove: ((CGPoint?, TimeInterval, Bool) -> Void)?
    var onLeftDown: ((CGPoint, TimeInterval, Bool) -> Void)?
    var onLeftUp: ((CGPoint, TimeInterval, Bool) -> Void)?
    var onRightDown: ((CGPoint, TimeInterval, Bool) -> Void)?
    var onRightUp: ((CGPoint, TimeInterval, Bool) -> Void)?

    private var trackingAreaRef: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .inVisibleRect,
            .mouseMoved,
            .mouseEnteredAndExited
        ]

        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil), event.timestamp, event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil), event.timestamp, event.modifierFlags.contains(.shift))
    }

    override func rightMouseDragged(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil), event.timestamp, event.modifierFlags.contains(.shift))
    }

    override func mouseEntered(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil), event.timestamp, event.modifierFlags.contains(.shift))
    }

    override func mouseExited(with event: NSEvent) {
        onMove?(nil, event.timestamp, event.modifierFlags.contains(.shift))
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        onMove?(location, event.timestamp, shift)
        onLeftDown?(location, event.timestamp, shift)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        onMove?(location, event.timestamp, shift)
        onLeftUp?(location, event.timestamp, shift)
    }

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        onMove?(location, event.timestamp, shift)
        onRightDown?(location, event.timestamp, shift)
    }

    override func rightMouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        onMove?(location, event.timestamp, shift)
        onRightUp?(location, event.timestamp, shift)
    }
}

final class KeyboardMonitor {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onModifierChanged: ((NSEvent) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            if event.type == .keyDown {
                if self?.onKeyDown?(event) == true {
                    return nil
                }
            } else if event.type == .flagsChanged {
                self?.onModifierChanged?(event)
            }
            return event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        stop()
    }
}
