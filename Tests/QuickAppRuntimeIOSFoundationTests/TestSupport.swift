import Foundation

@testable import QuickAppRuntimeIOSFoundation

final class FakeEngineProvider: JSEngineProvider {
  let identity: JSEngineIdentity
  init(identity: JSEngineIdentity) { self.identity = identity }
}

final class RecordingTraceSink: TraceSink {
  private let lock = NSLock()
  private(set) var events: [TraceEvent] = []

  func emit(_ event: TraceEvent) {
    lock.lock()
    events.append(event)
    lock.unlock()
  }
}

final class FakeMonotonicClock: MonotonicClock {
  private(set) var value: UInt64 = 1

  func nowNanoseconds() -> UInt64 {
    defer { value += 1 }
    return value
  }
}

final class FakePlatformPortSet: RuntimePlatformPortSet {}

func validManifest(
  conformance: Conformance = .v1,
  observation: ObservationLevel = .baseline
) -> RuntimeCompositionManifest {
  RuntimeCompositionManifest(
    profileID: "ios-v1-debug",
    conformance: conformance,
    buildMode: .debug,
    observationLevel: observation,
    jsEngine: JSEngineIdentity(
      engineID: "quickjs",
      engineVersion: "1",
      engineABI: "quickapp-kit-js-engine-v1",
      moduleID: "engine.quickjs"
    ),
    linkedModules: [
      LinkedModule(moduleID: "kernel.bridge", category: "kernel"),
      LinkedModule(moduleID: "kernel.render", category: "kernel"),
      LinkedModule(moduleID: "kernel.event", category: "kernel"),
      LinkedModule(moduleID: "kernel.lifecycle", category: "kernel"),
      LinkedModule(moduleID: "kernel.runtime-tree", category: "kernel"),
      LinkedModule(moduleID: "kernel.transaction", category: "kernel"),
      LinkedModule(moduleID: "runtime.js-framework", category: "runtime"),
      LinkedModule(moduleID: "engine.quickjs", category: "engine"),
    ],
    components: ["View", "Text", "Button"],
    capabilities: ["system.router", "system.prompt", "system.device"],
    binaryBytes: 1
  )
}

func compose(
  manifest: RuntimeCompositionManifest = validManifest(),
  engines: [any JSEngineProvider]? = nil,
  recordingSink: (any TraceSink)? = RecordingTraceSink(),
  monotonicClock: any MonotonicClock = FakeMonotonicClock(),
  platformPorts: any RuntimePlatformPortSet = FakePlatformPortSet()
) -> Result<ComposedRuntime, RuntimeFailure> {
  let selectedEngines = engines ?? [FakeEngineProvider(identity: manifest.jsEngine)]
  return IOSCompositionRoot.compose(
    manifest: manifest,
    selection: CompositionSelection(
      engineProviders: selectedEngines,
      noopTraceSink: NoopTraceSink(),
      recordingTraceSink: recordingSink,
      monotonicClock: monotonicClock,
      platformPorts: platformPorts,
      buildInventory: BuildInventory(
        linkedModuleIDs: manifest.linkedModules.map(\.moduleID),
        binaryBytes: manifest.binaryBytes
      )
    )
  )
}

func validProfile() -> RuntimeLaunchProfile {
  RuntimeLaunchProfile(
    artifact: "/tmp/case-001.rpk",
    entryRoute: "/pages/index",
    params: ["message": .string("hello")],
    viewport: Viewport(width: 390, height: 844),
    traceOutput: "disabled",
    target: .ios
  )
}

extension Result {
  func successValue(file: StaticString = #filePath, line: UInt = #line) throws -> Success {
    switch self {
    case .success(let value): value
    case .failure(let error):
      throw TestFailure("expected success, got \(error)", file: file, line: line)
    }
  }
}

struct TestFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String, file _: StaticString, line _: UInt) { self.description = description }
}
