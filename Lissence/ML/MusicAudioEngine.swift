import Foundation
import AVFoundation
import CoreHaptics
import Accelerate
import Combine
import QuartzCore

private enum HapticStyle {
    case tap
    case doubleTap
    case softContinuous
    case buzzContinuous
    case rising
    case microTap
}

final class MusicAudioEngine: ObservableObject {

    // 외부 노출 상태
    @Published var isRunning = false
    @Published var statusText = "대기 중"

    @Published var mood: Mood = .happy
    @Published var moodPercent: Double = 0
    @Published var moodProbabilities: [String: Double] = [
        "Q1": 0, "Q2": 0, "Q3": 0, "Q4": 0
    ]

    @Published var intensity: Float = 0
    @Published var sharpness: Float = 0
    @Published var bass: Float = 0
    @Published var treble: Float = 0

    /// 비트가 감지될 때마다 1씩 증가. Rive volume_spike 트리거에 사용.
    @Published var beatPulse: Int = 0

    // 오디오
    private let audioEngine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "MusicAudioEngine.analysis")
    private let mlQueue = DispatchQueue(label: "MusicAudioEngine.ml", qos: .userInitiated)

    // 햅틱
    private var hapticEngine: CHHapticEngine?

    // ML
    private var classifier: MoodClassifier?
    private let extractor = AudioFeatureExtractor()
    private let windowSeconds: Double = 3.0
    private let stepSeconds: Double = 1.0
    private var ringBuffer: [Float] = []
    private var ringSampleRate: Double = 44100
    private var totalSamples: Int = 0
    private var lastEmittedSample: Int = 0
    private var isProcessingWindow = false
    private var moodHistory: [[String: Double]] = []
    private let maxHistory = 3

    // 비트 감지 EMA / 상태
    private var energyEMA: Float = 0
    private var peakEMA: Float = 0
    private var lastEnergy: Float = 0
    private var lowEMA: Float = 0
    private var midEMA: Float = 0
    private var highEMA: Float = 0
    private var centroidEMA: Float = 0

    private let minBeatInterval: TimeInterval = 0.08
    private var lastBeatTime: TimeInterval = 0
    private let microCooldown: TimeInterval = 0.075
    private var lastMicroTrigger: TimeInterval = 0
    private let risingCooldown: TimeInterval = 0.40
    private var lastRisingTrigger: TimeInterval = 0

    // UI 스무딩
    private var smoothedIntensity: Float = 0
    private var smoothedSharpness: Float = 0
    private var smoothedBass: Float = 0
    private var smoothedTreble: Float = 0

    // MARK: - 시작 / 정지

    func start() {
        guard !isRunning else { return }

        do {
            classifier = try MoodClassifier()
        } catch {
            DispatchQueue.main.async {
                self.statusText = "모델 로드 실패: \(error.localizedDescription)"
            }
            return
        }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self else { return }

            guard granted else {
                DispatchQueue.main.async {
                    self.statusText = "마이크 권한이 거부됨"
                }
                return
            }

            DispatchQueue.main.async {
                do {
                    try self.configureAudioSession()
                    try self.setupHaptics()
                    try self.startAudioTap()
                    self.isRunning = true
                    self.statusText = "음악 분석 중..."
                } catch {
                    self.statusText = "시작 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        hapticEngine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        analysisQueue.async {
            self.energyEMA = 0
            self.peakEMA = 0
            self.lastEnergy = 0
            self.lowEMA = 0
            self.midEMA = 0
            self.highEMA = 0
            self.centroidEMA = 0
            self.ringBuffer.removeAll()
            self.totalSamples = 0
            self.lastEmittedSample = 0
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.intensity = 0
            self.sharpness = 0
            self.bass = 0
            self.treble = 0
            self.smoothedIntensity = 0
            self.smoothedSharpness = 0
            self.smoothedBass = 0
            self.smoothedTreble = 0
            self.moodHistory.removeAll()
            self.statusText = "정지됨"
        }
    }

    // MARK: - 셋업

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.defaultToSpeaker, .mixWithOthers])
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    private func setupHaptics() throws {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if hapticEngine == nil {
            hapticEngine = try CHHapticEngine()
        }
        hapticEngine?.resetHandler = { [weak self] in
            try? self?.hapticEngine?.start()
        }
        try hapticEngine?.start()
    }

    private func startAudioTap() throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        ringSampleRate = format.sampleRate

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.analysisQueue.async {
                self.processBuffer(buffer, sampleRate: format.sampleRate)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - 버퍼 처리

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        // 1) 비트/FFT 분석 → 햅틱 + UI
        let basic = extractBasic(buffer)
        let fft = extractFFT(buffer, sampleRate: Float(sampleRate))

        energyEMA = energyEMA * 0.90 + basic.rms * 0.10
        peakEMA   = peakEMA   * 0.88 + basic.peak * 0.12
        lowEMA    = lowEMA    * 0.88 + fft.low  * 0.12
        midEMA    = midEMA    * 0.88 + fft.mid  * 0.12
        highEMA   = highEMA   * 0.88 + fft.high * 0.12
        centroidEMA = centroidEMA * 0.90 + fft.centroid * 0.10

        let beat = detectBeat(basic, fft: fft)

        DispatchQueue.main.async {
            self.smoothedIntensity = self.smoothedIntensity * 0.80 + beat.uiIntensity * 0.20
            self.smoothedSharpness = self.smoothedSharpness * 0.80 + beat.uiSharpness * 0.20
            self.smoothedBass      = self.smoothedBass      * 0.80 + beat.uiBass      * 0.20
            self.smoothedTreble    = self.smoothedTreble    * 0.80 + beat.uiTreble    * 0.20

            self.intensity = min(max(self.smoothedIntensity, 0), 1)
            self.sharpness = min(max(self.smoothedSharpness, 0), 1)
            self.bass      = min(max(self.smoothedBass, 0), 1)
            self.treble    = min(max(self.smoothedTreble, 0), 1)
        }

        if beat.shouldTrigger {
            DispatchQueue.main.async { self.beatPulse &+= 1 }
            playHaptic(style: beat.style, intensity: beat.intensity, sharpness: beat.sharpness)
        } else {
            tryMicroTap(basic: basic, fft: fft)
        }

        // 2) 링버퍼에 누적 + 3초 윈도우 ML 추론
        appendToRingBuffer(buffer: buffer)
        maybeRunMLWindow()
    }

    private func appendToRingBuffer(buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var chunk = [Float](repeating: 0, count: frames)
        if channelCount == 1 {
            let data = channels[0]
            for i in 0..<frames { chunk[i] = data[i] }
        } else {
            for i in 0..<frames {
                var v: Float = 0
                for c in 0..<channelCount { v += channels[c][i] }
                chunk[i] = v / Float(channelCount)
            }
        }

        ringBuffer.append(contentsOf: chunk)
        totalSamples += frames

        let windowSamples = Int(ringSampleRate * windowSeconds)
        let stepSamples = Int(ringSampleRate * stepSeconds)
        let cap = max(windowSamples * 2, windowSamples + stepSamples)
        if ringBuffer.count > cap {
            ringBuffer.removeFirst(ringBuffer.count - cap)
        }
    }

    private func maybeRunMLWindow() {
        let windowSamples = Int(ringSampleRate * windowSeconds)
        let stepSamples = Int(ringSampleRate * stepSeconds)

        guard ringBuffer.count >= windowSamples else { return }
        guard totalSamples - lastEmittedSample >= stepSamples else { return }
        guard !isProcessingWindow else { return }

        lastEmittedSample = totalSamples
        isProcessingWindow = true

        let start = max(0, ringBuffer.count - windowSamples)
        let window = Array(ringBuffer[start..<ringBuffer.count])
        let rate = ringSampleRate
        let model = classifier

        mlQueue.async {
            defer {
                self.analysisQueue.async { self.isProcessingWindow = false }
            }
            guard let model else { return }
            do {
                let input = try self.extractor.makeInput(samples: window, sampleRate: rate)
                let result = try model.predict(input: input)
                self.applyMoodResult(result)
            } catch {
                DispatchQueue.main.async {
                    self.statusText = "ML 추론 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private func applyMoodResult(_ result: MoodPredictionResult) {
        let normalized = normalize(result.probabilities)

        moodHistory.append(normalized)
        if moodHistory.count > maxHistory {
            moodHistory.removeFirst()
        }

        var avg: [String: Double] = ["Q1": 0, "Q2": 0, "Q3": 0, "Q4": 0]
        for w in moodHistory {
            for k in avg.keys { avg[k]! += (w[k] ?? 0) }
        }
        for k in avg.keys { avg[k]! /= Double(moodHistory.count) }

        let chosen = chooseMood(avg)

        DispatchQueue.main.async {
            self.moodProbabilities = avg
            self.moodPercent = chosen.percent
            if let m = Mood(qLabel: chosen.label) {
                self.mood = m
            }
        }
    }

    private func normalize(_ p: [String: Double]) -> [String: Double] {
        let labels = ["Q1", "Q2", "Q3", "Q4"]
        var result: [String: Double] = [:]
        var sum = 0.0
        for l in labels {
            let v = p[l] ?? 0
            result[l] = v
            sum += v
        }
        if sum <= 0 {
            return ["Q1": 0.25, "Q2": 0.25, "Q3": 0.25, "Q4": 0.25]
        }
        for l in labels { result[l]! /= sum }
        return result
    }

    private func chooseMood(_ p: [String: Double]) -> (label: String, percent: Double) {
        let q1 = p["Q1"] ?? 0
        let q2 = p["Q2"] ?? 0
        let q3 = p["Q3"] ?? 0
        let q4 = p["Q4"] ?? 0

        let calmScore = q3 + q4
        let sadRelaxBest: (String, Double) = q4 >= q3 ? ("Q4", q4) : ("Q3", q3)

        let angryIsVeryStrong = q2 >= 0.62
        let angryBeatsQ1 = q2 >= q1 + 0.15
        let angryBeatsSad = q2 >= q3 + 0.25
        let angryBeatsRelax = q2 >= q4 + 0.25

        if q2 >= q1 && q2 >= q3 && q2 >= q4 {
            if angryIsVeryStrong && angryBeatsQ1 && angryBeatsSad && angryBeatsRelax {
                return ("Q2", q2 * 100)
            }
            if q4 >= 0.12 { return ("Q4", q4 * 100) }
            if q3 >= 0.12 { return ("Q3", q3 * 100) }
            let nonAngry = [("Q1", q1), ("Q3", q3), ("Q4", q4)].max { $0.1 < $1.1 } ?? ("Q1", q1)
            return (nonAngry.0, nonAngry.1 * 100)
        }

        if calmScore >= q2 * 0.75 && sadRelaxBest.1 >= 0.12 {
            return (sadRelaxBest.0, sadRelaxBest.1 * 100)
        }
        if q4 >= 0.18 && q4 >= q1 - 0.10 { return ("Q4", q4 * 100) }
        if q3 >= 0.18 && q3 >= q1 - 0.10 { return ("Q3", q3 * 100) }

        let adjusted: [String: Double] = [
            "Q1": q1, "Q2": q2 * 0.45, "Q3": q3 * 1.40, "Q4": q4 * 1.55
        ]
        let best = adjusted.max { $0.value < $1.value } ?? ("Q1", q1)
        return (best.key, (p[best.key] ?? 0) * 100)
    }

    // MARK: - 비트/FFT 분석 (BeatHapticsViewModel 로직 그대로)

    private func extractBasic(_ buffer: AVAudioPCMBuffer) -> (rms: Float, peak: Float, zcr: Float) {
        guard let data = buffer.floatChannelData else { return (0, 0, 0) }
        let frames = Int(buffer.frameLength)
        if frames <= 1 { return (0, 0, 0) }

        let channel = data[0]
        var sum: Float = 0
        var peak: Float = 0
        var zc = 0
        var prev = channel[0]

        for i in 0..<frames {
            let s = channel[i]
            sum += s * s
            peak = max(peak, abs(s))
            if i > 0 {
                if (prev >= 0 && s < 0) || (prev < 0 && s >= 0) { zc += 1 }
                prev = s
            }
        }
        let rms = sqrt(sum / Float(frames))
        let zcr = Float(zc) / Float(frames)
        return (rms, peak, zcr)
    }

    private func extractFFT(_ buffer: AVAudioPCMBuffer, sampleRate: Float)
        -> (low: Float, mid: Float, high: Float, centroid: Float)
    {
        guard let data = buffer.floatChannelData else { return (0, 0, 0, 0) }
        let frameCount = Int(buffer.frameLength)
        if frameCount < 2 { return (0, 0, 0, 0) }

        var size = 1
        while size * 2 <= frameCount { size *= 2 }
        if size < 2 { return (0, 0, 0, 0) }

        var samples = [Float](repeating: 0, count: size)
        let channel = data[0]
        for i in 0..<size { samples[i] = channel[i] }

        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(size))

        let log2n = vDSP_Length(log2(Float(size)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return (0, 0, 0, 0)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: size / 2)
        var imag = [Float](repeating: 0, count: size / 2)

        var lo: Float = 0; var mi: Float = 0; var hi: Float = 0
        var ws: Float = 0; var total: Float = 0

        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)

                samples.withUnsafeBufferPointer { sp in
                    sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                var mags = [Float](repeating: 0, count: size / 2)
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(size / 2))

                let binFreq = sampleRate / Float(size)
                for i in 1..<mags.count {
                    let f = Float(i) * binFreq
                    let m = mags[i]
                    total += m
                    ws += f * m
                    if f < 200 { lo += m }
                    else if f < 2000 { mi += m }
                    else { hi += m }
                }
            }
        }
        let centroid = total > 0 ? ws / total : 0
        return (lo, mi, hi, centroid)
    }

    private func detectBeat(
        _ f: (rms: Float, peak: Float, zcr: Float),
        fft: (low: Float, mid: Float, high: Float, centroid: Float)
    ) -> (
        shouldTrigger: Bool,
        style: HapticStyle,
        intensity: Float,
        sharpness: Float,
        uiIntensity: Float,
        uiSharpness: Float,
        uiBass: Float,
        uiTreble: Float
    ) {
        let now = CACurrentMediaTime()

        let safeEnergy = max(energyEMA, 0.0001)
        let safePeak = max(peakEMA, 0.0001)
        let safeLow = max(lowEMA, 0.0001)
        let safeHigh = max(highEMA, 0.0001)
        let safeCentroid = max(centroidEMA, 1.0)

        let relativeEnergy = f.rms / safeEnergy
        let relativePeak = f.peak / safePeak
        let energyRise = max(f.rms - lastEnergy, 0)
        lastEnergy = f.rms

        let bassBoost = fft.low / safeLow
        let trebleBoost = fft.high / safeHigh
        let centroidBoost = fft.centroid / safeCentroid

        let lowVsMid = fft.low / max(fft.mid, 0.0001)
        let highVsMid = fft.high / max(fft.mid, 0.0001)

        let uiIntensity = min(max(relativeEnergy * 0.35 + bassBoost * 0.08, 0), 1)
        let uiSharpness = min(max(f.zcr * 5.0 + highVsMid * 0.12, 0.05), 1)
        let uiBass = min(max(bassBoost * 0.5, 0), 1)
        let uiTreble = min(max(trebleBoost * 0.5, 0), 1)

        guard now - lastBeatTime >= minBeatInterval else {
            return (false, .tap, 0, 0, uiIntensity, uiSharpness, uiBass, uiTreble)
        }

        let isStrongEnough =
            (relativeEnergy > 1.12 && energyRise > 0.0015) ||
            (relativePeak > 1.08 && energyRise > 0.0012) ||
            (f.rms > safeEnergy * 1.05 && f.peak > safePeak * 1.03) ||
            (bassBoost > 1.15 && relativeEnergy > 1.04) ||
            (trebleBoost > 1.18 && f.zcr > 0.05)

        guard isStrongEnough else {
            return (false, .tap, 0, 0, uiIntensity, uiSharpness, uiBass, uiTreble)
        }

        lastBeatTime = now

        var sharp = min(max(f.zcr * 3.0, 0.15), 0.75)
        var inten = (relativeEnergy - 1.0) * 1.8 + (relativePeak - 1.0) * 1.0
        let sharpBoost = 1.0 + (sharp - 0.15) * 0.9
        inten *= sharpBoost
        inten *= (1.0 + min(max(bassBoost - 1.0, 0), 1.0) * 0.45)
        sharp *= (1.0 + min(max(trebleBoost - 1.0, 0), 1.0) * 0.50)
        sharp *= (1.0 + min(max(centroidBoost - 1.0, 0), 1.0) * 0.18)
        inten = min(max(inten, 0.30), 1.0)
        sharp = min(max(sharp, 0.08), 0.95)

        let strongBassAccent = bassBoost > 1.22 && lowVsMid > 0.78
        let strongTrebleAccent = trebleBoost > 1.16 && highVsMid > 0.84
        let veryStrongHit =
            (relativeEnergy > 1.24 && relativePeak > 1.12) ||
            (energyRise > 0.0045 && relativePeak > 1.10)
        let moderateHit =
            (relativeEnergy > 1.10 && relativePeak > 1.03) ||
            (energyRise > 0.0018)

        var style: HapticStyle = .tap
        let currentMood = self.mood

        switch currentMood {
        case .happy:
            inten *= 0.92; sharp *= 0.88
            if veryStrongHit && strongBassAccent { style = .rising }
            else if veryStrongHit { style = .doubleTap }
            else if moderateHit { style = .softContinuous; inten *= 0.92; sharp *= 0.82 }
            else if strongTrebleAccent { style = .microTap; inten *= 0.70 }
            else { style = .softContinuous; inten *= 0.95; sharp *= 0.80 }

        case .angry:
            inten *= 1.08; sharp *= 1.02
            if veryStrongHit && strongBassAccent { style = .rising; inten *= 1.05 }
            else if veryStrongHit { style = .doubleTap }
            else if moderateHit { style = .buzzContinuous; inten *= 1.00; sharp *= 0.90 }
            else if strongTrebleAccent && f.zcr > 0.055 { style = .tap }
            else { style = .buzzContinuous; inten *= 1.03; sharp *= 0.88 }

        case .sad:
            inten *= 0.72; sharp *= 0.70; style = .softContinuous

        case .relaxed:
            inten *= 0.65; sharp *= 0.60; style = .buzzContinuous
        }

        inten = min(max(inten, 0.22), 1.0)
        sharp = min(max(sharp, 0.08), 0.95)

        let risingCondition =
            relativeEnergy > 1.22 &&
            energyRise > 0.004 &&
            bassBoost > 1.15 &&
            now - lastRisingTrigger > risingCooldown

        if risingCondition && (currentMood == .happy || currentMood == .angry) {
            lastRisingTrigger = now
            if veryStrongHit || strongBassAccent { style = .rising }
        }

        return (true, style, inten, sharp, uiIntensity, uiSharpness, uiBass, uiTreble)
    }

    private func tryMicroTap(
        basic: (rms: Float, peak: Float, zcr: Float),
        fft: (low: Float, mid: Float, high: Float, centroid: Float)
    ) {
        let now = CACurrentMediaTime()
        let enoughGapFromBeat = now - lastBeatTime > 0.055
        let enoughGapFromMicro = now - lastMicroTrigger > microCooldown

        let safeEnergy = max(energyEMA, 0.0001)
        let safePeak = max(peakEMA, 0.0001)
        let safeHigh = max(highEMA, 0.0001)
        let safeMid = max(midEMA, 0.0001)

        let relativeEnergy = basic.rms / safeEnergy
        let relativePeak = basic.peak / safePeak
        let trebleBoost = fft.high / safeHigh
        let highVsMid = fft.high / safeMid

        let condition =
            relativeEnergy > 1.01 &&
            relativePeak > 1.00 &&
            basic.zcr > 0.04 &&
            (trebleBoost > 1.05 || highVsMid > 0.85)

        guard enoughGapFromBeat && enoughGapFromMicro && condition else { return }
        lastMicroTrigger = now

        let mIntensity = min(max((relativeEnergy - 1.0) * 0.30 + 0.08, 0.08), 0.18)
        let mSharpness = min(max(basic.zcr * 2.0 + highVsMid * 0.08, 0.18), 0.38)

        playHaptic(style: .microTap, intensity: mIntensity, sharpness: mSharpness)
    }

    // MARK: - 햅틱 재생

    private func playHaptic(style: HapticStyle, intensity: Float, sharpness: Float) {
        switch style {
        case .tap:             playTap(intensity, sharpness)
        case .doubleTap:       playDoubleTap(intensity, sharpness)
        case .softContinuous:  playContinuous(intensity * 0.75, sharpness * 0.45, duration: 0.24, intensityFloor: 0.18)
        case .buzzContinuous:  playContinuous(intensity * 0.90, sharpness * 0.50, duration: 0.34, intensityFloor: 0.20)
        case .rising:          playRising(intensity, sharpness)
        case .microTap:        playTap(max(intensity, 0.05), max(sharpness, 0.08))
        }
    }

    private func playTap(_ intensity: Float, _ sharpness: Float) {
        guard let engine = hapticEngine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        try? engine.makePlayer(with: try CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
    }

    private func playDoubleTap(_ intensity: Float, _ sharpness: Float) {
        guard let engine = hapticEngine else { return }
        let first = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        let second = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: max(intensity * 0.72, 0.12)),
                .init(parameterID: .hapticSharpness, value: min(sharpness * 0.95, 1.0))
            ],
            relativeTime: 0.09
        )
        try? engine.makePlayer(with: try CHHapticPattern(events: [first, second], parameters: [])).start(atTime: 0)
    }

    private func playContinuous(_ intensity: Float, _ sharpness: Float, duration: TimeInterval, intensityFloor: Float) {
        guard let engine = hapticEngine else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: max(intensity, intensityFloor)),
                .init(parameterID: .hapticSharpness, value: max(sharpness, 0.05))
            ],
            relativeTime: 0,
            duration: duration
        )
        try? engine.makePlayer(with: try CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
    }

    private func playRising(_ intensity: Float, _ sharpness: Float) {
        guard let engine = hapticEngine else { return }
        let baseI = max(intensity * 0.35, 0.12)
        let baseS = max(sharpness * 0.35, 0.08)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: baseI),
                .init(parameterID: .hapticSharpness, value: baseS)
            ],
            relativeTime: 0,
            duration: 0.22
        )
        let iCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0,    value: baseI),
                .init(relativeTime: 0.12, value: min(intensity * 0.75, 1.0)),
                .init(relativeTime: 0.22, value: min(intensity, 1.0))
            ],
            relativeTime: 0
        )
        let sCurve = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                .init(relativeTime: 0,    value: baseS),
                .init(relativeTime: 0.22, value: min(sharpness, 1.0))
            ],
            relativeTime: 0
        )
        try? engine.makePlayer(with: try CHHapticPattern(events: [event], parameterCurves: [iCurve, sCurve])).start(atTime: 0)
    }
}
