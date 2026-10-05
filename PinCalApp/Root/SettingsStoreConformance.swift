//
//  SettingsStoreConformance.swift
//  PinCalApp
//

import CorePersistence
import SettingsFeature

/// The join between the settings port and the store that satisfies it.
///
/// The whole file. `UserDefaultsSettingsStore` lives in `CorePersistence` and `SettingsPersisting` is
/// declared in `SettingsFeature`, and neither package depends on the other — so the layer that can
/// see both is the only one allowed to say that one satisfies the other. This is the same
/// arrangement as `CalendarStore`, which exists beside it for the same reason, and the port's own
/// doc records why the implementation is not simply declared next to the protocol.
///
/// **Empty on purpose.** The store already has the three properties the port asks for, as stored
/// `@Observable` ones that write through to `UserDefaults`, so there is nothing to forward and no
/// second place for a setting's behaviour to live.
///
/// `@retroactive` is required, not decoration. The type is owned by `CorePersistence` and the
/// protocol by `SettingsFeature`, so a conformance declared here is in a third module — which is
/// exactly the case the attribute exists for. Without it the compiler warns that this "will not
/// behave correctly if the owners of `UserDefaultsSettingsStore` introduce this conformance in the
/// future", and *with* it the same thing is true in a form that only shows up as a
/// duplicate-conformance error if either package ever adds it. So this is a real fragility, recorded
/// here so that a future reader does not read the attribute as a mistake and delete it.
///
/// When a second backend arrives it will be a second type, and this grows by one line: another
/// `extension SomeOtherStore: @retroactive SettingsPersisting {}`. `PCAppSession.makeSettingsStore()`
/// is where the choice between them is made.
extension UserDefaultsSettingsStore: @retroactive SettingsPersisting {}
