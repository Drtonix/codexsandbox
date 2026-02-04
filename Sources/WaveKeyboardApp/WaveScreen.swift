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
                TimelineView(.animation(minimumInterval: 1.0 / 50.0, paused: false)) { _ in
                    Canvas(rendersAsynchronously: true) { context, size in
                        let samples = wave.samples
                        let bodies = wave.bodyDrawStates
                        let waterChunks = wave.waterChunkDrawStates
                        guard samples.count > 1 else { return }

                        let centerY = size.height / 2
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
                            let displacement = left + (right - left) * fraction
                            let y = centerY + displacement
                            path.addLine(to: CGPoint(x: x, y: y))
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

                        for body in bodies {
                            var bodyContext = context
                            bodyContext.translateBy(x: body.center.x, y: body.center.y)
                            bodyContext.rotate(by: .radians(body.angle))
                            switch body.shape {
                            case .cube:
                                bodyContext.stroke(
                                    squarePath,
                                    with: .color(wave.accentColor),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                            case .circle:
                                bodyContext.stroke(
                                    circlePath,
                                    with: .color(wave.accentColor),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                            case .polygon:
                                if let vertices = body.localVertices, vertices.count > 1 {
                                    var polygonPath = Path()
                                    polygonPath.move(to: vertices[0])
                                    for vertex in vertices.dropFirst() {
                                        polygonPath.addLine(to: vertex)
                                    }
                                    polygonPath.closeSubpath()
                                    bodyContext.stroke(
                                        polygonPath,
                                        with: .color(wave.accentColor),
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                    )
                                }
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
    private let collapsedSize = CGSize(width: 142, height: 36)
    private let handleHeight: CGFloat = 36
    private let margin: CGFloat = 10

    private func tr(_ ru: String, _ en: String) -> String {
        wave.language == .ru ? ru : en
    }

    private var currentSize: CGSize {
        isCollapsed ? collapsedSize : expandedSize
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
        .frame(width: collapsedSize.width, height: collapsedSize.height)
        .background(wave.panelBackgroundColor)
        .foregroundStyle(wave.accentColor)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(wave.accentColor.opacity(0.2), lineWidth: 1))
        .gesture(
            dragGesture(for: collapsedSize) {
                center = recentered(center, from: collapsedSize, to: expandedSize, anchorX: 1, anchorY: 0)
                isCollapsed = false
                center = clamped(center, for: expandedSize)
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
                    center = recentered(center, from: expandedSize, to: collapsedSize, anchorX: 1, anchorY: 0)
                    isCollapsed = true
                    center = clamped(center, for: collapsedSize)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: expandedSize.width, height: handleHeight)
            .background(wave.panelBackgroundColor)
            .foregroundStyle(wave.accentColor.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(wave.accentColor.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(for: expandedSize))

            WaveControlsPanel(wave: wave, height: expandedSize.height - handleHeight - 6)
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

    private func tr(_ ru: String, _ en: String) -> String {
        wave.language == .ru ? ru : en
    }

    private func drawingToolLabel(_ tool: WaveModel.DrawingTool) -> String {
        switch tool {
        case .none:
            return tr("Нет", "Off")
        case .quadrilateral:
            return tr("4-угольник", "Quad")
        case .ellipse:
            return tr("Окружность", "Circle")
        case .freeform:
            return tr("Фигура", "Shape")
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("Настройка Волны", "Wave Tuning"))
                        .font(.headline)
                        .foregroundStyle(wave.accentColor)
                    Spacer()
                    Text("FPS \(Int(wave.fps.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(wave.accentColor.opacity(0.7))
                    Button(tr("Сброс", "Reset")) {
                        wave.resetTuning()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(wave.accentColor)
                    .foregroundStyle(wave.backgroundColor)
                }

                HStack(spacing: 8) {
                    Button(tr("Сброс Сцены", "Reset Scene")) {
                        wave.resetScene()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(wave.accentColor)
                    .foregroundStyle(wave.accentColor)

                    Button(tr("Куб", "Cube")) {
                        wave.addCube()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(wave.accentColor)
                    .foregroundStyle(wave.backgroundColor)

                    Button(tr("Шар", "Ball")) {
                        wave.addCircle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(wave.accentColor)
                    .foregroundStyle(wave.accentColor)

                    Button(
                        wave.weldToolEnabled
                            ? tr("Сварка: Вкл", "Weld: On")
                            : tr("Сварка", "Weld")
                    ) {
                        wave.toggleWeldTool()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(wave.accentColor)
                    .foregroundStyle(wave.accentColor)
                }

                HStack {
                    Text(tr("Рисование", "Drawing"))
                        .font(.caption2)
                        .foregroundStyle(wave.accentColor.opacity(0.85))
                    Spacer()
                    Text(tr("Shift: Ровно", "Shift: Constrain"))
                        .font(.caption2)
                        .foregroundStyle(wave.accentColor.opacity(0.6))
                }

                Picker("", selection: $wave.drawingTool) {
                    Text(drawingToolLabel(.none)).tag(WaveModel.DrawingTool.none)
                    Text(drawingToolLabel(.quadrilateral)).tag(WaveModel.DrawingTool.quadrilateral)
                    Text(drawingToolLabel(.ellipse)).tag(WaveModel.DrawingTool.ellipse)
                    Text(drawingToolLabel(.freeform)).tag(WaveModel.DrawingTool.freeform)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button(
                    wave.isTimeFrozen
                        ? tr("Продолжить Время", "Resume Time")
                        : tr("Заморозить Время", "Freeze Time")
                ) {
                    wave.toggleTimeFrozen()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(wave.accentColor)
                .foregroundStyle(wave.accentColor)

                Picker(tr("Язык", "Language"), selection: $wave.language) {
                    Text("RU").tag(AppLanguage.ru)
                    Text("EN").tag(AppLanguage.en)
                }
                .pickerStyle(.segmented)

                Button(tr("Сменить Цвета", "Toggle Colors")) {
                    wave.toggleTheme()
                }
                .buttonStyle(.bordered)
                .tint(wave.accentColor)
                .foregroundStyle(wave.accentColor)

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
                    PanelSection(title: tr("Объекты: Столкновения", "Objects: Collisions"), color: wave.accentColor)
                    Toggle(tr("Столкновения Объектов", "Object Collisions"), isOn: $wave.cubeCollisionEnabled)
                        .tint(wave.accentColor)
                        .foregroundStyle(wave.accentColor)
                        .font(.caption2)
                    ControlSlider(tr("Упругость Столкновений", "Collision Restitution"), value: $wave.collisionRestitution, range: 0...0.95, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Трение Столкновений", "Collision Friction"), value: $wave.collisionFriction, range: 0...1.2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Сила Импульса", "Impulse Scale"), value: $wave.collisionImpulseScale, range: 0...2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Передача Вращения", "Angular Transfer"), value: $wave.collisionAngularTransfer, range: 0...2, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Коррекция Проникновения", "Penetration Correction"), value: $wave.collisionPositionCorrection, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Допуск Проникновения", "Penetration Slop"), value: $wave.collisionSlop, range: 0...6, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Итерации Решателя", "Solver Iterations"), value: $wave.collisionIterations, range: 1...10, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Качество Коллизий", "Collision Quality"), value: $wave.collisionQuality, range: 0.2...1.0, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Сварка Объектов", "Object Welding"), color: wave.accentColor)
                    Toggle(tr("Режим Сварки", "Weld Mode"), isOn: $wave.weldToolEnabled)
                        .tint(wave.accentColor)
                        .foregroundStyle(wave.accentColor)
                        .font(.caption2)
                    Button(tr("Очистить Сварки", "Clear Welds")) {
                        wave.clearWelds()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(wave.accentColor)
                    .foregroundStyle(wave.accentColor)
                    ControlSlider(tr("Жесткость Сварки", "Weld Stiffness"), value: $wave.weldLinearStiffness, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Демпфер Сварки", "Weld Damping"), value: $wave.weldLinearDamping, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Жесткость Поворота", "Weld Angular Stiff"), value: $wave.weldAngularStiffness, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Демпфер Поворота", "Weld Angular Damp"), value: $wave.weldAngularDamping, range: 0...1, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Итерации Сварки", "Weld Iterations"), value: $wave.weldIterations, range: 1...10, step: 1, format: "%.0f", accentColor: wave.accentColor)
                }

                Group {
                    PanelSection(title: tr("Ограничения Объектов", "Object Limits"), color: wave.accentColor)
                    ControlSlider(tr("Скорость Объекта X", "Object Speed X"), value: $wave.squareVelocityLimitX, range: 0.5...25, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Скорость Объекта Y", "Object Speed Y"), value: $wave.squareVelocityLimitY, range: 0.5...25, step: 0.1, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Угловая Скорость Объекта", "Object Angular Speed"), value: $wave.squareAngularLimit, range: 0.01...1, step: 0.005, format: "%.3f", accentColor: wave.accentColor)
                    ControlSlider(tr("Инерция Броска", "Throw Inertia"), value: $wave.dragThrowLinearInertia, range: 0...4, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Инерция Броска Вращение", "Throw Angular Inertia"), value: $wave.dragThrowAngularInertia, range: 0...4, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Лимит Броска Множитель", "Throw Clamp Scale"), value: $wave.dragThrowClampScale, range: 0.5...4, step: 0.05, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Шаг Поворота Клавиш", "Keyboard Rotate Step"), value: $wave.keyboardRotateStepDegrees, range: 0.5...45, step: 0.5, format: "%.1f", accentColor: wave.accentColor)
                    ControlSlider(tr("Шаг Поворота Shift", "Shift Rotate Step"), value: $wave.keyboardRotateSnapDegrees, range: 1...90, step: 1, format: "%.0f", accentColor: wave.accentColor)
                    ControlSlider(tr("Отскок Стен X", "Wall Bounce X"), value: $wave.wallBounceX, range: 0...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Отскок Потолок", "Wall Bounce Top"), value: $wave.wallBounceTop, range: 0...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                    ControlSlider(tr("Отскок Пол", "Wall Bounce Bottom"), value: $wave.wallBounceBottom, range: 0...0.9, step: 0.01, format: "%.2f", accentColor: wave.accentColor)
                }
            }
            .padding(12)
        }
        .frame(width: 360, height: height)
        .background(wave.panelBackgroundColor)
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
            .textCase(.uppercase)
            .padding(.top, 6)
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
        case freeform

        var id: String { rawValue }
    }

    enum BodyShape {
        case cube
        case circle
        case polygon
    }

    struct BodyDrawState: Identifiable {
        let id: UUID
        let shape: BodyShape
        let center: CGPoint
        let angle: CGFloat
        let localVertices: [CGPoint]?
    }

    struct WaterChunkDrawState: Identifiable {
        let id: UUID
        let center: CGPoint
        let radius: CGFloat
        let opacity: CGFloat
        let velocity: CGVector
        let tailLength: CGFloat
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
    }

    private struct WaterChunk {
        let id: UUID
        var center: CGPoint
        var velocity: CGVector
        var radius: CGFloat
        var age: CGFloat
        var life: CGFloat
    }

    private struct CollisionManifold {
        var normal: CGVector
        var penetration: CGFloat
        var contactPoint: CGPoint
    }

    private struct WeldConstraint {
        var firstID: UUID
        var secondID: UUID
        var firstLocalAnchor: CGPoint
        var secondLocalAnchor: CGPoint
        var restAngle: CGFloat
    }

    private struct CollisionPair: Hashable {
        let first: Int
        let second: Int
    }

    private struct SpatialCell: Hashable {
        let x: Int
        let y: Int
    }

    private(set) var samples: [CGFloat]
    private(set) var bodyDrawStates: [BodyDrawState]
    private(set) var weldCursorPoint: CGPoint?
    private(set) var weldPendingPoint: CGPoint?
    private(set) var drawingPreviewPoints: [CGPoint] = []
    private(set) var drawingPreviewClosed: Bool = false
    private(set) var waterChunkDrawStates: [WaterChunkDrawState] = []
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
    @Published var gravityForce: CGFloat = 0.4
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
    @Published var squareVelocityLimitX: CGFloat = 6.8
    @Published var squareVelocityLimitY: CGFloat = 7.8
    @Published var squareAngularLimit: CGFloat = 0.095
    @Published var dragThrowLinearInertia: CGFloat = 1.55
    @Published var dragThrowAngularInertia: CGFloat = 1.25
    @Published var dragThrowClampScale: CGFloat = 1.8
    @Published var keyboardRotateStepDegrees: CGFloat = 6.3
    @Published var keyboardRotateSnapDegrees: CGFloat = 15
    @Published var wallBounceX: CGFloat = 0.14
    @Published var wallBounceTop: CGFloat = 0.1
    @Published var wallBounceBottom: CGFloat = 0.09
    @Published var cubeCollisionEnabled: Bool = true
    @Published var collisionRestitution: CGFloat = 0.18
    @Published var collisionFriction: CGFloat = 0.42
    @Published var collisionImpulseScale: CGFloat = 1.0
    @Published var collisionAngularTransfer: CGFloat = 1.0
    @Published var collisionPositionCorrection: CGFloat = 0.55
    @Published var collisionSlop: CGFloat = 0.35
    @Published var collisionIterations: CGFloat = 2
    @Published var collisionQuality: CGFloat = 0.55 {
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
    @Published var isTimeFrozen: Bool = false
    @Published private(set) var fps: CGFloat = 0
    @Published var drawingTool: DrawingTool = .none {
        didSet {
            if drawingTool != .none {
                weldToolEnabled = false
            }
            clearDrawingState()
        }
    }
    @Published var weldToolEnabled: Bool = false {
        didSet {
            if weldToolEnabled {
                drawingTool = .none
            } else {
                pendingWeldBodyID = nil
                pendingWeldAnchorLocal = nil
                weldPendingPoint = nil
                weldCursorPoint = nil
            }
        }
    }
    @Published var weldLinearStiffness: CGFloat = 0.74
    @Published var weldLinearDamping: CGFloat = 0.24
    @Published var weldAngularStiffness: CGFloat = 0.58
    @Published var weldAngularDamping: CGFloat = 0.26
    @Published var weldIterations: CGFloat = 2

    var accentColor: Color {
        theme == .dark ? .white : .black
    }

    var backgroundColor: Color {
        theme == .dark ? .black : .white
    }

    var panelBackgroundColor: Color {
        theme == .dark ? Color.black.opacity(0.72) : Color.white.opacity(0.84)
    }

    let squareSize: CGFloat = 56
    let circleRadius: CGFloat = 28

    private let pointCount = 320
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
    private var weldConstraints: [WeldConstraint] = []
    private var pendingWeldBodyID: UUID?
    private var pendingWeldAnchorLocal: CGPoint?
    private var bodyIndexByID: [UUID: Int] = [:]
    private var spawnedBodyHistory: [UUID] = []
    private var bodySplashCooldown: [UUID: CGFloat] = [:]
    private var calmSkipToggle = false
    private var lastTickTimestamp: CFAbsoluteTime?
    private var smoothedFPS: CGFloat = 0
    private var waterChunks: [WaterChunk] = []
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
            collisionVertexCap: 0
        )
        self.bodies = [firstBody]
        self.bodyDrawStates = [
            BodyDrawState(
                id: firstBody.id,
                shape: firstBody.shape,
                center: firstBody.center,
                angle: firstBody.angle,
                localVertices: nil
            )
        ]
        self.weldCursorPoint = nil
        self.weldPendingPoint = nil
        self.language = Self.systemLanguage()
        self.theme = .dark
    }

    func start() {
        guard timer == nil else { return }

        let scheduledTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 50.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        timer = scheduledTimer
        RunLoop.main.add(scheduledTimer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTickTimestamp = nil
        smoothedFPS = 0
        fps = 0
        wasShiftPressed = false
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
        gravityForce = 0.4
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
        squareVelocityLimitX = 6.8
        squareVelocityLimitY = 7.8
        squareAngularLimit = 0.095
        dragThrowLinearInertia = 1.55
        dragThrowAngularInertia = 1.25
        dragThrowClampScale = 1.8
        keyboardRotateStepDegrees = 6.3
        keyboardRotateSnapDegrees = 15
        wallBounceX = 0.14
        wallBounceTop = 0.1
        wallBounceBottom = 0.09
        cubeCollisionEnabled = true
        collisionRestitution = 0.18
        collisionFriction = 0.42
        collisionImpulseScale = 1.0
        collisionAngularTransfer = 1.0
        collisionPositionCorrection = 0.55
        collisionSlop = 0.35
        collisionIterations = 2
        collisionQuality = 0.55
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
        weldLinearStiffness = 0.74
        weldLinearDamping = 0.24
        weldAngularStiffness = 0.58
        weldAngularDamping = 0.26
        weldIterations = 2
    }

    func toggleTheme() {
        theme = (theme == .dark) ? .light : .dark
    }

    func toggleTimeFrozen() {
        isTimeFrozen.toggle()
    }

    func handleKeyDown(_ event: NSEvent) {
        let isSpace = event.keyCode == 49 || event.charactersIgnoringModifiers == " "
        if isSpace {
            toggleTimeFrozen()
            return
        }

        let raw = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shiftPressed = event.modifierFlags.contains(.shift)
        let isUndoSpawn = event.keyCode == 6 || raw == "z"
        if isUndoSpawn {
            undoLastSpawnedBody()
            return
        }

        let rotateLeft = event.keyCode == 0 || raw == "a"
        if rotateLeft {
            rotateObjectFromKeyboard(clockwise: false, snapped: shiftPressed)
            return
        }

        let rotateRight = event.keyCode == 2 || raw == "d"
        if rotateRight {
            rotateObjectFromKeyboard(clockwise: true, snapped: shiftPressed)
            return
        }

        registerKeyPress()
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

    func toggleWeldTool() {
        weldToolEnabled.toggle()
        if !weldToolEnabled {
            pendingWeldBodyID = nil
            pendingWeldAnchorLocal = nil
            weldPendingPoint = nil
            weldCursorPoint = nil
        }
    }

    func clearWelds() {
        weldConstraints.removeAll(keepingCapacity: true)
        pendingWeldBodyID = nil
        pendingWeldAnchorLocal = nil
        weldPendingPoint = nil
        weldCursorPoint = nil
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

        if bodies.isEmpty {
            bodies = [makeBody(shape: .cube, center: defaultBodyCenter(forIndex: 0, in: size))]
        } else if oldSize.width > 1, oldSize.height > 1 {
            for index in bodies.indices {
                let xRatio = bodies[index].center.x / oldSize.width
                let yRatio = bodies[index].center.y / oldSize.height
                bodies[index].center = CGPoint(x: xRatio * size.width, y: yRatio * size.height)
            }
        } else {
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
        bodySplashCooldown.removeAll(keepingCapacity: true)
        wasShiftPressed = false

        draggingBodyIndex = nil
        dragOffset = .zero
        lastDragCenter = nil
        lastDragTimestamp = nil
        weldConstraints.removeAll(keepingCapacity: true)
        pendingWeldBodyID = nil
        pendingWeldAnchorLocal = nil
        weldPendingPoint = nil
        weldCursorPoint = nil
        spawnedBodyHistory.removeAll(keepingCapacity: true)
        clearDrawingState()

        let spawn = defaultBodyCenter(forIndex: 0, in: viewportSize)
        bodies = [makeBody(shape: .cube, center: spawn)]
        syncBodyDrawStates()
    }

    func addCube() {
        guard bodies.count < 32 else { return }

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
        body.angle = CGFloat.random(in: -0.18...0.18)
        body.velocity = CGVector(dx: CGFloat.random(in: -0.4...0.4), dy: CGFloat.random(in: -0.2...0.2))
        body.angularVelocity = CGFloat.random(in: -0.03...0.03)

        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
        syncBodyDrawStates()
    }

    func addCircle() {
        guard bodies.count < 32 else { return }

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
        body.velocity = CGVector(dx: CGFloat.random(in: -0.35...0.35), dy: CGFloat.random(in: -0.18...0.18))
        body.angularVelocity = CGFloat.random(in: -0.025...0.025)
        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
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

            bodies.remove(at: removeIndex)

            if let draggingBodyIndex {
                if draggingBodyIndex == removeIndex {
                    self.draggingBodyIndex = nil
                    dragOffset = .zero
                    lastDragCenter = nil
                    lastDragTimestamp = nil
                } else if draggingBodyIndex > removeIndex {
                    self.draggingBodyIndex = draggingBodyIndex - 1
                }
            }

            cleanupWeldState()
            syncBodyDrawStates()
            syncWeldPreviewPoints()
            return
        }
    }

    private func rotateObjectFromKeyboard(clockwise: Bool, snapped: Bool) {
        guard let targetIndex = keyboardRotationTargetIndex(), bodies.indices.contains(targetIndex) else { return }

        let freeStep = max(0.5, keyboardRotateStepDegrees) * .pi / 180
        let snapStep = max(1, keyboardRotateSnapDegrees) * .pi / 180
        let baseStep: CGFloat = snapped ? snapStep : freeStep
        let deltaAngle: CGFloat = clockwise ? baseStep : -baseStep
        applyAngularDelta(deltaAngle, toComponentContaining: targetIndex, zeroAngularVelocity: false)
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

    private func keyboardRotationTargetIndex() -> Int? {
        if let draggingBodyIndex, bodies.indices.contains(draggingBodyIndex) {
            return draggingBodyIndex
        }
        if let cursor = lastPointerLocation, let hovered = bodyIndex(containing: cursor) {
            return hovered
        }
        return bodies.indices.last
    }

    func registerKeyPress() {
        guard !isTimeFrozen else { return }
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
        syncWeldPreviewPoints()

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
            let clamped = clampedBodyCenter(target, for: bodies[draggingBodyIndex])

            var body = bodies[draggingBodyIndex]

            if let lastDragCenter, let lastDragTimestamp {
                let dt = max(CGFloat(timestamp - lastDragTimestamp), 1.0 / 240.0)
                let velocityX = (clamped.x - lastDragCenter.x) / (dt * 60)
                let velocityY = (clamped.y - lastDragCenter.y) / (dt * 60)
                body.velocity.dx = body.velocity.dx * 0.45 + velocityX * 0.55
                body.velocity.dy = body.velocity.dy * 0.45 + velocityY * 0.55
                body.angularVelocity = body.angularVelocity * 0.62 + velocityX * 0.0038
            }

            body.center = clamped
            bodies[draggingBodyIndex] = body
            lastDragCenter = clamped
            lastDragTimestamp = timestamp
            propagateDraggedWeldComponent(from: draggingBodyIndex)

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

        switch button {
        case .left:
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

            if let index = bodyIndex(containing: location) {
                draggingBodyIndex = index
                let center = bodies[index].center
                dragOffset = CGSize(
                    width: center.x - location.x,
                    height: center.y - location.y
                )
                lastDragCenter = center
                lastDragTimestamp = timestamp
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

            updatePointer(at: location, in: size)
            if isTimeFrozen { return }
            registerPointerClick(at: location, in: size)

        case .right:
            if isTimeFrozen { return }
            if weldToolEnabled || drawingTool != .none {
                return
            }
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

        if button == .left, drawingTool != .none {
            endDrawing(at: location, constrained: isShiftPressed)
            pointerX = nil
            pointerStrength = 0
            return
        }

        if button == .left, let index = draggingBodyIndex {
            guard bodies.indices.contains(index) else {
                draggingBodyIndex = nil
                lastDragCenter = nil
                lastDragTimestamp = nil
                return
            }

            var root = bodies[index]
            let target = CGPoint(
                x: location.x + dragOffset.width,
                y: location.y + dragOffset.height
            )
            let clamped = clampedBodyCenter(target, for: root)

            if let lastDragCenter, let lastDragTimestamp {
                let dt = max(CGFloat(timestamp - lastDragTimestamp), 1.0 / 240.0)
                let velocityX = (clamped.x - lastDragCenter.x) / (dt * 60)
                let velocityY = (clamped.y - lastDragCenter.y) / (dt * 60)
                root.velocity.dx = root.velocity.dx * 0.35 + velocityX * 0.65
                root.velocity.dy = root.velocity.dy * 0.35 + velocityY * 0.65
                root.angularVelocity = root.angularVelocity * 0.5 + velocityX * 0.0042 + velocityY * 0.0015
            }

            root.center = clamped
            root.velocity.dx *= max(0, dragThrowLinearInertia)
            root.velocity.dy *= max(0, dragThrowLinearInertia)
            root.angularVelocity *= max(0, dragThrowAngularInertia)
            bodies[index] = root

            propagateDraggedWeldComponent(from: index)

            let weldedIndices = weldedComponentIndices(containing: index)
            let clampScale = max(0.5, dragThrowClampScale)
            let maxVX = squareVelocityLimitX * clampScale
            let maxVY = squareVelocityLimitY * clampScale
            let maxAV = squareAngularLimit * clampScale

            for weldedIndex in weldedIndices where bodies.indices.contains(weldedIndex) {
                bodies[weldedIndex].velocity.dx = max(-maxVX, min(maxVX, bodies[weldedIndex].velocity.dx))
                bodies[weldedIndex].velocity.dy = max(-maxVY, min(maxVY, bodies[weldedIndex].velocity.dy))
                bodies[weldedIndex].angularVelocity = max(-maxAV, min(maxAV, bodies[weldedIndex].angularVelocity))
            }
            draggingBodyIndex = nil
            lastDragCenter = nil
            lastDragTimestamp = nil
            syncBodyDrawStates()
            syncWeldPreviewPoints()
        }
    }

    private func beginDrawing(at point: CGPoint, constrained: Bool) {
        drawingStartPoint = point
        switch drawingTool {
        case .none:
            clearDrawingState()
        case .quadrilateral, .ellipse:
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
                collisionMaxVertexCount: 14
            )
        case .freeform:
            addPolygonBody(
                fromWorldVertices: freeformPoints,
                preserveTopology: false,
                targetMaxVertexCount: 28,
                collisionMaxVertexCount: 12
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

    private func updatePointer(at location: CGPoint?, in size: CGSize) {
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
        updateFPS()
        guard samples.count > 2 else { return }
        guard !isTimeFrozen else { return }

        if shouldSkipCalmFrame() {
            calmSkipToggle.toggle()
            if calmSkipToggle { return }
        } else {
            calmSkipToggle = false
        }

        activity = max(0, activity * 0.996)

        let stiffness = max(0, stiffnessBase + activity * stiffnessActivity)
        let damping = min(max(0, dampingBase - activity * dampingActivity), 0.99999)
        let visc = max(0, viscosity)

        updateBodiesPhysics()
        updateWaterChunks()
        var nextVelocities = velocities
        var nextSamples = samples

        applyPointerPull()

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

        nextSamples[0] = 0
        nextSamples[pointCount - 1] = 0
        nextVelocities[0] = 0
        nextVelocities[pointCount - 1] = 0

        samples = nextSamples
        velocities = nextVelocities
        surfaceSpread = samples.reduce(0) { max($0, abs($1)) }
        syncBodyDrawStates()
        syncWaterChunkDrawStates()
        syncWeldPreviewPoints()
    }

    private func updateFPS() {
        let now = CFAbsoluteTimeGetCurrent()
        defer { lastTickTimestamp = now }
        guard let lastTickTimestamp else { return }
        let dt = now - lastTickTimestamp
        guard dt > 0.0001 else { return }

        let instantFPS = CGFloat(1.0 / dt)
        if smoothedFPS <= 0.1 {
            smoothedFPS = instantFPS
        } else {
            smoothedFPS = smoothedFPS * 0.88 + instantFPS * 0.12
        }
        fps = smoothedFPS
    }

    private func shouldSkipCalmFrame() -> Bool {
        if bodies.count > 7 { return false }
        if weldToolEnabled || drawingTool != .none { return false }
        if !waterChunks.isEmpty { return false }
        return isSceneCalm()
    }

    private func updateWaterChunks() {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
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

    private func applyPointerPull() {
        guard draggingBodyIndex == nil else { return }
        guard !weldToolEnabled else { return }
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

    private func updateBodiesPhysics() {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }

        if bodies.isEmpty {
            bodies = [makeBody(shape: .cube, center: defaultBodyCenter(forIndex: 0, in: viewportSize))]
            return
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

        for index in bodies.indices {
            if draggingBodyIndex == index {
                bodies[index].center = clampedBodyCenter(bodies[index].center, for: bodies[index])
                bodies[index].angle = normalizedAngle(bodies[index].angle)
                continue
            }

            var body = bodies[index]
            let bodyMass = bodyMass(for: body)
            let bodyInertiaValue = bodyInertia(for: body)
            var totalForce = CGVector(dx: 0, dy: gravityForce * bodyMass)
            var totalTorque: CGFloat = 0
            var submergedSamples = 0
            let samplePoints = bodySamplePoints(for: body)
            let sampleWeight: CGFloat = 1.0 / CGFloat(max(1, samplePoints.count))
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
                body.velocity.dx *= 0.992 - immersionRatio * 0.01
                body.velocity.dy *= 0.992 - immersionRatio * 0.012
                body.angularVelocity *= 0.991 - immersionRatio * 0.011
            } else {
                body.velocity.dx *= 0.998
                body.velocity.dy *= 0.9988
                body.angularVelocity *= 0.996
            }

            body.velocity.dx += totalForce.dx / bodyMass
            body.velocity.dy += totalForce.dy / bodyMass
            body.angularVelocity += totalTorque / bodyInertiaValue

            body.velocity.dx = max(-squareVelocityLimitX, min(squareVelocityLimitX, body.velocity.dx))
            body.velocity.dy = max(-squareVelocityLimitY, min(squareVelocityLimitY, body.velocity.dy))
            body.angularVelocity = max(-squareAngularLimit, min(squareAngularLimit, body.angularVelocity))

            body.center.x += body.velocity.dx
            body.center.y += body.velocity.dy
            body.angle = normalizedAngle(body.angle + body.angularVelocity)
            applyWorldBounds(to: &body)

            bodies[index] = body
        }

        cleanupWeldState()
        let weldTopology = weldedTopology()

        if cubeCollisionEnabled, bodies.count > 1 {
            resolveBodyCollisions(groupLookup: weldTopology.lookup)
        }

        resolveWeldConstraints(components: weldTopology.components)

        for index in bodies.indices {
            bodies[index].angle = normalizedAngle(bodies[index].angle)
            bodies[index].velocity.dx = max(-squareVelocityLimitX, min(squareVelocityLimitX, bodies[index].velocity.dx))
            bodies[index].velocity.dy = max(-squareVelocityLimitY, min(squareVelocityLimitY, bodies[index].velocity.dy))
            bodies[index].angularVelocity = max(-squareAngularLimit, min(squareAngularLimit, bodies[index].angularVelocity))
            applyWorldBounds(to: &bodies[index])
        }
    }

    private func resolveBodyCollisions(groupLookup: [UUID: Int]) {
        let iterations = max(1, Int(collisionIterations.rounded()))
        guard bodies.count > 1 else { return }

        for _ in 0..<iterations {
            var hadCollision = false
            let candidatePairs = candidateCollisionPairs()

            for pair in candidatePairs {
                let first = pair.first
                let second = pair.second
                guard bodies.indices.contains(first), bodies.indices.contains(second) else { continue }

                let firstID = bodies[first].id
                let secondID = bodies[second].id
                if
                    let groupA = groupLookup[firstID],
                    let groupB = groupLookup[secondID],
                    groupA == groupB
                {
                    continue
                }

                let dx = bodies[second].center.x - bodies[first].center.x
                let dy = bodies[second].center.y - bodies[first].center.y
                let maxDistance = boundingRadius(for: bodies[first]) + boundingRadius(for: bodies[second]) + max(collisionSlop, 0) + 2
                if dx * dx + dy * dy > maxDistance * maxDistance {
                    continue
                }

                hadCollision = resolveCollisionPair(first, second) || hadCollision
            }

            if !hadCollision { break }
        }
    }

    private func candidateCollisionPairs() -> [CollisionPair] {
        guard bodies.count > 1 else { return [] }

        let maxRadius = bodies.map { boundingRadius(for: $0) }.max() ?? max(squareSize * 0.8, circleRadius)
        let adaptive = maxRadius * 1.8
        let cellSize = min(130, max(24, adaptive))
        var buckets: [SpatialCell: [Int]] = [:]
        buckets.reserveCapacity(bodies.count * 2)

        for index in bodies.indices {
            let body = bodies[index]
            let radius = boundingRadius(for: body) + max(collisionSlop, 0) + 2
            let minX = Int(floor((body.center.x - radius) / cellSize))
            let maxX = Int(floor((body.center.x + radius) / cellSize))
            let minY = Int(floor((body.center.y - radius) / cellSize))
            let maxY = Int(floor((body.center.y + radius) / cellSize))

            for x in minX...maxX {
                for y in minY...maxY {
                    buckets[SpatialCell(x: x, y: y), default: []].append(index)
                }
            }
        }

        var pairs = Set<CollisionPair>()
        pairs.reserveCapacity(bodies.count * 3)

        for bucket in buckets.values where bucket.count > 1 {
            for left in 0..<(bucket.count - 1) {
                for right in (left + 1)..<bucket.count {
                    let a = min(bucket[left], bucket[right])
                    let b = max(bucket[left], bucket[right])
                    pairs.insert(CollisionPair(first: a, second: b))
                }
            }
        }

        if pairs.isEmpty, bodies.count <= 12 {
            var fallback: [CollisionPair] = []
            fallback.reserveCapacity(bodies.count * bodies.count / 2)
            for first in 0..<(bodies.count - 1) {
                for second in (first + 1)..<bodies.count {
                    fallback.append(CollisionPair(first: first, second: second))
                }
            }
            return fallback
        }

        return Array(pairs)
    }

    private func resolveCollisionPair(_ firstIndex: Int, _ secondIndex: Int) -> Bool {
        var first = bodies[firstIndex]
        var second = bodies[secondIndex]

        guard let manifold = bodyCollisionManifold(first, second) else { return false }

        if manifold.penetration <= 0.0001 {
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

        let correctionStrength = min(max(collisionPositionCorrection, 0), 1)
        let slop = max(0, collisionSlop)
        let correctionMagnitude = max(manifold.penetration - slop, 0) * correctionStrength / invMassSum
        if correctionMagnitude > 0 {
            let correction = CGVector(
                dx: manifold.normal.dx * correctionMagnitude,
                dy: manifold.normal.dy * correctionMagnitude
            )
            if invMassFirst > 0 {
                first.center.x -= correction.dx * invMassFirst
                first.center.y -= correction.dy * invMassFirst
            }
            if invMassSecond > 0 {
                second.center.x += correction.dx * invMassSecond
                second.center.y += correction.dy * invMassSecond
            }
        }

        let rFirst = CGVector(
            dx: manifold.contactPoint.x - first.center.x,
            dy: manifold.contactPoint.y - first.center.y
        )
        let rSecond = CGVector(
            dx: manifold.contactPoint.x - second.center.x,
            dy: manifold.contactPoint.y - second.center.y
        )

        let velocityFirst = velocityAtContact(for: first, offset: rFirst)
        let velocitySecond = velocityAtContact(for: second, offset: rSecond)
        var relativeVelocity = CGVector(
            dx: velocitySecond.dx - velocityFirst.dx,
            dy: velocitySecond.dy - velocityFirst.dy
        )

        let velocityAlongNormal = dot(relativeVelocity, manifold.normal)
        if velocityAlongNormal > 0 {
            bodies[firstIndex] = first
            bodies[secondIndex] = second
            return true
        }

        let normalImpulseScale = max(0, collisionImpulseScale)
        if normalImpulseScale > 0 {
            let rFirstCrossNormal = cross(rFirst, manifold.normal)
            let rSecondCrossNormal = cross(rSecond, manifold.normal)
            let denominator = invMassSum +
                (rFirstCrossNormal * rFirstCrossNormal) * invInertiaFirst +
                (rSecondCrossNormal * rSecondCrossNormal) * invInertiaSecond

            if denominator > 0.000001 {
                let restitution = min(max(collisionRestitution, 0), 1)
                let impulseMagnitude = -(1 + restitution) * velocityAlongNormal / denominator * normalImpulseScale
                let impulse = CGVector(
                    dx: manifold.normal.dx * impulseMagnitude,
                    dy: manifold.normal.dy * impulseMagnitude
                )

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

                relativeVelocity = CGVector(
                    dx: velocityAtContact(for: second, offset: rSecond).dx - velocityAtContact(for: first, offset: rFirst).dx,
                    dy: velocityAtContact(for: second, offset: rSecond).dy - velocityAtContact(for: first, offset: rFirst).dy
                )

                let tangentCandidate = CGVector(
                    dx: relativeVelocity.dx - manifold.normal.dx * dot(relativeVelocity, manifold.normal),
                    dy: relativeVelocity.dy - manifold.normal.dy * dot(relativeVelocity, manifold.normal)
                )
                let tangentLengthSquared = tangentCandidate.dx * tangentCandidate.dx + tangentCandidate.dy * tangentCandidate.dy
                if tangentLengthSquared > 0.000001 {
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

                    if tangentDenominator > 0.000001 {
                        var tangentImpulseMagnitude = -dot(relativeVelocity, tangent) / tangentDenominator
                        let maxFriction = abs(impulseMagnitude) * max(0, collisionFriction)
                        tangentImpulseMagnitude = min(max(tangentImpulseMagnitude, -maxFriction), maxFriction)
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
                }
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
            guard let manifold = polygonCircleCollisionManifold(polygon: second, circle: first) else { return nil }
            return CollisionManifold(
                normal: CGVector(dx: -manifold.normal.dx, dy: -manifold.normal.dy),
                penetration: manifold.penetration,
                contactPoint: manifold.contactPoint
            )
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

        let axes = polygonAxes(for: firstVertices) + polygonAxes(for: secondVertices)
        if axes.isEmpty { return nil }

        var minOverlap = CGFloat.greatestFiniteMagnitude
        var bestAxis = CGVector(dx: 1, dy: 0)

        for axis in axes {
            let projectionFirst = projectedInterval(vertices: firstVertices, axis: axis)
            let projectionSecond = projectedInterval(vertices: secondVertices, axis: axis)
            let overlap = min(projectionFirst.max, projectionSecond.max) - max(projectionFirst.min, projectionSecond.min)
            if overlap <= 0 {
                return nil
            }
            if overlap < minOverlap {
                minOverlap = overlap
                bestAxis = axis
            }
        }

        let centerDelta = CGVector(
            dx: second.center.x - first.center.x,
            dy: second.center.y - first.center.y
        )
        if dot(centerDelta, bestAxis) < 0 {
            bestAxis = CGVector(dx: -bestAxis.dx, dy: -bestAxis.dy)
        }

        let firstSupport = supportPoint(vertices: firstVertices, direction: bestAxis)
        let secondSupport = supportPoint(
            vertices: secondVertices,
            direction: CGVector(dx: -bestAxis.dx, dy: -bestAxis.dy)
        )
        let contact = CGPoint(
            x: (firstSupport.x + secondSupport.x) * 0.5,
            y: (firstSupport.y + secondSupport.y) * 0.5
        )

        return CollisionManifold(normal: bestAxis, penetration: minOverlap, contactPoint: contact)
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
        return CollisionManifold(normal: normal, penetration: penetration, contactPoint: contact)
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
        let normal: CGVector
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

        let penetration = inside ? (radius + distance) : (radius - distance)
        if penetration <= 0 { return nil }
        return CollisionManifold(normal: normal, penetration: penetration, contactPoint: closest)
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

    private func cross(_ lhs: CGVector, _ rhs: CGVector) -> CGFloat {
        lhs.dx * rhs.dy - lhs.dy * rhs.dx
    }

    private func applyWorldBounds(to body: inout Body) {
        let collisionRadius = boundingRadius(for: body)
        let minX = collisionRadius
        let maxX = max(minX, viewportSize.width - collisionRadius)
        let minY = collisionRadius
        let maxY = max(minY, viewportSize.height - collisionRadius)

        if body.center.x < minX {
            body.center.x = minX
            body.velocity.dx *= -wallBounceX
            body.angularVelocity *= 0.92
        } else if body.center.x > maxX {
            body.center.x = maxX
            body.velocity.dx *= -wallBounceX
            body.angularVelocity *= 0.92
        }

        if body.center.y < minY {
            body.center.y = minY
            body.velocity.dy *= -wallBounceTop
            body.angularVelocity *= 0.9
        } else if body.center.y > maxY {
            body.center.y = maxY
            body.velocity.dy *= -wallBounceBottom
            body.velocity.dx *= 0.95
            body.angularVelocity *= 0.89
        }
    }

    private func resolveWeldConstraints(components: [[UUID]]) {
        guard !components.isEmpty else { return }

        let iterations = max(1, Int(weldIterations.rounded()))
        for _ in 0..<iterations {
            for component in components {
                guard component.count > 1 else { continue }
                let rootID: UUID
                if
                    let draggingBodyIndex,
                    bodies.indices.contains(draggingBodyIndex),
                    component.contains(bodies[draggingBodyIndex].id)
                {
                    rootID = bodies[draggingBodyIndex].id
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
                if weld.firstID == currentID, componentSet.contains(weld.secondID) {
                    let nextID = weld.secondID
                    guard !visited.contains(nextID), let nextIndex = bodyIndex(forID: nextID), bodies.indices.contains(nextIndex) else { continue }
                    let nextAngle = normalizedAngle(currentBody.angle + weld.restAngle)
                    let firstAnchorWorld = worldPoint(fromLocal: weld.firstLocalAnchor, in: currentBody)
                    let secondOffset = rotateVector(
                        CGVector(dx: weld.secondLocalAnchor.x, dy: weld.secondLocalAnchor.y),
                        by: nextAngle
                    )
                    bodies[nextIndex].angle = nextAngle
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
                    let firstOffset = rotateVector(
                        CGVector(dx: weld.firstLocalAnchor.x, dy: weld.firstLocalAnchor.y),
                        by: nextAngle
                    )
                    bodies[nextIndex].angle = nextAngle
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

        if let draggingBodyIndex, indices.contains(draggingBodyIndex), bodies.indices.contains(draggingBodyIndex) {
            let root = bodies[draggingBodyIndex]
            for index in indices where index != draggingBodyIndex {
                let r = CGVector(
                    dx: bodies[index].center.x - root.center.x,
                    dy: bodies[index].center.y - root.center.y
                )
                bodies[index].velocity = CGVector(
                    dx: root.velocity.dx - root.angularVelocity * r.dy,
                    dy: root.velocity.dy + root.angularVelocity * r.dx
                )
                bodies[index].angularVelocity = root.angularVelocity
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
            angularMomentum += inertia * bodies[index].angularVelocity
            angularMomentum += mass * cross(r, bodies[index].velocity)
            effectiveInertia += inertia + mass * (r.dx * r.dx + r.dy * r.dy)
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
            bodies[index].angularVelocity = omega
        }
    }

    private func cleanupWeldState() {
        let ids = Set(bodies.map(\.id))
        weldConstraints.removeAll { !ids.contains($0.firstID) || !ids.contains($0.secondID) || $0.firstID == $0.secondID }
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
        let rootID = bodies[rootIndex].id
        let lookup = weldedTopology().lookup
        guard let group = lookup[rootID] else { return }
        let component = bodies.compactMap { body -> UUID? in
            guard let g = lookup[body.id], g == group else { return nil }
            return body.id
        }
        guard component.count > 1 else { return }

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

    private func applyWaveReactionImpulse(atX x: CGFloat, fromWaterForceY forceY: CGFloat, spawnSpray: Bool = false) {
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

    private func isSceneCalm() -> Bool {
        if activity > 0.008 { return false }
        if pointerStrength > 0.004 { return false }
        if draggingBodyIndex != nil { return false }
        if surfaceSpread > 0.9 { return false }

        for body in bodies {
            if abs(body.velocity.dx) > 0.04 { return false }
            if abs(body.velocity.dy) > 0.04 { return false }
            if abs(body.angularVelocity) > 0.0025 { return false }
        }

        return true
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
        let centerY = viewportSize.height * 0.5
        return centerY + interpolatedValue(in: samples, atX: x)
    }

    private func waveVelocity(atX x: CGFloat) -> CGFloat {
        interpolatedValue(in: velocities, atX: x)
    }

    private func waveSlope(atX x: CGFloat) -> CGFloat {
        guard viewportSize.width > 1 else { return 0 }
        let deltaX = max(2, viewportSize.width / CGFloat(pointCount) * 2)
        let leftX = max(0, x - deltaX)
        let rightX = min(viewportSize.width, x + deltaX)
        let dy = waveHeight(atX: rightX) - waveHeight(atX: leftX)
        return dy / max(1, rightX - leftX)
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
            guard let vertices = body.collisionVertices ?? body.localVertices, vertices.count > 2 else { return false }
            let local = localPoint(fromWorld: point, in: body)
            return pointInPolygon(local, vertices: vertices)
        }
    }

    private func clampedBodyCenter(_ point: CGPoint, for body: Body) -> CGPoint {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return point }

        let radius = boundingRadius(for: body)
        let clampedX = min(max(radius, point.x), max(radius, viewportSize.width - radius))
        let clampedY = min(max(radius, point.y), max(radius, viewportSize.height - radius))
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func clampAllBodiesInside() {
        for index in bodies.indices {
            bodies[index].center = clampedBodyCenter(bodies[index].center, for: bodies[index])
        }
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
                    localVertices: body.localVertices
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
            collisionVertexCap: collisionVertexCap
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

        let sourcePoints: [CGPoint]
        if preserveTopology {
            sourcePoints = cleaned
        } else {
            sourcePoints = convexHull(points: cleaned)
        }

        guard sourcePoints.count >= 3 else { return }
        let maxCount = max(3, targetMaxVertexCount)
        let decimated = decimatePolygonVertices(sourcePoints, targetMaxCount: maxCount)
        guard decimated.count >= 3 else { return }

        let area = abs(polygonSignedArea(decimated))
        if area < 180 { return }

        let centroid = polygonCentroid(decimated)
        var local = decimated.map { CGPoint(x: $0.x - centroid.x, y: $0.y - centroid.y) }
        if polygonSignedArea(local) < 0 {
            local.reverse()
        }

        let radius = local.map { hypot($0.x, $0.y) }.max() ?? 0
        if radius < 9 { return }

        let collisionCap = max(3, collisionMaxVertexCount)
        let collisionBudget = collisionVertexBudget(localCount: local.count, cap: collisionCap)
        let collisionLocal: [CGPoint] =
            collisionBudget >= local.count
                ? local
                : decimatePolygonVertices(local, targetMaxCount: collisionBudget)

        var body = makeBody(
            shape: .polygon,
            center: centroid,
            localVertices: local,
            collisionVertices: collisionLocal,
            collisionVertexCap: collisionCap
        )
        body.center = clampedBodyCenter(body.center, for: body)
        body.velocity = .zero
        body.angularVelocity = 0
        bodies.append(body)
        recordSpawn(body.id)
        clampAllBodiesInside()
    }

    private func rebuildCollisionMeshes() {
        guard !bodies.isEmpty else { return }
        var changed = false

        for index in bodies.indices {
            guard bodies[index].shape == .polygon else { continue }
            guard let local = bodies[index].localVertices, local.count >= 3 else { continue }
            let cap = max(3, bodies[index].collisionVertexCap > 0 ? bodies[index].collisionVertexCap : min(local.count, 18))
            let budget = collisionVertexBudget(localCount: local.count, cap: cap)
            let reduced = budget >= local.count ? local : decimatePolygonVertices(local, targetMaxCount: budget)
            bodies[index].collisionVertices = reduced
            changed = true
        }

        if changed {
            syncBodyDrawStates()
        }
    }

    private func collisionVertexBudget(localCount: Int, cap: Int) -> Int {
        let capped = max(3, min(localCount, cap))
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
            guard let vertices = body.collisionVertices ?? body.localVertices, vertices.count > 2 else { return [.zero] }
            var points: [CGPoint] = [.zero]
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
            let ratio = min(4.8, max(0.12, area / squareArea))
            return base * ratio
        }
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
    var onKeyDown: ((NSEvent) -> Void)?
    var onModifierChanged: ((NSEvent) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            if event.type == .keyDown {
                self?.onKeyDown?(event)
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
