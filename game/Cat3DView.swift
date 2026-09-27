// Manage Cat Model

import SwiftUI
import SceneKit

// 使用 SceneKit 顯示 3D 貓咪模型，含隨機移動動畫與點擊偵測
struct Cat3DView: UIViewRepresentable {
    var onCatTapped: () -> Void  // 貓咪被點擊時的回呼

    // 建立 SceneKit 場景：載入貓咪模型、設定燈光、相機、動畫與點擊手勢
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()  // SceneKit 渲染視圖
        sceneView.scene = SCNScene()  // 建立空場景
        sceneView.backgroundColor = .clear  // 背景透明，讓上層 UI 可疊加

        // 加入點擊手勢，點擊後呼叫 Coordinator 的 handleTap
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)

        // 載入 cat.usdz 模型，失敗則回傳空場景
        guard let catScene = SCNScene(named: "cat.usdz") else {
            return sceneView
        }

        // 取得模型的根節點，失敗則回傳空場景
        guard let catNode = catScene.rootNode.childNodes.first else {
            return sceneView
        }

        // 將貓咪節點加入場景，並設定初始位置
        sceneView.scene?.rootNode.addChildNode(catNode)
        catNode.position = SCNVector3(0, 0, -0.7)  // 放在相機前方

        // 縮小貓咪模型尺寸（原始模型過大）
        catNode.scale = SCNVector3(0.001, 0.001, 0.001)

        // 播放 cat.usdz 內建的動畫（例如走路、待機等動作），並設為無限重複播放
        playEmbeddedAnimations(on: catNode)

        // 環境光
        let ambientLight = SCNNode()  // 環境光節點
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 1000
        sceneView.scene?.rootNode.addChildNode(ambientLight)

        // 方向光
        let directionLight = SCNNode()  // 方向光節點
        directionLight.light = SCNLight()
        directionLight.light?.type = .directional
        directionLight.light?.intensity = 1500
        directionLight.position = SCNVector3(5, 10, 10)
        sceneView.scene?.rootNode.addChildNode(directionLight)

        // 設定觀察相機並指定為主視角
        let cameraNode = SCNNode()  // 相機節點
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.3, 1.2)
        sceneView.scene?.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        // 啟動貓咪隨機漫步動畫
        startRandomMovement(catNode)

        // 將 sceneView 存入 Coordinator，供點擊判斷使用
        context.coordinator.sceneView = sceneView

        return sceneView
    }

    // 此元件沒有需要動態更新的內容
    func updateUIView(_ uiView: SCNView, context: Context) {}

    // 建立 Coordinator，並傳入點擊回呼
    func makeCoordinator() -> Coordinator {
        Coordinator(onCatTapped: onCatTapped)
    }

    //處理點擊事件的 Coordinator
    class Coordinator {
        var onCatTapped: () -> Void  // 點擊貓咪後要執行的回呼
        var sceneView: SCNView?  // SceneKit 視圖參考，用於點擊測試

        init(onCatTapped: @escaping () -> Void) {
            self.onCatTapped = onCatTapped
        }

        // 處理點擊手勢：判斷是否點擊到貓咪模型，若是則觸發回呼
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = sceneView else { return }
            let location = gesture.location(in: sceneView)  // 點擊位置（螢幕座標）

            // 對點擊位置做場景碰撞測試
            let hitResults = sceneView.hitTest(location, options: [:])

            // 若擊中任何節點，視為點到貓咪，觸發回呼
            if !hitResults.isEmpty {
                onCatTapped()
            }
        }
    }

    // 遞迴播放節點及其所有子節點內建的動畫
    // （USDZ 模型的動畫通常掛在子節點上，例如骨架關節，所以要往下找完整個階層）
    private func playEmbeddedAnimations(on node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            for key in child.animationKeys {
                guard let player = child.animationPlayer(forKey: key) else { continue }
                player.animation.repeatCount = .greatestFiniteMagnitude  // 無限重複播放
                player.play()
            }
        }
    }

    // 貓咪隨機漫步動畫
    // 讓貓咪在指定範圍內隨機選擇目標點移動，到達後暫停一段時間再選新目標
    private func startRandomMovement(_ catNode: SCNNode) {

        var targetX: Float = Float.random(in: -0.4...0.4)  // 目標位置 X（隨機）
        var targetZ: Float = Float.random(in: -0.8...0.0)  // 目標位置 Z（隨機）
        var currentX: Float = 0  // 目前位置 X
        var currentZ: Float = -0.5  // 目前位置 Z
        var isPaused = false  // 是否處於暫停（到達目標後的休息）狀態

        let speed: Float = 0.001  // 每幀移動速度
        let moveInterval = 0.016 // ~60 FPS

        // 每幀更新貓咪位置與朝向
        Timer.scheduledTimer(withTimeInterval: moveInterval, repeats: true) { timer in
            // 計算目前位置到目標位置的距離
            let dx = targetX - currentX
            let dz = targetZ - currentZ
            let distance = sqrt(dx*dx + dz*dz)

            // 已到達目標附近：進入暫停，並在隨機時間後選擇新目標
            if distance < 0.05 {
                if !isPaused {
                    isPaused = true

                    // 暫停 0.5~2.0 秒後重新選擇目標位置
                    let pauseTime = Double.random(in: 0.5...2.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + pauseTime) {
                        targetX = Float.random(in: -0.4...0.4)
                        targetZ = Float.random(in: -0.8...0.0)
                        isPaused = false
                    }
                }
                return
            }

            // 未到達目標且非暫停中：朝目標方向移動並轉向
            if !isPaused && distance > 0.01 {
                currentX += (dx / distance) * speed
                currentZ += (dz / distance) * speed

                // 更新貓咪位置（Y 固定，模擬地面高度）
                catNode.position = SCNVector3(currentX, -0.1, currentZ)

                // 計算面向移動方向所需的旋轉角度
                let angle = atan2(dx, dz)  // 移動方向角度
                let targetRotation = SCNVector4(0, 1, 0, angle)  // 繞 Y 軸旋轉

                // 以動畫平滑過渡到新的旋轉角度
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.1
                catNode.rotation = targetRotation
                SCNTransaction.commit()
            }
        }
    }
}
