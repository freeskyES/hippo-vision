//
//  HippoToggleStyle.swift
//  HippoMac
//
//  Reusable toggle style component
//

import SwiftUI

struct HippoToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isOn ? Color("HippoPrimary") : Color.gray.opacity(0.3))
                    .frame(width: 42, height: 24)

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            }
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
