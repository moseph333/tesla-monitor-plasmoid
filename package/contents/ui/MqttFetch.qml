import QtQuick
import org.kde.plasma.plasma5support as P5Support

import "logic.js" as Logic

// Runs mosquitto_sub for both the widget's poll and the settings page's buttons, and turns
// a failed run into a sentence people can act on.
QtObject {
    id: fetch

    // The running command, or "" when idle.
    property string pending: ""
    readonly property bool busy: pending !== ""
    // What the last run() was given, so messages can name the host, port and topics.
    property var options: ({})

    signal finished(string stdout, string errorText)

    // o = {host, port, user, password, tls, caFile, topics, wait}. Returns false, and runs
    // nothing, when the host can't be used.
    function run(o) {
        const cmd = Logic.mosquittoCommand(o)
        if (!cmd) return false
        options = o
        pending = cmd
        exec.connectSource(cmd)
        return true
    }

    // The running command's result is dropped when it arrives, so settings that just
    // changed can't be overwritten by data from the old ones.
    function cancel() {
        pending = ""
    }

    function message(e) {
        const b = Logic.parseBrokerHost(options.host)
        // Passed as a string so i18n() can't format it as a localized number such as "8,883".
        const port = String(b.port || options.port || 1883)
        switch (e.kind) {
        case "": return ""
        case "notInstalled": return i18n("mosquitto_sub isn't installed. Install the mosquitto package on Fedora or Arch, or mosquitto-clients on Debian and Ubuntu.")
        case "noAnswer": return i18n("%1 didn't answer on port %2. Check the host, the port and any firewall.", b.host, port)
        case "lookup": return i18n("Can't find a host called %1.", b.host)
        case "refused": return i18n("%1 refused the connection on port %2. Check the port.", b.host, port)
        case "unreachable": return i18n("Can't reach %1: %2", b.host, e.detail)
        case "auth": return i18n("The broker rejected the username or password.")
        case "tls": return i18n("The TLS connection failed. Check Use TLS, the port and the CA file, and that Host is the name on the broker's certificate rather than its IP address.")
        case "handshake": return i18n("The broker accepted the connection but didn't answer. If it uses TLS, turn on Use TLS; otherwise check the port.")
        case "oldClient": return i18n("This mosquitto_sub is too old to use the system's certificates (that needs mosquitto 2.0). Choose a CA file instead.")
        case "caFile": return i18n("Can't read the CA file %1.", String(options.caFile || ""))
        case "denied": return i18n("The broker didn't let this account read %1.", (options.topics || []).join(", "))
        case "other": return e.detail
        default: return i18n("mosquitto_sub stopped with exit code %1.", e.detail)
        }
    }

    // The executable engine shares one source between everyone who runs the same command
    // text, which is why the settings page waits 3 seconds where the widget waits 2.
    property QtObject executable: P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            exec.disconnectSource(source)
            if (source !== fetch.pending) return
            fetch.pending = ""
            const out = String(data["stdout"] || "")
            const error = Logic.mqttError(data["exit code"], String(data["stderr"] || ""), out.trim() !== "")
            fetch.finished(out, fetch.message(error))
        }
    }
}
