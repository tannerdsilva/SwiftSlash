import Foundation

extension timeval:Comparable {
	//MARK: Equatable functions
	public static func == (lhs:timeval, rhs:timeval) -> Bool {
		return (lhs.tv_sec == rhs.tv_sec) && (lhs.tv_usec == rhs.tv_usec)
	}
	
	func hash(into hasher:inout Hasher) {
		hasher.combine(self.tv_sec)
		hasher.combine(self.tv_usec)
	}
	
	//MARK: Comparable functions
	public static func < (lhs:timeval, rhs:timeval) -> Bool {
		if (lhs.tv_sec == rhs.tv_sec) {
			if (lhs.tv_usec < rhs.tv_usec) {
				return true
			}
		} else if (lhs.tv_sec < rhs.tv_sec) {
			return true
		}
		return false
	}
	
	public static func <= (lhs:timeval, rhs:timeval) -> Bool {
		if (lhs.tv_sec == rhs.tv_sec) {
			if (lhs.tv_usec <= rhs.tv_usec) {
				return true
			}
		} else if (lhs.tv_sec <= rhs.tv_sec) {
			return true
		}
		return false
	}
	
	public static func > (lhs:timeval, rhs:timeval) -> Bool {
		if (lhs.tv_sec == rhs.tv_sec) {
			if (lhs.tv_sec > rhs.tv_sec) {
				return true
			}
		} else if (lhs.tv_sec > rhs.tv_sec) {
			return true
		}
		return false
	}
	
	public static func >= (lhs:timeval, rhs:timeval) -> Bool {
		if (lhs.tv_sec == rhs.tv_sec) {
			if (lhs.tv_sec >= rhs.tv_sec) {
				return true
			}
		} else if (lhs.tv_sec >= rhs.tv_sec) {
			return true
		}
		return false
	}
}