//
//  ChinaTestRoutes.swift
//  StreetStamps
//
//  中国境内测试路线数据
//  所有坐标均为真实地点，支持CLGeocoder解析
//

import Foundation
import CoreLocation

#if DEBUG
enum ChinaTestRoutes {
    
    // MARK: - 上海区域
    
    /// 上海人民广场
    static let shanghaiPeopleSquare = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
    
    /// 上海外滩
    static let shanghaiBund = CLLocationCoordinate2D(latitude: 31.2397, longitude: 121.4919)
    
    /// 上海浦东陆家嘴
    static let shanghaiLujiazui = CLLocationCoordinate2D(latitude: 31.2362, longitude: 121.5000)
    
    /// 上海虹桥站
    static let shanghaiHongqiao = CLLocationCoordinate2D(latitude: 31.1941, longitude: 121.3198)
    
    // MARK: - 北京区域
    
    /// 北京天安门
    static let beijingTiananmen = CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975)
    
    /// 北京朝阳公园
    static let beijingChaoyangPark = CLLocationCoordinate2D(latitude: 39.9343, longitude: 116.4801)
    
    /// 北京首都机场T3
    static let beijingCapitalAirport = CLLocationCoordinate2D(latitude: 40.0799, longitude: 116.6031)
    
    // MARK: - 杭州区域
    
    /// 杭州西湖
    static let hangzhouWestLake = CLLocationCoordinate2D(latitude: 30.2590, longitude: 120.1388)
    
    /// 杭州东站
    static let hangzhouEast = CLLocationCoordinate2D(latitude: 30.2908, longitude: 120.2194)
    
    // MARK: - 深圳区域
    
    /// 深圳福田CBD
    static let shenzhenFutian = CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)
    
    /// 深圳宝安机场
    static let shenzhenAirport = CLLocationCoordinate2D(latitude: 22.6393, longitude: 113.8106)
    
    // MARK: - 测试场景
    
    /// 场景1: 上海30分钟跑步（外滩-陆家嘴环线）
    /// - 总距离: ~5km
    /// - 时长: 30分钟
    /// - 点数: 每3秒一点 = 600点
    static func shanghaiRunning30min() -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        
        // 外滩起点 -> 陆家嘴 -> 返回外滩
        let waypoints = [
            CLLocationCoordinate2D(latitude: 31.2397, longitude: 121.4919), // 外滩
            CLLocationCoordinate2D(latitude: 31.2380, longitude: 121.4950),
            CLLocationCoordinate2D(latitude: 31.2365, longitude: 121.4975),
            CLLocationCoordinate2D(latitude: 31.2350, longitude: 121.4990),
            CLLocationCoordinate2D(latitude: 31.2362, longitude: 121.5000), // 陆家嘴
            CLLocationCoordinate2D(latitude: 31.2375, longitude: 121.5020),
            CLLocationCoordinate2D(latitude: 31.2390, longitude: 121.5010),
            CLLocationCoordinate2D(latitude: 31.2410, longitude: 121.4990),
            CLLocationCoordinate2D(latitude: 31.2425, longitude: 121.4970),
            CLLocationCoordinate2D(latitude: 31.2420, longitude: 121.4940),
            CLLocationCoordinate2D(latitude: 31.2405, longitude: 121.4925),
            CLLocationCoordinate2D(latitude: 31.2397, longitude: 121.4919), // 返回外滩
        ]
        
        // 在waypoints之间插值，生成600点
        points = interpolateRoute(waypoints: waypoints, totalPoints: 600)
        
        // 添加GPS噪声（模拟真实跑步）
        points = addGPSNoise(to: points, maxOffsetMeters: 3)
        
        return points
    }
    
    /// 场景2: 上海8小时同城游（走走停停）
    /// - 总时长: 8小时
    /// - 交通方式: 走路 + 地铁 + 走路 + 休息 + 走路
    /// - 点数: 日常模式每小时约200点 = 1600点
    static func shanghaiDayTrip8h() -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        
        // 早上: 人民广场出发 (走路30分钟)
        let segment1 = interpolateRoute(waypoints: [
            shanghaiPeopleSquare,
            CLLocationCoordinate2D(latitude: 31.2350, longitude: 121.4780),
            CLLocationCoordinate2D(latitude: 31.2380, longitude: 121.4850),
            shanghaiBund
        ], totalPoints: 100)
        points.append(contentsOf: segment1)
        
        // 上午: 外滩停留1小时 (稀疏点)
        points.append(contentsOf: stationaryPoints(at: shanghaiBund, count: 20, radiusMeters: 30))
        
        // 地铁到陆家嘴 (快速跳跃)
        points.append(contentsOf: transitJump(from: shanghaiBund, to: shanghaiLujiazui, points: 30))
        
        // 陆家嘴步行观光1.5小时
        let lujiazuiWalk = interpolateRoute(waypoints: [
            shanghaiLujiazui,
            CLLocationCoordinate2D(latitude: 31.2380, longitude: 121.5020),
            CLLocationCoordinate2D(latitude: 31.2350, longitude: 121.5050),
            CLLocationCoordinate2D(latitude: 31.2330, longitude: 121.5030),
            CLLocationCoordinate2D(latitude: 31.2340, longitude: 121.4990),
            shanghaiLujiazui
        ], totalPoints: 150)
        points.append(contentsOf: lujiazuiWalk)
        
        // 午餐停留1小时
        points.append(contentsOf: stationaryPoints(at: shanghaiLujiazui, count: 15, radiusMeters: 20))
        
        // 下午: 地铁回人民广场
        points.append(contentsOf: transitJump(from: shanghaiLujiazui, to: shanghaiPeopleSquare, points: 25))
        
        // 人民广场周边步行2小时
        let afternoonWalk = interpolateRoute(waypoints: [
            shanghaiPeopleSquare,
            CLLocationCoordinate2D(latitude: 31.2320, longitude: 121.4700),
            CLLocationCoordinate2D(latitude: 31.2280, longitude: 121.4720),
            CLLocationCoordinate2D(latitude: 31.2260, longitude: 121.4760),
            CLLocationCoordinate2D(latitude: 31.2290, longitude: 121.4800),
            shanghaiPeopleSquare
        ], totalPoints: 200)
        points.append(contentsOf: afternoonWalk)
        
        // 晚餐停留
        points.append(contentsOf: stationaryPoints(at: shanghaiPeopleSquare, count: 20, radiusMeters: 50))
        
        // 傍晚: 再次去外滩看夜景
        let eveningWalk = interpolateRoute(waypoints: [
            shanghaiPeopleSquare,
            CLLocationCoordinate2D(latitude: 31.2350, longitude: 121.4800),
            shanghaiBund
        ], totalPoints: 80)
        points.append(contentsOf: eveningWalk)
        
        // 外滩夜景停留
        points.append(contentsOf: stationaryPoints(at: shanghaiBund, count: 30, radiusMeters: 40))
        
        return points
    }
    
    /// 场景3: 上海-杭州自驾跨城 (约180km)
    /// - 总时长: 3小时
    /// - 交通方式: 自驾
    /// - 点数: 约300点
    static func shanghaiToHangzhouDrive() -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        
        // 上海虹桥出发
        let highwayPoints = interpolateRoute(waypoints: [
            shanghaiHongqiao,
            CLLocationCoordinate2D(latitude: 31.1500, longitude: 121.2000),  // 松江
            CLLocationCoordinate2D(latitude: 30.9000, longitude: 121.0000),  // 嘉兴方向
            CLLocationCoordinate2D(latitude: 30.7000, longitude: 120.7000),  // 桐乡
            CLLocationCoordinate2D(latitude: 30.5000, longitude: 120.5000),  // 余杭
            CLLocationCoordinate2D(latitude: 30.3500, longitude: 120.3000),  // 杭州郊区
            hangzhouWestLake
        ], totalPoints: 250)
        points.append(contentsOf: highwayPoints)
        
        // 杭州城区行驶
        let cityDrive = interpolateRoute(waypoints: [
            hangzhouWestLake,
            CLLocationCoordinate2D(latitude: 30.2650, longitude: 120.1500),
            hangzhouEast
        ], totalPoints: 50)
        points.append(contentsOf: cityDrive)
        
        return points
    }
    
    /// 场景4: 北京-上海飞行 (约1200km)
    /// - 总时长: 2小时
    /// - 交通方式: 飞机
    /// - 点数: 稀疏点 ~50点
    static func beijingToShanghaiFlightPath() -> [CLLocationCoordinate2D] {
        let waypoints = [
            beijingCapitalAirport,
            CLLocationCoordinate2D(latitude: 39.5, longitude: 117.0),   // 起飞爬升
            CLLocationCoordinate2D(latitude: 38.0, longitude: 118.0),   // 巡航
            CLLocationCoordinate2D(latitude: 36.0, longitude: 119.0),   // 山东上空
            CLLocationCoordinate2D(latitude: 34.0, longitude: 119.5),   // 江苏上空
            CLLocationCoordinate2D(latitude: 32.5, longitude: 120.5),   // 下降
            CLLocationCoordinate2D(latitude: 31.5, longitude: 121.2),   // 进近
            CLLocationCoordinate2D(latitude: 31.1500, longitude: 121.8050), // 浦东机场
        ]
        
        return interpolateRoute(waypoints: waypoints, totalPoints: 50)
    }
    
    /// 场景5: 深圳福田CBD步行 (模拟午休散步)
    static func shenzhenWalk30min() -> [CLLocationCoordinate2D] {
        let waypoints = [
            shenzhenFutian,
            CLLocationCoordinate2D(latitude: 22.5450, longitude: 114.0600),
            CLLocationCoordinate2D(latitude: 22.5470, longitude: 114.0620),
            CLLocationCoordinate2D(latitude: 22.5460, longitude: 114.0650),
            CLLocationCoordinate2D(latitude: 22.5440, longitude: 114.0630),
            shenzhenFutian
        ]
        
        var points = interpolateRoute(waypoints: waypoints, totalPoints: 300)
        points = addGPSNoise(to: points, maxOffsetMeters: 2)
        return points
    }
    
    // MARK: - Helper Functions
    
    /// 在waypoints之间线性插值
    private static func interpolateRoute(waypoints: [CLLocationCoordinate2D], totalPoints: Int) -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2, totalPoints >= waypoints.count else { return waypoints }
        
        var result: [CLLocationCoordinate2D] = []
        let segmentCount = waypoints.count - 1
        let pointsPerSegment = totalPoints / segmentCount
        
        for i in 0..<segmentCount {
            let start = waypoints[i]
            let end = waypoints[i + 1]
            
            for j in 0..<pointsPerSegment {
                let t = Double(j) / Double(pointsPerSegment)
                let lat = start.latitude + (end.latitude - start.latitude) * t
                let lon = start.longitude + (end.longitude - start.longitude) * t
                result.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        
        // 确保最后一个点
        if let last = waypoints.last {
            result.append(last)
        }
        
        return result
    }
    
    /// 添加GPS噪声模拟真实数据
    private static func addGPSNoise(to points: [CLLocationCoordinate2D], maxOffsetMeters: Double) -> [CLLocationCoordinate2D] {
        // 1米约等于 0.00001 经纬度
        let maxOffset = maxOffsetMeters * 0.00001
        
        return points.map { p in
            let latNoise = Double.random(in: -maxOffset...maxOffset)
            let lonNoise = Double.random(in: -maxOffset...maxOffset)
            return CLLocationCoordinate2D(
                latitude: p.latitude + latNoise,
                longitude: p.longitude + lonNoise
            )
        }
    }
    
    /// 生成静止区域的稀疏点（模拟停留）
    private static func stationaryPoints(at center: CLLocationCoordinate2D, count: Int, radiusMeters: Double) -> [CLLocationCoordinate2D] {
        let maxOffset = radiusMeters * 0.00001
        
        return (0..<count).map { _ in
            let latNoise = Double.random(in: -maxOffset...maxOffset)
            let lonNoise = Double.random(in: -maxOffset...maxOffset)
            return CLLocationCoordinate2D(
                latitude: center.latitude + latNoise,
                longitude: center.longitude + lonNoise
            )
        }
    }
    
    /// 模拟地铁/公交跳跃（少量点，大间距）
    private static func transitJump(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, points: Int) -> [CLLocationCoordinate2D] {
        return interpolateRoute(waypoints: [from, to], totalPoints: points)
    }
}
#endif
