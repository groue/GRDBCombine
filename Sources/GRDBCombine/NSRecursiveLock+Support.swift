import Foundation

extension NSRecursiveLock {
    func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}
