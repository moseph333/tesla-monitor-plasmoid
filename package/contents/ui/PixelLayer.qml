import QtQuick

// What the car is drawn in: a multisampled layer over the whole of an item, placed so that
// its texture reaches the screen pixel for pixel. Whatever is put in it is placed from
// that item's corner.
// Not Shape.CurveRenderer: on Qt 6.7 and 6.8 it can keep showing the paths at an old
// scale when the row is resized several times in a row while the card lays out
// (QTBUG-133267). A multisampled layer gives the same smooth edges, and the same ones
// on every part. It is never turned; the car turns inside it.
// It does not lie on the item's own area, because at a scale factor such as 125 % or
// 150 % that rarely starts on a device pixel. A layer there reaches the screen blurred
// if it is smoothed (layer.smooth), and with rows left out or repeated if it is not.
// It starts on a multiple of 20 pixels of the window instead and is a multiple of 20
// pixels wide and high, which is a whole number of device pixels at every scale factor
// in steps of 5 %.
// The software renderer draws nothing for a Shape inside a layer at scale factors
// above 1, and doesn't need one (it anti-aliases on its own), so it skips it.
Item {
    id: pixelLayer

    // The item to cover, which this is a child of.
    required property Item target
    default property alias content: corner.data
    readonly property int grid: 20
    // Where the item is in the window, unless something above it is scaled or turned,
    // and how far that is past the grid.
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

    // The layer is on an item of its own at 0, 0, because Qt 6.12 makes a layer a
    // device pixel larger when its item is not on a device pixel of its parent.
    Item {
        width: Math.ceil((pixelLayer.past.x + Math.floor(pixelLayer.target.width)) / pixelLayer.grid) * pixelLayer.grid
        height: Math.ceil((pixelLayer.past.y + Math.floor(pixelLayer.target.height)) / pixelLayer.grid) * pixelLayer.grid
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.samples: 4

        // The item's corner in the layer. It is on a whole pixel even when the item
        // itself is not, so that the drawing is as sharp there.
        Item {
            id: corner
            x: Math.round(pixelLayer.past.x)
            y: Math.round(pixelLayer.past.y)
        }
    }
}
