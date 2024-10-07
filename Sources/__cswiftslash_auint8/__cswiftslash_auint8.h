/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CSWIFTSLASH_ATOMICUINT8_H
#define __CSWIFTSLASH_ATOMICUINT8_H

#include <stdint.h>
#include <stdbool.h>

/// @brief a structure that encapsulates a single (aligned) atomic uint8_t memory space.
typedef struct __cswiftslash_atomic_uint8 {

	// the stored value. NOTE: do not access or manipulate this field directly.
	uint8_t _Atomic ____v;

} __cswiftslash_atomic_uint8_t;

/// @brief initializes a new atomic uint8_t structure with a specified initial value.
/// @param initval the initial value to store in the atomic uint8_t structure before it is returned.
/// @return the initialized atomic uint8_t structure.
__cswiftslash_atomic_uint8_t __cswiftslash_auint8_init(
	const uint8_t initval
);

/// @brief loads the stored value from a specified `_cswiftslash_atomic_uint8_t` pointer. this function acts as a functional wrapper around the `atomic_load` function.
/// @param applyTo the atomic uint8_t structure to apply the operation to.
/// @return the stored value that was atomically loaded from memory.
uint8_t __cswiftslash_auint8_load(
	__cswiftslash_atomic_uint8_t *_Nonnull applyTo
);

/// @brief stores a value to a specified atomic pointer. this function acts as a functional wrapper around the `atomic_store` function.
/// @param applyTo the atomic uint8_t structure to apply the operation to.
/// @param newval the new value to store.
void __cswiftslash_auint8_store(
	__cswiftslash_atomic_uint8_t *_Nonnull applyTo,
	const uint8_t newval
);

/// @brief stores a value to a specified atomic pointer if the stored value is equal to the expected value. this function acts as a functional wrapper around the `atomic_compare_exchange_weak` function.
/// @param applyTo a pointer to the atomic uint8_t structure to apply the operation to.
/// @param expected the expected value to compare against.
/// @param newval the new value to store if the expected value is found.
/// @return whether the value was successfully stored.
bool __cswiftslash_auint8_compare_exchange_weak(
	__cswiftslash_atomic_uint8_t *_Nonnull applyTo,
	uint8_t *_Nonnull expected,
	const uint8_t newval
);

#endif // __CSWIFTSLASH_ATOMICUINT8_H