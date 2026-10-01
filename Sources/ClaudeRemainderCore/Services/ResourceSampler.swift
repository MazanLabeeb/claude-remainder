import Foundation
import Darwin

public struct ResourceSampler {
    private var previousWallClock: Date?
    private var previousCPUSeconds: Double?

    public init() {}

    public mutating func sample(cacheBytes: UInt64, networkRefreshCount: Int) -> ResourceMetrics {
        let now = Date()
        let currentCPUSeconds = Self.currentTaskCPUSeconds() ?? 0
        let cpuPercent: Double

        if let previousWallClock, let previousCPUSeconds {
            let wallDelta = now.timeIntervalSince(previousWallClock)
            let cpuDelta = currentCPUSeconds - previousCPUSeconds
            if wallDelta > 0 {
                cpuPercent = max(0, (cpuDelta / wallDelta) * 100)
            } else {
                cpuPercent = 0
            }
        } else {
            cpuPercent = 0
        }

        self.previousWallClock = now
        self.previousCPUSeconds = currentCPUSeconds

        return ResourceMetrics(
            sampledAt: now,
            cpuPercent: cpuPercent,
            residentMemoryBytes: Self.currentResidentMemoryBytes() ?? 0,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            cacheBytes: cacheBytes,
            networkRefreshCount: networkRefreshCount
        )
    }

    private static func currentTaskCPUSeconds() -> Double? {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + system
    }

    private static func currentResidentMemoryBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    intPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return info.phys_footprint
    }
}
