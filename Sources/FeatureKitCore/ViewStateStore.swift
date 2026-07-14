import Foundation

/// Observable storage for a `ViewState` struct with per-field updates.
@MainActor
public protocol ViewStateStore: AnyObject {
    associatedtype State: ViewState & Equatable

    var snapshot: State { get }

    func apply(_ state: State)
}
