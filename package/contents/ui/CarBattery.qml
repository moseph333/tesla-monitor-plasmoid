import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

import "models.js" as Models

// Side profile of the car, nose right, drawn like a Plasma battery icon: a thin half-opacity
// outline, a gap, then a solid fill that grows left to right. The cabin stays empty.
// value is 0..1, or below 0 when the level is unknown.
// The paths, from models.js, use each car's real proportions: 1 unit = 10 mm.
Item {
    id: car

    property real value: -1
    property bool charging: false
    property bool active: false
    // Which car: a key from Models.KEYS.
    property string model: "3"

    readonly property var shape: Models.sideProfile(model)
    readonly property real boxWidth: shape.boxWidth
    readonly property real boxHeight: shape.boxHeight
    readonly property real aspect: boxWidth / boxHeight
    readonly property size pathScale: Qt.size(width / boxWidth, height / boxHeight)
    readonly property color solid: Kirigami.Theme.textColor

    readonly property string outlinePath: shape.outlinePath
    readonly property string fillPath: shape.fillPath
    // The fill again, with a bolt-shaped gap through it.
    readonly property string chargingFillPath: shape.chargingFillPath
    readonly property string boltPath: shape.boltPath

    implicitHeight: Kirigami.Units.gridUnit
    implicitWidth: implicitHeight * aspect

    // Not Shape.CurveRenderer: on Qt 6.7 and 6.8 it can miss the last resize while the panel
    // lays out (QTBUG-133267) and leave the car undrawn or at an old size. The icon is drawn
    // into a multisampled layer instead. The layer sits on a slightly larger item so the
    // outline isn't clipped at the edges, and the shapes keep their exact size and position.
    // The software renderer draws nothing for a Shape inside a layer at scale factors above
    // 1, and doesn't need one (it anti-aliases and has no curve renderer), so it skips it.
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
