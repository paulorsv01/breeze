import BreezeCore
import Foundation

do {
    let smc = try SMCConnection()
    let snapshot = try smc.snapshot()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
