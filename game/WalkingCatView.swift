//
//  WalkingCatView.swift
//  game
//
//  GoWorld 地圖上的小貓：用 SceneKit 顯示 cat.usdz，播放它內建的走路動畫（原地踏步），背景透明。
//  跟 Cat3DView 不一樣：不會到處亂走、不能點、也沒有 Timer。
//

import SwiftUI   // SwiftUI 畫面
import SceneKit  // 3D 場景（跟 Cat3DView 一樣用 SceneKit）

// ── GoWorld 地圖的設定（全部放在這裡，方便調整）──────────────────────────
enum WalkMapTuning {
    static let catSize: CGFloat = 120       // 小貓在地圖上的大小（點）。太小 → 調大；擋住路 → 調小
    static let catTurnDegrees: Float = 180  // 小貓的朝向：180 = 背對你、往地圖前方走；0 = 面向你；150 或 210 = 斜一點，看得到側面
    static let followsHeading = true        // true = 地圖跟著你面向的方向轉（前方永遠在上面）；false = 北方永遠在上面
}

// 地圖上原地走路的 3D 小貓
struct WalkingCatView: UIViewRepresentable {

    // 建立 SceneKit 畫面：載入貓 → 調整大小和位置 → 轉身 → 播走路動畫 → 打燈 → 放相機
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()                               // SceneKit 渲染視圖
        sceneView.scene = SCNScene()                            // 建立空場景
        sceneView.backgroundColor = .clear                      // 背景透明 → 看得到下面的地圖
        sceneView.isUserInteractionEnabled = false              // 不接收手指 → 手勢都交給地圖（縮放、傾斜）

        // 載入 cat.usdz，失敗就回傳空畫面（跟 Cat3DView 一樣）
        guard let catScene = SCNScene(named: "cat.usdz") else {
            return sceneView
        }

        // 取得貓模型的根節點，失敗就回傳空畫面（跟 Cat3DView 一樣）
        guard let catNode = catScene.rootNode.childNodes.first else {
            return sceneView
        }

        // TODO A：用 addChildNode 把 catNode 加到場景的 rootNode 上
        //         （sceneView.scene 是 optional，所以要寫 sceneView.scene?.rootNode…）

        // ── 讓貓剛好裝進這個小畫面（不管模型原本的單位多大）──
        let (minCorner, maxCorner) = catNode.boundingBox                          // 貓的外框：最小角、最大角（模型自己的單位）
        let centerX = (minCorner.x + maxCorner.x) / 2                             // 外框中心的 x
        let centerZ = (minCorner.z + maxCorner.z) / 2                             // 外框中心的 z
        catNode.pivot = SCNMatrix4MakeTranslation(centerX, minCorner.y, centerZ)  // 中心點 = 腳底正中間（轉身、縮放都繞著這裡）
        let longestSide = max(maxCorner.x - minCorner.x,                          // 外框的寬
                              maxCorner.y - minCorner.y,                          // 外框的高
                              maxCorner.z - minCorner.z)                          // 外框的長 → 三個取最大的
        if longestSide > 0 {                                                      // 外框有大小才縮放（避免除以 0）
            let fitScale = 1 / longestSide                                        // 縮放倍數：讓最長的一邊變成 1
            catNode.scale = SCNVector3(fitScale, fitScale, fitScale)              // 三個方向一樣縮放（不會變形）
        }
        catNode.position = SCNVector3(0, 0, 0)                                    // 腳底正中間放在場景的原點

        // TODO B：讓貓轉身 → 把 catNode.eulerAngles.y 設成 WalkMapTuning.catTurnDegrees 換成的「弧度」
        //         （角度換弧度：× .pi ÷ 180）

        // 播放 cat.usdz 內建的走路動畫，無限重複（函式在最下面，裡面有 TODO D1、D2）
        playWalkAnimationForever(on: catNode)

        // 環境光（亮度跟 Cat3DView 一樣）
        let ambientLight = SCNNode()                            // 環境光節點
        ambientLight.light = SCNLight()                         // 加一盞燈
        ambientLight.light?.type = .ambient                     // 環境光：四面八方均勻照亮
        ambientLight.light?.intensity = 1000                    // 亮度
        sceneView.scene?.rootNode.addChildNode(ambientLight)    // 加進場景

        // 方向光（像太陽，讓貓有亮面和暗面）
        let directionLight = SCNNode()                          // 方向光節點
        directionLight.light = SCNLight()                       // 加一盞燈
        directionLight.light?.type = .directional               // 方向光
        directionLight.light?.intensity = 1500                  // 亮度
        directionLight.position = SCNVector3(5, 10, 10)         // 位置（跟 Cat3DView 一樣）
        sceneView.scene?.rootNode.addChildNode(directionLight)  // 加進場景

        // 相機：放在貓的後上方（貓最長的一邊 = 1，所以高 0.7、遠 1.2 剛好看到整隻）
        let cameraNode = SCNNode()                              // 相機節點
        cameraNode.camera = SCNCamera()                         // 加一台相機
        cameraNode.position = SCNVector3(0, 0.7, 1.2)           // 上方 0.7、後方 1.2

        // TODO C：用 cameraNode 的 look(at:) 讓相機看著貓身體的中間 SCNVector3(0, 0.3, 0)

        sceneView.scene?.rootNode.addChildNode(cameraNode)      // 加進場景
        sceneView.pointOfView = cameraNode                      // 用這台相機看

        return sceneView
    }

    // 這個畫面不需要跟著 SwiftUI 的狀態更新
    func updateUIView(_ uiView: SCNView, context: Context) {}

    // 播放 node 和它所有子節點內建的動畫，無限重複
    // （跟 Cat3DView 的 playEmbeddedAnimations 一樣：USDZ 的動畫常常掛在子節點上，所以要往下找完整個階層）
    private func playWalkAnimationForever(on node: SCNNode) {
        node.enumerateHierarchy { child, _ in                   // 走過 node 和它底下的每一個子節點
            for key in child.animationKeys {                    // 這個子節點身上的每一段動畫
                guard let player = child.animationPlayer(forKey: key) else {  // 拿到這段動畫的播放器
                    continue                                    // 拿不到 → 看下一段
                }

                // TODO D1：讓動畫無限重複 → 把 player.animation.repeatCount 設成 .greatestFiniteMagnitude
                // TODO D2：開始播放 → 呼叫 player 的 play()
            }
        }
    }
}

#Preview {
    WalkingCatView()                                    // 在 Xcode 預覽裡看走路的小貓
        .frame(width: 200, height: 200)                 // 預覽的大小
        .background(Color.green.opacity(0.3))           // 淡綠色底 → 看得出畫面的範圍（真正用的時候是透明的）
}
