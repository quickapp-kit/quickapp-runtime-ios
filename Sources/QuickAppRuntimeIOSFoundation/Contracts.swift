import Foundation

public enum RuntimeErrorCode: String, Equatable, Sendable {
  case abiInvalidArgument = "ABI_INVALID_ARGUMENT"
  case moduleABIUnsupported = "MODULE_ABI_UNSUPPORTED"
  case runtimeProfileIncompatible = "RUNTIME_PROFILE_INCOMPATIBLE"
  case packageNotFound = "PACKAGE_NOT_FOUND"
  case packageIOError = "PACKAGE_IO_ERROR"
  case lifecycleBusy = "LIFECYCLE_BUSY"
  case platformRejected = "PLATFORM_REJECTED"
}

public struct RuntimeFailure: Error, Equatable, Sendable {
  public let code: RuntimeErrorCode
  public let message: String

  public init(code: RuntimeErrorCode, message: String) {
    self.code = code
    self.message = message
  }
}

public indirect enum RuntimeValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case array([RuntimeValue])
  case object([String: RuntimeValue])
}

public struct Viewport: Equatable, Sendable {
  public let width: Double
  public let height: Double
  public let unit: String

  public init(width: Double, height: Double, unit: String = "logical-px") {
    self.width = width
    self.height = height
    self.unit = unit
  }
}

public enum RuntimeTarget: String, Equatable, Sendable {
  case android
  case lvgl
  case ios
}

public struct RuntimeLaunchProfile: Equatable, Sendable {
  public let artifact: String
  public let entryRoute: String?
  public let params: [String: RuntimeValue]
  public let viewport: Viewport
  public let traceOutput: String
  public let target: RuntimeTarget

  public init(
    artifact: String,
    entryRoute: String?,
    params: [String: RuntimeValue],
    viewport: Viewport,
    traceOutput: String,
    target: RuntimeTarget
  ) {
    self.artifact = artifact
    self.entryRoute = entryRoute
    self.params = params
    self.viewport = viewport
    self.traceOutput = traceOutput
    self.target = target
  }
}

public enum LifecycleAction: String, Equatable, Sendable {
  case enterForeground
  case enterBackground
  case destroyAppRuntime
}

public enum RuntimeState: String, Equatable, Sendable {
  case foreground
  case background
  case destroyed
}

public struct RuntimeLifecycleControl: Equatable, Sendable {
  public let requestID: String
  public let action: LifecycleAction

  public init(requestID: String, action: LifecycleAction) {
    self.requestID = requestID
    self.action = action
  }
}

public enum RuntimeLifecycleControlResult: Equatable, Sendable {
  case completed(requestID: String, action: LifecycleAction, runtimeState: RuntimeState)
  case failed(requestID: String, action: LifecycleAction, error: RuntimeFailure)

  public var requestID: String {
    switch self {
    case .completed(let requestID, _, _), .failed(let requestID, _, _): requestID
    }
  }

  public var action: LifecycleAction {
    switch self {
    case .completed(_, let action, _), .failed(_, let action, _): action
    }
  }
}

public struct RootPresented: Equatable, Sendable {
  public let surfaceID: String

  public init(surfaceID: String) {
    self.surfaceID = surfaceID
  }
}

public enum RawSceneSignal: Equatable, Sendable {
  case active
  case background
  case disconnected

  var lifecycleAction: LifecycleAction {
    switch self {
    case .active: .enterForeground
    case .background: .enterBackground
    case .disconnected: .destroyAppRuntime
    }
  }
}

public enum HostControlAdmission: Equatable, Sendable {
  case accepted(requestID: String)
  case deduplicated
  case rejected(RuntimeFailure)
}

public protocol MonotonicClock: AnyObject {
  func nowNanoseconds() -> UInt64
}

public final class SystemMonotonicClock: MonotonicClock {
  public init() {}

  public func nowNanoseconds() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
  }
}

// IOS-S01 owns only the dependency slot. IOS-S02+ supplies the concrete ports.
public protocol RuntimePlatformPortSet: AnyObject {}
