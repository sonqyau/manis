import Factory

struct ServiceDependency {}

extension Container {
    var mihomoService: Factory<MihomoService> {
        self { @MainActor in APIDomainMihomoServiceAdapter() }.shared
    }

    var launchAtLoginService: Factory<BootstrapService> {
        self { @MainActor in BootstrapManagerServiceAdapter() }.shared
    }

    var settingsService: Factory<SettingsService> {
        self { @MainActor in SettingsManagerServiceAdapter() }.shared
    }

    var persistenceService: Factory<PersistenceService> {
        self { @MainActor in RemoteConfigPersistenceServiceAdapter() }.shared
    }

    var resourceService: Factory<ResourceService> {
        self { @MainActor in ResourceDomainServiceAdapter() }.shared
    }

    var networkService: Factory<NetworkService> {
        self { @MainActor in NetworkDomainServiceAdapter() }.shared
    }
}
