/* LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_auint8.h"
#include <stdatomic.h>

_cswiftslash_atomic_uint8_t _cswiftslash_auint8_init(const uint8_t initval) {
	_cswiftslash_atomic_uint8_t newval = {
		.value = initval
	};
	return newval;
}

uint8_t _cswiftslash_auint8_load(_cswiftslash_atomic_uint8_t *_Nonnull applyTo) {
	return atomic_load(&applyTo->value);
}

void _cswiftslash_auint8_store(_cswiftslash_atomic_uint8_t *_Nonnull applyTo, const uint8_t value) {
	atomic_store(&applyTo->value, value);
}

bool _cswiftslash_auint8_compare_exchange_weak(_cswiftslash_atomic_uint8_t *_Nonnull applyTo, uint8_t *_Nonnull expected, const uint8_t desired) {
	return atomic_compare_exchange_weak(&applyTo->value, expected, desired);
}