import SwiftUI
import Foundation

struct StarMapView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var regions: [StarMapRegion] = []
    @State private var allRegions: [StarMapRegion] = [] // 存储所有星域数据用于搜索
    @State private var showRegionMap = false
    @State private var availableRegionIds: Set<Int> = []
    @State private var searchText = ""
    
    var filteredRegions: [StarMapRegion] {
        if searchText.isEmpty {
            return regions
        } else {
            return allRegions.filter { region in
                region.name.localizedCaseInsensitiveContains(searchText) ||
                region.nameEn.localizedCaseInsensitiveContains(searchText) ||
                region.nameZh.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 星域列表
            List {
                // Section 1: 星域图跳转
                Section {
                    NavigationLink(value: "region_map") {
                        Label(NSLocalizedString("Main_Star_Map", comment: "星域图"), systemImage: "map")
                    }
                }
                // Section 2: 星域列表
                Section(header: Text(NSLocalizedString("Main_Language_Map_Type_Region", comment: ""))) {
                    if filteredRegions.isEmpty && !searchText.isEmpty {
                        // 搜索无结果提示
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                Text(NSLocalizedString("StarMap_No_Results", comment: "未找到匹配的星域"))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 40)
                            Spacer()
                        }
                    } else {
                        ForEach(filteredRegions) { region in
                            NavigationLink(value: RegionNavigation.regionMap(region.id, region.name)) {
                                Text(region.name)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Star_Map", comment: "星图"))
        .navigationDestination(for: String.self) { value in
            if value == "region_map" {
                RegionMapView(databaseManager: databaseManager)
            }
        }
        .navigationDestination(for: RegionNavigation.self) { navigation in
            switch navigation {
            case .regionMap(let regionId, let regionName):
                RegionSystemMapView(databaseManager: databaseManager, regionId: regionId, regionName: regionName)
            }
        }
        .onAppear(perform: loadData)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("StarMap_Search_Region", comment: "搜索星域"))
        )
    }
    
    private func loadData() {
        loadRegionData()
        loadRegions()
    }
    
    private func loadRegionData() {
        guard let url = Bundle.main.url(forResource: "regions_data", withExtension: "json") else {
            Logger.error("无法找到 regions_data.json 文件")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let regionDataArray = try JSONDecoder().decode([RegionData].self, from: data)
            self.availableRegionIds = Set(regionDataArray.map { $0.region_id })
            Logger.info("加载了 \(availableRegionIds.count) 个可用星域ID")
        } catch {
            Logger.error("解析 regions_data.json 失败: \(error)")
            self.availableRegionIds = []
        }
    }
    
    private func loadRegions() {
        let sql = "SELECT regionID, regionName, regionName_en, regionName_zh FROM regions"
        if case let .success(rows) = DatabaseManager.shared.executeQuery(sql) {
            let allRegionsData = rows.compactMap { (row: [String: Any]) -> StarMapRegion? in
                guard let id = row["regionID"] as? Int, 
                      let name = row["regionName"] as? String,
                      let nameEn = row["regionName_en"] as? String,
                      let nameZh = row["regionName_zh"] as? String,
                      availableRegionIds.contains(id) else { 
                    return nil
                }
                return StarMapRegion(id: id, name: name, nameEn: nameEn, nameZh: nameZh)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            
            self.allRegions = allRegionsData
            self.regions = allRegionsData
            Logger.info("过滤后显示 \(regions.count) 个星域")
        } else {
            self.allRegions = []
            self.regions = []
        }
    }
} 
