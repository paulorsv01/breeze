import Foundation

enum HelperIdentity {
    static let appID = "com.breeze.fancontrol"
    static let helperID = "com.breeze.fancontrol.Helper"
    static let plistName = "com.breeze.fancontrol.Helper.plist"
}

@objc protocol BreezeHelperProtocol {
    func applyPreset(_ preset: String, configuration: Data, reply: @escaping (Data?, String?) -> Void)
    func heartbeat(reply: @escaping (Data?, String?) -> Void)
    func restore(reply: @escaping (Data?, String?) -> Void)
}
