# bull_fs

Unified file system APIs for user-selected directories on different platform. Supports local file system, Android SAF, and iOS / macOS `NSFileCoordinator`.

## Get started

### `BFEnv`

`BFEnv` is the core of this package. All supported environments are sub-classes of `BFEnv`, which defines the common APIs for file system operations. `bull_fs` has 3 implementations:

- `BFLocalEnv`: for local file system, which is a wrapper around Dart file system APIs.
- `BFSafEnv`: for Android Storage Access Framework (SAF).
- `BFNsfcEnv`: for iOS / macOS `NSFileCoordinator`.

Below is a good summary of when to use which on different platforms:

| Platform        | Which `BFEnv` to use                                            |
| --------------- | --------------------------------------------------------------- |
| iOS             | You need `BFNsfcEnv` to access directories                      |
| Android         | Use `BFSafEnv` if you need SAF.                                 |
| macOS           | Use `BFNsfcEnv` for iCloud folders and `BFLocalEnv` for others. |
| Windows / Linux | Use `BFLocalEnv`                                                |

### `BFPath`

Due to the differences in file system APIs on different platforms. Paths are represented by `BFPath` instead of `String`. `BFPath` is a platform-independent representation of a file path. It can be the following types:

- `BFLocalPath`: for local file system. Wrapping a path like `/path/to/file`.
- `BFScopedPath`: a scoped path.
  - When used with `BFSafEnv`, it's a URI like `content://com.android.externalstorage.documents/document/primary:Download/file.txt`.
  - When used with `BFNsfcEnv`, it's a iOS / macOS file URL like `file:///path/to/file`.

### Get a `BFEnv` instance (from a user directory)

You can always create an instance of `BFEnv` directly, feed it with some `BFPath` and call its APIs. But in most cases, especially on mobile, you only have directory access permission when the user selects a directory. Remember the purpose of this package is to provide a unified API for file system operations, so it's recommended to create a `BFEnv` from a user directory.

First, you need to get a user directory. We recommend using our package [`fc_file_picker_util`](https://github.com/flutter-cavalry/fc_file_picker_util), because it returns both path and URI if possible. Here is how to pick a directory with it:

```dart
import 'package:fc_file_picker_util/fc_file_picker_util.dart';

final pickerResult =
  await FcFilePickerUtil.pickFolder(writePermission: true);

if (pickerResult == null) {
  // User cancelled.
  return;
}
```

If picker result is not `null`, you can create a `BFEnv` instance from via `BFUiUtil.initFromUserDirectory`:

```dart
final bfInit = await BFUiUtil.initFromUserDirectory(
  path: pickerResult.path, uri: pickerResult.uri);
```

`BFUiUtil.initFromUserDirectory` returns a `BFInitResult` defined as:

```dart
/// The result of [BFUiUtil.initFromUserDirectory].
class BFInitResult {
  // The [BFPath] of the directory.
  final BFPath path;
  // The [BFEnv] created.
  final BFEnv env;
  // Whether the directory is in iCloud.
  final bool isIcloud;

  BFInitResult(this.path, this.env, this.isIcloud);
}
```

So how is `BFInitResult.env` created?

- On Windows, only `pickerResult.path` is set. `BFLocalEnv` is returned.
- On Android, `pickerResult.uri` is set. `BFSafEnv` is returned.
- On iOS, both `pickerResult.path` and `pickerResult.uri` are set. `BFNsfcEnv` is returned on iOS.
- On macOS, both `pickerResult.path` and `pickerResult.uri` are set. If the directory is in iCloud, `BFNsfcEnv` is returned. Otherwise, `BFLocalEnv` is returned.

Now you have both `BFEnv` and `BFPath` of the user directory. You can use `BFEnv` to perform file system operations.

### File system APIs

APIs supported by `BFEnv`:

- List directory content:
  - `list`: Lists sub-directories and files in a directory.
  - `listDirContentFiles`: a platform optimized version of `list` that only lists files recursively.
- Get stats:
  - `stat`: Gets file or directory info.
  - `child`: Gets a child file or directory.
  - `fileExists`: Checks if a file exists.
  - `directoryExists`: Checks if a directory exists.
- Read / write files:
  - With local files:
    - `copyToLocalFile`: Copies a [BFPath] to a local file.
    - `pasteLocalFile`: Copies a local file to a [BFPath].
  - With streams:
    - `readFileStream`: Reads a file as a stream.
    - `writeFileStream`: Writes a stream to a file.
  - With `Uint8List`:
    - `readFileBytes`: Reads a file as a `Uint8List`.
    - `writeFileBytes`: Writes a `Uint8List` to a file.
- Create directories:
  - `mkdirp`: Creates directories recursively.
  - `createDir`: Creates a directory. Unlike `mkdirp`, it always creates a new directory.
- Delete / rename / move files or directories:
  - `delete`: Deletes a file or directory.
  - `rename`: Renames a file or directory.
  - `moveToDir`: Moves a file or directory to another directory.
