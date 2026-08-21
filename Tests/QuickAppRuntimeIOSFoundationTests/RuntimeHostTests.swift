import Foundation
import XCTest

@testable import QuickAppRuntimeIOSFoundation

private final class LockedBox<Value> {
  private let lock = NSLock()
  private var storage: Value

  init(_ value: Value) { storage = value }

  func read() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func update(_ body: (inout Value) -> Void) {
    lock.lock()
    body(&storage)
    lock.unlock()
  }
}

private final class FakePackageSource: PackageSource {
  private let lock = NSLock()
  private var closes = 0
  var size: UInt64 { 4 }
  var closeCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return closes
  }

  func readAt(offset _: UInt64, length _: Int, completion: @escaping PackageReadCompletion) {
    completion(.success(ImmutableBytes([0, 1, 2, 3])))
  }

  func close() {
    lock.lock()
    closes += 1
    lock.unlock()
  }
}

private final class FakeCoreRuntime: CoreAppRuntime {
  typealias ControlRecord = (RuntimeLifecycleControl, LifecycleCompletion)
  private let lock = NSLock()
  private var rootCompletion: RootStartCompletion?
  private var controls: [ControlRecord] = []
  var onRootRequested: (() -> Void)?
  var onControl: ((RuntimeLifecycleControl) -> Void)?

  func startRoot(profile _: RuntimeLaunchProfile, completion: @escaping RootStartCompletion) {
    lock.lock()
    rootCompletion = completion
    let callback = onRootRequested
    lock.unlock()
    callback?()
  }

  func controlLifecycle(
    _ control: RuntimeLifecycleControl, completion: @escaping LifecycleCompletion
  ) {
    lock.lock()
    controls.append((control, completion))
    let callback = onControl
    lock.unlock()
    callback?(control)
  }

  func completeRoot(_ result: Result<RootPresented, RuntimeFailure>) {
    lock.lock()
    let completion = rootCompletion
    lock.unlock()
    completion?(result)
  }

  func controlSnapshot() -> [RuntimeLifecycleControl] {
    lock.lock()
    defer { lock.unlock() }
    return controls.map(\.0)
  }

  func completeControl(
    requestID: String, result: RuntimeLifecycleControlResult, repeatCount: Int = 1
  ) {
    lock.lock()
    let completion = controls.first { $0.0.requestID == requestID }?.1
    lock.unlock()
    for _ in 0..<repeatCount { completion?(result) }
  }
}

private final class FakeCoreFactory: CoreAppRuntimeFactory {
  private let runtime: FakeCoreRuntime
  private let callbackQueue: DispatchQueue
  private let lock = NSLock()
  private var request: AppRuntimeCreateRequest?
  var onCreate: (() -> Void)?

  init(runtime: FakeCoreRuntime, callbackQueue: DispatchQueue) {
    self.runtime = runtime
    self.callbackQueue = callbackQueue
  }

  func create(
    request: AppRuntimeCreateRequest,
    completion: @escaping (Result<any CoreAppRuntime, RuntimeFailure>) -> Void
  ) {
    lock.lock()
    self.request = request
    let callback = onCreate
    lock.unlock()
    callback?()
    callbackQueue.async { [runtime] in completion(.success(runtime)) }
  }

  func releaseCapturedRequest() {
    lock.lock()
    request = nil
    lock.unlock()
  }

  func capturedRequest() -> AppRuntimeCreateRequest? {
    lock.lock()
    defer { lock.unlock() }
    return request
  }
}

private final class WeakObjectBox {
  weak var value: AnyObject?
  init(_ value: AnyObject) { self.value = value }
}

private struct HostHarness {
  let host: IOSRuntimeHost
  let runtime: FakeCoreRuntime
  let factory: FakeCoreFactory
  let source: FakePackageSource
  let hostQueue: DispatchQueue
  let hostQueueKey: DispatchSpecificKey<String>
  let engine: WeakObjectBox
  let sink: WeakObjectBox
  let clock: WeakObjectBox
  let ports: WeakObjectBox
}

final class RuntimeHostTests: XCTestCase {
  func testProfilePreflightRunsBeforePackageSourceCreation() throws {
    let manifest = validManifest()
    let composed = try compose(manifest: manifest).successValue()
    let runtime = FakeCoreRuntime()
    let factory = FakeCoreFactory(
      runtime: runtime,
      callbackQueue: DispatchQueue(label: "ios-s01.test.preflight.factory")
    )
    let source = FakePackageSource()
    let sourceFactoryCalls = LockedBox(0)
    let invalidProfile = RuntimeLaunchProfile(
      artifact: "/tmp/case-001.rpk",
      entryRoute: "/pages/index",
      params: [:],
      viewport: Viewport(width: 390, height: 844),
      traceOutput: "disabled",
      target: .android
    )

    let result = IOSRuntimeHost.create(
      profile: invalidProfile,
      composition: composed,
      packageSourceFactory: {
        sourceFactoryCalls.update { $0 += 1 }
        return .success(source)
      },
      factory: factory
    )

    XCTAssertEqual(failureCode(result), .abiInvalidArgument)
    XCTAssertEqual(sourceFactoryCalls.read(), 0)
  }

  func testRootPresentedIsOnlyStartupSuccessBoundary() throws {
    let harness = try makeHarness()
    let rootRequested = expectation(description: "root requested")
    harness.runtime.onRootRequested = { rootRequested.fulfill() }
    let completionCount = LockedBox(0)
    let started = expectation(description: "started")
    harness.host.start { result in
      XCTAssertEqual(DispatchQueue.getSpecific(key: harness.hostQueueKey), "host")
      XCTAssertEqual(try? result.get(), RootPresented(surfaceID: "srf:root"))
      completionCount.update { $0 += 1 }
      started.fulfill()
    }
    wait(for: [rootRequested], timeout: 2)

    let barrier = expectation(description: "host barrier")
    harness.hostQueue.async { barrier.fulfill() }
    wait(for: [barrier], timeout: 2)
    XCTAssertEqual(completionCount.read(), 0)
    XCTAssertEqual(harness.host.state, .starting)

    let createRequest = try XCTUnwrap(harness.factory.capturedRequest())
    XCTAssertTrue(createRequest.monotonicClock === harness.clock.value)
    XCTAssertTrue(createRequest.platformPorts === harness.ports.value)

    harness.runtime.completeRoot(.success(RootPresented(surfaceID: "srf:root")))
    wait(for: [started], timeout: 2)
    XCTAssertEqual(completionCount.read(), 1)
    XCTAssertEqual(harness.host.state, .running)
  }

  func testRawSceneDedupOccursBeforeRequestID() throws {
    let harness = try makeStartedHarness()
    let controlCaptured = expectation(description: "control captured")
    harness.runtime.onControl = { _ in controlCaptured.fulfill() }
    let firstAdmission = expectation(description: "first accepted")
    let result = expectation(description: "first result")
    let acceptedID = LockedBox<String?>(nil)
    harness.host.handleRawSceneSignal(
      .active,
      admission: { admission in
        guard case .accepted(let requestID) = admission else {
          XCTFail("first raw signal must be accepted")
          return
        }
        acceptedID.update { $0 = requestID }
        firstAdmission.fulfill()
      },
      completion: { value in
        XCTAssertEqual(value.requestID, acceptedID.read())
        result.fulfill()
      })
    wait(for: [firstAdmission, controlCaptured], timeout: 2)

    let deduplicated = expectation(description: "deduplicated")
    let duplicateResultCount = LockedBox(0)
    harness.host.handleRawSceneSignal(
      .active,
      admission: { admission in
        XCTAssertEqual(admission, .deduplicated)
        deduplicated.fulfill()
      }, completion: { _ in duplicateResultCount.update { $0 += 1 } })
    wait(for: [deduplicated], timeout: 2)
    let dedupBarrier = expectation(description: "dedup barrier")
    harness.hostQueue.async { dedupBarrier.fulfill() }
    wait(for: [dedupBarrier], timeout: 2)
    XCTAssertEqual(duplicateResultCount.read(), 0)
    XCTAssertEqual(harness.runtime.controlSnapshot().count, 1)

    let requestID = try XCTUnwrap(acceptedID.read())
    harness.runtime.completeControl(
      requestID: requestID,
      result: .completed(requestID: requestID, action: .enterForeground, runtimeState: .foreground)
    )
    wait(for: [result], timeout: 2)
  }

  func testAcceptedControlsEnterCoreAndBusyIsForwardedExactlyOnce() throws {
    let harness = try makeStartedHarness()
    let captured = expectation(description: "two controls captured")
    captured.expectedFulfillmentCount = 2
    harness.runtime.onControl = { _ in captured.fulfill() }
    let admitted = expectation(description: "two admissions")
    admitted.expectedFulfillmentCount = 2
    let ids = LockedBox<[String]>([])
    let results = LockedBox<[RuntimeLifecycleControlResult]>([])
    let completed = expectation(description: "two results")
    completed.expectedFulfillmentCount = 2

    for action in [LifecycleAction.enterForeground, .enterBackground] {
      harness.host.requestLifecycle(
        action,
        admission: { admission in
          guard case .accepted(let requestID) = admission else {
            XCTFail("control must be accepted")
            return
          }
          ids.update { $0.append(requestID) }
          admitted.fulfill()
        },
        completion: { result in
          results.update { $0.append(result) }
          completed.fulfill()
        })
    }
    wait(for: [admitted, captured], timeout: 2)
    let controls = harness.runtime.controlSnapshot()
    XCTAssertEqual(controls.count, 2)
    XCTAssertNotEqual(controls[0].requestID, controls[1].requestID)

    let busy = RuntimeFailure(code: .lifecycleBusy, message: "core control is busy")
    harness.runtime.completeControl(
      requestID: controls[1].requestID,
      result: .failed(requestID: controls[1].requestID, action: controls[1].action, error: busy),
      repeatCount: 2
    )
    harness.runtime.completeControl(
      requestID: controls[0].requestID,
      result: .completed(
        requestID: controls[0].requestID, action: controls[0].action, runtimeState: .foreground)
    )
    wait(for: [completed], timeout: 2)

    let barrier = expectation(description: "duplicate result drained")
    harness.hostQueue.async { barrier.fulfill() }
    wait(for: [barrier], timeout: 2)
    XCTAssertEqual(results.read().count, 2)
    let busyResult = results.read().first { $0.requestID == controls[1].requestID }
    XCTAssertEqual(
      busyResult,
      .failed(requestID: controls[1].requestID, action: .enterBackground, error: busy)
    )
    XCTAssertEqual(harness.host.runtimeState, .foreground)
  }

  func testDestroyFailureStillClosesAndReleasesHostOwnedResources() throws {
    let harness = try makeStartedHarness()
    harness.factory.releaseCapturedRequest()
    XCTAssertNotNil(harness.engine.value)
    XCTAssertNotNil(harness.sink.value)
    let captured = expectation(description: "destroy captured")
    harness.runtime.onControl = { control in
      if control.action == .destroyAppRuntime { captured.fulfill() }
    }
    let admission = expectation(description: "destroy accepted")
    let completed = expectation(description: "destroy completed")
    let requestID = LockedBox<String?>(nil)
    let failure = RuntimeFailure(code: .platformRejected, message: "forced destroy failure")
    harness.host.destroy(
      admission: { value in
        guard case .accepted(let id) = value else {
          XCTFail("destroy must be accepted")
          return
        }
        requestID.update { $0 = id }
        admission.fulfill()
      },
      completion: { value in
        XCTAssertEqual(
          value,
          .failed(
            requestID: requestID.read()!,
            action: .destroyAppRuntime,
            error: failure
          ))
        completed.fulfill()
      })
    wait(for: [admission, captured], timeout: 2)
    let id = try XCTUnwrap(requestID.read())
    harness.runtime.completeControl(
      requestID: id,
      result: .failed(requestID: id, action: .destroyAppRuntime, error: failure)
    )
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(harness.host.state, .destroyed)
    XCTAssertEqual(harness.source.closeCount, 1)
    XCTAssertNil(harness.engine.value)
    XCTAssertNil(harness.sink.value)
    XCTAssertNil(harness.clock.value)
    XCTAssertNil(harness.ports.value)

    let rejected = expectation(description: "repeat destroy rejected")
    harness.host.destroy(
      admission: { value in
        guard case .rejected = value else {
          XCTFail("repeat destroy must not be accepted")
          return
        }
        rejected.fulfill()
      }, completion: { _ in XCTFail("rejected destroy has no typed result") })
    wait(for: [rejected], timeout: 2)
  }

  func testDestroyReleasesAllHostOwnedObjects() throws {
    let manifest = validManifest()
    var engine: FakeEngineProvider? = FakeEngineProvider(identity: manifest.jsEngine)
    var sink: RecordingTraceSink? = RecordingTraceSink()
    var clock: FakeMonotonicClock? = FakeMonotonicClock()
    var ports: FakePlatformPortSet? = FakePlatformPortSet()
    let engineBox = WeakObjectBox(try XCTUnwrap(engine))
    let sinkBox = WeakObjectBox(try XCTUnwrap(sink))
    let clockBox = WeakObjectBox(try XCTUnwrap(clock))
    let portsBox = WeakObjectBox(try XCTUnwrap(ports))

    var composition: ComposedRuntime? = try compose(
      manifest: manifest,
      engines: [try XCTUnwrap(engine)],
      recordingSink: try XCTUnwrap(sink),
      monotonicClock: try XCTUnwrap(clock),
      platformPorts: try XCTUnwrap(ports)
    ).successValue()
    var source: FakePackageSource? = FakePackageSource()
    var runtime: FakeCoreRuntime? = FakeCoreRuntime()
    var factory: FakeCoreFactory? = FakeCoreFactory(
      runtime: try XCTUnwrap(runtime),
      callbackQueue: DispatchQueue(label: "ios-s01.test.release.factory")
    )
    let sourceBox = WeakObjectBox(try XCTUnwrap(source))
    let runtimeBox = WeakObjectBox(try XCTUnwrap(runtime))
    let factoryBox = WeakObjectBox(try XCTUnwrap(factory))

    let host = try IOSRuntimeHost.create(
      profile: validProfile(),
      composition: try XCTUnwrap(composition),
      packageSourceFactory: { .success(source!) },
      factory: try XCTUnwrap(factory)
    ).get()
    composition = nil

    let rootRequested = expectation(description: "release root requested")
    runtime?.onRootRequested = { rootRequested.fulfill() }
    let started = expectation(description: "release started")
    host.start { _ in started.fulfill() }
    wait(for: [rootRequested], timeout: 2)
    runtime?.completeRoot(.success(RootPresented(surfaceID: "srf:release")))
    wait(for: [started], timeout: 2)

    let destroyCaptured = expectation(description: "release destroy captured")
    runtime?.onControl = { control in
      if control.action == .destroyAppRuntime { destroyCaptured.fulfill() }
    }
    let destroyed = expectation(description: "release destroyed")
    host.destroy(admission: { _ in }, completion: { _ in destroyed.fulfill() })
    wait(for: [destroyCaptured], timeout: 2)
    let destroyControl = try XCTUnwrap(runtime?.controlSnapshot().last)

    engine = nil
    sink = nil
    clock = nil
    ports = nil
    source = nil
    factory = nil
    runtime?.completeControl(
      requestID: destroyControl.requestID,
      result: .completed(
        requestID: destroyControl.requestID,
        action: destroyControl.action,
        runtimeState: .destroyed
      )
    )
    runtime = nil
    wait(for: [destroyed], timeout: 2)

    XCTAssertEqual(host.state, .destroyed)
    XCTAssertNil(engineBox.value)
    XCTAssertNil(sinkBox.value)
    XCTAssertNil(clockBox.value)
    XCTAssertNil(portsBox.value)
    XCTAssertNil(sourceBox.value)
    XCTAssertNil(runtimeBox.value)
    XCTAssertNil(factoryBox.value)
  }

  func testRootFailureRunsCoreCleanupBeforeReportingFailure() throws {
    let harness = try makeHarness()
    let rootRequested = expectation(description: "root requested")
    harness.runtime.onRootRequested = { rootRequested.fulfill() }
    let cleanupCaptured = expectation(description: "cleanup captured")
    harness.runtime.onControl = { control in
      if control.action == .destroyAppRuntime { cleanupCaptured.fulfill() }
    }
    let startFailed = expectation(description: "start failed")
    let expected = RuntimeFailure(code: .platformRejected, message: "present failed")
    harness.host.start { result in
      XCTAssertEqual(self.failureCode(result), expected.code)
      startFailed.fulfill()
    }
    wait(for: [rootRequested], timeout: 2)
    harness.runtime.completeRoot(.failure(expected))
    wait(for: [cleanupCaptured], timeout: 2)
    let cleanup = try XCTUnwrap(harness.runtime.controlSnapshot().last)
    harness.runtime.completeControl(
      requestID: cleanup.requestID,
      result: .failed(requestID: cleanup.requestID, action: cleanup.action, error: expected)
    )
    wait(for: [startFailed], timeout: 2)
    XCTAssertEqual(harness.host.state, .destroyed)
    XCTAssertEqual(harness.source.closeCount, 1)
  }

  func testNoopAndRecordingProduceEquivalentHostBehavior() throws {
    let noop = try runObservationScenario(level: .off)
    let recording = try runObservationScenario(level: .baseline)
    XCTAssertEqual(noop.actions, recording.actions)
    XCTAssertEqual(noop.states, recording.states)
    XCTAssertEqual(noop.closeCount, recording.closeCount)
  }

  private func makeHarness(
    conformance: Conformance = .v1,
    observation: ObservationLevel = .baseline
  ) throws -> HostHarness {
    let manifest = validManifest(conformance: conformance, observation: observation)
    let engine = FakeEngineProvider(identity: manifest.jsEngine)
    let sink = RecordingTraceSink()
    let clock = FakeMonotonicClock()
    let ports = FakePlatformPortSet()
    let engineBox = WeakObjectBox(engine)
    let sinkBox = WeakObjectBox(sink)
    let clockBox = WeakObjectBox(clock)
    let portsBox = WeakObjectBox(ports)
    let composed = try compose(
      manifest: manifest,
      engines: [engine],
      recordingSink: sink,
      monotonicClock: clock,
      platformPorts: ports
    ).successValue()
    let source = FakePackageSource()
    let runtime = FakeCoreRuntime()
    let callbackQueue = DispatchQueue(label: "ios-s01.test.factory")
    let factory = FakeCoreFactory(runtime: runtime, callbackQueue: callbackQueue)
    let hostQueue = DispatchQueue(label: "ios-s01.test.host")
    let hostQueueKey = DispatchSpecificKey<String>()
    hostQueue.setSpecific(key: hostQueueKey, value: "host")
    let host = try IOSRuntimeHost.create(
      profile: validProfile(),
      composition: composed,
      packageSourceFactory: { .success(source) },
      factory: factory,
      hostQueue: hostQueue,
      requestIDs: RequestIDGenerator(prefix: "req:ios-test")
    ).get()
    return HostHarness(
      host: host,
      runtime: runtime,
      factory: factory,
      source: source,
      hostQueue: hostQueue,
      hostQueueKey: hostQueueKey,
      engine: engineBox,
      sink: sinkBox,
      clock: clockBox,
      ports: portsBox
    )
  }

  private func makeStartedHarness() throws -> HostHarness {
    let harness = try makeHarness()
    let rootRequested = expectation(description: "root requested")
    harness.runtime.onRootRequested = { rootRequested.fulfill() }
    let started = expectation(description: "started")
    harness.host.start { result in
      do {
        _ = try result.get()
      } catch {
        XCTFail("host failed to start: \(error)")
      }
      started.fulfill()
    }
    wait(for: [rootRequested], timeout: 2)
    harness.runtime.completeRoot(.success(RootPresented(surfaceID: "srf:root")))
    wait(for: [started], timeout: 2)
    return harness
  }

  private func runObservationScenario(
    level: ObservationLevel
  ) throws -> (actions: [LifecycleAction], states: [RuntimeState], closeCount: Int) {
    let harness = try makeHarness(conformance: .custom, observation: level)
    let rootRequested = expectation(description: "scenario root")
    harness.runtime.onRootRequested = { rootRequested.fulfill() }
    let started = expectation(description: "scenario started")
    harness.host.start { _ in started.fulfill() }
    wait(for: [rootRequested], timeout: 2)
    harness.runtime.completeRoot(.success(RootPresented(surfaceID: "srf:scenario")))
    wait(for: [started], timeout: 2)

    let controlCaptured = expectation(description: "scenario foreground")
    harness.runtime.onControl = { control in
      if control.action == .enterForeground { controlCaptured.fulfill() }
    }
    let foreground = expectation(description: "scenario foreground result")
    var states: [RuntimeState] = []
    harness.host.requestLifecycle(
      .enterForeground, admission: { _ in },
      completion: { result in
        if case .completed(_, _, let state) = result { states.append(state) }
        foreground.fulfill()
      })
    wait(for: [controlCaptured], timeout: 2)
    let foregroundControl = try XCTUnwrap(harness.runtime.controlSnapshot().last)
    harness.runtime.completeControl(
      requestID: foregroundControl.requestID,
      result: .completed(
        requestID: foregroundControl.requestID,
        action: foregroundControl.action,
        runtimeState: .foreground
      )
    )
    wait(for: [foreground], timeout: 2)

    let destroyCaptured = expectation(description: "scenario destroy")
    harness.runtime.onControl = { control in
      if control.action == .destroyAppRuntime { destroyCaptured.fulfill() }
    }
    let destroyed = expectation(description: "scenario destroyed")
    harness.host.destroy(
      admission: { _ in },
      completion: { result in
        if case .completed(_, _, let state) = result { states.append(state) }
        destroyed.fulfill()
      })
    wait(for: [destroyCaptured], timeout: 2)
    let destroyControl = try XCTUnwrap(harness.runtime.controlSnapshot().last)
    harness.runtime.completeControl(
      requestID: destroyControl.requestID,
      result: .completed(
        requestID: destroyControl.requestID,
        action: destroyControl.action,
        runtimeState: .destroyed
      )
    )
    wait(for: [destroyed], timeout: 2)
    return (
      harness.runtime.controlSnapshot().map(\.action),
      states,
      harness.source.closeCount
    )
  }

  private func failureCode<T>(_ result: Result<T, RuntimeFailure>) -> RuntimeErrorCode? {
    guard case .failure(let error) = result else { return nil }
    return error.code
  }
}
