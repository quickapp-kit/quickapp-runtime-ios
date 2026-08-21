import Foundation
import XCTest

@testable import QuickAppRuntimeIOSFoundation

final class CompositionTests: XCTestCase {
  func testStrictProfileDecoderAndPreflight() throws {
    let data = Data(
      #"""
      {
        "artifact":"/tmp/case-001.rpk",
        "entryRoute":"/pages/index",
        "params":{"message":"hello","count":1},
        "viewport":{"width":390,"height":844,"unit":"logical-px"},
        "traceOutput":"disabled",
        "target":"ios"
      }
      """#.utf8)
    let profile = try RuntimeLaunchProfileDecoder.decode(data).successValue()
    XCTAssertEqual(profile.target, .ios)
    XCTAssertEqual(profile.entryRoute, "/pages/index")
    XCTAssertEqual(profile.params["count"], .integer(1))

    let unknown = Data(
      #"""
      {
        "artifact":"/tmp/a.rpk","params":{},
        "viewport":{"width":1,"height":1,"unit":"logical-px"},
        "traceOutput":"disabled","target":"ios","private":true
      }
      """#.utf8)
    XCTAssertThrowsError(try RuntimeLaunchProfileDecoder.decode(unknown).get())

    var wrongTarget = validProfile()
    wrongTarget = RuntimeLaunchProfile(
      artifact: wrongTarget.artifact,
      entryRoute: wrongTarget.entryRoute,
      params: wrongTarget.params,
      viewport: wrongTarget.viewport,
      traceOutput: wrongTarget.traceOutput,
      target: .android
    )
    XCTAssertThrowsError(try RuntimeLaunchProfileDecoder.validate(wrongTarget))
  }

  func testManifestFixtureAndSingleEngine() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "runtime-composition-ios-v1-debug",
        withExtension: "json"
      ))
    let manifest = try RuntimeCompositionManifestDecoder.decode(Data(contentsOf: url))
      .successValue()
    XCTAssertEqual(manifest.linkedModules.count, 8)
    XCTAssertEqual(try compose(manifest: manifest).successValue().traceSinkSelection, .recording)

    let noEngines = compose(manifest: manifest, engines: [])
    XCTAssertEqual(failureCode(noEngines), .runtimeProfileIncompatible)
    let engine = FakeEngineProvider(identity: manifest.jsEngine)
    XCTAssertEqual(
      failureCode(compose(manifest: manifest, engines: [engine, engine])),
      .runtimeProfileIncompatible)

    let wrong = JSEngineIdentity(
      engineID: "quickjs",
      engineVersion: "1",
      engineABI: "wrong",
      moduleID: "engine.quickjs"
    )
    XCTAssertEqual(
      failureCode(compose(manifest: manifest, engines: [FakeEngineProvider(identity: wrong)])),
      .moduleABIUnsupported
    )
  }

  func testObservationMatrix() throws {
    for conformance in [Conformance.v1, .custom] {
      for level in [ObservationLevel.baseline, .diagnostic] {
        let value = try compose(
          manifest: validManifest(
            conformance: conformance,
            observation: level
          )
        ).successValue()
        XCTAssertEqual(value.traceSinkSelection, .recording)
      }
    }
    let customOff = try compose(
      manifest: validManifest(
        conformance: .custom,
        observation: .off
      )
    ).successValue()
    XCTAssertEqual(customOff.traceSinkSelection, .noop)

    let v1Off = compose(manifest: validManifest(conformance: .v1, observation: .off))
    XCTAssertEqual(failureCode(v1Off), .runtimeProfileIncompatible)

    let missingRecording = compose(
      manifest: validManifest(conformance: .custom, observation: .baseline),
      recordingSink: nil
    )
    XCTAssertEqual(failureCode(missingRecording), .runtimeProfileIncompatible)
  }

  func testBuildInventoryMustMatchManifest() {
    let manifest = validManifest()
    let engine = FakeEngineProvider(identity: manifest.jsEngine)
    let selection = CompositionSelection(
      engineProviders: [engine],
      noopTraceSink: NoopTraceSink(),
      recordingTraceSink: RecordingTraceSink(),
      monotonicClock: FakeMonotonicClock(),
      platformPorts: FakePlatformPortSet(),
      buildInventory: BuildInventory(
        linkedModuleIDs: Array(manifest.linkedModules.dropLast()).map(\.moduleID),
        binaryBytes: manifest.binaryBytes
      )
    )
    XCTAssertEqual(
      failureCode(IOSCompositionRoot.compose(manifest: manifest, selection: selection)),
      .runtimeProfileIncompatible
    )
  }

  func testCompositionCarriesImmutableRuntimeDependencies() throws {
    let manifest = validManifest()
    let engine = FakeEngineProvider(identity: manifest.jsEngine)
    let sink = RecordingTraceSink()
    let clock = FakeMonotonicClock()
    let ports = FakePlatformPortSet()
    let value = try compose(
      manifest: manifest,
      engines: [engine],
      recordingSink: sink,
      monotonicClock: clock,
      platformPorts: ports
    ).successValue()

    XCTAssertTrue(value.engineProvider === engine)
    XCTAssertTrue(value.traceSink === sink)
    XCTAssertTrue(value.monotonicClock === clock)
    XCTAssertTrue(value.platformPorts === ports)
    XCTAssertEqual(value.manifest, manifest)
  }

  private func failureCode<T>(_ result: Result<T, RuntimeFailure>) -> RuntimeErrorCode? {
    guard case .failure(let error) = result else { return nil }
    return error.code
  }
}
