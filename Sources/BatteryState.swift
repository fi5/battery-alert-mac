import Foundation

struct BatterySnapshot: Equatable {
    let percent: Int
    let onBattery: Bool
}

/// The delivery flag is committed only after Notification Center accepts a request.
struct AlertPolicy {
    private(set) var hasNotified: Bool

    init(hasNotified: Bool = false) { self.hasNotified = hasNotified }

    mutating func shouldNotify(_ battery: BatterySnapshot, threshold: Int, enabled: Bool) -> Bool {
        if !battery.onBattery || battery.percent > threshold {
            hasNotified = false
            return false
        }
        return enabled && !hasNotified
    }

    mutating func markDelivered() { hasNotified = true }
    mutating func reset() { hasNotified = false }
}
