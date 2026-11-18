import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "logic.js" as Logic
import "teslaapi.js" as Api
import "sources.js" as Sources
import "homeassistant.js" as HomeAssistant

KCM.SimpleKCM {
    id: page

    property alias cfg_dataSource: dataSource.currentIndex
    property alias cfg_apiRegion: apiRegion.currentIndex
    property alias cfg_apiBaseUrl: apiBaseUrl.text
    property alias cfg_apiVin: apiVin.text
    property string cfg_apiAccessToken
    property string cfg_apiRefreshToken
    property alias cfg_apiClientId: apiClientId.text
    property alias cfg_apiAuthUrl: apiAuthUrl.text
    property alias cfg_apiRefreshSeconds: apiRefreshSeconds.value
    property alias cfg_apiIdleRefreshSeconds: apiIdleRefreshSeconds.value
    // Not shown. Unknown (0) once a new access token is typed in; known after a renewal.
    property real cfg_apiTokenExpiry: 0
    // The token settings aren't aliases either: like the password, where Apply saves them
    // depends on the wallet, so updateTokens() works them out from the fields.
    property string cfg_tokensKeyringId
    property string cfg_teslemetryToken
    property alias cfg_teslemetryVin: teslemetryVin.text
    property alias cfg_haUrl: haUrl.text
    property string cfg_haToken
    property alias cfg_haPrefix: haPrefix.text
    property string cfg_tessieToken
    property alias cfg_tessieVin: tessieVin.text
    property alias cfg_teslamateApiUrl: teslamateApiUrl.text
    property string cfg_teslamateApiToken
    property alias cfg_teslamateApiCarId: teslamateApiCarId.value
    property alias cfg_brokerHost: brokerHost.text
    property alias cfg_brokerPort: brokerPort.value
    property alias cfg_brokerUser: brokerUser.text
    // Not aliases: where Apply saves the password depends on the wallet, so
    // updatePassword() works these out from the field.
    property string cfg_brokerPassword
    property string cfg_keyringId
    property alias cfg_useTls: useTls.checked
    property alias cfg_caFile: caFile.text
    property alias cfg_topicPrefix: topicPrefix.text
    property alias cfg_refreshSeconds: refreshSeconds.value
    property alias cfg_idleRefreshSeconds: idleRefreshSeconds.value

    readonly property var source: Sources.byId(dataSource.currentIndex)
    readonly property bool mqtt: source.kind === "mqtt"
    readonly property bool fleet: source.kind === "fleet"
    readonly property bool rest: source.kind === "rest"
    // The cars the last Find Cars found, for the picker: [{prefix, name}] from MQTT,
    // [{vin, name, state}] from the Fleet API, Teslemetry or Tessie, [{id, name, vin}] from
    // the TeslaMate API, or [{prefix, name}] from Home Assistant.
    property var cars: []
    // Which button started the running check: "test" or "find".
    property string pendingCheck: ""
    readonly property bool checking: fetch.busy || apiFetch.busy || restFetch.busy
    readonly property bool canCheck: {
        if (checking) return false
        switch (source.kind) {
        case "fleet": {
            const o = fleetOptions()
            return Api.baseUrl(o.region, o.customUrl) !== "" && o.accessToken.trim() !== ""
        }
        case "rest":
            return restFetch.canRun(restOptions("cars"))
        default:
            return Logic.parseBrokerHost(brokerHost.text).host !== ""
        }
    }
    // True while tokens renewed by a check are put in their fields, which isn't an edit.
    property bool fillingTokens: false

    readonly property Keyring keyring: Keyring {
        onAvailabilityChanged: {
            page.updatePassword()
            page.updateTokens()
        }
    }
    readonly property KeyringSecret passwordSecret: KeyringSecret {
        keyring: page.keyring
        label: i18nc("@label name of the entry in the wallet", "Tesla Monitor MQTT password")
        onReverted: page.updatePassword()
    }
    // All the tokens as one secret, Logic.packSecrets()'s text.
    readonly property KeyringSecret tokenSecret: KeyringSecret {
        keyring: page.keyring
        label: i18nc("@label name of the entry in the wallet", "Tesla Monitor tokens")
        onReverted: page.updateTokens()
    }

    Component.onCompleted: {
        passwordSecret.load(cfg_keyringId, cfg_brokerPassword, value => brokerPassword.text = value)
        brokerPassword.text = cfg_keyringId ? "" : cfg_brokerPassword
        const savedTokens = {}
        for (const key of Logic.tokenSettings()) savedTokens[key] = page["cfg_" + key]
        tokenSecret.load(cfg_tokensKeyringId, Logic.packSecrets(savedTokens, Logic.tokenSettings()), value => {
            const read = Logic.unpackSecrets(value, Logic.tokenSettings())
            if (read) {
                page.fillTokens(read)
            } else {
                // Not tokens, so treated as unreadable: empty fields keep the entry.
                tokenSecret.savedValue = ""
                tokenSecret.unread = true
            }
        })
        if (!cfg_tokensKeyringId) fillTokens(savedTokens)
        if (!cfg_keyringId && !cfg_tokensKeyringId) keyring.probe()
    }

    // The token fields, keyed by setting.
    function tokenFields() {
        return {
            apiAccessToken: apiAccessToken,
            apiRefreshToken: apiRefreshToken,
            teslemetryToken: teslemetryToken,
            tessieToken: tessieToken,
            teslamateApiToken: teslamateApiToken,
            haToken: haToken
        }
    }

    // Puts tokens in their fields without counting it as an edit.
    function fillTokens(values) {
        fillingTokens = true
        const fields = tokenFields()
        for (const key in values) if (fields[key]) fields[key].text = values[key]
        fillingTokens = false
        updateTokens()
    }

    function tokenValue() {
        const fields = tokenFields()
        const values = {}
        for (const key in fields) values[key] = fields[key].text
        return Logic.packSecrets(values, Logic.tokenSettings())
    }

    function updateTokens() {
        const where = tokenSecret.target(tokenValue())
        const fields = tokenFields()
        cfg_tokensKeyringId = where.id
        for (const key in fields) page["cfg_" + key] = where.plain ? fields[key].text : ""
    }

    // Sets the cfg_ values to what Apply would save, so Plasma enables Apply when there's
    // something to save.
    function updatePassword() {
        const where = passwordSecret.target(brokerPassword.text)
        cfg_keyringId = where.id
        cfg_brokerPassword = where.plain ? brokerPassword.text : ""
    }

    // Plasma calls this on Apply, before it saves the cfg_ values.
    function saveConfig() {
        passwordSecret.save(brokerPassword.text)
        tokenSecret.save(tokenValue())
    }

    // What the page says about where the tokens go, or "".
    function tokensMessage() {
        if (tokenSecret.storeFailed)
            return tokenSecret.storeError
                ? i18n("Couldn't save the tokens in the wallet: %1. Press Apply to try again.", tokenSecret.storeError)
                : i18n("Couldn't save the tokens in the wallet. Press Apply to try again.")
        const install = i18n("Install libsecret-tools on Debian and Ubuntu, or libsecret on Fedora and Arch.")
        const value = tokenValue()
        if (tokenSecret.unread && value === "") {
            if (keyring.availability === "missing")
                return i18n("secret-tool isn't installed, so the tokens saved in the wallet can't be read.") + " " + install
            if (keyring.availability === "unavailable")
                return i18n("There's no wallet, so the saved tokens can't be read: %1", keyring.detail)
            return i18n("The saved tokens couldn't be read from the wallet, which may be closed. Enter them again to replace them, or leave the fields empty to keep them.")
        }
        if (tokenSecret.moving(value))
            return i18n("The tokens are saved in plain text in the widget's settings. Apply moves them into the wallet.")
        if (cfg_tokensKeyringId !== "" || value === "") return ""
        if (keyring.availability === "missing")
            return i18n("secret-tool isn't installed, so the tokens are saved in plain text in the widget's settings.") + " " + install
        if (keyring.availability === "unavailable")
            return i18n("There's no wallet, so the tokens are saved in plain text in the widget's settings: %1", keyring.detail)
        return ""
    }

    // What the page says about where the password goes, or "".
    function passwordMessage() {
        if (passwordSecret.storeFailed)
            return passwordSecret.storeError
                ? i18n("Couldn't save the password in the wallet: %1. Press Apply to try again.", passwordSecret.storeError)
                : i18n("Couldn't save the password in the wallet. Press Apply to try again.")
        const install = i18n("Install libsecret-tools on Debian and Ubuntu, or libsecret on Fedora and Arch.")
        // Once something is typed, where it goes matters more than what couldn't be read.
        if (passwordSecret.unread && brokerPassword.text === "") {
            if (keyring.availability === "missing")
                return i18n("secret-tool isn't installed, so the password saved in the wallet can't be read.") + " " + install
            if (keyring.availability === "unavailable")
                return i18n("There's no wallet, so the saved password can't be read: %1", keyring.detail)
            return i18n("The saved password couldn't be read from the wallet, which may be closed. Type it again to replace it, or leave the field empty to keep it.")
        }
        if (passwordSecret.moving(brokerPassword.text))
            return i18n("The password is saved in plain text in the widget's settings. Apply moves it into the wallet.")
        if (cfg_brokerPassword === "") return ""
        if (keyring.availability === "missing")
            return i18n("secret-tool isn't installed, so the password is saved in plain text in the widget's settings.") + " " + install
        if (keyring.availability === "unavailable")
            return i18n("There's no wallet, so the password is saved in plain text in the widget's settings: %1", keyring.detail)
        return ""
    }

    // A result describes the values it ran with, so editing any of them hides it and drops
    // a running check. result.visible is assigned, never bound, because the message's close
    // button assigns it too.
    function formEdited() {
        if (fillingTokens) return
        result.visible = false
        fetch.cancel()
        apiFetch.cancel()
        restFetch.cancel()
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

    // The message box guesses whether text is markup, and results quote car names and
    // servers, so they never get to be read as markup.
    function showResult(type, text) {
        result.type = type
        result.text = Logic.noMarkup(text)
        result.visible = true
    }

    // Both buttons test the values on the page, before they are applied. A saved password
    // comes from the wallet; one typed since goes on the command line while the check runs.
    function runCheck(kind) {
        result.visible = false
        pendingCheck = kind
        if (fleet) {
            runApiCheck(kind)
            return
        }
        if (rest) {
            runRestCheck(kind)
            return
        }
        const started = fetch.run({
            host: brokerHost.text,
            port: brokerPort.value,
            user: brokerUser.text,
            password: brokerPassword.text,
            keyringId: brokerPassword.text === passwordSecret.savedValue ? passwordSecret.savedId : "",
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
        const options = fleetOptions()
        if (kind === "test" && Api.cleanVin(options.vin) === "") {
            showResult(Kirigami.MessageType.Error, i18n("Enter the car's VIN, or use Find Cars."))
            return
        }
        const started = apiFetch.run(Object.assign(options, { request: kind === "find" ? "vehicles" : "summary" }))
        if (!started) showResult(Kirigami.MessageType.Error, source.key === "teslemetry"
            ? i18n("Paste your Teslemetry access token.")
            : i18n("Choose a region or enter the API's URL, and paste an access token."))
    }

    // The values on the page for TeslaApiFetch.run(), for the Fleet API or Teslemetry.
    function fleetOptions() {
        return Api.fleetOptions(source.key, {
            apiRegion: apiRegion.currentIndex,
            apiBaseUrl: apiBaseUrl.text,
            apiAccessToken: apiAccessToken.text,
            apiRefreshToken: apiRefreshToken.text,
            apiClientId: apiClientId.text,
            apiAuthUrl: apiAuthUrl.text,
            apiTokenExpiry: page.cfg_apiTokenExpiry,
            apiVin: apiVin.text,
            teslemetryToken: teslemetryToken.text,
            teslemetryVin: teslemetryVin.text
        })
    }

    // The values on the page for RestFetch.run(), asking for request.
    function restOptions(request) {
        switch (source.key) {
        case "teslamateApi":
            return { source: source, url: teslamateApiUrl.text, token: teslamateApiToken.text,
                     car: teslamateApiCarId.value, request: request }
        case "tessie":
            return { source: source, url: "", token: tessieToken.text, car: tessieVin.text, request: request }
        case "homeAssistant":
            return { source: source, url: haUrl.text, token: haToken.text, car: haPrefix.text, request: request }
        }
        return { source: source, url: "", token: "", car: "", request: request }
    }

    // Test Connection reads the car the settings name; Find Cars lists the cars.
    function runRestCheck(kind) {
        if (kind === "test" && source.key === "tessie" && Api.cleanVin(tessieVin.text) === "") {
            showResult(Kirigami.MessageType.Error, i18n("Enter the car's VIN, or use Find Cars."))
            return
        }
        if (kind === "test" && source.key === "homeAssistant" && HomeAssistant.cleanPrefix(haPrefix.text) === "") {
            showResult(Kirigami.MessageType.Error, i18n("Enter the car, or use Find Cars."))
            return
        }
        if (restFetch.run(restOptions(kind === "find" ? "cars" : "test"))) return
        switch (source.key) {
        case "tessie":
            showResult(Kirigami.MessageType.Error, i18n("Paste your Tessie access token."))
            break
        case "homeAssistant":
            showResult(Kirigami.MessageType.Error, i18n("Enter Home Assistant's address and paste an access token."))
            break
        default:
            showResult(Kirigami.MessageType.Error, i18n("Enter the service's address."))
        }
    }

    function restCheckFinished(found, err) {
        if (!found) {
            showResult(Kirigami.MessageType.Error, err)
            return
        }
        if (found.kind === "cars") {
            restCarsFound(found.cars)
            return
        }
        const name = found.values.display_name || (source.key === "tessie" ? Api.cleanVin(tessieVin.text)
            : source.key === "homeAssistant" ? HomeAssistant.cleanPrefix(haPrefix.text) : "")
        showResult(Kirigami.MessageType.Positive, foundText(name, found.values.state || ""))
    }

    function restCarsFound(found) {
        cars = found
        if (found.length === 1) {
            // Set before showing the message, since editing the car hides it.
            pickCar(found[0])
            showResult(Kirigami.MessageType.Positive, carSetText(found[0]))
        } else if (found.length > 1) {
            carPicker.currentIndex = -1
            showResult(Kirigami.MessageType.Information, i18np("Found %1 car. Choose one:", "Found %1 cars. Choose one:", found.length))
        } else {
            showResult(Kirigami.MessageType.Warning, source.key === "teslamateApi"
                ? i18n("TeslaMate has no cars yet.")
                : source.key === "homeAssistant"
                ? i18n("No cars found. Home Assistant's Tesla Fleet, Teslemetry or Tessie integration has to be set up, with the entities' English names.")
                : i18n("This account has no cars, or the token may not list them."))
        }
    }

    // What Find Cars says when it found one car and set it.
    function carSetText(car) {
        const key = carKey(car)
        if (source.key === "teslamateApi")
            return car.name ? i18n("Found %1. Car ID set to %2.", car.name, key) : i18n("Found a car. Car ID set to %1.", key)
        if (source.key === "homeAssistant")
            return car.name ? i18n("Found %1. Car set to %2.", car.name, key) : i18n("Found a car. Car set to %1.", key)
        return car.name ? i18n("Found %1. VIN set to %2.", car.name, key) : i18n("Found a car. VIN set to %1.", key)
    }

    // "Found Blue Thunder. It's asleep.", for a car's name and TeslaMate state.
    function foundText(name, state) {
        if (!name) return i18n("Found the car.")
        switch (state) {
        case "": return i18n("Found %1.", name)
        case "asleep": return i18n("Found %1. It's asleep.", name)
        case "offline": return i18n("Found %1. It's offline.", name)
        default: return i18n("Found %1. It's awake.", name)
        }
    }

    // What the car picker shows to tell cars apart, and what choosing one sets.
    function carKey(car) {
        switch (source.key) {
        case "fleet":
        case "teslemetry":
        case "tessie":
            return car.vin
        case "teslamateApi": return String(car.id)
        default: return car.prefix
        }
    }

    function pickCar(car) {
        switch (source.key) {
        case "fleet":
            apiVin.text = car.vin
            break
        case "teslemetry":
            teslemetryVin.text = car.vin
            break
        case "tessie":
            tessieVin.text = car.vin
            break
        case "homeAssistant":
            haPrefix.text = car.prefix
            break
        case "teslamateApi":
            teslamateApiCarId.value = car.id
            break
        default:
            topicPrefix.text = car.prefix
        }
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
        showResult(Kirigami.MessageType.Positive,
                   foundText(found.values.display_name || Api.cleanVin(apiVin.text), found.values.state || ""))
    }

    function apiCarsFound(found) {
        cars = found
        if (found.length === 1) {
            // Set before showing the message, since editing the VIN hides it.
            pickCar(found[0])
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
            model: [
                i18n("TeslaMate (MQTT)"),
                i18n("Tesla Fleet API"),
                i18n("TeslaMate API"),
                i18n("Teslemetry"),
                i18n("Tessie"),
                i18n("Home Assistant")
            ]
            onActivated: page.brokerEdited()
        }

        Hint {
            text: {
                switch (page.source.key) {
                case "fleet": return i18n("Reads the car straight from Tesla, or from a service with the same API. Tesla bills each request, so the widget asks sparingly and lets the car sleep.")
                case "teslemetry": return i18n("Reads the car from Teslemetry, a service that offers the Tesla Fleet API with its own token and keeps the car's data in a cache.")
                case "homeAssistant": return i18n("Reads the car's entities from Home Assistant, as its own Tesla Fleet, Teslemetry or Tessie integration provides them.")
                case "tessie": return i18n("Reads the car from Tessie, which keeps the car's latest data, so asking doesn't wake the car or keep it awake.")
                case "teslamateApi": return i18n("Reads TeslaMate's values from TeslaMateApi, a small web service that runs next to TeslaMate, so this computer doesn't need mosquitto_sub or a way to the MQTT broker.")
                default: return i18n("Reads the values TeslaMate publishes to an MQTT broker.")
                }
            }
        }

        Kirigami.Separator {
            visible: page.source.key === "teslemetry"
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Teslemetry")
        }

        Kirigami.PasswordField {
            id: teslemetryToken
            visible: page.source.key === "teslemetry"
            Kirigami.FormData.label: i18n("Access token:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: !page.tokenSecret.reading
            onTextChanged: {
                page.brokerEdited()
                page.updateTokens()
            }
        }

        QQC2.TextField {
            id: teslemetryVin
            visible: page.source.key === "teslemetry"
            Kirigami.FormData.label: i18n("VIN:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            inputMethodHints: Qt.ImhPreferUppercase | Qt.ImhNoPredictiveText
            onTextChanged: page.formEdited()
            onEditingFinished: if (text !== Api.cleanVin(text)) text = Api.cleanVin(text)
        }

        Hint {
            visible: page.source.key === "teslemetry"
            text: i18n("Make an access token in the Teslemetry console, at teslemetry.com, with access to the car's data. It doesn't expire, so there is nothing to renew. Teslemetry answers from its cache for free while the data is fresh, and charges credits when it has to ask the car. Find Cars fills in the VIN.")
        }

        Kirigami.Separator {
            visible: page.source.key === "homeAssistant"
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Home Assistant")
        }

        QQC2.TextField {
            id: haUrl
            visible: page.source.key === "homeAssistant"
            Kirigami.FormData.label: i18n("Address:")
            placeholderText: i18nc("example web address", "http://homeassistant.local:8123")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        Kirigami.PasswordField {
            id: haToken
            visible: page.source.key === "homeAssistant"
            Kirigami.FormData.label: i18n("Access token:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: !page.tokenSecret.reading
            onTextChanged: {
                page.brokerEdited()
                page.updateTokens()
            }
        }

        QQC2.TextField {
            id: haPrefix
            visible: page.source.key === "homeAssistant"
            Kirigami.FormData.label: i18n("Car:")
            placeholderText: i18nc("example start of entity IDs", "my_model_3")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
            onEditingFinished: if (text !== HomeAssistant.cleanPrefix(text)) text = HomeAssistant.cleanPrefix(text)
        }

        Hint {
            visible: page.source.key === "homeAssistant"
            text: i18n("Make a long-lived access token in your Home Assistant profile, under Security. The car is the start of its entity IDs, such as my_model_3 for sensor.my_model_3_battery_level; Find Cars lists them. The widget knows the entities by Home Assistant's English names, so renamed or translated entity IDs aren't found.")
        }

        Kirigami.Separator {
            visible: page.source.key === "tessie"
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Tessie")
        }

        Kirigami.PasswordField {
            id: tessieToken
            visible: page.source.key === "tessie"
            Kirigami.FormData.label: i18n("Access token:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: !page.tokenSecret.reading
            onTextChanged: {
                page.brokerEdited()
                page.updateTokens()
            }
        }

        QQC2.TextField {
            id: tessieVin
            visible: page.source.key === "tessie"
            Kirigami.FormData.label: i18n("VIN:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            inputMethodHints: Qt.ImhPreferUppercase | Qt.ImhNoPredictiveText
            onTextChanged: page.formEdited()
            onEditingFinished: if (text !== Api.cleanVin(text)) text = Api.cleanVin(text)
        }

        Hint {
            visible: page.source.key === "tessie"
            text: i18n("Make an access token in Tessie's dashboard, under Settings, API. Tessie doesn't charge for each request, so checking every minute costs nothing more. Find Cars fills in the VIN.")
        }

        Kirigami.Separator {
            visible: page.source.key === "teslamateApi"
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("TeslaMate API")
        }

        QQC2.TextField {
            id: teslamateApiUrl
            visible: page.source.key === "teslamateApi"
            Kirigami.FormData.label: i18n("Address:")
            placeholderText: i18nc("example web address", "http://teslamate.local:8080")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        Kirigami.PasswordField {
            id: teslamateApiToken
            visible: page.source.key === "teslamateApi"
            Kirigami.FormData.label: i18n("Token:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: !page.tokenSecret.reading
            onTextChanged: {
                page.formEdited()
                page.updateTokens()
            }
        }

        QQC2.SpinBox {
            id: teslamateApiCarId
            visible: page.source.key === "teslamateApi"
            Kirigami.FormData.label: i18n("Car ID:")
            from: 1
            to: 999
            editable: true
            textFromValue: (value) => String(value)
            valueFromText: (text) => parseInt(text)
            onValueModified: page.formEdited()
        }

        Hint {
            visible: page.source.key === "teslamateApi"
            text: i18n("TeslaMateApi listens on port 8080 and needs MQTT enabled. Reading the car needs no token; the token is TeslaMateApi's API_TOKEN, for a server that asks for it. The car ID is TeslaMate's, 1 for the first car; Find Cars lists them.")
        }

        Kirigami.Separator {
            visible: page.source.key === "fleet"
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Tesla Fleet API")
        }

        // In the order of Api.REGIONS, then a custom URL.
        QQC2.ComboBox {
            id: apiRegion
            visible: page.source.key === "fleet"
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
            visible: page.source.key === "fleet" && apiRegion.currentIndex === 3
            Kirigami.FormData.label: i18n("URL:")
            placeholderText: i18nc("example web address", "https://api.example.com")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        Hint {
            visible: page.source.key === "fleet"
            text: i18n("The region your Tesla account belongs to. Choose Custom URL for a service that offers the Fleet API's URLs with its own token. It must use HTTPS, unless it runs on this computer.")
        }

        Kirigami.PasswordField {
            id: apiAccessToken
            visible: page.source.key === "fleet"
            Kirigami.FormData.label: i18n("Access token:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: !page.tokenSecret.reading
            onTextChanged: {
                if (!page.fillingTokens) page.cfg_apiTokenExpiry = 0
                page.brokerEdited()
                page.updateTokens()
            }
        }

        Kirigami.PasswordField {
            id: apiRefreshToken
            visible: page.source.key === "fleet"
            Kirigami.FormData.label: i18n("Refresh token:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: !page.tokenSecret.reading
            onTextChanged: {
                page.formEdited()
                page.updateTokens()
            }
        }

        QQC2.TextField {
            id: apiClientId
            visible: page.source.key === "fleet"
            Kirigami.FormData.label: i18n("Client ID:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        QQC2.TextField {
            id: apiAuthUrl
            visible: page.source.key === "fleet" && apiRefreshToken.text.trim() !== ""
            Kirigami.FormData.label: i18n("Token server:")
            placeholderText: Api.authUrl("", apiRegion.currentIndex)
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        Hint {
            visible: page.source.key === "fleet"
            text: i18n("tools/tesla-login.py in the widget's source gets these for your own Fleet API app. Tesla's access tokens last 8 hours. With the refresh token and the app's client ID, the widget renews the access token itself and saves the new tokens. The token needs the vehicle_device_data scope.")
        }

        QQC2.TextField {
            id: apiVin
            visible: page.source.key === "fleet"
            Kirigami.FormData.label: i18n("VIN:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            inputMethodHints: Qt.ImhPreferUppercase | Qt.ImhNoPredictiveText
            onTextChanged: page.formEdited()
            onEditingFinished: if (text !== Api.cleanVin(text)) text = Api.cleanVin(text)
        }

        Kirigami.Separator {
            visible: page.mqtt
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("MQTT broker")
        }

        QQC2.TextField {
            id: brokerHost
            visible: page.mqtt
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
            visible: page.mqtt
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
            visible: page.mqtt
            Kirigami.FormData.label: i18n("Username:")
            placeholderText: i18n("Optional")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.brokerEdited()
        }

        Kirigami.PasswordField {
            id: brokerPassword
            visible: page.mqtt
            Kirigami.FormData.label: i18n("Password:")
            // Typing waits for the wallet, so what it returns can't overwrite what's typed.
            enabled: !page.passwordSecret.reading
            placeholderText: enabled ? i18n("Optional") : i18n("Reading the wallet…")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: {
                page.brokerEdited()
                page.updatePassword()
            }
        }

        Hint {
            visible: page.mqtt && page.cfg_keyringId !== "" && brokerPassword.text !== ""
                     && !passwordNote.visible
            text: i18n("The password is kept in the wallet, not in the widget's settings.")
        }

        Kirigami.InlineMessage {
            id: passwordNote
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            visible: page.mqtt && text !== ""
            type: page.passwordSecret.storeFailed ? Kirigami.MessageType.Error
                : page.passwordSecret.moving(brokerPassword.text) ? Kirigami.MessageType.Information
                : Kirigami.MessageType.Warning
            text: page.passwordMessage()
        }

        QQC2.CheckBox {
            id: useTls
            visible: page.mqtt
            Kirigami.FormData.label: i18n("Security:")
            text: i18n("Use TLS")
            onToggled: {
                page.followTls(checked)
                page.brokerEdited()
            }
        }

        RowLayout {
            visible: page.mqtt
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
            visible: page.mqtt
            text: i18n("Leave the CA file empty to use the system's certificates (needs mosquitto 2.0 or newer). TLS brokers usually listen on port 8883; with mosquitto 2.0, port 8883 always uses TLS. Host must match the name on the broker's certificate.")
        }

        Kirigami.Separator {
            visible: page.mqtt
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("TeslaMate")
        }

        QQC2.TextField {
            id: topicPrefix
            visible: page.mqtt
            Kirigami.FormData.label: i18n("Topic prefix:")
            placeholderText: "teslamate/cars/1"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            onTextChanged: page.formEdited()
        }

        Hint {
            visible: page.mqtt
            text: i18n("If TeslaMate sets MQTT_NAMESPACE, use teslamate/<namespace>/cars/1.")
        }

        // Where the tokens go, for every source that has one.
        Hint {
            visible: !page.mqtt && page.cfg_tokensKeyringId !== "" && page.tokenValue() !== ""
                     && !tokensNote.visible
            text: i18n("The tokens are kept in the wallet, not in the widget's settings.")
        }

        Kirigami.InlineMessage {
            id: tokensNote
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            visible: !page.mqtt && text !== ""
            type: page.tokenSecret.storeFailed ? Kirigami.MessageType.Error
                : page.tokenSecret.moving(page.tokenValue()) ? Kirigami.MessageType.Information
                : Kirigami.MessageType.Warning
            text: page.tokensMessage()
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

            RestFetch {
                id: restFetch
                onFinished: (found, err) => page.restCheckFinished(found, err)
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
                const id = page.carKey(c)
                const text = c.name ? i18nc("car name (topic prefix, VIN or car ID)", "%1 (%2)", c.name, id) : id
                // The names come from the server, and the list guesses whether text is markup.
                return Logic.noMarkup(text)
            })
            displayText: currentIndex < 0 ? i18n("Choose a car…") : currentText
            onActivated: (index) => page.pickCar(page.cars[index])
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
            visible: !page.source.cloud
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
            visible: !page.source.cloud
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
            visible: page.source.cloud
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
            visible: page.source.cloud
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
            text: page.source.sleepAware
                ? i18n("Used while the car is asleep, offline or falling asleep and the popup is closed, and always for a widget on the desktop. Opening the popup or pressing Refresh updates right away, at most once a minute. Asking an awake car keeps it awake, so after 15 idle minutes the widget stops asking for 21 minutes to let it sleep, as TeslaMate does.")
                : i18n("Used while the car is asleep or offline and the popup is closed, and always for a widget on the desktop. Opening the popup or pressing Refresh updates right away.")
        }

        // Tesla's own prices, for the Fleet API itself.
        Hint {
            visible: dataSource.currentIndex === 1
            text: i18n("Tesla bills roughly $1 for every 500 data requests (the rate varies by region), with a $10 monthly credit for individual developers. Checking every 5 minutes while a car is awake 3 hours a day, and every 15 minutes while it sleeps, comes to about 4,000 requests a month. Services with the same API have their own prices.")
        }
    }
}
