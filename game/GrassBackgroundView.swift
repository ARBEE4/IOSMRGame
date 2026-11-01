//
//  GrassBackgroundView.swift
//  game
//
//  草地背景：首頁（ContentView）和貓咪走動的頁面（GameView）共用。
//  圖片放在 Assets.xcassets 的 GrassBackground。想換圖：用新圖片取代那裡的圖片（名字不變），程式不用改。
//

import SwiftUI  // SwiftUI 畫面

// 蓋滿整個螢幕的草地背景圖
struct GrassBackgroundView: View {
    var body: some View {
        GeometryReader { geo in                                         // geo.size = 螢幕的大小
            Image("GrassBackground")                                    // Assets 裡的草地圖片
                .resizable()                                            // 允許改變大小
                .interpolation(.high)                                   // 放大時用最平滑的方式（這張圖很小，要放大很多倍）
                .scaledToFill()                                         // 等比例放大到蓋滿螢幕（左右多出來的部分會超出去）
                .frame(width: geo.size.width, height: geo.size.height)  // 圖片的框 = 螢幕的大小
                .clipped()                                              // 切掉超出螢幕的部分（換頁動畫時才不會露出來蓋到別頁）
        }
        .ignoresSafeArea()                                              // 連瀏海和底部橫條的位置也蓋滿
    }
}

#Preview {
    GrassBackgroundView()  // 在 Xcode 預覽裡看背景
}
