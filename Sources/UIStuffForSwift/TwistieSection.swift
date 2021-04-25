//
//  SectionButton.swift
//  ArcWorld
//
//  Created by Jim Hanson on 4/17/21.
//

import SwiftUI


//struct SectionStatePreferenceKey: PreferenceKey {
//    typealias Value = [SectionState]
//
//    static var defaultValue: [SectionState] = []
//
//    static func reduce(value: inout [SectionState], nextValue: () -> [SectionState]) {
//        value.append(contentsOf: nextValue())
//    }
//}
//
//struct SectionState: Equatable {
//    let nameWidth: CGFloat
//    // let selectedSection: Int
//}

public struct TwistieGroup {

    var selection: String? = nil

    public init() {}

 }

public struct TwistieSection<Content: View> : View {

    let leftInset: CGFloat = 30
    let twistieSize: CGFloat = 30

    let sectionName: String

    var group: Binding<TwistieGroup>

    var sectionContent: () -> Content

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleSelection) {
                Image(systemName: "chevron.right")
                    .frame(width: twistieSize, height: twistieSize)
                    .rotated(by: .degrees(isSelected() ? 90 : 0))

                Text(sectionName)
                    .lineLimit(1)
            }
            .foregroundColor(UIConstants.controlColor)
            .background(RoundedRectangle(cornerRadius: UIConstants.buttonCornerRadius)
                            .opacity(UIConstants.buttonOpacity))
            .padding(UIConstants.buttonPadding)

            if isSelected() {
                sectionContent()
                    .padding(EdgeInsets(top: UIConstants.buttonSpacing, leading: leftInset, bottom: 0, trailing: 0))
            }
        }
    }

    public init(_ sectionName: String, _ group: Binding<TwistieGroup>, @ViewBuilder content: @escaping () -> Content) {
        self.sectionName = sectionName
        self.group = group
        self.sectionContent = content
    }

    func toggleSelection() {
        if group.wrappedValue.selection == sectionName {
            group.wrappedValue.selection = nil
        }
        else {
            group.wrappedValue.selection = sectionName
        }
    }

    func isSelected() -> Bool {
        return group.wrappedValue.selection == self.sectionName
    }
}

//extension VerticalAlignment {
//
//    enum SectionName: AlignmentID {
//        static func defaultValue(in d: ViewDimensions) -> CGFloat {
//            d[.top]
//        }
//    }
//
//    static let sectionName = VerticalAlignment(SectionName.self)
//}

struct SectionButton: View {

    var sectionName: String

    var sectionID: Int

    var selectedSection: Binding<Int>

    var body: some View {

        Button(action: {
            selectedSection.wrappedValue = sectionID
        }) {
            Image(systemName: "chevron.right")
                .rotated(by: .degrees((sectionID == selectedSection.wrappedValue ? 90 : 0)))

            Text(sectionName)
                .lineLimit(1)

            Spacer()

        }
    }

    init(_ name: String, _ id: Int, _ selectedSection: Binding<Int>) {
        self.sectionName = name
        self.sectionID = id
        self.selectedSection = selectedSection
    }
}
