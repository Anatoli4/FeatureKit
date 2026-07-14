import Foundation

@MainActor
public protocol ViewStateStoreNotifying: AnyObject, ViewStateStore {
    var onChange: (() -> Void)? { get set }
}
