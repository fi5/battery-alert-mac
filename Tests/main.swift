import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let low = BatterySnapshot(percent: 15, onBattery: true)
let critical = BatterySnapshot(percent: 9, onBattery: true)
let high = BatterySnapshot(percent: 16, onBattery: true)
let plugged = BatterySnapshot(percent: 12, onBattery: false)

var policy = AlertPolicy()
check(!policy.shouldNotify(high, threshold: 15, enabled: true), "No warning above threshold")
check(policy.shouldNotify(low, threshold: 15, enabled: true), "Warn at exactly the threshold")
check(policy.shouldNotify(low, threshold: 15, enabled: true), "Failed delivery must remain retryable")
policy.markDelivered()
check(!policy.shouldNotify(critical, threshold: 15, enabled: true), "Do not repeat during the same discharge")
var restored = AlertPolicy(hasNotified: policy.hasNotified)
check(!restored.shouldNotify(low, threshold: 15, enabled: true), "Preserve suppression across relaunch")
check(!restored.shouldNotify(plugged, threshold: 15, enabled: true), "No alert while plugged in")
check(restored.shouldNotify(critical, threshold: 15, enabled: true), "Unplugging at low charge rearms the alert")
restored.markDelivered()
check(!restored.shouldNotify(high, threshold: 15, enabled: true), "Recovery resets without alerting")
check(restored.shouldNotify(low, threshold: 15, enabled: true), "Notify on the next discharge")
check(!AlertPolicy().shouldNotifyCopy(low, threshold: 15, enabled: false), "Disabled notifications stay silent")
var custom = AlertPolicy()
check(!custom.shouldNotify(low, threshold: 10, enabled: true), "Respect custom threshold")
check(custom.shouldNotify(BatterySnapshot(percent: 25, onBattery: true), threshold: 25, enabled: true), "Custom threshold is inclusive")
print("Passed \(checks) battery alert policy checks.")

extension AlertPolicy {
    func shouldNotifyCopy(_ battery: BatterySnapshot, threshold: Int, enabled: Bool) -> Bool {
        var copy = self
        return copy.shouldNotify(battery, threshold: threshold, enabled: enabled)
    }
}
