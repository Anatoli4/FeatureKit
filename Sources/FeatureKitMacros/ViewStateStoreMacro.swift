import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

public struct ViewStateStoreMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.notAStruct
        }

        let structName = structDecl.name.text
        let storeName = "\(structName)Store"
        let legacyStoreName = "\(storeName)Legacy"
        let modernStoreName = "\(storeName)Modern"
        let properties = try storedProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw MacroError.noStoredProperties
        }

        let accessLevel = structDecl.modifiers.first { modifier in
            modifier.name.text == "public" || modifier.name.text == "package" || modifier.name.text == "internal"
        }?.name.text ?? ""

        let accessPrefix = accessLevel.isEmpty ? "" : "\(accessLevel) "

        let legacyPublishedProperties = properties.map { property in
            let defaultValue = property.defaultValue ?? property.defaultLiteral
            return """
                @Published public var \(property.name): \(property.type) = \(defaultValue)
                """
        }
        .joined(separator: "\n    ")

        let modernProperties = properties.map { property in
            let defaultValue = property.defaultValue ?? property.defaultLiteral
            return "public var \(property.name): \(property.type) = \(defaultValue)"
        }
        .joined(separator: "\n    ")

        let stateInitAssignments = properties.map { property in
            "self.\(property.name) = state.\(property.name)"
        }
        .joined(separator: "\n        ")

        let snapshotArguments = properties.map { property in
            "\(property.name): \(property.name)"
        }
        .joined(separator: ", ")

        let applyDiffs = properties.map { property in
            """
            if \(property.name) != state.\(property.name) {
                \(property.name) = state.\(property.name)
                didChange = true
            }
            """
        }
        .joined(separator: "\n        ")

        let forwardedProperties = properties.map { property in
            """
            \(accessPrefix)var \(property.name): \(property.type) {
                get {
                    switch backend {
                    case .legacy(let store):
                        return store.\(property.name)
                    case .modern(let store):
                        return store.\(property.name)
                    }
                }
                set {
                    switch backend {
                    case .legacy(let store):
                        store.\(property.name) = newValue
                    case .modern(let store):
                        store.\(property.name) = newValue
                    }
                }
            }
            """
        }
        .joined(separator: "\n\n    ")

        let legacyStore = """
            @MainActor
            fileprivate final class \(legacyStoreName): ViewStateStoreNotifying, ObservableObject {
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

        let backendEnum = """
            @MainActor
            fileprivate enum \(storeName)Backend {
                case legacy(\(legacyStoreName))
                case modern(\(modernStoreName))

                var snapshot: \(structName) {
                    switch self {
                    case .legacy(let store):
                        return store.snapshot
                    case .modern(let store):
                        return store.snapshot
                    }
                }

                func apply(_ state: \(structName)) {
                    switch self {
                    case .legacy(let store):
                        store.apply(state)
                    case .modern(let store):
                        store.apply(state)
                    }
                }

                func setOnChange(_ handler: @escaping () -> Void) {
                    switch self {
                    case .legacy(let store):
                        store.onChange = handler
                    case .modern(let store):
                        store.onChange = handler
                    }
                }
            }
            """

        let facadeStore = """
            @MainActor
            \(accessPrefix)final class \(storeName): ViewStateStoreNotifying, ObservableObject {
                public typealias State = \(structName)

                public var onChange: (() -> Void)?

                private var backend: \(storeName)Backend

                \(forwardedProperties)

                public init() {
                    if #available(iOS 17, macOS 14, *) {
                        backend = .modern(\(modernStoreName)())
                    } else {
                        backend = .legacy(\(legacyStoreName)())
                    }
                    bindBackend()
                }

                public init(_ state: \(structName)) {
                    if #available(iOS 17, macOS 14, *) {
                        backend = .modern(\(modernStoreName)(state))
                    } else {
                        backend = .legacy(\(legacyStoreName)(state))
                    }
                    bindBackend()
                }

                public var snapshot: \(structName) {
                    backend.snapshot
                }

                public func apply(_ state: \(structName)) {
                    backend.apply(state)
                }

                private func bindBackend() {
                    backend.setOnChange { [weak self] in
                        self?.objectWillChange.send()
                        self?.onChange?()
                    }
                }
            }
            """

        return [
            DeclSyntax(stringLiteral: legacyStore),
            DeclSyntax(stringLiteral: modernStore),
            DeclSyntax(stringLiteral: backendEnum),
            DeclSyntax(stringLiteral: facadeStore),
        ]
    }

    private static func storedProperties(from structDecl: StructDeclSyntax) throws -> [PropertyInfo] {
        var properties: [PropertyInfo] = []

        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard variable.bindingSpecifier.tokenKind == .keyword(.var) else { continue }
            guard !variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else { continue }

            for binding in variable.bindings {
                guard binding.accessorBlock == nil else { continue }
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }

                let name = identifier.identifier.text
                let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription
                let defaultValue = binding.initializer?.value.trimmedDescription

                guard let type = typeAnnotation ?? inferredType(from: defaultValue) else {
                    throw MacroError.missingTypeAnnotation(identifier: name)
                }

                properties.append(
                    PropertyInfo(
                        name: name,
                        type: type,
                        defaultValue: defaultValue
                    )
                )
            }
        }

        return properties
    }

    private static func inferredType(from defaultValue: String?) -> String? {
        guard let defaultValue else { return nil }

        switch defaultValue {
        case "true", "false":
            return "Bool"
        case "nil":
            return nil
        case let value where value.hasPrefix("\""):
            return "String"
        case let value where Int(value) != nil:
            return "Int"
        case let value where Double(value) != nil:
            return "Double"
        default:
            return nil
        }
    }
}

private struct PropertyInfo {
    let name: String
    let type: String
    let defaultValue: String?

    var defaultLiteral: String {
        if let defaultValue {
            return defaultValue
        }

        if type.hasSuffix("?") {
            return "nil"
        }

        if type == "Bool" {
            return "false"
        }

        if type == "String" {
            return "\"\""
        }

        return "\(type)()"
    }
}

private enum MacroError: Error, CustomStringConvertible {
    case notAStruct
    case noStoredProperties
    case missingTypeAnnotation(identifier: String)

    var description: String {
        switch self {
        case .notAStruct:
            return "@ViewStateStore can only be applied to a struct."
        case .noStoredProperties:
            return "@ViewStateStore requires at least one stored `var` property."
        case .missingTypeAnnotation(let identifier):
            return "@ViewStateStore property `\(identifier)` needs an explicit type or a default value that can be inferred."
        }
    }
}

private extension SyntaxProtocol {
    var trimmedDescription: String {
        trimmed.description
    }
}
