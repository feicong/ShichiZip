// SZBridgeCommon.mm — Shared bridge infrastructure (codecs, password, GUIDs)

// This TU defines INITGUID so all IID constants are instantiated here
#define INITGUID

#include "SZBridgeCommon.h"

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
