import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Top-down car outline with a pressure reading at each corner.
RowLayout {
    id: tires

    // Each: { text: "42 psi", warn: bool }
    property var fl: ({ text: "—", warn: false })
    property var fr: ({ text: "—", warn: false })
    property var rl: ({ text: "—", warn: false })
    property var rr: ({ text: "—", warn: false })

    readonly property color lineColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                Kirigami.Theme.textColor.b, 0.35)
    readonly property color glassColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                 Kirigami.Theme.textColor.b, 0.07)

    spacing: Kirigami.Units.largeSpacing

    component Reading: PlasmaComponents3.Label {
        property var tire
        text: tire.text
        color: tire.warn ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        font.weight: tire.warn ? Font.Bold : Font.Normal
        font.features: { "tnum": 1 }
    }

    component Wheel: Rectangle {
        property bool warn
        width: Kirigami.Units.smallSpacing * 1.5
        height: Kirigami.Units.gridUnit * 0.9
        radius: width / 2
        color: warn ? Kirigami.Theme.negativeTextColor : tires.lineColor
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Reading { tire: tires.fl; Layout.alignment: Qt.AlignRight | Qt.AlignTop }
        Item { Layout.fillHeight: true }
        Reading { tire: tires.rl; Layout.alignment: Qt.AlignRight | Qt.AlignBottom }
    }

    Item {
        id: car
        Layout.preferredWidth: Kirigami.Units.gridUnit * 2.6
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5

        Rectangle {
            id: body
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            radius: width * 0.42
            color: "transparent"
            border.color: tires.lineColor
            border.width: 1.5

            // Glass roof
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.3
                width: parent.width * 0.62
                height: parent.height * 0.42
                radius: width * 0.3
                color: tires.glassColor
                border.color: tires.lineColor
                border.width: 1
            }
        }

        Wheel { warn: tires.fl.warn; x: 0; y: car.height * 0.16 }
        Wheel { warn: tires.fr.warn; x: car.width - width; y: car.height * 0.16 }
        Wheel { warn: tires.rl.warn; x: 0; y: car.height * 0.84 - height }
        Wheel { warn: tires.rr.warn; x: car.width - width; y: car.height * 0.84 - height }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Reading { tire: tires.fr; Layout.alignment: Qt.AlignLeft | Qt.AlignTop }
        Item { Layout.fillHeight: true }
        Reading { tire: tires.rr; Layout.alignment: Qt.AlignLeft | Qt.AlignBottom }
    }
}
