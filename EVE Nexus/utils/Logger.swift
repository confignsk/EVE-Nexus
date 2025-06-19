import Foundation
import OSLog
import UIKit

class Logger {
    static let shared = Logger()
    private let fileManager = FileManager.default
    private let dateFormatter = DateFormatter()
    private let logQueue = DispatchQueue(label: "com.eve.nexus.logger")
    private var currentLogFile: URL?
    private let maxLogFiles = 20  // 保留最近20个日志文件
    
    // 控制台输出重定向相关
    private var originalStderr: Int32 = 0
    private var logPipe: Pipe?
    private var isConsoleRedirected = false
    
    // 是否输出日志到文件，通过UserDefaults控制
    private var ifWriteToFile: Bool {
        return UserDefaults.standard.bool(forKey: "enableLogging")
    }

    // 日志长度限制
    private static var maxDebugLogLength = 2000  // debug日志最大长度
    private static var maxInfoLogLength = 200000  // info日志最大长度

    private init() {
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // 确保在访问 StaticResourceManager 之前完成基本初始化
        DispatchQueue.main.async { [weak self] in
            self?.setupLogDirectory()
            self?.rotateLogFiles()
            self?.createNewLogFile()
            self?.setupConsoleRedirection()
        }
        
        // 监听UserDefaults变化，动态启用/禁用控制台重定向
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func userDefaultsDidChange() {
        DispatchQueue.main.async { [weak self] in
            if self?.ifWriteToFile == true {
                self?.startConsoleRedirection()
            } else {
                self?.stopConsoleRedirection()
            }
        }
    }
    
    private func setupConsoleRedirection() {
        guard ifWriteToFile else { return }
        startConsoleRedirection()
    }
    
    private func startConsoleRedirection() {
        guard ifWriteToFile, !isConsoleRedirected else { return }
        
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 保存原始的stderr
            self.originalStderr = dup(STDERR_FILENO)
            
            // 创建管道
            self.logPipe = Pipe()
            guard let pipe = self.logPipe else { return }
            
            // 重定向stderr到管道
            dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            
            // 开始读取管道数据
            pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                if !data.isEmpty {
                    if let output = String(data: data, encoding: .utf8) {
                        self?.processConsoleOutput(output)
                    }
                }
            }
            
            self.isConsoleRedirected = true
            Logger.info("[ConsoleRedirect] 控制台输出重定向已启用")
        }
    }
    
    private func stopConsoleRedirection() {
        guard isConsoleRedirected else { return }
        
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 停止读取管道
            self.logPipe?.fileHandleForReading.readabilityHandler = nil
            
            // 恢复原始的stderr
            dup2(self.originalStderr, STDERR_FILENO)
            close(self.originalStderr)
            
            // 关闭管道
            self.logPipe?.fileHandleForWriting.closeFile()
            self.logPipe?.fileHandleForReading.closeFile()
            self.logPipe = nil
            
            self.isConsoleRedirected = false
            Logger.info("[ConsoleRedirect] 控制台输出重定向已停止")
        }
    }
    
    private func processConsoleOutput(_ output: String) {
        // 过滤掉我们自己的日志输出，避免无限循环
        if output.contains("[ConsoleRedirect]") || output.contains("EVE_Nexus_Logger") {
            return
        }
        
        // 按行分割输出
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty {
                // 格式化控制台输出并写入文件
                let formattedOutput = formatConsoleOutput(trimmedLine)
                writeConsoleOutputToFile(formattedOutput)
            }
        }
    }
    
    private func formatConsoleOutput(_ output: String) -> String {
        let timestamp = dateFormatter.string(from: Date())
        
        // 尝试解析常见的日志格式
        if output.contains("Timestamp:") && output.contains("Library:") {
            // 已经是格式化的系统日志
            return output
        } else if output.hasPrefix("[") && output.contains("]") {
            // 可能是其他库的日志格式
            return "Timestamp: \(timestamp) | Console: \(output)"
        } else {
            // 普通输出
            return "Timestamp: \(timestamp) | Console: \(output)"
        }
    }
    
    private func writeConsoleOutputToFile(_ message: String) {
        guard let logFile = currentLogFile else { return }
        
        let logMessage = "\(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
    }

    private func setupLogDirectory() {
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(
            "Logs")
        try? fileManager.createDirectory(at: logPath, withIntermediateDirectories: true)
    }

    // 获取设备标识符
    private func getDeviceIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    // 获取当前内存使用情况
    private func getMemoryUsage() -> (used: Double, total: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            // 获取系统总内存
            let totalMemory = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0
            return (used: usedMB, total: totalMemory)
        }
        return (used: 0, total: 0)
    }
    
    // 获取CPU使用率
    private func getCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            var threadsList: thread_act_array_t?
            var threadsCount = mach_msg_type_number_t(0)
            
            let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
            if threadsResult == KERN_SUCCESS {
                var totalCPU: Double = 0
                
                for i in 0..<threadsCount {
                    var threadInfo = thread_basic_info()
                    var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                    
                    let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                            thread_info(threadsList![Int(i)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                        }
                    }
                    
                    if infoResult == KERN_SUCCESS {
                        totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    }
                }
                
                // 清理内存
                vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.size))
                
                return totalCPU
            }
        }
        return 0
    }

    private func createNewLogFile() {
        guard ifWriteToFile else { return }
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(
            "Logs")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "EVE_Nexus_Debug_\(formatter.string(from: Date())).log"
        currentLogFile = logPath.appendingPathComponent(fileName)
        // 获取设备详细信息
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo
        let deviceIdentifier = getDeviceIdentifier()
        
        // 获取系统资源信息
        let memoryInfo = getMemoryUsage()
        let cpuUsage = getCPUUsage()
        
        // 获取磁盘空间信息
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var availableSpace: Int64 = 0
        var totalSpace: Int64 = 0
        
        do {
            let values = try documentsPath.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            availableSpace = Int64(values.volumeAvailableCapacity ?? 0)
            totalSpace = Int64(values.volumeTotalCapacity ?? 0)
        } catch {
            // 忽略错误，使用默认值
        }
        
        // 格式化内存显示 (MB)
        let memoryDisplay = String(format: "%.0fMB/%.0fMB", memoryInfo.used, memoryInfo.total)
        
        // 格式化存储空间显示 (MB)
        let usedStorageMB = Double(totalSpace - availableSpace) / 1024.0 / 1024.0
        let totalStorageMB = Double(totalSpace) / 1024.0 / 1024.0
        let storageDisplay = String(format: "%.0fMB/%.0fMB", usedStorageMB, totalStorageMB)
        
        // 写入日志文件头部信息
        let header = """
            \n\n=====================================
            EVE Panel Full Debug Log (Console Redirect Mode)
            Created at: \(dateFormatter.string(from: Date()))
            
            === 设备信息 ===
            Device Model: \(deviceIdentifier)
            iOS Version: \(device.systemName) \(processInfo.operatingSystemVersionString)
            App Version: v\(AppConfiguration.Version.fullVersion)
            
            === 系统资源状态 ===
            内存使用: \(memoryDisplay)
            CPU 使用率: \(String(format: "%.1f", cpuUsage))%
            存储使用: \(storageDisplay)
            
            === 调试模式 ===
            Debug Mode: All console output captured
            Log Level: All levels enabled
            Console Redirect: \(ifWriteToFile ? "启用" : "禁用")
            =====================================\n\n
            """
        Logger.info(header)
        Logger.info("[Logger] Create full debug log file: \(currentLogFile!.path)")
    }

    private func rotateLogFiles() {
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(
            "Logs")

        do {
            let files = try fileManager.contentsOfDirectory(
                at: logPath, includingPropertiesForKeys: [.creationDateKey]
            )
            let sortedFiles = files.filter { $0.pathExtension == "log" }
                .sorted { file1, file2 -> Bool in
                    let date1 =
                        try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate
                        ?? Date.distantPast
                    let date2 =
                        try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate
                        ?? Date.distantPast
                    return date1! > date2!
                }

            // 删除超过最大数量的旧日志文件
            if sortedFiles.count > maxLogFiles {
                for file in sortedFiles[maxLogFiles...] {
                    try? fileManager.removeItem(at: file)
                }
            }
        } catch {
            os_log(
                "Failed to rotate log files: %{public}@", type: .error, error.localizedDescription
            )
        }
    }

    private func writeToFile(_ message: String, type: OSLogType) {
        guard let logFile = currentLogFile else { return }

        logQueue.async {
            let timestamp = self.dateFormatter.string(from: Date())
            let logLevel = self.logLevelString(for: type)
            let logMessage = "[\(timestamp)] [APP-\(logLevel)] \(message)\n"

            if let data = logMessage.data(using: .utf8) {
                if self.fileManager.fileExists(atPath: logFile.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try? fileHandle.close()
                    }
                } else {
                    try? data.write(to: logFile, options: .atomic)
                }
            }
        }
    }

    private func logLevelString(for type: OSLogType) -> String {
        switch type {
        case .debug:
            return NSLocalizedString("Main_Setting_Logs_Level_Debug", comment: "")
        case .info:
            return NSLocalizedString("Main_Setting_Logs_Level_Info", comment: "")
        case .error:
            return NSLocalizedString("Main_Setting_Logs_Level_Error", comment: "")
        case .fault:
            return NSLocalizedString("Main_Setting_Logs_Level_Warning", comment: "")
        default:
            return NSLocalizedString("Main_Setting_Logs_Level_Info", comment: "")
        }
    }

    // 公共日志方法
    static func debug(_ message: String) {
        let truncatedMessage = truncateMessage(message, maxLength: maxDebugLogLength)
        os_log("%{public}@", type: .debug, truncatedMessage)
        shared.writeToFile(message, type: .debug)
    }

    static func info(_ message: String) {
        let truncatedMessage = truncateMessage(message, maxLength: maxInfoLogLength)
        os_log("%{public}@", type: .info, truncatedMessage)
        shared.writeToFile(message, type: .info)
    }

    static func warning(_ message: String) {
        os_log("%{public}@", type: .fault, message)
        shared.writeToFile(message, type: .fault)
    }

    static func error(_ message: String, error: Error? = nil, showAlert _: Bool = true) {
        os_log("%{public}@", type: .error, message)
        let errorMessage = "\(message) \(error?.localizedDescription ?? "")"
        // 记录到文件
        shared.writeToFile(errorMessage, type: .error)
    }

    static func fault(_ message: String) {
        os_log("%{public}@", type: .fault, message)
        shared.writeToFile(message, type: .fault)
    }

    // 截断消息到指定长度
    private static func truncateMessage(_ message: String, maxLength: Int) -> String {
        if message.count <= maxLength {
            return message
        } else {
            return message.prefix(maxLength) + "......"
        }
    }
    
    deinit {
        stopConsoleRedirection()
        NotificationCenter.default.removeObserver(self)
    }
}
