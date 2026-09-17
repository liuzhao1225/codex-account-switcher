import Foundation

/// A prepared user action. Contains presentation data and target IDs only.
public struct SwitchConfirmation: Encodable, Equatable, Sendable {
    public let accountID: UUID?
    public let providerID: String?
    public let title: String
    public let message: String
    public let confirmTitle: String
}
