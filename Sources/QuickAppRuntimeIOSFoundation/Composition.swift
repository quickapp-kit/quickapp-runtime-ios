import Foundation

public enum Conformance: String, Equatable, Sendable {
  case v1
  case custom
}

public enum RuntimeBuildMode: String, Equatable, Sendable {
  case debug
  case release
}

public enum ObservationLevel: String, Equatable, Sendable {
  case off
  case baseline
  case diagnostic
}

public struct JSEngineIdentity: Equatable, Sendable {
  public let engineID: String
  public let engineVersion: String
  public let engineABI: String
  public let moduleID: String

  public init(engineID: String, engineVersion: String, engineABI: String, moduleID: String) {
    self.engineID = engineID
    self.engineVersion = engineVersion
    self.engineABI = engineABI
    self.moduleID = moduleID
  }
}

public struct LinkedModule: Equatable, Sendable {
  public let moduleID: String
  public let category: String
  public let version: String?

  public init(moduleID: String, category: String, version: String? = nil) {
    self.moduleID = moduleID
    self.category = category
    self.version = version
  }
}

public struct RuntimeCompositionManifest: Equatable, Sendable {
  public let profileID: String
  public let target: String
  public let runtimeABI: String
  public let conformance: Conformance
  public let buildMode: RuntimeBuildMode
  public let observationLevel: ObservationLevel
  public let jsEngine: JSEngineIdentity
  public let linkedModules: [LinkedModule]
  public let components: [String]
  public let capabilities: [String]
  public let binaryBytes: UInt64
  public let staticMemoryBytes: UInt64?

  public init(
    profileID: String,
    target: String = "ios",
    runtimeABI: String = "quickapp-kit-runtime-v1",
    conformance: Conformance,
    buildMode: RuntimeBuildMode,
    observationLevel: ObservationLevel,
    jsEngine: JSEngineIdentity,
    linkedModules: [LinkedModule],
    components: [String],
    capabilities: [String],
    binaryBytes: UInt64,
    staticMemoryBytes: UInt64? = nil
  ) {
    self.profileID = profileID
    self.target = target
    self.runtimeABI = runtimeABI
    self.conformance = conformance
    self.buildMode = buildMode
    self.observationLevel = observationLevel
    self.jsEngine = jsEngine
    self.linkedModules = linkedModules
    self.components = components
    self.capabilities = capabilities
    self.binaryBytes = binaryBytes
    self.staticMemoryBytes = staticMemoryBytes
  }
}

public enum RuntimeCompositionManifestDecoder {
  public static func decode(_ data: Data) -> Result<RuntimeCompositionManifest, RuntimeFailure> {
    do {
      let root = try StrictJSON.parse(data)
      let object = try StrictJSON.object(
        root,
        allowed: [
          "schemaVersion", "kind", "profileId", "target", "runtimeAbi", "conformance",
          "buildMode", "observationLevel", "jsEngine", "linkedModules", "components",
          "capabilities", "binaryBytes", "staticMemoryBytes",
        ],
        required: [
          "schemaVersion", "kind", "profileId", "target", "runtimeAbi", "conformance",
          "buildMode", "observationLevel", "jsEngine", "linkedModules", "components",
          "capabilities", "binaryBytes",
        ],
        name: "RuntimeCompositionManifest"
      )
      guard try StrictJSON.uint64(object, "schemaVersion") == 1,
        try StrictJSON.string(object, "kind") == "runtimeCompositionManifest"
      else {
        throw StrictJSON.invalid("composition schema header is invalid")
      }
      let engineObject = try StrictJSON.object(
        object["jsEngine"] as Any,
        allowed: ["engineId", "engineVersion", "engineAbi", "moduleId"],
        required: ["engineId", "engineVersion", "engineAbi", "moduleId"],
        name: "jsEngine"
      )
      let moduleValues = try StrictJSON.array(object, "linkedModules")
      let modules = try moduleValues.map { value -> LinkedModule in
        let module = try StrictJSON.object(
          value,
          allowed: ["moduleId", "category", "version"],
          required: ["moduleId", "category"],
          name: "linkedModule"
        )
        return LinkedModule(
          moduleID: try StrictJSON.string(module, "moduleId")!,
          category: try StrictJSON.string(module, "category")!,
          version: try StrictJSON.string(module, "version", required: false)
        )
      }
      guard let conformanceText = try StrictJSON.string(object, "conformance"),
        let conformance = Conformance(rawValue: conformanceText),
        let buildModeText = try StrictJSON.string(object, "buildMode"),
        let buildMode = RuntimeBuildMode(rawValue: buildModeText),
        let observationText = try StrictJSON.string(object, "observationLevel"),
        let observation = ObservationLevel(rawValue: observationText)
      else {
        throw StrictJSON.invalid("composition enum is invalid")
      }
      let manifest = RuntimeCompositionManifest(
        profileID: try StrictJSON.string(object, "profileId")!,
        target: try StrictJSON.string(object, "target")!,
        runtimeABI: try StrictJSON.string(object, "runtimeAbi")!,
        conformance: conformance,
        buildMode: buildMode,
        observationLevel: observation,
        jsEngine: JSEngineIdentity(
          engineID: try StrictJSON.string(engineObject, "engineId")!,
          engineVersion: try StrictJSON.string(engineObject, "engineVersion")!,
          engineABI: try StrictJSON.string(engineObject, "engineAbi")!,
          moduleID: try StrictJSON.string(engineObject, "moduleId")!
        ),
        linkedModules: modules,
        components: try StrictJSON.stringArray(object, "components"),
        capabilities: try StrictJSON.stringArray(object, "capabilities"),
        binaryBytes: try StrictJSON.uint64(object, "binaryBytes"),
        staticMemoryBytes: object["staticMemoryBytes"] == nil
          ? nil
          : try StrictJSON.uint64(object, "staticMemoryBytes")
      )
      try RuntimeCompositionValidator.validate(manifest)
      return .success(manifest)
    } catch let failure as RuntimeFailure {
      return .failure(failure)
    } catch {
      return .failure(StrictJSON.invalid("composition decode failed"))
    }
  }
}

public enum RuntimeCompositionValidator {
  private static let fixedKernelModules: [String: String] = [
    "kernel.bridge": "kernel",
    "kernel.render": "kernel",
    "kernel.event": "kernel",
    "kernel.lifecycle": "kernel",
    "kernel.runtime-tree": "kernel",
    "kernel.transaction": "kernel",
    "runtime.js-framework": "runtime",
  ]

  public static func validate(_ manifest: RuntimeCompositionManifest) throws {
    guard manifest.target == "ios",
      manifest.runtimeABI == "quickapp-kit-runtime-v1",
      manifest.binaryBytes > 0,
      manifest.profileID.range(of: "^[a-z0-9]+(?:[.-][a-z0-9]+)*$", options: .regularExpression)
        != nil
    else {
      throw StrictJSON.invalid("composition header is invalid")
    }
    guard manifest.jsEngine.engineABI == "quickapp-kit-js-engine-v1",
      manifest.jsEngine.moduleID.hasPrefix("engine."),
      !manifest.jsEngine.engineID.isEmpty,
      !manifest.jsEngine.engineVersion.isEmpty
    else {
      throw RuntimeFailure(code: .moduleABIUnsupported, message: "JS engine identity is invalid")
    }
    let moduleIDs = manifest.linkedModules.map(\.moduleID)
    guard Set(moduleIDs).count == moduleIDs.count else {
      throw StrictJSON.invalid("linked module IDs must be unique")
    }
    let categories = Dictionary(
      uniqueKeysWithValues: manifest.linkedModules.map { ($0.moduleID, $0.category) })
    for (moduleID, category) in fixedKernelModules where categories[moduleID] != category {
      throw RuntimeFailure(
        code: .runtimeProfileIncompatible,
        message: "required module is missing or miscategorized: \(moduleID)")
    }
    let engineModules = manifest.linkedModules.filter { $0.category == "engine" }
    guard engineModules.count == 1, engineModules[0].moduleID == manifest.jsEngine.moduleID else {
      throw RuntimeFailure(
        code: .runtimeProfileIncompatible, message: "exactly one matching engine module is required"
      )
    }
    guard Set(manifest.components).count == manifest.components.count,
      Set(manifest.capabilities).count == manifest.capabilities.count
    else {
      throw StrictJSON.invalid("components and capabilities must be unique")
    }
    if manifest.conformance == .v1 {
      guard manifest.observationLevel != .off,
        Set(["View", "Text", "Button"]).isSubset(of: Set(manifest.components)),
        Set(["system.router", "system.prompt", "system.device"]).isSubset(
          of: Set(manifest.capabilities))
      else {
        throw RuntimeFailure(
          code: .runtimeProfileIncompatible, message: "v1 conformance set is incomplete")
      }
    }
  }
}

public struct TraceEvent: Equatable, Sendable {
  public let markerName: String
  public let timestampNS: UInt64

  public init(markerName: String, timestampNS: UInt64) {
    self.markerName = markerName
    self.timestampNS = timestampNS
  }
}

public protocol TraceSink: AnyObject {
  func emit(_ event: TraceEvent)
}

public final class NoopTraceSink: TraceSink {
  public init() {}
  public func emit(_: TraceEvent) {}
}

public protocol JSEngineProvider: AnyObject {
  var identity: JSEngineIdentity { get }
}

public struct BuildInventory: Equatable, Sendable {
  public let linkedModuleIDs: [String]
  public let binaryBytes: UInt64

  public init(linkedModuleIDs: [String], binaryBytes: UInt64) {
    self.linkedModuleIDs = linkedModuleIDs
    self.binaryBytes = binaryBytes
  }
}

public struct CompositionSelection {
  public let engineProviders: [any JSEngineProvider]
  public let noopTraceSink: any TraceSink
  public let recordingTraceSink: (any TraceSink)?
  public let monotonicClock: any MonotonicClock
  public let platformPorts: any RuntimePlatformPortSet
  public let buildInventory: BuildInventory

  public init(
    engineProviders: [any JSEngineProvider],
    noopTraceSink: any TraceSink,
    recordingTraceSink: (any TraceSink)?,
    monotonicClock: any MonotonicClock,
    platformPorts: any RuntimePlatformPortSet,
    buildInventory: BuildInventory
  ) {
    self.engineProviders = engineProviders
    self.noopTraceSink = noopTraceSink
    self.recordingTraceSink = recordingTraceSink
    self.monotonicClock = monotonicClock
    self.platformPorts = platformPorts
    self.buildInventory = buildInventory
  }
}

public enum TraceSinkSelection: Equatable, Sendable {
  case noop
  case recording
}

public struct ComposedRuntime {
  public let manifest: RuntimeCompositionManifest
  public let engineProvider: any JSEngineProvider
  public let traceSink: any TraceSink
  public let traceSinkSelection: TraceSinkSelection
  public let monotonicClock: any MonotonicClock
  public let platformPorts: any RuntimePlatformPortSet
}

public enum IOSCompositionRoot {
  public static func compose(
    manifest: RuntimeCompositionManifest,
    selection: CompositionSelection
  ) -> Result<ComposedRuntime, RuntimeFailure> {
    do {
      try RuntimeCompositionValidator.validate(manifest)
      guard selection.engineProviders.count == 1 else {
        throw RuntimeFailure(
          code: .runtimeProfileIncompatible, message: "exactly one JS engine provider is required")
      }
      let engine = selection.engineProviders[0]
      guard engine.identity == manifest.jsEngine else {
        let code: RuntimeErrorCode =
          engine.identity.engineABI == manifest.jsEngine.engineABI
          ? .runtimeProfileIncompatible
          : .moduleABIUnsupported
        throw RuntimeFailure(code: code, message: "selected engine does not match manifest")
      }
      let manifestModules = manifest.linkedModules.map(\.moduleID)
      guard Set(manifestModules) == Set(selection.buildInventory.linkedModuleIDs),
        manifestModules.count == selection.buildInventory.linkedModuleIDs.count,
        manifest.binaryBytes == selection.buildInventory.binaryBytes
      else {
        throw RuntimeFailure(
          code: .runtimeProfileIncompatible, message: "manifest and build inventory differ")
      }

      let sink: any TraceSink
      let sinkSelection: TraceSinkSelection
      switch (manifest.conformance, manifest.observationLevel) {
      case (.v1, .off):
        throw RuntimeFailure(
          code: .runtimeProfileIncompatible, message: "v1 cannot disable observation")
      case (.custom, .off):
        sink = selection.noopTraceSink
        sinkSelection = .noop
      case (_, .baseline), (_, .diagnostic):
        guard let recording = selection.recordingTraceSink else {
          throw RuntimeFailure(
            code: .runtimeProfileIncompatible, message: "recording TraceSink is required")
        }
        sink = recording
        sinkSelection = .recording
      }
      return .success(
        ComposedRuntime(
          manifest: manifest,
          engineProvider: engine,
          traceSink: sink,
          traceSinkSelection: sinkSelection,
          monotonicClock: selection.monotonicClock,
          platformPorts: selection.platformPorts
        ))
    } catch let failure as RuntimeFailure {
      return .failure(failure)
    } catch {
      return .failure(
        RuntimeFailure(code: .runtimeProfileIncompatible, message: "composition failed"))
    }
  }
}
