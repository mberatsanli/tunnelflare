//
//  Logger.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

/// Unified logging utility using Apple's os.log framework.
///
/// This provides structured logging with different categories for better
/// filtering and debugging in Console.app and Xcode.
///
/// ## Categories
/// - `app`: General application events
/// - `api`: API request/response logging
/// - `process`: Process management events
/// - `auth`: Authentication events
/// - `ui`: UI-related logging
/// - `notifications`: Notification events
/// - `keychain`: Keychain operations
///
/// ## Usage
/// ```swift
/// Logger.app.info("Application started")
/// Logger.api.debug("Request: GET /tunnels")
/// Logger.auth.error("Authentication failed: \(error.localizedDescription)")
/// ```
extension Logger {
    /// Subsystem identifier for all loggers.
    private static let subsystem = LogConstants.subsystem

    // MARK: - Logger Categories

    /// Logger for general application events.
    ///
    /// Use for:
    /// - Application lifecycle (launch, terminate)
    /// - Configuration changes
    /// - General status updates
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Logger for API request/response logging.
    ///
    /// Use for:
    /// - API request details (method, endpoint)
    /// - Response status and timing
    /// - Rate limiting events
    /// - API errors
    static let api = Logger(subsystem: subsystem, category: "api")

    /// Logger for process management events.
    ///
    /// Use for:
    /// - cloudflared process lifecycle
    /// - Process start/stop events
    /// - Crash detection
    /// - Health monitoring
    static let process = Logger(subsystem: subsystem, category: "process")

    /// Logger for authentication events.
    ///
    /// Use for:
    /// - API Token validation
    /// - Login/logout events
    /// - Session restoration
    /// - Authentication errors
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Logger for UI-related events.
    ///
    /// Use for:
    /// - View lifecycle
    /// - User interactions
    /// - Navigation events
    /// - State changes affecting UI
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Logger for notification events.
    ///
    /// Use for:
    /// - Notification delivery
    /// - User notification actions
    /// - Permission changes
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// Logger for Keychain operations.
    ///
    /// Use for:
    /// - Keychain save/retrieve/delete
    /// - Keychain errors
    /// - Security-related events
    static let keychain = Logger(subsystem: subsystem, category: "keychain")

    /// Logger for tunnel-specific events.
    ///
    /// Use for:
    /// - Tunnel state changes
    /// - Connection events
    /// - Tunnel-specific errors
    static let tunnel = Logger(subsystem: subsystem, category: "tunnel")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Logs a message with timing information.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - startTime: The start time of the operation.
    func timing(_ message: String, since startTime: Date) {
        let elapsed = Date().timeIntervalSince(startTime)
        let elapsedMs = Int(elapsed * 1000)
        self.info("\(message) (\(elapsedMs)ms)")
    }

    /// Logs an operation with automatic timing.
    ///
    /// - Parameters:
    ///   - operation: Description of the operation.
    ///   - work: The work to perform.
    /// - Returns: The result of the work.
    func timed<T>(_ operation: String, work: () throws -> T) rethrows -> T {
        let start = Date()
        defer {
            timing("\(operation) completed", since: start)
        }
        self.debug("Starting: \(operation)")
        return try work()
    }

    /// Logs an async operation with automatic timing.
    ///
    /// - Parameters:
    ///   - operation: Description of the operation.
    ///   - work: The async work to perform.
    /// - Returns: The result of the work.
    func timedAsync<T>(_ operation: String, work: () async throws -> T) async rethrows -> T {
        let start = Date()
        defer {
            timing("\(operation) completed", since: start)
        }
        self.debug("Starting: \(operation)")
        return try await work()
    }
}

// MARK: - Log Level Helpers

/// Represents log levels for filtering.
enum LogLevel: String, CaseIterable, Codable {
    case debug = "DBG"
    case info = "INF"
    case warning = "WRN"
    case error = "ERR"

    /// The display name for the log level.
    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    /// The system image name for the log level.
    var systemImage: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    /// The OSLogType corresponding to this level.
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

// MARK: - Debug Logging Helpers

#if DEBUG
/// Debug-only logging functions that are stripped from release builds.
enum DebugLog {
    /// Logs a debug message only in DEBUG builds.
    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        Logger.app.debug("[\(filename):\(line)] \(function) - \(message)")
    }

    /// Logs memory usage for debugging.
    static func logMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024 / 1024
            Logger.app.debug("Memory usage: \(String(format: "%.1f", usedMB)) MB")
        }
    }

    /// Logs the current thread for debugging concurrency issues.
    static func logThread(_ label: String) {
        let threadName = Thread.current.isMainThread ? "Main" : (Thread.current.name ?? "Background")
        Logger.app.debug("\(label) - Thread: \(threadName)")
    }
}
#endif

// MARK: - Sensitive Data Redaction

extension Logger {
    /// Logs a message with sensitive data redacted.
    ///
    /// Use this when logging information that might contain sensitive data.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - sensitiveValues: Values that should be redacted.
    func redacted(_ message: String, sensitiveValues: [String]) {
        var redactedMessage = message
        for value in sensitiveValues {
            redactedMessage = redactedMessage.replacingOccurrences(of: value, with: "[REDACTED]")
        }
        self.info("\(redactedMessage)")
    }
}

// MARK: - Structured Logging Helpers

extension Logger {
    /// Logs an API request.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - path: The request path.
    ///   - requestId: Optional request identifier for correlation.
    func logRequest(method: String, path: String, requestId: String? = nil) {
        if let requestId = requestId {
            self.info("[\(requestId)] \(method) \(path)")
        } else {
            self.info("\(method) \(path)")
        }
    }

    /// Logs an API response.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - path: The request path.
    ///   - duration: The request duration.
    ///   - requestId: Optional request identifier for correlation.
    func logResponse(statusCode: Int, path: String, duration: TimeInterval, requestId: String? = nil) {
        let durationMs = Int(duration * 1000)
        if let requestId = requestId {
            self.info("[\(requestId)] \(statusCode) \(path) (\(durationMs)ms)")
        } else {
            self.info("\(statusCode) \(path) (\(durationMs)ms)")
        }
    }
}
