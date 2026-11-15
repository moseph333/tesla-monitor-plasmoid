import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// The card's footer: the car's software version, an update's status, and when the data
// arrived. An update's status moves to a line of its own when one line can't hold
// everything, as on a narrow card or during a download. The version and the status are as
// wide as their texts, to the next whole pixel, and give way when even that is too much,
// so a long version elides rather than widen the card.
GridLayout {
    id: footer

    // main.qml's root item, which knows the car, and the card's Look.
    required property PlasmoidItem widget
    required property Look look

    // Moving the status to the other line resizes the car, which mustn't
    // happen each time a poll fails or the hour gains a digit. So the warning
    // icon keeps its place while it's hidden, and the time counts as wide as
    // it gets.
    readonly property bool oneLine: softwareVersion.implicitWidth + updateStatus.implicitWidth
                                    + freshness.implicitWidth
                                    + Math.max(0, widestUpdated.advanceWidth - updated.implicitWidth)
                                    + 2 * columnSpacing <= width

    columns: 3
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: Kirigami.Units.smallSpacing * 1.5

    // An hour of two digits, on a 12 hour clock and on a 24 hour clock, and
    // today, so no weekday comes with it.
    TextMetrics {
        id: widestUpdated
        font: updated.font
        text: {
            const late = new Date()
            late.setHours(22, 0, 0, 0)
            return widget.updatedText(late)
        }
    }

    PlasmaComponents3.Label {
        id: softwareVersion
        Layout.row: 0
        Layout.column: 0
        Layout.fillWidth: true
        Layout.maximumWidth: Math.ceil(implicitWidth)
        visible: text !== ""
        elide: Text.ElideRight
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.features: { "tnum": 1 }
        opacity: look.secondary
        text: widget.car.version ? i18n("Software %1", widget.car.version) : ""
        textFormat: Text.PlainText
    }

    // The update's status on a tint of the highlight color, which fills from
    // the start as the download or the installation goes on. The tint is a
    // little taller than the line of text, without making the footer taller.
    Item {
        id: updateStatus

        property real progress: widget.softwareUpdate.percent !== null
            ? Math.max(0, Math.min(1, widget.softwareUpdate.percent / 100)) : 0
        Behavior on progress {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
        }

        Layout.row: footer.oneLine ? 0 : 1
        Layout.column: footer.oneLine ? 1 : 0
        Layout.columnSpan: footer.oneLine ? 1 : 3
        Layout.fillWidth: true
        Layout.maximumWidth: Math.ceil(implicitWidth)
        visible: widget.softwareUpdate.phase !== ""
        implicitWidth: updateLabel.implicitWidth + 2 * updateLabel.anchors.leftMargin
        implicitHeight: updateLabel.implicitHeight

        Rectangle {
            id: pill
            anchors.fill: parent
            anchors.topMargin: -Kirigami.Units.smallSpacing / 2
            anchors.bottomMargin: -Kirigami.Units.smallSpacing / 2
            radius: height / 2
            color: look.tint(Kirigami.Theme.highlightColor, 0.2)

            Item {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * updateStatus.progress
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: pill.width
                    radius: pill.radius
                    color: look.tint(Kirigami.Theme.highlightColor, 0.3)
                }
            }
        }

        PlasmaComponents3.Label {
            id: updateLabel
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            elide: Text.ElideRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.features: { "tnum": 1 }
            text: widget.updateText()
        }
    }

    RowLayout {
        id: freshness
        Layout.row: 0
        Layout.column: 2
        Layout.fillWidth: true
        // The filler before the icon would count a spacing as width the row
        // needs, so the time keeps its distance from the icon by a margin.
        spacing: 0

        Item { Layout.fillWidth: true }

        // The icon is a pixel taller than the line of text. It hangs over the
        // line rather than stretch it, so the rows above don't move each time
        // a poll fails or works again.
        Item {
            implicitWidth: warning.width
            implicitHeight: updated.implicitHeight

            Kirigami.Icon {
                id: warning
                y: Math.round((parent.height - height) / 2)
                width: Kirigami.Units.iconSizes.small
                height: width
                visible: widget.errorText.length > 0
                source: "data-warning"
                HoverHandler { id: warnHover }
                PlasmaComponents3.ToolTip {
                    visible: warnHover.hovered
                    text: i18n("Showing last good data.\n%1", widget.errorText)
                }
            }
        }

        // At full strength while the data is old, since this time then says how
        // old. It stays in the text color: the icon before it carries the
        // warning's color, which some themes make too pale to read as text.
        PlasmaComponents3.Label {
            id: updated
            Layout.leftMargin: Kirigami.Units.smallSpacing
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.features: { "tnum": 1 }
            opacity: widget.stale ? 1 : look.secondary
            color: Kirigami.Theme.textColor
            text: {
                widget.now // re-evaluate on tick: at midnight the time gets its weekday
                return widget.lastUpdated ? widget.updatedText(widget.lastUpdated) : ""
            }
        }
    }
}
