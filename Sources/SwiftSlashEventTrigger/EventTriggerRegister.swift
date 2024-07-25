import __cswiftslash
import SwiftSlashFIFO

internal enum Register:Equatable, Hashable {

	/// register a reader.
	/// - parameters:
	/// 	- Int32: the file handle to register.
	/// 	- FIFO<Array<[UInt8]>: the fifo to write data to after it is captured from the file handle.
	case reader(Int32, FIFO<size_t>)


	/// register a writer.
	/// - parameters:
	/// 	- Int32: the file handle to register.
	/// 	- FIFO<[UInt8]>: the fifo to read data from to write to the file handle.
	case writer(Int32, FIFO<Void>)

	/// equatable implementation
	internal static func == (lhs:Register, rhs:Register) -> Bool {
		switch (lhs, rhs) {
			case (.reader(let l1, _), .reader(let r1, _)):
				return l1 == r1
			case (.writer(let l1, _), .writer(let r1, _)):
				return l1 == r1
			default:
				return false
		}
	}

	/// hashable implementation
	internal func hash(into hasher:inout Hasher) {
		switch self {
			case .reader(let i, _):
				hasher.combine(i)
			case .writer(let i, _):
				hasher.combine(i)
		}
	}
}