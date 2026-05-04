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

/// Pill circular de 56pt con un único affordance: el ícono central de micrófono.
/// Diseño Krug: una sola acción visible, estado autoevidente por color + ícono.
struct PillView: View {
    @ObservedObject var model: PillViewModel
    var onTap: () -> Void

    @State private var pulse: Bool = false
    @State private var isHovering: Bool = false

    private let size: CGFloat = 56

    var body: some View {
        ZStack {
            // Fondo translúcido con material adaptativo
            Circle()
                .fill(.regularMaterial)

            // Capa de color según estado
            Circle()
                .fill(fillColor)

            // Anillo pulsante cuando graba
            if model.state == .recording {
                Circle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 3)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            }

            // Borde sutil
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)

            // Ícono central
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(iconColor)
        }
        .frame(width: size, height: size)
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(Circle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
        .onAppear { pulse = true }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .help(helpText)
    }

    private var fillColor: Color {
        switch model.state {
        case .idle:         return Color.black.opacity(0.55)
        case .recording:    return Color.red.opacity(0.85)
        case .transcribing: return Color.orange.opacity(0.85)
        }
    }

    private var iconName: String {
        switch model.state {
        case .idle:         return "mic.fill"
        case .recording:    return "stop.fill"
        case .transcribing: return "waveform"
        }
    }

    private var iconColor: Color {
        switch model.state {
        case .idle:         return .white
        case .recording:    return .white
        case .transcribing: return .white
        }
    }

    private var accessibilityLabel: String {
        switch model.state {
        case .idle:         return "Micrófono — listo. Click para grabar."
        case .recording:    return "Micrófono — grabando. Click para detener y transcribir."
        case .transcribing: return "Micrófono — transcribiendo."
        }
    }

    private var helpText: String {
        switch model.state {
        case .idle:         return "Click para grabar"
        case .recording:    return "Click para detener y transcribir"
        case .transcribing: return "Transcribiendo…"
        }
    }
}
