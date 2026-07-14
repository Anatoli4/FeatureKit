import Foundation

public protocol Withable {}

extension Withable {
    public func with<Value>(
        _ keyPath: WritableKeyPath<Self, Value>,
        _ value: Value
    ) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}

public protocol ViewState: Withable {}

public extension ViewState {
    mutating func update(_ block: (inout Self) -> Void) {
        var copy = self
        block(&copy)
        self = copy
    }
}
