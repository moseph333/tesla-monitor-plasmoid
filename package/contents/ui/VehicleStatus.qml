import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// Doors, openings and Sentry, one per row. A value stays "—" until TeslaMate reports it.
// The rows spread out so the first and last line up with the tire readings beside them.
ColumnLayout {
    id: status

    // Raw TeslaMate values keyed by topic suffix
    property var car: ({})

    function isOpen(key) {
        return Logic.triState(car, key) === true
    }
    function openText(key) {
        const open = Logic.triState(car, key)
        return open === null ? "—" : (open ? i18n("Open") : i18n("Closed"))
    }

    spacing: 0

    component Gap: Item {
        Layout.fillHeight: true
    }

    component StatusRow: RowLayout {
        id: row

        property string label
        property string value
        property bool warn

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: row.label
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            elide: Text.ElideRight
        }

        PlasmaComponents3.Label {
            text: row.value
            color: row.warn ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.weight: Font.DemiBold
        }
    }

    StatusRow {
        label: i18n("Doors")
        value: status.openText("doors_open")
        warn: status.isOpen("doors_open")
    }
    Gap {}
    StatusRow {
        label: i18n("Windows")
        value: status.openText("windows_open")
        warn: status.isOpen("windows_open")
    }
    Gap {}
    StatusRow {
        label: i18n("Trunk")
        value: status.openText("trunk_open")
        warn: status.isOpen("trunk_open")
    }
    Gap {}
    StatusRow {
        label: i18n("Frunk")
        value: status.openText("frunk_open")
        warn: status.isOpen("frunk_open")
    }
    Gap {}
    // An open port is expected while the car is plugged in.
    StatusRow {
        label: i18n("Charge port")
        value: status.openText("charge_port_door_open")
        warn: status.isOpen("charge_port_door_open") && !Logic.bool(status.car, "plugged_in")
    }
    Gap {}
    StatusRow {
        label: i18n("Sentry")
        value: {
            const on = Logic.triState(status.car, "sentry_mode")
            return on === null ? "—" : (on ? i18n("On") : i18n("Off"))
        }
    }
}
