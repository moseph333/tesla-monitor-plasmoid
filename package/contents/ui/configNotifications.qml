import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_notifyChargeComplete: notifyChargeComplete.checked
    property alias cfg_notifyChargeStopped: notifyChargeStopped.checked
    property alias cfg_notifyLeftOpen: notifyLeftOpen.checked
    property alias cfg_notifyUnlocked: notifyUnlocked.checked
    property alias cfg_leftOpenMinutes: leftOpenMinutes.value
    property alias cfg_notifyTires: notifyTires.checked
    property alias cfg_notifyUpdates: notifyUpdates.checked

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: notifyChargeComplete
            Kirigami.FormData.label: i18n("Notify when:")
            text: i18n("Charging finishes")
        }

        QQC2.CheckBox {
            id: notifyChargeStopped
            text: i18n("Charging stops early or the charger loses power")
        }

        QQC2.CheckBox {
            id: notifyLeftOpen
            text: i18n("Something is left open")
        }

        QQC2.CheckBox {
            id: notifyUnlocked
            text: i18n("The car is unlocked with nobody inside")
        }

        // The delay belongs to the two settings above it, so it only matters while one of
        // them is on. The unit sits beside the spin box, not in its text: Plasma's style
        // takes the value as soon as the typed text reads as a number, so with the unit in
        // the text only the first digit typed would be saved. The spin box's own text and
        // parsing follow its locale, digits included, which parseInt() can't read.
        RowLayout {
            Kirigami.FormData.label: i18n("For at least:")
            enabled: notifyLeftOpen.checked || notifyUnlocked.checked
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: leftOpenMinutes
                from: 1
                to: 120
            }

            QQC2.Label {
                text: i18ncp("@label unit after a spin box", "minute", "minutes", leftOpenMinutes.value)
            }
        }

        QQC2.CheckBox {
            id: notifyTires
            text: i18n("A tire's pressure is low")
        }

        QQC2.CheckBox {
            id: notifyUpdates
            text: i18n("A software update is available")
        }

        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Plasma shows these as System Notifications. Copies of the widget that show the same car send each notification once. Nothing is sent for what's already the case when the widget starts.")
        }
    }
}
