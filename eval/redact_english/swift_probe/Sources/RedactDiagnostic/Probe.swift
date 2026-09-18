import Foundation
import DesertAnt
@_spi(RedactBindings) import Redact

struct Window: Codable, Sendable {
    let realTokens: Int
    let outputShape: [Int]
    let finiteValues: Int
    let nonfiniteValues: Int
    let finiteAbsoluteMax: Float
    let argmaxHistogram: [String: Int]
}

actor ObservedSession: InferenceSession {
    let wrapped: any InferenceSession
    var windows: [Window] = []
    init(_ wrapped: any InferenceSession) { self.wrapped = wrapped }
    nonisolated func inputWidth(_ name: String) -> Int? { wrapped.inputWidth(name) }
    func run(inputs: [String: Tensor], outputs: [String], deviceId: String?) async throws -> [Tensor] {
        // The official factory supplies a usage-tracked session. Observe aggregate
        // diagnostics only; do not replace inference or change its tensors.
        if let path = ProcessInfo.processInfo.environment["REDACT_DIAGNOSTIC_INPUTS"] {
            // Optional local-only token IDs for tokenizer parity. Never include
            // this file in reports, Git, CI artifacts or model training.
            let raw = inputs.mapValues { $0.int32Values ?? [] }
            let data = try Foundation.JSONEncoder().encode(raw) + Data([10])
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
        let result = try await wrapped.run(inputs: inputs, outputs: outputs, deviceId: deviceId)
        let values = result[0].float32Values ?? []
        let finite = values.filter(\.isFinite)
        let real = inputs["attention_mask"]?.int32Values?.filter { $0 == 1 }.count ?? 0
        let labels = result[0].shape.last ?? 0
        var histogram: [String: Int] = [:]
        if labels > 0 {
            for token in 0..<real {
                let start = token * labels
                if start + labels > values.count { break }
                let row = Array(values[start..<(start + labels)])
                if row.allSatisfy(\.isFinite), let maximum = row.max(), let top = row.firstIndex(of: maximum) {
                    histogram[String(top), default: 0] += 1
                } else {
                    histogram["nonfinite_row", default: 0] += 1
                }
            }
        }
        windows.append(Window(realTokens: real, outputShape: result[0].shape,
            finiteValues: finite.count, nonfiniteValues: values.count - finite.count,
            finiteAbsoluteMax: finite.map { abs($0) }.max() ?? 0, argmaxHistogram: histogram))
        return result
    }
    func drain() -> [Window] { let result = windows; windows = []; return result }
}

struct Row: Codable {
    let id: String
    let inputUtf8Bytes: Int
    let labels: [String]
    let windows: [Window]
}
struct Report: Codable {
    let sdkSource: String
    let computeUnits: String
    let rows: [Row]
}

@main struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("Usage: RedactDiagnostic MODEL_DIRECTORY OUTPUT_JSON") }
        let directory = URL(fileURLWithPath: args[1])
        if let path = ProcessInfo.processInfo.environment["REDACT_DIAGNOSTIC_INPUTS"] {
            guard FileManager.default.createFile(atPath: path, contents: Data()) else {
                fatalError("Cannot initialize diagnostic input capture")
            }
        }
        let session = try inferenceSession(modelPath: directory.appendingPathComponent(RedactModel.artifact).path,
                                          sdk: RedactModel.sdkInfo)
        let observed = ObservedSession(session)
        let assets = ModelAssets(tokenizer: Array(try Data(contentsOf: directory.appendingPathComponent(RedactModel.tokenizer))),
            labelsJSON: try String(contentsOf: directory.appendingPathComponent(RedactModel.labels), encoding: .utf8),
            session: observed)
        let redact = Redact(assets: assets)
        let contact = "Contact Rachel Chen in London at rachel.chen@example.test."
        let filler = "The worker finished the ordinary background task. "
        var rows: [Row] = []
        for count in [0, 1, 3, 5, 10, 50] {
            let text = String(repeating: filler, count: count) + contact
            let result = try await redact.redaction(of: text)
            rows.append(Row(id: "prefix_\(count)", inputUtf8Bytes: text.utf8.count,
                            labels: result.items.map { $0.label.rawValue }, windows: await observed.drain()))
        }
        let encoder = Foundation.JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = Report(sdkSource: "c015d5d95028caba783e802442e30ddd66c9247e",
            computeUnits: ProcessInfo.processInfo.environment["DAL_COREML_COMPUTE_UNITS"] ?? "SDK default", rows: rows)
        try encoder.encode(report).write(to: URL(fileURLWithPath: args[2]))
        print("Saved aggregate tensor diagnostics for \(rows.count) cases.")
    }
}
