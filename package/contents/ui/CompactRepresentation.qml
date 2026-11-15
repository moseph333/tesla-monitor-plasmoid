import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// The widget in a panel: the car as a battery icon, with the level, the range or the time
// to full beside it. Behaves like Plasma's default panel icon, for the mouse, the keyboard
// and screen readers.
MouseArea {
    id: compact

    // main.qml's root item, which knows the car.
    required property PlasmoidItem widget

    readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    // Pressing the icon while the popup is open takes focus from the popup, which closes
    // it before the click arrives. The click goes by the state at the press, or it would
    // open the popup again straight away.
    property bool wasExpanded: false

    Layout.minimumWidth: horizontal ? row.implicitWidth : -1
    hoverEnabled: true
    activeFocusOnTab: true
    onPressed: wasExpanded = widget.expanded
    onClicked: widget.expanded = !wasExpanded

    Keys.onPressed: (event) => {
        if (!widget.isActivationKey(event.key)) return
        Plasmoid.activated()
        // Taken here, so a system tray holding the widget doesn't act on it as well.
        event.accepted = true
    }

    Accessible.role: Accessible.Button
    Accessible.name: Plasmoid.title
    // The tooltip, which is all the icon has to say.
    Accessible.description: widget.toolTipMainText + "; " + widget.toolTipSubText
    Accessible.onPressAction: Plasmoid.activated()

    RowLayout {
        id: row
        anchors.centerIn: parent
        height: parent.height
        spacing: Kirigami.Units.smallSpacing
        // Dimmed while the data is old, so a level from hours ago doesn't pass for now.
        opacity: widget.stale ? 0.5 : 1

        CarBattery {
            // Plasma's small icon size, so it sits near the system tray's battery icon (whose
            // battery shape is 12 px tall) instead of growing with the panel. Thinner panels
            // and vertical panels shrink it to fit.
            readonly property real fitHeight: Math.min(Kirigami.Units.iconSizes.small,
                                                       compact.horizontal ? compact.height : compact.width / aspect)

            Layout.preferredHeight: fitHeight
            Layout.preferredWidth: fitHeight * aspect
            model: widget.carModel
            value: widget.level >= 0 ? widget.level / 100 : -1
            charging: widget.charging
            active: compact.containsMouse
        }

        PlasmaComponents3.Label {
            visible: compact.horizontal && widget.cfg.showPanelPercentage && text !== ""
            text: widget.panelLabel()
            font.features: { "tnum": 1 }
        }
    }
}
