//
//  ContentView.swift
//  first page user can see the game menu.
//  User can start or setting.
//  Created by Kwan Chi Chung on 22/4/2026.
//

import SwiftUI

// App 首頁：顯示遊戲標題與「Start」按鈕進入主畫面
struct ContentView: View {
    var body: some View {
        NavigationStack{
            ZStack{
                VStack(spacing: 10) {
                    // 三個動物圖示（貓、鳥、狗），純裝飾用
                    HStack{
                        Image(systemName: "cat")
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Image(systemName: "bird")
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Image(systemName: "dog")
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    Text("Welcome To")
                    Text("PetWorld")

                    // 點擊後導航到主畫面 MainView
                    NavigationLink(destination:MainView()){
                        Text("Start")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }

                } //V
                .font(.system(.largeTitle, design: .monospaced))
                .padding()
            } //Zstack
            .navigationTitle("")
            .navigationBarBackButtonHidden()
            .navigationBarTitleDisplayMode(.inline)
            // 右上角設定按鈕（齒輪圖示），目前點擊無實際功能
            .toolbar{
                ToolbarItem(placement: .topBarTrailing) {   // ← top-RIGHT
                    Button(action: {
                        // 設定按鈕功能尚未實作
                    }) {
                        Image(systemName: "gearshape")  // ← SF Symbol icon
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }
            }

        } //NavigationStack
    }  //Body
} //ContentView

#Preview {
    ContentView()
}
