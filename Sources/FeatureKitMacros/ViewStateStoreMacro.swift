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
            throw ViewStateStoreMacroError.notAStruct
        }

        let structName = structDecl.name.text
        let storeName = "\(structName)Store"
        let legacyStoreName = "\(storeName)Legacy"
        let modernStoreName = "\(storeName)Modern"
        let modernAdapterName = "\(storeName)ModernAdapter"
        let backendProtocolName = "\(storeName)Backend"
        let properties = try ViewStateStoreMacroSupport.storedProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw ViewStateStoreMacroError.noStoredProperties
        }

        let accessPrefix = ViewStateStoreMacroSupport.accessPrefix(for: structDecl)

        let backendProtocolRequirements = properties.map { property in
            "var \(property.name): \(property.type) { get set }"
        }
        .joined(separator: "\n    ")

        let backendProtocol = """
            @MainActor
            fileprivate protocol \(backendProtocolName): AnyObject {
                var onChange: (() -> Void)? { get set }
                var snapshot: \(structName) { get }
                func apply(_ state: \(structName))
                \(backendProtocolRequirements)
            }
            """

        let facadeForwardedProperties = properties.map { property in
            """
            \(accessPrefix)var \(property.name): \(property.type) {
                get { backend.\(property.name) }
                set { backend.\(property.name) = newValue }
            }
            """
        }
        .joined(separator: "\n\n    ")

        let facadeStore = """
            @MainActor
            \(accessPrefix)final class \(storeName): ViewStateStoreNotifying, ObservableObject {
                public typealias State = \(structName)

                public var onChange: (() -> Void)?

                private let backend: any \(backendProtocolName)

                \(facadeForwardedProperties)

                public init() {
                    if #available(iOS 17, macOS 14, *) {
                        backend = \(modernAdapterName)(store: \(modernStoreName)())
                    } else {
                        backend = \(legacyStoreName)()
                    }
                    bindBackend()
                }

                public init(_ state: \(structName)) {
                    if #available(iOS 17, macOS 14, *) {
                        backend = \(modernAdapterName)(store: \(modernStoreName)(state))
                    } else {
                        backend = \(legacyStoreName)(state)
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
                    backend.onChange = { [weak self] in
                        self?.objectWillChange.send()
                        self?.onChange?()
                    }
                }
            }
            """

        let legacyStore = ViewStateStoreLegacyGenerator.make(
            structName: structName,
            storeName: storeName,
            legacyStoreName: legacyStoreName,
            backendProtocolName: backendProtocolName,
            properties: properties
        )

        let modernPeers = ViewStateStoreModernGenerator.make(
            structName: structName,
            modernStoreName: modernStoreName,
            modernAdapterName: modernAdapterName,
            backendProtocolName: backendProtocolName,
            properties: properties
        )

        return [
            DeclSyntax(stringLiteral: backendProtocol),
            DeclSyntax(stringLiteral: legacyStore),
            DeclSyntax(stringLiteral: modernPeers),
            DeclSyntax(stringLiteral: facadeStore),
        ]
    }
}
