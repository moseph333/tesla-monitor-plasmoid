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
    property alias cfg_carModel: carModel.currentIndex
    property alias cfg_carColor: carColor.currentIndex
    property alias cfg_showNavigation: showNavigation.checked
    property alias cfg_unlockedOkGeofences: unlockedOkGeofences.text
    property alias cfg_teslamateUrl: teslamateUrl.text

    // What Automatic resolves to on this computer, to show in each combo box.
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

        Hint {
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
            Kirigami.FormData.label: i18n("Car")
        }

        // In the order of Models.KEYS, after Automatic.
        QQC2.ComboBox {
            id: carModel
            Kirigami.FormData.label: i18n("Model:")
            model: [
                i18nc("the car's model", "Automatic (as the car reports)"),
                i18nc("a car model", "Model S"),
                i18nc("a car model", "Model 3"),
                i18nc("a car model", "Model X"),
                i18nc("a car model", "Model Y"),
                i18nc("a car model", "Cybertruck")
            ]
        }

        Hint {
            text: i18n("The shape of the panel icon and of the car in the card. Automatic draws the model the car reports, and a Model 3 when none is reported.")
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

        Hint {
            text: i18n("Doors and windows are reported by driver and passenger side. This puts the driver on the car's right-hand side.")
        }

        QQC2.ComboBox {
            id: carColor
            Kirigami.FormData.label: i18n("Car color:")
            model: [i18n("The car's paint"), i18n("Theme colors")]
        }

        Hint {
            text: i18n("The paint is the one the car reports. When it's missing or unknown, the car is drawn in theme colors.")
        }

        QQC2.CheckBox {
            id: showNavigation
            Kirigami.FormData.label: i18n("Navigation:")
            text: i18n("Show the destination and arrival while driving")
        }

        Hint {
            text: i18n("Uses TeslaMate's active_route topic (TeslaMate 1.29 or newer), which includes the destination's name and location, or the route the other data sources report. With the Tesla Fleet API or Teslemetry, this also asks for the car's location, which shows a location sharing icon in the car.")
        }

        // For owners who leave the car unlocked on purpose, such as in a locked garage.
        QQC2.TextField {
            id: unlockedOkGeofences
            Kirigami.FormData.label: i18n("Unlocked is OK at:")
            placeholderText: i18n("Home, Work")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        }

        Hint {
            text: i18n("TeslaMate geofence names, or Home Assistant zone names, separated by commas. There, an unlocked car isn't shown as a warning or notified. The Tesla Fleet API, Teslemetry and Tessie have no geofences.")
        }

        // Normalized as the widget will open it, so an address typed without http:// shows
        // as the URL it becomes.
        QQC2.TextField {
            id: teslamateUrl
            Kirigami.FormData.label: i18n("TeslaMate:")
            placeholderText: i18nc("example web address", "http://teslamate.local:4000")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onEditingFinished: text = Logic.normalizeUrl(text)
        }

        Hint {
            text: i18n("Click the car's name in the popup, or use the widget's context menu, to open it.")
        }
    }
}
