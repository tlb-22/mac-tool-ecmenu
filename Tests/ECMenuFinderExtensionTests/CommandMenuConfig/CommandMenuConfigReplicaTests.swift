/**
 验证扩展菜单配置副本的缓存恢复、独立迁移和单飞刷新。
 通过隔离偏好与可控拉取结果检查失败保留快照、信号合并及过时响应丢弃。
 */

import Foundation
import XCTest
@testable import ECMenuFinderExtension

/// 验证配置更新信号只形成单飞拉取，且过时响应不会覆盖最终真相。
@MainActor
final class CommandMenuConfigReplicaTests: XCTestCase {
    func testFailedRefreshPreservesCacheAndNextSignalCanRefresh() async throws {
        let suiteName = "CommandMenuConfigReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let template = FileTemplateMenuItem(id: FileTemplateID(), displayName: "Notes")
        let cached = CommandMenuConfigSnapshot(
            configuration: CommandMenuConfig(isEnabled: false),
            newFileTemplates: [template]
        )
        let cachedData = CommandMenuConfigSnapshotCache.encode(cached)
        defaults.set(cachedData, forKey: CommandMenuConfigSnapshotCache.key)
        let transport = ControlledCommandMenuConfigTransport()
        let replica = CommandMenuConfigReplica(defaults: defaults, transport: transport)

        transport.completeNext(with: .failure(ApplicationIPCError.deadlineExceeded))
        await waitForRefresh(in: replica)
        XCTAssertFalse(replica.isEnabled)
        XCTAssertEqual(replica.newFileTemplates, [template])
        XCTAssertEqual(defaults.data(forKey: CommandMenuConfigSnapshotCache.key), cachedData)
        replica.refreshConfiguration()
        await waitForRequestCount(2, in: transport)
        XCTAssertFalse(replica.isEnabled)
        XCTAssertEqual(replica.newFileTemplates, [template])
        XCTAssertEqual(defaults.data(forKey: CommandMenuConfigSnapshotCache.key), cachedData)

        transport.completeNext(with: .success(.standard))
        await waitForRefresh(in: replica)
        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.newFileTemplates.isEmpty)
        let stored = try XCTUnwrap(defaults.data(forKey: CommandMenuConfigSnapshotCache.key))
        XCTAssertEqual(try CommandMenuConfigSnapshotCache.decode(stored), .standard)
    }

    func testInvalidCacheStartsWithStandardConfigurationWhenTransportIsUnavailable() throws {
        let suiteName = "CommandMenuConfigReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("{}".utf8), forKey: CommandMenuConfigSnapshotCache.key)
        let replica = CommandMenuConfigReplica(defaults: defaults, transport: nil)
        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.newFileTemplates.isEmpty)
        replica.refreshConfiguration()
        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.newFileTemplates.isEmpty)
    }

    /// 旧扩展缓存只迁移已有开关；真实模板库必须由主应用发布。
    func testLegacyCacheMigratesVisibilityWithoutInventingTemplates() throws {
        let suiteName = "CommandMenuConfigReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = CommandMenuConfig(
            isEnabled: false,
            hiddenFeatureIDs: ["new-text-file"]
        )
        defaults.set(
            CommandMenuConfigChannel.encodedData(for: legacy),
            forKey: CommandMenuConfigChannel.persistedConfigurationKey
        )

        let replica = CommandMenuConfigReplica(defaults: defaults, transport: nil)

        XCTAssertFalse(replica.isEnabled)
        XCTAssertFalse(replica.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertTrue(replica.newFileTemplates.isEmpty)
        XCTAssertNil(defaults.object(forKey: CommandMenuConfigChannel.persistedConfigurationKey))
        let stored = try XCTUnwrap(defaults.data(forKey: CommandMenuConfigSnapshotCache.key))
        XCTAssertEqual(
            try CommandMenuConfigSnapshotCache.decode(stored),
            CommandMenuConfigSnapshot(configuration: legacy, fileTemplateState: .unavailable)
        )
    }

    /// 同名模板以独立身份和原顺序恢复，已有新版快照优先于旧缓存。
    func testSnapshotCacheRestoresDuplicateNamesAndDistinctIdentities() throws {
        let suiteName = "CommandMenuConfigReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let templates = [
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
        ]
        let snapshot = CommandMenuConfigSnapshot(
            configuration: .standard,
            newFileTemplates: templates
        )
        defaults.set(
            CommandMenuConfigSnapshotCache.encode(snapshot),
            forKey: CommandMenuConfigSnapshotCache.key
        )
        defaults.set(
            CommandMenuConfigChannel.encodedData(for: CommandMenuConfig(isEnabled: false)),
            forKey: CommandMenuConfigChannel.persistedConfigurationKey
        )

        let replica = CommandMenuConfigReplica(defaults: defaults, transport: nil)

        XCTAssertTrue(replica.isEnabled)
        XCTAssertEqual(replica.newFileTemplates, templates)
        XCTAssertEqual(replica.newFileTemplates.map(\.displayName), ["TXT", "TXT"])
        XCTAssertNotEqual(replica.newFileTemplates[0].id, replica.newFileTemplates[1].id)
    }

    func testConcurrentRefreshSignalsCoalesceAndSkipStaleResponse() async throws {
        let suiteName = "CommandMenuConfigReplicaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let transport = ControlledCommandMenuConfigTransport()
        let replica = CommandMenuConfigReplica(
            defaults: defaults,
            transport: transport
        )
        XCTAssertEqual(transport.requestCount, 1)

        replica.refreshConfiguration()
        replica.refreshConfiguration()
        XCTAssertEqual(transport.requestCount, 1)

        let stale = CommandMenuConfigSnapshot(
            configuration: CommandMenuConfig(isEnabled: false),
            newFileTemplates: [FileTemplateMenuItem(id: FileTemplateID(), displayName: "Stale")]
        )
        transport.completeNext(with: .success(stale))
        await waitForRequestCount(2, in: transport)

        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertTrue(replica.newFileTemplates.isEmpty)

        let templates = [
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
            FileTemplateMenuItem(id: FileTemplateID(), displayName: "TXT"),
        ]
        let latest = CommandMenuConfigSnapshot(
            configuration: CommandMenuConfig(
                isEnabled: true,
                hiddenFeatureIDs: ["new-text-file"]
            ),
            newFileTemplates: templates
        )
        transport.completeNext(with: .success(latest))
        await waitForRefresh(in: replica)

        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertTrue(replica.isEnabled)
        XCTAssertFalse(replica.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertEqual(replica.newFileTemplates, templates)
        let stored = try XCTUnwrap(defaults.data(forKey: CommandMenuConfigSnapshotCache.key))
        XCTAssertEqual(try CommandMenuConfigSnapshotCache.decode(stored), latest)
    }

    private func waitForRefresh(in replica: CommandMenuConfigReplica) async {
        for _ in 0..<100 where replica.isRefreshing { await Task.yield() }
        XCTAssertFalse(replica.isRefreshing)
    }

    private func waitForRequestCount(
        _ expectedCount: Int,
        in transport: ControlledCommandMenuConfigTransport
    ) async {
        for _ in 0..<100 where transport.requestCount < expectedCount {
            await Task.yield()
        }
        XCTAssertEqual(transport.requestCount, expectedCount)
    }
}

/// 保存每次异步完成句柄，让测试明确控制响应顺序。
nonisolated private final class ControlledCommandMenuConfigTransport:
    CommandMenuConfigRequesting,
    @unchecked Sendable
{
    typealias Completion = @Sendable (
        Result<CommandMenuConfigSnapshot, Error>
    ) -> Void

    private let lock = NSLock()
    private var completions: [Completion] = []
    private var requests: [ApplicationIPCRequest] = []

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func fetchCommandMenuConfig(completion: @escaping Completion) {
        lock.lock()
        requests.append(.commandMenuConfig)
        completions.append(completion)
        lock.unlock()
    }

    func completeNext(
        with result: Result<CommandMenuConfigSnapshot, Error>
    ) {
        lock.lock()
        let completion = completions.removeFirst()
        lock.unlock()
        completion(result)
    }
}
