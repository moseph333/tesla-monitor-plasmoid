import QtQuick
import org.kde.plasma.plasma5support as P5Support

import "logic.js" as Logic

// Keeps the widget's secrets in the Secret Service through secret-tool: KWallet on Plasma,
// or another keyring such as GNOME Keyring. Callbacks get Logic.keyringResult()'s
// {status, value, detail}.
QtObject {
    id: keyring

    // What lookups have shown: "unknown" until one answers, then "ready", "missing" (no
    // secret-tool) or "unavailable" (no Secret Service), with secret-tool's reason in detail.
    // Set through setAvailability() only.
    property string availability: "unknown"
    property string detail: ""
    // Not a binding on availability, which might not have updated yet when a handler of
    // availabilityChanged reads it.
    property bool ready: false

    // Sets ready and detail before availability, so its handlers see all three agree.
    function setAvailability(value, reason) {
        ready = value === "ready"
        detail = reason || ""
        availability = value
    }

    // The callbacks waiting for each running command. The executable engine runs a given
    // command line once at a time, so a second call waits for the first one's result.
    property var callbacks: ({})

    // Checks for secret-tool and a Secret Service without opening the wallet.
    function probe(callback) {
        lookup("", callback)
    }

    function lookup(id, callback) {
        run(Logic.keyringLookupCommand(id), result => {
            keyring.setAvailability(result.status === "missing" ? "missing"
                : result.status === "error" ? "unavailable" : "ready", result.detail)
            if (callback) callback(result)
        })
    }

    // Saves secret under id, then deletes the entry under oldId, if any.
    function store(id, label, secret, oldId, callback) {
        run(Logic.keyringStoreCommand(id, label, secret, oldId), callback)
    }

    function clear(id, callback) {
        run(Logic.keyringClearCommand(id), callback)
    }

    function run(command, callback) {
        (callbacks[command] = callbacks[command] || []).push(callback || null)
        exec.connectSource(command)
    }

    property QtObject executable: P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            exec.disconnectSource(source)
            const waiting = keyring.callbacks[source] || []
            delete keyring.callbacks[source]
            const result = Logic.keyringResult(data["exit code"], data["stdout"], data["stderr"])
            for (const callback of waiting)
                if (callback) callback(result)
        }
    }
}
