import FeatureKitCore
import SwiftUI

@propertyWrapper
public struct FeatureState<Feature: BaseFeatureProtocol & ObservableObject>: DynamicProperty {
    @StateObject private var feature: Feature

    public init(wrappedValue: @autoclosure @escaping () -> Feature) {
        _feature = StateObject(wrappedValue: wrappedValue())
    }

    public var wrappedValue: Feature {
        feature
    }

    public var projectedValue: Feature {
        feature
    }
}
