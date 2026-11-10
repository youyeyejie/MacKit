/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See THIRD_PARTY_NOTICES.md for the original NOTICE and attribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import SwiftUI

private struct ShelfBackgroundClickCatcher: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> BackgroundClickView {
        let view = BackgroundClickView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: BackgroundClickView, context: Context) {
        nsView.onClick = onClick
    }

    final class BackgroundClickView: NSView {
        var onClick: (() -> Void)?

        override func mouseUp(with event: NSEvent) {
            onClick?()
        }
    }
}

struct ShelfView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var deleteMonitor: Any?
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting)
            { providers in
                handleDrop(providers: providers)
            }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
            if !selection.selectedIDs.isEmpty { focusShelf() }
        }
        .quickLookPresenter(using: quickLookService)
        .onAppear {
            deleteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                    let window = NSApp.keyWindow as? DynamicIslandWindow,
                    event.window == window,
                    !(window.firstResponder is NSTextView),
                    vm.notchState == .open,
                    DynamicIslandViewCoordinator.shared.currentView == .shelf
                else { return event }
                if event.keyCode == 0 {
                    selection.selectAll(in: tvm.items)
                    return nil
                }
                guard event.keyCode == 51, !selection.selectedIDs.isEmpty else { return event }
                for item in selection.selectedItems(in: tvm.items) { ShelfActionService.remove(item) }
                selection.clear()
                return nil
            }
        }
        .onDisappear {
            if let deleteMonitor { NSEvent.removeMonitor(deleteMonitor) }
            deleteMonitor = nil
        }
    }

    private func focusShelf() {
        guard let delegate = AtollAppDelegate.shared else { return }
        let panel = delegate.windows.first(where: { $0.key.localizedName == vm.screen })?.value ?? delegate.window
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        if let content = panel?.contentView { panel?.makeFirstResponder(content) }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        focusShelf()
        return true
    }

    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }

        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }

        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                ZStack {
                    ShelfBackgroundClickCatcher {
                        guard !selection.isDragging else { return }
                        selection.clear()
                    }

                    content
                        .padding()
                }
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting)
                { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
