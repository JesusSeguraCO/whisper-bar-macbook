import Cocoa
import SwiftUI

/// Subclase de NSPanel que captura click derecho para mostrar un menú contextual.
/// Necesaria porque NSPanel borderless no propaga rightMouseDown a SwiftUI.
final class PillPanel: NSPanel {
    var onRightClick: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

/// Controla el pill flotante de micrófono. Singleton.
/// Patrón espejado de FloatingTranscriptionWindowController.
final class PillWindowController: NSObject, NSWindowDelegate {
    static let shared = PillWindowController()

    private var panel: PillPanel?
    private let viewModel = PillViewModel()
    private let config = Config.shared

    /// Tamaño del pill (debe coincidir con PillView.size).
    private let pillSize = CGSize(width: 56, height: 56)

    /// Callback disparado cuando el usuario hace click izquierdo en el pill.
    var onPillTapped: (() -> Void)?

    /// Callback disparado cuando el usuario oculta el pill desde el menú contextual.
    var onPillHiddenByUser: (() -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Mostrar / Ocultar

    func showPill() {
        if let existing = panel {
            existing.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(
            rootView: PillView(
                model: viewModel,
                onTap: { [weak self] in self?.onPillTapped?() }
            )
        )
        // Fondo transparente del hosting para que solo el círculo sea visible
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let p = PillPanel(
            contentRect: NSRect(origin: .zero, size: pillSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hosting
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.onRightClick = { [weak self] _ in self?.showContextMenu() }

        let origin = resolvedOrigin()
        p.setFrame(NSRect(origin: origin, size: pillSize), display: true)
        p.orderFrontRegardless()

        self.panel = p
    }

    func hidePill() {
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
    }

    func togglePill() {
        if isVisible { hidePill() } else { showPill() }
    }

    // MARK: - Estado

    /// Actualiza el estado visual del pill. Thread-safe.
    func setState(_ state: PillState) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.state = state
        }
    }

    // MARK: - Posición

    /// Resuelve el origen a usar: el guardado si es válido, o el default.
    private func resolvedOrigin() -> NSPoint {
        let savedX = config.floatingPillOriginX
        let savedY = config.floatingPillOriginY
        if savedX.isFinite, savedY.isFinite {
            let candidate = NSPoint(x: savedX, y: savedY)
            if isOriginVisible(candidate) { return candidate }
        }
        return defaultOrigin()
    }

    /// Esquina inferior-derecha de la pantalla principal, con margen.
    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.maxX - pillSize.width - 24,
            y: frame.minY + 80
        )
    }

    /// Verifica que el rect del pill colocado en `origin` esté dentro de alguna pantalla.
    private func isOriginVisible(_ origin: NSPoint) -> Bool {
        let pillRect = NSRect(origin: origin, size: pillSize)
        return NSScreen.screens.contains { $0.frame.intersects(pillRect) }
    }

    @objc private func screenParametersChanged() {
        guard let panel else { return }
        if !isOriginVisible(panel.frame.origin) {
            let newOrigin = defaultOrigin()
            panel.setFrameOrigin(newOrigin)
            persistOrigin(newOrigin)
        }
    }

    private func persistOrigin(_ origin: NSPoint) {
        config.floatingPillOriginX = Double(origin.x)
        config.floatingPillOriginY = Double(origin.y)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        persistOrigin(panel.frame.origin)
    }

    // MARK: - Menú contextual (click derecho)

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Ocultar pill", action: #selector(handleHide), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferencias…", action: #selector(handlePreferences), keyEquivalent: "")
        for item in menu.items { item.target = self }

        if let panel, let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: panel.contentView ?? NSView())
        }
    }

    @objc private func handleHide() {
        config.floatingPillEnabled = false
        hidePill()
        onPillHiddenByUser?()
    }

    @objc private func handlePreferences() {
        DispatchQueue.main.async {
            PreferencesWindowController.shared.showWindow()
        }
    }

    // MARK: - Test helpers

    #if DEBUG
    var debugViewModel: PillViewModel { viewModel }
    #endif
}
