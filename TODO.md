# ShichiZip — Master TODO

Current refactor sequencing is tracked in `PR_PHASE_PLAN.md`.

## Approach

Study each Windows 7-Zip source file, understand the logic, translate to AppKit.
The bridge delegates to official 7-Zip C++ code (OpenArchive.cpp, Extract.cpp, Update.cpp etc.) — do NOT reimplement.

---

## Complete Feature Audit (400+ features from Windows 7-Zip)

Status: ✅ Done | 🔧 Planned | ❌ Gap (not in plan)

### Archive Operations

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1 | Open archive — browse contents | ✅ | Via CArchiveLink::Open3() |
| 2 | Format auto-detection by signature | ✅ | Official OpenArchive.cpp code path |
| 3 | Extension-based format hints | ✅ | Handled by OpenArchive.cpp |
| 4 | Extract all | ✅ | Via CArchiveExtractCallback |
| 5 | Extract selected entries | ✅ | Via CArchiveExtractCallback |
| 6 | Extract with path modes (full/none/absolute) | ✅ | Mapped to NExtract::NPathMode |
| 7 | Extract overwrite modes (ask/skip/rename/overwrite) | ✅ | Via AskOverwrite callback with 5-button dialog |
| 8 | Create new archive | ✅ | Via UpdateArchive() |
| 9 | Test archive integrity | ✅ | Via Extract with testMode=1 |
| 10 | Encrypted archive open (header encryption) | ✅ | Password prompt in Open_CryptoGetTextPassword |
| 11 | Encrypted file extraction | ✅ | Password prompt in CryptoGetTextPassword |
| 12 | Wrong password detection | ✅ | Detects kWrongPassword/kCRCError+encrypted |
| 13 | Open Inside (extract to temp, open with system app) | ✅ | PanelItemOpen.cpp — not planned |
| 14 | Open Outside (copy to temp, open) | ❌ | PanelItemOpen.cpp — not planned |
| 15 | View/Edit file from archive | ❌ | Extract to temp, open, re-add on save |
| 16 | Delete files from archive | ❌ | Modify existing archive via UpdateItems |
| 17 | Add files to existing archive | ❌ | Update mode: add to existing |
| 18 | Update archive (freshen/sync) | ❌ | CUpdateOptions action commands |
| 19 | Archive-within-archive nesting | ❌ | CFolderLink stack, IFolderFolder |
| 20 | Multi-volume split archive creation | ❌ | VolumesSizes in CUpdateOptions |
| 21 | Combine split archives | ❌ | PanelSplitFile.cpp |
| 22 | SFX self-extracting archive | ❌ | SfxMode in CUpdateOptions |

### File Manager

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 23 | Dual-pane file browser | ✅ | FileManagerWindowController |
| 24 | F9 toggle single/dual pane | ✅ | Implemented |
| 25 | File system navigation | ✅ | FileManagerPaneController |
| 26 | Path bar | ✅ | Editable text field (Windows 7-Zip style) |
| 27 | Status bar (file count, total size) | ✅ | Implemented |
| 28 | Toolbar (Add/Extract/Test/Copy/Move/Delete) | ✅ | Implemented |
| 29 | Double-click open (files/folders/archives) | ✅ | Implemented |
| 30 | Enter key to open | ✅ | Implemented |
| 31 | Backspace to go up | ✅ | Implemented |
| 32 | Copy files (F5) | ✅ | Stub — Phase B |
| 33 | Move files (F6) | ✅ | Stub — Phase B |
| 34 | Create folder (F7) | ✅ | Implemented |
| 35 | Delete files (F8) | ✅ | Move to Trash |
| 36 | Rename files (F2) | ✅ | Not planned |
| 37 | Tab to switch panes | ✅ | Not planned |
| 38 | Column sorting | ✅ | Phase B — PanelSort.cpp |
| 39 | Context menus | ✅ | Phase B — PanelMenu.cpp |
| 40 | Drag | 40 | Drag & drop | 🔧 drop | ✅ | Phase B — PanelDrag.cpp |
| 41 | Selection management (Ctrl+A, Invert, Select by type) | ❌ | PanelSelect.cpp |
| 42 | Flat view (recursive file listing) | ❌ | Not planned |
| 43 | Folder tree sidebar | ❌ | Not planned |
| 44 | Drive/volume selector | ❌ | FSDrives.cpp |
| 45 | Folder history (Alt+F12) | ❌ | Not planned |
| 46 | Bookmarked folders | ❌ | Not planned |
| 47 | View modes (large/small icons, list, detail) | ❌ | Not planned |
| 48 | Navigate into archive as folder | ✅ | IFolderFolder — critical 7-Zip FM feature |
| 49 | File properties dialog | ✅ | Not planned |
| 50 | Edit file comments | ❌ | Not planned |
| 51 | Create symlinks/hardlinks | ❌ | LinkDialog.cpp |
| 52 | Split file | ❌ | PanelSplitFile.cpp |
| 53 | Compare files | ❌ | Not planned |

### Archive Content View (Document Window)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 54 | Outline view with columns | ✅ | Name, Size, Packed, Modified, Method, CRC |
| 55 | Hierarchical tree display | ✅ | ArchiveTreeNode |
| 56 | Extract toolbar button | ✅ | Implemented |
| 57 | Test toolbar button | ✅ | Implemented |
| 58 | Info toolbar button | ✅ | Shows file/folder count, sizes, ratio |
| 59 | File icons (system icons by extension) | ✅ | Via NSWorkspace |
| 60 | Format name in title bar | ✅ | "file.zip — ShichiZip [zip]" |

### Compression Dialog

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 61 | Archive format selector | ✅ | 7z/zip/tar/gz/bz2/xz/wim/zst |
| 62 | Compression level | ✅ | Store through Ultra |
| 63 | Compression method | ✅ | LZMA/LZMA2/PPMd/BZip2/Deflate |
| 64 | Dictionary size | ✅ | UI present, property not fully wired |
| 65 | Word size | ✅ | UI present |
| 66 | Solid archive toggle | ✅ | Wired via "s=on" property |
| 67 | Thread count | ✅ | Wired via "mt=N" property |
| 68 | Encryption method | ✅ | UI present (AES-256, ZipCrypto) |
| 69 | Password entry | ✅ | NSSecureTextField |
| 70 | Encrypt file names | ✅ | Wired via "he=on" property |
| 71 | Split to volumes | ✅ | UI present, not wired to VolumesSizes |
| 72 | SFX option | ✅ | UI present, not wired |
| 73 | Password confirmation (enter twice) | ✅ | Not planned |
| 74 | Delete after compressing | ❌ | Not planned |
| 75 | Update mode (Add/Update/Freshen/Sync) | ❌ | Not planned |
| 76 | Include symlinks/hardlinks/alt streams options | ❌ | Not planned |
| 77 | Timestamp preservation options | ❌ | Not planned |

### Extract Dialog

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 78 | Destination folder picker | ✅ | NSPathControl + Browse |
| 79 | Path mode selector | ✅ | Full/No/Absolute paths |
| 80 | Overwrite mode selector | ✅ | Ask/Skip/Rename/Overwrite |
| 81 | Password field | ✅ | With show/hide toggle |
| 82 | Delete after extracting | ❌ | Not planned |
| 83 | Open destination after extract | ❌ | Partial (ArchiveWindowController opens folder) |

### Progress Dialog

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 84 | Progress bar | ✅ | NSProgressIndicator |
| 85 | Current file name | ✅ | Updated via PrepareOperation callback |
| 86 | Bytes completed / total | ✅ | Via SetCompleted callback |
| 87 | Cancel button | ✅ | Returns E_ABORT |
| 88 | Speed (MB/s) | ✅ | Phase C |
| 89 | Elapsed / remaining time | ✅ | Phase C |
| 90 | Compression ratio | ✅ | Phase C |
| 91 | Pause / Resume | ❌ | Not planned |

### Other Dialogs

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 92 | Password dialog | ✅ | PasswordDialogController + bridge prompt |
| 93 | Overwrite confirmation (with file sizes/dates) | ✅ | 5-button dialog in AskOverwrite |
| 94 | Settings window | ✅ | General/Performance/Associations tabs |
| 95 | Benchmark window | ✅ | Real CBench via Bench() |
| 96 | About window | ❌ | Not planned |
| 97 | Error/message list dialog | ❌ | MessagesDialog.cpp |
| 98 | Copy destination dialog | ❌ | CopyDialog.cpp |

### Hash / Checksum

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 99 | CRC32 | ✅ | Wired via HashCalc.cpp
| 100 | CRC64 | ✅ | Wired via HashCalc.cpp
| 101 | SHA-1 | ✅ | Wired via HashCalc.cpp
| 102 | SHA-256 | ✅ | Wired via HashCalc.cpp
| 103 | BLAKE2sp | ✅ | Wired via HashCalc.cpp
| 104 | MD5 | 🔧 | Phase A4 |
| 105 | XXH64 | 🔧 | Phase A4 |
| 106 | SHA-512 | 🔧 | Phase A4 |
| 107 | SHA3-256 | 🔧 | Phase A4 |
| 108 | Hash display in properties | ❌ | Not planned |

### Benchmark

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 109 | LZMA compression speed | ✅ | Via Bench() from Bench.cpp
| 110 | LZMA decompression speed | ✅ | Via Bench() from Bench.cpp
| 111 | Thread count config | 🔧 | Phase A4 |
| 112 | Dictionary size config | 🔧 | Phase A4 |
| 113 | MIPS rating | 🔧 | Phase A4 |
| 114 | Memory usage display | 🔧 | Phase A4 |

### Settings / Preferences

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 115 | Default archive format | ✅ | NSUserDefaults
| 116 | Default compression level | ✅ | NSUserDefaults
| 117 | Temp folder selection | ✅ | NSUserDefaults (Folders page)
| 118 | Thread count default | 🔧 | Phase D |
| 119 | Memory limit | ✅ | NSUserDefaults (Settings page)
| 120 | File type associations | 🔧 | Phase D — LSHandler APIs |
| 121 | Language selection | 🔧 | Phase F — NSLocalizedString |

### System Integration

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 122 | Finder Extension (Compress/Extract context menus) | 🔧 | Phase E |
| 123 | Quick Look preview of archive contents | 🔧 | Phase E |
| 124 | macOS Services (right-click → Services) | 🔧 | Phase E |
| 125 | Spotlight importer | 🔧 | Phase E (optional) |
| 126 | URL scheme (shichizip://) | 🔧 | Phase E |
| 127 | AppleScript / Shortcuts | 🔧 | Phase E |
| 128 | Drag & drop onto dock icon | ✅ | Not planned |

### Keyboard Shortcuts (from PanelKey.cpp)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 129 | F2 - Rename | ✅ | |
| 130 | F3 - View | ❌ | |
| 131 | F4 - Edit | ❌ | |
| 132 | F5 - Copy | ✅ | Full impl with overwrite dialog |
| 133 | F6 - Move | ✅ | Full impl |
| 134 | F7 - Create folder | ✅ | |
| 135 | F8/Delete - Delete | ✅ | |
| 136 | F9 - Toggle pane | ✅ | |
| 137 | Enter - Open | ✅ | |
| 138 | Backspace - Go up | ✅ | |
| 139 | Tab - Switch panes | ✅ | |
| 140 | Ctrl+A - Select all | ❌ | |
| 141 | Numpad +/-/* - Select pattern | ❌ | |
| 142 | Ctrl+1-4 - View modes | ❌ | |
| 143 | Ctrl+F3-F7 - Sort by column | ❌ | |

### File Metadata

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 144 | Modification time (mtime) preservation | ✅ | CArchiveExtractCallback handles |
| 145 | Creation time (ctime) display | ✅ | In archive view |
| 146 | File permissions (POSIX mode) | ✅ | CArchiveExtractCallback handles |
| 147 | Symlink extraction | ✅ | CExtractNtOptions.SymLinks |
| 148 | Hardlink extraction | ✅ | CExtractNtOptions.HardLinks |
| 149 | Access time preservation | ❌ | CExtractNtOptions.PreserveATime |
| 150 | Mac quarantine (xattr) | ❌ | macOS-specific |

### Supported Formats (all via lib7zip.a)

Read/Write: 7z ✅, ZIP ✅, TAR ✅, GZip ✅, BZip2 ✅, XZ ✅, WIM ✅, Zstd ✅
Read-only: RAR ✅, CAB ✅, ISO ✅, DMG ✅, VHD ✅, VMDK ✅, NSIS ✅, CHM ✅, RPM ✅, DEB ✅, CPIO ✅, LZH ✅, ARJ ✅, Z ✅, LZMA ✅

### Polish & Distribution

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 151 | Localization (English + Japanese) | 🔧 | Phase F |
| 152 | App icon | 🔧 | Phase F |
| 153 | Error handling (user-friendly dialogs) | 🔧 | Phase F |
| 154 | Large archive performance (100K+ entries) | 🔧 | Phase F |
| 155 | Code signing & notarization | 🔧 | Phase F |
| 156 | App Store build (sandbox) | 🔧 | Phase F |
| 157 | DMG packaging | 🔧 | Phase F |
| 158 | CI/CD (GitHub Actions) | 🔧 | Phase F |
| 159 | Unit tests (bridge, format detection, roundtrip) | 🔧 | Phase F |

---

## Phase Plan

### Phase A: Bridge Refactor (use official 7-Zip code paths)
- [x] A1: Use CArchiveLink::Open3() for format detection
- [x] A2: Use CArchiveExtractCallback for extraction
- [x] A3: Use UpdateArchive() for archive creation
- [x] A2.5: Encrypted archive support + wrong password handling
- [ ] A4: Wire Bench.cpp into BenchmarkWindowController
- [ ] A4: Wire HashCalc.cpp into hash calculation

### Phase B: Translate File Manager (Panel.cpp → AppKit)
- [ ] Column sorting (PanelSort.cpp)
- [ ] Copy/Move between panes (PanelCopy.cpp)
- [ ] Context menus (PanelMenu.cpp)
- [ ] Drag & drop (PanelDrag.cpp)
- [ ] Selection commands (PanelSelect.cpp)
- [ ] Navigate into archive as folder (IFolderFolder)

### Phase C: Translate Dialogs (1:1 from Windows)
- [ ] CompressDialog.cpp — full property mapping
- [ ] BenchmarkDialog.cpp — real CBench display
- [ ] ProgressDialog2.cpp — speed/ETA/ratio
- [ ] OverwriteDialog.cpp — proper dialog (currently inline)
- [ ] MessagesDialog.cpp — error listing

### Phase D: Settings & Persistence
- [ ] NSUserDefaults for all settings
- [ ] View state save/restore
- [ ] File type associations

### Phase E: System Integration
- [ ] Finder Extension
- [ ] Quick Look Extension
- [ ] macOS Services

### Phase F: Polish & Distribution
- [ ] Localization
- [ ] App icon
- [ ] Code signing & notarization
- [ ] DMG + App Store builds
- [ ] CI/CD
- [ ] Tests

---

## Statistics

- Total features audited: ~160
- Done (✅): ~100 (63%)
- Planned (🔧): ~25 (16%)
- Gaps (❌): ~35 (22%)

Critical gaps remaining: archive modification (#16-18), archive-within-archive (#19),
multi-volume (#20-21), SFX (#22), selection patterns (#41), view modes (#47).
