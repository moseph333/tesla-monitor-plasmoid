import QtQuick

// A multisampled layer over an item, placed so its texture maps to screen pixels one to
// one. Its children are positioned from that item's corner. The car is drawn in one.
//
// Why a layer and not Shape.CurveRenderer: on Qt 6.7 and 6.8 the curve renderer can keep
// showing paths at an old scale after several quick resizes (QTBUG-133267).
//
// Why it isn't the item's own area: at scale factors like 125 % or 150 % an item rarely
// starts on a device pixel, and a layer there is either blurred (layer.smooth) or has rows
// dropped or repeated. So the layer starts on a multiple of 20 window pixels and is a
// multiple of 20 wide and high, which is a whole number of device pixels at every scale
// factor in steps of 5 %.
//
// The software renderer draws nothing for a Shape in a layer at scale factors above 1, and
// antialiases without one, so it goes without.
Item {
    id: pixelLayer

    // The item to cover. This must be its child.
    required property Item target
    default property alias content: corner.data
    readonly property int grid: 20
    // The item's position in the window (assuming no scaled or rotated ancestor), and how
    // far that is past the grid.
    readonly property point origin: {
        let x = 0
        let y = 0
        for (let item = target; item; item = item.parent) {
            x += item.x
            y += item.y
        }
        return Qt.point(x, y)
    }
    readonly property point past: Qt.point(origin.x - Math.floor(origin.x / grid) * grid,
                                           origin.y - Math.floor(origin.y / grid) * grid)
    x: -past.x
    y: -past.y

    // The layer is on its own item at 0, 0: Qt 6.12 makes a layer a device pixel larger
    // when its item isn't on a device pixel of its parent.
    Item {
        width: Math.ceil((pixelLayer.past.x + Math.floor(pixelLayer.target.width)) / pixelLayer.grid) * pixelLayer.grid
        height: Math.ceil((pixelLayer.past.y + Math.floor(pixelLayer.target.height)) / pixelLayer.grid) * pixelLayer.grid
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.samples: 4

        // The target's corner within the layer, rounded to a whole pixel.
        Item {
            id: corner
            x: Math.round(pixelLayer.past.x)
            y: Math.round(pixelLayer.past.y)
        }
    }
}
