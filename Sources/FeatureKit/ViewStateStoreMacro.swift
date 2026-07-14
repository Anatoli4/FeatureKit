/// Generates an `ObservableObject` store with per-field `@Published` properties
/// and a diffing `apply(_:)` for the annotated struct.
///
/// ```swift
/// @ViewStateStore
/// struct SplashViewState: ViewState, Equatable {
///     var isLoading = true
///     var errorMessage: String?
/// }
/// // expands to `SplashViewStateStore`
/// ```
@attached(peer, names: suffixed(Store))
public macro ViewStateStore() = #externalMacro(module: "FeatureKitMacros", type: "ViewStateStoreMacro")
