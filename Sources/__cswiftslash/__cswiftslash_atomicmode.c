// // LICENSE MIT
// // copyright (c) tanner silva 2024. all rights reserved.
// #include "__cswiftslash_atomicmode.h"
// #include <stdatomic.h>

// /// @brief loads the stored value from a specified atomic pointer.
// uint8_t _cswiftslash_auint8_load(_cswiftslash_atomic_uint8_t *_Nonnull encap) {
// 	return atomic_load(&encap->value);
// }

// /// @brief stores a value to a specified atomic pointer.
// void _cswiftslash_auint8_store(_cswiftslash_atomic_uint8_t *_Nonnull encap, uint8_t value) {
// 	atomic_store(&encap->value, value);
// }

// /// @brief stores a value to a specified atomic pointer if the stored value is equal to the expected value.
// bool _cswiftslash_auint8_compare_exchange_weak(_cswiftslash_atomic_uint8_t *_Nonnull encap, uint8_t *_Nonnull expected, uint8_t desired) {
// 	return atomic_compare_exchange_weak(&encap->value, expected, desired);
// }
