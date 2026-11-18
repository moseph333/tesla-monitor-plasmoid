import QtQuick

// HTTP requests for TeslaApiFetch and RestFetch.
QtObject {
    id: http

    // Sends one request: body is null for none, or a form's text, and bearer a token for
    // the Authorization header or "". callback(status, body) runs once, with status 0 if
    // there was no reply within the timeout. Returns a function that ends the request at
    // once, as if it got no reply.
    //
    // Each request has a timer of its own: one that ends late must not stop the timer of a
    // request that followed it.
    function send(method, url, body, bearer, callback) {
        const xhr = new XMLHttpRequest()
        const timer = timeout.createObject(http)
        let finished = false
        const finish = (status, text) => {
            if (finished) return
            finished = true
            timer.destroy()
            callback(status, text)
        }
        const abort = () => {
            finish(0, "")
            try {
                xhr.abort()
            } catch (e) {
            }
        }
        timer.triggered.connect(abort)
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE) finish(xhr.status, String(xhr.responseText || ""))
        }
        xhr.open(method, url)
        xhr.setRequestHeader("Accept", "application/json")
        if (bearer) xhr.setRequestHeader("Authorization", "Bearer " + bearer)
        timer.start()
        if (body === null) {
            xhr.send()
        } else {
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
            xhr.send(body)
        }
        return abort
    }

    readonly property Component timeout: Component {
        Timer {
            interval: 20000
        }
    }
}
