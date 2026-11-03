import BreezeCore

actor SensorReader {
    private var connection: SMCConnection?

    func snapshot() throws -> FanSnapshot {
        if connection == nil { connection = try SMCConnection() }
        guard let connection else { throw FanError.unavailable("SMC unavailable.") }
        return try connection.snapshot()
    }
}
