//
//  PetARView.swift
//  AR with 3D cat model + tracking
//

import SwiftUI
import RealityKit
import ARKit

// AR 全螢幕畫面：顯示相機畫面並疊加 3D 貓咪模型
struct PetARView: View {
    @Environment(\.dismiss) var dismiss  // 用於關閉此全螢幕畫面
    @State private var isLoading = true  // 是否顯示載入中畫面
    @State private var arSession = ARSession()  // 此畫面專用的 AR Session

    var body: some View {
        ZStack {
            // AR 相機畫面 + 3D 貓咪模型
            ARViewWithCat(arSession: arSession)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // 顯示載入畫面 2.5 秒後自動隱藏（給模型載入時間）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        isLoading = false
                    }
                }
                .onDisappear {
                    // 畫面關閉時暫停 AR Session，釋放相機資源
                    arSession.pause()
                }

            // 載入中畫面：顯示轉圈動畫與文字
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Loading AR with Cat...")
                        .foregroundColor(.white)
                        .font(.system(.body, design: .rounded))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }

            // 左上角關閉按鈕
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .padding()
                            .shadow(radius: 3)
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

// 包裝 ARView，負責顯示相機畫面並載入 3D 貓咪模型
struct ARViewWithCat: UIViewControllerRepresentable {
    var arSession: ARSession  // 由外部傳入的 AR Session

    // 建立 ARView，並依序載入貓咪模型、啟動 AR 追蹤
    func makeUIViewController(context: Context) -> UIViewController {

        // 檢查裝置是否支援 ARWorldTracking
        guard ARWorldTrackingConfiguration.isSupported else {
            return UIViewController()
        }

        let arView = ARView(frame: .zero)  // AR 渲染視圖
        arView.session = arSession

        // 延遲 0.5 秒後載入貓咪 3D 模型
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadCatModel(in: arView)
        }

        // 延遲 1.0 秒後啟動 AR Session（給模型載入留出時間）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let config = ARWorldTrackingConfiguration()  // AR 世界追蹤設定
            config.planeDetection = [.horizontal, .vertical]  // 偵測水平與垂直平面
            config.environmentTexturing = .automatic  // 自動環境貼圖

            // 若裝置支援人物分割（含深度），則啟用此功能
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                config.frameSemantics.insert(.personSegmentationWithDepth)
            }

            arSession.run(config)
        }

        let controller = UIViewController()
        controller.view = arView

        return controller
    }

    // 此元件沒有需要動態更新的內容
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // 將 3D 貓咪模型載入 AR 場景；優先使用 Reality Composer 體驗，否則改用 USDZ
    private func loadCatModel(in arView: ARView) {

        // 嘗試載入 Reality Composer 製作的場景（目前回傳 nil，未實作）
        var anchor = try? Experience.loadCat()  // Reality Composer 場景錨點

        if anchor == nil {
            // 備援方案：直接載入 USDZ 模型檔
            guard let catScene = try? ModelEntity.loadModel(named: "cat.usdz") else {
                return
            }

            // 建立水平平面錨點並設定貓咪位置與縮放
            var modelAnchor = AnchorEntity(plane: .horizontal)  // 水平平面錨點
            catScene.position = [0, 0, -0.5]  // 放在相機前方
            catScene.scale = [0.003, 0.003, 0.003]  // 縮小模型尺寸

            modelAnchor.addChild(catScene)
            arView.scene.addAnchor(modelAnchor)

        } else if let loadedAnchor = anchor {
            // 成功載入 Reality Composer 場景，直接加入
            arView.scene.addAnchor(loadedAnchor)
        }
    }
}

// Reality Composer 體驗的預留介面（尚未實作）
enum Experience {
    // 嘗試載入 Reality Composer 製作的貓咪場景；若有對應專案可在此實作
    static func loadCat() throws -> AnchorEntity? {
        return nil
    }
}
