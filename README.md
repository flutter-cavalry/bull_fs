# bull_fs

Unified file system APIs for local file system, Android SAF, and iOS / macOS `NSFileCoordinator`.

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
