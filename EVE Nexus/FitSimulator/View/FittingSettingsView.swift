import SwiftUI

struct FittingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var fittingName: String = ""
    let databaseManager: DatabaseManager
    let shipTypeID: Int
    @State private var shipItem: DatabaseListItem?
    @State private var fittingData: [String: Any]
    let onNameChanged: ([String: Any]) -> Void
    @ObservedObject var viewModel: FittingEditorViewModel
    let onDelete: (() -> Void)?

    @AppStorage("skillsModePreference") private var skillsMode = "current_char"
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @State private var selectedCharacterId: Int? = nil
    var onSkillModeChanged: (() -> Void)?

    // 添加UI状态管理
    @State private var isExportingToESI = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var showingConfirmAlert = false
    @State private var alertMessage = ""

    // 删除配置相关状态
    @State private var showingDeleteConfirmAlert = false
    @State private var isDeletingFitting = false

    init(
        databaseManager: DatabaseManager, shipTypeID: Int, fittingName: String,
        fittingData: [String: Any], onNameChanged: @escaping ([String: Any]) -> Void,
        onSkillModeChanged: (() -> Void)? = nil, viewModel: FittingEditorViewModel,
        onDelete: (() -> Void)? = nil
    ) {
        self.databaseManager = databaseManager
        self.shipTypeID = shipTypeID
        _fittingName = State(initialValue: fittingName)
        _fittingData = State(initialValue: fittingData)
        self.onNameChanged = onNameChanged
        self.onSkillModeChanged = onSkillModeChanged
        self.viewModel = viewModel
        self.onDelete = onDelete
    }

    private var skillModeText: String {
        if skillsMode == "current_char" {
            // 获取当前角色名称
            if currentCharacterId != 0 {
                if let character = EVELogin.shared.getCharacterByID(currentCharacterId)?.character {
                    return character.CharacterName
                }
            }
            skillsMode = "all5"
        } else if skillsMode == "all5" {
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: "全5级"), 5)
        } else if skillsMode == "all4" {
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 4)
        } else if skillsMode == "all3" {
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 3)
        } else if skillsMode == "all2" {
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 2)
        } else if skillsMode == "all1" {
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 1)
        } else if skillsMode == "all0" {
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 0)
        } else if skillsMode == "character" {
            let charId = UserDefaults.standard.integer(forKey: "selectedSkillCharacterId")
            let chars = CharacterSkillsUtils.getAllCharacters(excludeCurrentCharacter: false)
            if let character = chars.first(where: { $0.id == charId }) {
                return character.name
            }
        }
        return NSLocalizedString("Fitting_Unknown_Skills", comment: "未知技能模式")
    }

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Fitting_Setting_Ship", comment: ""))) {
                TextField(NSLocalizedString("Fitting_Name", comment: ""), text: $fittingName)
                    .textFieldStyle(.plain)
                    .onChange(of: fittingName) { _, newValue in
                        var updatedData = fittingData
                        updatedData["name"] = newValue
                        fittingData = updatedData
                        onNameChanged(updatedData)
                    }

                if let shipItem = shipItem {
                    NavigationLink {
                        // 获取计算后的飞船属性
                        let shipOutputAttributes = viewModel.simulationOutput?.ship.attributes
                        ShowItemInfo(
                            databaseManager: databaseManager,
                            itemID: shipTypeID,
                            modifiedAttributes: shipOutputAttributes
                        )
                    } label: {
                        DatabaseListItemView(
                            item: shipItem,
                            showDetails: true
                        )
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            Section(header: Text(NSLocalizedString("Fitting_Setting_Skills", comment: "技能设置"))) {
                NavigationLink {
                    CharacterSkillsSelectorView(
                        databaseManager: databaseManager,
                        onSelectSkills: { _, skillModeName, characterId in
                            // 更新技能模式
                            if characterId == 0 {
                                // 虚拟角色情况 (All 5/4/3/2/1/0)
                                if skillModeName.contains("5") {
                                    skillsMode = "all5"
                                } else if skillModeName.contains("4") {
                                    skillsMode = "all4"
                                } else if skillModeName.contains("3") {
                                    skillsMode = "all3"
                                } else if skillModeName.contains("2") {
                                    skillsMode = "all2"
                                } else if skillModeName.contains("1") {
                                    skillsMode = "all1"
                                } else if skillModeName.contains("0") {
                                    skillsMode = "all0"
                                }
                                selectedCharacterId = nil
                            } else if characterId == currentCharacterId {
                                // 当前角色情况
                                skillsMode = "current_char"
                                selectedCharacterId = nil
                            } else {
                                // 其他角色情况
                                skillsMode = "character"
                                selectedCharacterId = characterId
                                UserDefaults.standard.set(
                                    characterId, forKey: "selectedSkillCharacterId"
                                )
                            }

                            // 执行技能模式更改回调
                            onSkillModeChanged?()
                        }
                    )
                } label: {
                    HStack {
                        Image("skill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Fitting_Skills_Mode", comment: "技能模式"))
                        Spacer()
                        Text(skillModeText)
                            .foregroundColor(.secondary)
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            Section(header: Text(NSLocalizedString("Fitting_Setting_Implants", comment: "植入体设置"))) {
                NavigationLink {
                    ImplantSettingsView(
                        databaseManager: databaseManager,
                        viewModel: viewModel
                    )
                } label: {
                    HStack {
                        Image("implants")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Fitting_Implants_Mode", comment: "查看/编辑植入体"))
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            Section {
                Button {
                    showingConfirmAlert = true
                } label: {
                    HStack {
                        if isExportingToESI {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(
                                NSLocalizedString(
                                    "Fitting_Exporting_To_ESI", comment: "正在上传到ESI..."
                                )
                            )
                            .foregroundColor(.secondary)
                            .font(.system(size: 17))
                        } else {
                            Text(NSLocalizedString("Fitting_Export_To_ESI", comment: "导出到ESI"))
                                .foregroundColor(.blue)
                                .font(.system(size: 17))
                        }
                        Spacer()
                    }
                }
                .disabled(isExportingToESI || currentCharacterId == 0)
                .contentShape(Rectangle())
                .listRowSeparator(.visible, edges: .bottom)
                .listRowSeparatorTint(Color(UIColor.separator))

                Button {
                    exportToClipboard()
                } label: {
                    HStack {
                        Text(NSLocalizedString("Fitting_Export_To_Clipboard", comment: "导出到剪贴板"))
                            .foregroundColor(.blue)
                            .font(.system(size: 17))
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .listRowSeparator(.visible, edges: .bottom)
                .listRowSeparatorTint(Color(UIColor.separator))

                Button {
                    exportToImage()
                } label: {
                    HStack {
                        Text(NSLocalizedString("Fitting_Export_To_Image", comment: "导出到图片"))
                            .foregroundColor(.blue)
                            .font(.system(size: 17))
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if onDelete != nil {
                    Button {
                        showingDeleteConfirmAlert = true
                    } label: {
                        if isDeletingFitting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 30, height: 30)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                        }
                    }
                    .disabled(isDeletingFitting)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                }
            }
        }
        .alert(
            NSLocalizedString("Fitting_Upload_Success_Title", comment: "导出成功"),
            isPresented: $showingSuccessAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) {}
        } message: {
            Text(alertMessage)
        }
        .alert(
            NSLocalizedString("Fitting_Upload_Failed_Title", comment: "导出失败"),
            isPresented: $showingErrorAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) {}
        } message: {
            Text(alertMessage)
        }
        .alert(
            NSLocalizedString("Fitting_Upload_Confirm_Title", comment: "确认上传"),
            isPresented: $showingConfirmAlert
        ) {
            Button(NSLocalizedString("Fitting_Upload_Cancel", comment: "取消"), role: .cancel) {}
            Button(NSLocalizedString("Fitting_Upload_Confirm", comment: "确认上传"), role: .destructive) {
                exportToESI()
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Fitting_Upload_Confirm_Message", comment: "将配置上传到EVE游戏内？"
                    ),
                    viewModel.simulationInput.name.isEmpty
                        ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "未命名配置")
                        : viewModel.simulationInput.name
                ))
        }
        .alert(
            NSLocalizedString("Fitting_Delete_Confirm_Title", comment: "确认删除"),
            isPresented: $showingDeleteConfirmAlert
        ) {
            Button(NSLocalizedString("Common_Cancel", comment: "取消"), role: .cancel) {}
            Button(NSLocalizedString("Fitting_Delete_Confirm", comment: "删除"), role: .destructive) {
                deleteFitting()
            }
        } message: {
            let fittingName =
                viewModel.simulationInput.name.isEmpty
                    ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "未命名配置")
                    : viewModel.simulationInput.name
            Text(
                String(
                    format: NSLocalizedString(
                        "Fitting_Delete_Confirm_Message", comment: "确定要删除配置吗？"
                    ), fittingName
                ))
        }
        .onAppear {
            let items = databaseManager.loadMarketItems(
                whereClause: "t.type_id = ?",
                parameters: [shipTypeID]
            )
            if let item = items.first {
                shipItem = item
            }

            if skillsMode == "character" {
                selectedCharacterId = UserDefaults.standard.integer(
                    forKey: "selectedSkillCharacterId")
            }
        }
    }

    // MARK: - 导出方法

    /// 导出配置到ESI
    private func exportToESI() {
        // 检查是否有当前角色
        guard currentCharacterId != 0 else {
            Logger.error("导出到ESI失败: 没有当前角色")
            alertMessage = NSLocalizedString(
                "Fitting_Upload_No_Character", comment: "请先登录角色后再尝试上传配置"
            )
            showingErrorAlert = true
            return
        }

        // 设置加载状态
        isExportingToESI = true

        Task {
            do {
                Logger.info("开始导出配置到ESI - 配置名称: \(viewModel.simulationInput.name)")

                // 将SimulationInput转换为CharacterFitting格式
                let characterFitting = FitConvert.simulationInputToCharacterFitting(
                    input: viewModel.simulationInput)

                // 上传到EVE服务器
                let newFittingId = try await CharacterFittingAPI.uploadCharacterFitting(
                    characterID: currentCharacterId,
                    fitting: characterFitting
                )

                Logger.info("配置上传成功 - 新装配ID: \(newFittingId)")

                // 在主线程显示成功消息
                await MainActor.run {
                    isExportingToESI = false
                    alertMessage = String(
                        format: NSLocalizedString(
                            "Fitting_Upload_Success_Message", comment: "配置已成功上传到EVE"
                        ), newFittingId
                    )
                    showingSuccessAlert = true
                }

            } catch {
                Logger.error("导出配置到ESI失败: \(error)")

                // 在主线程显示错误消息
                await MainActor.run {
                    isExportingToESI = false
                    alertMessage = String(
                        format: NSLocalizedString("Fitting_Upload_Failed_Message", comment: "上传失败"),
                        error.localizedDescription
                    )
                    showingErrorAlert = true
                }
            }
        }
    }

    /// 导出配置到剪贴板
    private func exportToClipboard() {
        // 将 SimulationInput 转换为 LocalFitting
        let localFitting = FitConvert.simulationInputToLocalFitting(
            input: viewModel.simulationInput)

        // 使用 FitConvert 的 localFittingToEFT 方法生成 EFT 格式文本
        let clipboardText = FitConvert.localFittingToEFT(
            localFitting: localFitting, databaseManager: databaseManager
        )

        // 将文本复制到剪贴板
        UIPasteboard.general.string = clipboardText

        // 显示成功提示
        alertMessage = NSLocalizedString("Fitting_Export_Clipboard_Success", comment: "配置已复制到剪贴板")
        showingSuccessAlert = true

        Logger.info("配置已导出到剪贴板")
        Logger.info("clipboardText: \(clipboardText)")
    }

    /// 导出配置到图片
    private func exportToImage() {
        Logger.info("开始直接导出装配到相册")

        Task {
            do {
                // 创建用于渲染的完整内容视图
                let contentView = VStack(spacing: 0) {
                    // 飞船信息区域
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Image(
                                uiImage: IconManager.shared.loadUIImage(
                                    for: viewModel.shipInfo.iconFileName)
                            )
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.shipInfo.name)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text(
                                    viewModel.simulationInput.name.isEmpty
                                        ? NSLocalizedString("Unnamed", comment: "")
                                        : viewModel.simulationInput.name
                                )
                                .font(.headline)
                                .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))

                    // 装备模块区域
                    ModulesExportSection(viewModel: viewModel)

                    // 植入体区域
                    if !viewModel.simulationInput.implants.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        ImplantsExportSection(viewModel: viewModel)
                    }

                    // 无人机区域
                    if !(viewModel.simulationOutput?.drones.isEmpty ?? true) {
                        Divider()
                            .padding(.vertical, 8)
                        DronesExportSection(viewModel: viewModel)
                    }

                    // 货舱区域
                    if !viewModel.simulationInput.cargo.items.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        CargoExportSection(viewModel: viewModel)
                    }

                    // 舰载机区域
                    if let fighters = viewModel.simulationOutput?.fighters, !fighters.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        FightersExportSection(viewModel: viewModel)
                    }

                    // 状态信息区域前的分割线
                    Divider()
                        .padding(.vertical, 8)

                    // 状态信息区域 - 使用原有的状态组件
                    VStack(spacing: 16) {
                        // 资源统计
                        ShipResourcesStatsView(viewModel: viewModel)

                        // 抗性统计
                        ShipResistancesStatsView(viewModel: viewModel)

                        // 电容统计
                        ShipCapacitorStatsView(viewModel: viewModel)

                        // 火力统计
                        ShipFirepowerStatsView(viewModel: viewModel)

                        // 维修统计
                        ShipRepairStatsView(viewModel: viewModel)

                        // 其他属性
                        ShipMiscStatsView(viewModel: viewModel)

                        // 货仓属性
                        ShipAllCargoView(viewModel: viewModel)
                    }
                    .padding(.horizontal)

                    // Footer信息
                    FooterView()
                }
                .frame(width: 425)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(.systemGroupedBackground))
                // 明确设置当前颜色模式
                .environment(\.colorScheme, colorScheme)

                // 使用ImageRenderer渲染
                let renderer = ImageRenderer(content: contentView)
                renderer.scale = 4.0 // 分辨率

                if let uiImage = renderer.uiImage {
                    // 保存到相册
                    try await saveImageToPhotoLibrary(uiImage)

                    await MainActor.run {
                        alertMessage = NSLocalizedString(
                            "Fitting_Export_Photo_Success", comment: "装配图片已保存到相册"
                        )
                        showingSuccessAlert = true
                        Logger.info("装配图片已成功保存到相册")
                    }
                } else {
                    throw NSError(
                        domain: "FittingSettingsView", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "无法生成图片"]
                    )
                }
            } catch {
                Logger.error("导出装配图片失败: \(error)")
                await MainActor.run {
                    alertMessage = String(
                        format: NSLocalizedString("Fitting_Export_Failed_Message", comment: ""),
                        error.localizedDescription
                    )
                    showingErrorAlert = true
                }
            }
        }
    }

    /// 保存图片到相册
    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            // 创建一个临时类来处理保存回调
            class SaveImageTarget: NSObject {
                let continuation: CheckedContinuation<Void, Error>

                init(continuation: CheckedContinuation<Void, Error>) {
                    self.continuation = continuation
                }

                @objc func image(
                    _: UIImage, didFinishSavingWithError error: Error?,
                    contextInfo _: UnsafeRawPointer
                ) {
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            let target = SaveImageTarget(continuation: continuation)
            UIImageWriteToSavedPhotosAlbum(
                image, target,
                #selector(SaveImageTarget.image(_:didFinishSavingWithError:contextInfo:)), nil
            )
        }
    }

    /// 删除配置
    private func deleteFitting() {
        guard let deleteHandler = onDelete else {
            Logger.error("删除配置失败: 没有删除处理器")
            return
        }

        isDeletingFitting = true

        Logger.info("开始删除配置: \(viewModel.simulationInput.name)")

        // 调用删除处理器（会处理本地或在线配置的删除，并自动关闭页面）
        deleteHandler()

        // 关闭设置页面
        dismiss()

        Logger.info("配置删除处理完成")
    }
}

// MARK: - Footer视图

struct FooterView: View {
    // 获取应用版本信息
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0.0"
    }

    // 格式化当前时间
    private var currentTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal)

            VStack(spacing: 4) {
                // 第一行：应用信息
                Text(
                    String(
                        format: NSLocalizedString("Fitting_Export_Generated_By", comment: ""),
                        "Tritanium", appVersion
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)

                // 第二行：时间信息
                Text(
                    String(
                        format: NSLocalizedString("Fitting_Export_Generated_Time", comment: ""),
                        currentTime
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }
}
