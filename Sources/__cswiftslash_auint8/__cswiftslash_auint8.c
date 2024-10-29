/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_auint8.h"
#include <stdatomic.h>

__cswiftslash_atomic_uint8_t __cswiftslash_auint8_init(const uint8_t _) {
	__cswiftslash_atomic_uint8_t r = {
		._ = _
	};
	return r;
}

uint8_t __cswiftslash_auint8_load(__cswiftslash_atomic_uint8_t *_Nonnull _) {
	return atomic_load(&_->_);
}

void __cswiftslash_auint8_store(__cswiftslash_atomic_uint8_t *_Nonnull _, const uint8_t ____s) {
	atomic_store(&_->_, ____s);
}

bool __cswiftslash_auint8_compare_exchange_weak(__cswiftslash_atomic_uint8_t *_Nonnull _, uint8_t *_Nonnull ____e, const uint8_t ____s) {
	return atomic_compare_exchange_weak(&_->_, ____e, ____s);
}

uint8_t __cswiftslash_auint8_increment(__cswiftslash_atomic_uint8_t *_Nonnull _, const uint8_t __) {
	return atomic_fetch_add(&_->_, __);
}