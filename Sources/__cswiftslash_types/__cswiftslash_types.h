/* LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef _CSWIFTSLASH_TYPES_H
#define _CSWIFTSLASH_TYPES_H

/// @brief a non-optional pointer
typedef void*_Nonnull _cswiftslash_ptr_t;

/// @brief a constant non-optional pointer
typedef const void*_Nonnull _cswiftslash_cptr_t;

/// @brief an optional pointer
typedef void*_Nullable _cswiftslash_optr_t;

/// @brief a constant optional pointer
typedef const void*_Nonnull _cswiftslash_coptr_t;

#endif // _CSWIFTSLASH_TYPES_H