//
//  MainView.swift
//  Main page user can play game.
//
//  Created by Kwan Chi Chung on 22/4/2026.
//

import SwiftUI

// 主畫面：提供進入遊戲世界（GameView）的入口
struct MainView: View {
    @State var showAR = false  // 預留：是否顯示 AR 畫面（目前未使用）

    var body: some View {

            VStack{
                // 點擊後導航到 GameView（遊戲世界）
                NavigationLink(destination:GameView()){
                    Text("Go World")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }

                    .navigationTitle("")
                    .navigationBarBackButtonHidden()
                    // 右上角房屋圖示：點擊返回 ContentView（首頁）
                    .toolbar{
                        ToolbarItem(placement: .topBarTrailing) {   // top right option logo
                            NavigationLink(destination: ContentView()){  // pop up from right
                                Image(systemName: "house")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
            }

    }
}

#Preview {
    MainView()
}
