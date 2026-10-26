import Foundation
import IOKit
import CryptoKit
import Darwin

/// Port IOKit par défaut (ioPortDefault n'existe qu'à partir de macOS 12).
let ioPortDefault: mach_port_t = 0

/// Informations sur ce Mac : identifiant de poste, modèle, version de macOS.
enum SystemInfo {
    static let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    static var hostname: String { Host.current().localizedName ?? "Mac" }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var modelIdentifier: String { sysctlString("hw.model") ?? "Mac" }

    static var isAppleSilicon: Bool {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &size, nil, 0) == 0 && v == 1
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func platformUUID() -> String {
        let svc = IOServiceGetMatchingService(ioPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(svc) }
        if let v = IORegistryEntryCreateCFProperty(svc, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return v
        }
        return Host.current().name ?? UUID().uuidString
    }

    /// Identifiant stable de ce Mac pour les licences (préfixé « mac- » pour le distinguer des PC).
    static let machineID: String = {
        let digest = SHA256.hash(data: Data(("optimac:" + platformUUID()).utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "mac-" + String(hex.prefix(48))
    }()
}

/// Mesures en direct : processeur, mémoire, disque, carte graphique.
final class Sampler {
    private var prevTicks: [Int64] = []
    private var prevDiskBytes: UInt64 = 0
    private var prevDiskTime = Date()

    func cpu() -> Double {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        let r = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &info, &count)
        guard r == KERN_SUCCESS, let info else { return 0 }
        let arr = (0..<Int(count)).map { Int64(info[$0]) }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        defer { prevTicks = arr }
        guard prevTicks.count == arr.count else { return 0 }
        var used: Int64 = 0, total: Int64 = 0
        let stride = Int(CPU_STATE_MAX)
        for c in 0..<Int(numCPUs) {
            let b = c * stride
            let u = arr[b + Int(CPU_STATE_USER)] - prevTicks[b + Int(CPU_STATE_USER)]
            let s = arr[b + Int(CPU_STATE_SYSTEM)] - prevTicks[b + Int(CPU_STATE_SYSTEM)]
            let n = arr[b + Int(CPU_STATE_NICE)] - prevTicks[b + Int(CPU_STATE_NICE)]
            let i = arr[b + Int(CPU_STATE_IDLE)] - prevTicks[b + Int(CPU_STATE_IDLE)]
            used += max(0, u + s + n)
            total += max(0, u + s + n + i)
        }
        return total > 0 ? Double(used) / Double(total) : 0
    }

    /// Mémoire utilisée (comme le Moniteur d'activité) et mémoire totale, en octets.
    static func memory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard r == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    /// Débit disque (lecture + écriture) en octets par seconde.
    func diskThroughput() -> Double {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(ioPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iter) }
        var total: UInt64 = 0
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            if let props = IORegistryEntryCreateCFProperty(svc, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                total &+= (props["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                total &+= (props["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        let now = Date()
        let dt = now.timeIntervalSince(prevDiskTime)
        defer { prevDiskBytes = total; prevDiskTime = now }
        guard prevDiskBytes > 0, total >= prevDiskBytes, dt > 0 else { return 0 }
        return Double(total - prevDiskBytes) / dt
    }

    /// Utilisation de la carte graphique (0…1), ou nil si macOS ne la fournit pas.
    static func gpu() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(ioPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            if let stats = IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let u = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                best = max(best ?? 0, u / 100)
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        return best
    }
}

/// Publie les mesures toutes les 2 secondes pour les graphiques de la barre latérale.
@MainActor
final class Monitor: ObservableObject {
    @Published var cpu: [Double] = Array(repeating: 0, count: 30)
    @Published var mem: [Double] = Array(repeating: 0, count: 30)
    @Published var disk: [Double] = Array(repeating: 0, count: 30)
    @Published var gpu: [Double] = Array(repeating: 0, count: 30)
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = 0
    @Published var diskRate: Double = 0
    @Published var hasGPU = true
    @Published var freeSpace: Int64 = 0
    @Published var totalSpace: Int64 = 0
    @Published var thermal: ProcessInfo.ThermalState = .nominal

    private let sampler = Sampler()
    private var timer: Timer?

    init() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let strong = self else { return }
            Task { @MainActor in strong.tick() }
        }
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > 30 { arr.removeFirst(arr.count - 30) }
    }

    func tick() {
        push(&cpu, sampler.cpu())
        let m = Sampler.memory()
        memUsed = m.used
        memTotal = m.total
        push(&mem, m.total > 0 ? Double(m.used) / Double(m.total) : 0)
        diskRate = sampler.diskThroughput()
        push(&disk, diskRate)
        if let g = Sampler.gpu() { push(&gpu, g); hasGPU = true } else { hasGPU = false }
        let v = FS.volume()
        freeSpace = v.free
        totalSpace = v.total
        thermal = ProcessInfo.processInfo.thermalState
    }

    var cpuNow: Double { cpu.last ?? 0 }
    var memNow: Double { mem.last ?? 0 }
    var gpuNow: Double { gpu.last ?? 0 }
    var diskUsedRatio: Double { totalSpace > 0 ? 1 - Double(freeSpace) / Double(totalSpace) : 0 }
}
