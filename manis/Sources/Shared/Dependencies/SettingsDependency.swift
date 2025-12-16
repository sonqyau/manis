import ComposableArchitecture
import Factory

struct SettingsDependency {}

enum BootstrapServiceKey: DependencyKey {
    static let liveValue = BootstrapServiceDependency(service: Container.shared
        .launchAtLoginService())
}

enum SettingsServiceKey: DependencyKey {
    static let liveValue = SettingsServiceDependency(service: Container.shared.settingsService())
}

enum PersistenceServiceKey: DependencyKey {
    static let liveValue = PersistenceServiceDependency(service: Container.shared
        .persistenceService())
}

enum NetworkServiceKey: DependencyKey {
    static let liveValue = NetworkServiceDependency(service: Container.shared.networkService())
}

enum ResourceServiceKey: DependencyKey {
    static let liveValue = ResourceServiceDependency(service: Container.shared.resourceService())
}

enum MihomoServiceKey: DependencyKey {
    static let liveValue = MihomoServiceDependency(service: Container.shared.mihomoService())
}

extension DependencyValues {
    var launchService: BootstrapService {
        get { self[BootstrapServiceKey.self].service }
        set { self[BootstrapServiceKey.self] = BootstrapServiceDependency(service: newValue) }
    }

    var settingsService: SettingsService {
        get { self[SettingsServiceKey.self].service }
        set { self[SettingsServiceKey.self] = SettingsServiceDependency(service: newValue) }
    }

    var persistenceService: PersistenceService {
        get { self[PersistenceServiceKey.self].service }
        set { self[PersistenceServiceKey.self] = PersistenceServiceDependency(service: newValue) }
    }

    var networkService: NetworkService {
        get { self[NetworkServiceKey.self].service }
        set { self[NetworkServiceKey.self] = NetworkServiceDependency(service: newValue) }
    }

    var resourceService: ResourceService {
        get { self[ResourceServiceKey.self].service }
        set { self[ResourceServiceKey.self] = ResourceServiceDependency(service: newValue) }
    }

    var mihomoService: MihomoService {
        get { self[MihomoServiceKey.self].service }
        set { self[MihomoServiceKey.self] = MihomoServiceDependency(service: newValue) }
    }
}

struct BootstrapServiceDependency: @unchecked Sendable {
    let service: BootstrapService
}

struct SettingsServiceDependency: @unchecked Sendable {
    let service: SettingsService
}

struct PersistenceServiceDependency: @unchecked Sendable {
    let service: PersistenceService
}

struct NetworkServiceDependency: @unchecked Sendable {
    let service: NetworkService
}

struct ResourceServiceDependency: @unchecked Sendable {
    let service: ResourceService
}

struct MihomoServiceDependency: @unchecked Sendable {
    let service: MihomoService
}
