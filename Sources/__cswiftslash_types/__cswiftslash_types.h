/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CSWIFTSLASH_TYPES_H
#define __CSWIFTSLASH_TYPES_H

/// a non-optional pointer
typedef void*_Nonnull __cswiftslash_ptr_t;

/// a constant non-optional pointer
typedef const void*_Nonnull __cswiftslash_cptr_t;

/// an optional pointer
typedef void*_Nullable __cswiftslash_optr_t;

/// a constant optional pointer
typedef const void*_Nonnull __cswiftslash_coptr_t;

#endif // __CSWIFTSLASH_TYPES_H