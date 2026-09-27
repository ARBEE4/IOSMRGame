//
//  CatDetailView.swift
//  game
//
//  Your original style + buttons, simplified
//

import SwiftUI

// 點擊貓咪後彈出的詳細資訊面板（情緒、飢餓度、功能按鈕）
struct CatDetailView: View {
    @State var ARMode = false  // 是否進入 AR 全螢幕模式

    var body: some View {

        ZStack {
            Color.gray.opacity(0.7).ignoresSafeArea()  // 半透明灰色背景
            VStack(spacing: 20) {

                // 情緒（mood）進度條，固定值 70%
                VStack(alignment: .leading){

                    ProgressView(value: 0.7, label: {
                        Label("mood", systemImage:"face.smiling")},currentValueLabel:{Text("70%")})
                            .progressViewStyle(BarProgessStyle(color:.green,height: 50.0))
                            .padding(20)

                }
                // 飢餓度（hunger）進度條，固定值 30%
                VStack(alignment: .leading){

                    ProgressView(value: 0.3, label: {
                        Label("hunger", systemImage:"fork.knife")},currentValueLabel:{Text("30%")})
                            .progressViewStyle(BarProgessStyle(height: 50.0))
                            .padding(20)

                }

                HStack{

                    // ARView 按鈕：點擊後開啟 AR 攝影機畫面
                    Button("ARView") {
                        ARMode = true
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .foregroundColor(.orange)
                    .cornerRadius(14)
                    .font(.title3.bold())


                    // TripWith 按鈕：尚未實作功能（預留位置）
                    Button("TripWith"){
                        // 此處放入你的旅行功能邏輯
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .foregroundColor(.orange)
                    .cornerRadius(14)
                    .font(.title3.bold())

                }// HStack end


            } // VStack end

        } //Zstack end
        .presentationBackground(.clear)  // sheet 背景透明，顯示底層內容

        // ARMode 為 true 時，全螢幕彈出 AR 畫面
        .fullScreenCover(isPresented: $ARMode){
            PetARView()
        }

    }//body end


} //View end

// 進度條樣式：可自訂顏色、高度，並在填充區疊加數值標籤
struct BarProgessStyle: ProgressViewStyle {

    var color:  Color = .yellow  // 進度條填充顏色
    var height: Double =  20.0  // 進度條高度
    var labelFontStyle: Font = .body  // 標籤文字字型

    // 建構自訂進度條外觀
    func makeBody(configuration: Configuration)-> some View{
        let progess = configuration.fractionCompleted ?? 0.0  // 完成比例（0.0~1.0）
        GeometryReader{ geometry in
            VStack(alignment: .leading){
                configuration.label.font(labelFontStyle)  // 標籤（如 "mood"）
                RoundedRectangle(cornerRadius: 10.0)
                    .fill(Color(uiColor:.systemGray5))  // 背景軌道顏色
                    .frame(height: height)
                    .frame(width: geometry.size.width)
                    .overlay(alignment: .leading){
                        RoundedRectangle(cornerRadius: 10.0)
                            .fill(color)  // 填充顏色
                            .frame(width: geometry.size.width*progess)  // 依比例填充寬度
                            .overlay{
                                if let currentValueLabel = configuration.currentValueLabel{
                                    currentValueLabel
                                        .font(.headline)
                                        .foregroundStyle(.white)  // 顯示在填充區上的數值文字
                                }
                            }
                    }
            }
        }
    }
}
