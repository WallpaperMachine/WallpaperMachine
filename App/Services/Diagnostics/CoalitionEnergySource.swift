import Darwin
import Foundation

/// Reads the kernel's per-coalition energy accounting without privileges.
///
/// A resource coalition groups an app with the XPC services it launches, so this app's
/// coalition also covers the control panel's WebKit processes and the video decoder
/// service. The lock-screen extension runs in a coalition of its own and is found by its
/// executable path inside this bundle.
///
/// `coalition_info_resource_usage` and `proc_listcoalitions` are private libsystem
/// exports and `PROC_PIDCOALITIONINFO` is a private `proc_pidinfo` flavor; the struct
/// layouts below come from xnu (`osfmk/mach/coalition.h`,
/// `bsd/sys/proc_info_private.h`). Symbols are resolved at run time and `init` returns
/// nil when any is missing, so the readout reports itself unavailable instead of failing.
/// Public macOS offers no per-process GPU energy: `task_gpu_utilisation` is only
/// accumulated on x86_64 and `rusage` energy covers the CPU alone.
final class CoalitionEnergySource: EnergyUsageSource, @unchecked Sendable {
  private typealias ResourceUsage = @convention(c) (UInt64, UnsafeMutableRawPointer, Int) -> Int32
  private typealias ListCoalitions = @convention(c) (Int32, Int32, UnsafeMutableRawPointer?, Int32)
    -> Int32

  /// `struct coalition_resource_usage` was 45 `uint64_t` fields and macOS 27 appends
  /// five more; the kernel copies the smaller of its size and ours, so fields a kernel
  /// lacks read as zero and fields past ours are not read.
  private static let usageFields = 45
  private static let gpuTimeField = 8
  private static let cpuEnergyField = 11
  private static let gpuEnergyField = 41
  private static let pidCoalitionInfoFlavor: Int32 = 20
  private static let listSingleType: Int32 = 2
  private static let resourceCoalition: Int32 = 0

  private let resourceUsage: ResourceUsage
  private let listCoalitions: ListCoalitions
  private let ownCoalition: UInt64
  private let extensionsPath: String

  init?(
    extensionsDirectory: URL = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Extensions", isDirectory: true)
  ) {
    // RTLD_DEFAULT is a macro Swift does not import; <dlfcn.h> defines it as -2.
    let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
    guard let usage = dlsym(everyImage, "coalition_info_resource_usage"),
      let list = dlsym(everyImage, "proc_listcoalitions"),
      let own = Self.coalition(of: getpid())
    else { return nil }
    resourceUsage = unsafeBitCast(usage, to: ResourceUsage.self)
    listCoalitions = unsafeBitCast(list, to: ListCoalitions.self)
    ownCoalition = own
    extensionsPath = extensionsDirectory.standardizedFileURL.path + "/"
  }

  func sample() -> EnergyUsageSample? {
    let now = DispatchTime.now().uptimeNanoseconds
    guard let mine = counters(ownCoalition) else { return nil }
    var own = [ownCoalition: mine]
    for pid in extensionPIDs() {
      guard let id = Self.coalition(of: pid), own[id] == nil, let value = counters(id) else {
        continue
      }
      own[id] = value
    }
    var others: [UInt64: UInt64] = [:]
    for id in coalitionIDs() where own[id] == nil {
      if let value = counters(id) { others[id] = value.gpuTimeNanoseconds }
    }
    return EnergyUsageSample(uptimeNanoseconds: now, own: own, otherGPUTime: others)
  }

  private func counters(_ coalition: UInt64) -> CoalitionEnergyCounters? {
    var fields = [UInt64](repeating: 0, count: Self.usageFields)
    let status = fields.withUnsafeMutableBytes {
      resourceUsage(coalition, $0.baseAddress!, $0.count)
    }
    guard status == 0 else { return nil }
    return CoalitionEnergyCounters(
      cpuEnergyNanojoules: fields[Self.cpuEnergyField],
      gpuEnergyNanojoules: fields[Self.gpuEnergyField],
      gpuTimeNanoseconds: fields[Self.gpuTimeField])
  }

  /// Every resource coalition id. Entries are `struct procinfo_coalinfo`:
  /// a `uint64_t` id followed by two `uint32_t` (type, task count).
  private func coalitionIDs() -> [UInt64] {
    var capacity = 1024
    while capacity <= 65536 {
      var entries = [UInt64](repeating: 0, count: capacity * 2)
      let bytes = entries.withUnsafeMutableBytes {
        listCoalitions(Self.listSingleType, Self.resourceCoalition, $0.baseAddress, Int32($0.count))
      }
      guard bytes >= 0 else { return [] }
      let count = Int(bytes) / 16
      if count < capacity { return (0..<count).map { entries[$0 * 2] } }
      capacity *= 2
    }
    return []
  }

  /// Processes running an executable from this bundle's `Contents/Extensions`.
  private func extensionPIDs() -> [pid_t] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
    let count = pids.withUnsafeMutableBytes {
      proc_listallpids($0.baseAddress, Int32($0.count))
    }
    guard count > 0 else { return [] }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    return pids.prefix(Int(count)).filter { pid in
      guard pid > 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
      return String(cString: path).hasPrefix(extensionsPath)
    }
  }

  /// `struct proc_pidcoalitioninfo`: ids per coalition type, then three reserved words.
  private static func coalition(of pid: pid_t) -> UInt64? {
    var info = [UInt64](repeating: 0, count: 5)
    let size = info.withUnsafeMutableBytes {
      proc_pidinfo(pid, pidCoalitionInfoFlavor, 0, $0.baseAddress, Int32($0.count))
    }
    guard size == 40, info[0] != 0 else { return nil }
    return info[0]
  }
}
