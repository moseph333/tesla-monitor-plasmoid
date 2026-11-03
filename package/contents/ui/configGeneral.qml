import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_brokerHost: brokerHost.text
    property alias cfg_brokerPort: brokerPort.value
    property alias cfg_brokerUser: brokerUser.text
    property alias cfg_brokerPassword: brokerPassword.text
    property alias cfg_topicPrefix: topicPrefix.text
    property alias cfg_imperial: imperial.checked
    property alias cfg_rangeType: rangeType.currentIndex
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
        }

        QQC2.SpinBox {
            id: brokerPort
            Kirigami.FormData.label: i18n("Port:")
            from: 1
            to: 65535
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
            Kirigami.FormData.label: i18n("Display")
        }

        QQC2.CheckBox {
            id: imperial
            Kirigami.FormData.label: i18n("Units:")
            text: i18n("Miles, °F and psi")
        }

        QQC2.ComboBox {
            id: rangeType
            Kirigami.FormData.label: i18n("Range:")
            model: [i18n("Rated (matches the car)"), i18n("Estimated"), i18n("Ideal")]
        }

        QQC2.SpinBox {
            id: refreshSeconds
            Kirigami.FormData.label: i18n("Refresh every:")
            from: 5
            to: 600
            textFromValue: (value) => i18np("%1 second", "%1 seconds", value)
            valueFromText: (text) => parseInt(text)
        }
    }
}
