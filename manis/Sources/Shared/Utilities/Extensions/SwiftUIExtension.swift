//
//  https://github.com/tokijh/ViewCondition (MIT)
//

import SwiftUI

public extension View {
    @ViewBuilder
    func `if`(
        _ condition: @autoclosure @escaping () -> Bool,
        @ViewBuilder content: (Self) -> some View,
    ) -> some View {
        if condition() {
            content(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`<Value>(
        `let` value: Value?,
        @ViewBuilder content: (_ view: Self, _ value: Value) -> some View,
    ) -> some View {
        if let value {
            content(self, value)
        } else {
            self
        }
    }

    @ViewBuilder
    func ifNot(
        _ notCondition: @autoclosure @escaping () -> Bool,
        @ViewBuilder content: (Self) -> some View,
    ) -> some View {
        if notCondition() {
            self
        } else {
            content(self)
        }
    }

    @ViewBuilder
    func then(@ViewBuilder content: (Self) -> some View) -> some View {
        content(self)
    }
}
