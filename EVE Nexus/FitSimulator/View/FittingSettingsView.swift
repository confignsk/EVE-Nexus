import SwiftUI

struct FittingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
        self._fittingName = State(initialValue: fittingName)
        self._fittingData = State(initialValue: fittingData)
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
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: "全5级"), 5)
        } else if skillsMode == "all4" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 4)
        } else if skillsMode == "all3" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 3)
        } else if skillsMode == "all2" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 2)
        } else if skillsMode == "all1" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 1)
        } else if skillsMode == "all0" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 0)
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
                        onSelectSkills: { skills, skillModeName, characterId in
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
                                UserDefaults.standard.set(characterId, forKey: "selectedSkillCharacterId")
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
                            Text(NSLocalizedString("Fitting_Exporting_To_ESI", comment: "正在上传到ESI..."))
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
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if let _ = onDelete {
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
        .alert(NSLocalizedString("Fitting_Upload_Success_Title", comment: "导出成功"), isPresented: $showingSuccessAlert) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) { }
        } message: {
            Text(alertMessage)
        }
        .alert(NSLocalizedString("Fitting_Upload_Failed_Title", comment: "导出失败"), isPresented: $showingErrorAlert) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) { }
        } message: {
            Text(alertMessage)
        }
        .alert(NSLocalizedString("Fitting_Upload_Confirm_Title", comment: "确认上传"), isPresented: $showingConfirmAlert) {
            Button(NSLocalizedString("Fitting_Upload_Cancel", comment: "取消"), role: .cancel) { }
            Button(NSLocalizedString("Fitting_Upload_Confirm", comment: "确认上传"), role: .destructive) {
                exportToESI()
            }
        } message: {
            Text(String(format: NSLocalizedString("Fitting_Upload_Confirm_Message", comment: "将配置上传到EVE游戏内？"), 
                       viewModel.simulationInput.name.isEmpty ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "未命名配置") : viewModel.simulationInput.name))
        }
        .alert(NSLocalizedString("Fitting_Delete_Confirm_Title", comment: "确认删除"), isPresented: $showingDeleteConfirmAlert) {
            Button(NSLocalizedString("Common_Cancel", comment: "取消"), role: .cancel) { }
            Button(NSLocalizedString("Fitting_Delete_Confirm", comment: "删除"), role: .destructive) {
                deleteFitting()
            }
        } message: {
            let fittingName = viewModel.simulationInput.name.isEmpty ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "未命名配置") : viewModel.simulationInput.name
            Text(String(format: NSLocalizedString("Fitting_Delete_Confirm_Message", comment: "确定要删除配置吗？"), fittingName))
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
                selectedCharacterId = UserDefaults.standard.integer(forKey: "selectedSkillCharacterId")
            }
        }
    }
    
    // MARK: - 导出方法
    
    /// 导出配置到ESI
    private func exportToESI() {
        // 检查是否有当前角色
        guard currentCharacterId != 0 else {
            Logger.error("导出到ESI失败: 没有当前角色")
            alertMessage = NSLocalizedString("Fitting_Upload_No_Character", comment: "请先登录角色后再尝试上传配置")
            showingErrorAlert = true
            return
        }
        
        // 设置加载状态
        isExportingToESI = true
        
        Task {
            do {
                Logger.info("开始导出配置到ESI - 配置名称: \(viewModel.simulationInput.name)")
                
                // 将SimulationInput转换为CharacterFitting格式
                let characterFitting = FitConvert.simulationInputToCharacterFitting(input: viewModel.simulationInput)
                
                // 上传到EVE服务器
                let newFittingId = try await CharacterFittingAPI.uploadCharacterFitting(
                    characterID: currentCharacterId,
                    fitting: characterFitting
                )
                
                Logger.info("配置上传成功 - 新装配ID: \(newFittingId)")
                
                // 在主线程显示成功消息
                await MainActor.run {
                    isExportingToESI = false
                    alertMessage = String(format: NSLocalizedString("Fitting_Upload_Success_Message", comment: "配置已成功上传到EVE"), newFittingId)
                    showingSuccessAlert = true
                }
                
            } catch {
                Logger.error("导出配置到ESI失败: \(error)")
                
                // 在主线程显示错误消息
                await MainActor.run {
                    isExportingToESI = false
                    alertMessage = String(format: NSLocalizedString("Fitting_Upload_Failed_Message", comment: "上传失败"), error.localizedDescription)
                    showingErrorAlert = true
                }
            }
        }
    }
    
    /// 导出配置到剪贴板
    private func exportToClipboard() {
        // 将 SimulationInput 转换为 LocalFitting
        let localFitting = FitConvert.simulationInputToLocalFitting(input: viewModel.simulationInput)
        
        // 使用 FitConvert 的 localFittingToEFT 方法生成 EFT 格式文本
        let clipboardText = FitConvert.localFittingToEFT(localFitting: localFitting, databaseManager: databaseManager)
        
        // 将文本复制到剪贴板
        UIPasteboard.general.string = clipboardText
        
        // 显示成功提示
        alertMessage = NSLocalizedString("Fitting_Export_Clipboard_Success", comment: "配置已复制到剪贴板")
        showingSuccessAlert = true
        
        Logger.info("配置已导出到剪贴板")
        Logger.info("clipboardText: \(clipboardText)")
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
