//
//  RenamedTypeShims.swift
//  SingleCalendarFeature
//
//  Temporary compatibility aliases for the Stage 1 rename
//  (`AddEditListView` -> `AddEditEventListView`). They exist so an in-flight
//  branch cannot break on a symbol that was only renamed for clarity.
//
//  Delete this file in Stage 8, when the view models are rebuilt as
//  projection facades and the old call shapes are gone. See
//  `REFACTOR_PLAN.md` §1 and §11.
//

import Foundation

@available(*, deprecated, renamed: "AddEditEventListView")
public typealias AddEditListView = AddEditEventListView

@available(*, deprecated, renamed: "AddEditEventListViewModel")
public typealias AddEditListViewModel = AddEditEventListViewModel
