import Foundation
import Darwin

/// App-process footprint only; visionOS rendering services can allocate additional memory.
func logEmberMemory(_ context: String) {
    #if DEBUG
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to:&info) { pointer in
        pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
            task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)
        }
    }
    if result == KERN_SUCCESS {
        print("Ember memory: \(context) — app footprint \(info.phys_footprint / 1_048_576) MiB")
    }
    #endif
}
