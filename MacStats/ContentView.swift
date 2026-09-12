import SwiftUI
import IOKit.ps
import Darwin
import Combine

class SystemStats: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var cpuPerCore: [Double] = []
    @Published var memoryUsed: Double = 0
    @Published var memoryTotal: Double = 0
    @Published var batteryPercentage: Int = 0
    @Published var isCharging: Bool = false
    @Published var diskFree: Double = 0
    @Published var diskTotal: Double = 0
    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0

    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastTimestamp = Date()

    func refresh() {
        let perCore = getCPUUsagePerCore()
        cpuPerCore = perCore
        cpuUsage = perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count)

        let memory = getMemoryUsage()
        memoryUsed = memory.used
        memoryTotal = memory.total

        let battery = getBatteryInfo()
        batteryPercentage = battery.percentage
        isCharging = battery.isCharging

        let disk = getDiskSpace()
        diskFree = disk.free
        diskTotal = disk.total

        let network = getNetworkBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTimestamp)

        if elapsed > 0 && lastBytesIn > 0 {
            let inDelta = Double(network.bytesIn) - Double(lastBytesIn)
            let outDelta = Double(network.bytesOut) - Double(lastBytesOut)
            downloadSpeed = max(0, inDelta / elapsed / 1024)
            uploadSpeed = max(0, outDelta / elapsed / 1024)
        }

        lastBytesIn = network.bytesIn
        lastBytesOut = network.bytesOut
        lastTimestamp = now
    }
}

func getCPUUsagePerCore() -> [Double] {
    var numCPUsU: natural_t = 0
    var cpuInfo: processor_info_array_t!
    var numCpuInfo: mach_msg_type_number_t = 0

    let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
    if result != KERN_SUCCESS {
        return []
    }

    var usages: [Double] = []

    for i in 0..<Int(numCPUsU) {
        let user = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)])
        let sys = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)])
        let idle = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)])
        let nice = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)])

        let total = user + sys + idle + nice
        usages.append(total > 0 ? (user + sys + nice) / total * 100 : 0)
    }

    let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

    return usages
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

func getDiskSpace() -> (free: Double, total: Double) {
    let path = NSHomeDirectory()

    guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path) else {
        return (0, 0)
    }

    let free = attributes[.systemFreeSize] as? Double ?? 0
    let total = attributes[.systemSize] as? Double ?? 0

    return (free / 1_073_741_824, total / 1_073_741_824)
}

func getNetworkBytes() -> (bytesIn: UInt64, bytesOut: UInt64) {
    var totalIn: UInt64 = 0
    var totalOut: UInt64 = 0

    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0 else { return (0, 0) }
    defer { freeifaddrs(ifaddrPtr) }

    var ptr = ifaddrPtr
    while ptr != nil {
        defer { ptr = ptr?.pointee.ifa_next }
        guard let interface = ptr?.pointee else { continue }

        let addrFamily = interface.ifa_addr.pointee.sa_family
        guard addrFamily == UInt8(AF_LINK) else { continue }

        let name = String(cString: interface.ifa_name)
        guard name != "lo0" else { continue }

        if let data = interface.ifa_data {
            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            totalIn += UInt64(networkData.ifi_ibytes)
            totalOut += UInt64(networkData.ifi_obytes)
        }
    }

    return (totalIn, totalOut)
}

func formatSpeed(_ kbPerSecond: Double) -> String {
    if kbPerSecond > 1024 {
        return String(format: "%.1f MB/s", kbPerSecond / 1024)
    }
    return String(format: "%.0f KB/s", kbPerSecond)
}

struct ContentView: View {
    @EnvironmentObject var stats: SystemStats
    @State private var showCoreDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("CPU: \(Int(stats.cpuUsage))%", systemImage: "cpu")
                ProgressView(value: stats.cpuUsage, total: 100)

                if showCoreDetails {
                    ForEach(Array(stats.cpuPerCore.enumerated()), id: \.offset) { index, usage in
                        HStack {
                            Text("Core \(index)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .leading)
                            ProgressView(value: usage, total: 100)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showCoreDetails.toggle()
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("RAM: \(String(format: "%.1f", stats.memoryUsed)) / \(String(format: "%.1f", stats.memoryTotal)) GB", systemImage: "memorychip")
                ProgressView(value: stats.memoryUsed, total: stats.memoryTotal)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("Battery: \(stats.batteryPercentage)%", systemImage: "battery.100")
                ProgressView(value: Double(stats.batteryPercentage), total: 100)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("Disk free: \(String(format: "%.0f", stats.diskFree)) / \(String(format: "%.0f", stats.diskTotal)) GB", systemImage: "internaldrive")
                ProgressView(value: stats.diskTotal - stats.diskFree, total: stats.diskTotal)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("Network", systemImage: "network")
                HStack {
                    Image(systemName: "arrow.down")
                    Text(formatSpeed(stats.downloadSpeed))
                    Spacer()
                    Image(systemName: "arrow.up")
                    Text(formatSpeed(stats.uploadSpeed))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

#Preview {
    ContentView().environmentObject(SystemStats())
}
