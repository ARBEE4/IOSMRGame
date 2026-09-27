//
//  PetARView.swift
//  AR with 3D cat model + hand-tracking pinch-and-drag control
//
//  手部追蹤（HandTracker / FingerOverlay）的核心邏輯搬到 HandTracking.swift，
//  這個檔案只負責：AR 畫面本身的組成，以及「貓咪控制器」—— 移植自 testAR 專案的
//  BlockController，把原本操控的藍色方塊換成 cat.usdz 載入的貓咪模型，
//  捏合手勢照舊，可以把貓咪從螢幕上抓起來、拖著移動。
//

import SwiftUI
import RealityKit
import ARKit
import Combine
import simd

// AR 全螢幕畫面：顯示相機畫面，疊加可用手勢抓取移動的 3D 貓咪，並疊加手指追蹤視覺化圖層
struct PetARView: View {
    @Environment(\.dismiss) var dismiss  // 用於關閉此全螢幕畫面
    @State private var isLoading = true  // 是否顯示載入中畫面
    @State private var arSession = ARSession()  // 此畫面專用的 AR Session

    // 手部追蹤參數與追蹤器：與 testAR 專案共用同一份邏輯（見 HandTracking.swift）
    private let tuning = HandTrackingTuning.standard
    @State private var tracker = HandTracker(tuning: .standard)
    // 重置用的計數器。用計數器而不是 Bool，就不需要在畫面更新中把旗標寫回 false。
    @State private var resetCounter = 0

    var body: some View {
        ZStack {
            // 第一層：AR 相機畫面 + 可用手勢抓取移動的 3D 貓咪
            ARViewWithCat(arSession: arSession, tracker: tracker, tuning: tuning, resetCounter: resetCounter)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // 顯示載入畫面 2.5 秒後自動隱藏（給模型載入時間）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        isLoading = false
                    }
                }
                .onDisappear {
                    // 畫面關閉時暫停 AR Session、停止手部追蹤，釋放相機資源、避免背景繼續耗電
                    arSession.pause()
                    tracker.stop()
                }

            // 第二層：手指圓點視覺化（拇指／食指／捏合連線），獨立成一層避免拖慢 AR 畫面重繪
            GeometryReader { geo in
                FingerOverlay(tracker: tracker)
                    .onAppear { tracker.viewportSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in tracker.viewportSize = newSize }
            }
            .ignoresSafeArea()

            // 第三層：載入中畫面：顯示轉圈動畫與文字
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

            // 第四層：關閉鈕、重置貓咪按鈕，由上而下排在同一個 VStack 避免互相疊在一起
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

                // 捏合抓不到貓咪、或貓咪被拖到畫面外時，用這顆按鈕把牠放回鏡頭正前方
                Button("Reset Cat") {
                    resetCounter += 1   // 數字一變，CatController 就會把貓咪放回鏡頭正前方
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(14)
                .font(.title3.bold())
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - AR 容器

/// 包裝 RealityKit 的 ARView，並串接手部追蹤 + 貓咪抓取控制器。
struct ARViewWithCat: UIViewRepresentable {
    var arSession: ARSession        // 由外部（PetARView）傳入並管理生命週期的 AR Session
    let tracker: HandTracker        // 手部追蹤器，狀態由 HandTracking.swift 提供
    let tuning: HandTrackingTuning  // 追蹤與抓取相關的可調參數
    var resetCounter: Int           // 數字變動時，CatController 會把貓咪重新放回鏡頭正前方

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = arSession   // 沿用外部傳入的 session，讓 PetARView 統一管理暫停/釋放

        // 裝置不支援 AR：回傳空白的相機畫面，不繼續設定
        guard ARWorldTrackingConfiguration.isSupported else {
            return arView
        }

        if tuning.disableExpensiveRenderEffects {
            // 關掉用不到的畫面特效，把 GPU 留給穩定的畫面更新率
            arView.renderOptions = [.disableMotionBlur,
                                    .disableDepthOfField,
                                    .disableCameraGrain,
                                    .disableHDR,
                                    .disableGroundingShadows,
                                    .disablePersonOcclusion]
        }

        context.coordinator.attach(to: arView, tracker: tracker, tuning: tuning)
        return arView
    }

    // 手部追蹤更新頻率很高（每秒 30 次），這裡只做一次整數比較，幾乎沒有成本
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.handleResetIfNeeded(counter: resetCounter)
    }

    func makeCoordinator() -> CatController { CatController() }
}

// MARK: - 貓咪控制器
//
// 移植自 testAR 專案的 BlockController：一樣負責「建立、抓取狀態機、每張畫面平滑內插」，
// 差別只在於操控的對象從程式產生的藍色方塊，換成從 cat.usdz 載入的貓咪模型
// （並且沿用先前加入的「播放內建動畫」邏輯，讓貓咪被拖著移動時腳步動畫也同時播放）。
final class CatController {

    private weak var arView: ARView?
    private var tracker: HandTracker?
    private var tuning = HandTrackingTuning.standard

    private var cat: ModelEntity?
    private var renderSubscription: Cancellable?

    /// 貓咪「想去」的世界座標。實際位置每張畫面往這裡靠近一點，所以移動是滑順的。
    private var targetWorldPosition: SIMD3<Float> = .init(repeating: 0)
    /// 貓咪投影到螢幕上的位置，抓取判定用。貓咪跑到畫面外時為 nil。
    private var catScreenPosition: CGPoint?

    private var isHolding = false
    private var wasPinching = false
    /// 抓取瞬間「貓咪」與「捏合中心」的螢幕位移，維持這個位移貓咪才不會瞬移到指尖
    private var grabScreenOffset: CGSize = .zero
    /// 抓取瞬間貓咪離相機的距離，拖動過程中維持不變（等於在同一個深度平面上移動）
    private var grabDistanceFromCamera: Float = 0.5

    private var hasPlacedCat = false
    private var lastHandledResetCounter = 0

    deinit {
        renderSubscription?.cancel()
    }

    // ── 建立 ───────────────────────────────────────────────────

    func attach(to arView: ARView, tracker: HandTracker, tuning: HandTrackingTuning) {
        self.arView = arView
        self.tracker = tracker
        self.tuning = tuning

        // 啟動 AR。不開平面偵測：貓咪是靠手勢直接在螢幕空間拖動，不是放在偵測到的平面上，開了也用不到。
        let config = ARWorldTrackingConfiguration()
        // 若裝置支援人物分割（含深度），則啟用此功能，讓真實的手可以正確遮擋虛擬貓咪
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        arView.session.run(config)

        // 讓追蹤器共用 ARView 自己的 session（session 只有一個擁有者，狀態不會打架）
        tracker.start(session: arView.session)

        // 載入 cat.usdz。先掛在世界原點，第一張有效影格出現時再擺到鏡頭前
        // （比固定延遲幾秒再擺放可靠，因為是真的等到 ARKit 有畫面才動作）。
        guard let catEntity = try? ModelEntity.loadModel(named: "cat.usdz") else {
            return
        }
        catEntity.scale = SIMD3<Float>(repeating: tuning.catScale)

        // 播放 cat.usdz 內建的動畫（例如走路、待機等動作），並設為無限重複播放
        for animation in catEntity.availableAnimations {
            catEntity.playAnimation(animation.repeat())
        }

        let anchor = AnchorEntity(world: SIMD3<Float>(repeating: 0))
        anchor.addChild(catEntity)
        arView.scene.addAnchor(anchor)
        self.cat = catEntity

        // 每張算圖畫面（約 60fps）跑一次。
        // 這是「順不順」的關鍵：偵測只有 30fps，但貓咪是 60fps 內插移動。
        renderSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onRender(deltaTime: event.deltaTime)
        }
    }

    // ── 每張畫面 ───────────────────────────────────────────────

    private func onRender(deltaTime: TimeInterval) {
        guard let arView, let cat, let tracker else { return }

        // 第一次拿到相機資料 → 把貓咪放到鏡頭正前方
        if !hasPlacedCat, arView.session.currentFrame != nil {
            hasPlacedCat = true
            placeCatInFrontOfCamera()
        }

        let currentWorld = cat.position(relativeTo: nil)

        // 貓咪模型的原點通常在腳底（USDZ 常見慣例），但使用者會直覺地對著「身體」捏合，
        // 所以這裡另外算出視覺外框的中心點，抓取判定要用這個點，而不是腳底的原點。
        let centerOffset = cat.visualBounds(relativeTo: nil).center - currentWorld

        // 更新貓咪「身體中心」在螢幕上的位置（抓取判定要用）
        catScreenPosition = arView.project(currentWorld + centerOffset)

        // 更新抓取狀態（貓咪大小固定，不會被捏合改變）
        updateGrab(arView: arView, tracker: tracker, currentWorld: currentWorld, centerOffset: centerOffset)

        // 平滑移動：以固定的時間常數往目標靠近。
        // 用 exp 而不是固定比例，是為了讓結果與畫面更新率無關（60fps 和 30fps 手感一致）。
        let moveAlpha = Float(1 - exp(-deltaTime / max(tuning.catFollowTime, 0.001)))
        cat.setPosition(currentWorld + (targetWorldPosition - currentWorld) * moveAlpha, relativeTo: nil)
    }

    // ── 抓取狀態機 ─────────────────────────────────────────────

    private func updateGrab(arView: ARView, tracker: HandTracker, currentWorld: SIMD3<Float>, centerOffset: SIMD3<Float>) {
        let pinching = tracker.isPinching

        // 剛捏下去的那一瞬間：判斷有沒有捏到貓咪（比對「身體中心」在螢幕上的位置，不是腳底）
        if pinching, !wasPinching {
            if let catScreen = catScreenPosition {
                let dx = catScreen.x - tracker.pinchMidpoint.x
                let dy = catScreen.y - tracker.pinchMidpoint.y
                if sqrt(dx * dx + dy * dy) < tuning.grabRadiusInPixels {
                    isHolding = true
                    grabScreenOffset = CGSize(width: dx, height: dy)     // 記住相對位置，貓咪不會瞬移
                    // 用「身體中心」到相機的距離，而不是腳底的原點，抓取深度才正確
                    grabDistanceFromCamera = max(length(currentWorld + centerOffset - arView.cameraTransform.translation), 0.1)
                }
            }
        }

        // 放開捏合 → 一定放開貓咪
        if !pinching { isHolding = false }

        // 持續拖動中：更新位置（貓咪大小固定，不會被捏合改變）
        if pinching, isHolding, tracker.canDrag {
            // 貓咪身體中心該出現在螢幕上的哪個位置
            let targetScreen = CGPoint(x: tracker.pinchMidpoint.x + grabScreenOffset.width,
                                       y: tracker.pinchMidpoint.y + grabScreenOffset.height)

            // 從螢幕位置射一條射線出去，取抓取時的深度 → 得到「身體中心」該在的世界座標。
            // 這樣做的好處：不需要任何座標軸對調或正負號猜測，手機轉成任何角度都正確。
            if let ray = arView.ray(through: targetScreen) {
                let centerCandidate = ray.origin + normalize(ray.direction) * grabDistanceFromCamera
                // 換算回「原點」該放的位置（原點 = 身體中心 − 偏移量），setPosition 動的是原點
                let candidate = centerCandidate - centerOffset
                // 跳動守衛：一次跳太遠視為追蹤誤判，直接忽略
                if length(candidate - targetWorldPosition) < tuning.maximumJumpInMeters {
                    targetWorldPosition = candidate
                }
            }
        }

        wasPinching = pinching
    }

    // ── 重置 ───────────────────────────────────────────────────

    /// 只有計數器變動時才真的重置。
    func handleResetIfNeeded(counter: Int) {
        guard counter != lastHandledResetCounter else { return }
        lastHandledResetCounter = counter
        placeCatInFrontOfCamera()
    }

    /// 把貓咪放到鏡頭正前方（不重建實體，只是移動位置）
    private func placeCatInFrontOfCamera() {
        guard let arView, let cat else { return }

        let camera = arView.cameraTransform
        let matrix = camera.matrix
        // 相機矩陣第 3 欄是「後方」，取負號才是前方（ARKit 用右手座標系，-Z 為前）
        let forward = -SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)

        let position = camera.translation + normalize(forward) * tuning.catSpawnDistance
        targetWorldPosition = position
        cat.setPosition(position, relativeTo: nil)    // 重置時直接歸位，不需要平滑
        isHolding = false
        grabDistanceFromCamera = tuning.catSpawnDistance

        // 大小固定不變，這裡只是確保重置後仍是基準值
        cat.scale = SIMD3<Float>(repeating: tuning.catScale)
    }
}
