import Foundation
import XCTest

@testable import QuickAppRuntimeIOSFoundation

final class PackageSourceTests: XCTestCase {
  func testAllSourceKindsShareRandomReadContract() throws {
    let expected = Data("0123456789abcdef\n".utf8)
    let io = DispatchQueue(label: "ios-s01.test.contract.io")
    let core = DispatchQueue(label: "ios-s01.test.contract.core")

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ios-s01-contract-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = directory.appendingPathComponent("case.rpk")
    try expected.write(to: package)

    let sources: [(String, AsyncPackageSource)] = [
      ("memory", AsyncPackageSource.memory(data: expected, ioQueue: io, coreQueue: core)),
      ("file", try AsyncPackageSource.file(url: package, ioQueue: io, coreQueue: core).get()),
      (
        "bundle",
        try AsyncPackageSource.bundleResource(
          bundle: .module,
          name: "package",
          extension: "bin",
          ioQueue: io,
          coreQueue: core
        ).get()
      ),
    ]

    for (name, source) in sources {
      verifyReadContract(name: name, source: source, expected: expected, coreQueue: core)
    }
  }

  func testMemorySourceCopiesInputAndCompletesOnCoreQueue() {
    let io = DispatchQueue(label: "ios-s01.test.io")
    let core = DispatchQueue(label: "ios-s01.test.core")
    let key = DispatchSpecificKey<String>()
    core.setSpecific(key: key, value: "core")

    var input = Data("0123456789".utf8)
    let source = AsyncPackageSource.memory(data: input, ioQueue: io, coreQueue: core)
    input[2] = Character("x").asciiValue!

    let read = expectation(description: "read")
    source.readAt(offset: 2, length: 4) { result in
      XCTAssertEqual(DispatchQueue.getSpecific(key: key), "core")
      XCTAssertEqual(try? result.get().copyBytes(), Array("2345".utf8))
      read.fulfill()
    }
    wait(for: [read], timeout: 2)
  }

  func testCloseAllowsAcceptedReadAndRejectsNewRead() {
    let io = DispatchQueue(label: "ios-s01.test.close.io")
    let core = DispatchQueue(label: "ios-s01.test.close.core")
    let source = AsyncPackageSource.memory(
      data: Data("abcdef".utf8),
      ioQueue: io,
      coreQueue: core
    )
    let accepted = expectation(description: "accepted read")
    source.readAt(offset: 1, length: 3) { result in
      XCTAssertEqual(try? result.get().copyBytes(), Array("bcd".utf8))
      accepted.fulfill()
    }
    source.close()

    let rejected = expectation(description: "closed read")
    source.readAt(offset: 0, length: 1) { result in
      XCTAssertEqual(self.failureCode(result), .packageIOError)
      rejected.fulfill()
    }
    wait(for: [accepted, rejected], timeout: 2)
  }

  func testFileSourceKeepsOpenedResourceIdentity() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ios-s01-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = directory.appendingPathComponent("case.rpk")
    let moved = directory.appendingPathComponent("original.rpk")
    try Data("original".utf8).write(to: package)

    let io = DispatchQueue(label: "ios-s01.test.file.io")
    let core = DispatchQueue(label: "ios-s01.test.file.core")
    let source = try AsyncPackageSource.file(url: package, ioQueue: io, coreQueue: core).get()
    try FileManager.default.moveItem(at: package, to: moved)
    try Data("replaced".utf8).write(to: package)

    let read = expectation(description: "fixed handle read")
    source.readAt(offset: 0, length: 8) { result in
      XCTAssertEqual(try? result.get().copyBytes(), Array("original".utf8))
      read.fulfill()
    }
    wait(for: [read], timeout: 2)
    source.close()
  }

  func testFileSourceReportsShortReadWithoutPartialBytes() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ios-s01-short-read-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = directory.appendingPathComponent("case.rpk")
    try Data("abcdef".utf8).write(to: package)

    let io = DispatchQueue(label: "ios-s01.test.short-read.io")
    let core = DispatchQueue(label: "ios-s01.test.short-read.core")
    let source = try AsyncPackageSource.file(url: package, ioQueue: io, coreQueue: core).get()
    let writer = try FileHandle(forWritingTo: package)
    try writer.truncate(atOffset: 3)
    try writer.close()

    let read = expectation(description: "short read")
    source.readAt(offset: 0, length: 6) { result in
      XCTAssertEqual(self.failureCode(result), .packageIOError)
      read.fulfill()
    }
    wait(for: [read], timeout: 2)
    source.close()
  }

  func testBundleResourceAndRangeFailures() throws {
    let io = DispatchQueue(label: "ios-s01.test.bundle.io")
    let core = DispatchQueue(label: "ios-s01.test.bundle.core")
    let source = try AsyncPackageSource.bundleResource(
      bundle: .module,
      name: "package",
      extension: "bin",
      ioQueue: io,
      coreQueue: core
    ).get()
    XCTAssertEqual(source.size, 17)

    let zero = expectation(description: "zero")
    source.readAt(offset: source.size, length: 0) { result in
      XCTAssertEqual(try? result.get().count, 0)
      zero.fulfill()
    }
    let invalid = expectation(description: "invalid")
    source.readAt(offset: source.size, length: 1) { result in
      XCTAssertEqual(self.failureCode(result), .packageIOError)
      invalid.fulfill()
    }
    wait(for: [zero, invalid], timeout: 2)
  }

  private func failureCode<T>(_ result: Result<T, RuntimeFailure>) -> RuntimeErrorCode? {
    guard case .failure(let error) = result else { return nil }
    return error.code
  }

  private func verifyReadContract(
    name: String,
    source: AsyncPackageSource,
    expected: Data,
    coreQueue: DispatchQueue
  ) {
    XCTAssertEqual(source.size, UInt64(expected.count), name)
    let cases: [(UInt64, Int)] = [
      (0, 3),
      (5, 4),
      (UInt64(expected.count - 3), 3),
      (UInt64(expected.count), 0),
    ]
    for (index, readCase) in cases.enumerated() {
      let read = expectation(description: "\(name) read \(index)")
      source.readAt(offset: readCase.0, length: readCase.1) { result in
        let lower = Int(readCase.0)
        let upper = lower + readCase.1
        XCTAssertEqual(
          try? result.get().copyBytes(),
          Array(expected[lower..<upper]),
          name
        )
        read.fulfill()
      }
      wait(for: [read], timeout: 2)
    }

    let invalid = expectation(description: "\(name) invalid range")
    source.readAt(offset: source.size, length: 1) { result in
      XCTAssertEqual(self.failureCode(result), .packageIOError, name)
      invalid.fulfill()
    }
    wait(for: [invalid], timeout: 2)

    source.close()
    let closed = expectation(description: "\(name) closed")
    source.readAt(offset: 0, length: 1) { result in
      XCTAssertEqual(self.failureCode(result), .packageIOError, name)
      closed.fulfill()
    }
    wait(for: [closed], timeout: 2)

    let drained = expectation(description: "\(name) core queue drained")
    coreQueue.async { drained.fulfill() }
    wait(for: [drained], timeout: 2)
  }
}
