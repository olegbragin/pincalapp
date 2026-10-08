//
//  PCCalendarCardView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

public struct PCCalendarCardView: View {
    @Bindable var viewModel: PCCalendarCardViewModel
    var onNameFieldFocusedChanged: ((Int64, Bool) -> Void)?

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
        nameFieldFocused: Bool
    ) {
        self.viewModel = viewModel
        self.archivedLabel = archivedLabel
        self.columnsLabel = columnsLabel
        self.namePlaceholder = namePlaceholder
        self.onNameFieldFocusedChanged = onNameFieldFocusedChanged
        self.nameFieldFocused = nameFieldFocused
    }

    public var body: some View {
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
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isEditing)
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
    private func confirmEdit() {
        nameFieldFocused = false
        viewModel.confirmEdit()
    }
}
