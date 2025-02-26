/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing

extension Tag {
	@Tag internal static var __cswiftslash:Self
}

@Suite("__cswiftslash_tests",
	.serialized,
	.tags(.__cswiftslash)
)
internal struct __cswiftslash_tests {}