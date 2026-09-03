import Foundation
import XCTest
@testable import ECMenuFinderExtension

/// 验证配置更新信号只形成单飞拉取，且过时响应不会覆盖最终真相。
@MainActor
final class MenuConfigurationReplicaTests: XCTestCase {
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

        let stale = MenuConfiguration(isEnabled: false)
        transport.completeNext(with: .success(stale))
        await waitForRequestCount(2, in: transport)

        // 第一份响应在拉取期间收到过新信号，因此不能应用。
        XCTAssertTrue(replica.isEnabled)
        XCTAssertTrue(replica.isVisible(.init(rawValue: "new-text-file")))

        let latest = MenuConfiguration(
            isEnabled: true,
            hiddenFeatureIDs: ["new-text-file"]
        )
        transport.completeNext(with: .success(latest))
        await Task.yield()

        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertTrue(replica.isEnabled)
        XCTAssertFalse(replica.isVisible(.init(rawValue: "new-text-file")))
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
        Result<MenuConfiguration, Error>
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
        with result: Result<MenuConfiguration, Error>
    ) {
        lock.lock()
        let completion = completions.removeFirst()
        lock.unlock()
        completion(result)
    }
}
