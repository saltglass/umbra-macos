# Adding a settings page

(The General page, `GeneralPage.swift`, is the one page that isn't a group of
Umbra's settings: it is about the app itself, so it is a plain grouped `Form`
with one small view per `Section`, and works while Umbra isn't running. Add
new app-level sections there. Its "Opening torrents" logic is
`DefaultAppModel` in UmbraKit; `WorkspaceDefaultApps` is the part that talks
to macOS.)

Copy `QueueSeedingPage.swift`; it is the pattern. Changes apply as they're
made (no Save button); the model does all the sending, queuing, reverting
and reloading, so a page only lays out rows.

1. **Group:** UmbraKit's `SettingsGroup` already has `.downloads`, `.speed`,
   `.queue`, `.seeding`, `.connection` and `.notifications`
   (`UmbraKit/Sources/UmbraKit/Settings/SettingsGroup.swift`). A new group
   needs its two calls in `SettingsActions.swift` and a `static var` there.
2. **Page file:** `App/Settings/<Name>Page.swift`, a view taking one
   `SettingsGroupModel<…>` per group it shows. Wrap the content in
   `SettingsForm(groups: [...]) { Section { … } }` (it shows the
   not-connected / loading / failed states for you).
3. **Rows:** `SettingsNumberRow` for typed fields (sent on Return or on
   leaving the box) with a `SettingsFormat` (`.wholeNumber()`,
   `.wholeNumber(blank: 0)` for "0 is no limit", `.optionalWholeNumber`,
   `.optionalDecimal()`, `.optionalHoursAsMinutes()`, `.text`,
   `.newSecret`); `SettingsToggleRow` for switches; for a menu,
   `Picker(selection: model.binding(\.field, otherwise: …))` (sent at
   once). Edits touching several fields: `model.change { $0.… }`.
   `umbraName` is the JSON field name Umbra uses in its refusals.
   Section-wide refusals: show `model.pageProblem` with `SettingsProblem`.
4. **Wire it:** in `SettingsWindow.swift`, add a `case` in `content(of:)`
   using `models.model(for: .yourGroup)`.
   (The VPN page is the exception: the VPN isn't a group, so it has its
   own `VpnSettingsModel`, from `models.vpn`; see `VpnPage.swift`.)
5. **Wording, ranges, units:** from Umbra's web page
   (`~/Forgejo/umbra/web/src/pages/settings/`). Never check a value in
   Swift: Umbra refuses it and its message is shown.
6. **Secrets** (mail password): the field is `\.password` on
   `NotificationsDraft` with `.newSecret`; "Remove" calls
   `model.set(\.password, to: .removed)`. Never put one in a fixture.
7. **Snapshots:** add entries to `App/Debug/SettingsSnapshots.swift` with
   fixture models (`.init(.group, fixture: value, refusal: …)` and
   `phase: .notConnected`); run `just snapshot`, view light and dark.
8. **Tests:** the model is already tested; add a `SettingsActionsTests`
   case only for a new group, and test any new `SettingsFormat`.
