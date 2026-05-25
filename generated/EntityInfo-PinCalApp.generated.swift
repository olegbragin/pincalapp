// Generated using the ObjectBox Swift Generator — https://objectbox.io
// DO NOT EDIT

// swiftlint:disable all
import ObjectBox
import Foundation

// MARK: - Entity metadata


extension PPCalendar: ObjectBox.__EntityRelatable {
    internal typealias EntityType = PPCalendar

    internal var _id: EntityId<PPCalendar> {
        return EntityId<PPCalendar>(self.id.value)
    }
}

extension PPCalendar: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = PPCalendarBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "PPCalendar", id: 1)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: PPCalendar.self, id: 1, uid: 733612980013388544)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 5079360852619614208)
        try entityBuilder.addProperty(name: "name", type: PropertyType.string, id: 2, uid: 2197111896515014400)
        try entityBuilder.addProperty(name: "year", type: PropertyType.long, id: 3, uid: 1936306707119382272)
        try entityBuilder.addProperty(name: "numberOfColumns", type: PropertyType.long, id: 4, uid: 2411535501137855488)

        try entityBuilder.lastProperty(id: 4, uid: 2411535501137855488)
    }
}

extension PPCalendar {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPCalendar.id == myId }
    internal static var id: Property<PPCalendar, Id, Id> { return Property<PPCalendar, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPCalendar.name.startsWith("X") }
    internal static var name: Property<PPCalendar, String, Void> { return Property<PPCalendar, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPCalendar.year > 1234 }
    internal static var year: Property<PPCalendar, Int, Void> { return Property<PPCalendar, Int, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPCalendar.numberOfColumns > 1234 }
    internal static var numberOfColumns: Property<PPCalendar, Int, Void> { return Property<PPCalendar, Int, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Use `PPCalendar.events` to refer to this ToMany relation property in queries,
    /// like when using `QueryBuilder.and(property:, conditions:)`.

    internal static var events: ToManyProperty<PPEvent> { return ToManyProperty(.backlinkRelationId(1)) }


    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == PPCalendar {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<PPCalendar, Id, Id> { return Property<PPCalendar, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .name.startsWith("X") }

    internal static var name: Property<PPCalendar, String, Void> { return Property<PPCalendar, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .year > 1234 }

    internal static var year: Property<PPCalendar, Int, Void> { return Property<PPCalendar, Int, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .numberOfColumns > 1234 }

    internal static var numberOfColumns: Property<PPCalendar, Int, Void> { return Property<PPCalendar, Int, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Use `.events` to refer to this ToMany relation property in queries, like when using
    /// `QueryBuilder.and(property:, conditions:)`.

    internal static var events: ToManyProperty<PPEvent> { return ToManyProperty(.backlinkRelationId(1)) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `PPCalendar.EntityBindingType`.
internal final class PPCalendarBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = PPCalendar
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_name = propertyCollector.prepare(string: entity.name)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.year, at: 2 + 2 * 3)
        propertyCollector.collect(entity.numberOfColumns, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_name, at: 2 + 2 * 2)
    }

    internal func postPut(fromEntity entity: EntityType, id: ObjectBox.Id, store: ObjectBox.Store) throws {
        if entityId(of: entity) == 0 {  // New object was put? Attach relations now that we have an ID.
            let events = ToMany<PPEvent>.backlink(
                sourceBox: store.box(for: ToMany<PPEvent>.ReferencedType.self),
                targetId: EntityId<PPCalendar>(id.value),
                relationId: 1)
            if !entity.events.isEmpty {
                events.replace(entity.events)
            }
            entity.events = events
            try entity.events.applyToDb()
        }
    }
    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = PPCalendar()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.name = entityReader.read(at: 2 + 2 * 2)
        entity.year = entityReader.read(at: 2 + 2 * 3)
        entity.numberOfColumns = entityReader.read(at: 2 + 2 * 4)

        entity.events = ToMany<PPEvent>.backlink(
            sourceBox: store.box(for: ToMany<PPEvent>.ReferencedType.self),
            targetId: EntityId<PPCalendar>(entity.id.value),
            relationId: 1)
        return entity
    }
}



extension PPEvent: ObjectBox.__EntityRelatable {
    internal typealias EntityType = PPEvent

    internal var _id: EntityId<PPEvent> {
        return EntityId<PPEvent>(self.id.value)
    }
}

extension PPEvent: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = PPEventBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "PPEvent", id: 2)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: PPEvent.self, id: 2, uid: 4904468296089419008)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 4020757217319346176)
        try entityBuilder.addProperty(name: "name", type: PropertyType.string, id: 2, uid: 584207948386106112)
        try entityBuilder.addProperty(name: "color", type: PropertyType.string, id: 3, uid: 8201044470155641856)
        try entityBuilder.addProperty(name: "date", type: PropertyType.date, id: 4, uid: 3097048831935147264)
        try entityBuilder.addToManyRelation(id: 1, uid: 6203705735387614720,
                                            targetId: 1, targetUid: 733612980013388544)

        try entityBuilder.lastProperty(id: 4, uid: 3097048831935147264)
    }
}

extension PPEvent {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPEvent.id == myId }
    internal static var id: Property<PPEvent, Id, Id> { return Property<PPEvent, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPEvent.name.startsWith("X") }
    internal static var name: Property<PPEvent, String, Void> { return Property<PPEvent, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPEvent.color.startsWith("X") }
    internal static var color: Property<PPEvent, String, Void> { return Property<PPEvent, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { PPEvent.date > 1234 }
    internal static var date: Property<PPEvent, Date, Void> { return Property<PPEvent, Date, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Use `PPEvent.calendars` to refer to this ToMany relation property in queries,
    /// like when using `QueryBuilder.and(property:, conditions:)`.

    internal static var calendars: ToManyProperty<PPCalendar> { return ToManyProperty(.relationId(1)) }


    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == PPEvent {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<PPEvent, Id, Id> { return Property<PPEvent, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .name.startsWith("X") }

    internal static var name: Property<PPEvent, String, Void> { return Property<PPEvent, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .color.startsWith("X") }

    internal static var color: Property<PPEvent, String, Void> { return Property<PPEvent, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .date > 1234 }

    internal static var date: Property<PPEvent, Date, Void> { return Property<PPEvent, Date, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Use `.calendars` to refer to this ToMany relation property in queries, like when using
    /// `QueryBuilder.and(property:, conditions:)`.

    internal static var calendars: ToManyProperty<PPCalendar> { return ToManyProperty(.relationId(1)) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `PPEvent.EntityBindingType`.
internal final class PPEventBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = PPEvent
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_name = propertyCollector.prepare(string: entity.name)
        let propertyOffset_color = propertyCollector.prepare(string: entity.color)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.date, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_name, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_color, at: 2 + 2 * 3)
    }

    internal func postPut(fromEntity entity: EntityType, id: ObjectBox.Id, store: ObjectBox.Store) throws {
        if entityId(of: entity) == 0 {  // New object was put? Attach relations now that we have an ID.
            let calendars = ToMany<PPCalendar>.relation(
                sourceId: EntityId<PPEvent>(id.value),
                targetBox: store.box(for: ToMany<PPCalendar>.ReferencedType.self),
                relationId: 1)
            if !entity.calendars.isEmpty {
                calendars.replace(entity.calendars)
            }
            entity.calendars = calendars
            try entity.calendars.applyToDb()
        }
    }
    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = PPEvent()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.name = entityReader.read(at: 2 + 2 * 2)
        entity.color = entityReader.read(at: 2 + 2 * 3)
        entity.date = entityReader.read(at: 2 + 2 * 4)

        entity.calendars = ToMany<PPCalendar>.relation(
            sourceId: EntityId<PPEvent>(entity.id.value),
            targetBox: store.box(for: ToMany<PPCalendar>.ReferencedType.self),
            relationId: 1)
        return entity
    }
}


/// Helper function that allows calling Enum(rawValue: value) with a nil value, which will return nil.
fileprivate func optConstruct<T: RawRepresentable>(_ type: T.Type, rawValue: T.RawValue?) -> T? {
    guard let rawValue = rawValue else { return nil }
    return T(rawValue: rawValue)
}

// MARK: - Store setup

fileprivate func cModel() throws -> OpaquePointer {
    let modelBuilder = try ObjectBox.ModelBuilder()
    try PPCalendar.buildEntity(modelBuilder: modelBuilder)
    try PPEvent.buildEntity(modelBuilder: modelBuilder)
    modelBuilder.lastEntity(id: 2, uid: 4904468296089419008)
    modelBuilder.lastRelation(id: 1, uid: 6203705735387614720)
    return modelBuilder.finish()
}

extension ObjectBox.Store {
    /// A store with a fully configured model. Created by the code generator with your model's metadata in place.
    ///
    /// # In-memory database
    /// To use a file-less in-memory database, instead of a directory path pass `memory:` 
    /// together with an identifier string:
    /// ```swift
    /// let inMemoryStore = try Store(directoryPath: "memory:test-db")
    /// ```
    ///
    /// - Parameters:
    ///   - directoryPath: The directory path in which ObjectBox places its database files for this store,
    ///     or to use an in-memory database `memory:<identifier>`.
    ///   - maxDbSizeInKByte: Limit of on-disk space for the database files. Default is `1024 * 1024` (1 GiB).
    ///   - fileMode: UNIX-style bit mask used for the database files; default is `0o644`.
    ///     Note: directories become searchable if the "read" or "write" permission is set (e.g. 0640 becomes 0750).
    ///   - maxReaders: The maximum number of readers.
    ///     "Readers" are a finite resource for which we need to define a maximum number upfront.
    ///     The default value is enough for most apps and usually you can ignore it completely.
    ///     However, if you get the maxReadersExceeded error, you should verify your
    ///     threading. For each thread, ObjectBox uses multiple readers. Their number (per thread) depends
    ///     on number of types, relations, and usage patterns. Thus, if you are working with many threads
    ///     (e.g. in a server-like scenario), it can make sense to increase the maximum number of readers.
    ///     Note: The internal default is currently around 120. So when hitting this limit, try values around 200-500.
    ///   - readOnly: Opens the database in read-only mode, i.e. not allowing write transactions.
    ///
    /// - important: This initializer is created by the code generator. If you only see the internal `init(model:...)`
    ///              initializer, trigger code generation by building your project.
    internal convenience init(directoryPath: String, maxDbSizeInKByte: UInt64 = 1024 * 1024,
                            fileMode: UInt32 = 0o644, maxReaders: UInt32 = 0, readOnly: Bool = false) throws {
        try self.init(
            model: try cModel(),
            directory: directoryPath,
            maxDbSizeInKByte: maxDbSizeInKByte,
            fileMode: fileMode,
            maxReaders: maxReaders,
            readOnly: readOnly)
    }
}

// swiftlint:enable all
