// SZArchive.mm — 7-Zip core bridge for ShichiZip
// This file must be compiled as Objective-C++ (.mm)

// Workaround for BOOL typedef conflict between 7-Zip (int) and ObjC (bool on arm64)
// Strategy: Let ObjC define BOOL first, then redirect 7-Zip's typedef to a dummy name

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "SZArchive.h"

// Define INITGUID to make this TU define the IID constants
#define INITGUID

// Before including MyWindows.h, redirect BOOL so 7-Zip's typedef creates a harmless alias
#define BOOL BOOL_7Z_COMPAT
#include "CPP/Common/MyWindows.h"
#undef BOOL
// Now BOOL refers to ObjC's bool type, and BOOL_7Z_COMPAT is typedef'd to int

#include "CPP/Common/MyString.h"
#include "CPP/Common/IntToString.h"
#include "CPP/Windows/FileDir.h"
#include "CPP/Windows/FileFind.h"
#include "CPP/Windows/FileName.h"
#include "CPP/Windows/PropVariant.h"
#include "CPP/Windows/PropVariantConv.h"
#include "CPP/7zip/Common/FileStreams.h"
#include "CPP/7zip/Common/StreamObjects.h"
#include "CPP/7zip/Archive/IArchive.h"
#include "CPP/7zip/IPassword.h"
#include "CPP/7zip/ICoder.h"
#include "CPP/7zip/UI/Common/LoadCodecs.h"
#include "CPP/7zip/UI/Common/OpenArchive.h"
#include "CPP/7zip/UI/Common/ArchiveExtractCallback.h"
#include "CPP/7zip/UI/Common/Extract.h"
#include "CPP/7zip/UI/Common/IFileExtractCallback.h"
#include "CPP/7zip/PropID.h"
#include "CPP/Windows/TimeUtils.h"
#include "C/7zCrc.h"

#include <string>
#include <vector>

NSString * const SZArchiveErrorDomain = @"SZArchiveErrorDomain";

static NSError *SZMakeError(NSInteger code, NSString *desc) {
    return [NSError errorWithDomain:SZArchiveErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: desc}];
}

// Codec manager singleton
static CCodecs *g_Codecs = nullptr;
static bool g_CodecsInitialized = false;

static CCodecs *GetCodecs() {
    if (!g_CodecsInitialized) {
        CrcGenerateTable();
        g_Codecs = new CCodecs;
        if (g_Codecs->Load() != S_OK) { delete g_Codecs; g_Codecs = nullptr; }
        g_CodecsInitialized = true;
    }
    return g_Codecs;
}

// UString <-> NSString using NSString's own UTF-8 facilities
static UString ToU(NSString *s) {
    if (!s) return UString();
    // Convert via wchar_t
    NSUInteger len = [s length];
    UString u;
    u.Empty();
    for (NSUInteger i = 0; i < len; i++) {
        unichar ch = [s characterAtIndex:i];
        u += (wchar_t)ch;
    }
    return u;
}
static NSString *ToNS(const UString &u) {
    NSMutableString *s = [NSMutableString stringWithCapacity:u.Len()];
    for (unsigned i = 0; i < u.Len(); i++) {
        unichar ch = (unichar)u[i];
        [s appendString:[NSString stringWithCharacters:&ch length:1]];
    }
    return s;
}

// Property helpers
static NSString *ItemStr(IInArchive *ar, UInt32 i, PROPID p) {
    NWindows::NCOM::CPropVariant v;
    if (ar->GetProperty(i, p, &v) != S_OK) return nil;
    if (v.vt == VT_BSTR && v.bstrVal) return ToNS(UString(v.bstrVal));
    return nil;
}
static uint64_t ItemU64(IInArchive *ar, UInt32 i, PROPID p) {
    NWindows::NCOM::CPropVariant v;
    if (ar->GetProperty(i, p, &v) != S_OK) return 0;
    if (v.vt == VT_UI8) return v.uhVal.QuadPart;
    if (v.vt == VT_UI4) return v.ulVal;
    return 0;
}
static int ItemBool(IInArchive *ar, UInt32 i, PROPID p) {
    NWindows::NCOM::CPropVariant v;
    if (ar->GetProperty(i, p, &v) != S_OK) return 0;
    return (v.vt == VT_BOOL && v.boolVal != VARIANT_FALSE) ? 1 : 0;
}
static NSDate *ItemDate(IInArchive *ar, UInt32 i, PROPID p) {
    NWindows::NCOM::CPropVariant v;
    if (ar->GetProperty(i, p, &v) != S_OK || v.vt != VT_FILETIME) return nil;
    uint64_t ft = ((uint64_t)v.filetime.dwHighDateTime << 32) | v.filetime.dwLowDateTime;
    static const uint64_t EPOCH_DIFF = 116444736000000000ULL;
    if (ft < EPOCH_DIFF) return nil;
    return [NSDate dateWithTimeIntervalSince1970:(double)(ft - EPOCH_DIFF) / 10000000.0];
}

// ============================================================
// IFolderArchiveExtractCallback — our UI callback, used by CArchiveExtractCallback
// This matches the pattern from ExtractCallbackConsole.cpp
// ============================================================
class SZFolderExtractCallback final :
    public IFolderArchiveExtractCallback,
    public IFolderArchiveExtractCallback2,
    public ICryptoGetTextPassword,
    public CMyUnknownImp
{
public:
    UString Password;
    bool PasswordIsDefined;
    UInt64 TotalSize;
    SZOverwriteMode OverwriteMode;
    __unsafe_unretained id<SZProgressDelegate> Delegate;

    SZFolderExtractCallback() : PasswordIsDefined(false), TotalSize(0),
        OverwriteMode(SZOverwriteModeAsk), Delegate(nil) {}

    Z7_COM_UNKNOWN_IMP_3(IFolderArchiveExtractCallback, IFolderArchiveExtractCallback2, ICryptoGetTextPassword)

    // IProgress
    STDMETHOD(SetTotal)(UInt64 total) override {
        TotalSize = total;
        return S_OK;
    }
    STDMETHOD(SetCompleted)(const UInt64 *completed) override {
        if (completed && TotalSize > 0) {
            double f = (double)*completed / (double)TotalSize;
            UInt64 c = *completed, t = TotalSize;
            id<SZProgressDelegate> d = Delegate;
            if (d) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [d progressDidUpdate:f];
                    [d progressDidUpdateBytesCompleted:c total:t];
                });
                if ([d progressShouldCancel]) return E_ABORT;
            }
        }
        return S_OK;
    }

    // IFolderArchiveExtractCallback
    STDMETHOD(AskOverwrite)(
        const wchar_t *existName, const FILETIME *existTime, const UInt64 *existSize,
        const wchar_t *newName, const FILETIME *newTime, const UInt64 *newSize,
        Int32 *answer) override
    {
        // Map our SZOverwriteMode to 7-Zip's NOverwriteAnswer
        switch (OverwriteMode) {
            case SZOverwriteModeOverwrite:
                *answer = NOverwriteAnswer::kYesToAll;
                return S_OK;
            case SZOverwriteModeSkip:
                *answer = NOverwriteAnswer::kNoToAll;
                return S_OK;
            case SZOverwriteModeRename:
                *answer = NOverwriteAnswer::kAutoRename;
                return S_OK;
            case SZOverwriteModeAsk:
            default: {
                // Ask user on main thread with file details
                __block Int32 result = NOverwriteAnswer::kYes;
                NSString *existStr = existName ? ToNS(UString(existName)) : @"";
                NSString *newStr = newName ? ToNS(UString(newName)) : @"";
                dispatch_sync(dispatch_get_main_queue(), ^{
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"File already exists";
                    NSMutableString *info = [NSMutableString string];
                    [info appendFormat:@"Would you like to replace the existing file:\n%@", existStr];
                    if (existSize) {
                        [info appendFormat:@"\nSize: %@",
                            [NSByteCountFormatter stringFromByteCount:(long long)*existSize
                                                           countStyle:NSByteCountFormatterCountStyleFile]];
                    }
                    [info appendFormat:@"\n\nwith this one from the archive:\n%@", newStr];
                    if (newSize) {
                        [info appendFormat:@"\nSize: %@",
                            [NSByteCountFormatter stringFromByteCount:(long long)*newSize
                                                           countStyle:NSByteCountFormatterCountStyleFile]];
                    }
                    alert.informativeText = info;
                    alert.alertStyle = NSAlertStyleWarning;
                    [alert addButtonWithTitle:@"Yes"];
                    [alert addButtonWithTitle:@"Yes to All"];
                    [alert addButtonWithTitle:@"No"];
                    [alert addButtonWithTitle:@"No to All"];
                    [alert addButtonWithTitle:@"Auto Rename"];
                    NSModalResponse resp = [alert runModal];
                    if (resp == NSAlertFirstButtonReturn) result = NOverwriteAnswer::kYes;
                    else if (resp == NSAlertFirstButtonReturn + 1) result = NOverwriteAnswer::kYesToAll;
                    else if (resp == NSAlertFirstButtonReturn + 2) result = NOverwriteAnswer::kNo;
                    else if (resp == NSAlertFirstButtonReturn + 3) result = NOverwriteAnswer::kNoToAll;
                    else if (resp == NSAlertFirstButtonReturn + 4) result = NOverwriteAnswer::kAutoRename;
                });
                *answer = result;
                // If user chose "to all", update the mode for subsequent files
                if (result == NOverwriteAnswer::kYesToAll) OverwriteMode = SZOverwriteModeOverwrite;
                else if (result == NOverwriteAnswer::kNoToAll) OverwriteMode = SZOverwriteModeSkip;
                return S_OK;
            }
        }
    }

    STDMETHOD(PrepareOperation)(const wchar_t *name, Int32 isFolder, Int32 askExtractMode, const UInt64 *position) override {
        if (name) {
            id<SZProgressDelegate> d = Delegate;
            if (d) {
                NSString *n = ToNS(UString(name));
                dispatch_async(dispatch_get_main_queue(), ^{
                    [d progressDidUpdateFileName:n];
                });
            }
        }
        return S_OK;
    }

    STDMETHOD(MessageError)(const wchar_t *message) override {
        return S_OK;
    }

    STDMETHOD(SetOperationResult)(Int32 opRes, Int32 encrypted) override {
        return S_OK;
    }

    // IFolderArchiveExtractCallback2
    STDMETHOD(ReportExtractResult)(Int32 opRes, Int32 encrypted, const wchar_t *name) override {
        return S_OK;
    }

    // ICryptoGetTextPassword
    STDMETHOD(CryptoGetTextPassword)(BSTR *pw) override {
        if (!PasswordIsDefined) return E_ABORT;
        return StringToBstr(Password, pw);
    }
};

// ============================================================
// Update callback
// ============================================================
struct UpdItem { UString path, archPath; bool isDir; UInt64 size; FILETIME mt, ct; UInt32 winAttr; };

class SZUpdateCallback final : public IArchiveUpdateCallback2, public ICryptoGetTextPassword2, public CMyUnknownImp {
public:
    CObjectVector<UpdItem> Items;
    UString Password; bool PasswordIsDefined, EncryptHeaders;
    UInt64 TotalSize;
    __unsafe_unretained id<SZProgressDelegate> Delegate;

    SZUpdateCallback() : PasswordIsDefined(false), EncryptHeaders(false), TotalSize(0), Delegate(nil) {}

    Z7_COM_UNKNOWN_IMP_2(IArchiveUpdateCallback2, ICryptoGetTextPassword2)

    STDMETHOD(SetTotal)(UInt64 t) override { TotalSize = t; return S_OK; }
    STDMETHOD(SetCompleted)(const UInt64 *cv) override {
        if (cv && TotalSize > 0) {
            double f = (double)*cv / (double)TotalSize;
            UInt64 c = *cv, t = TotalSize;
            id<SZProgressDelegate> d = Delegate;
            if (d) {
                dispatch_async(dispatch_get_main_queue(), ^{ [d progressDidUpdate:f]; [d progressDidUpdateBytesCompleted:c total:t]; });
                if ([d progressShouldCancel]) return E_ABORT;
            }
        }
        return S_OK;
    }
    STDMETHOD(GetUpdateItemInfo)(UInt32, Int32 *nd, Int32 *np, UInt32 *iia) override {
        if (nd) *nd = 1; if (np) *np = 1; if (iia) *iia = (UInt32)(Int32)-1; return S_OK;
    }
    STDMETHOD(GetProperty)(UInt32 i, PROPID pid, PROPVARIANT *val) override {
        NWindows::NCOM::CPropVariant p;
        if (i >= (UInt32)Items.Size()) return E_INVALIDARG;
        const auto &it = Items[i];
        switch (pid) {
            case kpidIsAnti: p = false; break;
            case kpidPath: p = it.archPath; break;
            case kpidIsDir: p = it.isDir; break;
            case kpidSize: p = it.size; break;
            case kpidMTime: p = it.mt; break;
            case kpidCTime: p = it.ct; break;
            case kpidAttrib: p = it.winAttr; break;
        }
        p.Detach(val); return S_OK;
    }
    STDMETHOD(GetStream)(UInt32 i, ISequentialInStream **in) override {
        *in = nullptr;
        if (i >= (UInt32)Items.Size()) return E_INVALIDARG;
        const auto &it = Items[i];
        if (it.isDir) return S_OK;
        id<SZProgressDelegate> d = Delegate;
        if (d) { NSString *n = ToNS(it.archPath); dispatch_async(dispatch_get_main_queue(), ^{ [d progressDidUpdateFileName:n]; }); }
        CInFileStream *spec = new CInFileStream;
        CMyComPtr<ISequentialInStream> loc(spec);
        if (!spec->Open(us2fs(it.path))) return S_FALSE;
        *in = loc.Detach(); return S_OK;
    }
    STDMETHOD(SetOperationResult)(Int32) override { return S_OK; }
    STDMETHOD(GetVolumeSize)(UInt32, UInt64*) override { return S_FALSE; }
    STDMETHOD(GetVolumeStream)(UInt32, ISequentialOutStream**) override { return S_FALSE; }
    STDMETHOD(CryptoGetTextPassword2)(Int32 *def, BSTR *pw) override {
        *def = PasswordIsDefined ? 1 : 0;
        return StringToBstr(Password, pw);
    }
};

// ============================================================
// ObjC implementations
// ============================================================
@implementation SZCompressionSettings
- (instancetype)init {
    if ((self = [super init])) { _format = SZArchiveFormat7z; _level = SZCompressionLevelNormal; _method = SZCompressionMethodLZMA2; _encryption = SZEncryptionMethodNone; _solidMode = YES; }
    return self;
}
@end
@implementation SZExtractionSettings
- (instancetype)init {
    if ((self = [super init])) { _pathMode = SZPathModeFullPaths; _overwriteMode = SZOverwriteModeAsk; }
    return self;
}
@end
@implementation SZArchiveEntry @end
@implementation SZFormatInfo @end

// ============================================================
// IOpenCallbackUI implementation (matches OpenCallbackConsole pattern)
// ============================================================
class SZOpenCallbackUI : public IOpenCallbackUI {
public:
    UString Password;
    bool PasswordIsDefined;
    __unsafe_unretained id<SZProgressDelegate> Delegate;

    SZOpenCallbackUI() : PasswordIsDefined(false), Delegate(nil) {}

    HRESULT Open_CheckBreak() override { return S_OK; }
    HRESULT Open_SetTotal(const UInt64 *, const UInt64 *) override { return S_OK; }
    HRESULT Open_SetCompleted(const UInt64 *, const UInt64 *) override { return S_OK; }
    HRESULT Open_Finished() override { return S_OK; }
#ifndef Z7_NO_CRYPTO
    HRESULT Open_CryptoGetTextPassword(BSTR *password) override {
        if (!PasswordIsDefined) return E_ABORT;
        return StringToBstr(Password, password);
    }
#endif
};

@interface SZArchive () {
    CArchiveLink *_arcLink;  // Use official CArchiveLink instead of raw IInArchive
    BOOL _isOpen;
    NSString *_archivePath;
}
@end

@implementation SZArchive
- (instancetype)init {
    if ((self = [super init])) {
        _arcLink = new CArchiveLink;
        _isOpen = NO;
    }
    return self;
}
- (void)dealloc { [self close]; delete _arcLink; _arcLink = nullptr; }

- (BOOL)openAtPath:(NSString *)path error:(NSError **)error {
    return [self openAtPath:path password:nil error:error];
}

- (BOOL)openAtPath:(NSString *)path password:(NSString *)password error:(NSError **)error {
    CCodecs *codecs = GetCodecs();
    if (!codecs) { if (error) *error = SZMakeError(-1, @"Failed to init codecs"); return NO; }
    _archivePath = [path copy];

    // Use CArchiveLink::Open3() — the same code path as real 7-Zip
    CObjectVector<COpenType> types;  // empty = auto-detect all formats
    CIntVector excludedFormats;      // empty = don't exclude any
    CObjectVector<CProperty> props;  // empty = no special properties

    COpenOptions options;
    options.codecs = codecs;
    options.types = &types;
    options.excludedFormats = &excludedFormats;
    options.props = &props;
    options.stdInMode = false;
    options.stream = NULL;  // CArchiveLink will create its own stream from filePath
    options.filePath = ToU(path);

    SZOpenCallbackUI callbackUI;
    if (password) {
        callbackUI.PasswordIsDefined = true;
        callbackUI.Password = ToU(password);
    }

    HRESULT res = _arcLink->Open3(options, &callbackUI);

    if (res != S_OK) {
        NSString *desc;
        if (res == S_FALSE) desc = @"Cannot open archive or unsupported format";
        else if (res == E_ABORT) desc = @"Operation was cancelled";
        else desc = [NSString stringWithFormat:@"Failed to open archive (0x%08X)", (unsigned)res];
        if (error) *error = SZMakeError(res, desc);
        return NO;
    }

    _isOpen = YES;
    return YES;
}

- (void)close {
    if (_isOpen) {
        _arcLink->Close();
    }
    _isOpen = NO;
}

- (NSString *)formatName {
    if (!_isOpen) return nil;
    const CArc &arc = _arcLink->Arcs.Back();
    CCodecs *c = GetCodecs();
    if (!c || arc.FormatIndex < 0) return nil;
    return ToNS(c->Formats[arc.FormatIndex].Name);
}

- (NSUInteger)entryCount {
    if (!_isOpen) return 0;
    IInArchive *archive = _arcLink->GetArchive();
    if (!archive) return 0;
    UInt32 n = 0; archive->GetNumberOfItems(&n); return n;
}

- (NSArray<SZArchiveEntry *> *)entries {
    if (!_isOpen) return @[];
    IInArchive *archive = _arcLink->GetArchive();
    if (!archive) return @[];
    UInt32 n = 0; archive->GetNumberOfItems(&n);
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:n];
    for (UInt32 i = 0; i < n; i++) {
        SZArchiveEntry *e = [SZArchiveEntry new];
        e.index = i;
        e.path = ItemStr(archive, i, kpidPath) ?: @"";
        e.size = ItemU64(archive, i, kpidSize);
        e.packedSize = ItemU64(archive, i, kpidPackSize);
        e.crc = (uint32_t)ItemU64(archive, i, kpidCRC);
        e.isDirectory = ItemBool(archive, i, kpidIsDir);
        e.isEncrypted = ItemBool(archive, i, kpidEncrypted);
        e.method = ItemStr(archive, i, kpidMethod);
        e.attributes = (uint32_t)ItemU64(archive, i, kpidAttrib);
        e.modifiedDate = ItemDate(archive, i, kpidMTime);
        e.createdDate = ItemDate(archive, i, kpidCTime);
        e.comment = ItemStr(archive, i, kpidComment);
        [arr addObject:e];
    }
    return arr;
}

- (BOOL)extractToPath:(NSString *)dest settings:(SZExtractionSettings *)s progress:(id<SZProgressDelegate>)p error:(NSError **)error {
    if (!_isOpen) { if (error) *error = SZMakeError(-4, @"No archive open"); return NO; }
    IInArchive *archive = _arcLink->GetArchive();
    const CArc &arc = _arcLink->Arcs.Back();
    NWindows::NFile::NDir::CreateComplexDir(us2fs(ToU(dest)));

    // Map SZOverwriteMode → NExtract::NOverwriteMode
    NExtract::NOverwriteMode::EEnum owMode = NExtract::NOverwriteMode::kAsk;
    switch (s.overwriteMode) {
        case SZOverwriteModeOverwrite: owMode = NExtract::NOverwriteMode::kOverwrite; break;
        case SZOverwriteModeSkip: owMode = NExtract::NOverwriteMode::kSkip; break;
        case SZOverwriteModeRename: owMode = NExtract::NOverwriteMode::kRename; break;
        case SZOverwriteModeAsk: default: owMode = NExtract::NOverwriteMode::kAsk; break;
    }

    // Map SZPathMode → NExtract::NPathMode
    NExtract::NPathMode::EEnum pathMode = NExtract::NPathMode::kFullPaths;
    switch (s.pathMode) {
        case SZPathModeNoPaths: pathMode = NExtract::NPathMode::kNoPaths; break;
        case SZPathModeAbsolutePaths: pathMode = NExtract::NPathMode::kAbsPaths; break;
        case SZPathModeFullPaths: default: pathMode = NExtract::NPathMode::kFullPaths; break;
    }

    // Create our UI callback (IFolderArchiveExtractCallback)
    SZFolderExtractCallback *faeSpec = new SZFolderExtractCallback;
    CMyComPtr<IFolderArchiveExtractCallback> faeCallback(faeSpec);
    faeSpec->Delegate = p;
    faeSpec->OverwriteMode = s.overwriteMode;
    if (s.password) { faeSpec->PasswordIsDefined = true; faeSpec->Password = ToU(s.password); }

    // Create the official CArchiveExtractCallback (handles file creation, attrs, timestamps)
    CArchiveExtractCallback *ecs = new CArchiveExtractCallback;
    CMyComPtr<IArchiveExtractCallback> ec(ecs);

    CExtractNtOptions ntOptions;
    UStringVector removePathParts;

    ecs->InitForMulti(false, pathMode, owMode,
        NExtract::NZoneIdMode::kNone, false);

    ecs->Init(ntOptions, NULL, &arc, faeCallback,
        false /* stdOutMode */, s == nil ? false : false /* testMode */,
        us2fs(ToU(dest)), removePathParts, false,
        arc.GetEstmatedPhySize());

    HRESULT r = archive->Extract(nullptr, (UInt32)(Int32)-1, 0, ec);
    if (r != S_OK) { if (error) *error = SZMakeError(r == E_ABORT ? -5 : -6, r == E_ABORT ? @"Cancelled" : @"Extraction failed"); return NO; }
    return YES;
}

- (BOOL)extractEntries:(NSArray<NSNumber *> *)indices toPath:(NSString *)dest settings:(SZExtractionSettings *)s progress:(id<SZProgressDelegate>)p error:(NSError **)error {
    if (!_isOpen) { if (error) *error = SZMakeError(-4, @"No archive open"); return NO; }
    IInArchive *archive = _arcLink->GetArchive();
    const CArc &arc = _arcLink->Arcs.Back();
    NWindows::NFile::NDir::CreateComplexDir(us2fs(ToU(dest)));

    NExtract::NOverwriteMode::EEnum owMode = NExtract::NOverwriteMode::kAsk;
    switch (s.overwriteMode) {
        case SZOverwriteModeOverwrite: owMode = NExtract::NOverwriteMode::kOverwrite; break;
        case SZOverwriteModeSkip: owMode = NExtract::NOverwriteMode::kSkip; break;
        case SZOverwriteModeRename: owMode = NExtract::NOverwriteMode::kRename; break;
        default: break;
    }
    NExtract::NPathMode::EEnum pathMode = NExtract::NPathMode::kFullPaths;
    switch (s.pathMode) {
        case SZPathModeNoPaths: pathMode = NExtract::NPathMode::kNoPaths; break;
        case SZPathModeAbsolutePaths: pathMode = NExtract::NPathMode::kAbsPaths; break;
        default: break;
    }

    SZFolderExtractCallback *faeSpec = new SZFolderExtractCallback;
    CMyComPtr<IFolderArchiveExtractCallback> faeCallback(faeSpec);
    faeSpec->Delegate = p;
    faeSpec->OverwriteMode = s.overwriteMode;
    if (s.password) { faeSpec->PasswordIsDefined = true; faeSpec->Password = ToU(s.password); }

    CArchiveExtractCallback *ecs = new CArchiveExtractCallback;
    CMyComPtr<IArchiveExtractCallback> ec(ecs);

    CExtractNtOptions ntOptions;
    UStringVector removePathParts;

    ecs->InitForMulti(false, pathMode, owMode,
        NExtract::NZoneIdMode::kNone, false);
    ecs->Init(ntOptions, NULL, &arc, faeCallback,
        false, false, us2fs(ToU(dest)), removePathParts, false,
        arc.GetEstmatedPhySize());

    std::vector<UInt32> ia; ia.reserve(indices.count);
    for (NSNumber *n in indices) ia.push_back([n unsignedIntValue]);
    HRESULT r = archive->Extract(ia.data(), (UInt32)ia.size(), 0, ec);
    if (r != S_OK) { if (error) *error = SZMakeError(r == E_ABORT ? -5 : -6, r == E_ABORT ? @"Cancelled" : @"Extraction failed"); return NO; }
    return YES;
}

- (BOOL)testWithProgress:(id<SZProgressDelegate>)p error:(NSError **)error {
    if (!_isOpen) { if (error) *error = SZMakeError(-4, @"No archive open"); return NO; }
    IInArchive *archive = _arcLink->GetArchive();
    const CArc &arc = _arcLink->Arcs.Back();

    SZFolderExtractCallback *faeSpec = new SZFolderExtractCallback;
    CMyComPtr<IFolderArchiveExtractCallback> faeCallback(faeSpec);
    faeSpec->Delegate = p;

    CArchiveExtractCallback *ecs = new CArchiveExtractCallback;
    CMyComPtr<IArchiveExtractCallback> ec(ecs);

    CExtractNtOptions ntOptions;
    UStringVector removePathParts;

    ecs->InitForMulti(false, NExtract::NPathMode::kFullPaths,
        NExtract::NOverwriteMode::kOverwrite,
        NExtract::NZoneIdMode::kNone, false);
    ecs->Init(ntOptions, NULL, &arc, faeCallback,
        false, true /* testMode */, FString(), removePathParts, false,
        arc.GetEstmatedPhySize());

    HRESULT r = archive->Extract(nullptr, (UInt32)(Int32)-1, 1 /* test */, ec);
    if (r != S_OK) { if (error) *error = SZMakeError(-7, @"Archive test failed"); return NO; }
    return YES;
}

+ (BOOL)createAtPath:(NSString *)archivePath fromPaths:(NSArray<NSString *> *)src settings:(SZCompressionSettings *)s progress:(id<SZProgressDelegate>)p error:(NSError **)error {
    CCodecs *codecs = GetCodecs();
    if (!codecs) { if (error) *error = SZMakeError(-1, @"Failed to init codecs"); return NO; }
    static const char *fmts[] = {"7z","zip","tar","gzip","bzip2","xz","wim","zstd"};
    int fi = (int)s.format; if (fi < 0 || fi >= 8) fi = 0;
    int formatIndex = -1;
    for (unsigned i = 0; i < codecs->Formats.Size(); i++)
        if (codecs->Formats[i].Name.IsEqualTo_Ascii_NoCase(fmts[fi])) { formatIndex = (int)i; break; }
    if (formatIndex < 0) { if (error) *error = SZMakeError(-8, @"Unsupported format"); return NO; }

    CMyComPtr<IOutArchive> oa;
    if (codecs->CreateOutArchive((unsigned)formatIndex, oa) != S_OK || !oa)
        { if (error) *error = SZMakeError(-9, @"Cannot create handler"); return NO; }

    CMyComPtr<ISetProperties> sp; oa.QueryInterface(IID_ISetProperties, (void**)&sp);
    if (sp) {
        const wchar_t *names[] = {L"x"}; NWindows::NCOM::CPropVariant vals[1];
        vals[0] = (UInt32)s.level; sp->SetProperties(names, vals, 1);
    }

    SZUpdateCallback *cb = new SZUpdateCallback;
    CMyComPtr<IArchiveUpdateCallback2> uc(cb); cb->Delegate = p;
    if (s.password && s.encryption != SZEncryptionMethodNone) {
        cb->PasswordIsDefined = true; cb->Password = ToU(s.password); cb->EncryptHeaders = s.encryptFileNames;
    }

    for (NSString *srcPath in src) {
        NWindows::NFile::NFind::CFileInfo fi2; if (!fi2.Find(us2fs(ToU(srcPath)))) continue;
        FILETIME fmt, fct;
        FiTime_To_FILETIME(fi2.MTime, fmt);
        FiTime_To_FILETIME(fi2.CTime, fct);
        UInt32 wattr = fi2.GetWinAttrib();
        if (fi2.IsDir()) {
            UpdItem d; d.path = ToU(srcPath); d.archPath = ToU([srcPath lastPathComponent]);
            d.isDir = true; d.size = 0; d.mt = fmt; d.ct = fct; d.winAttr = wattr;
            cb->Items.Add(d);
            NSFileManager *fm = [NSFileManager defaultManager];
            NSDirectoryEnumerator *de = [fm enumeratorAtPath:srcPath]; NSString *rp;
            while ((rp = [de nextObject])) {
                NSString *fp = [srcPath stringByAppendingPathComponent:rp];
                NWindows::NFile::NFind::CFileInfo sf; if (!sf.Find(us2fs(ToU(fp)))) continue;
                FILETIME smt, sct;
                FiTime_To_FILETIME(sf.MTime, smt);
                FiTime_To_FILETIME(sf.CTime, sct);
                UpdItem it; it.path = ToU(fp);
                it.archPath = ToU([[srcPath lastPathComponent] stringByAppendingPathComponent:rp]);
                it.isDir = sf.IsDir(); it.size = sf.IsDir() ? 0 : sf.Size;
                it.mt = smt; it.ct = sct; it.winAttr = sf.GetWinAttrib(); cb->Items.Add(it);
            }
        } else {
            UpdItem it; it.path = ToU(srcPath); it.archPath = ToU([srcPath lastPathComponent]);
            it.isDir = false; it.size = fi2.Size; it.mt = fmt; it.ct = fct; it.winAttr = wattr;
            cb->Items.Add(it);
        }
    }

    COutFileStream *ofs = new COutFileStream;
    CMyComPtr<ISequentialOutStream> os(ofs);
    if (!ofs->Create_ALWAYS(us2fs(ToU(archivePath)))) { if (error) *error = SZMakeError(-10, @"Cannot create file"); return NO; }
    HRESULT r = oa->UpdateItems(os, (UInt32)cb->Items.Size(), uc);
    if (r != S_OK) { if (error) *error = SZMakeError(r == E_ABORT ? -5 : -11, r == E_ABORT ? @"Cancelled" : @"Failed"); return NO; }
    return YES;
}

+ (NSArray<SZFormatInfo *> *)supportedFormats {
    CCodecs *codecs = GetCodecs(); if (!codecs) return @[];
    NSMutableArray *arr = [NSMutableArray array];
    for (unsigned i = 0; i < codecs->Formats.Size(); i++) {
        const CArcInfoEx &ai = codecs->Formats[i];
        SZFormatInfo *info = [SZFormatInfo new]; info.name = ToNS(ai.Name);
        NSMutableArray *exts = [NSMutableArray array];
        for (unsigned j = 0; j < ai.Exts.Size(); j++) [exts addObject:ToNS(ai.Exts[j].Ext)];
        info.extensions = exts; info.canWrite = ai.UpdateEnabled; [arr addObject:info];
    }
    return arr;
}

+ (NSDictionary<NSString*,NSString*> *)calculateHashForPath:(NSString *)path algorithm:(NSString *)alg error:(NSError **)error {
    (void)path; (void)alg; if (error) *error = nil; return @{@"status": @"TODO"};
}
@end
