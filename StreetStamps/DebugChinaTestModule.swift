//
//  DebugChinaTestModule.swift
//  StreetStamps
//
//  完整的中国测试板块
//  支持: 30分钟跑步、8小时同城游、跨城自驾、飞机
//

import Foundation
import SwiftUI
import CoreLocation

#if DEBUG
struct DebugChinaTestModule: View {
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @StateObject private var tracking = TrackingService.shared
    
    @State private var currentTest: TestScenario? = nil
    @State private var testProgress: Double = 0
    @State private var testStatus: String = "Ready"
    @State private var elapsedTime: TimeInterval = 0
    @State private var pointsGenerated: Int = 0
    @State private var isRunning: Bool = false
    
    @State private var playbackSpeed: Double = 10  // 默认10倍速
    
    enum TestScenario: String, CaseIterable {
        case shanghaiRun30min = "上海跑步30分钟"
        case shanghaiDayTrip8h = "上海同城游8小时"
        case shanghaiHangzhouDrive = "上海-杭州自驾"
        case beijingShanghaieFlight = "北京-上海飞行"
        case shenzhenWalk30min = "深圳步行30分钟"
        
        var description: String {
            switch self {
            case .shanghaiRun30min:
                return "外滩-陆家嘴环线，5km跑步，测试运动模式精度"
            case .shanghaiDayTrip8h:
                return "走路+地铁+停留，测试日常模式省电和多交通方式"
            case .shanghaiHangzhouDrive:
                return "180km高速自驾，测试跨城判断和路线渲染"
            case .beijingShanghaieFlight:
                return "1200km飞行，测试稀疏点和飞行模式"
            case .shenzhenWalk30min:
                return "福田CBD散步，测试另一个城市的Geocode"
            }
        }
        
        var recommendedMode: TrackingMode {
            switch self {
            case .shanghaiRun30min, .shenzhenWalk30min:
                return .sport
            case .shanghaiDayTrip8h, .shanghaiHangzhouDrive, .beijingShanghaieFlight:
                return .daily
            }
        }
        
        var estimatedDuration: String {
            switch self {
            case .shanghaiRun30min: return "30分钟 (加速后约3分钟)"
            case .shanghaiDayTrip8h: return "8小时 (加速后约48分钟)"
            case .shanghaiHangzhouDrive: return "3小时 (加速后约18分钟)"
            case .beijingShanghaieFlight: return "2小时 (加速后约12分钟)"
            case .shenzhenWalk30min: return "30分钟 (加速后约3分钟)"
            }
        }
        
        func getPoints() -> [CLLocationCoordinate2D] {
            switch self {
            case .shanghaiRun30min:
                return ChinaTestRoutes.shanghaiRunning30min()
            case .shanghaiDayTrip8h:
                return ChinaTestRoutes.shanghaiDayTrip8h()
            case .shanghaiHangzhouDrive:
                return ChinaTestRoutes.shanghaiToHangzhouDrive()
            case .beijingShanghaieFlight:
                return ChinaTestRoutes.beijingToShanghaiFlightPath()
            case .shenzhenWalk30min:
                return ChinaTestRoutes.shenzhenWalk30min()
            }
        }
    }
    
    var body: some View {
        List {
            // MARK: - 状态面板
            Section("当前状态") {
                LabeledContent("定位模式", value: String(describing: locationHub.mode))
                LabeledContent("国家 ISO2", value: locationHub.countryISO2 ?? "nil")
                
                if let loc = locationHub.currentLocation {
                    LabeledContent("当前位置", value: String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                    LabeledContent("精度", value: String(format: "%.1fm", loc.horizontalAccuracy))
                }
                
                if isRunning {
                    LabeledContent("测试场景", value: currentTest?.rawValue ?? "无")
                    LabeledContent("进度", value: String(format: "%.1f%%", testProgress * 100))
                    LabeledContent("已生成点数", value: "\(pointsGenerated)")
                    LabeledContent("模拟时间", value: formatTime(elapsedTime))
                }
            }
            
            // MARK: - 播放速度
            Section("播放设置") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: L10n.t("debug_playback_speed"), locale: Locale.current, Int(playbackSpeed)))
                        .font(.subheadline)
                    
                    Slider(value: $playbackSpeed, in: 1...100, step: 1) {
                        Text(L10n.key("debug_speed"))
                    }
                    
                    HStack {
                        Button("1x") { playbackSpeed = 1 }
                        Button("10x") { playbackSpeed = 10 }
                        Button("50x") { playbackSpeed = 50 }
                        Button("100x") { playbackSpeed = 100 }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            
            // MARK: - 测试场景
            Section("测试场景") {
                ForEach(TestScenario.allCases, id: \.self) { scenario in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(scenario.rawValue)
                                    .font(.headline)
                                Text(scenario.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: L10n.t("debug_estimated"), locale: Locale.current, scenario.estimatedDuration))
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            if isRunning && currentTest == scenario {
                                ProgressView()
                            } else {
                                Button(L10n.t("debug_start")) {
                                    startTest(scenario)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isRunning)
                            }
                        }
                        
                        // 推荐模式标签
                        HStack {
                            Text(L10n.key("debug_recommended_mode"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Label(
                                scenario.recommendedMode == .sport ? "运动" : "日常",
                                systemImage: scenario.recommendedMode.icon
                            )
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(scenario.recommendedMode == .sport ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // MARK: - 控制按钮
            Section("控制") {
                if isRunning {
                    Button(L10n.t("debug_stop_test"), role: .destructive) {
                        stopTest()
                    }
                }
                
                Button(L10n.t("debug_switch_to_system")) {
                    locationHub.switchToSystem()
                    locationHub.startHighPower()
                }
                
                Button(L10n.t("debug_clear_all_journeys"), role: .destructive) {
                    // 实际实现需要在JourneyStore中添加clearAll方法
                    testStatus = "清除功能需要实现"
                }
            }
            
            // MARK: - 快速Geocode测试
            Section("Geocode测试") {
                Button(L10n.t("debug_test_geocode_shanghai")) {
                    testGeocode(ChinaTestRoutes.shanghaiPeopleSquare, name: "上海")
                }
                
                Button(L10n.t("debug_test_geocode_beijing")) {
                    testGeocode(ChinaTestRoutes.beijingTiananmen, name: "北京")
                }
                
                Button(L10n.t("debug_test_geocode_hangzhou")) {
                    testGeocode(ChinaTestRoutes.hangzhouWestLake, name: "杭州")
                }
                
                Button(L10n.t("debug_test_geocode_shenzhen")) {
                    testGeocode(ChinaTestRoutes.shenzhenFutian, name: "深圳")
                }
                
                Text(testStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // MARK: - 使用说明
            Section("使用说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.key("debug_step_1"))
                    Text(L10n.key("debug_step_2"))
                    Text(L10n.key("debug_step_3"))
                    Text(L10n.key("debug_step_4"))
                    Text(L10n.key("debug_step_5"))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .navigationTitle("中国测试板块")
    }
    
    // MARK: - Functions
    
    private func startTest(_ scenario: TestScenario) {
        currentTest = scenario
        isRunning = true
        testProgress = 0
        pointsGenerated = 0
        elapsedTime = 0
        testStatus = "正在播放: \(scenario.rawValue)"
        
        let points = scenario.getPoints()
        let pointsPerSecond = playbackSpeed
        
        // 根据场景设置精度
        let accuracy: CLLocationAccuracy
        let speed: CLLocationSpeed?
        let altitude: CLLocationDistance
        
        switch scenario {
        case .shanghaiRun30min, .shenzhenWalk30min:
            accuracy = 8
            speed = 3.0  // 跑步速度 ~10km/h
            altitude = 10
        case .shanghaiDayTrip8h:
            accuracy = 20
            speed = nil  // 自动计算
            altitude = 10
        case .shanghaiHangzhouDrive:
            accuracy = 15
            speed = 30  // ~100km/h
            altitude = 50
        case .beijingShanghaieFlight:
            accuracy = 100
            speed = 250  // ~900km/h
            altitude = 10000
        }
        
        locationHub.mockPlayPath(
            points: points,
            pointsPerSecond: pointsPerSecond,
            fixedSpeed: speed,
            accuracy: accuracy,
            altitude: altitude
        )
        
        // 模拟进度更新
        let totalDuration = Double(points.count) / pointsPerSecond
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            guard self.isRunning else {
                timer.invalidate()
                return
            }
            
            self.elapsedTime += 0.5
            self.testProgress = min(1.0, self.elapsedTime / totalDuration)
            self.pointsGenerated = Int(Double(points.count) * self.testProgress)
            
            if self.testProgress >= 1.0 {
                self.testStatus = "✅ 测试完成: \(scenario.rawValue)"
                self.isRunning = false
                timer.invalidate()
            }
        }
    }
    
    private func stopTest() {
        isRunning = false
        locationHub.switchToSystem()
        testStatus = "测试已停止"
        currentTest = nil
    }
    
    private func testGeocode(_ coord: CLLocationCoordinate2D, name: String) {
        testStatus = "正在测试 \(name) Geocode..."
        
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")) { placemarks, error in
            if let err = error as NSError? {
                testStatus = "❌ \(name) 失败: code=\(err.code)"
            } else if let pm = placemarks?.first {
                testStatus = "✅ \(name): \(pm.locality ?? "nil"), \(pm.country ?? "nil")"
            } else {
                testStatus = "⚠️ \(name): 无结果"
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Preview
struct DebugChinaTestModule_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DebugChinaTestModule()
        }
    }
}
#endif
