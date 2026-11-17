import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

// Temperatures, climate and odometer, side by side on one tinted surface.
Rectangle {
    // main.qml's root item, which has the car's state, and the card's Look.
    required property PlasmoidItem widget
    required property Look look

    implicitHeight: stats.implicitHeight + stats.anchors.topMargin + stats.anchors.bottomMargin
    radius: look.radius
    color: look.surface

    RowLayout {
        id: stats

        // Logic.climateMode(): preconditioning, dog, camp, keep, defrost, on, overheat, off
        // or null.
        readonly property var climateMode: Logic.climateMode(widget.car)
        readonly property bool climateActive: climateMode !== null && climateMode !== "off"
        // The temperature the climate is set to, for the modes that heat or cool to it.
        readonly property var setTemp: ["preconditioning", "dog", "camp", "keep", "on"].includes(climateMode)
            ? Logic.num(widget.car, "driver_temp_setting") : null
        // The width of an equal share. Cells are equally wide, except one whose text needs
        // more (such as "Preconditioning"): it gets what it asks for and the rest share
        // what is left, so the dividers barely move when a text changes. 0 when the strip
        // is too narrow, and the layout then shrinks every cell.
        readonly property real share: {
            const needs = [inside, outside, climate, odometer].map(cell => cell.implicitWidth)
            needs.sort((a, b) => b - a)
            let room = width
            let cells = needs.length
            for (const need of needs) {
                if (need * cells <= room) break
                room -= need
                cells--
            }
            return cells > 0 ? room / cells : 0
        }

        anchors.fill: parent
        anchors.topMargin: Kirigami.Units.smallSpacing * 1.5
        anchors.bottomMargin: Kirigami.Units.smallSpacing * 1.5
        spacing: 0

        Stat {
            id: inside
            Layout.fillWidth: true
            Layout.preferredWidth: Math.max(implicitWidth, stats.share)
            divider: false
            label: i18n("Inside")
            value: widget.fmtTemp(Logic.num(widget.car, "inside_temp"))
        }
        Stat {
            id: outside
            Layout.fillWidth: true
            Layout.preferredWidth: Math.max(implicitWidth, stats.share)
            label: i18n("Outside")
            value: widget.fmtTemp(Logic.num(widget.car, "outside_temp"))
        }
        Stat {
            id: climate
            Layout.fillWidth: true
            Layout.preferredWidth: Math.max(implicitWidth, stats.share)
            label: {
                switch (stats.climateMode) {
                case "preconditioning": return i18n("Preconditioning")
                case "dog": return i18n("Dog Mode")
                case "camp": return i18n("Camp Mode")
                case "keep": return i18n("Keep Climate")
                case "defrost": return i18n("Defrosting")
                case "overheat": return i18nc("cabin overheat protection is cooling the car", "Cabin Cooling")
                default: return i18n("Climate")
                }
            }
            // The set temperature while it's on, if the source gives it. A dash while the
            // climate hasn't been reported.
            value: stats.setTemp !== null ? widget.fmtTemp(stats.setTemp)
                : stats.climateActive ? i18n("On")
                : stats.climateMode === null ? "—" : i18n("Off")
            dot: stats.climateActive
        }
        Stat {
            id: odometer
            Layout.fillWidth: true
            Layout.preferredWidth: Math.max(implicitWidth, stats.share)
            label: i18n("Odometer")
            value: widget.fmtDistance(Logic.num(widget.car, "odometer"))
        }
    }
}
