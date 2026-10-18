import Foundation
import HHTCore

// Offline replay of the production inference engine for calibration (issue #46).
// Never writes to the input database; see docs/research/inference-calibration.md.

let usage = """
usage: hht-calibrate replay --db <travel.sqlite> --out <predictions.json>
                            [--config <partial-config.json>] [--mode batch|streaming] [--step <seconds>] [--end <ISO-8601>]
       hht-calibrate reinfer-check --db <travel.sqlite> [--out <check.json>]
                                       re-run inference on a private copy; report any human-edited record it changed
       hht-calibrate config            print the default InferenceConfig as JSON
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }
args.removeFirst()
var opts: [String: String] = [:]
while !args.isEmpty {
    let k = args.removeFirst()
    guard k.hasPrefix("--"), !args.isEmpty else { fail("bad argument '\(k)'\n" + usage) }
    opts[String(k.dropFirst(2))] = args.removeFirst()
}

do {
    switch command {
    case "config":
        print(String(data: try ReplayResult.encoder().encode(InferenceConfig.default), encoding: .utf8)!)
    case "replay":
        guard let db = opts["db"], let out = opts["out"] else { fail(usage) }
        let config = try Replay.config(overridingWith: opts["config"].map { try Data(contentsOf: URL(fileURLWithPath: $0)) })
        let mode: Replay.Mode
        switch opts["mode"] ?? "batch" {
        case "batch": mode = .batch
        case "streaming": mode = .streaming(step: Double(opts["step"] ?? "900") ?? 900)
        default: fail("unknown mode\n" + usage)
        }
        let end = try opts["end"].map { s -> Date in
            guard let d = ISO8601DateFormatter().date(from: s) else { throw ReplayError.badConfig("bad --end '\(s)'") }
            return d
        }
        let input = try Replay.loadInput(databaseAt: db)
        let result = try Replay.run(input, config: config, mode: mode, end: end)
        try ReplayResult.encoder().encode(result).write(to: URL(fileURLWithPath: out))
        print("replayed \(result.pointCount) points (\(result.mode), \(result.runs) runs): "
              + "\(result.visits.count) visits, \(result.trips.count) trips → \(out)")
    case "reinfer-check":
        guard let db = opts["db"] else { fail(usage) }
        let r = try Replay.reinferenceCheck(databaseAt: db)
        if let out = opts["out"] { try ReplayResult.encoder().encode(r).write(to: URL(fileURLWithPath: out)) }
        print("locked visits \(r.lockedVisits) (\(r.deletedLockedVisits) deleted), locked trips \(r.lockedTrips); \(r.report)")
        for line in r.changedVisits { print("  visit changed  \(line)") }
        for line in r.missingVisits { print("  visit missing  \(line)") }
        for line in r.changedTrips { print("  trip changed   \(line)") }
        for line in r.missingTrips { print("  trip missing   \(line)") }
        print(r.passed ? "PASS: every human-edited record survived re-inference" : "FAIL: human edits changed by re-inference")
        if !r.passed { exit(1) }
    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
