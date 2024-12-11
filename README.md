> [!WARNING]  
> Experimental. Expect breaking changes and don't use it in production.

# bull_fs

Unified file system APIs for local file system (Dart IO), Android SAF, and iOS / macOS `NSFileCoordinator` (mostly for iCloud access).

## Get started

### `BFEnv`

`BFEnv` is the core of this package. All supported environments are sub-classes of `BFEnv`. This class defines the common APIs for file system operations. `bull_fs` has 3 implementations:

- `BFLocalEnv`: for local file system, which is a wrapper around Dart IO.
- `BFSafEnv`: for Android Storage Access Framework (SAF).
- `BFNsfcEnv`: for iOS / macOS `NSFileCoordinator` (mostly for iCloud access).

Below is a good summary of which to use on different platforms:

| Platform        | Which `BFEnv` to use                                                 |
| --------------- | -------------------------------------------------------------------- |
| iOS             | Use `BFNsfcEnv` if you need access to user-selected folders or files |
| Android         | Use `BFSafEnv` if you need SAF access.                               |
| macOS           | Use `BFNsfcEnv` for iCloud folders and `BFLocalEnv` for others.      |
| Windows / Linux | Use `BFLocalEnv`                                                     |

### `BFPath`

Due to the differences in file system APIs on different platforms. Paths are represented by `BFPath` instead of `String`. `BFPath` is a platform-independent representation of a file path. It can be the following types:

- `BFLocalPath`: for local file system. Wrapping a path like `/path/to/file`.
- `BFScopedPath`: a scoped path.
  - When used with `BFSafEnv`, it's a URI like `content://com.android.externalstorage.documents/document/primary:Download/file.txt`.
  - When used with `BFNsfcEnv`, it's a iOS / macOS file URL like `file:///path/to/file`.

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
