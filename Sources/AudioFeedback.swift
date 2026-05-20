import AVFoundation

// MARK: - AudioPreset

/// Define un preset de sonido generado por síntesis.
struct AudioPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String       // "Relajante", "Concentración", "Energético", "Neutro"
    let description: String
    let baseFreq: Double       // Hz fundamental
    let beatFreq: Double       // Hz de offset binaural (0 = sin binaural)
    let breatheRate: Double    // Hz de modulación de amplitud

    static let all: [AudioPreset] = [
        .init(id: "theta",  name: "Theta Binaural",   category: "Relajante",
              description: "4 Hz · meditación y relajación profunda",
              baseFreq: 256, beatFreq: 4,  breatheRate: 0.6),
        .init(id: "deep",   name: "Deep Drone",        category: "Relajante",
              description: "3 Hz · graves profundos, ideal con auriculares",
              baseFreq: 128, beatFreq: 3,  breatheRate: 0.3),
        .init(id: "528hz",  name: "Solfeggio 528 Hz",  category: "Relajante",
              description: "Frecuencia de transformación, suave",
              baseFreq: 528, beatFreq: 0,  breatheRate: 0.6),
        .init(id: "alpha",  name: "Alpha Binaural",    category: "Concentración",
              description: "10 Hz · enfoque tranquilo y creatividad",
              baseFreq: 256, beatFreq: 10, breatheRate: 1.0),
        .init(id: "beta",   name: "Beta Binaural",     category: "Energético",
              description: "20 Hz · alerta máxima y productividad",
              baseFreq: 200, beatFreq: 20, breatheRate: 3.0),
        .init(id: "432hz",  name: "Tono 432 Hz",       category: "Neutro",
              description: "Frecuencia armónica suave, sin binaural",
              baseFreq: 432, beatFreq: 0,  breatheRate: 0.8),
    ]

    static let customPreset = AudioPreset(
        id: "custom", name: "Archivo personalizado", category: "Personalizado",
        description: "Selecciona tu propio archivo de audio",
        baseFreq: 0, beatFreq: 0, breatheRate: 0
    )

    static var categories: [String] {
        var seen = [String]()
        var result = [String]()
        for p in all {
            if !seen.contains(p.category) { seen.append(p.category); result.append(p.category) }
        }
        return result
    }
}

// MARK: - AudioFeedback

/// Reproduce sonido de feedback durante la transcripción.
/// Soporta presets generados por síntesis y archivos de audio personalizados.
class AudioFeedback {

    // Síntesis (presets)
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var mixer  = AVAudioMixerNode()
    private let sampleRate: Double = 44100
    private let maxAmplitude: Float = 0.07

    // Archivo personalizado
    private var filePlayer: AVAudioPlayer?

    private var fadeTimer:    Timer?
    private var previewTimer: Timer?

    private(set) var isPlaying = false

    // MARK: - API pública

    func start() {
        guard !isPlaying else { return }
        let cfg = Config.shared
        guard cfg.audioFeedbackEnabled else { return }
        play(presetId: cfg.audioFeedbackPreset,
             volume:   Float(cfg.audioFeedbackVolume))
    }

    func stop() {
        previewTimer?.invalidate(); previewTimer = nil
        guard isPlaying else { return }
        if filePlayer != nil { stopFilePlayer() } else { stopEngineWithFade() }
    }

    /// Reproduce un preset durante 3 s para previsualización en Preferencias.
    func preview(presetId: String, volume: Float) {
        stopImmediate()
        play(presetId: presetId, volume: volume)
        previewTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.stopImmediate()
        }
    }

    // MARK: - Privado

    private func play(presetId: String, volume: Float) {
        if presetId == "custom" {
            startCustomFile(volume: volume)
        } else {
            let preset = AudioPreset.all.first { $0.id == presetId } ?? AudioPreset.all[0]
            startEnginePreset(preset, volume: volume)
        }
    }

    // MARK: Engine (presets sintetizados)

    private func startEnginePreset(_ preset: AudioPreset, volume: Float) {
        fadeTimer?.invalidate(); fadeTimer = nil

        // Crear instancias frescas para evitar conflictos con sesiones previas
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        mixer  = AVAudioMixerNode()

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(player)
        engine.attach(mixer)
        engine.connect(player, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        mixer.outputVolume = 0
        do { try engine.start() } catch { return }

        player.scheduleBuffer(makeBuffer(for: preset), at: nil, options: .loops)
        player.play()
        isPlaying = true
        fadeVolume(to: maxAmplitude * volume, duration: 1.2)
    }

    private func stopEngineWithFade() {
        isPlaying = false
        fadeVolume(to: 0, duration: 0.6) { [weak self] in
            self?.player.stop()
            self?.engine.stop()
        }
    }

    private func stopImmediate() {
        fadeTimer?.invalidate(); fadeTimer = nil
        previewTimer?.invalidate(); previewTimer = nil
        player.stop()
        engine.stop()
        filePlayer?.stop(); filePlayer = nil
        isPlaying = false
        mixer.outputVolume = 0
    }

    // MARK: Archivo personalizado

    private func startCustomFile(volume: Float) {
        let path = Config.shared.audioFeedbackCustomPath
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard let ap = try? AVAudioPlayer(contentsOf: url) else { return }
        ap.numberOfLoops = -1
        ap.volume = volume
        ap.prepareToPlay()
        ap.play()
        filePlayer = ap
        isPlaying = true
    }

    private func stopFilePlayer() {
        filePlayer?.stop()
        filePlayer = nil
        isPlaying = false
    }

    // MARK: Síntesis de buffer

    private func makeBuffer(for preset: AudioPreset) -> AVAudioPCMBuffer {
        let frameCount: AVAudioFrameCount = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let left  = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        let pi2   = 2.0 * Double.pi
        // Si hay binaural, el canal derecho usa la frecuencia desplazada
        let rightFreq = preset.beatFreq > 0 ? preset.baseFreq + preset.beatFreq : preset.baseFreq

        for i in 0..<Int(frameCount) {
            let t       = Double(i) / sampleRate
            let breathe = Float(sin(pi2 * preset.breatheRate * t) * 0.12 + 0.88)
            left[i]  = Float(sin(pi2 * preset.baseFreq * t)) * breathe
            right[i] = Float(sin(pi2 * rightFreq * t)) * breathe
        }
        return buffer
    }

    // MARK: Fade de volumen

    private func fadeVolume(to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        let steps    = 30
        let interval = duration / Double(steps)
        let start    = mixer.outputVolume
        var step     = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            let t = Float(step) / Float(steps)
            self.mixer.outputVolume = start + (target - start) * t
            if step >= steps {
                timer.invalidate()
                self.fadeTimer = nil
                completion?()
            }
        }
    }
}
