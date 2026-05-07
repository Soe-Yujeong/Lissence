import Foundation

struct TrainingStats {
    let means: [Float]
    let stds: [Float]

    static func load() -> TrainingStats {
        NSLog("TrainingStats.load() called")

        guard let url = Bundle.main.url(forResource: "train_stats_segments_improved", withExtension: "json") else {
            NSLog("stats file NOT found")
            return TrainingStats(means: [0, 0, 0], stds: [1, 1, 1])
        }

        NSLog("stats file found: \(url)")

        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("stats json read failed")
            return TrainingStats(means: [0, 0, 0], stds: [1, 1, 1])
        }

        let meanKeys = ["channel_mean", "channel_means", "means", "mean"]
        let stdKeys = ["channel_std", "channel_stds", "stds", "std"]

        let means = readArray(object, keys: meanKeys) ?? [0, 0, 0]
        let stds = readArray(object, keys: stdKeys) ?? [1, 1, 1]

        let finalMeans = fit3(means, fallback: [0, 0, 0])
        let finalStds = fit3(stds, fallback: [1, 1, 1])

        NSLog("stats loaded means: \(finalMeans)")
        NSLog("stats loaded stds: \(finalStds)")

        return TrainingStats(
            means: finalMeans,
            stds: finalStds
        )
    }

    private static func readArray(_ object: [String: Any], keys: [String]) -> [Float]? {
        for key in keys {
            if let array = object[key] as? [Double] {
                return array.map { Float($0) }
            }

            if let array = object[key] as? [Float] {
                return array
            }

            if let array = object[key] as? [NSNumber] {
                return array.map { $0.floatValue }
            }
        }

        return nil
    }

    private static func fit3(_ values: [Float], fallback: [Float]) -> [Float] {
        if values.count >= 3 {
            return Array(values.prefix(3))
        }

        if values.count == 1 {
            return [values[0], values[0], values[0]]
        }

        return fallback
    }
}
