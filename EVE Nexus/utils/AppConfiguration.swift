import Foundation

enum AppConfiguration {
    // 应用版本信息
    enum Version {
        static var fullVersion: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? NSLocalizedString("Unknown", comment: "")
        }
    }

    // 数据库版本信息
    enum Database {
        static var version: String {
            // 从SDE数据库获取版本信息
            if let versionInfo = getSDEVersionInfo() {
                return versionInfo
            }
            return NSLocalizedString("Unknown", comment: "")
        }

        private static func getSDEVersionInfo() -> String? {
            let databaseManager = DatabaseManager.shared

            let query = "SELECT build_number, release_date FROM version_info WHERE id = 1"

            if case let .success(results) = databaseManager.executeQuery(query, useCache: false),
               let row = results.first,
               let buildNumber = row["build_number"] as? Int,
               let releaseDateString = row["release_date"] as? String
            {
                // 解析日期并格式化为 YYYY-MM-DD 格式
                let dateFormatter = ISO8601DateFormatter()
                if let releaseDate = dateFormatter.date(from: releaseDateString) {
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateFormat = "yyyy-MM-dd"
                    let formattedDate = displayFormatter.string(from: releaseDate)
                    return "\(formattedDate)-\(buildNumber)"
                } else {
                    // 如果日期解析失败，直接使用原始字符串的前10位
                    let datePrefix = String(releaseDateString.prefix(10))
                    return "\(datePrefix)-\(buildNumber)"
                }
            }

            return nil
        }
    }
}
