import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct FeatureKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ViewStateStoreMacro.self,
    ]
}
