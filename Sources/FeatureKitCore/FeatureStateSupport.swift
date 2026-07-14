import Foundation

public enum FeatureStateSupport {
    @MainActor
    public static func send<Store: ViewStateStore, Action>(
        with action: Action,
        store: Store,
        reduce: (Action) -> Store.State
    ) {
        let next = reduce(action)
        guard next != store.snapshot else { return }
        store.apply(next)
    }
}
