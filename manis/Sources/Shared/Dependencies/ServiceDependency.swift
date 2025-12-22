import ComposableArchitecture

@MainActor
enum MihomoServiceKey: @preconcurrency DependencyKey {
    static let liveValue: any MihomoService = APIDomainMihomoServiceAdapter()
}

extension DependencyValues {
    var mihomoService: any MihomoService {
        get { self[MihomoServiceKey.self] }
        set { self[MihomoServiceKey.self] = newValue }
    }
}

@MainActor
enum SettingsServiceKey: @preconcurrency DependencyKey {
    static let liveValue: any SettingsService = SettingsManagerServiceAdapter()
}

extension DependencyValues {
    var settingsService: any SettingsService {
        get { self[SettingsServiceKey.self] }
        set { self[SettingsServiceKey.self] = newValue }
    }
}

@MainActor
enum ResourceServiceKey: @preconcurrency DependencyKey {
    static let liveValue: any ResourceService = ResourceDomainServiceAdapter()
}

extension DependencyValues {
    var resourceService: any ResourceService {
        get { self[ResourceServiceKey.self] }
        set { self[ResourceServiceKey.self] = newValue }
    }
}

@MainActor
enum PersistenceServiceKey: @preconcurrency DependencyKey {
    static let liveValue: any PersistenceService = RemoteConfigPersistenceServiceAdapter()
}

extension DependencyValues {
    var persistenceService: any PersistenceService {
        get { self[PersistenceServiceKey.self] }
        set { self[PersistenceServiceKey.self] = newValue }
    }
}

@MainActor
enum NetworkServiceKey: @preconcurrency DependencyKey {
    static let liveValue: any NetworkService = NetworkDomainServiceAdapter()
}

extension DependencyValues {
    var networkService: any NetworkService {
        get { self[NetworkServiceKey.self] }
        set { self[NetworkServiceKey.self] = newValue }
    }
}