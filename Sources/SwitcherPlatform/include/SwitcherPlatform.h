#ifndef SWITCHER_PLATFORM_H
#define SWITCHER_PLATFORM_H
#include <stddef.h>
#include <stdint.h>
// Platform primitives only; account policy is implemented in Swift.
uint32_t switcher_restrict_path(const char *utf8_path, int directory);
uint32_t switcher_atomic_write(const char *utf8_path, const void *bytes, size_t count);
uint32_t switcher_check_path(const char *utf8_path);
#endif
