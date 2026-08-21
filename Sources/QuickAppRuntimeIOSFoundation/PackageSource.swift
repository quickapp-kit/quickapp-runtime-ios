import Foundation

public struct ImmutableBytes: Equatable, Sendable {
  private let storage: [UInt8]

  public init<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
    storage = Array(bytes)
  }

  public var count: Int { storage.count }
  public var isEmpty: Bool { storage.isEmpty }
  public func copyBytes() -> [UInt8] { storage }
}

public typealias PackageReadResult = Result<ImmutableBytes, RuntimeFailure>
public typealias PackageReadCompletion = (PackageReadResult) -> Void

public protocol PackageSource: AnyObject {
  var size: UInt64 { get }
  func readAt(offset: UInt64, length: Int, completion: @escaping PackageReadCompletion)
  func close()
}

private protocol PackageBackend: AnyObject {
  var size: UInt64 { get }
  func read(offset: UInt64, length: Int) -> PackageReadResult
  func close()
}

private final class MemoryPackageBackend: PackageBackend {
  private let lock = NSLock()
  private var bytes: [UInt8]?

  init(data: Data) {
    bytes = Array(data)
  }

  var size: UInt64 {
    lock.withLock { UInt64(bytes?.count ?? 0) }
  }

  func read(offset: UInt64, length: Int) -> PackageReadResult {
    lock.withLock {
      guard let bytes else { return .failure(packageIO("source is closed")) }
      guard let range = checkedRange(size: bytes.count, offset: offset, length: length) else {
        return .failure(packageIO("read range is invalid"))
      }
      return .success(ImmutableBytes(bytes[range]))
    }
  }

  func close() {
    lock.withLock { bytes = nil }
  }
}

private final class FilePackageBackend: PackageBackend {
  private let lock = NSLock()
  private var handle: FileHandle?
  let size: UInt64

  private init(handle: FileHandle, size: UInt64) {
    self.handle = handle
    self.size = size
  }

  static func open(url: URL) -> Result<FilePackageBackend, RuntimeFailure> {
    guard url.isFileURL else {
      return .failure(
        RuntimeFailure(code: .packageNotFound, message: "package URL must be a file URL"))
    }
    do {
      let handle = try FileHandle(forReadingFrom: url)
      let size = try handle.seekToEnd()
      try handle.seek(toOffset: 0)
      return .success(FilePackageBackend(handle: handle, size: size))
    } catch {
      return .failure(
        RuntimeFailure(code: .packageNotFound, message: "package file cannot be opened"))
    }
  }

  func read(offset: UInt64, length: Int) -> PackageReadResult {
    lock.withLock {
      guard let handle else { return .failure(packageIO("source is closed")) }
      guard checkedRange(size: size, offset: offset, length: length) != nil else {
        return .failure(packageIO("read range is invalid"))
      }
      do {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length else {
          return .failure(packageIO("package short read"))
        }
        return .success(ImmutableBytes(data))
      } catch {
        return .failure(packageIO("package read failed"))
      }
    }
  }

  func close() {
    lock.withLock {
      guard let handle else { return }
      self.handle = nil
      try? handle.close()
    }
  }
}

public final class AsyncPackageSource: PackageSource {
  private final class State {
    let lock = NSLock()
    var backend: (any PackageBackend)?
    var acceptingReads = true
    var inFlightReads = 0
    let size: UInt64

    init(backend: any PackageBackend) {
      self.backend = backend
      size = backend.size
    }

    func acceptRead() -> (any PackageBackend)? {
      lock.withLock {
        guard acceptingReads, let backend else { return nil }
        inFlightReads += 1
        return backend
      }
    }

    func finishRead() {
      let backendToClose: (any PackageBackend)? = lock.withLock {
        inFlightReads -= 1
        guard !acceptingReads, inFlightReads == 0 else { return nil }
        let value = backend
        backend = nil
        return value
      }
      backendToClose?.close()
    }

    func close() {
      let backendToClose: (any PackageBackend)? = lock.withLock {
        guard acceptingReads else { return nil }
        acceptingReads = false
        guard inFlightReads == 0 else { return nil }
        let value = backend
        backend = nil
        return value
      }
      backendToClose?.close()
    }
  }

  private let state: State
  private let ioQueue: DispatchQueue
  private let coreQueue: DispatchQueue

  private init(backend: any PackageBackend, ioQueue: DispatchQueue, coreQueue: DispatchQueue) {
    state = State(backend: backend)
    self.ioQueue = ioQueue
    self.coreQueue = coreQueue
  }

  public static func memory(
    data: Data,
    ioQueue: DispatchQueue,
    coreQueue: DispatchQueue
  ) -> AsyncPackageSource {
    AsyncPackageSource(
      backend: MemoryPackageBackend(data: data),
      ioQueue: ioQueue,
      coreQueue: coreQueue
    )
  }

  public static func file(
    url: URL,
    ioQueue: DispatchQueue,
    coreQueue: DispatchQueue
  ) -> Result<AsyncPackageSource, RuntimeFailure> {
    FilePackageBackend.open(url: url).map {
      AsyncPackageSource(backend: $0, ioQueue: ioQueue, coreQueue: coreQueue)
    }
  }

  public static func bundleResource(
    bundle: Bundle,
    name: String,
    extension fileExtension: String?,
    subdirectory: String? = nil,
    ioQueue: DispatchQueue,
    coreQueue: DispatchQueue
  ) -> Result<AsyncPackageSource, RuntimeFailure> {
    guard
      let url = bundle.url(
        forResource: name,
        withExtension: fileExtension,
        subdirectory: subdirectory
      )
    else {
      return .failure(
        RuntimeFailure(code: .packageNotFound, message: "bundle package resource was not found"))
    }
    return file(url: url, ioQueue: ioQueue, coreQueue: coreQueue)
  }

  public var size: UInt64 { state.size }

  public func readAt(offset: UInt64, length: Int, completion: @escaping PackageReadCompletion) {
    guard length >= 0,
      checkedRange(size: state.size, offset: offset, length: length) != nil
    else {
      coreQueue.async { completion(.failure(packageIO("read range is invalid"))) }
      return
    }
    guard let backend = state.acceptRead() else {
      coreQueue.async { completion(.failure(packageIO("source is closed"))) }
      return
    }
    let state = state
    let coreQueue = coreQueue
    ioQueue.async {
      let result = backend.read(offset: offset, length: length)
      state.finishRead()
      coreQueue.async { completion(result) }
    }
  }

  public func close() {
    state.close()
  }

  deinit {
    state.close()
  }
}

private func checkedRange(size: Int, offset: UInt64, length: Int) -> Range<Int>? {
  checkedRange(size: UInt64(size), offset: offset, length: length)
}

private func checkedRange(size: UInt64, offset: UInt64, length: Int) -> Range<Int>? {
  guard length >= 0,
    offset <= size,
    UInt64(length) <= size - offset,
    offset <= UInt64(Int.max),
    UInt64(length) <= UInt64(Int.max) - offset
  else {
    return nil
  }
  let lower = Int(offset)
  return lower..<lower + length
}

private func packageIO(_ message: String) -> RuntimeFailure {
  RuntimeFailure(code: .packageIOError, message: message)
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
