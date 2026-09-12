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
    @Environment(\.pcVibe) private var vibe

    @FocusState private var nameFieldFocused: Bool
    
    public init(viewModel: PCCalendarCardViewModel, onNameFieldFocusedChanged: ((Int64, Bool) -> Void)? = nil, nameFieldFocused: Bool) {
        self.viewModel = viewModel
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
                        TextField("Calendar name", text: $viewModel.editingName)
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
                        Text("Archived")
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

                Text("Columns: \(viewModel.numberOfColumns)")
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
                    }
                    .transition(.opacity)
                }
            }
            .foregroundColor(.white)
            .padding(20)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isEditing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.6), lineWidth: viewModel.isEditing ? 2 : 1)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isEditing)
        )
        .frame(height: 200)
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
