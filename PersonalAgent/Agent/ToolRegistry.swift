import Foundation
import FoundationModels

/// Central tool registry carrying the access
/// declarations. The controller receives exactly the tools registered here —
/// nothing else is callable by the model.
struct ToolRegistry: Sendable {
    struct Entry: Sendable {
        let name: String
        let access: ToolAccess
        let tool: any Tool
    }

    let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }

    var tools: [any Tool] {
        entries.map(\.tool)
    }

    var toolNames: [String] {
        entries.map(\.name)
    }

    var mutationToolNames: [String] {
        entries.filter { $0.access == .mutation }.map(\.name)
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    static func entry<T: Tool & AccessDeclaring>(_ tool: T) -> Entry {
        Entry(name: tool.name, access: T.access, tool: tool)
    }
}
