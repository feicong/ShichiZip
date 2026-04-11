// SZBridgeCommon.mm — Shared bridge infrastructure (codecs, password, GUIDs)

// This TU defines INITGUID so all IID constants are instantiated here
#define INITGUID

#include "SZBridgeCommon.h"

NSString* const SZArchiveErrorDomain = @"SZArchiveErrorDomain";

// ============================================================
// Codec manager singleton
// ============================================================

CCodecs* _Nullable SZGetCodecs() {
    static CCodecs* codecs = []() -> CCodecs* {
        CrcGenerateTable();

        CCodecs* loadedCodecs = new CCodecs;
        if (loadedCodecs->Load() != S_OK) {
            delete loadedCodecs;
            return nullptr;
        }

        return loadedCodecs;
    }();

    return codecs;
}
