import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "logic.js" as Logic

KCM.SimpleKCM {
    property alias cfg_distanceUnit: distanceUnit.currentIndex
    property alias cfg_temperatureUnit: temperatureUnit.currentIndex
    property alias cfg_pressureUnit: pressureUnit.currentIndex
    property alias cfg_rangeType: rangeType.currentIndex
    property alias cfg_showPanelPercentage: showPanelPercentage.checked
    property alias cfg_panelText: panelText.currentIndex
    property alias cfg_panelChargingTime: panelChargingTime.checked
    property alias cfg_rightHandDrive: rightHandDrive.checked
    property alias cfg_carColor: carColor.currentIndex
    property alias cfg_showNavigation: showNavigation.checked
    property alias cfg_unlockedOkGeofences: unlockedOkGeofences.text
    property alias cfg_teslamateUrl: teslamateUrl.text

    // What Automatic means on this computer, so each combo can say which unit it gives.
    readonly property var autoUnits: Logic.resolveUnits(0, 0, 0, Qt.locale().measurementSystem)

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Units")
        }

        QQC2.ComboBox {
            id: distanceUnit
            Kirigami.FormData.label: i18n("Distance:")
            model: [
                i18nc("automatic unit (the unit it gives here)", "Automatic (%1)",
                      autoUnits.distance === "mi" ? i18n("miles") : i18n("kilometers")),
                i18n("Kilometers"),
                i18n("Miles")
            ]
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Speed uses the same unit.")
        }

        QQC2.ComboBox {
            id: temperatureUnit
            Kirigami.FormData.label: i18n("Temperature:")
            model: [
                i18nc("automatic unit (the unit it gives here)", "Automatic (%1)", "°" + autoUnits.temperature),
                "°C",
                "°F"
            ]
        }

        QQC2.ComboBox {
            id: pressureUnit
            Kirigami.FormData.label: i18n("Tire pressure:")
            model: [
                i18nc("automatic unit (the unit it gives here)", "Automatic (%1)", autoUnits.pressure),
                "bar",
                "psi",
                "kPa"
            ]
        }

        QQC2.ComboBox {
            id: rangeType
            Kirigami.FormData.label: i18n("Range:")
            model: [i18n("Rated (matches the car)"), i18n("Estimated"), i18n("Ideal")]
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Panel")
        }

        QQC2.CheckBox {
            id: showPanelPercentage
            text: i18n("Show text next to the icon")
        }

        QQC2.ComboBox {
            id: panelText
            Kirigami.FormData.label: i18n("Text:")
            enabled: showPanelPercentage.checked
            model: [i18n("Battery percentage"), i18n("Range"), i18n("Percentage and range")]
        }

        QQC2.CheckBox {
            id: panelChargingTime
            enabled: showPanelPercentage.checked
            text: i18n("While charging, show the time to full")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Card")
        }

        QQC2.CheckBox {
            id: rightHandDrive
            Kirigami.FormData.label: i18n("Car:")
            text: i18n("Right-hand drive")
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("TeslaMate reports doors and windows by driver and passenger side. This puts the driver on the car's right-hand side.")
        }

        QQC2.ComboBox {
            id: carColor
            Kirigami.FormData.label: i18n("Car color:")
            model: [i18n("The car's paint"), i18n("Theme colors")]
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("The paint comes from TeslaMate. When it's missing or unknown, the car is drawn in theme colors.")
        }

        QQC2.CheckBox {
            id: showNavigation
            Kirigami.FormData.label: i18n("Navigation:")
            text: i18n("Show the destination and arrival while driving")
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Uses TeslaMate's active_route topic (TeslaMate 1.29 or newer), which includes the destination's name and location.")
        }

        // For owners who leave the car unlocked on purpose, such as in a locked garage with
        // Tesla's Exclude Home setting.
        QQC2.TextField {
            id: unlockedOkGeofences
            Kirigami.FormData.label: i18n("Unlocked is OK at:")
            placeholderText: i18n("Home, Work")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("TeslaMate geofence names, separated by commas. There, an unlocked car isn't shown as a warning or notified.")
        }

        // Saved the way the widget opens it, so an address typed without http:// shows
        // here as the URL it will be.
        QQC2.TextField {
            id: teslamateUrl
            Kirigami.FormData.label: i18n("TeslaMate:")
            placeholderText: i18nc("example web address", "http://teslamate.local:4000")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onEditingFinished: text = Logic.normalizeUrl(text)
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Click the car's name in the popup, or use the widget's context menu, to open it.")
        }
    }
}
