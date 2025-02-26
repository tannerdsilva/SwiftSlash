/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing

internal final class WhenDeinitTool<T> {
	private let conf:Confirmation
	internal let value:T
	internal init(_ value:T, _ conf:Confirmation) {
		self.conf = conf
		self.value = value
	}
	
	deinit {
		conf.confirm()
	}
}

extension WhenDeinitTool:Equatable, Hashable where T:Hashable, T:Equatable {
	static func == (lhs: WhenDeinitTool<T>, rhs: WhenDeinitTool<T>) -> Bool {
		return lhs.value == rhs.value
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(value)
	}
}
