import Foundation
import Vision

actor BarcodeService {
    func detectQRPayloads(in imageURL: URL) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(url: imageURL, options: [:]).perform([request])
                    var seen = Set<String>()
                    let payloads = request.results?.compactMap { observation -> String? in
                        guard observation.symbology == .qr,
                              let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !payload.isEmpty,
                              seen.insert(payload).inserted
                        else { return nil }
                        return payload
                    } ?? []
                    continuation.resume(returning: payloads)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
