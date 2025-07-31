import Foundation

// MARK: - 共享数据模型
struct Center: Codable {
    let x: Double
    let y: Double
}

// MARK: - 全星域地图数据结构 (regions_data.json)
struct RegionData: Codable {
    let region_id: Int
    let faction_id: Int
    let center: Center
    let relations: [String]
}

// MARK: - 星域地图数据结构 (systems_data.json 中的单个星域数据)
struct SystemMapData: Codable {
    let region_id: Int
    let faction_id: Int
    let center: Center
    let relations: [String]
    let systems: [String: SystemPosition]
    let jumps: [String: [String]]
}

struct SystemPosition: Codable {
    let x: Double
    let y: Double
}

struct SystemNodeData {
    let systemId: Int
    let name: String
    let security: Double
    let regionId: Int
    let position: CGPoint
    let connections: [Int]
}

struct StarMapRegion: Identifiable {
    let id: Int
    let name: String
}

// MARK: - 导航枚举
enum RegionNavigation: Hashable {
    case regionMap(Int, String) // regionId, regionName
} 