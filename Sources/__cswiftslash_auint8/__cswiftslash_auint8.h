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

/// a structure that encapsulates a single (aligned) atomic uint8_t memory space.
typedef struct __cswiftslash_atomic_uint8 {

	// the stored value. NOTE: do not access or manipulate this field directly.
	uint8_t _Atomic ____v;

} __cswiftslash_atomic_uint8_t;

/// initializes a new atomic uint8_t structure with a specified initial value.
/// @param _ the initial value to store in the atomic uint8_t structure before it is returned.
/// @return the initialized atomic uint8_t structure.
__cswiftslash_atomic_uint8_t __cswiftslash_auint8_init(
	const uint8_t _
);

/// loads the stored value, given a pointer to an atomic structure.
/// @param _ a pointer to the atomic uint8_t structure to apply the operation to.
/// @return the stored value that was atomically loaded from memory.
uint8_t __cswiftslash_auint8_load(
	__cswiftslash_atomic_uint8_t *_Nonnull _
);

/// stores a value to a specified atomic pointer. this function acts as a functional wrapper around the `atomic_store` function.
/// @param _ a pointer to the atomic uint8_t structure to apply the operation to.
/// @param ____s the new value to store.
void __cswiftslash_auint8_store(
	__cswiftslash_atomic_uint8_t *_Nonnull _,
	const uint8_t ____s
);

/// stores a value to a specified atomic pointer if the stored value is equal to the expected value. this function acts as a functional wrapper around the `atomic_compare_exchange_weak` function.
/// @param _ a pointer to the atomic uint8_t structure to apply the operation to.
/// @param __ the expected value to compare against.
/// @param ___ the new value to store if the expected value is found.
/// @return whether the value was successfully stored.
bool __cswiftslash_auint8_compare_exchange_weak(
	__cswiftslash_atomic_uint8_t *_Nonnull _,
	uint8_t *_Nonnull ____e,
	const uint8_t ____s
);

/// atomically increments the stored value by one.
/// @param _ a pointer to the atomic uint8_t structure to apply the operation to.
/// @param __ the value to increment by.
/// @return the originally stored value.
uint8_t __cswiftslash_auint8_increment(
	__cswiftslash_atomic_uint8_t *_Nonnull _,
	const uint8_t __
);

#endif // __CSWIFTSLASH_ATOMICUINT8_H