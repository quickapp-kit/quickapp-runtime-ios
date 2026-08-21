import CoreFoundation
import Foundation

enum StrictJSON {
  static func object(
    _ value: Any,
    allowed: Set<String>,
    required: Set<String>,
    name: String
  ) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
      throw invalid("\(name) must be an object")
    }
    let keys = Set(object.keys)
    guard keys.isSubset(of: allowed), required.isSubset(of: keys) else {
      throw invalid("\(name) contains unknown or missing fields")
    }
    return object
  }

  static func string(_ object: [String: Any], _ key: String, required: Bool = true) throws
    -> String?
  {
    guard let value = object[key] else {
      if required { throw invalid("\(key) is required") }
      return nil
    }
    guard let string = value as? String, !string.isEmpty else {
      throw invalid("\(key) must be a non-empty string")
    }
    return string
  }

  static func double(_ object: [String: Any], _ key: String) throws -> Double {
    guard let number = object[key] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else {
      throw invalid("\(key) must be a number")
    }
    let value = number.doubleValue
    guard value.isFinite else { throw invalid("\(key) must be finite") }
    return value
  }

  static func uint64(_ object: [String: Any], _ key: String) throws -> UInt64 {
    guard let number = object[key] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.rounded() == number.doubleValue,
      number.doubleValue >= 0,
      number.doubleValue <= Double(UInt64.max)
    else {
      throw invalid("\(key) must be a non-negative integer")
    }
    return number.uint64Value
  }

  static func array(_ object: [String: Any], _ key: String) throws -> [Any] {
    guard let array = object[key] as? [Any] else {
      throw invalid("\(key) must be an array")
    }
    return array
  }

  static func stringArray(_ object: [String: Any], _ key: String) throws -> [String] {
    let values = try array(object, key)
    let strings = try values.map { value -> String in
      guard let string = value as? String, !string.isEmpty else {
        throw invalid("\(key) must contain non-empty strings")
      }
      return string
    }
    guard Set(strings).count == strings.count else {
      throw invalid("\(key) contains duplicates")
    }
    return strings
  }

  static func parse(_ data: Data) throws -> Any {
    do {
      return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw invalid("invalid JSON")
    }
  }

  static func runtimeValue(_ value: Any) throws -> RuntimeValue {
    if value is NSNull { return .null }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .bool(number.boolValue)
      }
      let double = number.doubleValue
      guard double.isFinite else { throw invalid("RuntimeValue number must be finite") }
      if double.rounded() == double,
        double >= Double(Int64.min),
        double <= Double(Int64.max)
      {
        return .integer(number.int64Value)
      }
      return .number(double)
    }
    if let string = value as? String { return .string(string) }
    if let array = value as? [Any] { return .array(try array.map(runtimeValue)) }
    if let object = value as? [String: Any] {
      return .object(try object.mapValues(runtimeValue))
    }
    throw invalid("unsupported RuntimeValue")
  }

  static func invalid(_ message: String) -> RuntimeFailure {
    RuntimeFailure(code: .abiInvalidArgument, message: message)
  }
}
