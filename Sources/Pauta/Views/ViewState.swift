import SwiftUI

/// O mesmo que @State. No SDK atual @State virou macro, e o plugin dele só vem com o Xcode;
/// como o build usa só as CommandLineTools, embrulhamos o State à mão.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private var state: State<Value>

    init(wrappedValue: Value) {
        state = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { state.projectedValue }
}
