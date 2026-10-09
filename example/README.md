# BullFS Example

The example app browses a user-selected folder. Filesystem tests use Flutter's
standard integration test runner.

## Integration Tests

Run commands from this directory. Find device IDs with `flutter devices`.

```sh
flutter test integration_test/bf_local_env_test.dart -d <device-id>
flutter test integration_test/bf_platform_env_test.dart -d <device-id>
```

The local suite uses `BFLocalEnv` in an automatically created temporary folder.
It does not require user input.

The platform suite opens a native folder picker once per run. Select a writable
folder when prompted. It uses `BFSafEnv` on Android and `BFNsfcEnv` on macOS/iOS,
including non-iCloud Apple folders. Cancellation fails the test; unsupported
platforms skip the suite. Allow up to five minutes for the first test while
selecting a folder. These tests are interactive and require a desktop session
or an emulator/device with a user available to complete the picker.

Both entry points register the same `BFEnv` cases. Test target and environment
wrappers in `integration_test/support` own platform selection, local scratch
files, permission release, and cleanup. Each case creates a uniquely named
child folder and deletes only that folder, even on failure. The selected folder
and its existing contents are never deleted, and it need not be empty. Temporary
local files are deleted when the suite finishes. Interrupting the process may
leave test child folders behind.

Run the example's smoke and fixture tests with `flutter test test`.
