//
//  HandTracking.swift
//  game
//
//  手部追蹤（Vision）核心邏輯 —— 從 testAR 專案的 HandTrackingARView.swift 移植過來，
//  拿掉裡面跟「方塊」有關的部分（那些現在放在 PetARView.swift 的 CatController），
//  只留下和裝置、手勢偵測本身有關、完全通用的部分：
//
//  1. HandTrackingTuning  所有可調參數集中在這裡。要調順暢度／靈敏度／偵測距離，
//                         只需要改這一個 struct，不用翻整份程式碼。
//  2. HandTracker         Vision 手部偵測流程。重的運算全部在背景佇列，
//                         主執行緒只負責「拿影格」和「更新畫面狀態」。
//  3. FingerOverlay       手指圓點與連線（獨立成一個 View，避免整個 AR 畫面重繪）。
//
//  ── 相對於最早期版本的主要修正（在 testAR 專案調通，這裡原封不動繼承）──────
//  A. Vision 從「主執行緒」搬到背景佇列 → 不再卡住 RealityKit 算圖（卡頓主因）
//  B. 偵測 10fps → 30fps，且移動改成「每張畫面內插」→ 不再一格一格跳
//  C. 送進 Vision 的影像先轉正 → 模型看到的是直立的手，遠距離偵測率大幅提升
//  D. 捏合門檻改成「相對手掌大小」→ 手遠手近都是同一個手勢，不會誤判
//  E. 抓取物件改用 ARView.ray(through:) 從螢幕座標反推世界座標 → 任何持機角度都正確
//  F. 修掉「每按一次 Reset 就多開一個 Timer」的 bug（按越多次越卡）
//

import SwiftUI
import UIKit
import ARKit
import Vision
import ImageIO
import QuartzCore
import Observation

// MARK: - 1. 可調參數

/// 所有「手感」與「效能」相關的數字集中在這裡。
/// 每一項都標明：預設值 → 調大／調小各有什麼優缺點。
struct HandTrackingTuning {

    /// 一份共用的預設值（畫面與追蹤器共用同一份，避免兩邊參數不一致）
    static let standard = HandTrackingTuning()

    // ── 偵測頻率 ────────────────────────────────────────────────

    /// 每秒執行幾次 Vision 手部偵測（舊版是 10）。
    /// 調高：反應更即時、快速揮手比較不會斷。缺點是 CPU／神經網路引擎負載上升，手機會變燙、耗電。
    /// 調低：省電、機身涼。缺點是手指圓點會有明顯延遲感。
    /// 建議 20 ~ 30；iPhone 12 以下建議 20。
    var detectionsPerSecond: Double = 30

    // ── 信心度門檻（Vision 對每個關節點的把握程度，0 ~ 1）────────────

    /// 低於這個信心度就當作「這一幀沒看到手」（舊版是 0.7，太嚴格，手一遠就整隻消失）。
    /// 調低：手離遠、光線差、手部側面時也還抓得到。缺點是偶爾會出現亂飄的假點。
    /// 調高：點很穩、幾乎不亂跳。缺點是手稍微遠一點就完全失去追蹤。
    /// 建議 0.25 ~ 0.4。
    var minimumTrackingConfidence: Float = 0.3

    /// 要「拖動貓咪」需要的信心度，比上面嚴格一些。
    /// 這樣可以：手勉強看得到時仍顯示圓點，但不會用不可靠的座標去亂拖貓咪。
    /// 調低：遠距離也拖得動。缺點是貓咪可能被雜訊帶偏。
    /// 建議 0.4 ~ 0.6。
    var minimumDragConfidence: Float = 0.45

    /// 手「暫時不見」的寬限時間（秒）。這段時間內維持上一幀狀態，不清空圓點也不放開貓咪。
    /// 調高：追蹤短暫中斷時貓咪不會突然掉下來，體感穩定很多。缺點是真的放手時會晚一點才鬆開。
    /// 調低：放手反應快。缺點是手抖一下貓咪就掉了。
    /// 建議 0.2 ~ 0.5。
    var handLostGracePeriod: Double = 0.35

    // ── 平滑（這兩個是「順不順」的關鍵）───────────────────────────

    /// 手指圓點的平滑係數，0 = 完全不平滑（最靈敏也最抖），0.9 = 非常黏（很穩但很鈍）。
    /// 調高：圓點滑順不抖。缺點是跟手會有延遲。
    /// 調低：跟手緊。缺點是 Vision 的雜訊會直接顯示成抖動。
    /// 建議 0.3 ~ 0.6。
    var pointSmoothing: CGFloat = 0.45

    /// 貓咪追上目標位置所需的時間常數（秒）。數字越小＝追越快。
    /// 這是「每張畫面內插」用的，跟偵測頻率無關，所以就算偵測只有 30fps，貓咪仍是 60fps 滑順移動。
    /// 調小（例如 0.03）：貓咪幾乎黏著手指。缺點是手部雜訊會直接傳到貓咪身上。
    /// 調大（例如 0.15）：移動非常滑順、有重量感。缺點是明顯的拖尾延遲。
    /// 建議 0.05 ~ 0.12。
    var catFollowTime: Double = 0.08

    // ── 捏合判定 ───────────────────────────────────────────────

    /// 捏合「成立」門檻：拇指到食指的距離 ÷ 手掌長度，小於這個值算捏起來。
    /// 用比例而不是固定像素，手離鏡頭遠近都不影響判定（固定像素的話，手一遠就會誤判成一直在捏）。
    /// 調高：更容易觸發。缺點是手指沒真的併攏也會被當成捏合。
    /// 建議 0.28 ~ 0.45。
    var pinchEngageRatio: CGFloat = 0.35

    /// 捏合「放開」門檻，必須比上面大 → 形成遲滯區（hysteresis）。
    /// 好處：在門檻邊緣時不會「捏開捏開」高速抖動，貓咪不會閃爍掉落。
    /// 兩個數字差越大越穩定，但放開時要張得越開。建議差 0.15 ~ 0.25。
    var pinchReleaseRatio: CGFloat = 0.55

    /// 萬一手腕／中指根關節沒偵測到，無法量手掌長度時，退回這個固定像素值當基準。
    var fallbackPalmSizeInPixels: CGFloat = 120

    // ── 抓取貓咪 ───────────────────────────────────────────────

    /// 捏合中心點離貓咪螢幕位置多近才算抓到（像素，舊版是 75）。
    /// 調大：好抓、不容易抓空。缺點是可能在明顯沒對準時就抓起來。
    /// 建議 60 ~ 120（螢幕大的裝置可以調大）。
    var grabRadiusInPixels: CGFloat = 90

    /// 單次更新允許貓咪目標位置移動的最大距離（公尺）。超過視為追蹤誤判，直接忽略這一次。
    /// 調小：更能擋掉亂跳。缺點是快速揮手時會被誤擋，貓咪跟不上。
    /// 建議 0.3 ~ 0.8。
    var maximumJumpInMeters: Float = 0.5

    // ── 貓咪外觀 ───────────────────────────────────────────────

    /// 貓咪模型（cat.usdz）的縮放比例。原始模型過大，所以用一個很小的數字縮小。
    /// 貓咪大小固定不變，不會被手勢（捏合）改變。
    /// 調小：重置後的貓咪比較不會感覺過大。調大：比較顯眼、容易一眼看到。
    var catScale: Float = 0.0005

    /// 重置時貓咪放在鏡頭正前方多遠（公尺）
    var catSpawnDistance: Float = 0.5

    // ── 效能與座標 ─────────────────────────────────────────────

    /// 關掉 RealityKit 比較吃效能的畫面特效。
    /// 優點：GPU 負擔下降，舊機型畫面更順。缺點：畫面少了動態模糊／景深等真實感（這個 App 用不到）。
    var disableExpensiveRenderEffects = true

    /// 是否用 ARFrame.displayTransform 做座標轉換。
    /// 開啟：正確處理「相機是 4:3、螢幕是長條」造成的裁切，手指圓點會準確落在真實手指上。
    /// 關閉：改用最單純的線性對應。萬一開啟後圓點位置怪怪的，可以關掉這個做 A/B 比對，
    ///      這樣就能立刻知道問題是出在座標轉換還是偵測本身。
    var useDisplayTransform = true
}

// MARK: - 2. 手部追蹤器

/// Vision 手部偵測的完整流程。
///
/// 執行緒規則（很重要，早期版本就是敗在這裡）：
/// - `tick()` 在主執行緒：只做「拿影格 + 讀取畫面方向」這些極輕的事
/// - `detectHand()` 在背景佇列：Vision 推論（10 ~ 30ms）全部在這裡，不會卡住畫面
/// - `apply()` 回到主執行緒：更新給 SwiftUI 看的狀態
@Observable
final class HandTracker {

    // ── 對外狀態（畫面與貓咪控制器會讀這些）────────────────────────

    /// 拇指指尖在螢幕上的位置（像素）
    private(set) var thumbPoint: CGPoint = .zero
    /// 食指指尖在螢幕上的位置（像素）
    private(set) var indexPoint: CGPoint = .zero
    /// 拇指與食指的中點，抓取判定用
    private(set) var pinchMidpoint: CGPoint = .zero
    /// 目前畫面中是否看得到手
    private(set) var isHandVisible = false
    /// 目前是否處於捏合狀態（已含遲滯處理）
    private(set) var isPinching = false
    /// 信心度是否足夠拿來拖動貓咪
    private(set) var canDrag = false

    // ── 外部設定 ───────────────────────────────────────────────

    /// 畫面尺寸，由 SwiftUI 的 GeometryReader 回報，座標轉換要用
    var viewportSize: CGSize = .zero

    // ── 內部狀態（@ObservationIgnored：改變時不需要觸發畫面重繪）──────

    @ObservationIgnored private let tuning: HandTrackingTuning
    @ObservationIgnored private weak var session: ARSession?
    @ObservationIgnored private var timer: Timer?

    /// Vision 請求物件重複使用（每次 new 一個很浪費）。
    /// 因為有 isBusy 保護，同時間只會有一次推論在跑，所以共用同一個物件是安全的。
    @ObservationIgnored private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1        // 只找一隻手 → 推論速度快將近一倍
        return request
    }()

    /// 背景佇列：序列式（一次只跑一個），避免多個推論同時搶 CPU
    @ObservationIgnored private let queue = DispatchQueue(label: "com.game.hand-tracking", qos: .userInitiated)

    /// 背景是否正在推論中。true 時直接跳過這一次 tick，避免工作堆積造成雪崩式延遲。
    @ObservationIgnored private var isBusy = false

    /// 上一次處理過的影格時間戳，避免同一張影格被重複分析
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = 0

    /// 最後一次真的看到手的時間，寬限期判定用
    @ObservationIgnored private var lastSeenTime: TimeInterval = 0

    init(tuning: HandTrackingTuning) {
        self.tuning = tuning
    }

    // ── 啟動與停止 ─────────────────────────────────────────────

    /// 開始追蹤。session 由 ARView 提供（讓 ARView 保持是 session 的唯一擁有者）。
    func start(session: ARSession) {
        self.session = session
        timer?.invalidate()                                   // 先關掉舊的，避免重複啟動時開出兩個 Timer

        let interval = 1.0 / max(tuning.detectionsPerSecond, 1)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // 加到 .common mode：即使畫面上有捲動或動畫在跑，Timer 也不會被暫停
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 停止追蹤（View 消失時呼叫，避免背景繼續吃電）
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    // ── 主執行緒：取得影格並丟到背景 ─────────────────────────────

    private func tick() {
        // 背景還在忙 → 直接跳過這一次。這一行就是「不會越跑越卡」的關鍵。
        guard !isBusy else { return }
        // 畫面尺寸還沒回報，座標無法換算
        guard viewportSize != .zero else { return }
        guard let frame = session?.currentFrame else { return }
        // 同一張影格不重複分析
        guard frame.timestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = frame.timestamp

        // 讀取目前畫面方向（使用者可能把手機轉成橫的）
        let interfaceOrientation = Self.currentInterfaceOrientation
        let imageOrientation = Self.imageOrientation(for: interfaceOrientation)

        // displayTransform 負責處理「相機影像 4:3、螢幕比較長」造成的裁切與旋轉。
        // 必須在主執行緒、趁 frame 還在手上時取得。
        let displayTransform = frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize)

        // 只把「像素緩衝區」帶到背景，不要整個 ARFrame 帶走。
        // ARKit 的影格數量有限，抓著不放會讓 session 拿不到新影格而卡住。
        let pixelBuffer = frame.capturedImage
        let viewport = viewportSize

        // 先把要用的東西取成區域變數，背景閉包就不需要碰 self
        let request = self.request
        let currentTuning = self.tuning

        isBusy = true
        queue.async { [weak self] in
            let sample = Self.detectHand(in: pixelBuffer,
                                         orientation: imageOrientation,
                                         request: request,
                                         tuning: currentTuning)

            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false                                   // 放行下一次 tick
                self.apply(sample,
                           displayTransform: displayTransform,
                           imageOrientation: imageOrientation,
                           viewport: viewport)
            }
        }
    }

    // ── 背景執行緒：Vision 偵測 ────────────────────────────────

    /// 一隻手的關鍵點，座標都在「轉正後的正規化空間」（0~1，原點左下，與 Vision 相同）
    private struct HandSample {
        var thumb: CGPoint
        var index: CGPoint
        var wrist: CGPoint?
        var middleKnuckle: CGPoint?
        var confidence: Float
    }

    /// 對整張畫面跑一次 Vision 手部偵測。沒看到手、或信心度不夠時回傳 nil。
    private static func detectHand(in pixelBuffer: CVPixelBuffer,
                                   orientation: CGImagePropertyOrientation,
                                   request: VNDetectHumanHandPoseRequest,
                                   tuning: HandTrackingTuning) -> HandSample? {

        // 直接用 pixel buffer（零複製，最快的路徑），
        // 並告訴 Vision 影像該怎麼轉正 —— 這個參數如果漏掉，模型看到的是躺著的手，是遠距離抓不到的主因。
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        // 執行推論。失敗就當作這一幀沒看到手。
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        guard let thumb = points[.thumbTip], let index = points[.indexTip] else { return nil }

        // 兩個指尖都要達到最低信心度，否則視為沒看到
        guard thumb.confidence >= tuning.minimumTrackingConfidence,
              index.confidence >= tuning.minimumTrackingConfidence else { return nil }

        // 手腕與中指根關節：拿來量「手掌長度」，捏合門檻要用（可有可無，沒有就用備援值）
        let wrist = confidentPoint(points[.wrist], minimum: tuning.minimumTrackingConfidence)
        let knuckle = confidentPoint(points[.middleMCP], minimum: tuning.minimumTrackingConfidence)

        return HandSample(thumb: thumb.location,
                          index: index.location,
                          wrist: wrist,
                          middleKnuckle: knuckle,
                          confidence: min(thumb.confidence, index.confidence))
    }

    /// 取出「信心度足夠」的關鍵點；不夠或不存在就回傳 nil。
    private static func confidentPoint(_ point: VNRecognizedPoint?, minimum: Float) -> CGPoint? {
        guard let point, point.confidence >= minimum else { return nil }
        return point.location
    }

    // ── 主執行緒：把偵測結果變成畫面狀態 ─────────────────────────

    private func apply(_ sample: HandSample?,
                       displayTransform: CGAffineTransform,
                       imageOrientation: CGImagePropertyOrientation,
                       viewport: CGSize) {

        let now = CACurrentMediaTime()

        // 這一幀沒看到手
        guard let sample else {
            // 寬限期內：什麼都不做，維持上一幀 → 圓點不閃爍、貓咪不會突然掉落
            guard now - lastSeenTime > tuning.handLostGracePeriod else { return }
            // 超過寬限期：確定手真的離開了，全部清空
            isHandVisible = false
            isPinching = false
            canDrag = false
            thumbPoint = .zero
            indexPoint = .zero
            return
        }

        lastSeenTime = now

        // 正規化座標 → 螢幕像素座標
        let rawThumb = screenPoint(from: sample.thumb, displayTransform: displayTransform, imageOrientation: imageOrientation, viewport: viewport)
        let rawIndex = screenPoint(from: sample.index, displayTransform: displayTransform, imageOrientation: imageOrientation, viewport: viewport)

        // 平滑：把 Vision 每幀的小抖動濾掉
        thumbPoint = smooth(thumbPoint, toward: rawThumb)
        indexPoint = smooth(indexPoint, toward: rawIndex)
        pinchMidpoint = CGPoint(x: (thumbPoint.x + indexPoint.x) / 2,
                                y: (thumbPoint.y + indexPoint.y) / 2)

        isHandVisible = true
        canDrag = sample.confidence >= tuning.minimumDragConfidence

        // ── 捏合判定 ──
        // 指尖距離除以手掌長度 → 得到與距離無關的比例值
        let fingerGap = hypot(thumbPoint.x - indexPoint.x, thumbPoint.y - indexPoint.y)
        let palmSize: CGFloat
        if let wrist = sample.wrist, let knuckle = sample.middleKnuckle {
            let a = screenPoint(from: wrist, displayTransform: displayTransform, imageOrientation: imageOrientation, viewport: viewport)
            let b = screenPoint(from: knuckle, displayTransform: displayTransform, imageOrientation: imageOrientation, viewport: viewport)
            palmSize = max(hypot(a.x - b.x, a.y - b.y), 1)    // 至少 1，避免除以 0
        } else {
            palmSize = tuning.fallbackPalmSizeInPixels
        }
        let ratio = fingerGap / palmSize

        // 遲滯：捏起來用小門檻、放開用大門檻，中間那段維持現狀 → 不會在邊界高速抖動
        if isPinching {
            if ratio > tuning.pinchReleaseRatio { isPinching = false }
        } else if ratio < tuning.pinchEngageRatio {
            isPinching = true
        }
    }

    /// 指數平滑：新值佔 (1 - factor)，舊值佔 factor
    private func smooth(_ current: CGPoint, toward target: CGPoint) -> CGPoint {
        // 第一次偵測到手時直接跳過去，不然圓點會從畫面左上角 (0,0) 滑進來
        guard current != .zero else { return target }
        let factor = min(max(tuning.pointSmoothing, 0), 0.95)
        return CGPoint(x: current.x * factor + target.x * (1 - factor),
                       y: current.y * factor + target.y * (1 - factor))
    }

    // ── 座標轉換 ───────────────────────────────────────────────

    /// Vision 的正規化座標（轉正後、原點左下）→ 螢幕像素座標（原點左上）
    private func screenPoint(from point: CGPoint,
                             displayTransform: CGAffineTransform,
                             imageOrientation: CGImagePropertyOrientation,
                             viewport: CGSize) -> CGPoint {

        // 第 1 步：Vision 原點在左下，UIKit 原點在左上 → y 翻轉
        let upright = CGPoint(x: point.x, y: 1 - point.y)

        guard tuning.useDisplayTransform else {
            // 簡易模式：直接線性對應。沒有處理相機 4:3 與螢幕比例的差異，
            // 邊緣會有偏移，但完全不會有旋轉方向搞錯的風險，適合拿來對照除錯。
            return CGPoint(x: upright.x * viewport.width, y: upright.y * viewport.height)
        }

        // 第 2 步：轉回「相機原始影像」的座標系（displayTransform 要求的輸入空間）。
        // 因為我們送給 Vision 前已經把影像轉正了，這裡要做反向旋轉。
        let native: CGPoint
        switch imageOrientation {
        case .right:                                    // 直立：原始影像順時針轉 90° 才是正的
            native = CGPoint(x: upright.y, y: 1 - upright.x)
        case .left:                                     // 上下顛倒的直立
            native = CGPoint(x: 1 - upright.y, y: upright.x)
        case .down:                                     // 橫向（另一邊）：轉 180°
            native = CGPoint(x: 1 - upright.x, y: 1 - upright.y)
        default:                                        // .up 橫向：原始影像本來就是正的
            native = upright
        }

        // 第 3 步：交給 ARKit 處理裁切與縮放 → 得到 0~1 的畫面座標
        let normalizedInView = native.applying(displayTransform)

        // 第 4 步：乘上畫面尺寸變成實際像素
        return CGPoint(x: normalizedInView.x * viewport.width,
                       y: normalizedInView.y * viewport.height)
    }

    /// 目前畫面方向（使用者可能已經把手機轉過來了）
    private static var currentInterfaceOrientation: UIInterfaceOrientation {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.interfaceOrientation ?? .portrait
    }

    /// 畫面方向 → 影像該怎麼轉才會是直立的（後鏡頭）
    private static func imageOrientation(for interface: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interface {
        case .portrait:             return .right
        case .portraitUpsideDown:   return .left
        case .landscapeLeft:        return .down
        case .landscapeRight:       return .up
        default:                    return .right
        }
    }
}

// MARK: - 3. 手指視覺化圖層

/// 只負責畫兩個圓點和一條線。獨立出來是為了縮小 SwiftUI 的重繪範圍。
struct FingerOverlay: View {

    let tracker: HandTracker

    var body: some View {
        ZStack {
            // 透明底色：讓 ZStack 撐滿 GeometryReader，.position 才會用整個畫面當座標系
            Color.clear

            if tracker.isHandVisible {
                // 拇指到食指的連線。
                // 這裡必須用 Canvas 而不是 Path：Path 當成 View 時會被 ZStack 依它自己的
                // 外框置中擺放，線就會跑掉；Canvas 會填滿整個區域，可以直接用絕對座標畫。
                Canvas { context, _ in
                    var path = Path()
                    path.move(to: tracker.thumbPoint)
                    path.addLine(to: tracker.indexPoint)
                    context.stroke(path, with: .color(.yellow), lineWidth: 2)
                }

                // 紅點：拇指指尖
                Circle()
                    .fill(Color.red)
                    .frame(width: 20, height: 20)
                    .position(tracker.thumbPoint)

                // 藍點：食指指尖。捏合時整體換成綠色，一眼就知道有沒有觸發。
                Circle()
                    .fill(tracker.isPinching ? Color.green : Color.blue)
                    .frame(width: 20, height: 20)
                    .position(tracker.indexPoint)
            }
        }
        .allowsHitTesting(false)        // 這層不吃觸控，不會擋到下面的按鈕
    }
}
