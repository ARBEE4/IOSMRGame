//
//  PetStrokeDetector.swift
//  game
//
//  撫摸（揮手）偵測：手在貓咪上方「來回」移動，移動方向反轉達到指定次數，就判定為撫摸一次。
//  規則與網頁預覽版相同（參數在 HandTrackingTuning）：
//    - 2 秒內方向反轉 3 次（例如 右 → 左 → 右 → 左）
//    - 每一下至少移動螢幕短邊的 3%（濾掉手抖和 Vision 的雜訊）
//  左右（x）和上下（y）分開計算，哪一個方向先達標都算 → 左右揮手、上下撫摸都可以。
//
//  這個檔案只做「數學判斷」，不碰 RealityKit／Vision：
//  手在不在貓咪上方、有沒有在捏合，由 PetARView.swift 的 CatController 決定要不要餵資料進來。
//

import CoreGraphics                                                      // CGPoint、CGFloat
import Foundation                                                        // TimeInterval

/// 撫摸偵測器。每張畫面呼叫一次 feed(...)；回傳 true 代表「剛剛完成一次撫摸」。
struct PetStrokeDetector {

    private var horizontal = AxisStrokeCounter()                         // 左右方向的來回計數
    private var vertical = AxisStrokeCounter()                           // 上下方向的來回計數

    /// 餵入手目前在螢幕上的位置（點座標）。
    /// - Parameters:
    ///   - point: 手的位置（CatController 用拇指與食指的中點）
    ///   - time: 目前時間（秒，只要一直往前走就好，不需要是真實時鐘）
    ///   - minimumStroke: 每一下至少要移動多少點才算
    ///   - reversalsNeeded: 需要幾次方向反轉
    ///   - window: 反轉必須在幾秒內完成
    /// - Returns: 任一方向在時間窗內的反轉次數達標時回傳 true
    mutating func feed(_ point: CGPoint,
                       time: TimeInterval,
                       minimumStroke: CGFloat,
                       reversalsNeeded: Int,
                       window: TimeInterval) -> Bool {
        let x = horizontal.feed(point.x, time: time, minimumStroke: minimumStroke, window: window) // 左右反轉次數
        let y = vertical.feed(point.y, time: time, minimumStroke: minimumStroke, window: window)   // 上下反轉次數
        return max(x, y) >= reversalsNeeded                              // 任一方向達標就算撫摸
    }

    /// 清空進度（手離開貓咪、捏合、抓著貓咪、或剛觸發完一次時呼叫）。
    mutating func reset() {
        horizontal = AxisStrokeCounter()                                 // 左右從頭算
        vertical = AxisStrokeCounter()                                   // 上下從頭算
    }
}

/// 單一方向（x 或 y）的來回計數。
private struct AxisStrokeCounter {

    private var start: CGFloat?                                          // 開始追蹤時的位置（方向還沒決定前，用來量第一下）
    private var extreme: CGFloat = 0                                     // 這一下目前走到最遠的位置（下一次反轉從這裡量）
    private var direction: CGFloat = 0                                   // 目前移動方向：+1 或 -1；0 = 還沒動夠遠、方向未定
    private var reversalTimes: [TimeInterval] = []                       // 每次方向反轉發生的時間

    /// 餵入一個位置，回傳「時間窗內」的反轉次數。
    mutating func feed(_ value: CGFloat, time: TimeInterval, minimumStroke: CGFloat, window: TimeInterval) -> Int {
        reversalTimes.removeAll { time - $0 > window }                   // 丟掉太舊的反轉（超過時間窗）

        guard let start else {                                           // 第一個點：只記住位置
            self.start = value                                           // 記住起點
            extreme = value                                              // 最遠點先等於起點
            return reversalTimes.count                                   // 還沒有任何反轉
        }

        if direction == 0 {                                              // 方向還沒決定
            if abs(value - start) >= minimumStroke {                     // 離起點夠遠 → 第一下成立
                direction = value > start ? 1 : -1                       // 往哪邊走就定哪個方向
                extreme = value                                          // 從這裡開始記最遠點
            }
            return reversalTimes.count                                   // 第一下不算反轉
        }

        if (value - extreme) * direction > 0 {                           // 繼續往同一個方向走
            extreme = value                                              // 更新最遠點
        } else if (extreme - value) * direction >= minimumStroke {       // 往回走得夠遠 → 算一次反轉
            reversalTimes.append(time)                                   // 記下反轉時間
            direction = -direction                                       // 現在改往反方向
            extreme = value                                              // 新的一下從這裡開始記最遠點
        }
        return reversalTimes.count                                       // 時間窗內的反轉次數
    }
}
