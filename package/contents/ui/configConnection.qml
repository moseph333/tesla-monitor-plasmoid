import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "logic.js" as Logic
import "teslaapi.js" as Api

KCM.SimpleKCM {
    id: page

    property alias cfg_dataSource: dataSource.currentIndex
    property alias cfg_apiRegion: apiRegion.currentIndex
    property alias cfg_apiBaseUrl: apiBaseUrl.text
    property alias cfg_apiVin: apiVin.text
    property alias cfg_apiAccessToken: apiAccessToken.text
    property alias cfg_apiRefreshToken: apiRefreshToken.text
    property alias cfg_apiClientId: apiClientId.text
    property alias cfg_apiAuthUrl: apiAuthUrl.text
    property alias cfg_apiRefreshSeconds: apiRefreshSeconds.value
    property alias cfg_apiIdleRefreshSeconds: apiIdleRefreshSeconds.value
    // Not shown. Unknown (0) once a new access token is typed in; known after a renewal.
    property real cfg_apiTokenExpiry: 0
    property alias cfg_brokerHost: brokerHost.text
    property alias cfg_brokerPort: brokerPort.value
    property alias cfg_brokerUser: brokerUser.text
    property alias cfg_brokerPassword: brokerPassword.text
    property alias cfg_useTls: useTls.checked
    property alias cfg_caFile: caFile.text
    property alias cfg_topicPrefix: topicPrefix.text
    property alias cfg_refreshSeconds: refreshSeconds.value
    property alias cfg_idleRefreshSeconds: idleRefreshSeconds.value

    readonly property bool useApi: dataSource.currentIndex === 1
    // The cars the last Find Cars found, for the picker: [{prefix, name}] from MQTT, or
    // [{vin, name, state}] from the API.
    property var cars: []
    // Which button started the running check: "test" or "find".
    property string pendingCheck: ""
    readonly property bool checking: fetch.busy || apiFetch.busy
    readonly property bool canCheck: !checking && (useApi
        ? Api.baseUrl(apiRegion.currentIndex, apiBaseUrl.text) !== "" && apiAccessToken.text.trim() !== ""
        : Logic.parseBrokerHost(brokerHost.text).host !== "")
    // True while tokens renewed by a check are put in their fields, which isn't an edit.
    property bool fillingTokens: false

    // A result describes the values it ran with, so editing any of them hides it and drops
    // a running check. result.visible is assigned, never bound, because the message's close
    // button assigns it too.
    function formEdited() {
        if (fillingTokens) return
        result.visible = false
        fetch.cancel()
        apiFetch.cancel()
    }

    // Cars found on one broker don't apply to another.
    function brokerEdited() {
        cars = []
        formEdited()
    }

    // TLS brokers usually listen on 8883, others on 1883. The port follows a change of mode
    // only if it still has the other mode's default, so a custom port is kept.
    function followTls(tls) {
        if (tls && brokerPort.value === 1883) brokerPort.value = 8883
        else if (!tls && brokerPort.value === 8883) brokerPort.value = 1883
    }

    function showResult(type, text) {
        result.type = type
        result.text = text
        result.visible = true
    }

    // Both buttons test the values on the page, before they are applied.
    function runCheck(kind) {
        result.visible = false
        pendingCheck = kind
        if (useApi) {
            runApiCheck(kind)
            return
        }
        const started = fetch.run({
            host: brokerHost.text,
            port: brokerPort.value,
            user: brokerUser.text,
            password: brokerPassword.text,
            tls: useTls.checked,
            caFile: caFile.text,
            topics: kind === "find"
                ? ["teslamate/cars/+/display_name", "teslamate/+/cars/+/display_name"]
                : [Logic.topicPrefix(topicPrefix.text) + "/#"],
            wait: 3
        })
        if (!started) showResult(Kirigami.MessageType.Error, i18n("Enter the broker's host name or address."))
    }

    // Test Connection asks for the car's summary, which never wakes it; Find Cars for the
    // account's cars.
    function runApiCheck(kind) {
        if (kind === "test" && Api.cleanVin(apiVin.text) === "") {
            showResult(Kirigami.MessageType.Error, i18n("Enter the car's VIN, or use Find Cars."))
            return
        }
        const started = apiFetch.run({
            region: apiRegion.currentIndex,
            customUrl: apiBaseUrl.text,
            accessToken: apiAccessToken.text,
            refreshToken: apiRefreshToken.text,
            clientId: apiClientId.text,
            authUrl: apiAuthUrl.text,
            tokenExpiry: page.cfg_apiTokenExpiry,
            vin: apiVin.text,
            request: kind === "find" ? "vehicles" : "summary"
        })
        if (!started) showResult(Kirigami.MessageType.Error, i18n("Choose a region or enter the API's URL, and paste an access token."))
    }

    // Tokens a check renewed. The old ones no longer work, so they are replaced on the page.
    function tokensRenewed(access, refresh, expiresAt) {
        fillingTokens = true
        apiAccessToken.text = access
        apiRefreshToken.text = refresh
        page.cfg_apiTokenExpiry = expiresAt
        fillingTokens = false
    }

    function apiCheckFinished(found, err) {
        if (!found) {
            showResult(Kirigami.MessageType.Error, err)
            return
        }
        if (found.kind === "vehicles") {
            apiCarsFound(found.vehicles)
            return
        }
        const name = found.values.display_name || Api.cleanVin(apiVin.text)
        const state = found.values.state || ""
        showResult(Kirigami.MessageType.Positive, state === "online" ? i18n("Found %1. It's awake.", name)
                   : state === "asleep" ? i18n("Found %1. It's asleep.", name)
                   : state === "offline" ? i18n("Found %1. It's offline.", name)
                   : i18n("Found %1.", name))
    }

    function apiCarsFound(found) {
        cars = found
        if (found.length === 1) {
            // Set before showing the message, since editing the VIN hides it.
            apiVin.text = found[0].vin
            showResult(Kirigami.MessageType.Positive, found[0].name
                ? i18n("Found %1. VIN set to %2.", found[0].name, found[0].vin)
                : i18n("Found a car. VIN set to %1.", found[0].vin))
        } else if (found.length > 1) {
            carPicker.currentIndex = -1
            showResult(Kirigami.MessageType.Information, i18np("Found %1 car. Choose one:", "Found %1 cars. Choose one:", found.length))
        } else {
            showResult(Kirigami.MessageType.Warning, i18n("This account has no cars, or the token may not list them."))
        }
    }

    function checkFinished(out, err) {
        if (pendingCheck === "find") carsFound(out, err)
        else connectionTested(out, err)
    }

    function connectionTested(out, err) {
        const prefix = String(fetch.options.topics[0]).replace(/\/#$/, "")
        const values = Logic.parseMqtt(out, prefix)
        const n = Object.keys(values).length
        if (n > 0 && values.display_name)
            showResult(Kirigami.MessageType.Positive, i18np("Found %2, %1 value", "Found %2, %1 values", n, values.display_name))
        else if (n > 0)
            showResult(Kirigami.MessageType.Positive, i18np("Found %1 value", "Found %1 values", n))
        else if (err)
            showResult(Kirigami.MessageType.Error, err)
        else
            showResult(Kirigami.MessageType.Warning, i18n("Connected, but there's no TeslaMate data on %1/#. Try Find Cars, or check that MQTT is enabled in TeslaMate.", prefix))
    }

    function carsFound(out, err) {
        const found = Logic.parseCars(out)
        cars = found
        if (found.length === 1) {
            // Set before showing the message, since editing the prefix hides it.
            topicPrefix.text = found[0].prefix
            showResult(Kirigami.MessageType.Positive, found[0].name
                ? i18n("Found %1. Topic prefix set to %2.", found[0].name, found[0].prefix)
                : i18n("Found a car. Topic prefix set to %1.", found[0].prefix))
        } else if (found.length > 1) {
            carPicker.currentIndex = -1
            showResult(Kirigami.MessageType.Information, i18np("Found %1 car. Choose one:", "Found %1 cars. Choose one:", found.length))
        } else if (err) {
            showResult(Kirigami.MessageType.Error, err)
        } else {
            showResult(Kirigami.MessageType.Warning, i18n("No TeslaMate cars found. Check that MQTT is enabled in TeslaMate and that this account may read teslamate/#."))
        }
    }

    Kirigami.FormLayout {
        // In the order of the dataSource setting's values.
        QQC2.ComboBox {
            id: dataSource
            Kirigami.FormData.label: i18n("Data source:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            model: [i18n("TeslaMate (MQTT)"), i18n("Tesla Fleet API")]
            onActivated: page.brokerEdited()
        }

        Hint {
            text: page.useApi
                ? i18n("Reads the car straight from Tesla, or from a service with the same API. Tesla bills each request, so the widget asks sparingly and lets the car sleep.")
                : i18n("Reads the values TeslaMate publishes to an MQTT broker.")
        }

        Kirigami.Separator {
            visible: page.useApi
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Tesla Fleet API")
        }

        // In the order of Api.REGIONS, then a custom URL.
        QQC2.ComboBox {
            id: apiRegion
            visible: page.useApi
            Kirigami.FormData.label: i18n("Region:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            model: [
                i18n("North America, Asia-Pacific"),
                i18n("Europe, Middle East, Africa"),
                i18n("China"),
                i18n("Custom URL")
            ]
            onActivated: page.brokerEdited()
        }

        QQC2.TextField {
            id: apiBaseUrl
            visible: page.useApi && apiRegion.currentIndex === 3
            Kirigami.FormData.label: i18n("URL:")
            placeholderText: i18nc("example web address", "https://api.example.com")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        Hint {
            visible: page.useApi
            text: i18n("The region your Tesla account belongs to. Choose Custom URL for a service that offers the Fleet API's URLs with its own token.")
        }

        Kirigami.PasswordField {
            id: apiAccessToken
            visible: page.useApi
            Kirigami.FormData.label: i18n("Access token:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: {
                if (!page.fillingTokens) page.cfg_apiTokenExpiry = 0
                page.brokerEdited()
            }
        }

        Kirigami.PasswordField {
            id: apiRefreshToken
            visible: page.useApi
            Kirigami.FormData.label: i18n("Refresh token:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        QQC2.TextField {
            id: apiClientId
            visible: page.useApi
            Kirigami.FormData.label: i18n("Client ID:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        QQC2.TextField {
            id: apiAuthUrl
            visible: page.useApi && apiRefreshToken.text.trim() !== ""
            Kirigami.FormData.label: i18n("Token server:")
            placeholderText: "https://fleet-auth.prd.vn.cloud.tesla.com"
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        Hint {
            visible: page.useApi
            text: i18n("Tesla's access tokens last 8 hours. With the refresh token and the client ID of the Fleet API app that issued them, the widget renews the access token itself and saves the new tokens. The token needs the vehicle_device_data scope. Tokens are stored unencrypted in Plasma's configuration.")
        }

        QQC2.TextField {
            id: apiVin
            visible: page.useApi
            Kirigami.FormData.label: i18n("VIN:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            inputMethodHints: Qt.ImhPreferUppercase | Qt.ImhNoPredictiveText
            onTextChanged: page.formEdited()
            onEditingFinished: if (text !== Api.cleanVin(text)) text = Api.cleanVin(text)
        }

        Kirigami.Separator {
            visible: !page.useApi
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("MQTT broker")
        }

        QQC2.TextField {
            id: brokerHost
            visible: !page.useApi
            Kirigami.FormData.label: i18n("Host:")
            placeholderText: i18nc("example broker addresses", "192.168.1.x or mqtt.example.com")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
            // People paste what their broker's docs show, e.g. mqtts://user:pw@host:8883/,
            // but mosquitto_sub only takes a bare host, so the other parts move to their
            // own fields. The scheme sets Use TLS, and the port follows as it does for the
            // checkbox (setting checked here doesn't emit toggled). Credentials never
            // overwrite what was typed.
            onEditingFinished: {
                const pasted = Logic.parseBrokerHost(text)
                if (text !== pasted.host) text = pasted.host
                if (pasted.port) brokerPort.value = pasted.port
                else if (pasted.tls !== null) page.followTls(pasted.tls)
                if (pasted.tls !== null) useTls.checked = pasted.tls
                if (pasted.user && brokerUser.text === "") brokerUser.text = pasted.user
                if (pasted.password && brokerPassword.text === "") brokerPassword.text = pasted.password
            }
        }

        QQC2.SpinBox {
            id: brokerPort
            visible: !page.useApi
            Kirigami.FormData.label: i18n("Port:")
            from: 1
            to: 65535
            editable: true
            textFromValue: (value) => String(value)
            valueFromText: (text) => parseInt(text)
            onValueModified: page.brokerEdited()
        }

        QQC2.TextField {
            id: brokerUser
            visible: !page.useApi
            Kirigami.FormData.label: i18n("Username:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        Kirigami.PasswordField {
            id: brokerPassword
            visible: !page.useApi
            Kirigami.FormData.label: i18n("Password:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        QQC2.CheckBox {
            id: useTls
            visible: !page.useApi
            Kirigami.FormData.label: i18n("Security:")
            text: i18n("Use TLS")
            onToggled: {
                page.followTls(checked)
                page.brokerEdited()
            }
        }

        RowLayout {
            visible: !page.useApi
            Kirigami.FormData.label: i18n("CA file:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: useTls.checked
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: caFile
                Layout.fillWidth: true
                placeholderText: i18n("System certificates")
                onTextChanged: page.brokerEdited()
            }

            QQC2.Button {
                text: i18n("Browse…")
                icon.name: "document-open"
                onClicked: caDialog.open()

                QtDialogs.FileDialog {
                    id: caDialog
                    title: i18n("Choose a CA Certificate")
                    nameFilters: [i18n("Certificates (*.pem *.crt *.cer)"), i18n("All files (*)")]
                    // mosquitto_sub needs a path, and a file URL percent-encodes spaces and
                    // the like.
                    onAccepted: caFile.text = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
                }
            }
        }

        Hint {
            visible: !page.useApi
            text: i18n("Leave the CA file empty to use the system's certificates (needs mosquitto 2.0 or newer). TLS brokers usually listen on port 8883; with mosquitto 2.0, port 8883 always uses TLS. Host must match the name on the broker's certificate.")
        }

        Kirigami.Separator {
            visible: !page.useApi
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("TeslaMate")
        }

        QQC2.TextField {
            id: topicPrefix
            visible: !page.useApi
            Kirigami.FormData.label: i18n("Topic prefix:")
            placeholderText: "teslamate/cars/1"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        Hint {
            visible: !page.useApi
            text: i18n("If TeslaMate sets MQTT_NAMESPACE, use teslamate/<namespace>/cars/1.")
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Test Connection")
                icon.name: "network-connect"
                enabled: page.canCheck
                onClicked: page.runCheck("test")
            }

            QQC2.Button {
                text: i18n("Find Cars")
                icon.name: "edit-find"
                enabled: page.canCheck
                onClicked: page.runCheck("find")
            }

            QQC2.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                running: page.checking
                visible: running
            }

            MqttFetch {
                id: fetch
                onFinished: (out, err) => page.checkFinished(out, err)
            }

            TeslaApiFetch {
                id: apiFetch
                onFinished: (found, err) => page.apiCheckFinished(found, err)
                onTokensRenewed: (access, refresh, expiresAt) => page.tokensRenewed(access, refresh, expiresAt)
            }
        }

        Kirigami.InlineMessage {
            id: result
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            visible: false
            showCloseButton: true
        }

        QQC2.ComboBox {
            id: carPicker
            Kirigami.FormData.label: i18n("Car:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            visible: page.cars.length > 1
            model: page.cars.map(c => {
                const id = c.vin || c.prefix
                return c.name ? i18nc("car name (topic prefix or VIN)", "%1 (%2)", c.name, id) : id
            })
            displayText: currentIndex < 0 ? i18n("Choose a car…") : currentText
            onActivated: (index) => {
                const car = page.cars[index]
                if (car.vin) apiVin.text = car.vin
                else topicPrefix.text = car.prefix
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Refresh")
        }

        // The unit is a label beside each spin box, not part of its text. Plasma's style
        // takes the value as soon as the typed text parses as a number, so with a unit in
        // the text the first digit would be saved and the rest land after the unit. i18np()
        // would also add digit grouping or locale digits that parseInt() can't read back.
        RowLayout {
            visible: !page.useApi
            Kirigami.FormData.label: i18n("Every:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: refreshSeconds
                from: 5
                to: 600
            }

            QQC2.Label {
                text: i18ncp("@label unit after a spin box", "second", "seconds", refreshSeconds.value)
            }
        }

        RowLayout {
            visible: !page.useApi
            Kirigami.FormData.label: i18n("While the car sleeps:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: idleRefreshSeconds
                from: 5
                to: 3600
                stepSize: 5
            }

            QQC2.Label {
                text: i18ncp("@label unit after a spin box", "second", "seconds", idleRefreshSeconds.value)
            }
        }

        // The API's own rates, in minutes: each request is billed.
        RowLayout {
            visible: page.useApi
            Kirigami.FormData.label: i18n("Every:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: apiRefreshMinutes
                from: 1
                to: 60
                value: Math.max(1, Math.round(apiRefreshSeconds.value / 60))
                onValueModified: apiRefreshSeconds.value = value * 60
            }

            QQC2.Label {
                text: i18ncp("@label unit after a spin box", "minute", "minutes", apiRefreshMinutes.value)
            }

            // Holds the setting, which is in seconds like the MQTT one.
            QQC2.SpinBox {
                id: apiRefreshSeconds
                visible: false
                from: 60
                to: 3600
            }
        }

        RowLayout {
            visible: page.useApi
            Kirigami.FormData.label: i18n("While the car sleeps:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: apiIdleRefreshMinutes
                from: 1
                to: 240
                value: Math.max(1, Math.round(apiIdleRefreshSeconds.value / 60))
                onValueModified: apiIdleRefreshSeconds.value = value * 60
            }

            QQC2.Label {
                text: i18ncp("@label unit after a spin box", "minute", "minutes", apiIdleRefreshMinutes.value)
            }

            QQC2.SpinBox {
                id: apiIdleRefreshSeconds
                visible: false
                from: 60
                to: 14400
            }
        }

        Hint {
            text: page.useApi
                ? i18n("Used while the car is asleep, offline or falling asleep and the popup is closed, and always for a widget on the desktop. Opening the popup or pressing Refresh updates right away, at most once a minute. Asking an awake car keeps it awake, so after 15 idle minutes the widget stops asking for 21 minutes to let it sleep, as TeslaMate does.")
                : i18n("Used while the car is asleep or offline and the popup is closed, and always for a widget on the desktop. Opening the popup or pressing Refresh updates right away.")
        }

        Hint {
            visible: page.useApi
            text: i18n("Tesla bills roughly $1 for every 500 data requests (the rate varies by region), with a $10 monthly credit for individual developers. Checking every 5 minutes while a car is awake 3 hours a day, and every 15 minutes while it sleeps, comes to about 4,000 requests a month. Services with the same API have their own prices.")
        }
    }
}
