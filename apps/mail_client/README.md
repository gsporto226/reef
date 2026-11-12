# mail_client

The mail client integration app (`docs/integration-apps.md`): folders, a
thread list and threads in one windowing doc, drawn master-detail on expanded
screens and as a stack on compact ones.

The UI follows `design/SPEC.md`. Tokens and icon glyphs are generated from
`design/tokens.json` and `design/SPEC.snapshot.json`; regenerate after a
design sync (`test/design_builder_test.dart` fails while they are stale):

```powershell
fvm dart run build_runner build
```

`test/screens_test.dart` renders every SPEC screen at its frame size into
`test/goldens/` (`--update-goldens` to refresh).

```powershell
fvm flutter run -d windows
fvm flutter test integration_test -d windows
```
