import Foundation

@MainActor
public protocol BaseFeatureProtocol: AnyObject {
    associatedtype Store: ViewStateStore
    associatedtype Action

    var viewState: Store { get }
}
