import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

ColumnLayout {
    id: stat

    property string label
    property string value
    property color valueColor: Kirigami.Theme.textColor

    spacing: 0

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: stat.value
        color: stat.valueColor
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: stat.label
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.6
        elide: Text.ElideRight
    }
}
