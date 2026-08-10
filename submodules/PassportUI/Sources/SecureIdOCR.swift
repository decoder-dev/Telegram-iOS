import Foundation
import UIKit
import ImageIO
import Vision
import SwiftSignalKit

enum SecureIdOCR {
    static func recognizeData(in image: UIImage, shouldBeDriversLicense: Bool) -> Signal<SecureIdMRZ?, NoError> {
        let initial = shouldBeDriversLicense ? recognizeBarcode(in: image) : recognizeMRZ(in: image)
        let fallback = shouldBeDriversLicense ? recognizeMRZ(in: image) : recognizeBarcode(in: image)
        return initial
        |> mapToSignal { value -> Signal<SecureIdMRZ?, NoError> in
            if let value {
                return .single(value)
            }
            return fallback
        }
    }

    private static func recognizeMRZ(in image: UIImage) -> Signal<SecureIdMRZ?, NoError> {
        guard let cgImage = image.cgImage else {
            return .single(nil)
        }

        return Signal { subscriber in
            if #available(iOS 13.0, *) {
                let request = VNRecognizeTextRequest { request, _ in
                    let strings = (request.results ?? []).compactMap { observation -> String? in
                        (observation as? VNRecognizedTextObservation)?.topCandidates(1).first?.string
                    }
                    subscriber.putNext(parseRecognizedMRZLines(strings))
                    subscriber.putCompletion()
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]
                request.preferBackgroundProcessing = true

                Queue.concurrentDefaultQueue().async {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation, options: [:])
                    try? handler.perform([request])
                }

                return ActionDisposable {
                    request.cancel()
                }
            } else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
        }
    }

    private static func recognizeBarcode(in image: UIImage) -> Signal<SecureIdMRZ?, NoError> {
        guard #available(iOS 11.0, *), let cgImage = image.cgImage else {
            return .single(nil)
        }

        return Signal { subscriber in
            let request = VNDetectBarcodesRequest { request, _ in
                var result: SecureIdMRZ?
                for observation in request.results ?? [] {
                    guard let barcode = observation as? VNBarcodeObservation, barcode.symbology == .pdf417, let payload = barcode.payloadStringValue else {
                        continue
                    }
                    if let parsed = SecureIdMRZ.parseBarcodePayload(payload) {
                        result = parsed
                        break
                    }
                }
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
            request.preferBackgroundProcessing = true

            Queue.concurrentDefaultQueue().async {
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation, options: [:])
                try? handler.perform([request])
            }

            return ActionDisposable {
                if #available(iOS 13.0, *) {
                    request.cancel()
                }
            }
        }
    }

    private static func parseRecognizedMRZLines(_ strings: [String]) -> SecureIdMRZ? {
        let candidateLines = strings
            .flatMap { $0.components(separatedBy: .newlines) }
            .map(normalizeMRZLine)
            .filter { !$0.isEmpty }
            .flatMap(expandedCandidateLines)

        for index in candidateLines.indices where index + 1 < candidateLines.count {
            if let result = SecureIdMRZ.parseLines([candidateLines[index], candidateLines[index + 1]]) {
                return result
            }
        }
        for index in candidateLines.indices where index + 2 < candidateLines.count {
            if let result = SecureIdMRZ.parseLines([candidateLines[index], candidateLines[index + 1], candidateLines[index + 2]]) {
                return result
            }
        }
        return nil
    }

    private static func expandedCandidateLines(_ line: String) -> [String] {
        var result: [String] = []
        if line.count == 44 || line.count == 30 {
            result.append(line)
        }
        if line.count > 44 {
            for offset in 0 ... (line.count - 44) {
                result.append(line.substring(from: offset, length: 44))
            }
        }
        if line.count > 30 {
            for offset in 0 ... (line.count - 30) {
                result.append(line.substring(from: offset, length: 30))
            }
        }
        return result
    }

    private static func normalizeMRZLine(_ string: String) -> String {
        var result = ""
        for scalar in string.uppercased().unicodeScalars {
            if (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 48 && scalar.value <= 57) {
                result.unicodeScalars.append(scalar)
            } else if scalar == "<" || scalar == "‹" || scalar == "〈" {
                result.append("<")
            }
        }
        return result
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self.imageOrientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}

private extension String {
    func substring(from offset: Int, length: Int) -> String {
        if offset < 0 || length <= 0 || offset >= self.count {
            return ""
        }
        let lower = self.index(self.startIndex, offsetBy: offset)
        let upper = self.index(lower, offsetBy: min(length, self.distance(from: lower, to: self.endIndex)))
        return String(self[lower ..< upper])
    }
}
