import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Connection")
        icon: "network-connect"
        source: "configConnection.qml"
    }
    ConfigCategory {
        name: i18n("Display")
        icon: "preferences-desktop-display"
        source: "configDisplay.qml"
    }
}
