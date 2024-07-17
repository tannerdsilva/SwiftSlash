// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_TYPES_H
#define _CSWIFTSLASH_TYPES_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// a non-optional pointer
typedef void*_Nonnull _cswiftslash_ptr_t;
typedef const void*_Nonnull _cswiftslash_cptr_t;

// an optional pointer
typedef void*_Nullable _cswiftslash_optr_t;

// a non-optional constant pointer
typedef const void*_Nonnull _cswiftslash_coptr_t;

#endif // _CSWIFTSLASH_TYPES_H