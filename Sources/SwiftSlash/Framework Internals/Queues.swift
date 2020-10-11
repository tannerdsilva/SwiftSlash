import Foundation

internal let process_master_queue = DispatchQueue(label:"com.swiftslash.global.process", attributes:[.concurrent])
internal let file_handle_guard = DispatchQueue(label:"com.swiftslash.global.filehandle.sync", target:process_master_queue)
