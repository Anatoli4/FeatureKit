import Combine
import Foundation

@preconcurrency @MainActor
open class BaseFeature<ViewStateType: ViewState, Action>: ObservableObject {
    @Published
    public private(set) var viewState: ViewStateType

    private var observationTasks: [UUID: Task<Void, Never>] = [:]

    public init(viewState: ViewStateType) {
        self.viewState = viewState
    }

    deinit {
        observationTasks.values.forEach { $0.cancel() }
    }

    public func send(with action: Action) {
        viewState = reduceState(with: action)
    }

    open func reduceState(with action: Action) -> ViewStateType {
        fatalError("reduceState(with:) must be overridden in \(String(describing: Self.self))")
    }

    /// Runs a one-shot async side effect on the main actor. The task is cancelled when the feature is deallocated.
    @discardableResult
    public func run(
        priority: TaskPriority? = nil,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let task = Task(priority: priority) { @MainActor in
            await operation()
        }
        store(task)
        return task
    }

    /// Maps stream elements to actions. Cancels the previous observation with the same `id`.
    @discardableResult
    public func observe(
        id: UUID = UUID(),
        stream: AsyncStream<Action>
    ) -> Task<Void, Never> {
        cancelObservation(id: id)
        let task = Task { @MainActor [weak self] in
            for await action in stream {
                guard let self else { return }
                send(with: action)
            }
        }
        observationTasks[id] = task
        return task
    }

    /// Maps async sequence elements to actions. Cancels the previous observation with the same `id`.
    @discardableResult
    public func observe<S: AsyncSequence>(
        id: UUID = UUID(),
        sequence: S,
        action: @escaping (S.Element) -> Action
    ) -> Task<Void, Never> where S.Element: Sendable {
        cancelObservation(id: id)
        let task = Task { @MainActor [weak self] in
            do {
                for try await element in sequence {
                    guard let self else { return }
                    send(with: action(element))
                }
            } catch {
                return
            }
        }
        observationTasks[id] = task
        return task
    }

    /// Maps async stream elements to actions. Cancels the previous observation with the same `id`.
    @discardableResult
    public func observe<T: Sendable>(
        id: UUID = UUID(),
        stream: AsyncStream<T>,
        action: @escaping (T) -> Action
    ) -> Task<Void, Never> {
        cancelObservation(id: id)
        let task = Task { @MainActor [weak self] in
            for await element in stream {
                guard let self else { return }
                send(with: action(element))
            }
        }
        observationTasks[id] = task
        return task
    }

    public func cancelObservation(id: UUID) {
        observationTasks[id]?.cancel()
        observationTasks[id] = nil
    }

    public func cancelAllObservations() {
        observationTasks.values.forEach { $0.cancel() }
        observationTasks.removeAll()
    }

    private func store(_ task: Task<Void, Never>) {
        let id = UUID()
        observationTasks[id] = task
    }
}
