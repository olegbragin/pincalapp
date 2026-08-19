//
//  CalendarCardView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct CalendarCardView: View {
    @Bindable var viewModel: CalendarCardViewModel
    var onTap: (() -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(viewModel.gradient)

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
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                    Text(viewModel.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    if viewModel.isEditing {
                        Button {
                            viewModel.confirmEdit()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    } else {
                        Button {
                            viewModel.startEditing()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }

                Text("Columns: \(viewModel.numberOfColumns)")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.7)
                    .padding(.top, 2)

                Spacer(minLength: 0)

                if viewModel.isEditing {
                    TextField("Calendar name", text: $viewModel.editingName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.15))
                        )
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
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
        .frame(height: 200)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isEditing)
        .onTapGesture {
            if !viewModel.isEditing {
                onTap?()
            }
        }
    }
}
