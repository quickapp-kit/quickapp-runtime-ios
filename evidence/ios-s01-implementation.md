# IOS-S01 Implementation Evidence

## Conclusion

IOS-S01 is implemented and verified as an isolated, UIKit-free Host Foundation. It covers strict launch/composition preflight before PackageSource creation, one Engine Provider, immutable clock/platform-port dependency injection, the frozen observation matrix, immutable PackageSource reads, Root-presented startup, raw Scene admission, accepted lifecycle control correlation, and deterministic teardown.

This is parallel foundation preparation, not early iOS platform implementation. IOS-S02 and UIKit Surface/Mount/Input remain blocked until M3 and cannot start before M2 Android completion.

The final App/native target link map is intentionally pending IOS-S08/IOS-S09. IOS-S01 verifies that Composition Root rejects a supplied inventory that differs from its Manifest; it does not fabricate proof that shared Core, JS Framework, and QuickJS are already linked into an iOS product.

## Reproduce

```sh
./tools/verify-ios-s01.sh
```

## Results

| Check | Result |
|---|---|
| Debug contract tests | 19 passed, 0 failed |
| Release build | Passed |
| AddressSanitizer | 19 passed, 0 failed |
| ThreadSanitizer | 19 passed, 0 failed |
| iOS Simulator target compile | Passed with `arm64-apple-ios15.0-simulator` and Xcode iPhoneSimulator SDK |
| Swift formatter lint | Passed with 0 warnings |
| IOS-S01 boundary scan | Passed; no UIKit/SwiftUI, Surface/Mount/Input types in Foundation Sources |

## Contract Evidence

| Area | Evidence |
|---|---|
| Profile | Strict fields, iOS target, absolute artifact, normalized route, RuntimeValue and logical viewport |
| Composition | Fixed Kernel modules, one JS Framework declaration, exactly one matching Engine, exact supplied inventory and byte count, immutable clock/platform-port slots |
| Observation | `v1 baseline/diagnostic -> Recording`; `custom off -> Noop`; `custom baseline/diagnostic -> Recording`; `v1 off` rejected |
| PackageSource | One random-read contract covers Memory, Bundle and fixed open file handle; short/zero/invalid reads, close race and Core queue completion are covered |
| Startup | Profile/Manifest preflight precedes PackageSource creation; Fake Core creation does not complete start; only Root `presented` does; failure runs Core cleanup before local release |
| Scene/control | Raw duplicate produces no RequestId; every accepted control enters Core; ID/action complete once; `LIFECYCLE_BUSY` is unchanged |
| Teardown | Destroy success/failure closes PackageSource; Engine/Sink/Clock/PortSet/Source/Fake Core/Factory weak references all reach zero; repeated destroy is rejected before a new RequestId |
| Threading | Host state and callbacks use the Host queue; package work uses I/O queue; read completion uses Core queue |

## Task Status

| Task | Status |
|---|---|
| T01-T03 | Complete |
| T04 | Isolated inventory rejection complete; real App/native link map pending IOS-S08/IOS-S09 |
| T05-T11 | Complete |
| T12 | Complete for IOS-S01 isolated implementation |
