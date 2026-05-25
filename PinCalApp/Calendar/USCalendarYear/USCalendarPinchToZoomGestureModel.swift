//
//  USCalendarPinchToZoomGestureModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 26.03.2026.
//

import Foundation
import Observation

@Observable
final class USCalendarPinchToZoomGestureModel {
    private let baseSensitivity: CGFloat = 0.12
    private let minSensitivity: CGFloat = 0.08
    private var smoothMagnification: CGFloat = 1.0  // Для сглаживания
    private var accumulatedDelta: CGFloat = 0.0  // Накопленная дельта
    private var lastMagnification: CGFloat = 1.0
    private var lastNumberOfColumns: Int = 3
    var numberOfColumns: Int
    
    init(numberOfColumns: Int) {
        self.numberOfColumns = numberOfColumns
        self.lastNumberOfColumns = numberOfColumns
    }
    
    /// Обрабатывает жест масштабирования
    /// - Parameters:
    ///   - magnification: Текущий коэффициент масштабирования
    ///   - velocity: Скорость изменения масштаба (CGFloat)
    func handleMagnify(
        magnification: CGFloat,
        velocity: CGFloat,
        gestureDuration: TimeInterval,  // Передаётся из View (длительность жеста),
        didChange: (Int) -> Void
    ) {
        // 1. Сглаживание входного значения масштабирования
        let smoothingFactor: CGFloat = 0.3
        smoothMagnification = smoothMagnification * (1 - smoothingFactor) + magnification * smoothingFactor
        
        let effectiveMagnification = smoothMagnification
        
        // 2. Вычисляем дельту относительно предыдущего сглаженного значения
        let delta = effectiveMagnification - lastMagnification
        lastMagnification = effectiveMagnification
        
        // 3. Адаптивный порог в зависимости от скорости и длительности жеста
        let speedInfluence = min(abs(velocity) / 300.0, 0.8)  // Нормализация скорости
        let durationInfluence = min(gestureDuration / 0.3, 1.0)  // Чем дольше жест, тем ниже порог
        let dynamicThreshold = baseSensitivity * (1.0 - speedInfluence * 0.7 - durationInfluence * 0.3)
        let finalThreshold = max(minSensitivity, dynamicThreshold)  // Минимум — minSensitivity
        
        // 4. Накопление дельты с экспоненциальным затуханием и усилением текущего движения
        accumulatedDelta = accumulatedDelta * 0.65 + delta * 1.5
        
        // 5. Гистерезис: требуется превышение порога в 1.6 раза для срабатывания
        let triggerThreshold = finalThreshold * 1.6
        
        var newCount = lastNumberOfColumns
        
        if accumulatedDelta > triggerThreshold {
            newCount -= 1
            // Частичный сброс накопленной дельты (оставляем 25% для плавного продолжения)
            accumulatedDelta *= 0.25
        } else if accumulatedDelta < -triggerThreshold {
            newCount += 1
            accumulatedDelta *= 0.25
        }
        
        // 6. Ограничение диапазона колонок
        newCount = max(1, min(newCount, 3))
        
        // 7. Обновление состояния только при изменении
        if newCount != lastNumberOfColumns {
            numberOfColumns = newCount
            lastNumberOfColumns = newCount
            didChange(numberOfColumns)
        }
    }
}
