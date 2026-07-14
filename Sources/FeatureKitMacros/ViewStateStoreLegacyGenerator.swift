enum ViewStateStoreLegacyGenerator {
    static func make(
        structName: String,
        storeName: String,
        legacyStoreName: String,
        backendProtocolName: String,
        properties: [ViewStateStorePropertyInfo]
    ) -> String {
        let legacyPublishedProperties = properties.map { property in
            let defaultValue = property.defaultValue ?? property.defaultLiteral
            return """
                @Published public var \(property.name): \(property.type) = \(defaultValue)
                """
        }
        .joined(separator: "\n    ")

        let stateInitAssignments = ViewStateStoreMacroSupport.stateInitAssignments(for: properties)
        let snapshotArguments = ViewStateStoreMacroSupport.snapshotArguments(for: properties)
        let applyDiffs = ViewStateStoreMacroSupport.applyDiffs(for: properties)

        return """
            @MainActor
            fileprivate final class \(legacyStoreName): \(backendProtocolName), ObservableObject {
                public typealias State = \(structName)

                public var onChange: (() -> Void)?

                \(legacyPublishedProperties)

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
    }
}
