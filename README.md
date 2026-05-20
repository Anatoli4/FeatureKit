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
                         reduceState(Action) → ViewState
                              │
                              ▼
                         @Published viewState  ──▶  View re-renders
```

| Type | Role |
|------|------|
| `ViewState` | UI snapshot (struct, optionally `Equatable`) |
| `Action` | Events: taps, API results, timers |
| `BaseFeature` | Holds state, runs reducer, manages async subscriptions |

**Combine** is only used for `@Published` (SwiftUI requirement on iOS 15–16). Feature logic uses **`async/await`** — no `sink` / `cancellables`.

---

## Example: Splash screen

### ViewState and Action

```swift
import FeatureKit

struct SplashViewState: ViewState, Equatable {
    var isLoading = true
    var errorMessage: String?
}

enum SplashAction {
    case setLoading(Bool)
    case setError(String?)
}
```

### Feature

```swift
import FeatureKit
import Factory

@MainActor
final class SplashFeature: BaseFeature<SplashViewState, SplashAction> {
    private let router: SplashRouter

    @Injected(\.configService) private var configService

    init(router: SplashRouter) {
        self.router = router
        super.init(viewState: SplashViewState())
    }

    override func reduceState(with action: SplashAction) -> SplashViewState {
        switch action {
        case .setLoading(let isLoading):
            viewState.with(\.isLoading, isLoading)
        case .setError(let message):
            viewState.with(\.errorMessage, message)
        }
    }

    func onAppear() {
        send(with: .setLoading(true))

        run { [weak self] in
            guard let self else { return }
            do {
                try await configService.load()
                router.routeToMain()
            } catch {
                send(with: .setError(error.localizedDescription))
            }
            send(with: .setLoading(false))
        }
    }
}
```

### View (iOS 15+)

```swift
import SwiftUI

struct SplashView: View {
    @StateObject private var feature: SplashFeature

    private var state: SplashViewState { feature.viewState }

    init(feature: SplashFeature) {
        _feature = StateObject(wrappedValue: feature)
    }

    var body: some View {
        ZStack {
            if state.isLoading {
                ProgressView()
            }
        }
        .onAppear(perform: feature.onAppear)
    }
}
```

> On iOS 17+ you can adopt `@Observable` / `@State` separately; FeatureKit currently targets `@StateObject`.

---

## `Withable` — updating state

Immutable style (inside `reduceState`):

```swift
viewState.with(\.isLoading, false)
```

Mutable style (outside reducer):

```swift
var state = viewState
state.update { $0.isLoading = false }
send(with: .setLoading(false))  // prefer updating state only via send
```

---

## Async API

### `run` — one-shot side effect

```swift
run(priority: .userInitiated) { [weak self] in
    await self?.purchase()
}
```

The task is cancelled when the feature is deallocated.

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
| `.sink { }.store(in: &cancellables)` | `observe(stream:)` / `run { }` |
| `public var cancellables` | not needed |
| `send(on: publisher)` | `observe(stream:)` or `observe(sequence:)` |
| `CurrentValueSubject` in services | `AsyncStream` + `yield` |

Remove `import Combine` from features; keep it in services only while migrating.

---

## API reference

### `Withable`

- `with(_:value:)` — returns a copy of the struct with one field changed

### `ViewState`

- `update(_:)` — in-place mutation via copy-writeback

### `BaseFeature<ViewState, Action>`

| Method | Description |
|--------|-------------|
| `send(with:)` | Apply an `Action` through `reduceState` |
| `reduceState(with:)` | Override in subclass |
| `run(priority:operation:)` | Main-actor `Task` |
| `observe(id:stream:)` | `AsyncStream<Action>` |
| `observe(id:stream:action:)` | `AsyncStream<T>` → `Action` |
| `observe(id:sequence:action:)` | Any `AsyncSequence` |
| `cancelObservation(id:)` | Cancel one subscription |
| `cancelAllObservations()` | Cancel all subscriptions |

---

## Performance

- One UI update = one `send` = one `@Published` write.
- `for await` does not spawn extra threads; observations run on `@MainActor`.
- For “latest value only” in services: `AsyncStream(bufferingPolicy: .bufferingNewest(1))`.

---

## Package layout

```
FeatureKit/
├── Package.swift
└── Sources/FeatureKit/
    ├── Withable.swift
    └── BaseFeature.swift
```
