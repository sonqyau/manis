import Foundation

ProcessInfo.processInfo.disableSuddenTermination()

let helper = MainDaemon()

helper.run()
