import Foundation

struct HermesSessionSummary: Identifiable, Equatable {
    let id: String
    let preview: String
    let lastActive: Date
    let messageCount: Int
}
