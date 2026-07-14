/// Generates a platform-specific observable store with per-field updates
/// and a diffing `apply(_:)` for the annotated struct.
///
/// iOS 15–16 / macOS 12–13: `ObservableObject` + `@Published`
/// iOS 17+ / macOS 14+: `@Observable`
///
/// ```swift
/// @ViewStateStore
/// struct SplashViewState: ViewState, Equatable {
///     var isLoading = true
/// }
/// // expands to `SplashViewStateStore`
/// ```
@attached(peer, names: suffixed(Store), suffixed(StoreLegacy), suffixed(StoreModern), suffixed(StoreModernAdapter), suffixed(StoreBackend))
public macro ViewStateStore() = #externalMacro(module: "FeatureKitMacros", type: "ViewStateStoreMacro")
