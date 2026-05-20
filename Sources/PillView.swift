import SwiftUI

/// Estado visual del pill flotante.
enum PillState {
    case idle           // Listo para grabar
    case recording      // Grabando (usuario habla)
    case transcribing   // Procesando audio → texto
}

/// View model observable. Único punto de cambio de estado para la UI.
final class PillViewModel: ObservableObject {
    @Published var state: PillState = .idle
}

// MARK: - Paleta neón

private enum Neon {
    static let cyan    = Color(red: 0.00, green: 0.92, blue: 1.00) // #00EBFF
    static let magenta = Color(red: 1.00, green: 0.10, blue: 0.78) // #FF1AC8
    static let red     = Color(red: 1.00, green: 0.18, blue: 0.34) // #FF2D57
    static let purple  = Color(red: 0.55, green: 0.36, blue: 1.00) // #8C5CFF
    static let lime    = Color(red: 0.32, green: 1.00, blue: 0.55) // #52FF8C
    static let inkTop    = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let inkBottom = Color(red: 0.04, green: 0.04, blue: 0.10)
}

/// Pill alargado con paleta neón y animaciones específicas por estado.
/// Diseño Krug: estado autoevidente, alta visibilidad sobre cualquier fondo.
struct PillView: View {
    @ObservedObject var model: PillViewModel
    var onTap: () -> Void
    var onCancel: () -> Void

    @State private var isHovering: Bool = false

    private let height: CGFloat = 44

    var body: some View {
        // Color.clear fill expande para ocupar el NSPanel; el capsule queda
        // centrado con margen suficiente para que el glow no se recorte en las
        // esquinas rectangulares del panel.
        ZStack {
            Color.clear
                .allowsHitTesting(false)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                content(time: t)
                    .padding(.horizontal, 14)
                    .frame(height: height)
                    .frame(minWidth: 150)
                    .background(background(time: t))
                    .overlay(border(time: t))
                    .clipShape(Capsule())
                    .shadow(color: glowColor.opacity(glowOpacity(time: t)),
                            radius: glowRadius(time: t), x: 0, y: 0)
                    .scaleEffect(isHovering ? 1.05 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
            }
            .fixedSize()
            .contentShape(Capsule())
            .onTapGesture { onTap() }
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .help(helpText)
    }

    // MARK: Contenido por estado

    @ViewBuilder
    private func content(time: TimeInterval) -> some View {
        switch model.state {
        case .idle:         IdleContent(time: time)
        case .recording:    RecordingContent(time: time, onCancel: onCancel)
        case .transcribing: TranscribingContent(time: time, onCancel: onCancel)
        }
    }

    // MARK: Fondo + borde con animación

    @ViewBuilder
    private func background(time: TimeInterval) -> some View {
        switch model.state {
        case .idle:
            LinearGradient(
                colors: [Neon.inkTop, Neon.inkBottom],
                startPoint: .top, endPoint: .bottom
            )
        case .recording:
            // Gradient hot red→magenta con shift sutil de fase
            let shift = sin(time * 1.2) * 0.5 + 0.5  // 0..1
            LinearGradient(
                colors: [Neon.red, Neon.magenta],
                startPoint: UnitPoint(x: shift * 0.3, y: 0),
                endPoint:   UnitPoint(x: 1.0 - shift * 0.3, y: 1.0)
            )
        case .transcribing:
            let shift = (time.truncatingRemainder(dividingBy: 2)) / 2  // 0..1
            LinearGradient(
                colors: [Neon.purple, Neon.cyan],
                startPoint: UnitPoint(x: shift, y: 0),
                endPoint:   UnitPoint(x: 1 + shift, y: 1)
            )
        }
    }

    @ViewBuilder
    private func border(time: TimeInterval) -> some View {
        switch model.state {
        case .idle:
            // Borde respirado cyan↔magenta
            let breath = sin(time * 1.6) * 0.5 + 0.5  // 0..1
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Neon.cyan.opacity(0.6 + breath * 0.4),
                            Neon.magenta.opacity(0.6 + breath * 0.4),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    lineWidth: 1.6
                )
        case .recording, .transcribing:
            Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.4)
        }
    }

    // MARK: Glow dinámico

    private var glowColor: Color {
        switch model.state {
        case .idle:         return Neon.cyan
        case .recording:    return Neon.red
        case .transcribing: return Neon.purple
        }
    }

    private func glowRadius(time: TimeInterval) -> CGFloat {
        switch model.state {
        case .idle:
            let breath = sin(time * 1.6) * 0.5 + 0.5
            return 6 + CGFloat(breath) * 6   // 6..12
        case .recording:
            let pulse = sin(time * 4.5) * 0.5 + 0.5
            return 12 + CGFloat(pulse) * 8   // 12..20
        case .transcribing:
            return 14
        }
    }

    private func glowOpacity(time: TimeInterval) -> Double {
        switch model.state {
        case .idle:
            let breath = sin(time * 1.6) * 0.5 + 0.5
            return 0.35 + breath * 0.25
        case .recording:    return 0.85
        case .transcribing: return 0.7
        }
    }

    // MARK: Accesibilidad

    private var accessibilityLabel: String {
        switch model.state {
        case .idle:         return "Micrófono — listo. Click para grabar."
        case .recording:    return "Grabando. Click para detener y transcribir."
        case .transcribing: return "Procesando transcripción."
        }
    }

    private var helpText: String {
        switch model.state {
        case .idle:         return "Click para grabar"
        case .recording:    return "Click para detener y transcribir · Esc o ✕ para cancelar"
        case .transcribing: return "Procesando… · Esc o ✕ para cancelar"
        }
    }
}

// MARK: - Contenido por estado

private struct IdleContent: View {
    let time: TimeInterval

    var body: some View {
        let breath = sin(time * 1.6) * 0.5 + 0.5  // 0..1
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Neon.cyan, Neon.magenta],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Neon.cyan.opacity(0.6 + breath * 0.4), radius: 4)
            Text("Listo")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(.white.opacity(0.92))
                .tracking(0.3)
        }
    }
}

private struct RecordingContent: View {
    let time: TimeInterval
    let onCancel: () -> Void

    var body: some View {
        // Punto rojo pulsante
        let pulse = sin(time * 4.5) * 0.5 + 0.5  // 0..1
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .scaleEffect(0.85 + pulse * 0.35)
                .opacity(0.75 + pulse * 0.25)
                .shadow(color: .white.opacity(0.6), radius: 3)

            Text("REC")
                .font(.system(.callout, design: .monospaced).weight(.heavy))
                .tracking(2.5)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 1)

            WaveformBars(time: time)

            CancelButton(action: onCancel)
        }
    }
}

private struct WaveformBars: View {
    let time: TimeInterval
    private let count = 4

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.8, height: barHeight(for: i))
            }
        }
        .frame(height: 18)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Cada barra desfasada para dar sensación de onda viajera
        let speed: Double = 6.0
        let phase = time * speed + Double(index) * 0.7
        let v = sin(phase) * 0.5 + 0.5  // 0..1
        return 5 + CGFloat(v) * 13       // 5..18
    }
}

private struct TranscribingContent: View {
    let time: TimeInterval
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text("Procesando")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(.white)
                .tracking(0.3)
            DotsLoader(time: time)

            CancelButton(action: onCancel)
        }
    }
}

private struct DotsLoader: View {
    let time: TimeInterval

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .opacity(opacity(for: i))
                    .scaleEffect(scale(for: i))
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        let phase = time * 3.5 + Double(index) * 0.5
        return 0.35 + (sin(phase) * 0.5 + 0.5) * 0.65
    }

    private func scale(for index: Int) -> CGFloat {
        let phase = time * 3.5 + Double(index) * 0.5
        return 0.85 + CGFloat(sin(phase) * 0.5 + 0.5) * 0.4
    }
}

/// Botón ✕ para cancelar grabación o transcripción.
/// Se diferencia del área principal del pill para que no active el onTap.
private struct CancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.80))
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
        .buttonStyle(.plain)
        .help("Cancelar (Esc)")
    }
}
