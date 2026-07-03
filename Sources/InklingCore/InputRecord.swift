import Foundation

/// One captured typing input: the final text of a single focus session in a
/// text field. Canonical personalization record — PersonalMemory is derived
/// from these. Codable for encrypted on-disk storage.
public struct InputRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var appBundleID: String?
    public var text: String
    public var hadAcceptedCompletion: Bool

    public init(
        id: UUID,
        timestamp: Date,
        appBundleID: String?,
        text: String,
        hadAcceptedCompletion: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.text = text
        self.hadAcceptedCompletion = hadAcceptedCompletion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        hadAcceptedCompletion = try c.decodeIfPresent(Bool.self, forKey: .hadAcceptedCompletion) ?? false
    }
}
