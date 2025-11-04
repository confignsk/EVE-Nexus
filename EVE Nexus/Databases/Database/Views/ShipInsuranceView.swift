import SwiftUI

struct ShipInsuranceView: View {
    let typeId: Int
    let typeName: String

    @State private var insuranceData: InsurancePriceItem?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = errorMessage {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else if let insurance = insuranceData {
                insuranceLevelsSection(insurance: insurance)
            } else {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("Insurance_No_Data", comment: "该飞船暂无保险数据"))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(NSLocalizedString("Insurance_Title", comment: "保险"))
        .task {
            await loadInsuranceData()
        }
    }

    @ViewBuilder
    private func insuranceLevelsSection(insurance: InsurancePriceItem) -> some View {
        Section(header: Text(NSLocalizedString("Insurance_Levels", comment: "保险等级")).font(.headline)) {
            ForEach(Array(insurance.levels.enumerated()), id: \.offset) { _, level in
                VStack(alignment: .leading, spacing: 6) {
                    // 第一行：保险等级名称
                    Text(level.localizedName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    // 第二行：保险费用
                    HStack {
                        Text(NSLocalizedString("Insurance_Cost", comment: "保险费用"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image("isk")
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(FormatUtil.formatISK(level.cost))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }

                    // 第三行：赔付金额
                    HStack {
                        Text(NSLocalizedString("Insurance_Payout", comment: "赔付金额"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image("isk")
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(FormatUtil.formatISK(level.payout))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }

                    // 第四行：净收益
                    let netProfit = level.payout - level.cost
                    HStack {
                        Text(NSLocalizedString("Insurance_Net_Profit", comment: "净收益"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image("isk")
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(FormatUtil.formatISK(netProfit))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(netProfit >= 0 ? .green : .red)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
            }
        }

        Section {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text(NSLocalizedString("Insurance_Info_Tip", comment: "保险赔付在飞船被摧毁时发放"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadInsuranceData() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let insurance = try await InsurancePricesAPI.shared.getInsurancePrice(for: typeId)

            await MainActor.run {
                self.insuranceData = insurance
                self.isLoading = false
            }

            if insurance != nil {
                Logger.info("[+] 成功加载飞船 \(typeName) 的保险数据")
            } else {
                Logger.warning("[!] 飞船 \(typeName) 没有保险数据")
            }
        } catch {
            Logger.error("[x] 加载飞船保险数据失败: \(error)")

            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
