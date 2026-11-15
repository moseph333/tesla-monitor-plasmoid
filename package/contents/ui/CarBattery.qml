import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

import "models.js" as Models

// The car's side profile, nose right, drawn like a Plasma battery icon: a thin outline at
// half opacity, a gap, and a solid fill that grows left to right. value is 0..1, or below 0
// when the level is unknown. Paths come from models.js.
Item {
    id: car

    property real value: -1
    property bool charging: false
    property bool active: false
    // A key from Models.KEYS.
    property string model: "3"

    readonly property var shape: Models.sideProfile(model)
    readonly property real boxWidth: shape.boxWidth
    readonly property real boxHeight: shape.boxHeight
    readonly property real aspect: boxWidth / boxHeight
    readonly property size pathScale: Qt.size(width / boxWidth, height / boxHeight)
    readonly property color solid: Kirigami.Theme.textColor

    readonly property string outlinePath: shape.outlinePath
    readonly property string fillPath: shape.fillPath
    // The fill with a bolt-shaped gap.
    readonly property string chargingFillPath: shape.chargingFillPath
    readonly property string boltPath: shape.boltPath

    implicitHeight: Kirigami.Units.gridUnit
    implicitWidth: implicitHeight * aspect

    // Drawn in a multisampled layer, not with Shape.CurveRenderer: on Qt 6.7 and 6.8 the
    // curve renderer can miss the last resize while the panel lays out (QTBUG-133267),
    // leaving the car undrawn or at an old size. The layer's item is slightly larger so the
    // outline isn't clipped. The software renderer draws nothing for a Shape in a layer at
    // scale factors above 1, and antialiases without one, so it goes without.
    Item {
        id: canvas
        readonly property real pad: Kirigami.Units.smallSpacing
        x: -pad
        y: -pad
        width: car.width + 2 * pad
        height: car.height + 2 * pad
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.samples: 4

        Item {
            x: canvas.pad
            y: canvas.pad
            width: car.width
            height: car.height

            Shape {
                anchors.fill: parent

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(car.solid.r, car.solid.g, car.solid.b, car.active ? 0.7 : 0.5)
                    strokeWidth: 1
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    scale: car.pathScale
                    PathSvg { path: car.outlinePath }
                }
            }

            Item {
                width: parent.width * Math.max(0, Math.min(1, car.value))
                height: parent.height
                clip: true

                Shape {
                    width: car.width
                    height: car.height

                    ShapePath {
                        fillColor: car.solid
                        strokeColor: "transparent"
                        strokeWidth: 0
                        scale: car.pathScale
                        PathSvg { path: car.charging ? car.chargingFillPath : car.fillPath }
                    }
                }
            }

            Shape {
                anchors.fill: parent
                visible: car.charging

                ShapePath {
                    fillColor: car.solid
                    strokeColor: "transparent"
                    strokeWidth: 0
                    scale: car.pathScale
                    PathSvg { path: car.boltPath }
                }
            }
        }
    }
}
