//
//  GameView.swift
//  Tap cat to show CatDetailView in sheet
//

import SwiftUI

// 遊戲主畫面：顯示 3D 貓咪，點擊貓咪會彈出詳細資訊面板
struct GameView: View {
    @Environment(\.dismiss) var dismiss  // 用於返回上一頁
    @State private var showCatDetail = false  // 控制 CatDetailView sheet 是否顯示

    var body: some View {
        VStack(spacing: 0) {
            // 頂部標題列
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.accentColor)
                }

                Spacer()

                Text("My Cat")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Image(systemName: "cat")
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            // 3D 貓咪畫面，含隨機移動動畫；點擊貓咪時觸發 onCatTapped
            Cat3DView(onCatTapped: {
                showCatDetail = true
            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .navigationTitle("")
        .navigationBarBackButtonHidden()

        // 點擊貓咪後，以 sheet 形式彈出詳細資訊面板
        .sheet(isPresented: $showCatDetail) {
            CatDetailView()
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }
}
