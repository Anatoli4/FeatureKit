import Combine
import FeatureKitCore
import Foundation

@preconcurrency @MainActor
open class BaseFeature<Store: ViewStateStore, Action>: ObservableObject, BaseFeatureProtocol {
    public let viewState: Store

    private let tasks = FeatureTaskSupport<Action>()

    public init(viewState: Store) {
        self.viewState = viewState
        bindStoreObservation()
    }

    public func send(with action: Action) {
        FeatureStateSupport.send(with: action, store: viewState, reduce: reduceState)
    }

    open func reduceState(with action: Action) -> Store.State {
        fatalError("reduceState(with:) must be overridden in \(String(describing: Self.self))")
    }

    @discardableResult
    public func runOnMain(
        priority: TaskPriority? = nil,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        tasks.runOnMain(priority: priority, operation: operation)
    }

    @discardableResult
    public func run(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void,
        onMain: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        tasks.run(priority: priority, operation: operation, onMain: onMain)
    }

    @discardableResult
    public func run<T: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> T,
        onResult: @escaping @MainActor (T) -> Void
    ) -> Task<Void, Never> {
        tasks.run(priority: priority, operation: operation, onResult: onResult)
    }

    @discardableResult
    public func observe(
        id: UUID = UUID(),
        stream: AsyncStream<Action>
    ) -> Task<Void, Never> {
        tasks.observe(id: id, stream: stream) { [weak self] action in
            self?.send(with: action)
        }
    }

    @discardableResult
    public func observe<S: AsyncSequence>(
        id: UUID = UUID(),
        sequence: S,
        action: @escaping (S.Element) -> Action
    ) -> Task<Void, Never> where S.Element: Sendable {
        tasks.observe(id: id, sequence: sequence, send: { [weak self] in
            self?.send(with: $0)
        }, action: action)
    }

    @discardableResult
    public func observe<T: Sendable>(
        id: UUID = UUID(),
        stream: AsyncStream<T>,
        action: @escaping (T) -> Action
    ) -> Task<Void, Never> {
        tasks.observe(id: id, stream: stream, send: { [weak self] in
            self?.send(with: $0)
        }, action: action)
    }

    public func cancelObservation(id: UUID) {
        tasks.cancelObservation(id: id)
    }

    public func cancelAllObservations() {
        tasks.cancelAllObservations()
    }

    private func bindStoreObservation() {
        guard let notifyingStore = viewState as? any ViewStateStoreNotifying else { return }

        notifyingStore.onChange = { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
