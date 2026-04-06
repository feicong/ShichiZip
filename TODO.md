# ShichiZip — Revised Plan & Remaining Work

## Approach Change

**Previous approach:** Reinvent UI logic from scratch, then wire to 7-Zip core.  
**Problem:** Caused bugs — wrong format detection, duplicate tree nodes, broken path handling — all already solved in the Windows code.  
**New approach:** Study each Windows UI source file, understand the logic, translate to AppKit faithfully. The 7-Zip Windows code is the specification.

---

## Architecture: Windows → macOS Mapping

### Layer 1: Reuse As-Is (already in lib7zip.a)
These files compile into the static library and need NO translation:

| Windows Source | Purpose |
|---|---|
| `UI/Common/OpenArchive.cpp` | Format detection, signature matching, archive opening |
| `UI/Common/ArchiveExtractCallback.cpp` | Extract orchestration with callbacks |
| `UI/Common/ArchiveOpenCallback.cpp` | Open callbacks (password, progress) |
| `UI/Common/Extract.cpp` | High-level extract coordinator |
| `UI/Common/Update.cpp` | High-level update/create coordinator |
| `UI/Common/UpdateCallback.cpp` | Create archive callbacks |
| `UI/Common/LoadCodecs.cpp` | Codec/format registry |
| `UI/Common/Bench.cpp` | Benchmark engine |
| `UI/Common/HashCalc.cpp` | Checksum calculation |
| `UI/Common/EnumDirItems.cpp` | File enumeration |
| `UI/Common/PropIDUtils.cpp` | Property display formatting |
| `UI/Common/SetProperties.cpp` | Compression property setting |

**Action:** The bridge should call these directly instead of reimplementing their logic.

### Layer 2: Bridge (Obj-C++ wrappers calling Layer 1)
Current `SZArchive.mm` should be refactored to delegate to `OpenArchive.cpp` and `Extract.cpp` instead of reimplementing format detection and extract callbacks.

| Current ShichiZip | Should Delegate To |
|---|---|
| Format detection loop in `openAtPath:` | `CArchiveLink::Open()` from `OpenArchive.cpp` |
| `SZExtractCallback` class | Wrap `CArchiveExtractCallback` from `ArchiveExtractCallback.cpp` |
| `SZUpdateCallback` class | Wrap `CUpdateCallbackAgent` or `UpdateCallback.cpp` patterns |
| Compression property setup | `SetProperties.cpp` |

### Layer 3: Translate Win32 UI → AppKit
Each Windows UI file maps to a Swift/AppKit equivalent:

#### GUI Dialogs (UI/GUI/)

| Windows Source | → macOS Target | Status |
|---|---|---|
| `CompressDialog.cpp` (~1200 lines) | `CompressDialogController.swift` | Partial — needs 1:1 option mapping |
| `ExtractDialog.cpp` (~400 lines) | `ExtractDialogController.swift` | Partial — needs overwrite logic from source |
| `BenchmarkDialog.cpp` (~800 lines) | `BenchmarkWindowController.swift` | Placeholder — needs real CBench integration |
| `ExtractGUI.cpp` | Extract orchestration with GUI progress | Not started |
| `UpdateGUI.cpp` | Create archive orchestration with GUI | Not started |
| `UpdateCallbackGUI.cpp/.2.cpp` | Progress/error reporting during create | Not started |
| `HashGUI.cpp` | Hash calculation with GUI | Not started |

#### File Manager (UI/FileManager/)

| Windows Source | → macOS Target | Priority | Status |
|---|---|---|---|
| **Core Panel** | | | |
| `Panel.cpp` | `FileManagerPaneController.swift` | High | Partial |
| `PanelItems.cpp` | Item display/data source | High | Needs translation |
| `PanelListNotify.cpp` | List view notifications | High | Needs translation |
| `PanelSort.cpp` | Column sorting | High | Not started |
| `PanelKey.cpp` | Keyboard shortcuts | High | Partial |
| `PanelMenu.cpp` | Context menus | Medium | Not started |
| `PanelFolderChange.cpp` | Directory navigation | High | Partial |
| `PanelCopy.cpp` | Copy/Move operations | Medium | Not started |
| `PanelDrag.cpp` | Drag & drop | Medium | Not started |
| `PanelSelect.cpp` | Selection management | Medium | Not started |
| `PanelItemOpen.cpp` | Open items (archives, files) | High | Partial |
| `PanelOperations.cpp` | File operations (delete, rename) | Medium | Partial |
| `PanelCrc.cpp` | CRC/hash calculation from panel | Low | Not started |
| `PanelSplitFile.cpp` | Split/combine files | Low | Not started |
| **Folder Models** | | | |
| `FSFolder.cpp` | File system folder model | High | Partial (via FileSystemItem) |
| `FSFolderCopy.cpp` | File copy implementation | Medium | Not started |
| `FSDrives.cpp` | Drive/volume listing | Medium | Not started |
| `RootFolder.cpp` | Root (Computer) view | Low | Not started |
| `AltStreamsFolder.cpp` | NTFS alt streams | N/A | Skip (macOS irrelevant) |
| `NetFolder.cpp` | Network browsing | Low | Not started |
| **Dialogs** | | | |
| `OverwriteDialog.cpp` | Overwrite confirmation | High | Inline in callback |
| `PasswordDialog.cpp` | Password entry | Done | Done |
| `ProgressDialog2.cpp` | Progress with details | High | Partial |
| `CopyDialog.cpp` | Copy destination picker | Medium | Not started |
| `ComboDialog.cpp` | Generic combo dialog | Low | Not started |
| `EditDialog.cpp` | Text edit dialog | Low | Not started |
| `SplitDialog.cpp` | Split file dialog | Low | Not started |
| `LinkDialog.cpp` | Symlink dialog | Low | Not started |
| `MessagesDialog.cpp` | Error message list | Medium | Not started |
| `ListViewDialog.cpp` | Generic list dialog | Low | Not started |
| `AboutDialog.cpp` | About window | Low | Not started |
| `BrowseDialog.cpp` | Folder browser | Medium | Via NSOpenPanel |
| **Settings** | | | |
| `OptionsDialog.cpp` | Settings coordinator | Medium | Partial |
| `SettingsPage.cpp` | General settings | Medium | Partial |
| `EditPage.cpp` | Editor settings | Low | Not started |
| `FoldersPage.cpp` | Working folders | Low | Not started |
| `SystemPage.cpp` | File associations | Medium | Not started |
| `MenuPage.cpp` | Context menu settings | Low | Not started |
| `LangPage.cpp` | Language settings | Low | Not started |
| **App Infrastructure** | | | |
| `FM.cpp` / `App.cpp` | Application lifecycle | Done | AppDelegate.swift |
| `MyLoadMenu.cpp` | Menu bar construction | Done | MainMenu.swift |
| `RegistryUtils.cpp` | Settings persistence | Medium | → NSUserDefaults |
| `RegistryAssociations.cpp` | File type associations | Medium | → UTI/LSHandler |
| `ViewSettings.cpp` | View state persistence | Medium | Not started |
| `FormatUtils.cpp` | Number/size formatting | Done | Via ByteCountFormatter |
| `SysIconUtils.cpp` | System icon lookup | Done | Via NSWorkspace |
| `PropertyName.cpp` | Property name strings | Low | Not started |
| `StringUtils.cpp` | String utilities | Done | Via Swift String |
| `LangUtils.cpp` | Localization | Low | → NSLocalizedString |

#### Explorer Integration (UI/Explorer/)
| Windows Source | → macOS Target | Status |
|---|---|---|
| Context menu shell extension | Finder Extension | Not started |

---

## Revised Phase Plan

### Phase A: Refactor Bridge to Use OpenArchive.cpp (HIGH PRIORITY)
- [ ] Replace custom format detection with `CArchiveLink::Open()` / `CArchiveLink::Open2()`
- [ ] Replace `SZExtractCallback` with wrapper around `CArchiveExtractCallback`
- [ ] Replace `SZUpdateCallback` with wrapper around `UpdateCallback.cpp` patterns
- [ ] Use `PropIDUtils.cpp` for property formatting
- [ ] Wire `Bench.cpp` into BenchmarkWindowController
- [ ] Wire `HashCalc.cpp` into hash calculation

### Phase B: Translate File Manager Faithfully (HIGH PRIORITY)
Study and translate these files in order:
- [ ] `Panel.cpp` → understand panel architecture, translate to PaneController
- [ ] `PanelItems.cpp` → item data source, column definitions
- [ ] `PanelFolderChange.cpp` → directory navigation logic
- [ ] `PanelItemOpen.cpp` → archive-as-folder navigation
- [ ] `PanelSort.cpp` → sorting logic
- [ ] `PanelKey.cpp` → full keyboard shortcut map
- [ ] `PanelListNotify.cpp` → list update notifications
- [ ] `FSFolder.cpp` → file system model
- [ ] `FSDrives.cpp` → drive listing
- [ ] `PanelCopy.cpp` + `FSFolderCopy.cpp` → copy/move operations
- [ ] `PanelSelect.cpp` → selection commands
- [ ] `PanelMenu.cpp` → context menus
- [ ] `PanelDrag.cpp` → drag & drop
- [ ] `PanelOperations.cpp` → delete, rename

### Phase C: Translate Dialogs Faithfully (MEDIUM PRIORITY)
- [ ] `CompressDialog.cpp` → 1:1 option mapping
- [ ] `ExtractDialog.cpp` → 1:1 option mapping  
- [ ] `BenchmarkDialog.cpp` → real benchmark via CBench
- [ ] `OverwriteDialog.cpp` → proper overwrite dialog (not inline alert)
- [ ] `ProgressDialog2.cpp` → full progress with speed/ETA/ratio
- [ ] `CopyDialog.cpp` → copy destination dialog
- [ ] `MessagesDialog.cpp` → error listing

### Phase D: Settings & Persistence
- [ ] `RegistryUtils.cpp` → NSUserDefaults mapping
- [ ] `ViewSettings.cpp` → view state save/restore
- [ ] `OptionsDialog.cpp` → settings window
- [ ] `SystemPage.cpp` → file associations via LSHandler

### Phase E: System Integration
- [ ] Finder Extension (translate Explorer shell extension concept)
- [ ] Quick Look Extension
- [ ] macOS Services

### Phase F: Polish & Distribution
- [ ] Localization (study `LangUtils.cpp` pattern)
- [ ] App icon
- [ ] Code signing & notarization
- [ ] DMG packaging
- [ ] App Store build

---

## Completed Phases

### Phase 1: Foundation ✅
- [x] Clone 7-Zip source as git submodule (`vendor/7zip/`)
- [x] Study macOS build system (`cmpl_mac_arm64.mak`, `7zip_gcc.mak`)
- [x] Create Makefile for `lib7zip.a` (311 objects, all formats + codecs + crypto)
- [x] Validate: 7zz console binary builds and runs on arm64 macOS

### Phase 2: Obj-C++ Bridge ✅
- [x] `SZArchive.h` — ObjC API (open, list, extract, create, test, formats)
- [x] `SZArchive.mm` — C++ implementation wrapping IInArchive/IOutArchive
- [x] `SZArchiveEntry` — entry model (path, size, packed, crc, method, dates, encrypted)
- [x] `SZCompressionSettings` / `SZExtractionSettings` — options
- [x] `SZProgressDelegate` — progress callback protocol
- [x] BOOL typedef conflict workaround (ObjC bool vs 7-Zip int)
- [x] POSIX compatibility (CFiTime→FILETIME, mode→GetWinAttrib)

### Phase 3: Xcode Project ✅
- [x] XcodeGen `project.yml` spec
- [x] Info.plist with UTI declarations (7z, zip, tar, gz, bz2, xz, rar, iso)
- [x] Entitlements (direct + App Store variants)
- [x] Bridging header
- [x] Programmatic main menu (`MainMenu.swift`)
- [x] Asset catalog with AppIcon placeholder

### Phase 4: File Manager UI ✅
- [x] `FileManagerWindowController` — dual-pane with F9 toggle, toolbar
- [x] `FileManagerPaneController` — file system browsing, path bar, status bar
- [x] Keyboard shortcuts (Enter, Backspace, F5–F9)
- [x] Open archives from file manager → document window

### Phase 5: Dialogs ✅
- [x] `ArchiveDocument` + `ArchiveWindowController` — document-based architecture
- [x] `ArchiveViewController` — outline view with 6 columns
- [x] `CompressDialogController` — all format/level/method/encryption options
- [x] `ExtractDialogController` — path mode, overwrite, password
- [x] `ProgressDialogController` — progress bar, filename, bytes, cancel
- [x] `PasswordDialogController` — show/hide toggle
- [x] `SettingsWindowController` — General, Performance, Associations tabs
- [x] `BenchmarkWindowController` — placeholder benchmark
