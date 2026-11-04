import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_imperial: imperial.checked
    property alias cfg_rangeType: rangeType.currentIndex
    property alias cfg_showPanelPercentage: showPanelPercentage.checked
    property alias cfg_rightHandDrive: rightHandDrive.checked

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Units")
        }

        QQC2.CheckBox {
            id: imperial
            text: i18n("Miles, °F and psi")
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
            text: i18n("Show battery percentage next to the icon")
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
            text: i18n("TeslaMate reports doors and windows by driver and passenger side. This puts the driver on the right of the car drawing.")
        }
    }
}
