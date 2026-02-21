//
//  StreetStampsWidgetsBundle.swift
//  StreetStampsWidgets
//
//  Widget Extension 入口
//

import WidgetKit
import SwiftUI

@main
struct StreetStampsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Live Activity for tracking
        TrackingLiveActivity()
    }
}
