# FeatureKit

A lightweight reducer-style layer for screens: immutable `ViewState`, `Action` events, and `BaseFeature` as an `ObservableObject`.

**iOS 15+** · Swift 6

---

## Installation

### XcodeGen (`project.yml`)

```yaml
packages:
  FeatureKit:
    path: ../FeatureKit   # relative to your app's project.yml

targets:
  MyApp:
    dependencies:
      - package: FeatureKit
```

### Swift Package Manager (from another package)

```swift
dependencies: [
    .package(path: "../FeatureKit"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: ["FeatureKit"]
    ),
]
```

---

## Concepts

```
View  ──onAppear / tap──▶  Feature.send(Action)
                              │
                              ▼
                         reduceState(Action) → ViewState struct
                              │
                              ▼
                         ViewStateStore.apply  ──▶  per-field @Published
                              │
                              ▼
                         View re-renders
```

| Type | Role |
|------|------|
| `ViewState` | Immutable UI snapshot (struct, `Equatable`) |
| `@ViewStateStore` | Macro that generates an `ObservableObject` store |
| `Action` | Events: taps, API results, timers |
| `BaseFeature` | Holds store, runs reducer, manages async subscriptions |

`@ViewStateStore` generates a single `<Name>Store` facade. Under the hood it picks the right backend at runtime:

| OS | Backend | Mechanism |
|----|---------|-----------|
| iOS 15–16 / macOS 12–13 | `*StoreLegacy` | `ObservableObject` + `@Published` |
| iOS 17+ / macOS 14+ | `*StoreModern` | `@Observable` |

You only use `SplashViewStateStore` — legacy/modern types are `fileprivate`.

**Combine** is only used for `@Published` on the legacy path and for `BaseFeature`. Feature logic uses **`async/await`** — no `sink` / `cancellables` in features.

---

## Example: Splash screen

### ViewState and Action

```swift
import FeatureKit

@ViewStateStore
struct SplashViewState: ViewState, Equatable {
    var isLoading = true
    var errorMessage: String?
}

enum SplashAction {
    case setLoading(Bool)
    case setError(String?)
}
```

`@ViewStateStore` expands to `SplashViewStateStore` — a facade over a platform-specific store with `isLoading`, `errorMessage`, `snapshot`, and `apply(_:)`.

### Feature

```swift
import FeatureKit
import Factory

@MainActor
final class SplashFeature: BaseFeature<SplashViewStateStore, SplashAction> {
    private let router: SplashRouter

    @Injected(\.configService) private var configService

    init(router: SplashRouter) {
        self.router = router
        super.init(viewState: SplashViewStateStore())
    }

    override func reduceState(with action: SplashAction) -> SplashViewState {
        switch action {
        case .setLoading(let isLoading):
            viewState.snapshot.with(\.isLoading, isLoading)
        case .setError(let message):
            viewState.snapshot.with(\.errorMessage, message)
        }
    }

    func onAppear() {
        send(with: .setLoading(true))

        run(
            operation: { [configService] () async -> Result<Void, Error> in
                Result { try await configService.load() }
            },
            onResult: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    router.routeToMain()
                case .failure(let error):
                    send(with: .setError(error.localizedDescription))
                }
                send(with: .setLoading(false))
            }
        )
    }
}
```

### View (iOS 15+)

```swift
import SwiftUI

struct SplashView: View {
    @FeatureState private var feature: SplashFeature

    private var state: SplashViewStateStore { feature.viewState }

    init(feature: SplashFeature) {
        _feature = FeatureState(wrappedValue: feature)
    }

    var body: some View {
        ZStack {
            if state.isLoading {
                ProgressView()
            }
            if let error = state.errorMessage {
                Text(error)
            }
        }
        .onAppear(perform: feature.onAppear)
    }
}
```

`@FeatureState` wraps `@StateObject` today. On iOS 17+ apps you can also hold the feature with `@State` when using `@Observable` stores directly.

---

## `Withable` — updating state

Immutable style (inside `reduceState`):

```swift
viewState.snapshot.with(\.isLoading, false)
```

Mutable style on the struct snapshot:

```swift
var state = viewState.snapshot
state.update { $0.isLoading = false }
send(with: .setLoading(false))  // prefer updating state only via send
```

---

## Async API

### `run` / `runOnMain` — one-shot side effects

Background work with main-actor completion (network, disk, heavy logic):

```swift
run(priority: .userInitiated, operation: { try await api.fetch() }) { [weak self] items in
    self?.send(with: .loaded(items))
}
```

Side effects that should stay on the main actor (navigation, quick UI work):

```swift
runOnMain(priority: .userInitiated) { [weak self] in
    await self?.purchase()
}
```

Both tasks are cancelled when the feature is deallocated.

### `observe` — event stream → actions

Service exposes `AsyncStream`:

```swift
// UserService.swift
var currentUserStream: AsyncStream<UserModel?> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let id = observer.register { user in
            continuation.yield(user)
        }
        continuation.onTermination = { _ in observer.unregister(id) }
        continuation.yield(storage.currentUser)
    }
}

// MainFeature.swift
private let userObservationID = UUID()

func onAppear() {
    observe(id: userObservationID, stream: userService.currentUserStream) { user in
        .userUpdated(user)
    }
}

deinit {
    cancelObservation(id: userObservationID)
}
```

Calling `observe(id: same, ...)` again cancels the previous observation with that `id`.

### `AsyncSequence` (e.g. `publisher.values` during migration)

```swift
observe(sequence: userService.currentUserPublisher.values) { user in
    .userUpdated(user)
}
```

### Cancellation

```swift
cancelObservation(id: userObservationID)
cancelAllObservations()
```

---

## Migration checklist (Combine → async in features)

| Before | After |
|--------|-------|
| `.sink { }.store(in: &cancellables)` | `observe(stream:)` / `run` / `runOnMain` |
| `public var cancellables` | not needed |
| `send(on: publisher)` | `observe(stream:)` or `observe(sequence:)` |
| `CurrentValueSubject` in services | `AsyncStream` + `yield` |

Remove `import Combine` from features; keep it in services only while migrating.

---

## API reference

### `@ViewStateStore`

Macro on a `struct` with stored `var` properties. Generates a public `<StructName>Store` facade:

- iOS 15–16: `ObservableObject` + `@Published` backend
- iOS 17+: `@Observable` backend
- `snapshot` — current struct value
- `apply(_:)` — updates only changed fields

Properties need an explicit type or a default value the macro can infer (`true`/`false` → `Bool`, string literal → `String`).

### `FeatureState`

Property wrapper for features in SwiftUI. Uses `@StateObject` under the hood on iOS 15+.

### `ViewStateStore`

Protocol implemented by generated stores.

### `Withable`

- `with(_:value:)` — returns a copy of the struct with one field changed

### `ViewState`

- `update(_:)` — in-place mutation via copy-writeback

### `BaseFeature<Store, Action>`

| Member | Description |
|--------|-------------|
| `viewState` | Generated `ViewStateStore` instance |
| `send(with:)` | `reduceState` → `viewState.apply` |
| `reduceState(with:)` | Override in subclass, returns struct |
| `run(priority:operation:onMain:)` | Background `Task`, completion on `@MainActor` |
| `run(priority:operation:onResult:)` | Background `Task`, result on `@MainActor` |
| `runOnMain(priority:operation:)` | Main-actor `Task` |
| `observe(id:stream:)` | `AsyncStream<Action>` |
| `observe(id:stream:action:)` | `AsyncStream<T>` → `Action` |
| `observe(id:sequence:action:)` | Any `AsyncSequence` |
| `cancelObservation(id:)` | Cancel one subscription |
| `cancelAllObservations()` | Cancel all subscriptions |

---

## Performance

- `send` skips `apply` when the reducer returns an equal snapshot.
- `apply` publishes only fields that actually changed.
- `for await` does not spawn extra threads; observations run on `@MainActor`.
- For “latest value only” in services: `AsyncStream(bufferingPolicy: .bufferingNewest(1))`.

---

## Package layout

```
FeatureKit/
├── Package.swift
├── Sources/
│   ├── FeatureKitCore/
│   │   ├── Withable.swift
│   │   ├── ViewStateStore.swift
│   │   ├── ViewStateStoreNotifying.swift
│   │   ├── FeatureStateSupport.swift
│   │   ├── FeatureTaskSupport.swift
│   │   └── BaseFeatureProtocol.swift
│   ├── FeatureKit/
│   │   ├── BaseFeature.swift
│   │   ├── FeatureState.swift
│   │   ├── ViewStateStoreMacro.swift
│   │   └── Exports.swift
│   └── FeatureKitMacros/
│       ├── Plugin.swift
│       └── ViewStateStoreMacro.swift
└── Tests/FeatureKitTests/
```
