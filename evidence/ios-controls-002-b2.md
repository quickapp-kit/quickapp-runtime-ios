# iOS B2 Slider + Picker Evidence

## Conclusion

iOS B2 is implemented against the real `controls-002.rpk`. Slider and text Picker use the existing MountTransaction, Runtime Tree, Event Router, JS handler and Lifecycle paths. No shared Core, JS, Toolkit, Contract or Example files were changed.

## Input

- RPK: `/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/controls-002/dist/controls-002.rpk`
- SHA-256: `b738c890107d54f82ecf2c3f949c5df3688b6760e45d326b08f4c23de53d297a`
- Bundle copy has the same SHA-256.

## Platform Mapping

- Slider -> `UISlider`; `min=0`, `max=100`, `step=5`, initial `value=40`.
- Slider user values are quantized to the configured step and emit `change` with `value` and `isFromUser=true`.
- Picker -> page `UIButton` plus temporary `UIPickerView` overlay.
- Picker range `安静|标准|性能`, initial `selected=1`.
- Cancel closes the overlay without `change`; Confirm emits `change` with `selected` and `value`.
- The temporary overlay is platform UI only. It is not inserted into the Core Runtime Tree and is removed during Surface teardown.

## Verification

Host probes against the real RPK:

```text
ios.event.change.queued surface=srf:1 node=node:4 accepted=1
ios.event.change.dispatched surface=srf:1 node=node:4 accepted=1
ios.js.event.executed surface=srf:1 handler=hdl:1 accepted=1
ios.event.change.queued surface=srf:1 node=node:7 accepted=1
ios.event.change.dispatched surface=srf:1 node=node:7 accepted=1
ios.js.event.executed surface=srf:1 handler=hdl:2 accepted=1
ios.probe.runtime.stopped surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0 coreQueue=0
```

Real Simulator evidence:

- Home: `/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/evidence/screenshots/ios-controls-002-home-2026-08-25.png`
- Picker open: `/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/evidence/screenshots/ios-controls-002-picker-open-2026-08-25.png`
- Logs: `evidence/showcase-logs/ios-controls-002-slider-host-probe.log`, `evidence/showcase-logs/ios-controls-002-picker-host-probe.log`

The iOS Accessibility tree reported Slider value `40`, then `55` after platform value update. The Picker panel exposed Cancel and Confirm and rendered all three text options. The controls-002 package is single-page and has no navigation handler; push/back and repeated page entry are not applicable to this input package.

Builds:

```text
cmake --build build-ios-ninja --target quickapp_ios_simulator -j 4
cmake --build build-host --target quickapp_ios_spine_probe -j 4
```

Both passed.
