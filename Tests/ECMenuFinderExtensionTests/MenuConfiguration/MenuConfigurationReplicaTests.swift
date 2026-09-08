import Foundation
import XCTest
@testable import ECMenuFinderExtension

/// 验证配置更新信号只形成单飞拉取，且过时响应不会覆盖最终真相。
@MainActor
final class MenuConfigurationReplicaTests: XCTestCase {
    func testFailedRefreshPreservesCacheAndNextSignalCanRefresh() async throws {
        let suiteName = "MenuConfigurationReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let template = FileTemplateMenuItem(id: FileTemplateID(), displayName: "Notes")
        let cached = MenuConfigurationSnapshot(
            configuration: MenuConfiguration(isEnabled: false),
            fileTemplates: [template]
        )
        let cachedData = MenuConfigurationSnapshotCache.encode(cached)
        defaults.set(cachedData, forKey: MenuConfigurationSnapshotCache.key)
        let transport = ControlledMenuConfigurationTransport()
        let replica = MenuConfigurationReplica(defaults: defaults, transport: transport)

        transport.completeNext(with: .failure(ApplicationIPCError.deadlineExceeded))
        await waitForRefresh(in: replica)
        XCTAssertFalse(replica.isEnabled)
        XCTAssertEqual(replica.fileTemplates, [template])
        XCTAssertEqual(defaults.data(forKey: MenuConfigurationSnapshotCache.key), cachedData)
        replica.refreshConfiguration()
        await waitForRequestCount(2, in: transport)
        XCTAssertFalse(replica.isEnabled)
        XCTAssertEqual(replica.fileTemplates, [template])
        XCTAssertEqual(defaults.data(forKey: MenuConfigurationSnapshotCache.key), cachedData)

        transport.completeNext(with: .success(.standard))
        await waitForRefresh(in: replica)
        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.fileTemplates.isEmpty)
        let stored = try XCTUnwrap(defaults.data(forKey: MenuConfigurationSnapshotCache.key))
        XCTAssertEqual(try MenuConfigurationSnapshotCache.decode(stored), .standard)
    }

    func testInvalidCacheStartsWithStandardConfigurationWhenTransportIsUnavailable() throws {
        let suiteName = "MenuConfigurationReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("{}".utf8), forKey: MenuConfigurationSnapshotCache.key)
        let replica = MenuConfigurationReplica(defaults: defaults, transport: nil)
        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.fileTemplates.isEmpty)
        replica.refreshConfiguration()
        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.fileTemplates.isEmpty)
    }

    /// 旧扩展缓存只迁移已有开关；真实模板库必须由主应用发布。
    func testLegacyCacheMigratesVisibilityWithoutInventingTemplates() throws {
        let suiteName = "MenuConfigurationReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = MenuConfiguration(
            isEnabled: false,
            hiddenFeatureIDs: ["new-text-file"]
        )
        defaults.set(
            MenuConfigurationChannel.encodedData(for: legacy),
            forKey: MenuConfigurationChannel.persistedConfigurationKey
        )

        let replica = MenuConfigurationReplica(defaults: defaults, transport: nil)

        XCTAssertFalse(replica.isEnabled)
        XCTAssertFalse(replica.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertTrue(replica.fileTemplates.isEmpty)
        XCTAssertNil(defaults.object(forKey: MenuConfigurationChannel.persistedConfigurationKey))
        let stored = try XCTUnwrap(defaults.data(forKey: MenuConfigurationSnapshotCache.key))
        XCTAssertEqual(
            try MenuConfigurationSnapshotCache.decode(stored),
            MenuConfigurationSnapshot(configuration: legacy, fileTemplateState: .unavailable)
        )
    }

    /// 同名模板以独立身份和原顺序恢复，已有新版快照优先于旧缓存。
    func testSnapshotCacheRestoresDuplicateNamesAndDistinctIdentities() throws {
        let suiteName = "MenuConfigurationReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let templates = [
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
        ]
        let snapshot = MenuConfigurationSnapshot(
            configuration: .standard,
            fileTemplates: templates
        )
        defaults.set(
            MenuConfigurationSnapshotCache.encode(snapshot),
            forKey: MenuConfigurationSnapshotCache.key
        )
        defaults.set(
            MenuConfigurationChannel.encodedData(for: MenuConfiguration(isEnabled: false)),
            forKey: MenuConfigurationChannel.persistedConfigurationKey
        )

        let replica = MenuConfigurationReplica(defaults: defaults, transport: nil)

        XCTAssertTrue(replica.isEnabled)
        XCTAssertEqual(replica.fileTemplates, templates)
        XCTAssertEqual(replica.fileTemplates.map(\.displayName), ["TXT", "TXT"])
        XCTAssertNotEqual(replica.fileTemplates[0].id, replica.fileTemplates[1].id)
    }

    func testConcurrentRefreshSignalsCoalesceAndSkipStaleResponse() async throws {
        let suiteName = "MenuConfigurationReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let transport = ControlledMenuConfigurationTransport()
        let replica = MenuConfigurationReplica(
            defaults: defaults,
            transport: transport
        )
        XCTAssertEqual(transport.requestCount, 1)

        replica.refreshConfiguration()
        replica.refreshConfiguration()
        XCTAssertEqual(transport.requestCount, 1)

        let stale = MenuConfigurationSnapshot(
            configuration: MenuConfiguration(isEnabled: false),
            fileTemplates: [FileTemplateMenuItem(id: FileTemplateID(), displayName: "Stale")]
        )
        transport.completeNext(with: .success(stale))
        await waitForRequestCount(2, in: transport)

        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertTrue(replica.fileTemplates.isEmpty)

        let templates = [
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
        ]
        let latest = MenuConfigurationSnapshot(
            configuration: MenuConfiguration(
                isEnabled: true,
                hiddenFeatureIDs: ["new-text-file"]
            ),
            fileTemplates: templates
        )
        transport.completeNext(with: .success(latest))
        await waitForRefresh(in: replica)

        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertTrue(replica.isEnabled)
        XCTAssertFalse(replica.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertEqual(replica.fileTemplates, templates)
        let stored = try XCTUnwrap(defaults.data(forKey: MenuConfigurationSnapshotCache.key))
        XCTAssertEqual(try MenuConfigurationSnapshotCache.decode(stored), latest)
    }

    private func waitForRefresh(in replica: MenuConfigurationReplica) async {
        for _ in 0..<100 where replica.isRefreshing { await Task.yield() }
        XCTAssertFalse(replica.isRefreshing)
    }

    private func waitForRequestCount(
        _ expectedCount: Int,
        in transport: ControlledMenuConfigurationTransport
    ) async {
        for _ in 0..<100 where transport.requestCount < expectedCount {
            await Task.yield()
        }
        XCTAssertEqual(transport.requestCount, expectedCount)
    }
}

/// 保存每次异步完成句柄，让测试明确控制响应顺序。
nonisolated private final class ControlledMenuConfigurationTransport:
    MenuConfigurationRequesting,
    @unchecked Sendable
{
    typealias Completion = @Sendable (
        Result<MenuConfigurationSnapshot, Error>
    ) -> Void

    private let lock = NSLock()
    private var completions: [Completion] = []
    private var requests: [ApplicationIPCRequest] = []

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func fetchMenuConfiguration(completion: @escaping Completion) {
        lock.lock()
        requests.append(.menuConfiguration)
        completions.append(completion)
        lock.unlock()
    }

    func completeNext(
        with result: Result<MenuConfigurationSnapshot, Error>
    ) {
        lock.lock()
        let completion = completions.removeFirst()
        lock.unlock()
        completion(result)
    }
}
