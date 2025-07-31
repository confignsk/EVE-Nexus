import SwiftUI
import Foundation

struct StarMapView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var regions: [StarMapRegion] = []
    @State private var showRegionMap = false
    @State private var availableRegionIds: Set<Int> = []
    
    var body: some View {
        List {
            // Section 1: 星域图跳转
            Section {
                NavigationLink(value: "region_map") {
                    Label(NSLocalizedString("Main_Star_Map", comment: "星域图"), systemImage: "map")
                }
            }
            // Section 2: 星域列表
            Section(header: Text(NSLocalizedString("Main_Language_Map_Type_Region", comment: ""))) {
                ForEach(regions) { region in
                    NavigationLink(value: RegionNavigation.regionMap(region.id, region.name)) {
                        Text(region.name)
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
        let sql = "select regionID, regionName from regions"
        if case let .success(rows) = DatabaseManager.shared.executeQuery(sql) {
            self.regions = rows.compactMap { row in
                guard let id = row["regionID"] as? Int, 
                      let name = row["regionName"] as? String,
                      availableRegionIds.contains(id) else { 
                    return nil as StarMapRegion? 
                }
                return StarMapRegion(id: id, name: name)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            Logger.info("过滤后显示 \(regions.count) 个星域")
        } else {
            self.regions = []
        }
    }
} 
