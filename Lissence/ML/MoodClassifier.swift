import Foundation
import CoreML

struct MoodPredictionResult {
    let label: String
    let probabilities: [String: Double]
}

final class MoodClassifier {
    private let model: MLModel
    private let inputName = "input_layer"
    private let fallbackLabels = ["Q1", "Q2", "Q3", "Q4"]

    init() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        if let compiledURL = Bundle.main.url(forResource: "MusicMoodClassifier", withExtension: "mlmodelc") {
            model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } else if let packageURL = Bundle.main.url(forResource: "MusicMoodClassifier", withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: packageURL)
            model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } else {
            throw NSError(domain: "MoodClassifier", code: 1, userInfo: [NSLocalizedDescriptionKey: "MusicMoodClassifier 모델을 찾지 못했습니다."])
        }
    }

    func predict(input: MLMultiArray) throws -> MoodPredictionResult {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: input)
        ])

        let output = try model.prediction(from: provider)

        if let label = output.featureValue(for: "classLabel")?.stringValue {
            let probabilities = readProbabilityDictionary(output) ?? [:]
            return MoodPredictionResult(label: label, probabilities: probabilities)
        }

        if let arrayResult = readMultiArrayOutput(output) {
            return arrayResult
        }

        throw NSError(domain: "MoodClassifier", code: 2, userInfo: [NSLocalizedDescriptionKey: "모델 출력 classLabel 또는 MultiArray를 찾지 못했습니다. 출력 이름: \(output.featureNames.joined(separator: ", "))"])
    }

    private func readProbabilityDictionary(_ output: MLFeatureProvider) -> [String: Double]? {
        for name in output.featureNames {
            guard let value = output.featureValue(for: name), value.type == .dictionary else {
                continue
            }

            var result: [String: Double] = [:]

            for (key, val) in value.dictionaryValue {
                if let label = key as? String {
                    result[label] = val.doubleValue
                } else if let labelNumber = key as? NSNumber {
                    result[labelNumber.stringValue] = val.doubleValue
                }
            }

            if !result.isEmpty {
                return result
            }
        }

        return nil
    }

    private func readMultiArrayOutput(_ output: MLFeatureProvider) -> MoodPredictionResult? {
        for name in output.featureNames {
            guard let array = output.featureValue(for: name)?.multiArrayValue else {
                continue
            }

            let count = array.count
            guard count >= 4 else {
                continue
            }

            var probabilities: [String: Double] = [:]
            var bestIndex = 0
            var bestValue = -Double.infinity

            for i in 0..<min(4, count) {
                let value = array[i].doubleValue
                probabilities[fallbackLabels[i]] = value
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }

            return MoodPredictionResult(label: fallbackLabels[bestIndex], probabilities: probabilities)
        }

        return nil
    }
}
