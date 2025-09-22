import SwiftUI

struct CalculatorView: View {
    @StateObject private var databaseManager = DatabaseManager.shared

    var body: some View {
        List {
            NavigationLink(destination: BlueprintCalculatorView()) {
                HStack {
                    Image("industry")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)

                    Text(NSLocalizedString("Calculator_Blueprint", comment: ""))
                        .font(.body)
                }
            }

            NavigationLink(destination: OreRefineryCalculatorView(databaseManager: databaseManager)) {
                HStack {
                    Image("reprocess")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)

                    Text(NSLocalizedString("Calculator_Ore_Refinery", comment: ""))
                        .font(.body)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Calculator_Title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }
}
