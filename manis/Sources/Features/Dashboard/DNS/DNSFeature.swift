import ComposableArchitecture
import Foundation

@MainActor
struct DNSFeature: @preconcurrency Reducer {
    @ObservableState
    struct State {
        var domain: String = ""
        var recordType: String = "A"
        var recordTypes: [String] = ["A", "AAAA", "CNAME", "MX", "TXT", "NS"]
        var queryResult: DNSQueryResponse?
        var isQuerying: Bool = false
        var isFlushingCache: Bool = false
        var alert: AlertState<AlertAction>?
    }

    enum AlertAction: Equatable, DismissibleAlertAction {
        case dismissError
    }

    @CasePathable
    enum Action {
        case updateDomain(String)
        case selectRecordType(String)
        case performQuery
        case queryFinished(Result<DNSQueryResponse, Error>)
        case flushDNSCache
        case flushDNSCacheFinished(Result<Void, Error>)
        case alert(AlertAction)
    }

    @Dependency(\.mihomoService)
    var mihomoService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .updateDomain(domain):
                state.domain = domain
                return .none

            case let .selectRecordType(type):
                if state.recordType != type {
                    state.recordType = type
                }
                return .none

            case .performQuery:
                guard !state.domain.isEmpty, !state.isQuerying else {
                    return .none
                }
                state.isQuerying = true
                state.alert = nil

                let domain = state.domain
                let recordType = state.recordType
                let service = mihomoService

                return .run { @MainActor send in
                    do {
                        let result = try await service.queryDNS(name: domain, type: recordType)
                        send(.queryFinished(.success(result)))
                    } catch {
                        send(.queryFinished(.failure(error)))
                    }
                }

            case let .queryFinished(result):
                state.isQuerying = false
                switch result {
                case let .success(response):
                    state.queryResult = response

                case let .failure(error):
                    state.alert = .error(error)
                    state.queryResult = nil
                }
                return .none

            case .flushDNSCache:
                guard !state.isFlushingCache else {
                    return .none
                }
                state.isFlushingCache = true
                state.alert = nil

                let service = mihomoService

                return .run { @MainActor send in
                    do {
                        try await service.flushDNSCache()
                        send(.flushDNSCacheFinished(.success(())))
                    } catch {
                        send(.flushDNSCacheFinished(.failure(error)))
                    }
                }

            case let .flushDNSCacheFinished(result):
                state.isFlushingCache = false
                switch result {
                case .success:
                    break

                case let .failure(error):
                    state.alert = .error(error)
                }
                return .none

            case .alert(.dismissError):
                state.alert = nil
                return .none
            }
        }
    }

    init() {}
}
