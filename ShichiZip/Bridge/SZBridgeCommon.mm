// SZBridgeCommon.mm — Shared bridge infrastructure (codecs, password, GUIDs)

// This TU defines INITGUID so all IID constants are instantiated here
#define INITGUID

#include "SZBridgeCommon.h"

#import "../Dialogs/SZDialogPresenter.h"

NSString * const SZArchiveErrorDomain = @"SZArchiveErrorDomain";

// ============================================================
// Codec manager singleton
// ============================================================

static CCodecs *g_Codecs = nullptr;
static bool g_CodecsInitialized = false;

CCodecs *SZGetCodecs() {
    if (!g_CodecsInitialized) {
        CrcGenerateTable();
        g_Codecs = new CCodecs;
        if (g_Codecs->Load() != S_OK) { delete g_Codecs; g_Codecs = nullptr; }
        g_CodecsInitialized = true;
    }
    return g_Codecs;
}

// ============================================================
// Password prompt
// ============================================================

static SZDialogStyle SZDialogStyleForPromptStyle(SZOperationPromptStyle style) {
    switch (style) {
        case SZOperationPromptStyleWarning:
            return SZDialogStyleWarning;
        case SZOperationPromptStyleCritical:
            return SZDialogStyleCritical;
        case SZOperationPromptStyleInformational:
        default:
            return SZDialogStyleInformational;
    }
}

SZOperationSession *SZCreateDefaultOperationSession(id<SZProgressDelegate> progressDelegate) {
    SZOperationSession *session = [SZOperationSession new];
    session.progressDelegate = progressDelegate;
    session.passwordRequestHandler = ^BOOL(NSString *title,
                                           NSString *message,
                                           NSString *initialValue,
                                           NSString * _Nullable * _Nullable password) {
        return [SZDialogPresenter promptForPasswordWithTitle:title
                                                     message:message
                                                initialValue:initialValue
                                                     password:password];
    };
    session.choiceRequestHandler = ^NSInteger(SZOperationPromptStyle style,
                                              NSString *title,
                                              NSString *message,
                                              NSArray<NSString *> *buttonTitles) {
        return [SZDialogPresenter runMessageWithStyle:SZDialogStyleForPromptStyle(style)
                                                title:title
                                              message:message
                                         buttonTitles:buttonTitles];
    };
    return session;
}

HRESULT SZPromptForPassword(SZOperationSession *session, UString &outPassword, bool &wasDefined, NSString *context) {
    NSString *message = context.length > 0
        ? [NSString stringWithFormat:@"Enter password for \"%@\".", context]
        : @"This archive is encrypted. Enter password.";
    NSString *initialValue = wasDefined ? ToNS(outPassword) : nil;
    __block NSString *result = @"";
    BOOL confirmed = NO;

    if (session) {
        confirmed = [session requestPasswordWithTitle:@"Password Required"
                                              message:message
                                         initialValue:initialValue
                                             password:&result];
    } else {
        confirmed = [SZDialogPresenter promptForPasswordWithTitle:@"Password Required"
                                                          message:message
                                                     initialValue:initialValue
                                                          password:&result];
    }

    if (confirmed) {
        outPassword = ToU(result ?: @"");
        wasDefined = true;
        return S_OK;
    }
    return E_ABORT;
}
