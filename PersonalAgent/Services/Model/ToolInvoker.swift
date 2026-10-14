import Foundation
import FoundationModels

/// Drives a registered tool from provider-neutral JSON arguments — the adapter
/// a non-Apple provider needs for tool calling (tools stay untouched, the
/// provider adapts to them). Apple's `LanguageModelSession` calls tools itself
/// and does not go through here. Only registered tools are callable, and
/// arguments that do not decode into the tool's declared `Arguments` never
/// reach the tool.
enum ToolInvoker {
    static func invoke(toolNamed name: String, in tools: [any Tool], argumentsJSON: String) async throws -> String {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw LanguageModelError.toolCallFailed(
                toolName: name,
                details: "Unbekanntes Werkzeug – nur registrierte Werkzeuge dürfen aufgerufen werden."
            )
        }
        return try await invoke(tool, argumentsJSON: argumentsJSON)
    }

    static func invoke(_ tool: any Tool, argumentsJSON: String) async throws -> String {
        try await invokeTyped(tool, argumentsJSON: argumentsJSON)
    }

    private static func invokeTyped<T: Tool>(_ tool: T, argumentsJSON: String) async throws -> String {
        let arguments: T.Arguments
        do {
            let content = try GeneratedContent(json: argumentsJSON)
            arguments = try T.Arguments(content)
        } catch {
            throw LanguageModelError.toolCallFailed(
                toolName: tool.name,
                details: "Ungültige Argumente: \(error.localizedDescription)"
            )
        }
        do {
            let output = try await tool.call(arguments: arguments)
            return output as? String ?? String(describing: output)
        } catch {
            throw LanguageModelError.toolCallFailed(toolName: tool.name, details: error.localizedDescription)
        }
    }
}
