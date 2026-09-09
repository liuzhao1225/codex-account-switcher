#include "SwitcherPlatform.h"
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <aclapi.h>
#include <objbase.h>
#include <wchar.h>
#include <stdlib.h>

static wchar_t *wide_path(const char *path) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!count) return NULL;
    wchar_t *result = calloc((size_t)count, sizeof(wchar_t));
    if (!result) { SetLastError(ERROR_OUTOFMEMORY); return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, result, count)) { free(result); return NULL; }
    return result;
}

static DWORD check_path(const wchar_t *path) {
    DWORD size = GetFullPathNameW(path, 0, NULL, NULL);
    if (!size) return GetLastError();
    wchar_t *full = calloc((size_t)size + 1, sizeof(wchar_t));
    if (!full) return ERROR_OUTOFMEMORY;
    if (!GetFullPathNameW(path, size, full, NULL)) { DWORD error = GetLastError(); free(full); return error; }
    DWORD error = ERROR_SUCCESS;
    size_t length = wcslen(full);
    for (size_t i = 3; i <= length; i++) {
        if (full[i] != L'\\' && full[i] != L'/' && full[i] != L'\0') continue;
        wchar_t delimiter = full[i]; full[i] = L'\0';
        DWORD attributes = GetFileAttributesW(full);
        if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) error = ERROR_REPARSE_TAG_INVALID;
        full[i] = delimiter;
        if (error) break;
    }
    free(full); return error;
}

static DWORD private_descriptor(PSECURITY_DESCRIPTOR *descriptor, int directory) {
    HANDLE token = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return GetLastError();
    DWORD count = 0;
    GetTokenInformation(token, TokenUser, NULL, 0, &count);
    TOKEN_USER *user = malloc(count);
    if (!user) { CloseHandle(token); return ERROR_OUTOFMEMORY; }
    if (!GetTokenInformation(token, TokenUser, user, count, &count)) {
        DWORD error = GetLastError(); free(user); CloseHandle(token); return error;
    }
    LPWSTR sid = NULL;
    if (!ConvertSidToStringSidW(user->User.Sid, &sid)) {
        DWORD error = GetLastError(); free(user); CloseHandle(token); return error;
    }
    wchar_t sddl[256];
    swprintf(sddl, 256, directory ? L"D:P(A;OICI;FA;;;%ls)" : L"D:P(A;;FA;;;%ls)", sid);
    DWORD error = ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, SDDL_REVISION_1, descriptor, NULL)
        ? ERROR_SUCCESS : GetLastError();
    LocalFree(sid); free(user); CloseHandle(token); return error;
}

uint32_t switcher_check_path(const char *utf8_path) {
    wchar_t *path = wide_path(utf8_path);
    if (!path) return GetLastError();
    DWORD error = check_path(path); free(path); return error;
}

uint32_t switcher_restrict_path(const char *utf8_path, int directory) {
    wchar_t *path = wide_path(utf8_path);
    if (!path) return GetLastError();
    DWORD error = check_path(path);
    PSECURITY_DESCRIPTOR descriptor = NULL;
    if (!error) error = private_descriptor(&descriptor, directory);
    if (!error && !SetFileSecurityW(path, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, descriptor)) error = GetLastError();
    if (descriptor) LocalFree(descriptor);
    free(path); return error;
}

uint32_t switcher_atomic_write(const char *utf8_path, const void *bytes, size_t count) {
    wchar_t *path = wide_path(utf8_path);
    if (!path) return GetLastError();
    DWORD error = check_path(path);
    PSECURITY_DESCRIPTOR descriptor = NULL;
    if (!error) error = private_descriptor(&descriptor, 0);
    wchar_t *temporary = NULL;
    HANDLE file = INVALID_HANDLE_VALUE;
    if (!error) {
        GUID id; HRESULT result = CoCreateGuid(&id);
        if (FAILED(result)) error = ERROR_GEN_FAILURE;
        else {
            size_t size = wcslen(path) + 64;
            temporary = calloc(size, sizeof(wchar_t));
            if (!temporary) error = ERROR_OUTOFMEMORY;
            else {
                swprintf(temporary, size, L"%ls.switcher-%08lx%04x%04x%02x%02x%02x%02x%02x%02x%02x%02x.tmp", path,
                    id.Data1, id.Data2, id.Data3, id.Data4[0], id.Data4[1], id.Data4[2], id.Data4[3], id.Data4[4], id.Data4[5], id.Data4[6], id.Data4[7]);
                SECURITY_ATTRIBUTES security = { sizeof(security), descriptor, FALSE };
                file = CreateFileW(temporary, GENERIC_WRITE, 0, &security, CREATE_NEW, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, NULL);
                if (file == INVALID_HANDLE_VALUE) error = GetLastError();
            }
        }
    }
    if (!error) {
        size_t offset = 0;
        while (offset < count) {
            DWORD requested = (DWORD)((count - offset) > MAXDWORD ? MAXDWORD : count - offset), written = 0;
            if (!WriteFile(file, (const char *)bytes + offset, requested, &written, NULL) || !written) { error = GetLastError(); if (!error) error = ERROR_WRITE_FAULT; break; }
            offset += written;
        }
        if (!error && !FlushFileBuffers(file)) error = GetLastError();
    }
    if (file != INVALID_HANDLE_VALUE) { if (!CloseHandle(file) && !error) error = GetLastError(); }
    if (!error && !MoveFileExW(temporary, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) error = GetLastError();
    if (temporary) { if (error) DeleteFileW(temporary); free(temporary); }
    if (descriptor) LocalFree(descriptor);
    free(path); return error;
}
#else
uint32_t switcher_restrict_path(const char *path, int directory) { (void)path; (void)directory; return 0; }
uint32_t switcher_atomic_write(const char *path, const void *bytes, size_t count) { (void)path; (void)bytes; (void)count; return 0; }
uint32_t switcher_check_path(const char *path) { (void)path; return 0; }
#endif
