import CryptoKit
import Foundation

/// EventKit identifies items by string; the domain uses UUIDs. Deriving the
/// UUID from the external ID keeps identities stable across fetches.
enum DeterministicID {
    static func uuid(forExternalID externalID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(externalID.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}
