@_exported import Combine
import Foundation

/// Observable storage for a `ViewState` struct with per-field `@Published` updates.
@MainActor
public protocol ViewStateStore: AnyObject, ObservableObject {
    associatedtype State: ViewState & Equatable

    var snapshot: State { get }

    func apply(_ state: State)
}
