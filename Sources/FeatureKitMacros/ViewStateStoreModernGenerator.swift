enum ViewStateStoreModernGenerator {
    static func make(
        structName: String,
        modernStoreName: String,
        modernAdapterName: String,
        backendProtocolName: String,
        properties: [ViewStateStorePropertyInfo]
    ) -> String {
        let modernProperties = properties.map { property in
            let defaultValue = property.defaultValue ?? property.defaultLiteral
            return "public var \(property.name): \(property.type) = \(defaultValue)"
        }
        .joined(separator: "\n    ")

        let adapterForwardedProperties = properties.map { property in
            """
            public var \(property.name): \(property.type) {
                get { store.\(property.name) }
                set { store.\(property.name) = newValue }
            }
            """
        }
        .joined(separator: "\n\n    ")

        let stateInitAssignments = ViewStateStoreMacroSupport.stateInitAssignments(for: properties)
        let snapshotArguments = ViewStateStoreMacroSupport.snapshotArguments(for: properties)
        let applyDiffs = ViewStateStoreMacroSupport.applyDiffs(for: properties)

        let modernStore = """
            @available(iOS 17, macOS 14, *)
            @MainActor
            @Observable
            fileprivate final class \(modernStoreName): ViewStateStoreNotifying {
                public typealias State = \(structName)

                @ObservationIgnored
                public var onChange: (() -> Void)?

                \(modernProperties)

                public init() {}

                public init(_ state: \(structName)) {
                    \(stateInitAssignments)
                }

                public var snapshot: \(structName) {
                    \(structName)(\(snapshotArguments))
                }

                public func apply(_ state: \(structName)) {
                    var didChange = false
                    \(applyDiffs)
                    if didChange {
                        onChange?()
                    }
                }
            }
            """

        let modernAdapter = """
            @available(iOS 17, macOS 14, *)
            @MainActor
            fileprivate final class \(modernAdapterName): \(backendProtocolName) {
                public typealias State = \(structName)

                private let store: \(modernStoreName)

                public var onChange: (() -> Void)? {
                    get { store.onChange }
                    set { store.onChange = newValue }
                }

                init(store: \(modernStoreName)) {
                    self.store = store
                }

                public var snapshot: \(structName) {
                    store.snapshot
                }

                public func apply(_ state: \(structName)) {
                    store.apply(state)
                }

                \(adapterForwardedProperties)
            }
            """

        return modernStore + "\n" + modernAdapter
    }
}
