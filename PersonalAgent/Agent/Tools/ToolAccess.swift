/// Every tool declares read-only or mutation. Mutation tools never apply
/// their effect inside `call` — they deposit a proposal that only an explicit
/// user confirmation in the app executes.
enum ToolAccess: Sendable {
    case readOnly
    case mutation
}

protocol AccessDeclaring {
    static var access: ToolAccess { get }
}

extension GetOpenTasksTool: AccessDeclaring {
    static var access: ToolAccess { .readOnly }
}

extension GetTaskStatisticsTool: AccessDeclaring {
    static var access: ToolAccess { .readOnly }
}

extension FindFreeTimeTool: AccessDeclaring {
    static var access: ToolAccess { .readOnly }
}

extension GetReminderRecommendationTool: AccessDeclaring {
    static var access: ToolAccess { .readOnly }
}

extension ScheduleNotificationTool: AccessDeclaring {
    static var access: ToolAccess { .mutation }
}

extension CreateReminderTool: AccessDeclaring {
    static var access: ToolAccess { .mutation }
}
