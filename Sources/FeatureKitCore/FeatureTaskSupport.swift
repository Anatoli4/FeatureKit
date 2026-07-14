import Foundation

@MainActor
public final class FeatureTaskSupport<Action> {
    private var observationTasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    deinit {
        observationTasks.values.forEach { $0.cancel() }
    }

    @discardableResult
    public func runOnMain(
        priority: TaskPriority? = nil,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let task = Task(priority: priority) { @MainActor in
            await operation()
        }
        store(task)
        return task
    }

    @discardableResult
    public func run(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void,
        onMain: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        let task = Task.detached(priority: priority) {
            await operation()
            await onMain()
        }
        store(task)
        return task
    }

    @discardableResult
    public func run<T: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> T,
        onResult: @escaping @MainActor (T) -> Void
    ) -> Task<Void, Never> {
        let task = Task.detached(priority: priority) {
            let value = await operation()
            await onResult(value)
        }
        store(task)
        return task
    }

    @discardableResult
    public func observe(
        id: UUID = UUID(),
        stream: AsyncStream<Action>,
        send: @escaping @MainActor (Action) -> Void
    ) -> Task<Void, Never> {
        cancelObservation(id: id)
        let task = Task { @MainActor in
            for await action in stream {
                send(action)
            }
        }
        observationTasks[id] = task
        return task
    }

    @discardableResult
    public func observe<S: AsyncSequence>(
        id: UUID = UUID(),
        sequence: S,
        send: @escaping @MainActor (Action) -> Void,
        action: @escaping (S.Element) -> Action
    ) -> Task<Void, Never> where S.Element: Sendable {
        cancelObservation(id: id)
        let task = Task { @MainActor in
            do {
                for try await element in sequence {
                    send(action(element))
                }
            } catch {
                return
            }
        }
        observationTasks[id] = task
        return task
    }

    @discardableResult
    public func observe<T: Sendable>(
        id: UUID = UUID(),
        stream: AsyncStream<T>,
        send: @escaping @MainActor (Action) -> Void,
        action: @escaping (T) -> Action
    ) -> Task<Void, Never> {
        cancelObservation(id: id)
        let task = Task { @MainActor in
            for await element in stream {
                send(action(element))
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
