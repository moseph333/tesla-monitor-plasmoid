import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "logic.js" as Logic

KCM.SimpleKCM {
    id: page

    property alias cfg_brokerHost: brokerHost.text
    property alias cfg_brokerPort: brokerPort.value
    property alias cfg_brokerUser: brokerUser.text
    property alias cfg_brokerPassword: brokerPassword.text
    property alias cfg_useTls: useTls.checked
    property alias cfg_caFile: caFile.text
    property alias cfg_topicPrefix: topicPrefix.text
    property alias cfg_refreshSeconds: refreshSeconds.value
    property alias cfg_idleRefreshSeconds: idleRefreshSeconds.value

    // The cars the last Find Cars found, for the picker.
    property var cars: []
    // Which button started the running check: "test" or "find".
    property string pendingCheck: ""
    readonly property bool canCheck: Logic.parseBrokerHost(brokerHost.text).host !== "" && !fetch.busy

    // A result describes the values it ran with, so editing any of them hides it and drops
    // a running check. result.visible is assigned, never bound, because the message's close
    // button assigns it too.
    function formEdited() {
        result.visible = false
        fetch.cancel()
    }

    // Cars found on one broker don't apply to another.
    function brokerEdited() {
        cars = []
        formEdited()
    }

    // TLS brokers usually listen on 8883, others on 1883. The port follows a change of mode
    // only if it still has the other mode's default, so a custom port is kept.
    function followTls(tls) {
        if (tls && brokerPort.value === 1883) brokerPort.value = 8883
        else if (!tls && brokerPort.value === 8883) brokerPort.value = 1883
    }

    function showResult(type, text) {
        result.type = type
        result.text = text
        result.visible = true
    }

    // Both buttons test the values on the page, before they are applied.
    function runCheck(kind) {
        result.visible = false
        pendingCheck = kind
        const started = fetch.run({
            host: brokerHost.text,
            port: brokerPort.value,
            user: brokerUser.text,
            password: brokerPassword.text,
            tls: useTls.checked,
            caFile: caFile.text,
            topics: kind === "find"
                ? ["teslamate/cars/+/display_name", "teslamate/+/cars/+/display_name"]
                : [Logic.topicPrefix(topicPrefix.text) + "/#"],
            wait: 3
        })
        if (!started) showResult(Kirigami.MessageType.Error, i18n("Enter the broker's host name or address."))
    }

    function checkFinished(out, err) {
        if (pendingCheck === "find") carsFound(out, err)
        else connectionTested(out, err)
    }

    function connectionTested(out, err) {
        const prefix = String(fetch.options.topics[0]).replace(/\/#$/, "")
        const values = Logic.parseMqtt(out, prefix)
        const n = Object.keys(values).length
        if (n > 0 && values.display_name)
            showResult(Kirigami.MessageType.Positive, i18np("Found %2, %1 value", "Found %2, %1 values", n, values.display_name))
        else if (n > 0)
            showResult(Kirigami.MessageType.Positive, i18np("Found %1 value", "Found %1 values", n))
        else if (err)
            showResult(Kirigami.MessageType.Error, err)
        else
            showResult(Kirigami.MessageType.Warning, i18n("Connected, but there's no TeslaMate data on %1/#. Try Find Cars, or check that MQTT is enabled in TeslaMate.", prefix))
    }

    function carsFound(out, err) {
        const found = Logic.parseCars(out)
        cars = found
        if (found.length === 1) {
            // Set before showing the message, since editing the prefix hides it.
            topicPrefix.text = found[0].prefix
            showResult(Kirigami.MessageType.Positive, found[0].name
                ? i18n("Found %1. Topic prefix set to %2.", found[0].name, found[0].prefix)
                : i18n("Found a car. Topic prefix set to %1.", found[0].prefix))
        } else if (found.length > 1) {
            carPicker.currentIndex = -1
            showResult(Kirigami.MessageType.Information, i18np("Found %1 car. Choose one:", "Found %1 cars. Choose one:", found.length))
        } else if (err) {
            showResult(Kirigami.MessageType.Error, err)
        } else {
            showResult(Kirigami.MessageType.Warning, i18n("No TeslaMate cars found. Check that MQTT is enabled in TeslaMate and that this account may read teslamate/#."))
        }
    }

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("MQTT broker")
        }

        QQC2.TextField {
            id: brokerHost
            Kirigami.FormData.label: i18n("Host:")
            placeholderText: i18nc("example broker addresses", "192.168.1.x or mqtt.example.com")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
            // People paste what their broker's docs show, e.g. mqtts://user:pw@host:8883/,
            // but mosquitto_sub only takes a bare host, so the other parts move to their
            // own fields. The scheme sets Use TLS, and the port follows as it does for the
            // checkbox (setting checked here doesn't emit toggled). Credentials never
            // overwrite what was typed.
            onEditingFinished: {
                const pasted = Logic.parseBrokerHost(text)
                if (text !== pasted.host) text = pasted.host
                if (pasted.port) brokerPort.value = pasted.port
                else if (pasted.tls !== null) page.followTls(pasted.tls)
                if (pasted.tls !== null) useTls.checked = pasted.tls
                if (pasted.user && brokerUser.text === "") brokerUser.text = pasted.user
                if (pasted.password && brokerPassword.text === "") brokerPassword.text = pasted.password
            }
        }

        QQC2.SpinBox {
            id: brokerPort
            Kirigami.FormData.label: i18n("Port:")
            from: 1
            to: 65535
            editable: true
            textFromValue: (value) => String(value)
            valueFromText: (text) => parseInt(text)
            onValueModified: page.brokerEdited()
        }

        QQC2.TextField {
            id: brokerUser
            Kirigami.FormData.label: i18n("Username:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        Kirigami.PasswordField {
            id: brokerPassword
            Kirigami.FormData.label: i18n("Password:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        QQC2.CheckBox {
            id: useTls
            Kirigami.FormData.label: i18n("Security:")
            text: i18n("Use TLS")
            onToggled: {
                page.followTls(checked)
                page.brokerEdited()
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("CA file:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: useTls.checked
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: caFile
                Layout.fillWidth: true
                placeholderText: i18n("System certificates")
                onTextChanged: page.brokerEdited()
            }

            QQC2.Button {
                text: i18n("Browse…")
                icon.name: "document-open"
                onClicked: caDialog.open()

                QtDialogs.FileDialog {
                    id: caDialog
                    title: i18n("Choose a CA Certificate")
                    nameFilters: [i18n("Certificates (*.pem *.crt *.cer)"), i18n("All files (*)")]
                    // mosquitto_sub needs a path, and a file URL percent-encodes spaces and
                    // the like.
                    onAccepted: caFile.text = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
                }
            }
        }

        Hint {
            text: i18n("Leave the CA file empty to use the system's certificates (needs mosquitto 2.0 or newer). TLS brokers usually listen on port 8883; with mosquitto 2.0, port 8883 always uses TLS. Host must match the name on the broker's certificate.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("TeslaMate")
        }

        QQC2.TextField {
            id: topicPrefix
            Kirigami.FormData.label: i18n("Topic prefix:")
            placeholderText: "teslamate/cars/1"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        Hint {
            text: i18n("If TeslaMate sets MQTT_NAMESPACE, use teslamate/<namespace>/cars/1.")
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Test Connection")
                icon.name: "network-connect"
                enabled: page.canCheck
                onClicked: page.runCheck("test")
            }

            QQC2.Button {
                text: i18n("Find Cars")
                icon.name: "edit-find"
                enabled: page.canCheck
                onClicked: page.runCheck("find")
            }

            QQC2.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                running: fetch.busy
                visible: running
            }

            MqttFetch {
                id: fetch
                onFinished: (out, err) => page.checkFinished(out, err)
            }
        }

        Kirigami.InlineMessage {
            id: result
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            visible: false
            showCloseButton: true
        }

        QQC2.ComboBox {
            id: carPicker
            Kirigami.FormData.label: i18n("Car:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            visible: page.cars.length > 1
            model: page.cars.map(c => c.name ? i18nc("car name (topic prefix)", "%1 (%2)", c.name, c.prefix) : c.prefix)
            displayText: currentIndex < 0 ? i18n("Choose a car…") : currentText
            onActivated: (index) => topicPrefix.text = page.cars[index].prefix
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Refresh")
        }

        // The unit is a label beside each spin box, not part of its text. Plasma's style
        // takes the value as soon as the typed text parses as a number, so with a unit in
        // the text the first digit would be saved and the rest land after the unit. i18np()
        // would also add digit grouping or locale digits that parseInt() can't read back.
        RowLayout {
            Kirigami.FormData.label: i18n("Every:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: refreshSeconds
                from: 5
                to: 600
            }

            QQC2.Label {
                text: i18ncp("@label unit after a spin box", "second", "seconds", refreshSeconds.value)
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("While the car sleeps:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: idleRefreshSeconds
                from: 5
                to: 3600
                stepSize: 5
            }

            QQC2.Label {
                text: i18ncp("@label unit after a spin box", "second", "seconds", idleRefreshSeconds.value)
            }
        }

        Hint {
            text: i18n("Used while the car is asleep or offline and the popup is closed, and always for a widget on the desktop. Opening the popup or pressing Refresh updates right away.")
        }
    }
}
