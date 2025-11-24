import Foundation
import Pulse
import SwiftUI

// 频率限制信息结构
struct RateLimitInfo {
    let group: String?
    let limit: String?
    let remaining: Int?
    let used: Int?
    let retryAfter: Int?

    init(from response: HTTPURLResponse) {
        group = response.value(forHTTPHeaderField: "X-Ratelimit-Group")
        limit = response.value(forHTTPHeaderField: "X-Ratelimit-Limit")
        remaining = Int(response.value(forHTTPHeaderField: "X-Ratelimit-Remaining") ?? "")
        used = Int(response.value(forHTTPHeaderField: "X-Ratelimit-Used") ?? "")
        retryAfter = Int(response.value(forHTTPHeaderField: "Retry-After") ?? "")
    }

    var logString: String {
        var components: [String] = []

        components.append("组: \(group ?? "N/A")")
        components.append("限制: \(limit ?? "N/A")")
        components.append("剩余: \(remaining?.description ?? "N/A")")
        components.append("已用: \(used?.description ?? "N/A")")
        components.append("重试间隔: \(retryAfter?.description ?? "N/A")")

        return components.joined(separator: ", ")
    }
}

// 修改类定义，继承自NSObject
@globalActor actor NetworkManagerActor {
    static let shared = NetworkManagerActor()
}

@NetworkManagerActor
class NetworkManager: @unchecked Sendable {
    static let shared = NetworkManager()
    private let retrier: RequestRetrier
    private let rateLimiter: RateLimiter
    private let session: any URLSessionProtocol

    // 添加并发控制信号量
    private let concurrentSemaphore = DispatchSemaphore(value: 8)

    private init() {
        retrier = RequestRetrier()
        rateLimiter = RateLimiter()

        // 总是使用 URLSessionProxy 来记录网络请求日志
        // 这样网络日志总是被记录，只是用户界面上的查看按钮受 enableLogging 控制
        // 配置 NetworkLogger，使用与 Logger 相同的 LoggerStore
        var configuration = NetworkLogger.Configuration()
        // 配置敏感信息过滤（自动将敏感头信息替换为 <private>）
        configuration.sensitiveHeaders = ["Authorization", "Access-Token", "X-Auth-Token"]
        configuration.sensitiveQueryItems = ["token", "key", "password"]

        // 创建 NetworkLogger，使用与 Logger 相同的 LoggerStore
        // 这样所有日志（文本日志和网络日志）都会存储在同一个地方
        let loggerStore = Logger.shared.loggerStore
        let networkLogger = NetworkLogger(store: loggerStore, configuration: configuration)

        // 创建自定义的 URLSessionConfiguration 以支持 HTTP 缓存
        let sessionConfiguration = URLSessionConfiguration.default
        // 确保使用共享的 URLCache，并设置足够的缓存大小
        // 默认的 URLCache.shared 容量可能不够，需要确保有足够的空间
        if sessionConfiguration.urlCache == nil {
            // 设置 URLCache：内存 4MB，磁盘 20MB
            sessionConfiguration.urlCache = URLCache(
                memoryCapacity: 4 * 1024 * 1024,  // 4MB 内存缓存
                diskCapacity: 20 * 1024 * 1024,  // 20MB 磁盘缓存
                diskPath: "EVE_Nexus_HTTP_Cache"
            )
        } else {
            // 如果已有缓存，确保容量足够
            let existingCache = sessionConfiguration.urlCache!
            if existingCache.memoryCapacity < 4 * 1024 * 1024 {
                existingCache.memoryCapacity = 4 * 1024 * 1024
            }
            if existingCache.diskCapacity < 20 * 1024 * 1024 {
                existingCache.diskCapacity = 20 * 1024 * 1024
            }
        }
        // 设置请求缓存策略为使用协议默认策略（会遵循 HTTP 缓存头）
        sessionConfiguration.requestCachePolicy = .useProtocolCachePolicy

        // 使用 URLSessionProxy 包装 URLSession
        // URLSessionProxy 会自动记录所有网络请求到 Pulse
        // 直接使用 URLSessionProxy 而不是它的 session 属性，这样才能正确拦截 async/await 方法
        session = URLSessionProxy(configuration: sessionConfiguration, logger: networkLogger)
    }

    // 通用的数据获取函数
    func fetchData(
        from url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String]? = nil,
        forceRefresh: Bool = false,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        // 等待信号量
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                self.concurrentSemaphore.wait()
                continuation.resume()
            }
        }

        defer {
            // 完成后释放信号量
            DispatchQueue.global(qos: .userInitiated).async {
                self.concurrentSemaphore.signal()
            }
        }

        try await rateLimiter.waitForPermission()

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = method

        // 配置缓存策略
        // 注意：.reloadRevalidatingCacheData 会始终向服务器验证，即使缓存有效也会发送请求
        // 如果希望真正使用缓存而不发送请求，应该使用 .returnCacheDataElseLoad
        if forceRefresh {
            // 强制刷新时，使用重新验证策略（会发送请求但可能返回304）
            request.cachePolicy = .reloadRevalidatingCacheData
        } else {
            // 非强制刷新时，优先使用缓存，如果缓存过期或不存在才请求
            // 这样可以真正避免不必要的网络请求
            request.cachePolicy = .returnCacheDataElseLoad
        }

        // 添加基本请求头
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("tranquility", forHTTPHeaderField: "datasource")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(
            "Tritanium_v\(AppConfiguration.Version.fullVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        // 如果是 POST 请求且有请求体，设置 Content-Type
        if method == "POST" && body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // 添加自定义请求头
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 设置请求体
        if let body = body {
            request.httpBody = body
            // 添加请求体日志
            if method == "POST", let jsonString = String(data: body, encoding: .utf8) {
                Logger.debug("POST Request Body: \(jsonString)")
            }
        }

        return try await retrier.execute(noRetryKeywords: noRetryKeywords, timeouts: timeouts) {
//            Logger.info(
//                "[HTTP-Request] HTTP \(method) Request to: \(url), User-Agent: \(request.value(forHTTPHeaderField: "User-Agent") ?? "N/A")"
//            )

            // 使用Task.detached确保在后台线程执行，并设置合适的QoS
            try await Task.detached(priority: .userInitiated) {
                let (data, response) = try await self.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("无效的HTTP响应 - URL: \(url.absoluteString)")
                    throw NetworkError.invalidResponse
                }

                // 检查成功状态码（200 OK, 201 Created, 204 No Content, 304 Not Modified）
                guard [200, 201, 204, 304].contains(httpResponse.statusCode) else {
                    // 添加错误日志记录
                    if let responseBody = String(data: data, encoding: .utf8) {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体: \(responseBody)")

                        // 将响应体包含在错误中
                        throw NetworkError.httpError(
                            statusCode: httpResponse.statusCode, message: responseBody
                        )
                    } else {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体无法解析")
                        throw NetworkError.httpError(statusCode: httpResponse.statusCode)
                    }
                }
                // 解析频率限制信息
                let rateLimitInfo = RateLimitInfo(from: httpResponse)
                if rateLimitInfo.remaining ?? 100 <= 20 {
                    Logger.warning("[HTTP-Response] URL: \(url.absoluteString), Code: \(httpResponse.statusCode), Body Length: \(data.count) bytes, Rate Limit: \(rateLimitInfo.logString)")
                }
                return data
            }.value
        }
    }

    // 清除所有缓存
    func clearAllCaches() async {
        // 清除文件缓存
        await clearFileCaches()
    }

    private func clearFileCaches() async {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let staticDataSetPath = paths[0].appendingPathComponent("StaticDataSet")

        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(
                at: staticDataSetPath, includingPropertiesForKeys: nil
            )

            for url in contents {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int64
                {
                    Logger.info(
                        "Deleting file: \(url.lastPathComponent) (Size: \(FormatUtil.formatFileSize(fileSize)))"
                    )
                    try? FileManager.default.removeItem(at: url)
                }
            }

            Logger.info("Finished clearing StaticDataSet directory")
        } catch {
            try? FileManager.default.createDirectory(
                at: staticDataSetPath, withIntermediateDirectories: true
            )
            Logger.error("Error accessing StaticDataSet directory: \(error)")
        }
    }

    // 专门用于需访问令牌的请求
    func fetchDataWithToken(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }
        Logger.debug("Fetch data with token \(token.prefix(8))......")
        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(
            from: url,
            headers: allHeaders,
            noRetryKeywords: noRetryKeywords,
            timeouts: timeouts
        )
    }

    // POST请求带Token的方法
    func postDataWithToken(
        to url: URL,
        body: Data,
        characterId: Int,
        headers: [String: String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(
            from: url,
            method: "POST",
            body: body,
            headers: allHeaders,
            timeouts: timeouts
        )
    }

    // DELETE请求带Token的方法
    func deleteDataWithToken(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 使用基础的 fetchData 方法发送DELETE请求
        return try await fetchData(
            from: url,
            method: "DELETE",
            headers: allHeaders,
            noRetryKeywords: noRetryKeywords
        )
    }

    // 专门用于需访问令牌的请求，并返回响应头中的页数信息
    func fetchDataWithTokenAndPages(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> (Data, Int) {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // 添加请求头
        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return try await retrier.execute(noRetryKeywords: noRetryKeywords, timeouts: timeouts) {
            Logger.info("HTTP GET Request to: \(url)")

            return try await Task.detached(priority: .userInitiated) {
                let (data, response) = try await self.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("无效的HTTP响应 - URL: \(url.absoluteString)")
                    throw NetworkError.invalidResponse
                }

                guard httpResponse.statusCode == 200 else {
                    if let responseBody = String(data: data, encoding: .utf8) {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体: \(responseBody)")
                        throw NetworkError.httpError(
                            statusCode: httpResponse.statusCode, message: responseBody
                        )
                    } else {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体无法解析")
                        throw NetworkError.httpError(statusCode: httpResponse.statusCode)
                    }
                }

                // 从响应头中获取总页数
                let totalPages = Int(httpResponse.value(forHTTPHeaderField: "X-Pages") ?? "1") ?? 1
                Logger.info("获取到总页数: \(totalPages)")

                return (data, totalPages)
            }.value
        }
    }

    /// 处理分页数据的通用方法
    /// - Parameters:
    ///   - baseUrl: 基础URL，不包含页码参数
    ///   - characterId: 角色ID，用于获取访问令牌
    ///   - maxConcurrentPages: 最大并发请求数
    ///   - decoder: 用于解码数据的闭包
    ///   - progressCallback: 进度回调闭包，提供当前页数和总页数
    /// - Returns: 解码后的数据数组
    func fetchPaginatedData<T>(
        from baseUrl: URL,
        characterId: Int,
        maxConcurrentPages: Int = 3,
        decoder: @escaping (Data) throws -> [T],
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> [T] {
        var allItems: [T] = []

        // 构建第一页的URL
        let firstPageUrlString =
            baseUrl.absoluteString + (baseUrl.absoluteString.contains("?") ? "&" : "?") + "page=1"
        guard let firstPageUrl = URL(string: firstPageUrlString) else {
            throw NetworkError.invalidURL
        }

        Logger.info("开始获取第1页数据")

        // 获取第一页数据和总页数
        let (firstPageData, totalPages) = try await fetchDataWithTokenAndPages(
            from: firstPageUrl,
            characterId: characterId,
            timeouts: [2, 10, 15, 15, 15]
        )

        progressCallback?(1, totalPages)

        let firstPageItems = try decoder(firstPageData)
        Logger.success("成功获取第1页数据，本页包含\(firstPageItems.count)个项目")
        allItems.append(contentsOf: firstPageItems)

        // 如果有多页，使用并发获取剩余页面
        if totalPages > 1 {
            Logger.info("检测到总共有\(totalPages)页数据，开始并发获取剩余页面")

            do {
                try await withThrowingTaskGroup(of: (page: Int, items: [T]).self) { group in
                    var currentPage = 2
                    var inProgressPages = 0
                    var completedPages = Set<Int>()
                    completedPages.insert(1) // 第一页已完成

                    // 添加初始任务
                    while currentPage <= totalPages, inProgressPages < maxConcurrentPages {
                        let page = currentPage
                        group.addTask(priority: .userInitiated) {
                            let pageUrlString =
                                baseUrl.absoluteString
                                    + (baseUrl.absoluteString.contains("?") ? "&" : "?")
                                    + "page=\(page)"
                            guard let pageUrl = URL(string: pageUrlString) else {
                                throw NetworkError.invalidURL
                            }

                            Logger.info("开始获取第\(page)页数据")

                            let data = try await self.fetchDataWithToken(
                                from: pageUrl,
                                characterId: characterId,
                                timeouts: [2, 10, 15, 15, 15]
                            )

                            let pageItems = try decoder(data)
                            Logger.success("成功获取第\(page)页数据，本页包含\(pageItems.count)个项目")

                            // 添加短暂延迟以避免请求过于频繁
                            try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000)) // 500ms延迟

                            return (page: page, items: pageItems)
                        }
                        currentPage += 1
                        inProgressPages += 1
                    }

                    // 处理完成的任务并添加新任务
                    for try await result in group {
                        allItems.append(contentsOf: result.items)
                        completedPages.insert(result.page)
                        inProgressPages -= 1

                        // 更新进度回调
                        progressCallback?(completedPages.count, totalPages)

                        // 如果还有更多页面要获取，添加新任务
                        if currentPage <= totalPages {
                            let page = currentPage
                            group.addTask(priority: .userInitiated) {
                                let pageUrlString =
                                    baseUrl.absoluteString
                                        + (baseUrl.absoluteString.contains("?") ? "&" : "?")
                                        + "page=\(page)"
                                guard let pageUrl = URL(string: pageUrlString) else {
                                    throw NetworkError.invalidURL
                                }

                                Logger.info("开始获取第\(page)页数据")

                                let data = try await self.fetchDataWithToken(
                                    from: pageUrl,
                                    characterId: characterId,
                                    timeouts: [2, 10, 15, 15, 15]
                                )

                                let pageItems = try decoder(data)
                                Logger.success("成功获取第\(page)页数据，本页包含\(pageItems.count)个项目")

                                // 添加短暂延迟以避免请求过于频繁
                                try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000)) // 500ms延迟

                                return (page: page, items: pageItems)
                            }
                            currentPage += 1
                            inProgressPages += 1
                        }
                    }

                    // 检查是否所有页面都已获取
                    if completedPages.count != totalPages {
                        let missingPages = Set(1 ... totalPages).subtracting(completedPages)
                        Logger.warning("部分页面未能获取: \(missingPages)")
                    }
                }
            } catch {
                // 如果是取消错误，直接抛出
                if error is CancellationError {
                    throw error
                }

                // 对于其他错误，如果已经获取了一些数据，记录错误但继续返回已获取的数据
                if !allItems.isEmpty {
                    Logger.error("获取部分页面时出错: \(error)，但已获取\(allItems.count)个项目")
                } else {
                    // 如果没有获取到任何数据，则抛出错误
                    throw error
                }
            }
        }

        Logger.info("数据获取完成，共\(allItems.count)个项目")
        return allItems
    }
}

// 网络错误枚举
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String? = nil)
    case invalidImageData
    case noValidPrice
    case invalidData
    case refreshTokenExpired
    case unauthed
    case invalidToken(String)
    case maxRetriesExceeded
    case authenticationError(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Network_Error_Invalid_URL", comment: "")
        case .invalidResponse:
            return NSLocalizedString("Network_Error_Invalid_Response", comment: "")
        case let .httpError(statusCode, message):
            if let message = message {
                return
                    "\(String.localizedStringWithFormat(NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode)): \(message)"
            }
            return String(
                format: NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode
            )
        case .invalidImageData:
            return NSLocalizedString("Network_Error_Invalid_Image", comment: "")
        case .noValidPrice:
            return NSLocalizedString("Network_Error_No_Price", comment: "")
        case .invalidData:
            return NSLocalizedString("Network_Error_Invalid_Data", comment: "")
        case .refreshTokenExpired:
            return NSLocalizedString("Network_Error_Token_Expired", comment: "")
        case .unauthed:
            return NSLocalizedString("Network_Error_Unauthed", comment: "")
        case let .invalidToken(reason):
            return "Token无效: \(reason)"
        case .maxRetriesExceeded:
            return "已达到最大重试次数"
        case let .authenticationError(reason):
            return "认证出错: \(reason)"
        case let .decodingError(error):
            return "解码响应数据失败: \(error)"
        }
    }
}

// 添加 RequestRetrier 类
class RequestRetrier {
    private let defaultTimeouts: [TimeInterval]
    private let retryDelay: TimeInterval
    private var noRetryKeywords: [String]

    init(
        defaultTimeouts: [TimeInterval] = [1.5, 3, 5, 20, 20, 20], retryDelay: TimeInterval = 0,
        noRetryKeywords: [String] = []
    ) {
        self.defaultTimeouts = defaultTimeouts
        self.retryDelay = retryDelay
        self.noRetryKeywords = noRetryKeywords
    }

    func execute<T>(
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        // 使用自定义超时序列或默认序列
        let effectiveTimeouts = timeouts ?? defaultTimeouts

        // 合并默认的和临时的不重试关键词
        let keywords = Set(self.noRetryKeywords + (noRetryKeywords ?? []))
        var attempts = 0
        var lastError: Error?

        while attempts < effectiveTimeouts.count {
            do {
                // 设置当前尝试的超时时间
                let timeout = effectiveTimeouts[attempts]
                Logger.info("尝试第 \(attempts + 1) 次请求，超时时间: \(timeout)秒")

                return try await withTimeout(timeout) {
                    try await operation()
                }
            } catch {
                lastError = error

                // 检查是否应该重试
                if !shouldRetry(error, keywords: keywords) {
                    throw error
                }

                attempts += 1
                if attempts < effectiveTimeouts.count {
                    let delay = UInt64(retryDelay * pow(2.0, Double(attempts))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T)
        async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 添加实际操作任务
            group.addTask(priority: .userInitiated) {
                try await operation()
            }

            // 添加超时任务
            group.addTask(priority: .userInitiated) {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NetworkError.httpError(statusCode: 408, message: "请求超时")
            }

            defer {
                group.cancelAll()
            }

            // 等待第一个完成的任务
            do {
                let result =
                    try await group.next()
                        ?? {
                            throw NetworkError.httpError(statusCode: 408, message: "请求超时")
                        }()
                return result
            } catch {
                // 取消所有任务并抛出错误
                group.cancelAll()
                throw error
            }
        }
    }

    private func shouldRetry(_ error: Error, keywords: Set<String>) -> Bool {
        // 首先检查是否是网络错误
        if case let NetworkError.httpError(statusCode, message) = error {
            // 如果响应中包含不重试的关键词，则不重试
            if let errorMessage = message,
               keywords.contains(where: { errorMessage.contains($0) })
            {
                Logger.info("检测到不重试关键词，停止重试")
                return false
            }

            // 对于特定状态码才重试
            return [408, 500, 502, 503, 504].contains(statusCode)
        }
        return false
    }
}

// 添加 RateLimiter 类
actor RateLimiter {
    private var tokens: Int
    private let maxTokens: Int
    private var lastRefill: Date
    private let refillRate: Double // tokens per second

    init(maxTokens: Int = 150, refillRate: Double = 50) {
        self.maxTokens = maxTokens
        tokens = maxTokens
        lastRefill = Date()
        self.refillRate = refillRate
    }

    private func refillTokens() {
        let now = Date()
        let timePassed = now.timeIntervalSince(lastRefill)
        let tokensToAdd = Int(timePassed * refillRate)

        tokens = min(maxTokens, tokens + tokensToAdd)
        lastRefill = now
    }

    func waitForPermission() async throws {
        while tokens <= 0 {
            refillTokens()
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        tokens -= 1
    }
}
