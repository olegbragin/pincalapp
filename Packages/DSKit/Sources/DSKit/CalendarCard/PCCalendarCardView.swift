//
//  PCCalendarCardView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

/// How much of a calendar card to draw.
///
/// `.full` is the screen-size card. `.compact` exists because the collapsed landscape rail is
/// 66pt wide, and the full card cannot be made to fit by shrinking: it is 200pt tall with 20pt
/// of padding and three 28pt buttons, so at that width every one of those becomes the tap
/// target of its neighbour.
public enum PCCardLayout: Sendable, Equatable {
    case full
    case compact
}

public struct PCCalendarCardView: View {
    @Bindable var viewModel: PCCalendarCardViewModel
    var onNameFieldFocusedChanged: ((Int64, Bool) -> Void)?
    private let layout: PCCardLayout

    /// The badge shown on an archived card.
    public let archivedLabel: String

    /// The line under the name, already carrying the column count.
    ///
    /// A finished `String` rather than a format template or a count plus a template, because the
    /// count belongs to the view model and the *sentence* belongs to the caller — a translator is
    /// entitled to reorder the two, and `String(format:)` against a template this package owned
    /// would quietly assume they do not.
    public let columnsLabel: String

    /// Placeholder for the rename field.
    public let namePlaceholder: String

    @Environment(\.pcVibe) private var vibe

    @FocusState private var nameFieldFocused: Bool

    public init(
        viewModel: PCCalendarCardViewModel,
        archivedLabel: String,
        columnsLabel: String,
        namePlaceholder: String,
        onNameFieldFocusedChanged: ((Int64, Bool) -> Void)? = nil,
        nameFieldFocused: Bool,
        layout: PCCardLayout = .full
    ) {
        self.layout = layout
        self.viewModel = viewModel
        self.archivedLabel = archivedLabel
        self.columnsLabel = columnsLabel
        self.namePlaceholder = namePlaceholder
        self.onNameFieldFocusedChanged = onNameFieldFocusedChanged
        self.nameFieldFocused = nameFieldFocused
    }

    public var body: some View {
        Group {
            if layout == .compact {
                compactCard
            } else {
                fullCard
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isEditing)
    }

    /// Name and column count only.
    ///
    /// The pencil and trash are gone rather than shrunk. At 66pt there is no width at which a
    /// 28pt button is still distinguishable from its neighbour, and a control too small to hit
    /// is worse than an absent one — so renaming and archiving stay on the expanded list, and
    /// this rail's job is to switch calendars and get out of the way.
    private var compactCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(vibe.cardGradient())

            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.name)
                    .font(vibe.font(for: .metadata))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(columnsLabel)
                    .font(vibe.font(for: .metadata))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var fullCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(vibe.cardGradient())

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear, .black.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: viewModel.isArchived ? "archivebox" : "calendar")
                        .font(vibe.font(for: .headerIcon))
                    if viewModel.isEditing {
                        TextField(namePlaceholder, text: $viewModel.editingName)
                            .font(vibe.font(for: .title))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.white.opacity(0.15))
                            )
                            .focused($nameFieldFocused)
                            .submitLabel(.done)
                            .onAppear {
                                nameFieldFocused = true
                            }
                            .onSubmit {
                                confirmEdit()
                            }
                            .accessibilityIdentifier("card-name-field-\(viewModel.id)")
                    } else {
                        Text(viewModel.name)
                            .font(vibe.font(for: .title))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    if viewModel.isArchived {
                        Text(archivedLabel)
                            .font(vibe.font(for: .badge))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.15)))
                    } else if viewModel.isEditing {
                        Button {
                            confirmEdit()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(vibe.font(for: .toolbarIcon))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                )
                        }
                        .accessibilityIdentifier("card-confirm-edit-\(viewModel.id)")
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    } else {
                        Button {
                            viewModel.startEditing()
                        } label: {
                            Image(systemName: "pencil")
                                .font(vibe.font(for: .toolbarIcon))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                )
                        }
                        .accessibilityIdentifier("card-edit-\(viewModel.id)")
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }

                Text(columnsLabel)
                    .font(vibe.font(for: .metadata))
                    .opacity(0.7)
                    .padding(.top, 2)

                Spacer(minLength: 0)

                if viewModel.isArchived {
                    HStack(spacing: 12) {
                        Spacer()
                        Button {
                            viewModel.onRestore?()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(vibe.font(for: .footerIcon))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("card-restore-\(viewModel.id)")
                        Button {
                            viewModel.onPermanentDelete?()
                        } label: {
                            Image(systemName: "trash")
                                .font(vibe.font(for: .footerIcon))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("card-permanent-delete-\(viewModel.id)")
                    }
                    .transition(.opacity)
                } else {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.onDelete?()
                        } label: {
                            Image(systemName: "trash")
                                .font(vibe.font(for: .footerIcon))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(.white.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("card-archive-\(viewModel.id)")
                    }
                    .transition(.opacity)
                }
            }
            .foregroundColor(.white)
            .padding(20)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isEditing)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.6), lineWidth: viewModel.isEditing ? 2 : 1)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isEditing)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEditing)
        .onChange(of: nameFieldFocused) { _, isFocused in
            if isFocused {
                onNameFieldFocusedChanged?(viewModel.id, true)
            } else if viewModel.isEditing {
                confirmEdit()
            }
        }
    }

    /// Resigns focus before committing so the focused `TextField` is never
    /// removed from the hierarchy (removing a still-focused field triggers a
    /// UIKit `UIFocusSystem` assertion on iOS 26, which crashes the app).
    ///
    /// Only reachable from the full layout: the compact card has no rename field.
    private func confirmEdit() {
        nameFieldFocused = false
        viewModel.confirmEdit()
    }
}
