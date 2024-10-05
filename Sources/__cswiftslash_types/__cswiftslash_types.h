// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_TYPES_H
#define _CSWIFTSLASH_TYPES_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>
#include <math.h> // arguably this include doesn't belong in this particular file but I'm not gonna make a new header file just for this oddball include so whatever, here it is.
#include <stdlib.h>

// a non-optional pointer
typedef void*_Nonnull _cswiftslash_ptr_t;

// a constant non-optional pointer
typedef const void*_Nonnull _cswiftslash_cptr_t;

// an optional pointer
typedef void*_Nullable _cswiftslash_optr_t;

// a non-optional constant pointer
typedef const void*_Nonnull _cswiftslash_coptr_t;

#endif // _CSWIFTSLASH_TYPES_H