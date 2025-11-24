import SwiftUI

struct NoDataSection: View {
    var icon: String = "doc.text"
    var text: String = NSLocalizedString("Misc_No_Data", comment: "")
    var iconSize: CGFloat = 30
    var spacing: CGFloat = 8

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: spacing) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize))
                        .foregroundColor(.secondary)
                    Text(text)
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            }
        }
    }
}
