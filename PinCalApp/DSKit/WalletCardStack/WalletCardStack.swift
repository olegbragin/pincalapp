//
//  WalletCardStack.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 14.08.2026.
//

import SwiftUI

/// A stacked deck of cards.
/// Cards overlap vertically; the first item is frontmost. The user taps a card
/// to select it or swipes left to remove it.
struct WalletCardStack<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var aspectRatio: CGFloat
    var maxCardHeight: CGFloat
    var editingCardHeight: CGFloat
    var peek: CGFloat
    var horizontalPadding: CGFloat
    var onSelect: (Item) -> Void
    var onRemove: ((Item) -> Void)?
    var editingID: AnyHashable?
    let cardContent: (Item, CGFloat, CGFloat, Bool) -> Content

    init(
        items: [Item],
        aspectRatio: CGFloat = 1.586,
        maxCardHeight: CGFloat = 200,
        editingCardHeight: CGFloat = 320,
        peek: CGFloat = 72,
        horizontalPadding: CGFloat = 12,
        onSelect: @escaping (Item) -> Void,
        onRemove: ((Item) -> Void)? = nil,
        editingID: AnyHashable? = nil,
        @ViewBuilder cardContent: @escaping (Item, CGFloat, CGFloat, Bool) -> Content
    ) {
        self.items = items
        self.aspectRatio = aspectRatio
        self.maxCardHeight = maxCardHeight
        self.editingCardHeight = editingCardHeight
        self.peek = peek
        self.horizontalPadding = horizontalPadding
        self.onSelect = onSelect
        self.onRemove = onRemove
        self.editingID = editingID
        self.cardContent = cardContent
    }

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = max(0, proxy.size.width - horizontalPadding * 2)
            let normalCardHeight = min(maxCardHeight, cardWidth / aspectRatio)
            let totalContentHeight = normalCardHeight + peek * CGFloat(max(0, items.count - 1))

            ZStack(alignment: .top) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isEditing = editingID == AnyHashable(item.id)
                    let isCovering = editingIndex != nil && index < editingIndex!
                    let cardHeight = isEditing ? editingCardHeight : normalCardHeight
                    let dragOffset = dragOffsets[item.id, default: 0]

                    cardContent(item, cardWidth, cardHeight, isEditing)
                        .allowsHitTesting(!isCovering)
                        .frame(width: cardWidth, height: cardHeight)
                        .position(
                            x: proxy.size.width / 2,
                            y: stackY(for: index, normalHeight: normalCardHeight) + cardHeight / 2
                        )
                        .offset(x: dragOffset)
                        .opacity(dragOffset < -cardWidth * 0.6 ? 0 : 1)
                        .zIndex(zIndex(for: index))
                        .onTapGesture {
                            guard !isEditing else { return }
                            onSelect(items[index])
                        }
                        .simultaneousGesture(
                            !isEditing && onRemove != nil
                                ? DragGesture(minimumDistance: 50, coordinateSpace: .local)
                                    .onChanged { value in
                                        guard value.translation.width < 0 else { return }
                                        withAnimation(.interactiveSpring()) {
                                            dragOffsets[item.id] = value.translation.width
                                        }
                                    }
                                    .onEnded { value in
                                        if value.translation.width < -120 {
                                            let removedItem = item
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                dragOffsets[item.id] = -cardWidth - 40
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                                onRemove?(removedItem)
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.35)) {
                                                dragOffsets[item.id] = 0
                                            }
                                        }
                                    }
                                : nil
                        )
                }
            }
            .contentShape(Rectangle())
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: editingID)
            .frame(width: proxy.size.width, height: totalContentHeight, alignment: .top)
        }
    }

    @State private var dragOffsets: [AnyHashable: CGFloat] = [:]

    private func normalY(for index: Int) -> CGFloat {
        CGFloat(max(0, items.count - 1 - index)) * peek
    }

    private func stackY(for index: Int, normalHeight: CGFloat) -> CGFloat {
        guard let editIndex = editingIndex else {
            return normalY(for: index)
        }

        if index == editIndex {
            return normalY(for: index)
        } else if index > editIndex {
            return normalY(for: index)
        } else {
            let editingTop = normalY(for: editIndex)
            let revealY = editingTop + editingCardHeight * 0.9
            let cardsAboveCount = editIndex - index
            return revealY + CGFloat(cardsAboveCount - 1) * peek
        }
    }

    private func zIndex(for index: Int) -> Double {
        guard let editingIndex else {
            return -Double(index)
        }

        if index < editingIndex {
            return 200 + Double(editingIndex - index)
        } else if index == editingIndex {
            return 100
        } else {
            return -Double(index)
        }
    }

    private var editingIndex: Int? {
        guard let editingID else { return nil }
        return items.firstIndex { AnyHashable($0.id) == editingID }
    }
}
