import QtQuick

import "logic.js" as Logic

// One secret on the settings page: where it's saved, and where Apply would save it. A
// value is the secret as the page's fields hold it, "" for none. With a wallet, a changed
// value goes there under a new id, so the widget sees the change and reads it again;
// without one, it goes in the settings in plain text.
QtObject {
    id: secret

    required property Keyring keyring
    // The entry's name in the wallet.
    required property string label

    // As saved: the value, its id in the wallet ("" if it isn't there), and whether it's in
    // the settings instead.
    property string savedValue: ""
    property string savedId: ""
    property bool savedPlain: false
    // True while the saved value is being read from the wallet.
    property bool reading: false
    // The saved value is in the wallet but couldn't be read, so the fields are empty, and
    // leaving them empty keeps it.
    property bool unread: false
    // The wallet didn't take what the last Apply sent; storeError is secret-tool's reason.
    property bool storeFailed: false
    property string storeError: ""
    // The id the next changed value goes under.
    property string nextId: Logic.newKeyringId(Date.now(), Math.random())

    // The saved state went back after a failed store, so the page should work out its
    // cfg_ values again.
    signal reverted()

    // Starts from the settings: the secret's id, or its plain value without one. A value
    // read from the wallet is passed to read().
    function load(id, plainValue, read) {
        savedId = id
        savedPlain = !id && plainValue !== ""
        savedValue = id ? "" : plainValue
        if (!id) return
        reading = true
        keyring.lookup(id, result => {
            secret.reading = false
            if (result.status === "ok") {
                // Saved first, so the fields' change reads as no change.
                secret.savedValue = result.value
                read(result.value)
            } else {
                secret.unread = true
            }
        })
    }

    // Whether value is the one saved in plain text, which Apply would move into the wallet.
    function moving(value) {
        return value === savedValue && savedPlain && keyring.ready
    }

    // Where Apply would save value: {id, plain}, plain being true for the settings. A value
    // as it was stays where it is, unless it can move from the settings into the wallet; an
    // emptied one is removed.
    function target(value) {
        if (moving(value)) return { id: nextId, plain: false }
        if (value === savedValue) return { id: savedId, plain: savedPlain }
        if (value === "") return { id: "", plain: false }
        if (keyring.ready) return { id: nextId, plain: false }
        return { id: "", plain: true }
    }

    // Does the wallet's part of Apply. It runs in the background and finishes even if the
    // settings close first; a failure after that has no page to show it on.
    function save(value) {
        storeFailed = false
        const where = target(value)
        const before = { value: savedValue, id: savedId, plain: savedPlain }
        if (where.id && where.id !== savedId) {
            keyring.store(where.id, label, value, savedId, result => secret.stored(result, before))
            nextId = Logic.newKeyringId(Date.now(), Math.random())
        } else if (!where.id && savedId && keyring.ready) {
            keyring.clear(savedId)
        }
        if (value !== savedValue) unread = false
        savedValue = value
        savedId = where.id
        savedPlain = where.plain
    }

    // The settings already point at the new entry, which isn't there, so the saved state
    // goes back to what really is, and Apply tries again.
    function stored(result, before) {
        if (result.status === "ok") return
        savedValue = before.value
        savedId = before.id
        savedPlain = before.plain
        if (result.status === "missing") keyring.setAvailability("missing", "")
        storeError = result.status === "missing" ? "" : result.detail
        storeFailed = true
        reverted()
    }
}
