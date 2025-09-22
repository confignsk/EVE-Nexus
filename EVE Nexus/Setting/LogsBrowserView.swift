import Foundation
import SwiftUI

struct LogsBrowserView: View {
    @State private var logFiles: [URL] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSelectionMode = false
    @State private var selectedFiles: Set<URL> = []
    @State private var showingDeleteAlert = false

    var body: some View {
        VStack {
            if isLoading {
                ProgressView(NSLocalizedString("Main_Setting_Logs_Loading", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("Main_Setting_Logs_Load_Failed", comment: ""))
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if logFiles.isEmpty {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("Main_Setting_Logs_No_Files", comment: ""))
                        .font(.headline)
                    Text(NSLocalizedString("Main_Setting_Logs_No_Files_Detail", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    List(logFiles, id: \.path) { logFile in
                        if isSelectionMode {
                            LogFileSelectionRowView(
                                logFile: logFile,
                                isSelected: selectedFiles.contains(logFile),
                                onToggle: {
                                    if selectedFiles.contains(logFile) {
                                        selectedFiles.remove(logFile)
                                    } else {
                                        selectedFiles.insert(logFile)
                                    }
                                }
                            )
                        } else {
                            LogFileRowView(logFile: logFile)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Logs_Browser_Title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelectionMode {
                    Button(NSLocalizedString("Main_Setting_Logs_Cancel", comment: "")) {
                        isSelectionMode = false
                        selectedFiles.removeAll()
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !isSelectionMode {
                        Button(NSLocalizedString("Main_Setting_Logs_Refresh", comment: "")) {
                            loadLogFiles()
                        }
                    }

                    Button(
                        isSelectionMode
                            ? NSLocalizedString("Main_Setting_Logs_Done", comment: "")
                            : NSLocalizedString("Main_Setting_Logs_Select", comment: "")
                    ) {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedFiles.removeAll()
                        }
                    }
                    .disabled(logFiles.isEmpty)
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                if isSelectionMode && !selectedFiles.isEmpty {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)

                    Spacer()

                    Button(action: shareSelectedFiles) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            loadLogFiles()
        }
        .alert(
            NSLocalizedString("Main_Setting_Logs_Delete_Confirm_Title", comment: ""),
            isPresented: $showingDeleteAlert
        ) {
            Button(NSLocalizedString("Main_Setting_Logs_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Main_Setting_Clean", comment: ""), role: .destructive) {
                deleteSelectedFiles()
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Main_Setting_Logs_Delete_Confirm_Message", comment: ""
                    ),
                    selectedFiles.count
                ))
        }
    }

    private func loadLogFiles() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let logPath = StaticResourceManager.shared.getStaticDataSetPath()
                    .appendingPathComponent("Logs")

                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: logPath.path) else {
                    await MainActor.run {
                        self.logFiles = []
                        self.isLoading = false
                    }
                    return
                }

                let files = try fileManager.contentsOfDirectory(
                    at: logPath,
                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )

                let logFiles =
                    files
                        .filter { $0.pathExtension == "log" }
                        .sorted { file1, file2 in
                            // 优先使用创建时间排序
                            let date1 =
                                (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate)
                                    ?? Date.distantPast
                            let date2 =
                                (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate)
                                    ?? Date.distantPast

                            // 如果创建时间相同，则按文件名排序
                            if date1 == date2 {
                                return file1.lastPathComponent > file2.lastPathComponent
                            }

                            // 最新的文件排在前面
                            return date1 > date2
                        }

                await MainActor.run {
                    self.logFiles = logFiles
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func deleteSelectedFiles() {
        let fileManager = FileManager.default
        var deletedCount = 0

        for file in selectedFiles {
            do {
                try fileManager.removeItem(at: file)
                deletedCount += 1
            } catch {
                Logger.error(
                    String(
                        format: NSLocalizedString("Main_Setting_Logs_Delete_Failed", comment: ""),
                        file.lastPathComponent, error.localizedDescription
                    ))
            }
        }

        Logger.info(
            String(
                format: NSLocalizedString("Main_Setting_Logs_Delete_Success", comment: ""),
                deletedCount
            ))
        selectedFiles.removeAll()
        isSelectionMode = false
        loadLogFiles()
    }

    private func shareSelectedFiles() {
        let activityViewController = UIActivityViewController(
            activityItems: Array(selectedFiles),
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first
        {
            // 适配iPad
            if let popover = activityViewController.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(
                    x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0
                )
                popover.permittedArrowDirections = []
            }

            window.rootViewController?.present(activityViewController, animated: true)
        }
    }
}

struct LogFileRowView: View {
    let logFile: URL
    @State private var fileSize: String = ""
    @State private var creationDate: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(logFile.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)

                Text(creationDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(fileSize)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .onAppear {
            loadFileInfo()
        }
    }

    private func loadFileInfo() {
        do {
            let resourceValues = try logFile.resourceValues(forKeys: [
                .creationDateKey, .fileSizeKey,
            ])

            if let date = resourceValues.creationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                creationDate = formatter.string(from: date)
            }

            if let size = resourceValues.fileSize {
                fileSize = FormatUtil.formatFileSize(Int64(size))
            }
        } catch {
            creationDate = NSLocalizedString("Main_Setting_Logs_Unknown_Date", comment: "")
            fileSize = NSLocalizedString("Main_Setting_Logs_Unknown_Size", comment: "")
        }
    }
}

struct LogFileSelectionRowView: View {
    let logFile: URL
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var fileSize: String = ""
    @State private var creationDate: String = ""

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text(logFile.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)

                Text(creationDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(fileSize)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .onAppear {
            loadFileInfo()
        }
    }

    private func loadFileInfo() {
        do {
            let resourceValues = try logFile.resourceValues(forKeys: [
                .creationDateKey, .fileSizeKey,
            ])

            if let date = resourceValues.creationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                creationDate = formatter.string(from: date)
            }

            if let size = resourceValues.fileSize {
                fileSize = FormatUtil.formatFileSize(Int64(size))
            }
        } catch {
            creationDate = NSLocalizedString("Main_Setting_Logs_Unknown_Date", comment: "")
            fileSize = NSLocalizedString("Main_Setting_Logs_Unknown_Size", comment: "")
        }
    }
}

#Preview {
    LogsBrowserView()
}
