import Foundation

//this is the queue that acts as the 'workload root' for the sub-queues that make up the SwiftSlash workload
let swiftslashCaptainQueue = DispatchQueue(label:"com.swiftslash.global.captain", attributes:[.concurrent])

//file handles and pipes are created and closed using this queue
let fileHandleQueue = DispatchQueue(label:"com.swiftslash.global.fh_admin", target:swiftslashCaptainQueue)