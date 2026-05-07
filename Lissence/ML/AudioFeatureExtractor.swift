import Foundation
import CoreML
import Accelerate

final class AudioFeatureExtractor {
    private let targetSampleRate: Double = 22050
    private let duration: Double = 3.0
    private let nFFT = 2048
    private let hopLength = 512
    private let melBins = 128
    private let mfccBins = 20
    private let targetHeight = 128
    private let targetWidth = 128

    private let means: [Float]
    private let stds: [Float]

    init() {
        let stats = TrainingStats.load()
        means = stats.means
        stds = stats.stds
    }

    func makeInput(samples: [Float], sampleRate: Double) throws -> MLMultiArray {
        let audio = prepareAudio(samples: samples, sampleRate: sampleRate)
        let magnitude = stftMagnitudeScipyLike(audio)
        let power = magnitude.map { row in row.map { $0 * $0 } }

        let spec = amplitudeToDB(magnitude)
        let melPower = applyMelFilter(power)
        let mel = powerToDB(melPower)
        let mfcc = dctType2Ortho(mel, keep: mfccBins)

        let spec128 = resizeArea(spec, newRows: targetHeight, newCols: targetWidth)
        let mfcc128 = resizeArea(mfcc, newRows: targetHeight, newCols: targetWidth)
        let mel128 = resizeArea(mel, newRows: targetHeight, newCols: targetWidth)

        let array = try MLMultiArray(shape: [1, NSNumber(value: targetHeight), NSNumber(value: targetWidth), 3], dataType: .float32)

        for r in 0..<targetHeight {
            for c in 0..<targetWidth {
                let values = [spec128[r][c], mfcc128[r][c], mel128[r][c]]

                for ch in 0..<3 {
                    let value = (values[ch] - means[ch]) / max(stds[ch], 1e-8)
                    let index = r * targetWidth * 3 + c * 3 + ch
                    array[index] = NSNumber(value: value)
                }
            }
        }

        return array
    }

    private func prepareAudio(samples: [Float], sampleRate: Double) -> [Float] {
        let resampled = resampleLinear(samples: samples, from: sampleRate, to: targetSampleRate)
        let targetCount = Int(targetSampleRate * duration)

        if resampled.count >= targetCount {
            return Array(resampled.prefix(targetCount))
        }

        return resampled + [Float](repeating: 0, count: targetCount - resampled.count)
    }

    private func resampleLinear(samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty else {
            return []
        }

        if abs(sourceRate - targetRate) < 1 {
            return samples
        }

        let ratio = targetRate / sourceRate
        let newCount = max(1, Int(Double(samples.count) * ratio))
        var output = [Float](repeating: 0, count: newCount)

        for i in 0..<newCount {
            let sourceIndex = Double(i) / ratio
            let left = Int(floor(sourceIndex))
            let right = min(left + 1, samples.count - 1)
            let frac = Float(sourceIndex - Double(left))
            output[i] = samples[left] * (1 - frac) + samples[right] * frac
        }

        return output
    }

    private func stftMagnitudeScipyLike(_ samples: [Float]) -> [[Float]] {
        let boundaryPad = nFFT / 2
        var padded = [Float](repeating: 0, count: boundaryPad)
        padded.append(contentsOf: samples)
        padded.append(contentsOf: [Float](repeating: 0, count: boundaryPad))

        let remainder = (padded.count - nFFT) % hopLength
        if remainder != 0 {
            let extra = hopLength - remainder
            padded.append(contentsOf: [Float](repeating: 0, count: extra))
        }

        let frameCount = max(1, 1 + (padded.count - nFFT) / hopLength)
        let binCount = nFFT / 2 + 1
        let window = hannWindow(nFFT)
        let windowSum = max(window.reduce(0, +), 1e-10)

        guard let setup = vDSP_create_fftsetup(vDSP_Length(log2(Float(nFFT))), FFTRadix(kFFTRadix2)) else {
            return Array(repeating: [Float](repeating: 0, count: frameCount), count: binCount)
        }

        let log2n = vDSP_Length(log2(Float(nFFT)))
        var result = Array(repeating: [Float](repeating: 0, count: frameCount), count: binCount)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopLength
            var frame = Array(padded[start..<start + nFFT])
            vDSP.multiply(frame, window, result: &frame)

            var real = [Float](repeating: 0, count: nFFT / 2)
            var imag = [Float](repeating: 0, count: nFFT / 2)

            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                    frame.withUnsafeBufferPointer { framePtr in
                        framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(nFFT / 2))
                        }
                    }

                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            result[0][frameIndex] = abs(real[0]) / windowSum
            result[binCount - 1][frameIndex] = abs(imag[0]) / windowSum

            if binCount > 2 {
                for bin in 1..<(binCount - 1) {
                    result[bin][frameIndex] = sqrt(real[bin] * real[bin] + imag[bin] * imag[bin]) / windowSum
                }
            }
        }

        vDSP_destroy_fftsetup(setup)
        return result
    }

    private func amplitudeToDB(_ input: [[Float]]) -> [[Float]] {
        let flat = input.flatMap { $0 }
        let ref = max((flat.max() ?? 0) + 1e-10, 1e-10)
        var output = input
        var maxValue = -Float.greatestFiniteMagnitude

        for r in 0..<output.count {
            for c in 0..<output[r].count {
                let value = 20.0 * log10(max(output[r][c], 1e-10)) - 20.0 * log10(ref)
                output[r][c] = value
                maxValue = max(maxValue, value)
            }
        }

        let floorValue = maxValue - 80.0

        for r in 0..<output.count {
            for c in 0..<output[r].count {
                output[r][c] = max(output[r][c], floorValue)
            }
        }

        return output
    }

    private func powerToDB(_ input: [[Float]]) -> [[Float]] {
        let flat = input.flatMap { $0 }
        let ref = max((flat.max() ?? 0) + 1e-10, 1e-10)
        var output = input
        var maxValue = -Float.greatestFiniteMagnitude

        for r in 0..<output.count {
            for c in 0..<output[r].count {
                let value = 10.0 * log10(max(output[r][c], 1e-10)) - 10.0 * log10(ref)
                output[r][c] = value
                maxValue = max(maxValue, value)
            }
        }

        let floorValue = maxValue - 80.0

        for r in 0..<output.count {
            for c in 0..<output[r].count {
                output[r][c] = max(output[r][c], floorValue)
            }
        }

        return output
    }

    private func applyMelFilter(_ power: [[Float]]) -> [[Float]] {
        let filters = melFilterBankScipyLike()
        let frames = power.first?.count ?? 0
        var output = Array(repeating: [Float](repeating: 0, count: frames), count: melBins)

        for m in 0..<melBins {
            for t in 0..<frames {
                var sum: Float = 0
                for k in 0..<power.count {
                    sum += filters[m][k] * power[k][t]
                }
                output[m][t] = sum
            }
        }

        return output
    }

    private func melFilterBankScipyLike() -> [[Float]] {
        let fmax = Float(targetSampleRate / 2.0)
        let minMel = hzToMel(0)
        let maxMel = hzToMel(fmax)

        var hzPoints = [Float]()
        for i in 0..<(melBins + 2) {
            let mel = minMel + (maxMel - minMel) * Float(i) / Float(melBins + 1)
            hzPoints.append(melToHz(mel))
        }

        let bins = hzPoints.map { hz in
            Int(floor(Float(nFFT + 1) * hz / Float(targetSampleRate)))
        }

        var filters = Array(repeating: [Float](repeating: 0, count: nFFT / 2 + 1), count: melBins)

        for i in 1...(melBins) {
            var left = bins[i - 1]
            var center = bins[i]
            var right = bins[i + 1]

            if center <= left {
                center = left + 1
            }
            if right <= center {
                right = center + 1
            }

            for j in left..<center {
                if j >= 0 && j < filters[i - 1].count {
                    filters[i - 1][j] = Float(j - left) / Float(center - left)
                }
            }

            for j in center..<right {
                if j >= 0 && j < filters[i - 1].count {
                    filters[i - 1][j] = Float(right - j) / Float(right - center)
                }
            }
        }

        for m in 0..<melBins {
            let denom = max(hzPoints[m + 2] - hzPoints[m], 1e-10)
            let enorm = 2.0 / denom
            for k in 0..<filters[m].count {
                filters[m][k] *= enorm
            }
        }

        return filters
    }

    private func dctType2Ortho(_ input: [[Float]], keep: Int) -> [[Float]] {
        let rows = input.count
        let cols = input.first?.count ?? 0

        guard rows > 0, cols > 0 else {
            return Array(repeating: [Float](repeating: 0, count: cols), count: keep)
        }

        var output = Array(repeating: [Float](repeating: 0, count: cols), count: keep)

        for k in 0..<keep {
            let scale = k == 0 ? sqrt(1.0 / Float(rows)) : sqrt(2.0 / Float(rows))

            for t in 0..<cols {
                var sum: Float = 0
                for n in 0..<rows {
                    let angle = Float.pi * Float(k) * (Float(n) + 0.5) / Float(rows)
                    sum += input[n][t] * cos(angle)
                }
                output[k][t] = scale * sum
            }
        }

        return output
    }

    private func resizeArea(_ input: [[Float]], newRows: Int, newCols: Int) -> [[Float]] {
        let rows = input.count
        let cols = input.first?.count ?? 0

        guard rows > 0, cols > 0 else {
            return Array(repeating: [Float](repeating: 0, count: newCols), count: newRows)
        }

        var output = Array(repeating: [Float](repeating: 0, count: newCols), count: newRows)
        let rowScale = Float(rows) / Float(newRows)
        let colScale = Float(cols) / Float(newCols)

        for r in 0..<newRows {
            let rowStart = Float(r) * rowScale
            let rowEnd = Float(r + 1) * rowScale
            let r0 = Int(floor(rowStart))
            let r1 = min(Int(ceil(rowEnd)), rows)

            for c in 0..<newCols {
                let colStart = Float(c) * colScale
                let colEnd = Float(c + 1) * colScale
                let c0 = Int(floor(colStart))
                let c1 = min(Int(ceil(colEnd)), cols)

                var sum: Float = 0
                var weightSum: Float = 0

                for rr in r0..<r1 {
                    let top = max(rowStart, Float(rr))
                    let bottom = min(rowEnd, Float(rr + 1))
                    let rowWeight = max(0, bottom - top)

                    for cc in c0..<c1 {
                        let left = max(colStart, Float(cc))
                        let right = min(colEnd, Float(cc + 1))
                        let colWeight = max(0, right - left)
                        let weight = rowWeight * colWeight
                        sum += input[rr][cc] * weight
                        weightSum += weight
                    }
                }

                output[r][c] = weightSum > 0 ? sum / weightSum : input[min(r0, rows - 1)][min(c0, cols - 1)]
            }
        }

        return output
    }

    private func hannWindow(_ count: Int) -> [Float] {
        (0..<count).map { i in
            0.5 - 0.5 * cos(2 * Float.pi * Float(i) / Float(count))
        }
    }

    private func hzToMel(_ hz: Float) -> Float {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    private func melToHz(_ mel: Float) -> Float {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }
}
