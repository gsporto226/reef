# reef_multi_window

**Experimental** ([ADR 0013](../../docs/adr/0013-multi-window-is-experimental.md)).
Real platform windows for reef shells (`RealShellPlatform`, `ShellViews`) over
Flutter's windowing API, which is unstable: master channel only, enabled per
run with `FLUTTER_WINDOWING=true`, and missing window placement, z-order and
touch capture. The API here may change without a superseding ADR. Without the
flag, `RealShellPlatform.isSupported` is false and apps run one window.
