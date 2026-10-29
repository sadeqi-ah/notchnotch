import SwiftUI
import NotchCore
import NotchRenderer

struct NotchView: View {
    let model: AppModel
    let onInteraction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var geometry: NotchGeometry { model.geometry }
    private var silhouette: NotchSilhouette {
        let size = geometry.bodySize(presentation: model.presentation)
        return .init(bodyWidth: size.width, bodyHeight: size.height,
                     shoulder: geometry.shoulderRadius(presentation: model.presentation),
                     bottomRadius: geometry.bottomRadius(presentation: model.presentation), attached: geometry.attached)
    }
    private var isHidden: Bool { model.presentation == .idle }
    private var barHeight: CGFloat { model.presentation == .hovered ? geometry.hoveredHeight : model.topHeight }
    private var shellShadow: (opacity: Double, radius: CGFloat) {
        switch model.presentation {
        case .idle, .compact: (0, 0)
        case .hovered: (0.24, 12)
        case .peek: (0.18, 8)
        case .expanded: (0.34, 16)
        }
    }
    private var shellAnimation: Animation? {
        reduceMotion ? nil : .spring(response: model.isExpanded ? 0.44 : 0.36,
                                     dampingFraction: model.isExpanded ? 0.82 : 0.9, blendDuration: 0.12)
    }

    var body: some View {
        ZStack(alignment: .top) {
            silhouette.fill(.black)
                .opacity(isHidden ? 0 : 1)
                .shadow(color: .black.opacity(shellShadow.opacity), radius: shellShadow.radius, y: 7)

            ZStack(alignment: .top) {
                compactBar
                    .opacity(model.isExpanded || isHidden ? 0 : 1)
                    .blur(radius: reduceMotion ? 0 : model.isExpanded || isHidden ? 3 : 0)
                    .allowsHitTesting(!model.isExpanded && !isHidden)
                    .accessibilityHidden(model.isExpanded || isHidden)
                    .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.13), value: model.isExpanded)

                expandedContent
                    .opacity(model.isExpanded ? 1 : 0)
                    .blur(radius: reduceMotion || model.isExpanded ? 0 : 5)
                    .scaleEffect(reduceMotion || model.isExpanded ? 1 : 0.96, anchor: .top)
                    .offset(y: reduceMotion || model.isExpanded ? 0 : -6)
                    .allowsHitTesting(model.isExpanded)
                    .disabled(!model.isExpanded)
                    .accessibilityHidden(!model.isExpanded)
                    .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18)
                        .delay(model.isExpanded && !reduceMotion ? 0.07 : 0), value: model.isExpanded)
            }
            .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height, alignment: .top)
            .clipShape(silhouette)
        }
        .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height, alignment: .top)
        .preferredColorScheme(.dark)
        .contextMenu {
            ForEach(model.platform.surfaces) { item in
                Button(item.surface.title) { onInteraction(); model.open(item.key) }
            }
            Divider()
            Button("Settings & Extensions…") { model.onOpenManagement?() }
        }
        .animation(shellAnimation, value: model.presentation)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92), value: geometry.fittedContentHeight)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.9), value: geometry.compactWidth)
    }

    private var compactBar: some View {
        Button {
            onInteraction()
            model.toggle()
        } label: {
            VStack(spacing: 0) {
                compactWings
                    .frame(height: barHeight)
                Text(model.lastPeekText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .opacity(model.isPeeking ? 1 : 0)
                    .blur(radius: reduceMotion || model.isPeeking ? 0 : 4)
                    .offset(y: reduceMotion || model.isPeeking ? 0 : -22)
                    .accessibilityHidden(!model.isPeeking)
                    .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18)
                        .delay(model.isPeeking && !reduceMotion ? 0.06 : 0), value: model.isPeeking)
            }
            .frame(width: model.isPeeking ? geometry.peekWidth : geometry.bodySize(presentation: model.presentation).width,
                   height: model.isPeeking ? geometry.peekHeight : barHeight, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open NotchNotch")
        .accessibilityValue(model.isPeeking ? model.lastPeekText : model.wingSurface?.surface.title ?? "Activity hub")
        .help(model.platform.pendingCount > 0 ? "A question is waiting" : "Open activities")
    }

    private var compactWings: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                if let compact = model.wingSurface?.surface.compact {
                    ForEach(compact.leading) { node in NativeNodeView(node: node, compact: true) { _, _ in } }
                } else if model.presentation == .hovered || model.platform.pendingCount > 0 {
                    Image(systemName: model.wingSurface?.surface.kind == .prompt ? "bubble.left.fill" : "square.grid.2x2.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                }
            }.frame(maxWidth: .infinity).clipped()
            Color.clear.frame(width: model.notchWidth)
            HStack(spacing: 3) {
                if let compact = model.wingSurface?.surface.compact {
                    ForEach(compact.trailing) { node in NativeNodeView(node: node, compact: true) { _, _ in } }
                } else if model.presentation == .hovered || model.platform.pendingCount > 0 {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                }
                if model.platform.pendingCount > 0 {
                    Circle().fill(.white).frame(width: 3, height: 3)
                }
            }.frame(maxWidth: .infinity).clipped()
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance: CGFloat = model.pageDirection == .next ? 32 : -32
        return .asymmetric(insertion: .offset(x: distance).combined(with: .opacity),
                           removal: .offset(x: -distance).combined(with: .opacity))
    }

    private var pagerHeight: CGFloat { model.platform.surfaces.isEmpty ? 0 : 24 }

    private var expandedContent: some View {
        let pageKey = model.displayedSurface?.key
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                expandedPage
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    model.measureContent(proxy.size.height + pagerHeight, for: pageKey)
                                }
                                .onChange(of: proxy.size.height) { _, height in
                                    model.measureContent(height + pagerHeight, for: pageKey)
                                }
                                .onChange(of: pagerHeight) { _, height in
                                    model.measureContent(proxy.size.height + height, for: pageKey)
                                }
                        }
                    }
                    .id(pageKey)
                    .transition(pageTransition)
            }
            .frame(height: max(0, model.contentHeight - pagerHeight), alignment: .top)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.32, dampingFraction: 0.92),
                       value: pageKey)
            activityPicker.frame(height: pagerHeight)
            Color.clear.frame(height: NotchGeometry.expandedBottomPadding)
        }
        .frame(width: geometry.expandedWidth)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) {
            // Shared chrome stays in the right camera wing while page content
            // transitions beneath it, including the headerless music player.
            HStack(spacing: 0) {
                Spacer()
                Button("Open Settings & Extensions", systemImage: "gearshape") { model.onOpenManagement?() }
                    .labelStyle(.iconOnly).font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
                    .buttonStyle(.plain).help("Settings & Extensions")
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 24)
            .frame(height: model.topHeight + 8)
        }
        .onChange(of: pageKey, initial: true) { _, _ in model.selectContent() }
    }

    @ViewBuilder private var expandedPage: some View {
        if model.playerNode != nil, let selected = model.displayedSurface {
            NativeNodeView(node: selected.surface.expanded, cameraHeight: model.topHeight) { action, value in
                onInteraction()
                model.send(extensionID: selected.key.extensionID, action: action, value: value)
            }
            .padding(.horizontal, 27).padding(.top, 14)
            .frame(width: geometry.expandedWidth)
        } else { standardExpandedContent }
    }

    private var standardExpandedContent: some View {
        VStack(spacing: 0) {
            topControls.frame(height: model.topHeight + 8)
            VStack(spacing: 14) {
                if let selected = model.displayedSurface {
                    NativeNodeView(node: selected.surface.expanded) { action, value in
                        onInteraction()
                        model.send(extensionID: selected.key.extensionID, action: action, value: value)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No activities.").font(.system(size: 17, weight: .semibold))
                        Text("Your notch stays out of the way until an activity starts.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Open Settings & Extensions") { model.onOpenManagement?() }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        if !model.errors.isEmpty {
                            Button("Restart extensions") { model.reloadExtensions(force: true) }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !model.errors.isEmpty && model.platform.selected != nil {
                    Text("An extension stopped. Restart it from the menu bar.")
                        .font(.system(size: 10)).foregroundStyle(NotchPalette.color(.warning))
                }
            }
            .padding(.horizontal, 28)
            .frame(width: geometry.expandedWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: geometry.expandedWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var topControls: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(model.platform.surfaces) { item in
                    Button {
                        onInteraction()
                        model.open(item.key)
                    } label: {
                        Label(item.surface.title, systemImage: item.surface.kind == .prompt ? "bubble.left" : "circle")
                    }
                }
                Divider()
                Button("Settings & Extensions…") { model.onOpenManagement?() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45)).frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Switch activity")
            .accessibilityLabel("Switch activity")

            Spacer(minLength: model.notchWidth)
            if model.platform.pendingCount > 0 {
                Button { onInteraction(); model.openPrompt() } label: {
                    Image(systemName: "bubble.left.fill").font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8)).frame(width: 24, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("Open pending question")
            }
            Button { model.close() } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4)).frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Collapse panel")
            Color.clear.frame(width: 24, height: 24).accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder private var activityPicker: some View {
        if !model.platform.surfaces.isEmpty {
            HStack(spacing: 0) {
                ForEach(model.platform.surfaces) { item in
                    let isSelected = model.displayedSurface?.key == item.key
                    Button { onInteraction(); model.open(item.key) } label: {
                        Capsule()
                            .fill(.white.opacity(isSelected ? 0.9 : 0.28))
                            .frame(width: isSelected ? 16 : 4, height: 4)
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.surface.title)
                    .accessibilityLabel(item.surface.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85),
                       value: model.displayedSurface?.key)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Activities")
            .help("Swipe left or right with two fingers to switch activities")
        }
    }
}
