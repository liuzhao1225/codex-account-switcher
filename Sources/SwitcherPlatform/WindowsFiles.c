#include "SwitcherPlatform.h"
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <sddl.h>
#include <aclapi.h>
#include <objbase.h>
#include <wchar.h>
#include <stdlib.h>

uint32_t switcher_sha256(const void *bytes, size_t count, uint8_t digest[32]) {
    if (!bytes || !digest || count > UINT32_MAX) return ERROR_INVALID_PARAMETER;
    BCRYPT_ALG_HANDLE algorithm = NULL;
    NTSTATUS status = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, NULL, 0);
    if (status >= 0) {
        status = BCryptHash(algorithm, NULL, 0, (PUCHAR)bytes, (ULONG)count, digest, 32);
        BCryptCloseAlgorithmProvider(algorithm, 0);
    }
    return status >= 0 ? 0 : (uint32_t)status;
}

static wchar_t *wide_path(const char *path) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!count) return NULL;
    wchar_t *result = calloc((size_t)count, sizeof(wchar_t));
    if (!result) { SetLastError(ERROR_OUTOFMEMORY); return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, result, count)) { free(result); return NULL; }
    return result;
}

// Reject reparse points on the target path and its local storage components (up to 4 trailing
// levels), without breaking machines whose user profile or AppData root lives on a junction/Dev Drive.
static DWORD check_path(const wchar_t *path) {
    DWORD size = GetFullPathNameW(path, 0, NULL, NULL);
    if (!size) return GetLastError();
    wchar_t *full = calloc((size_t)size + 1, sizeof(wchar_t));
    if (!full) return ERROR_OUTOFMEMORY;
    if (!GetFullPathNameW(path, size, full, NULL)) { DWORD error = GetLastError(); free(full); return error; }

    size_t length = wcslen(full);
    size_t separators[8];
    size_t sep_count = 0;
    for (size_t i = 3; i <= length; i++) {
        if (full[i] == L'\\' || full[i] == L'/' || full[i] == L'\0') {
            if (sep_count < 8) {
                separators[sep_count++] = i;
            } else {
                memmove(separators, separators + 1, 7 * sizeof(size_t));
                separators[7] = i;
            }
        }
    }
    size_t start_idx = sep_count > 4 ? sep_count - 4 : 0;
    DWORD error = ERROR_SUCCESS;
    for (size_t k = start_idx; k < sep_count; k++) {
        size_t pos = separators[k];
        wchar_t delimiter = full[pos];
        full[pos] = L'\0';
        DWORD attributes = GetFileAttributesW(full);
        if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
            error = ERROR_REPARSE_TAG_INVALID;
        }
        full[pos] = delimiter;
        if (error) break;
    }
    free(full);
    return error;
}

static wchar_t *extended_path(const wchar_t *path) {
    DWORD size = GetFullPathNameW(path, 0, NULL, NULL);
    if (!size) return NULL;
    wchar_t *full = calloc((size_t)size, sizeof(wchar_t));
    if (!full) { SetLastError(ERROR_OUTOFMEMORY); return NULL; }
    DWORD length = GetFullPathNameW(path, size, full, NULL);
    if (!length || length >= size) {
        DWORD error = length ? ERROR_INSUFFICIENT_BUFFER : GetLastError();
        free(full); SetLastError(error); return NULL;
    }
    for (DWORD i = 0; i < length; i++) if (full[i] == L'/') full[i] = L'\\';
    if (wcsncmp(full, L"\\\\?\\", 4) == 0) return full;
    int unc = wcsncmp(full, L"\\\\", 2) == 0;
    const wchar_t *prefix = unc ? L"\\\\?\\UNC\\" : L"\\\\?\\";
    const wchar_t *suffix = full + (unc ? 2 : 0);
    size_t count = wcslen(prefix) + wcslen(suffix) + 1;
    wchar_t *extended = calloc(count, sizeof(wchar_t));
    if (extended) swprintf(extended, count, L"%ls%ls", prefix, suffix);
    free(full);
    if (!extended) SetLastError(ERROR_OUTOFMEMORY);
    return extended;
}

static wchar_t *child_path(const wchar_t *directory, const wchar_t *name) {
    size_t count = wcslen(directory) + wcslen(name) + 2;
    wchar_t *child = calloc(count, sizeof(wchar_t));
    if (child) swprintf(child, count, L"%ls\\%ls", directory, name);
    return child;
}

// Preflight and remove using direct entry attributes without O(depth) GetFullPathNameW per file.
static DWORD walk_directory(const wchar_t *path, int remove) {
    DWORD attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES) return GetLastError();
    if (attributes & FILE_ATTRIBUTE_REPARSE_POINT) return ERROR_REPARSE_TAG_INVALID;
    if (!(attributes & FILE_ATTRIBUTE_DIRECTORY)) return ERROR_DIRECTORY;

    wchar_t *pattern = child_path(path, L"*");
    if (!pattern) return ERROR_OUTOFMEMORY;
    WIN32_FIND_DATAW entry;
    HANDLE search = FindFirstFileW(pattern, &entry);
    DWORD error = search == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;
    free(pattern);
    if (search == INVALID_HANDLE_VALUE) {
        if (error != ERROR_FILE_NOT_FOUND) return error;
    } else {
        do {
            if (wcscmp(entry.cFileName, L".") == 0 || wcscmp(entry.cFileName, L"..") == 0) continue;
            if (entry.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
                error = ERROR_REPARSE_TAG_INVALID;
                break;
            }
            wchar_t *child = child_path(path, entry.cFileName);
            if (!child) { error = ERROR_OUTOFMEMORY; break; }
            DWORD current = GetFileAttributesW(child);
            if (current == INVALID_FILE_ATTRIBUTES) error = GetLastError();
            else if (current & FILE_ATTRIBUTE_REPARSE_POINT) error = ERROR_REPARSE_TAG_INVALID;
            else if (current & FILE_ATTRIBUTE_DIRECTORY) {
                error = walk_directory(child, remove);
            } else if (remove) {
                if ((current & FILE_ATTRIBUTE_READONLY) &&
                    !SetFileAttributesW(child, current & ~FILE_ATTRIBUTE_READONLY)) error = GetLastError();
                if (!error && !DeleteFileW(child)) error = GetLastError();
            }
            free(child);
            if (error) break;
        } while (FindNextFileW(search, &entry));
        if (!error) {
            DWORD last = GetLastError();
            if (last != ERROR_NO_MORE_FILES) error = last;
        }
        FindClose(search);
        if (error) return error;
    }
    if (remove && !RemoveDirectoryW(path)) return GetLastError();
    return ERROR_SUCCESS;
}

uint32_t switcher_remove_directory(const char *utf8_path) {
    wchar_t *path = wide_path(utf8_path);
    if (!path) return GetLastError();
    DWORD error = check_path(path);
    wchar_t *extended = error ? NULL : extended_path(path);
    if (!error && !extended) error = GetLastError();
    free(path);
    if (!error) error = walk_directory(extended, 0);
    if (!error) error = walk_directory(extended, 1);
    free(extended);
    return error;
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
uint32_t switcher_remove_directory(const char *path) { (void)path; return 0; }
#endif
