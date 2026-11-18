// SPDX-License-Identifier: AGPL-3.0-only
// Ekranın kendiliğinden kararıp kilitlenmesini engeller. iOS kilitlenen ya da arka plana geçen uygulamayı askıya alır
// ve PS5/TV bağlantıları kopar; bu yüzden çeviri (ya da TV kurulumu) sürerken ekran açık kalmalı.
//
// Birden çok neden aynı anda isteyebilir (çeviri + TV kurulumu): biri bitince diğerininki kapanmasın diye nedenler
// tek yerde tutulur. iOS bayrağı bazen kendisi sıfırlar (arka plandan dönüş, ses/görüntü oturumları); bu yüzden istek
// sürerken bayrak düzenli olarak ve uygulama öne her geldiğinde yeniden konur.

import UIKit

@MainActor
enum ScreenAwake {
    enum Reason: Hashable { case translation, tvInstall }

    private static var reasons = Set<Reason>()
    private static var timer: Timer?

    static func set(_ on: Bool, for reason: Reason) {
        if on { reasons.insert(reason) } else { reasons.remove(reason) }
        apply(force: on)
        if reasons.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                Task { @MainActor in ScreenAwake.apply() }
            }
        }
    }

    /// Bayrağı yeniden uygular. `force`: iOS'un unuttuğu bayrak, kapatıp açınca yeniden etkinleşir.
    static func apply(force: Bool = true) {
        let wanted = !reasons.isEmpty
        let app = UIApplication.shared
        if wanted, force { app.isIdleTimerDisabled = false }
        if app.isIdleTimerDisabled != wanted || force { app.isIdleTimerDisabled = wanted }
    }
}
