//
//  Debouncer.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import Foundation
import Combine

// MARK: - Debouncer

/// A utility for debouncing actions.
///
/// Debouncer delays execution of an action until a specified time interval
/// has passed without any new calls. This is useful for search fields and
/// other input that should not trigger actions on every keystroke.
///
/// ## Usage
/// ```swift
/// let debouncer = Debouncer(delay: 0.3)
///
/// // In your text field binding
/// TextField("Search", text: $searchText)
///     .onChange(of: searchText) { _, newValue in
///         debouncer.debounce {
///             await performSearch(newValue)
///         }
///     }
/// ```
@MainActor
final class Debouncer {

    // MARK: - Properties

    /// The delay before executing the action.
    private let delay: TimeInterval

    /// The current debounce task.
    private var task: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new debouncer with the specified delay.
    ///
    /// - Parameter delay: The time to wait before executing the action (in seconds).
    init(delay: TimeInterval = 0.3) {
        self.delay = delay
    }

    // MARK: - Public Methods

    /// Debounces an action.
    ///
    /// If called again before the delay has passed, the previous action is cancelled
    /// and the delay restarts.
    ///
    /// - Parameter action: The action to execute after the delay.
    func debounce(action: @escaping () async -> Void) {
        // Cancel any existing task
        task?.cancel()

        // Create a new task with the delay
        task = Task {
            do {
                try await Task.sleep(for: .seconds(delay))

                // Check if task was cancelled during sleep
                guard !Task.isCancelled else { return }

                await action()
            } catch {
                // Task was cancelled - this is expected behavior
            }
        }
    }

    /// Debounces a synchronous action.
    ///
    /// - Parameter action: The action to execute after the delay.
    func debounce(action: @escaping () -> Void) {
        self.debounce(action: { () async -> Void in action() })
    }

    /// Cancels any pending debounced action.
    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - DebouncedText

/// A property wrapper that debounces text changes.
///
/// Use this wrapper for text fields that should not trigger updates on every keystroke.
///
/// ## Usage
/// ```swift
/// @DebouncedText(delay: 0.3) var searchText: String = ""
///
/// TextField("Search", text: $searchText.binding)
///     .onChange(of: searchText) { _, newValue in
///         // This only fires after 0.3s of no typing
///     }
/// ```
@propertyWrapper
@MainActor
final class DebouncedText {

    // MARK: - Properties

    private var value: String
    private let delay: TimeInterval
    private let debouncer: Debouncer
    private var onChange: ((String) -> Void)?

    // MARK: - Initialization

    init(wrappedValue: String = "", delay: TimeInterval = 0.3) {
        self.value = wrappedValue
        self.delay = delay
        self.debouncer = Debouncer(delay: delay)
    }

    // MARK: - Property Wrapper

    var wrappedValue: String {
        get { value }
        set {
            value = newValue
            debouncer.debounce { [weak self] in
                self?.onChange?(newValue)
            }
        }
    }

    var projectedValue: DebouncedText {
        self
    }

    // MARK: - Public Methods

    /// Sets the change handler.
    ///
    /// - Parameter handler: The handler to call when the debounced value changes.
    func onDebouncedChange(_ handler: @escaping (String) -> Void) {
        self.onChange = handler
    }
}
