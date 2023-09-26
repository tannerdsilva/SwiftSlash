#ifndef CLIBSWIFTSLASH_TYPES_H
#define CLIBSWIFTSLASH_TYPES_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/// a pointer to an integer, an integer which signifies an error code for a function.
typedef int*_Nonnull err_ptr_t;

/// a pointer to a data byte buffer.
typedef uint8_t*_Nonnull data_ptr_t;

/// an abstract pointer type.
typedef void*_Nullable ptr_t;

#endif // CLIBSWIFTSLASH_TYPES_H