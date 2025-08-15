import SwiftUI

struct LPSearchResultsView: View {
    let searchText: String
    let searchResults: (factions: [Faction], corporations: [Corporation])
    let lpSearchResults: [LPSearchResult]
    
    var body: some View {
        List {
            // 势力搜索结果
            if !searchResults.factions.isEmpty {
                Section(NSLocalizedString("Main_LP_Store_Factions", comment: "")) {
                    ForEach(searchResults.factions) { faction in
                        NavigationLink(destination: FactionLPDetailView(faction: faction)) {
                            HStack {
                                IconManager.shared.loadImage(for: faction.iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36)
                                Text(faction.name)
                                    .padding(.leading, 8)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            
            // 军团搜索结果
            if !searchResults.corporations.isEmpty {
                Section(NSLocalizedString("Main_LP_Store_Corps", comment: "")) {
                    ForEach(searchResults.corporations) { corporation in
                        NavigationLink(
                            destination: CorporationLPStoreView(
                                corporationId: corporation.id,
                                corporationName: corporation.name
                            )
                        ) {
                            HStack {
                                CorporationIconView(corporationId: corporation.id, iconFileName: corporation.iconFileName, size: 36)
                                Text(corporation.name)
                                    .padding(.leading, 8)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            
            // 物品类别搜索结果
            if !lpSearchResults.isEmpty {
                Section(NSLocalizedString("Main_LP_Available_Items", comment: "可用物品")) {
                    ForEach(lpSearchResults, id: \.categoryId) { category in
                        NavigationLink(
                            destination: LPSearchCategoryView(
                                categoryName: category.categoryName,
                                offers: category.offers
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: category.categoryIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36)
                                    .cornerRadius(6)
                                Text(category.categoryName)
                                    .padding(.leading, 8)
                                
                                Spacer()
                                Text("\(category.offerCount)")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            
            // 无搜索结果
            if searchResults.factions.isEmpty && searchResults.corporations.isEmpty && lpSearchResults.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Search_Results", comment: "搜索结果"))
        .navigationBarTitleDisplayMode(.inline)
    }
} 
