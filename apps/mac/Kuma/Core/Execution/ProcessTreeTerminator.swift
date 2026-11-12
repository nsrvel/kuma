import Darwin
import Foundation
import os

/// Kills descendant PIDs of a managed subprocess (e.g. `npm run dev` → node) on macOS.
nonisolated enum ProcessTreeTerminator {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "ProcessTreeTerminator")

    /// Snapshot of `root` and all descendants (by parent walk), stable after the root shell exits.
    static func subtreePIDs(root: pid_t) -> Set<pid_t> {
        guard root > 1 else { return [] }
        let parentMap = allProcessesParentMap()
        var tree: Set<pid_t> = [root]
        var frontier: Set<pid_t> = [root]
        while !frontier.isEmpty {
            var next: Set<pid_t> = []
            for (pid, ppid) in parentMap where frontier.contains(ppid) && !tree.contains(pid) {
                tree.insert(pid)
                next.insert(pid)
            }
            frontier = next
        }
        return tree
    }

    static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid, 0) == 0
    }

    /// Deepest descendants first so parents can exit cleanly.
    static func sendSignal(_ signal: Int32, toSubtree pids: Set<pid_t>, root: pid_t) {
        let selfPID = getpid()
        let ordered = depthOrdered(pids: pids, root: root)
        for pid in ordered where pid != selfPID {
            if kill(pid, signal) != 0 && errno != ESRCH {
                logger.debug("kill(\(pid), \(signal)) errno \(errno)")
            }
        }
    }

    static func anyAlive(in pids: Set<pid_t>) -> Bool {
        pids.contains { isProcessAlive($0) }
    }

    private static func depthOrdered(pids: Set<pid_t>, root: pid_t) -> [pid_t] {
        let parentMap = allProcessesParentMap()
        var depths: [pid_t: Int] = [root: 0]
        var queue: [pid_t] = [root]
        while let current = queue.popLast() {
            let currentDepth = depths[current] ?? 0
            for (pid, ppid) in parentMap where ppid == current && pids.contains(pid) && depths[pid] == nil {
                depths[pid] = currentDepth + 1
                queue.append(pid)
            }
        }
        return pids.sorted { (depths[$0] ?? 0) > (depths[$1] ?? 0) }
    }

    private static func allProcessesParentMap() -> [pid_t: pid_t] {
        let capacity = 16_384
        var buffer = [pid_t](repeating: 0, count: capacity)
        let byteCount = Int32(MemoryLayout<pid_t>.stride * capacity)
        let used = proc_listallpids(&buffer, byteCount)
        guard used > 0 else { return [:] }
        let count = Int(used) / MemoryLayout<pid_t>.stride
        var map: [pid_t: pid_t] = [:]
        for pid in buffer.prefix(count) where pid > 1 {
            if let ppid = parentPID(of: pid) {
                map[pid] = ppid
            }
        }
        return map
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let status = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard status == size else { return nil }
        return pid_t(info.pbi_ppid)
    }
}
