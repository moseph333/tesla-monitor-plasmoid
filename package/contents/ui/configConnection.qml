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

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("MQTT broker")
        }

        QQC2.TextField {
            id: brokerHost
            Kirigami.FormData.label: i18n("Host:")
            placeholderText: "192.168.1.x or mqtt.moseph.net"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            // People paste whatever their broker's docs show, such as
            // mqtts://user:pw@host:8883/. mosquitto_sub only takes a bare host, so the rest
            // moves to the fields it belongs in. Credentials never overwrite what's typed.
            onEditingFinished: {
                const r = Logic.parseBrokerHost(text)
                if (text !== r.host) text = r.host
                if (r.port) brokerPort.value = r.port
                else if (r.tls === true && brokerPort.value === 1883) brokerPort.value = 8883
                if (r.tls === true) useTls.checked = true
                if (r.user && brokerUser.text === "") brokerUser.text = r.user
                if (r.password && brokerPassword.text === "") brokerPassword.text = r.password
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
        }

        QQC2.TextField {
            id: brokerUser
            Kirigami.FormData.label: i18n("Username:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        }

        Kirigami.PasswordField {
            id: brokerPassword
            Kirigami.FormData.label: i18n("Password:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        }

        QQC2.CheckBox {
            id: useTls
            Kirigami.FormData.label: i18n("Security:")
            text: i18n("Use TLS")
            // Follow the switch only while the port still holds the other mode's usual
            // value, so a custom port is left alone.
            onToggled: {
                if (checked && brokerPort.value === 1883) brokerPort.value = 8883
                else if (!checked && brokerPort.value === 8883) brokerPort.value = 1883
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
            }

            QQC2.Button {
                text: i18n("Browse…")
                icon.name: "document-open"
                onClicked: caDialog.open()

                QtDialogs.FileDialog {
                    id: caDialog
                    title: i18n("Choose a CA Certificate")
                    nameFilters: [i18n("Certificates (*.pem *.crt *.cer)"), i18n("All files (*)")]
                    // mosquitto_sub wants a path, and a file URL escapes spaces and other
                    // characters.
                    onAccepted: caFile.text = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
                }
            }
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
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
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("If TeslaMate sets MQTT_NAMESPACE, use teslamate/<namespace>/cars/1.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Refresh")
        }

        QQC2.SpinBox {
            id: refreshSeconds
            Kirigami.FormData.label: i18n("Every:")
            from: 5
            to: 600
            textFromValue: (value) => i18np("%1 second", "%1 seconds", value)
            valueFromText: (text) => parseInt(text)
        }
    }
}
