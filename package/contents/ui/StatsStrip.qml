import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

// The temperatures, the climate and the odometer, side by side on one tinted surface.
Rectangle {
    // main.qml's root item, which knows the car, and the card's Look.
    required property PlasmoidItem widget
    required property Look look

    implicitHeight: stats.implicitHeight + stats.anchors.topMargin + stats.anchors.bottomMargin
    radius: look.radius
    color: look.surface

    RowLayout {
        id: stats

        readonly property bool climateOn: Logic.bool(widget.car, "is_climate_on")
        readonly property bool preconditioning: Logic.bool(widget.car, "is_preconditioning")
        // The cells are as wide as each other, except one whose texts need
        // more than its share, as "Preconditioning" does. That one gets what
        // it asks for and the others share the rest, so the hairlines hardly
        // move when a text changes. This is the width of the cells that
        // share. It is 0 when the strip is too narrow for what the cells ask
        // for, and the layout then shrinks them all.
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
            label: stats.preconditioning ? i18n("Preconditioning") : i18n("Climate")
            // A dash, like the readings beside it, while TeslaMate hasn't said
            // whether the climate is on.
            value: stats.preconditioning || stats.climateOn ? i18n("On")
                : Logic.triState(widget.car, "is_climate_on") === null ? "—" : i18n("Off")
            dot: stats.preconditioning || stats.climateOn
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
