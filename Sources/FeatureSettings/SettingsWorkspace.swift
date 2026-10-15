#if os(tvOS)
import CoreUI
import CoreModels
import FeatureProfiles
import SwiftUI

public struct SettingsExitAction {
    public let perform: () -> Void

    public init(_ perform: @escaping () -> Void) { self.perform = perform }
}

private struct SettingsExitActionKey: EnvironmentKey {
    static let defaultValue: SettingsExitAction? = nil
}

private struct SettingsWorkspaceFocusScopeKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

public extension EnvironmentValues {
    var settingsExitAction: SettingsExitAction? {
        get { self[SettingsExitActionKey.self] }
        set { self[SettingsExitActionKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var settingsWorkspaceFocusScope: Namespace.ID? {
        get { self[SettingsWorkspaceFocusScopeKey.self] }
        set { self[SettingsWorkspaceFocusScopeKey.self] = newValue }
    }
}

struct SettingsWorkspace<Sidebar: View, Detail: View>: View {
    @Bindable var navigation: SettingsNavigationModel
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: (SettingsRoute) -> Detail
    @Environment(\.settingsExitAction) private var exit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sidebarScope

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = min(548, geometry.size.width * 0.32)
            let fullScreen = navigation.usesFullScreenDetail
            HStack(alignment: .top, spacing: fullScreen ? 0 : 56) {
                if !fullScreen {
                    sidebar()
                        .padding(.top, 36)
                        .frame(width: sidebarWidth, alignment: .topLeading)
                        .focusSection()
                        .focusScope(sidebarScope)
                        .environment(\.settingsWorkspaceFocusScope, sidebarScope)
                        .onExitCommand { exit?.perform() }
                        .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
                }

                SettingsPageStack(
                    navigation: navigation.pages, pageWidth: geometry.size.width,
                    onRootBack: navigation.returnToSidebar
                ) {
                    detail(navigation.section)
                        .id(navigation.section)
                        .environment(\.settingsPageBackButton, fullScreen ? AnyView(Button {
                            navigation.returnToSidebar()
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }.accessibilityIdentifier("settings-category-back")) : nil)
                } destination: { route in
                    SettingsWorkspaceDestination(route: route) {
                        detail(route)
                    }
                }
                .toolbar(.hidden, for: .tabBar)
                .safeAreaPadding(.top, 36)
                .ignoresSafeArea(.container, edges: .vertical)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .disabled(navigation.restoringSidebar)
                .focusSection()
                .background {
                    NativeFocusRegionObserver(isEnabled: !navigation.restoringSidebar) {
                        navigation.focusInDetail = true
                        navigation.isCategoryOpen = true
                        navigation.restoringSidebar = false
                        navigation.enteringDetail = false
                    }
                }
            }
            .animation(reduceMotion ? nil : SettingsPageMotion.animation, value: fullScreen)
        }
        .environment(navigation)
        .environment(\.settingsInWorkspace, true)
        .onAppear {
            if navigation.isCategoryOpen || !navigation.path.isEmpty {
                navigation.enterDetail()
            } else {
                navigation.returnToSidebar()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct SettingsWorkspaceDestination<Content: View>: View {
    let route: SettingsRoute
    @ViewBuilder var content: () -> Content
    @SettingsPageDismiss private var dismiss

    var body: some View {
        if route == .artwork || route == .navigationLayout {
            content()
        } else {
            content()
                .environment(\.settingsPageBackButton, AnyView(Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }.settingsWorkspaceEntry(route: route)
                    .settingsPageEntryFocus(enabled: !route.usesFullScreenDetail)
                    .accessibilityIdentifier("settings-workspace-back")))
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

struct SettingsSectionButton: View {
    let title: Text
    let icon: String
    var assetIcon: String?
    var value: Text?
    let route: SettingsRoute
    @Environment(SettingsNavigationModel.self) private var navigation
    @Environment(\.settingsWorkspaceFocusScope) private var scope
    @Environment(\.resetFocus) private var resetFocus
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focused: Bool

    private var canReceiveFocus: Bool {
        !navigation.usesFullScreenDetail && !navigation.enteringDetail
            && (!(navigation.focusInDetail || navigation.restoringSidebar) || navigation.section == route)
    }

    var body: some View {
        Button {
            navigation.select(route)
            navigation.enterDetail()
        } label: {
            SettingsSectionLabel(
                title: title, icon: icon, assetIcon: assetIcon,
                value: value, selected: navigation.section == route
            )
        }
        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
        .onMoveCommand { direction in
            if direction == (layoutDirection == .leftToRight ? .right : .left) {
                navigation.select(route)
                navigation.enterDetail()
            }
        }
        .focused($focused)
        .modifier(SettingsSectionFocusPreference(scope: scope, selected: navigation.section == route))
        .disabled(!canReceiveFocus)
        .accessibilityIdentifier("settings-section-\(route)")
        .accessibilityAddTraits(navigation.section == route ? .isSelected : [])
        .navigationEntryFocus(navigation.section == route ? .content : nil)
        .background {
            NativeFocusRegionObserver(isEnabled: canReceiveFocus) {
                guard canReceiveFocus else { return }
                navigation.focusInDetail = false
                navigation.restoringSidebar = false
                navigation.enteringDetail = false
                navigation.select(route)
            }
        }
        .task(id: navigation.sidebarFocusRequest) {
            guard navigation.section == route else { return }
            focused = false
            await Task.yield()
            guard !Task.isCancelled, navigation.section == route,
                  !navigation.focusInDetail, !navigation.enteringDetail else { return }
            focused = true
            if let scope { resetFocus(in: scope) }
        }
    }
}

private struct SettingsSectionFocusPreference: ViewModifier {
    let scope: Namespace.ID?
    let selected: Bool

    func body(content: Content) -> some View {
        if let scope {
            content.prefersDefaultFocus(selected, in: scope)
        } else {
            content
        }
    }
}

private struct SettingsSectionLabel: View {
    let title: Text
    let icon: String
    let assetIcon: String?
    let value: Text?
    let selected: Bool
    @Environment(\.settingsRowIsFocused) private var focused
    @Environment(\.themePalette) private var palette

    var body: some View {
        SettingsRowLabel(icon: icon, assetIcon: assetIcon, title: title, trailing: {
            HStack(spacing: 10) {
                value?.font(.caption).settingsRowSecondary()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .settingsRowSecondary()
            }
        })
        .background {
            if selected && !focused {
                RoundedRectangle(cornerRadius: 16).fill(palette.fillSubtle)
            }
        }
    }
}

enum SettingsWorkspaceHeaderMetrics {
    static let iconSize: CGFloat = 52
    static let titleFont: Font = .system(size: 36, weight: .bold)
    static let labelSpacing = PlozzTheme.Spacing.medium
    static let outerInset = PlozzTheme.Spacing.medium
    static let controlInset = PlozzTheme.Spacing.xSmall
    static let contentInset = outerInset + controlInset
}

struct SettingsWorkspaceProfileHeader: View {
    let profile: Profile
    let canEdit: Bool
    let onSwitch: () -> Void
    let onEdit: () -> Void
    @Environment(SettingsNavigationModel.self) private var navigation

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSwitch) {
                HStack(spacing: SettingsWorkspaceHeaderMetrics.labelSpacing) {
                    ProfileAvatarView(profile: profile, size: SettingsWorkspaceHeaderMetrics.iconSize)
                        .accessibilityIdentifier("settings-profile-avatar")
                    Text(verbatim: profile.name)
                        .font(SettingsWorkspaceHeaderMetrics.titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("settings-profile-name")
                    Spacer(minLength: 0)
                }
                .padding(SettingsWorkspaceHeaderMetrics.controlInset)
            }
            .buttonStyle(SettingsFocusButtonStyle(size: .contained))
            .accessibilityLabel("Switch Profile")
            .accessibilityValue(Text(verbatim: profile.name))
            .accessibilityIdentifier("settings-profile-switch")
            if canEdit {
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings-profile-edit")
            }
        }
        .disabled(navigation.focusInDetail || navigation.restoringSidebar || navigation.enteringDetail)
        .padding(SettingsWorkspaceHeaderMetrics.outerInset)
    }
}
#endif
