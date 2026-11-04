import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// 270° arc with an optional limit tick. value and marker are 0..1 (marker < 0 hides it).
Item {
    id: ring

    property real value: 0
    property real marker: -1
    property color color: Kirigami.Theme.highlightColor
    property string centerText
    property string subText
    property string noteText
    property real thickness: Math.max(4, Math.round(width * 0.07))

    implicitWidth: Kirigami.Units.gridUnit * 8
    implicitHeight: implicitWidth

    readonly property real clamped: Math.max(0, Math.min(1, value))
    property real shown: clamped
    Behavior on shown {
        NumberAnimation { duration: Kirigami.Units.longDuration * 2; easing.type: Easing.OutCubic }
    }

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real radius: (Math.min(width, height) - thickness) / 2 - 2
    readonly property real markerAngle: (135 + 270 * Math.max(0, Math.min(1, marker))) * Math.PI / 180
    readonly property color track: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                            Kirigami.Theme.textColor.b, 0.12)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.track
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.cx; centerY: ring.cy
                radiusX: ring.radius; radiusY: ring.radius
                startAngle: 135; sweepAngle: 270
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.shown > 0.002 ? ring.color : "transparent"
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.cx; centerY: ring.cy
                radiusX: ring.radius; radiusY: ring.radius
                startAngle: 135; sweepAngle: 270 * ring.shown
            }
        }

        // Charge limit tick
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.marker >= 0 ? Kirigami.Theme.textColor : "transparent"
            strokeWidth: Math.max(2, ring.thickness * 0.3)
            capStyle: ShapePath.RoundCap
            startX: ring.cx + (ring.radius - ring.thickness * 0.95) * Math.cos(ring.markerAngle)
            startY: ring.cy + (ring.radius - ring.thickness * 0.95) * Math.sin(ring.markerAngle)
            PathLine {
                x: ring.cx + (ring.radius + ring.thickness * 0.95) * Math.cos(ring.markerAngle)
                y: ring.cy + (ring.radius + ring.thickness * 0.95) * Math.sin(ring.markerAngle)
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        PlasmaComponents3.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ring.centerText
            font.pixelSize: Math.round(ring.width * 0.2)
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        PlasmaComponents3.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ring.subText
            font.pixelSize: Math.round(ring.width * 0.085)
            opacity: 0.7
            visible: text.length > 0
        }

        // A caveat about the numbers above it, such as how much of a cold battery is usable,
        // so it takes the neutral color.
        PlasmaComponents3.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ring.noteText
            font.pixelSize: Math.round(ring.width * 0.075)
            color: Kirigami.Theme.neutralTextColor
            visible: text.length > 0
        }
    }
}
