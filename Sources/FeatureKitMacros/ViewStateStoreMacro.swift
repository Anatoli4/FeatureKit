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
        let properties = try storedProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw MacroError.noStoredProperties
        }

        let publishedProperties = properties.map { property in
            let defaultValue = property.defaultValue ?? property.defaultLiteral
            return """
                @Published public var \(property.name): \(property.type) = \(defaultValue)
                """
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
            }
            """
        }
        .joined(separator: "\n        ")

        let generated = """
            @MainActor
            final class \(storeName): ViewStateStore, ObservableObject {
                public typealias State = \(structName)

                \(publishedProperties)

                public init() {}

                public init(_ state: \(structName)) {
                    \(stateInitAssignments)
                }

                public var snapshot: \(structName) {
                    \(structName)(\(snapshotArguments))
                }

                public func apply(_ state: \(structName)) {
                    \(applyDiffs)
                }
            }
            """

        return [DeclSyntax(stringLiteral: generated)]
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
