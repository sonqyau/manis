import Foundation

protocol MainLogService {
    func logger(for category: LogCategory) -> CategoryLogger
    func log(_ message: String, level: MainLogLevel, category: LogCategory)
}

struct MainLogServiceAdapter: MainLogService {
    private let logging: MainLog

    init(logging: MainLog = .shared) {
        self.logging = logging
    }

    func logger(for category: LogCategory) -> CategoryLogger {
        logging.logger(for: category)
    }

    func log(_ message: String, level: MainLogLevel, category: LogCategory) {
        logging.log(message, level: level, category: category)
    }
}
