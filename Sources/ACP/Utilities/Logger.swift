//
//  Logger+ACP.swift
//  ACP
//
//  Logging utility for ACP.
//

import os

extension Logger {
    private static let acpSubsystem = OSAllocatedUnfairLock(initialState: "com.acp")

    /// Configures the logging subsystem used by subsequently created ACP loggers.
    public static func configureACPLogging(subsystem: String) {
        acpSubsystem.withLock { $0 = subsystem }
    }

    /// Creates a logger for a specific category.
    public static func forCategory(_ category: String) -> Logger {
        let subsystem = acpSubsystem.withLock { $0 }
        return Logger(subsystem: subsystem, category: category)
    }

    /// Convenience logger for ACP.
    public static let acp = Logger.forCategory("ACP")
}
