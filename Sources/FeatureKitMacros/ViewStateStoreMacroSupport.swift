import SwiftSyntax

struct ViewStateStorePropertyInfo {
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

enum ViewStateStoreMacroError: Error, CustomStringConvertible {
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

enum ViewStateStoreMacroSupport {
    static func storedProperties(from structDecl: StructDeclSyntax) throws -> [ViewStateStorePropertyInfo] {
        var properties: [ViewStateStorePropertyInfo] = []

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
                    throw ViewStateStoreMacroError.missingTypeAnnotation(identifier: name)
                }

                properties.append(
                    ViewStateStorePropertyInfo(
                        name: name,
                        type: type,
                        defaultValue: defaultValue
                    )
                )
            }
        }

        return properties
    }

    static func accessPrefix(for structDecl: StructDeclSyntax) -> String {
        let accessLevel = structDecl.modifiers.first { modifier in
            modifier.name.text == "public" || modifier.name.text == "package" || modifier.name.text == "internal"
        }?.name.text ?? ""

        return accessLevel.isEmpty ? "" : "\(accessLevel) "
    }

    static func stateInitAssignments(for properties: [ViewStateStorePropertyInfo]) -> String {
        properties.map { property in
            "self.\(property.name) = state.\(property.name)"
        }
        .joined(separator: "\n        ")
    }

    static func snapshotArguments(for properties: [ViewStateStorePropertyInfo]) -> String {
        properties.map { property in
            "\(property.name): \(property.name)"
        }
        .joined(separator: ", ")
    }

    static func applyDiffs(for properties: [ViewStateStorePropertyInfo]) -> String {
        properties.map { property in
            """
            if \(property.name) != state.\(property.name) {
                \(property.name) = state.\(property.name)
                didChange = true
            }
            """
        }
        .joined(separator: "\n        ")
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

private extension SyntaxProtocol {
    var trimmedDescription: String {
        trimmed.description
    }
}
