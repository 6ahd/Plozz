import CoreModels
import XCTest
@testable import FeatureWatchlistCore

final class WatchlistBatchReconcilerTests: XCTestCase {
    func testBatchDrainIsBoundedAndConfirmedWorkStaysQuietAfterRelaunch() async throws {
        let backing = InMemoryWatchlistMutationStateStore()
        let store = try DurableWatchlistMutationStore(store: backing)
        let destination = BatchDestination()
        let reconciler = makeReconciler(store, destination)
        let targets = (1...72).map(target)
        try await reconciler.identityEvidenceChanged(
            profileID: "p", changes: targets.map { .init(desiredState: .present, target: $0) }
        )
        let first = await reconciler.drain(profileID: "p")
        let second = await reconciler.drain(profileID: "p")
        XCTAssertEqual(first, 50)
        XCTAssertEqual(second, 22)
        let sizes = await destination.sizes
        XCTAssertEqual(sizes, [50, 22])
        let restored = try DurableWatchlistMutationStore(store: backing)
        let next = makeReconciler(restored, destination)
        try await next.identityEvidenceChanged(
            profileID: "p", changes: targets.map { .init(desiredState: .present, target: $0) }
        )
        let idle = await next.drain(profileID: "p")
        XCTAssertEqual(idle, 0)
    }

    func testRetryRetainsBatchKeyAndDoesNotSpinThroughDestinationCooldown() async throws {
        let backing = InMemoryWatchlistMutationStateStore()
        let store = try DurableWatchlistMutationStore(store: backing)
        let destination = BatchDestination(failure: .rateLimited(retryAfter: 600))
        let reconciler = makeReconciler(store, destination)
        let now = Date()
        try await reconciler.identityEvidenceChanged(
            profileID: "p", changes: (1...22).map { .init(desiredState: .present, target: target($0)) }, now: now
        )
        _ = await reconciler.drain(profileID: "p", now: now)
        let deadline = await store.earliestNextAttempt(profileID: "p")
        XCTAssertEqual(deadline, now.addingTimeInterval(600))
        let restored = try DurableWatchlistMutationStore(store: backing)
        let next = makeReconciler(restored, destination)
        let early = await next.drain(profileID: "p", now: now.addingTimeInterval(599))
        XCTAssertEqual(early, 0)
        await destination.setFailure(nil)
        _ = await next.drain(profileID: "p", now: now.addingTimeInterval(601))
        let keys = await destination.keys
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])
    }

    func testReadSettlesMatchingQueuedChangesButNotNewerOrOtherAccountIntent() async throws {
        for (readTime, identity, expectedCount) in [
            (101.0, "scope", 0), (99.0, "scope", 1), (101.0, "other", 1)
        ] {
            let backing = InMemoryWatchlistMutationStateStore()
            let store = try DurableWatchlistMutationStore(store: backing)
            let item = target(1)
            let destination = WatchlistDestinationID(rawValue: "tracker")!
            try await store.enqueue(
                profileID: "p", desiredState: .present, target: item,
                destinationID: destination, confirmationIdentity: "scope", now: Date(timeIntervalSince1970: 100)
            )
            _ = try await store.observeNativeBatch([.init(
                key: .init(profileID: "p", aliasID: item.aliasID, destinationID: destination),
                isPresent: true, localDesiredState: .present, confirmationIdentity: identity,
                nativeReadStartedAt: Date(timeIntervalSince1970: readTime), isEligibleTarget: true
            )])
            let reopened = try DurableWatchlistMutationStore(store: backing)
            let pending = await reopened.allMutations()
            XCTAssertEqual(pending.count, expectedCount)
        }
    }

    func testPartialResultsParkOnlyFailedItemsAndBadResultLengthAcknowledgesNothing() async throws {
        for malformed in [false, true] {
            let store = try DurableWatchlistMutationStore(store: InMemoryWatchlistMutationStateStore())
            let destination = BatchDestination(partial: true, malformed: malformed)
            let reconciler = makeReconciler(store, destination)
            try await reconciler.identityEvidenceChanged(
                profileID: "p", changes: (1...3).map { .init(desiredState: .present, target: target($0)) }
            )
            _ = await reconciler.drain(profileID: "p")
            let pending = await store.allMutations()
            XCTAssertEqual(pending.count, malformed ? 3 : 1)
            XCTAssertTrue(pending.allSatisfy {
                $0.phase == (malformed ? .retryScheduled : .waitingForIdentity)
            })
        }
    }

    func testLegacyDeliveryIDsPersistAndNewIntentGetsNewID() async throws {
        let item = target(1)
        let destination = WatchlistDestinationID(rawValue: "tracker")!
        var legacy = WatchlistMutation(
            key: .init(profileID: "p", aliasID: item.aliasID, destinationID: destination),
            desiredState: .present, target: item
        )
        legacy.deliveryID = nil
        let backing = InMemoryWatchlistMutationStateStore(state: .init(mutations: [legacy]))
        let store = try DurableWatchlistMutationStore(store: backing)
        let first = await store.allMutations()
        let reopened = try DurableWatchlistMutationStore(store: backing)
        let restored = await reopened.allMutations()
        XCTAssertNotNil(first.first?.deliveryID)
        XCTAssertEqual(first.first?.deliveryID, restored.first?.deliveryID)
        try await reopened.enqueue(
            profileID: "p", desiredState: .absent, target: item, destinationID: destination
        )
        let changed = await reopened.allMutations()
        XCTAssertNotEqual(first.first?.deliveryID, changed.first?.deliveryID)
    }

    func testStaleReadCannotUndoConfirmedWriteOrClearNewRemoval() async throws {
        let store = try DurableWatchlistMutationStore(store: InMemoryWatchlistMutationStateStore())
        let item = target(1)
        let destination = WatchlistDestinationID(rawValue: "tracker")!
        let key = WatchlistMutationKey(profileID: "p", aliasID: item.aliasID, destinationID: destination)
        try await store.enqueue(
            profileID: "p", desiredState: .present, target: item, destinationID: destination,
            confirmationIdentity: "scope", now: Date(timeIntervalSince1970: 90)
        )
        try await store.markSucceeded(key, now: Date(timeIntervalSince1970: 100))
        let observation = WatchlistNativeObservationRequest(
            key: key, isPresent: false, localDesiredState: .absent, confirmationIdentity: "scope",
            nativeReadStartedAt: Date(timeIntervalSince1970: 99), isEligibleTarget: true
        )
        _ = try await store.observeNativeBatch([observation])
        let confirmed = await store.isAlreadyConfirmed(
            key, desiredState: .present, target: item, confirmationIdentity: "scope"
        )
        XCTAssertTrue(confirmed)
        try await store.enqueue(
            profileID: "p", desiredState: .absent, target: item, destinationID: destination,
            confirmationIdentity: "scope", now: Date(timeIntervalSince1970: 101)
        )
        _ = try await store.observeNativeBatch([observation])
        let pending = await store.allMutations()
        XCTAssertEqual(pending.map(\.desiredState), [.absent])
    }

    func testNewIntentDuringBatchIsNotAcknowledgedByOldResponse() async throws {
        let store = try DurableWatchlistMutationStore(store: InMemoryWatchlistMutationStateStore())
        let destination = BatchDestination(beforeReply: {
            let pending = await store.allMutations()
            let old = try XCTUnwrap(pending.first)
            try await store.enqueue(
                profileID: old.key.profileID, desiredState: .absent, target: old.target,
                destinationID: old.key.destinationID, confirmationIdentity: old.confirmationIdentity
            )
        })
        let reconciler = makeReconciler(store, destination)
        try await reconciler.identityEvidenceChanged(
            profileID: "p", changes: [.init(desiredState: .present, target: target(1))]
        )
        _ = await reconciler.drain(profileID: "p")
        let pending = await store.allMutations()
        XCTAssertEqual(pending.map(\.desiredState), [.absent])
        XCTAssertEqual(pending.first?.phase, .queued)
    }

    func testBatchesSeparateOperationsAndProfiles() async throws {
        let store = try DurableWatchlistMutationStore(store: InMemoryWatchlistMutationStateStore())
        let destination = BatchDestination()
        let reconciler = makeReconciler(store, destination)
        try await reconciler.identityEvidenceChanged(profileID: "p", changes: [
            .init(desiredState: .present, target: target(1)),
            .init(desiredState: .absent, target: target(2))
        ])
        try await reconciler.identityEvidenceChanged(
            profileID: "q", changes: [.init(desiredState: .present, target: target(3))]
        )
        _ = await reconciler.drain(profileID: "p")
        let states = await destination.states
        XCTAssertEqual(Set(states), [.present, .absent])
        XCTAssertEqual(states.count, 2)
        let pending = await store.allMutations()
        XCTAssertEqual(pending.map(\.key.profileID), ["q"])
    }

    func testFailedPersistenceRollsBackQueueConfirmationAndCooldown() async throws {
        let backing = FailingMutationStateStore()
        let store = try DurableWatchlistMutationStore(store: backing)
        let item = target(1)
        let destination = WatchlistDestinationID(rawValue: "tracker")!
        try await store.enqueue(
            profileID: "p", desiredState: .present, target: item,
            destinationID: destination, confirmationIdentity: "scope"
        )
        let original = await store.allMutations()
        let mutation = try XCTUnwrap(original.first)
        for operation in 0..<6 {
            backing.failNextSave()
            do {
                switch operation {
                case 0: try await store.markSucceeded(mutation)
                case 1: try await store.markFailed(mutation, classification: .transient, retryAt: .distantFuture)
                case 2: _ = try await store.deferDestination(destination, until: .distantFuture)
                case 3: _ = try await store.parkDestinationForAuthentication(destination)
                case 4:
                    try await store.enqueue(
                        profileID: "p", desiredState: .absent, target: item, destinationID: destination
                    )
                default:
                    _ = try await store.observeNativeBatch([.init(
                        key: mutation.key, isPresent: true, localDesiredState: .present,
                        confirmationIdentity: "scope", nativeReadStartedAt: .distantFuture, isEligibleTarget: true
                    )])
                }
                XCTFail("Expected persistence failure")
            } catch {}
            let pending = await store.allMutations()
            XCTAssertEqual(pending, original)
            let reopened = try DurableWatchlistMutationStore(store: backing)
            let restored = await reopened.allMutations()
            XCTAssertEqual(restored, original)
            let confirmed = await store.isAlreadyConfirmed(
                mutation.key, desiredState: .present, target: item, confirmationIdentity: "scope"
            )
            XCTAssertFalse(confirmed)
        }
    }

    private func target(_ id: Int) -> WatchlistMutationTarget {
        WatchlistMutationTarget(
            aliasID: .init(), kind: .movie,
            externalIDs: [WatchlistExternalID(namespace: .tmdb, value: String(id))!]
        )!
    }

    private func makeReconciler(
        _ store: DurableWatchlistMutationStore, _ destination: BatchDestination
    ) -> WatchlistReconciler {
        .init(registry: .init([destination]), mutationStore: store, retryPolicy: .init(jitterFraction: 0))
    }
}

private actor BatchDestination: WatchlistBatchApplying {
    nonisolated let id = WatchlistDestinationID(rawValue: "batch")!
    nonisolated let maximumBatchSize = 50
    nonisolated let capabilities = WatchlistDestinationCapabilities(
        readable: true, writable: true, removable: true,
        bindingRequirement: .globalExternalIdentity, globalIdentityNamespaces: [.tmdb]
    )
    var sizes: [Int] = []
    var keys: [String] = []
    var states: [WatchlistDesiredState] = []
    private var failure: WatchlistDestinationError?
    private let partial: Bool
    private let malformed: Bool
    private let beforeReply: @Sendable () async throws -> Void

    init(
        failure: WatchlistDestinationError? = nil, partial: Bool = false, malformed: Bool = false,
        beforeReply: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.failure = failure
        self.partial = partial
        self.malformed = malformed
        self.beforeReply = beforeReply
    }

    func setFailure(_ failure: WatchlistDestinationError?) { self.failure = failure }
    func fetchEntries() async throws -> [WatchlistDestinationEntry] { [] }
    func resolve(_ target: WatchlistMutationTarget) async throws -> WatchlistDestinationBinding? {
        .init(destinationID: id, opaqueValue: target.identityFingerprint)
    }
    func apply(_ desiredState: WatchlistDesiredState, to binding: WatchlistDestinationBinding) async throws {
        XCTFail("Expected the bulk transport")
    }
    func apply(
        _ desiredState: WatchlistDesiredState, to binding: WatchlistDestinationBinding,
        expectedReconciliationScope: String
    ) async throws {
        XCTFail("Expected the bulk transport")
    }
    func apply(
        _ desiredState: WatchlistDesiredState, to bindings: [WatchlistDestinationBinding],
        idempotencyKey: String, expectedReconciliationScope: String
    ) async throws -> [Result<Void, WatchlistDestinationError>] {
        sizes.append(bindings.count)
        keys.append(idempotencyKey)
        states.append(desiredState)
        try await beforeReply()
        if let failure { throw failure }
        if malformed { return [] }
        return bindings.indices.map { partial && $0 == 1 ? .failure(.unsupportedIdentity) : .success(()) }
    }
}

private final class FailingMutationStateStore: WatchlistMutationStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state = WatchlistMutationStoreState()
    private var fail = false
    func load() throws -> WatchlistMutationStoreState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
    func save(_ value: WatchlistMutationStoreState) throws {
        lock.lock()
        defer { lock.unlock() }
        if fail { fail = false; throw CocoaError(.fileWriteUnknown) }
        state = value
    }
    func failNextSave() {
        lock.lock()
        defer { lock.unlock() }
        fail = true
    }
}
