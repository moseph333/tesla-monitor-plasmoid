import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// Side profile of a Model 3, nose right, drawn like a Plasma battery icon: a thin half-opacity
// outline, a gap, then a solid fill that grows left to right. The cabin stays empty.
// value is 0..1, or below 0 when the level is unknown.
// The paths use the car's real proportions: 1 unit = 10 mm.
Item {
    id: car

    property real value: -1
    property bool charging: false
    property bool active: false

    readonly property real boxWidth: 477.4
    readonly property real boxHeight: 148.3
    readonly property real aspect: boxWidth / boxHeight
    readonly property size pathScale: Qt.size(width / boxWidth, height / boxHeight)
    readonly property color solid: Kirigami.Theme.textColor

    readonly property string outlinePath: "M 56 131.4 C 44 130 32 126.5 20 120 C 12 108 6 90 4 70 C 4 60 7 50 11 44 C 12 42 14 41 18 41 C 64 34 124 8 224 4 C 266 4 300 24 330 40 C 338 44.5 349 47 362 49 C 389 53 424 60 449 70 C 461 75 469 86 472 95 C 474 104 473 116 467 124 C 463 130 456 132 449 132 L 435.4 132 M 147.9 132 L 343.6 132 M 72.6 114.9 A 29.4 29.4 0 1 0 131.4 114.9 A 29.4 29.4 0 1 0 72.6 114.9 Z M 360.1 114.9 A 29.4 29.4 0 1 0 418.9 114.9 A 29.4 29.4 0 1 0 360.1 114.9 Z"
    readonly property string fillPath: "M 22 56 C 34 52 46 48 58 47 L 326 58 C 344 59.5 354 60 362 61 C 389 65 416 70.5 442 81 C 451 85 456 92 459 99 C 461 105 461 112 456 116 C 453 119 449 120 444 120 L 430.6 120 A 41.4 41.4 0 1 0 348.4 120 L 143.1 120 A 41.4 41.4 0 1 0 60.9 120 L 54 120 C 44 119 37 116 32 112 C 26 103 20 89 17.5 72 C 17 66 18 60 22 56 Z M 88 114.9 A 14 14 0 1 0 116 114.9 A 14 14 0 1 0 88 114.9 Z M 375.5 114.9 A 14 14 0 1 0 403.5 114.9 A 14 14 0 1 0 375.5 114.9 Z"
    // The fill again, with a bolt-shaped gap through it.
    readonly property string chargingFillPath: "M 22 56 C 34 52 46 48 58 47 L 226.3 53.9 L 202.7 88 L 225.7 88 L 217.2 120 L 143.1 120 A 41.4 41.4 0 1 0 60.9 120 L 54 120 C 44 119 37 116 32 112 C 26 103 20 89 17.5 72 C 17 66 18 60 22 56 Z M 277 56 L 326 58 C 344 59.5 354 60 362 61 C 389 65 416 70.5 442 81 C 451 85 456 92 459 99 C 461 105 461 112 456 116 C 453 119 449 120 444 120 L 430.6 120 A 41.4 41.4 0 1 0 348.4 120 L 234.3 120 Z M 88 114.9 A 14 14 0 1 0 116 114.9 A 14 14 0 1 0 88 114.9 Z M 375.5 114.9 A 14 14 0 1 0 403.5 114.9 A 14 14 0 1 0 375.5 114.9 Z"
    readonly property string boltPath: "M 254 28 L 218 80 L 236 80 L 226 118 L 262 64 L 244 64 Z"

    implicitHeight: Kirigami.Units.gridUnit
    implicitWidth: implicitHeight * aspect

    // Not Shape.CurveRenderer: on Qt 6.7 and 6.8 it can miss the last resize while the panel
    // lays out (QTBUG-133267) and leave the car undrawn or at an old size. The icon is drawn
    // into a multisampled layer instead. The layer sits on a slightly larger item so the
    // outline isn't clipped at the edges, and the shapes keep their exact size and position.
    Item {
        id: canvas
        readonly property real pad: Kirigami.Units.smallSpacing
        x: -pad
        y: -pad
        width: car.width + 2 * pad
        height: car.height + 2 * pad
        layer.enabled: true
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
