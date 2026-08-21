import Foundation

public typealias RootStartCompletion = (Result<RootPresented, RuntimeFailure>) -> Void
public typealias LifecycleCompletion = (RuntimeLifecycleControlResult) -> Void

public protocol CoreAppRuntime: AnyObject {
  func startRoot(profile: RuntimeLaunchProfile, completion: @escaping RootStartCompletion)
  func controlLifecycle(
    _ control: RuntimeLifecycleControl, completion: @escaping LifecycleCompletion)
}

public struct AppRuntimeCreateRequest {
  public let manifest: RuntimeCompositionManifest
  public let packageSource: any PackageSource
  public let engineProvider: any JSEngineProvider
  public let traceSink: any TraceSink
  public let monotonicClock: any MonotonicClock
  public let platformPorts: any RuntimePlatformPortSet

  public init(
    manifest: RuntimeCompositionManifest,
    packageSource: any PackageSource,
    engineProvider: any JSEngineProvider,
    traceSink: any TraceSink,
    monotonicClock: any MonotonicClock,
    platformPorts: any RuntimePlatformPortSet
  ) {
    self.manifest = manifest
    self.packageSource = packageSource
    self.engineProvider = engineProvider
    self.traceSink = traceSink
    self.monotonicClock = monotonicClock
    self.platformPorts = platformPorts
  }
}

public protocol CoreAppRuntimeFactory: AnyObject {
  // AppRuntimeId is intentionally absent. Core owns that identity.
  func create(
    request: AppRuntimeCreateRequest,
    completion: @escaping (Result<any CoreAppRuntime, RuntimeFailure>) -> Void
  )
}

public final class RequestIDGenerator {
  private let lock = NSLock()
  private var nextValue: UInt64 = 1
  private var namespace = UUID().uuidString.lowercased()
  private let prefix: String

  public init(prefix: String = "req:ios") {
    self.prefix = prefix
  }

  public func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    let value = nextValue
    if nextValue == UInt64.max {
      namespace = UUID().uuidString.lowercased()
      nextValue = 1
    } else {
      nextValue += 1
    }
    return "\(prefix):\(namespace):\(value)"
  }
}

public enum IOSRuntimeHostState: String, Equatable, Sendable {
  case idle
  case starting
  case running
  case destroying
  case destroyed
  case failed
}

public final class IOSRuntimeHost {
  private struct PendingControl {
    let action: LifecycleAction
    let completion: LifecycleCompletion
  }

  private struct DeferredDestroy {
    let result: RuntimeLifecycleControlResult
    let completion: LifecycleCompletion
  }

  private let profile: RuntimeLaunchProfile
  private let manifest: RuntimeCompositionManifest
  private let hostQueue: DispatchQueue
  private let queueKey = DispatchSpecificKey<UInt8>()
  private let requestIDs: RequestIDGenerator

  private var composition: ComposedRuntime?
  private var packageSource: (any PackageSource)?
  private var factory: (any CoreAppRuntimeFactory)?
  private var runtime: (any CoreAppRuntime)?
  private var currentState: IOSRuntimeHostState = .idle
  private var committedRuntimeState: RuntimeState?
  private var lastRawSceneSignal: RawSceneSignal?
  private var pendingControls: [String: PendingControl] = [:]
  private var deferredDestroy: DeferredDestroy?

  public static func create(
    profile: RuntimeLaunchProfile,
    composition: ComposedRuntime,
    packageSourceFactory: () -> Result<any PackageSource, RuntimeFailure>,
    factory: any CoreAppRuntimeFactory,
    hostQueue: DispatchQueue = DispatchQueue(label: "quickapp.runtime.ios.host"),
    requestIDs: RequestIDGenerator = RequestIDGenerator()
  ) -> Result<IOSRuntimeHost, RuntimeFailure> {
    do {
      try RuntimeLaunchProfileDecoder.validate(profile)
      try RuntimeCompositionValidator.validate(composition.manifest)
      let packageSource = try packageSourceFactory().get()
      return .success(
        IOSRuntimeHost(
          profile: profile,
          composition: composition,
          packageSource: packageSource,
          factory: factory,
          hostQueue: hostQueue,
          requestIDs: requestIDs
        ))
    } catch let failure as RuntimeFailure {
      return .failure(failure)
    } catch {
      return .failure(
        RuntimeFailure(code: .abiInvalidArgument, message: "runtime host preflight failed"))
    }
  }

  private init(
    profile: RuntimeLaunchProfile,
    composition: ComposedRuntime,
    packageSource: any PackageSource,
    factory: any CoreAppRuntimeFactory,
    hostQueue: DispatchQueue,
    requestIDs: RequestIDGenerator
  ) {
    self.profile = profile
    manifest = composition.manifest
    self.composition = composition
    self.packageSource = packageSource
    self.factory = factory
    self.hostQueue = hostQueue
    self.requestIDs = requestIDs
    hostQueue.setSpecific(key: queueKey, value: 1)
  }

  public var state: IOSRuntimeHostState {
    onHostQueue { currentState }
  }

  public var runtimeState: RuntimeState? {
    onHostQueue { committedRuntimeState }
  }

  public func describeComposition() -> RuntimeCompositionManifest {
    manifest
  }

  public func start(completion: @escaping RootStartCompletion) {
    hostQueue.async { [self] in
      guard currentState == .idle,
        let composition,
        let packageSource,
        let factory
      else {
        completion(
          .failure(RuntimeFailure(code: .platformRejected, message: "runtime host cannot start")))
        return
      }
      currentState = .starting
      let request = AppRuntimeCreateRequest(
        manifest: composition.manifest,
        packageSource: packageSource,
        engineProvider: composition.engineProvider,
        traceSink: composition.traceSink,
        monotonicClock: composition.monotonicClock,
        platformPorts: composition.platformPorts
      )
      factory.create(request: request) { [self] result in
        hostQueue.async { [self] in
          handleRuntimeCreated(result, startCompletion: completion)
        }
      }
    }
  }

  public func requestLifecycle(
    _ action: LifecycleAction,
    admission: @escaping (HostControlAdmission) -> Void,
    completion: @escaping LifecycleCompletion
  ) {
    hostQueue.async { [self] in
      acceptLifecycle(action, admission: admission, completion: completion)
    }
  }

  public func handleRawSceneSignal(
    _ signal: RawSceneSignal,
    admission: @escaping (HostControlAdmission) -> Void,
    completion: @escaping LifecycleCompletion
  ) {
    hostQueue.async { [self] in
      guard currentState == .running else {
        admission(.rejected(hostAdmissionFailure()))
        return
      }
      if lastRawSceneSignal == signal {
        admission(.deduplicated)
        return
      }
      lastRawSceneSignal = signal
      acceptLifecycle(signal.lifecycleAction, admission: admission, completion: completion)
    }
  }

  public func destroy(
    admission: @escaping (HostControlAdmission) -> Void,
    completion: @escaping LifecycleCompletion
  ) {
    requestLifecycle(.destroyAppRuntime, admission: admission, completion: completion)
  }

  private func handleRuntimeCreated(
    _ result: Result<any CoreAppRuntime, RuntimeFailure>,
    startCompletion: @escaping RootStartCompletion
  ) {
    guard currentState == .starting else { return }
    switch result {
    case .failure(let error):
      currentState = .failed
      finishLocalTeardown()
      startCompletion(.failure(error))
    case .success(let runtime):
      self.runtime = runtime
      runtime.startRoot(profile: profile) { [self] result in
        hostQueue.async { [self] in
          handleRootResult(result, startCompletion: startCompletion)
        }
      }
    }
  }

  private func handleRootResult(
    _ result: Result<RootPresented, RuntimeFailure>,
    startCompletion: @escaping RootStartCompletion
  ) {
    guard currentState == .starting else { return }
    switch result {
    case .success(let presented):
      currentState = .running
      startCompletion(.success(presented))
    case .failure(let error):
      currentState = .destroying
      guard let runtime else {
        finishLocalTeardown()
        startCompletion(.failure(error))
        return
      }
      let control = RuntimeLifecycleControl(
        requestID: requestIDs.next(),
        action: .destroyAppRuntime
      )
      runtime.controlLifecycle(control) { [self] _ in
        hostQueue.async { [self] in
          guard currentState == .destroying else { return }
          finishLocalTeardown()
          startCompletion(.failure(error))
        }
      }
    }
  }

  private func acceptLifecycle(
    _ action: LifecycleAction,
    admission: @escaping (HostControlAdmission) -> Void,
    completion: @escaping LifecycleCompletion
  ) {
    guard currentState == .running, let runtime else {
      admission(.rejected(hostAdmissionFailure()))
      return
    }
    let requestID = requestIDs.next()
    let control = RuntimeLifecycleControl(requestID: requestID, action: action)
    pendingControls[requestID] = PendingControl(action: action, completion: completion)
    if action == .destroyAppRuntime {
      currentState = .destroying
    }
    admission(.accepted(requestID: requestID))
    runtime.controlLifecycle(control) { [self] result in
      hostQueue.async { [self] in
        handleLifecycleResult(result, expected: control)
      }
    }
  }

  private func handleLifecycleResult(
    _ result: RuntimeLifecycleControlResult,
    expected control: RuntimeLifecycleControl
  ) {
    guard let pending = pendingControls.removeValue(forKey: control.requestID) else {
      return
    }
    let delivered: RuntimeLifecycleControlResult
    if result.requestID == control.requestID, result.action == control.action {
      delivered = result
    } else {
      delivered = .failed(
        requestID: control.requestID,
        action: control.action,
        error: RuntimeFailure(
          code: .abiInvalidArgument, message: "lifecycle result correlation mismatch")
      )
    }

    switch delivered {
    case .completed(_, let action, let runtimeState):
      committedRuntimeState = runtimeState
      if action == .destroyAppRuntime {
        deferredDestroy = DeferredDestroy(result: delivered, completion: pending.completion)
      } else {
        pending.completion(delivered)
      }
    case .failed(_, let action, _):
      if action == .destroyAppRuntime {
        deferredDestroy = DeferredDestroy(result: delivered, completion: pending.completion)
      } else {
        pending.completion(delivered)
      }
    }
    finishDestroyWhenDrained()
  }

  private func finishDestroyWhenDrained() {
    guard pendingControls.isEmpty, let deferredDestroy else { return }
    self.deferredDestroy = nil
    finishLocalTeardown()
    deferredDestroy.completion(deferredDestroy.result)
  }

  private func finishLocalTeardown() {
    let source = packageSource
    packageSource = nil
    runtime = nil
    factory = nil
    composition = nil
    pendingControls.removeAll()
    lastRawSceneSignal = nil
    currentState = .destroyed
    source?.close()
  }

  private func hostAdmissionFailure() -> RuntimeFailure {
    let code: RuntimeErrorCode = currentState == .destroying ? .lifecycleBusy : .platformRejected
    return RuntimeFailure(code: code, message: "runtime host is not accepting lifecycle controls")
  }

  private func onHostQueue<T>(_ body: () -> T) -> T {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      return body()
    }
    return hostQueue.sync(execute: body)
  }
}
