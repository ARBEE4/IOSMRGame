import SwiftUI
import RealityKit
import ARKit

// 包裝 ARView 成 SwiftUI 可用元件，建立基本 AR 場景（無方塊、無手部追蹤）
struct ARViewContainer: UIViewControllerRepresentable {
    var arSession: ARSession  // 由外部傳入的 AR Session

    // 建立並設定 ARView，延遲啟動 AR 追蹤
    func makeUIViewController(context: Context) -> UIViewController {

        // 檢查裝置是否支援 ARWorldTracking，不支援則回傳空白畫面
        guard ARWorldTrackingConfiguration.isSupported else {
            return UIViewController()
        }

        // 建立 ARView 並指定 Session
        let arView = ARView(frame: .zero)
        arView.session = arSession

        // 建立容器 ViewController
        let controller = UIViewController()

        // 將 ARView 設為主視圖（非子視圖），確保佔滿整個畫面
        controller.view = arView

        // 延遲 0.8 秒後啟動 AR Session，等待視圖層級建立完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {

            let configuration = ARWorldTrackingConfiguration()  // AR 世界追蹤設定
            configuration.planeDetection = [.horizontal, .vertical]  // 偵測水平與垂直平面
            configuration.environmentTexturing = .automatic  // 自動環境貼圖（用於反射效果）

            // 若裝置支援人物分割（含深度），則啟用此功能
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                configuration.frameSemantics.insert(.personSegmentationWithDepth)
            }

            // 啟動 AR Session
            self.arSession.run(configuration)
        }

        return controller
    }

    // 此元件沒有需要動態更新的內容
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}
