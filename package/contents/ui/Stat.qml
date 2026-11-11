import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// One cell of the card's stats strip: a value over its label, centered. Every cell after
// the first draws the hairline between it and the cell before it.
Item {
    id: stat

    property string label
    property string value
    // A small dot in the highlight color before the value, for something that is on.
    property bool dot: false
    // The hairline on the side the row starts from, which a row's first cell turns off.
    property bool divider: true

    // The card writes a value it doesn't know as a dash. It's drawn lighter than a
    // reading, so a row of dashes doesn't weigh as much as a row of numbers.
    readonly property bool unknown: value === "—"

    // The texts with some air beside them. A cell that gets less than it asks for still
    // shows them whole until they come as near to its edges as the column's margins.
    implicitWidth: Math.max(valueRow.implicitWidth, labelText.implicitWidth) + 2 * Kirigami.Units.largeSpacing
    implicitHeight: column.implicitHeight

    Look { id: look }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        visible: stat.divider
        color: look.hairline
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: 0

        // As wide as the dot and the value, so the two are centered together, and no
        // wider than the cell, so a long value elides.
        RowLayout {
            id: valueRow
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: false
            Layout.maximumWidth: column.width
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                visible: stat.dot
                implicitWidth: Kirigami.Units.smallSpacing * 1.5
                implicitHeight: implicitWidth
                radius: width / 2
                color: Kirigami.Theme.highlightColor
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: stat.value
                opacity: stat.unknown ? look.faint : 1
                font.weight: stat.unknown ? Font.Normal : Font.DemiBold
                font.features: { "tnum": 1 }
                elide: Text.ElideRight
            }
        }

        PlasmaComponents3.Label {
            id: labelText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: stat.label
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: look.secondary
            elide: Text.ElideRight
        }
    }
}
