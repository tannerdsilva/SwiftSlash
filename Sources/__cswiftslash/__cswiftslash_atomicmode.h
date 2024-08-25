// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_ATOMICMODE_H
#define _CSWIFTSLASH_ATOMICMODE_H

#include "__cswiftslash_types.h"

/// @brief a structure that encapsulates an atomic uint8_t.
typedef struct _cswiftslash_atomic_uint8 {
	uint8_t _Atomic value;
} _cswiftslash_atomic_uint8_t;

/// @brief loads the stored value from a specified `_cswiftslash_atomic_uint8_t` pointer.
/// @return the stored value.
uint8_t _cswiftslash_auint8_load(_cswiftslash_atomic_uint8_t* _Nonnull);

/// @brief stores a value to a specified atomic pointer.
void _cswiftslash_auint8_store(_cswiftslash_atomic_uint8_t* _Nonnull, uint8_t);

/// @brief stores a value to a specified atomic pointer if the stored value is equal to the expected value.
bool _cswiftslash_auint8_compare_exchange_weak(_cswiftslash_atomic_uint8_t* _Nonnull, uint8_t* _Nonnull, uint8_t);

#endif // _CSWIFTSLASH_ATOMICMODE_H