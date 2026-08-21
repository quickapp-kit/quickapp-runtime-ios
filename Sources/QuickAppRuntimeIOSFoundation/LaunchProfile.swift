import Foundation

public enum RuntimeLaunchProfileDecoder {
  public static func decode(_ data: Data) -> Result<RuntimeLaunchProfile, RuntimeFailure> {
    do {
      let root = try StrictJSON.parse(data)
      let object = try StrictJSON.object(
        root,
        allowed: ["artifact", "entryRoute", "params", "viewport", "traceOutput", "target"],
        required: ["artifact", "params", "viewport", "traceOutput", "target"],
        name: "RuntimeLaunchProfile"
      )
      let viewportObject = try StrictJSON.object(
        object["viewport"] as Any,
        allowed: ["width", "height", "unit"],
        required: ["width", "height", "unit"],
        name: "viewport"
      )
      guard let paramsObject = object["params"] as? [String: Any] else {
        throw StrictJSON.invalid("params must be an object")
      }
      let params = try paramsObject.mapValues(StrictJSON.runtimeValue)
      guard let targetText = try StrictJSON.string(object, "target"),
        let target = RuntimeTarget(rawValue: targetText)
      else {
        throw StrictJSON.invalid("target is invalid")
      }
      let profile = RuntimeLaunchProfile(
        artifact: try StrictJSON.string(object, "artifact")!,
        entryRoute: try StrictJSON.string(object, "entryRoute", required: false),
        params: params,
        viewport: Viewport(
          width: try StrictJSON.double(viewportObject, "width"),
          height: try StrictJSON.double(viewportObject, "height"),
          unit: try StrictJSON.string(viewportObject, "unit")!
        ),
        traceOutput: try StrictJSON.string(object, "traceOutput")!,
        target: target
      )
      try validate(profile)
      return .success(profile)
    } catch let failure as RuntimeFailure {
      return .failure(failure)
    } catch {
      return .failure(StrictJSON.invalid("profile decode failed"))
    }
  }

  public static func validate(_ profile: RuntimeLaunchProfile) throws {
    guard profile.target == .ios else {
      throw StrictJSON.invalid("target must be ios")
    }
    guard profile.artifact.hasPrefix("/"), !profile.artifact.contains("\0") else {
      throw StrictJSON.invalid("artifact must be an absolute resolved path")
    }
    guard profile.viewport.width > 0,
      profile.viewport.height > 0,
      profile.viewport.unit == "logical-px"
    else {
      throw StrictJSON.invalid("viewport is invalid")
    }
    if let route = profile.entryRoute {
      guard route.hasPrefix("/"), !route.contains("//") else {
        throw StrictJSON.invalid("entryRoute must be normalized")
      }
      let segments = route.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
      guard !segments.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else {
        throw StrictJSON.invalid("entryRoute must be normalized")
      }
    }
    guard !profile.traceOutput.isEmpty else {
      throw StrictJSON.invalid("traceOutput is invalid")
    }
  }
}
