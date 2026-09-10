import SwiftUI
import IOKit.ps

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("MacStats")
                .font(.headline)

            Divider()

            Text("Cтатистика")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
    
    func getCPUUsage() -> Double {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        if result != KERN_SUCCESS {
            return 0
        }

        var totalUsage: Double = 0

        for i in 0..<Int(numCPUsU) {
            let user = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)])
            let sys = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)])
            let idle = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)])
            let nice = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)])

            let total = user + sys + idle + nice
            if total > 0 {
                totalUsage += (user + sys + nice) / total
            }
        }

        let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

        return (totalUsage / Double(numCPUsU)) * 100
    }
    
    func getMemoryUsage() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0)
        }

        let pageSize = Double(vm_kernel_page_size)

        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize

        let usedBytes = active + wired + compressed
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

        return (usedBytes / 1_073_741_824, totalBytes / 1_073_741_824)
    }
    
    func getBatteryInfo() -> (percentage: Int, isCharging: Bool) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        guard let source = sources.first else {
            return (0, false)
        }

        let info = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as! [String: AnyObject]

        let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let state = info[kIOPSPowerSourceStateKey] as? String ?? ""

        let isCharging = state == kIOPSACPowerValue

        return (capacity, isCharging)
    }
}

#Preview {
    ContentView()
}
