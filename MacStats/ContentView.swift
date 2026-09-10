import SwiftUI

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
}

#Preview {
    ContentView()
}
