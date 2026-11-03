import Foundation
import Security

enum CodeIdentity {
    static func peerRequirement(identifier: String) throws -> String {
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode else {
            throw NSError(domain: "Breeze.Signing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not verify the app signature."])
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess, let staticCode else {
            throw NSError(domain: "Breeze.Signing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read the executable signature."])
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw NSError(domain: "Breeze.Signing", code: 2, userInfo: [NSLocalizedDescriptionKey: "The app and service require a valid Apple signing identity."])
        }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
