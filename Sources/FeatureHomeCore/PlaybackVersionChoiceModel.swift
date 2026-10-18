import CoreModels
import CoreNetworking
import Foundation
import Observation

/// A presentation-owned gate, shared by initial play and episode/playlist advance.
/// No stream or engine is opened while a choice is pending.
@MainActor
@Observable
public final class PlaybackVersionChoiceModel {
    public struct Prompt: Equatable {
        public let id: UUID
        public let item: MediaItem
        public let versions: [MediaVersion]
        public let selectedVersionID: String?
        public var needsIntroduction: Bool
    }

    public private(set) var prompt: Prompt?
    @ObservationIgnored private var continuation: CheckedContinuation<MediaItem, Error>?
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var settings: PlaybackSettingsModel?
    @ObservationIgnored private var preferences: (any VersionPreferenceStoring)?
    @ObservationIgnored private var isCurrent: () -> Bool = { false }
    @ObservationIgnored private var capabilities: MediaCapabilities = .default

    public init() {}

    public var isPreparing: Bool { owner != nil }

    public func prepare(
        _ opened: MediaItem,
        provider: any MediaProvider,
        settings: PlaybackSettingsModel,
        preferences: any VersionPreferenceStoring,
        offlineResolver: (any OfflinePlaybackResolving)? = nil,
        capabilities: MediaCapabilities = .detected(),
        isCurrent: @escaping () -> Bool = { true }
    ) async throws -> MediaItem {
        guard owner == nil else {
            PlozzLog.playback.error("A version choice is already pending.")
            throw AppError.invalidResponse
        }
        guard [.movie, .episode].contains(opened.kind), opened.youTubeTrailerVideoID == nil else {
            return opened
        }
        let id = UUID()
        owner = id
        defer { clear(owner: id) }
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        var item = opened
        if opened.versions.isEmpty,
           PlayerVersionSelection.versions(for: opened).count <= 1 {
            let local = await offlineResolver?.localPlaybackURL(for: opened, versionID: opened.selectedVersionID)
            if local == nil {
                let resolved = try await provider.item(id: opened.id)
                guard resolved.id == opened.id, resolved.kind == opened.kind,
                      resolved.sourceAccountID == nil || resolved.sourceAccountID == opened.sourceAccountID else {
                    PlozzLog.playback.error("Version details did not match the requested title.")
                    throw AppError.invalidResponse
                }
                item = PlayerVersionSelection.item(opened: opened, resolved: resolved)
                if item.seriesID == nil { item.seriesID = resolved.seriesID }
            }
        }
        try Task.checkCancellation()
        guard owner == id, isCurrent() else { throw CancellationError() }
        let versions = PlayerVersionSelection.versions(for: item)
        guard versions.count > 1 else { return item }
        let selectedID = DetailPlaybackSelection.preferredVersionID(
            for: item, versions: versions, versionOverride: nil,
            preferences: preferences, capabilities: capabilities
        )
        if settings.settings.versionSelectionMode == .automatic {
            guard let selectedID,
                  let selected = PlayerVersionSelection.selecting(
                    selectedID, in: item, explicit: item.explicitSourceSelection
                  ) else {
                PlozzLog.playback.error("Could not resolve an automatic playback version.")
                throw AppError.invalidResponse
            }
            return selected
        }
        self.settings = settings
        self.preferences = preferences
        self.isCurrent = isCurrent
        self.capabilities = capabilities
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                prompt = Prompt(
                    id: id, item: item, versions: versions, selectedVersionID: selectedID,
                    needsIntroduction: settings.settings.versionSelectionMode == nil
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(owner: id) }
        }
    }

    public func chooseMode(_ mode: PlaybackVersionSelectionMode, promptID: UUID) {
        guard let prompt, prompt.id == promptID, prompt.needsIntroduction else { return }
        guard isCurrent() else { cancel(); return }
        settings?.settings.versionSelectionMode = mode
        if mode == .askEveryTime {
            self.prompt?.needsIntroduction = false
        } else {
            guard let preferences,
                  let id = DetailPlaybackSelection.preferredVersionID(
                    for: prompt.item, versions: prompt.versions, versionOverride: nil,
                    preferences: preferences, capabilities: capabilities
                  ),
                  let item = PlayerVersionSelection.selecting(
                    id, in: prompt.item, explicit: prompt.item.explicitSourceSelection
                  ) else {
                PlozzLog.playback.error("Could not resolve the first automatic playback version.")
                finish(.failure(AppError.invalidResponse), owner: prompt.id)
                return
            }
            finish(.success(item), owner: prompt.id)
        }
    }

    public func chooseVersion(_ versionID: String, promptID: UUID) {
        guard let prompt, prompt.id == promptID, !prompt.needsIntroduction else { return }
        guard isCurrent() else { cancel(); return }
        guard let version = prompt.versions.first(where: { $0.id == versionID }),
              let item = PlayerVersionSelection.selecting(versionID, in: prompt.item) else {
            PlozzLog.playback.error("The requested playback version is no longer available.")
            return
        }
        if let preferences, preferences.shouldRememberVersion(for: prompt.item) {
            preferences.rememberVersion(version, forTitle: DetailPlaybackSelection.versionPreferenceKey(for: prompt.item))
            if DetailPlaybackSelection.versionPreferenceKey(for: item)
                != DetailPlaybackSelection.versionPreferenceKey(for: prompt.item) {
                preferences.rememberVersion(version, forTitle: DetailPlaybackSelection.versionPreferenceKey(for: item))
            }
        }
        finish(.success(item), owner: prompt.id)
    }

    public func cancel() {
        guard let owner else { return }
        cancel(owner: owner)
    }

    private func cancel(owner id: UUID) {
        finish(.failure(CancellationError()), owner: id)
    }

    private func finish(_ result: Result<MediaItem, Error>, owner id: UUID) {
        guard owner == id else { return }
        let continuation = self.continuation
        clear(owner: id)
        continuation?.resume(with: result)
    }

    private func clear(owner id: UUID) {
        guard owner == id else { return }
        prompt = nil
        continuation = nil
        settings = nil
        preferences = nil
        isCurrent = { false }
        owner = nil
    }

}
