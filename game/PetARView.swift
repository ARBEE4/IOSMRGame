//
//  PetARView.swift
//  AR with 3D cat model + hand-tracking pinch-and-drag control
//
//  手部追蹤（HandTracker / FingerOverlay）的核心邏輯搬到 HandTracking.swift，
//  這個檔案只負責：AR 畫面本身的組成，以及「貓咪控制器」—— 移植自 testAR 專案的
//  BlockController，把原本操控的藍色方塊換成 cat.usdz 載入的貓咪模型，
//  捏合手勢照舊，可以把貓咪從螢幕上抓起來、拖著移動。
//
//  揮手撫摸：張開的手在貓咪上方來回揮動 → 貓咪坐下、左右歪頭、冒出愛心，播完繼續走路
//  （判斷規則在 PetStrokeDetector.swift，換貓與播放在 CatPetSwap.swift，參數在 HandTrackingTuning）。
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

    // build handtracker call HandTracking.swift
    private let tuning = HandTrackingTuning.standard
    @State private var tracker = HandTracker(tuning: .standard)
    // 重置用的計數器。用計數器而不是 Bool，就不需要在畫面更新中把旗標寫回 false。
    @State private var resetCounter = 0
    // 拍照用的計數器（和 resetCounter 同樣的做法）：數字一變，CatController 就拍一張 AR 畫面存進相簿
    @State private var photoCounter = 0
    // 拍照時白色閃光的透明度：0 = 看不見，1 = 全白
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            // 第一層：AR 相機畫面 + 可用手勢抓取移動的 3D 貓咪
            ARViewWithCat(arSession: arSession, tracker: tracker, tuning: tuning, resetCounter: resetCounter, photoCounter: photoCounter)
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
                FingerOverlay(tracker: tracker) // call function from handtracking
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

                // 底部按鈕列：左邊 Reset Cat，右邊拍照
                HStack(spacing: 16) {
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

                    // 拍照按鈕：把現在的 AR 畫面（相機畫面＋貓咪）存進相簿
                    Button {
                        takePhoto()
                    } label: {
                        Image(systemName: "camera.fill")   // 相機圖示
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .font(.title3.bold())
                }
                .padding(.bottom, 30)
            }

            // 第五層：拍照時的白色閃光，蓋住整個畫面一下下。
            // 它是 SwiftUI 的一層，照片只拍 AR 畫面，所以閃光不會出現在照片裡。
            Color.white
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)   // 閃光不擋觸控
        }
    }

    /// 按下拍照：通知 CatController 拍照，同時讓畫面白閃一下
    private func takePhoto() {
        photoCounter += 1                                   // 數字一變，CatController 就拍一張 AR 畫面存進相簿
        flashOpacity = 1                                    // 閃光：先全白
        // 等畫面真的變白之後，再慢慢淡掉。
        // （如果同一瞬間先設 1 再設 0，SwiftUI 只會看到最後的 0，閃光就不會出現）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.35)) {
                flashOpacity = 0                            // 0.35 秒內淡回透明
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
    var photoCounter: Int           // 數字變動時，CatController 會拍一張 AR 畫面存進相簿

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
        context.coordinator.takePhotoIfNeeded(counter: photoCounter)
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
    /// 拿起貓咪時的位置（第一個點）。放手時如果貓咪身體完全沒碰到綠色水平面，就跳回這裡。
    private var grabStartPosition: SIMD3<Float> = .init(repeating: 0)

    // ── 水平面顯示（自己畫的淡色平面，取代 .showAnchorGeometry）──────────────

    /// 每一塊偵測到的水平面 → 畫它的那個錨點（裡面掛著淡色平面模型）。鑰匙是 ARKit 給每塊平面的編號。
    private var planeOverlays: [UUID: AnchorEntity] = [:]
    /// 距離上次更新平面形狀過了多久（秒）。形狀每 0.2 秒更新一次就夠了，不用每張畫面都重做（省效能）。
    private var timeSincePlaneOverlayUpdate: TimeInterval = 0

    private var hasPlacedCat = false
    private var lastHandledResetCounter = 0
    private var lastHandledPhotoCounter = 0   // 上一次處理過的拍照計數（同一次按鈕只拍一張）

    // ── 撫摸反應（坐下、歪頭、冒愛心）───────────────────────────────

    /// 走路貓 ↔ 撫摸反應貓 的切換器（見 CatPetSwap.swift）。載入完成前是 nil，這段時間不能撫摸。
    private var catSwap: CatPetSwap?
    /// CatPetSwap 載入完成前，先用原本的方式播放走路動畫；載入完成後停掉，交給 CatPetSwap 播。
    private var fallbackWalkControllers: [AnimationPlaybackController] = []
    /// 揮手（撫摸）偵測器（見 PetStrokeDetector.swift）
    private var petDetector = PetStrokeDetector()
    /// 撫摸偵測用的時鐘：每張畫面累加 deltaTime（秒）
    private var petClock: TimeInterval = 0
    /// 手已經離開「貓咪範圍」多久了（秒），超過寬限時間就清空撫摸進度
    private var timeOutsidePetZone: TimeInterval = 0
    /// 距離上一次捏合／抓著貓咪過了多久（秒）。放開後要等 petCooldownAfterPinch 才開始算揮手。
    /// 一開始設很大，代表「很久沒捏了」，進畫面就能直接摸。
    private var timeSincePinch: TimeInterval = 999

    /// 撫摸反應是否正在播放。
    /// CatPetSwap 是 @MainActor 類別；這裡的呼叫都發生在主執行緒（畫面更新、SwiftUI），
    /// 所以用 MainActor.assumeIsolated 告訴編譯器「現在就在主執行緒上」。
    private var isReacting: Bool {
        let reacting: Bool = MainActor.assumeIsolated {
            if let swap = catSwap {                  // 反應檔已經載入
                return swap.isReacting               // 回傳它是不是正在播放
            } else {
                return false                         // 還沒載入 → 一定沒有在播放
            }
        }
        return reacting
    }

    deinit {
        renderSubscription?.cancel()
    }

    // ── 建立 ───────────────────────────────────────────────────

    func attach(to arView: ARView, tracker: HandTracker, tuning: HandTrackingTuning) {
        self.arView = arView
        self.tracker = tracker
        self.tuning = tuning
        
        // 啟動 AR。不開平面偵測：貓咪是靠手勢直接在螢幕空間拖動，不是放在偵測到的平面上，開了也用不到。
        // 也不開人物分割（personSegmentationWithDepth）：上面的 .disablePersonOcclusion 已經關掉「手遮住貓咪」，
        // 開了只會多耗電，還會在主控台印出 "padding deconvolution…" 訊息。
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        arView.session.run(config)
        // 開發用：內建的平面顯示（.showAnchorGeometry）會蓋在貓咪上面，而且不能改顏色、不能調前後順序，
        // 所以改用自己畫的淡色平面（見 updatePlaneOverlays），它是場景裡真正的 3D 物體，會在貓咪下面。
        // 想和內建的比較時，把下一行前面的 // 拿掉即可。
        // arView.debugOptions.insert(.showAnchorGeometry)
        
        // 讓追蹤器共用 ARView 自己的 session（session 只有一個擁有者，狀態不會打架）
        tracker.start(session: arView.session)

        // 載入 cat.usdz。先掛在世界原點，第一張有效影格出現時再擺到鏡頭前
        // （比固定延遲幾秒再擺放可靠，因為是真的等到 ARKit 有畫面才動作）。
        guard let catEntity = try? ModelEntity.loadModel(named: "cat.usdz") else {
            return
        }
        catEntity.scale = SIMD3<Float>(repeating: tuning.catScale)

        // 播放 cat.usdz 內建的動畫（例如走路、待機等動作），並設為無限重複播放。
        // 記住這些播放控制器：撫摸反應載入完成後要停掉它們，改由 CatPetSwap 接手播放走路。
        for animation in catEntity.availableAnimations {
            fallbackWalkControllers.append(catEntity.playAnimation(animation.repeat()))
        }

        let anchor = AnchorEntity(world: SIMD3<Float>(repeating: 0))
        anchor.addChild(catEntity)
        arView.scene.addAnchor(anchor)
        self.cat = catEntity

        // 在背景載入撫摸反應（cat_sit_headturn_hearts.usdz），放在走路貓旁邊並先隱藏。
        // 必須在貓咪加進場景之後才呼叫：CatPetSwap 要和走路貓用同一個父節點（anchor）。
        loadPetReaction(for: catEntity)

        // 每張算圖畫面（約 60fps）跑一次。
        // 這是「順不順」的關鍵：偵測只有 30fps，但貓咪是 60fps 內插移動。
        renderSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onRender(deltaTime: event.deltaTime)
        }
    }

    /// 載入撫摸反應並接手走路動畫。
    /// 載入是非同步的（iOS 18 的 Entity(named:)），不會卡住畫面；失敗時貓咪維持原本的走路動畫，只是不能撫摸。
    private func loadPetReaction(for walkingCat: ModelEntity) {
        Task { @MainActor [weak self] in                                   // 在主執行緒上跑非同步工作（RealityKit 物件要在主執行緒使用）
            let swap = CatPetSwap(walkModel: walkingCat)                   // 建立切換器，對象是目前這隻走路貓
            do {
                try await swap.load()                                      // 載入反應檔，放在走路貓旁邊、隱藏、停在第一格
                guard let self else { return }                             // AR 畫面已經關掉 → 不用繼續
                for controller in self.fallbackWalkControllers {           // 原本的每一個走路動畫
                    controller.stop()                                      // 停掉它
                }
                self.fallbackWalkControllers.removeAll()                   // 清空，不再需要
                swap.startWalking()                                        // 改由 CatPetSwap 播走路（它要知道步伐走到哪，才能無縫切換）
                self.catSwap = swap                                        // 從這一刻起可以撫摸
            } catch {
                print("⚠️ 撫摸反應載入失敗，貓咪維持原本的走路動畫：\(error)") // 例如檔案沒加進 App → 看 Xcode 下方的主控台
            }
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

        // 把 ARKit 找到的水平面畫成淡色平面（放在 isReacting 前面：貓咪做撫摸反應時，平面也要繼續更新）
        updatePlaneOverlays(arView: arView, deltaTime: deltaTime)

        // 撫摸反應播放中（坐下 → 歪頭 → 冒愛心 → 起身，約 4.7 秒）：走路貓被隱藏，換成反應貓在原地播動畫。
        // 這段時間暫停抓取、移動與撫摸偵測，播完後貓咪回到同一個位置繼續走路。
        if isReacting {
            isHolding = false                    // 反應中不能抓貓咪
            wasPinching = tracker.isPinching     // 播完時手如果還捏著，不算「剛捏下去」，避免一播完就被抓走
            petDetector.reset()                  // 撫摸進度歸零，避免播完馬上又觸發
            timeOutsidePetZone = 0               // 同上
            return                               // 不移動貓咪（反應貓的位置在切換那一刻就固定了）
        }

        let currentWorld = cat.position(relativeTo: nil)

        // 貓咪目前的 3D 外框（世界座標）。抓取要用它的中心，撫摸要用它在螢幕上的範圍。
        let bounds = cat.visualBounds(relativeTo: nil)

        // 貓咪模型的原點通常在腳底（USDZ 常見慣例），但使用者會直覺地對著「身體」捏合，
        // 所以這裡另外算出視覺外框的中心點，抓取判定要用這個點，而不是腳底的原點。
        let centerOffset = bounds.center - currentWorld

        // 更新貓咪「身體中心」在螢幕上的位置（抓取判定要用）
        catScreenPosition = arView.project(currentWorld + centerOffset)

        // 更新抓取狀態（貓咪大小固定，不會被捏合改變）
        updateGrab(arView: arView, tracker: tracker, currentWorld: currentWorld, centerOffset: centerOffset)

        // 撫摸偵測：手張開、在貓咪上方來回揮動 → 觸發坐下 + 歪頭 + 冒愛心
        updatePetting(arView: arView, tracker: tracker, bounds: bounds, deltaTime: deltaTime)

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
                    // 記住拿起來的地方（第一個點）：放手時貓咪完全沒碰到綠色水平面，就跳回這裡
                    grabStartPosition = targetWorldPosition
                }
            }
        }

        // 放開捏合 → 一定放開貓咪。
        // 放手的瞬間（剛剛還抓著）先檢查貓咪有沒有碰到綠色水平面：有 → 落在綠色上；完全沒有 → 跳回拿起來的地方
        if !pinching {
            if isHolding {                                               // 剛剛還抓著 → 這一格就是「放手的瞬間」
                landOrJumpBack(arView: arView)                           // 落在水平面上，或跳回第一個點
            }
            isHolding = false                                            // 放開貓咪
        }

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

    // ── 水平面（第一版：只用 ARKit 偵測到的綠色平面）──────────────────────

    /// 螢幕上的一個點往畫面裡看：如果碰到「偵測到的水平面」（綠色），回傳碰到的 3D 位置；沒碰到就回傳 nil。
    private func horizontalSurfacePoint(at screenPoint: CGPoint, in arView: ARView) -> SIMD3<Float>? {
        // 從螢幕上的點射一條線出去，只找「已偵測、有形狀大小」的水平面（就是畫面上綠色的那些）
        let results = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
        if let first = results.first {                                   // 結果由近到遠排好，第一個 = 最近的平面
            let column = first.worldTransform.columns.3                  // 4×4 矩陣第 4 欄 = 碰到的位置
            return SIMD3<Float>(column.x, column.y, column.z)            // 只取 x、y、z（第 4 個數字用不到）
        } else {
            return nil                                                   // 沒碰到水平面：牆壁、空中、還沒掃描到的地方
        }
    }

    /// 貓咪原點比腳底高多少（公尺）。放到平面上時，原點要放在「平面高度 + 這個值」，腳才剛好踩在平面上。
    private func footOffset(of cat: Entity) -> Float {
        let bounds = cat.visualBounds(relativeTo: nil)                   // 貓咪在世界中的 3D 外框
        let origin = cat.position(relativeTo: nil)                       // 原點在世界中的位置
        return origin.y - bounds.min.y                                   // 原點高度 − 外框最低點（腳底）的高度
    }

    /// 放手時用（腳底後面不是綠色的時候）：檢查貓咪身體的「任何部分」有沒有碰到綠色水平面。
    /// 做法：在貓咪螢幕上的範圍（矩形）裡平均取 7 × 7 = 49 個點，每個點都往畫面裡看是不是綠色。
    /// 有碰到的點裡，挑「離腳底最近」的那一個，回傳它後面那塊綠色平面上的 3D 位置；一個都沒碰到就回傳 nil。
    private func nearestGreenPoint(touching cat: Entity, feetScreen: CGPoint, in arView: ARView) -> SIMD3<Float>? {
        let bounds = cat.visualBounds(relativeTo: nil)                   // 貓咪在世界中的 3D 外框
        guard let catRect = screenRect(of: bounds, in: arView) else {    // 3D 外框 → 螢幕上的矩形
            return nil                                                   // 投影失敗（例如有一角在鏡頭後方）→ 當作沒碰到
        }
        let visibleRect = catRect.intersection(arView.bounds)            // 只看螢幕裡看得到的部分（超出螢幕的不算）
        if visibleRect.isEmpty {                                         // 貓咪整個在螢幕外 → 沒有可以檢查的地方
            return nil                                                   // → 當作沒碰到
        }

        // 每一邊取幾個點（7 → 7 × 7 = 49 個點）。
        // 調高：很窄的綠色也抓得到。缺點是放手時多做幾次射線檢查（只在放手那一刻做一次，影響很小）。
        // 調低：檢查次數少。缺點是點和點之間的空隙變大，很窄的綠色可能漏掉。建議 5 ~ 9（至少要 2）。
        let samplesPerSide = 7

        var bestPoint: SIMD3<Float>? = nil                               // 目前找到「最靠近腳底」的綠色位置（還沒找到 = nil）
        var bestDistance: CGFloat = .greatestFiniteMagnitude             // 它在螢幕上離腳底多遠；一開始設成「無限遠」

        for row in 0..<samplesPerSide {                                  // 由上到下，每一列
            for column in 0..<samplesPerSide {                           // 由左到右，每一行
                let fractionX = CGFloat(column) / CGFloat(samplesPerSide - 1)  // 0、1/6、2/6 … 1（矩形最左 → 最右）
                let fractionY = CGFloat(row) / CGFloat(samplesPerSide - 1)     // 0、1/6、2/6 … 1（矩形最上 → 最下）
                let sample = CGPoint(x: visibleRect.minX + visibleRect.width * fractionX,
                                     y: visibleRect.minY + visibleRect.height * fractionY)  // 這個取樣點在螢幕上的位置

                if let greenPoint = horizontalSurfacePoint(at: sample, in: arView) {   // 這個點後面是綠色水平面？
                    let dx = sample.x - feetScreen.x                     // 和腳底的左右距離
                    let dy = sample.y - feetScreen.y                     // 和腳底的上下距離
                    let distance = sqrt(dx * dx + dy * dy)               // 和腳底的直線距離（螢幕上，單位：點）
                    if distance < bestDistance {                         // 比目前找到的更靠近腳底？
                        bestDistance = distance                          // 記住新的最近距離
                        bestPoint = greenPoint                           // 記住它後面的綠色位置
                    }
                }
            }
        }

        return bestPoint                                                 // 有碰到 → 最靠近腳底的綠色位置；都沒碰到 → nil
    }

    /// 放手的瞬間呼叫一次，決定貓咪落在哪裡：
    ///   1. 腳底在螢幕上的那個點，後面是綠色水平面 → 直接落在那裡（貓咪不用橫移）
    ///   2. 腳底後面不是綠色，但貓咪身體「任何部分」碰到綠色 → 移到碰到的、最靠近腳底的那個綠色位置
    ///   3. 完全沒碰到綠色（牆壁、空中、還沒掃描到的地方）→ 跳回拿起來的地方（grabStartPosition，第一個點）
    /// 這裡只改 targetWorldPosition：onRender 每張畫面會讓貓咪往那裡靠近，所以看起來是很快地滑過去（約 0.25 秒）。
    private func landOrJumpBack(arView: ARView) {
        guard let cat else {                                             // 貓咪還沒載入（理論上不會發生）
            return
        }

        let origin = cat.position(relativeTo: nil)                       // 貓咪現在的原點（世界座標）
        let lift = footOffset(of: cat)                                   // 原點比腳底高多少
        let feetWorld = SIMD3<Float>(origin.x, origin.y - lift, origin.z) // 腳底：原點正下方、外框最低的高度

        // 腳底投影到螢幕上的位置。腳底在鏡頭後面時拿不到 → 無法判斷，直接跳回第一個點
        guard let feetScreen = arView.project(feetWorld) else {
            targetWorldPosition = grabStartPosition                      // 跳回拿起來的地方
            return
        }

        if let surfacePoint = horizontalSurfacePoint(at: feetScreen, in: arView) {
            // 1. 腳底後面是綠色 → 落地：原點 = 平面上的點往上 lift（腳底剛好踩在平面上）
            let landing = SIMD3<Float>(surfacePoint.x, surfacePoint.y + lift, surfacePoint.z)
            targetWorldPosition = landing                                // 貓咪滑過去、落在平面上
        } else if let greenPoint = nearestGreenPoint(touching: cat, feetScreen: feetScreen, in: arView) {
            // 2. 腳底後面不是綠色，但身體某個部分碰到綠色 → 移到那個綠色位置（一樣往上 lift，腳底踩在平面上）
            let landing = SIMD3<Float>(greenPoint.x, greenPoint.y + lift, greenPoint.z)
            targetWorldPosition = landing                                // 貓咪滑到碰到的綠色上
        } else {
            // 3. 完全沒碰到綠色 → 跳回拿起來的地方（第一個點）
            targetWorldPosition = grabStartPosition
        }
    }

    // ── 水平面顯示（自己畫的淡色平面，取代 .showAnchorGeometry）──────────────
    // 為什麼不用內建的：內建的平面顯示是除錯用的覆蓋層，會蓋在貓咪上面，也不能改顏色、不能調前後順序。
    // 自己畫的平面是場景裡真正的 3D 物體，會和貓咪比遠近（深度測試）：貓咪站在平面上時，平面自然在貓咪下面。

    /// 每張畫面呼叫：每 0.2 秒讓淡色平面和 ARKit 目前找到的水平面一致一次（新的加上、形狀更新、消失的移除）。
    private func updatePlaneOverlays(arView: ARView, deltaTime: TimeInterval) {
        timeSincePlaneOverlayUpdate += deltaTime                            // 累加時間
        if timeSincePlaneOverlayUpdate < 0.2 {                              // 還沒到 0.2 秒
            return                                                          // 這張畫面先不更新
        }
        timeSincePlaneOverlayUpdate = 0                                     // 重新計時

        guard let frame = arView.session.currentFrame else {                // 目前這張相機畫面
            return                                                          // 還沒有 → 這次先不做
        }

        var stillExisting = Set<UUID>()                                     // 這次還存在的平面編號

        for anchor in frame.anchors {                                       // ARKit 目前所有的錨點
            guard let planeAnchor = anchor as? ARPlaneAnchor else {         // 是不是平面？
                continue                                                    // 不是 → 跳過，看下一個
            }
            if planeAnchor.alignment != .horizontal {                       // 是不是水平面？
                continue                                                    // 不是 → 跳過（保險用，config 只開了水平）
            }
            stillExisting.insert(planeAnchor.identifier)                    // 記下：這塊平面還在

            // 找這塊平面的錨點；第一次看到就新做一個（錨點會自動跟著 ARKit 修正平面的位置）
            let overlay: AnchorEntity
            if let existing = planeOverlays[planeAnchor.identifier] {
                overlay = existing                                          // 做過了 → 拿出來更新形狀
            } else {
                overlay = AnchorEntity(anchor: planeAnchor)                 // 新平面 → 做一個跟著它走的錨點
                arView.scene.addAnchor(overlay)                             // 加進場景
                planeOverlays[planeAnchor.identifier] = overlay             // 記住它
            }

            // ARKit 會一直把平面變大、修正形狀 → 用最新的形狀重做網格。
            // 這和放手檢查用的 .existingPlaneGeometry 是同一個形狀，所以「畫出來的範圍」就是「貓咪能落地的範圍」。
            if let mesh = makePlaneMesh(from: planeAnchor.geometry) {
                if let plane = overlay.children.first as? ModelEntity {     // 已經有平面模型
                    plane.model?.mesh = mesh                                // → 只換形狀
                } else {                                                    // 第一次
                    overlay.addChild(makePlaneModel(mesh: mesh))            // → 做一個淡色平面掛上去
                }
            }
        }

        // 移除已經不存在的平面（例如 ARKit 把兩塊合併成一塊時，舊的那塊會消失）
        for (id, overlay) in planeOverlays {
            if !stillExisting.contains(id) {
                arView.scene.removeAnchor(overlay)                          // 從場景拿掉
                planeOverlays[id] = nil                                     // 從字典拿掉
            }
        }
    }

    /// 用 ARKit 的平面形狀（頂點 + 三角形）組成 RealityKit 的網格。組不出來就回傳 nil。
    private func makePlaneMesh(from geometry: ARPlaneGeometry) -> MeshResource? {
        // 三角形的頂點編號：ARKit 給的是 Int16，RealityKit 要 UInt32。
        // 每個三角形再「反過來」加一次 → 正面、背面都畫得出來，不管從哪個角度看都不會消失。
        let arkitIndices = geometry.triangleIndices                         // ARKit 的三角形編號（每 3 個一組）
        var indices: [UInt32] = []                                          // 要給 RealityKit 的編號
        var i = 0
        while i + 2 < arkitIndices.count {                                  // 一次處理一個三角形（3 個編號）
            let a = UInt32(arkitIndices[i])                                 // 第 1 個頂點
            let b = UInt32(arkitIndices[i + 1])                             // 第 2 個頂點
            let c = UInt32(arkitIndices[i + 2])                             // 第 3 個頂點
            indices.append(contentsOf: [a, b, c])                           // 正面
            indices.append(contentsOf: [a, c, b])                           // 背面（順序反過來）
            i += 3                                                          // 下一個三角形
        }
        if indices.isEmpty {                                                // 還沒有任何三角形
            return nil                                                      // → 這次先不畫
        }

        var descriptor = MeshDescriptor(name: "planeOverlay")               // 自己組一個網格
        descriptor.positions = MeshBuffers.Positions(geometry.vertices)     // 頂點位置（相對於平面的錨點）
        descriptor.primitives = .triangles(indices)                         // 用上面的三角形連起來

        do {
            return try MeshResource.generate(from: [descriptor])            // 組成 RealityKit 的網格
        } catch {
            return nil                                                      // 組不出來 → 這次先不畫
        }
    }

    /// 做一個淡色、半透明的平面模型（顏色、淡的程度都可以在這裡改）。
    private func makePlaneModel(mesh: MeshResource) -> ModelEntity {
        var material = UnlitMaterial(color: .systemGreen)                   // 顏色：綠色（Unlit：不受燈光影響，亮暗房間看起來都一樣）
        material.blending = .transparent(opacity: 0.25)                     // 淡的程度：0 = 看不見，1 = 完全不透明
        let plane = ModelEntity(mesh: mesh, materials: [material])          // 平面模型
        plane.position = SIMD3<Float>(0, -0.005, 0)                         // 往下 5 毫米：貓咪的腳永遠在平面上面，不會和平面互相閃爍
        return plane
    }

    // ── 撫摸（揮手）偵測 ─────────────────────────────────────────

    /// 手張開、在貓咪上方來回揮動 → 叫 CatPetSwap 播放撫摸反應。
    /// 規則（參數在 HandTrackingTuning）：2 秒內方向反轉 3 次（例如 右 → 左 → 右 → 左），每一下至少移動螢幕短邊的 3%。
    /// 避免「換手勢被當成揮手」的三道保護：
    ///   A. 用手掌位置（palmPoint，中指根關節）算來回，不用指尖：手指張合時它幾乎不動
    ///   B. 捏合放開或放下貓咪後，冷卻 petCooldownAfterPinch 秒才開始算
    ///   C. 手要張開（opennessRatio ≥ petOpenHandRatio）才算
    /// 只有「真的不是在摸」（沒載入、看不到手、正在捏合／抓著貓咪、離開貓咪太久）才清空進度；
    /// 揮手時一瞬間的小狀況（手看起來半合、指尖剛好超出範圍）只跳過那一格，不會把前面揮的都作廢。
    private func updatePetting(arView: ARView, tracker: HandTracker, bounds: BoundingBox, deltaTime: TimeInterval) {
        petClock += deltaTime                                              // 累加撫摸偵測的時鐘

        // B. 冷卻計時：正在捏合或抓著貓咪就歸零，放開後才開始累加
        if tracker.isPinching || isHolding {
            timeSincePinch = 0                                             // 還在「抓」的手勢
        } else {
            timeSincePinch += deltaTime                                    // 放開多久了
        }

        // 真的不是在摸 → 清空進度：反應檔還沒載入、看不到手、正在捏合、或正抓著貓咪（「抓」的手勢）
        guard catSwap != nil, tracker.isHandVisible, !tracker.isPinching, !isHolding else {
            petDetector.reset()                                            // 進度歸零
            timeOutsidePetZone = 0                                         // 離開計時歸零
            return
        }

        // 暫時的狀況 → 只跳過這一格、保留進度：剛放開捏合還在冷卻中（B）、或手這一瞬間看起來沒張開（C）
        guard timeSincePinch >= tuning.petCooldownAfterPinch,              // B. 冷卻結束
              tracker.opennessRatio >= tuning.petOpenHandRatio else {      // C. 手有張開
            return                                                         // 下一格再看
        }

        // 貓咪在螢幕上的範圍（3D 外框投影到螢幕）；貓咪在鏡頭後方時拿不到 → 這一格不判斷
        guard let catRect = screenRect(of: bounds, in: arView) else {
            petDetector.reset()                                            // 看不到貓咪，進度歸零
            return
        }
        // 往外多留一點空間：貓咪在畫面上不大，揮到最旁邊時手常常會稍微超出
        let petZone = catRect.insetBy(dx: -tuning.petZonePadding, dy: -tuning.petZonePadding)

        // 手不在貓咪範圍內：指尖或指節其中一個在範圍內就算在（揮到最邊邊時指尖常常會甩出去）。
        // 短暫離開可以接受，離開太久才清空進度。
        guard petZone.contains(tracker.pinchMidpoint) || petZone.contains(tracker.palmPoint) else {
            timeOutsidePetZone += deltaTime                                // 累計離開時間
            if timeOutsidePetZone > tuning.petZoneLeaveGrace {             // 離開太久
                petDetector.reset()                                        // 進度歸零
            }
            return
        }
        timeOutsidePetZone = 0                                             // 手回到貓咪上方

        // 每一下最少移動距離：螢幕短邊 × 比例（不同尺寸的手機手感一致）
        let minimumStroke = min(arView.bounds.width, arView.bounds.height) * tuning.petMinimumStrokeFraction

        // A. 把「手掌」位置餵給偵測器（手指張合不影響）；方向反轉次數達標就回傳 true
        let petted = petDetector.feed(tracker.palmPoint,
                                      time: petClock,
                                      minimumStroke: minimumStroke,
                                      reversalsNeeded: tuning.petReversalsNeeded,
                                      window: tuning.petTimeWindow)
        guard petted else { return }                                       // 還沒揮夠 → 下一格繼續累積

        petDetector.reset()                                                // 觸發一次就從頭算
        MainActor.assumeIsolated { catSwap?.pet() }                        // 貓咪走完這一步 → 坐下、歪頭、冒愛心
    }

    /// 把貓咪的 3D 外框（8 個角）投影到螢幕上，回傳剛好包住它們的矩形（螢幕點座標）。
    /// 任何一個角投影失敗（例如在鏡頭後方）就回傳 nil。
    private func screenRect(of bounds: BoundingBox, in arView: ARView) -> CGRect? {
        guard !bounds.isEmpty else { return nil }                          // 外框無效（例如模型沒有網格）
        var rect = CGRect.null                                             // 空矩形，之後把每個角併進來
        for x in [bounds.min.x, bounds.max.x] {                            // 外框的左、右
            for y in [bounds.min.y, bounds.max.y] {                        // 外框的下、上
                for z in [bounds.min.z, bounds.max.z] {                    // 外框的後、前
                    guard let point = arView.project(SIMD3<Float>(x, y, z)) else { return nil } // 3D 角 → 螢幕點
                    rect = rect.union(CGRect(origin: point, size: .zero))  // 把這個點併進矩形
                }
            }
        }
        return rect                                                        // 貓咪在螢幕上的範圍
    }

    // ── 重置 ───────────────────────────────────────────────────

    /// 只有計數器變動時才真的重置。
    func handleResetIfNeeded(counter: Int) {
        guard counter != lastHandledResetCounter else { return }
        lastHandledResetCounter = counter
        placeCatInFrontOfCamera()
    }

    // ── 拍照 ───────────────────────────────────────────────────

    /// PetARView 的拍照計數器變動時呼叫：拍一張 AR 畫面（相機畫面＋貓咪）存進相簿
    func takePhotoIfNeeded(counter: Int) {
        guard counter != lastHandledPhotoCounter else { return }   // 數字沒變 → 不是按了拍照，什麼都不做
        lastHandledPhotoCounter = counter                          // 記住這個數字，同一次不會拍兩張
        takePhoto()
    }

    /// 拍照：先藏起淡綠色平面，等畫面更新後用 ARView 的截圖功能拍下來、存進相簿，再把平面顯示回來
    private func takePhoto() {
        guard let arView else { return }                           // AR 畫面已經關掉 → 不拍

        // 1. 先把淡綠色平面藏起來（它們是測試用的，不要出現在回憶照片裡）
        for overlay in planeOverlays.values {
            overlay.isEnabled = false
        }

        // 2. 等一下下（約 3 張畫面），讓「沒有平面」的畫面真的畫出來，再拍
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // ARView 的截圖：相機畫面＋3D 貓咪（不含按鈕、手指圓點）。
            // @Sendable 很重要：RealityKit 會在「背景執行緒」呼叫這段 { }。
            // 不加的話，Swift 以為它寫在主執行緒的程式裡、就一定在主執行緒跑，偷偷加了檢查；
            // RealityKit 從背景呼叫時檢查失敗 → App 當機（畫面停在白光）。加了 @Sendable 就不會有這個假設。
            arView.snapshot(saveToHDR: false) { @Sendable image in
                // 3D 物件（平面）和 planeOverlays 只能在主執行緒碰 → 先回到主執行緒再做事
                DispatchQueue.main.async {
                    // 3. 把淡綠色平面顯示回來（主執行緒）
                    if let self {
                        for overlay in self.planeOverlays.values {
                            overlay.isEnabled = true
                        }
                    }

                    // 4. 有拍到 → 存進相簿（App 自己的 Documents/Photos 資料夾）。
                    //    轉成 JPEG、寫檔要一點時間，放到背景做，AR 畫面才不會卡一下
                    if let image {
                        DispatchQueue.global(qos: .userInitiated).async {
                            let saved = PhotoStore.save(image)
                            if saved == false {
                                print("⚠️ 照片存檔失敗")         // 例如 iPhone 空間不足 → 看 Xcode 下方的主控台
                            }
                        }
                    }
                }
            }
        }
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

        // 撫摸反應播放中按了 Reset：坐著的貓也一起移過去，播完換回走路貓時才不會跳位置
        MainActor.assumeIsolated { catSwap?.matchPetToWalk() }
    }
}
