import FeatureKit
import Testing

@ViewStateStore
struct CounterViewState: ViewState, Equatable {
    var count = 0
    var label: String = "items"
}

private enum CounterAction {
    case increment
}

@MainActor
private final class CounterFeature: BaseFeature<CounterViewStateStore, CounterAction> {
    init() {
        super.init(viewState: CounterViewStateStore())
    }

    override func reduceState(with action: CounterAction) -> CounterViewState {
        switch action {
        case .increment:
            viewState.snapshot.with(\.count, viewState.count + 1)
        }
    }
}

@Test
@MainActor
func viewStateStoreAppliesOnlyChangedFields() {
    let store = CounterViewStateStore(CounterViewState(count: 1, label: "items"))

    store.apply(CounterViewState(count: 2, label: "items"))

    #expect(store.count == 2)
    #expect(store.label == "items")
    #expect(store.snapshot == CounterViewState(count: 2, label: "items"))
}

@Test
@MainActor
func baseFeatureUsesViewStateStore() {
    let feature = CounterFeature()
    feature.send(with: .increment)

    #expect(feature.viewState.count == 1)
}
