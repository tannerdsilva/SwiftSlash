// extension Future {
// 	internal struct AwaitResult {
// 		private let cont:UnsafeMutablePointer<UnsafeContinuation<R, Swift.Error>>
// 		private init(_ cont:UnsafeMutablePointer<UnsafeContinuation<R, Swift.Error>>) {
// 			self.cont = cont
// 		}
// 		internal static func expose(_ cont:consuming UnsafeContinuation<R, Swift.Error>, _ handlerF:(UnsafeMutableRawPointer) -> Void) {
// 			withUnsafeMutablePointer(to:&cont) {
// 				var newSelf = AwaitResult($0)
// 				withUnsafeMutablePointer(to:&newSelf) {
// 					handlerF($0)
// 				}
// 			}
// 		}
// 		internal borrowing func resume(returning result:consuming R) {
// 			cont.pointee.resume(returning:result)
// 		}
// 		internal borrowing func resume(throwing error:consuming Swift.Error) {
// 			cont.pointee.resume(throwing:error)
// 		}
// 	}
// }