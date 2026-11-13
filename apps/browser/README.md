# browser

The Browser integration app (`docs/integration-apps.md`). Windows only.

Building needs `nuget.exe` on `PATH` (flutter_inappwebview downloads WebView2
with it). A deep checkout path can exceed Windows' 260-character limit in the
plugin build; map a short drive with `subst` and build from there.

Integration tests: `fvm flutter test integration_test -d windows`.
