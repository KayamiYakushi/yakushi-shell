import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// The lock screen's one shared state: what is typed and the password check.
// Every screen's surface shows and edits this same text, so typing works on
// whichever screen has the keyboard.
//
// The check goes through PAM: /etc/pam.d/yakushi-lock when the package put
// it there (`yakushi lock` passes it on), else "login", like a text console.
// Either way the system's own rules apply: wrong-password delay, faillock
// after repeated failures, fingerprint or OTP modules if the system has them. Only PamResult.Success
// unlocks; any error keeps the screen locked.
//
// The typed text is cleared the moment it has been handed to PAM.
//
// Caps Lock: Wayland gives an app no lock-key state, so it is followed
// from the keys themselves, with no timing involved:
//   - when the lock opens: the keyboards' Caps Lock LEDs in /sys, read once;
//   - each Caps Lock press flips it (key repeat ignored);
//   - each letter typed settles it for sure: upper case without Shift (or
//     lower case with Shift) means Caps Lock is on.
Scope {
    id: ctx

    property string text: ""
    property string message: ""          // shown under the field
    property bool failed: false          // the last try was refused
    property int failures: 0             // bumped on each refusal (the field shakes)
    readonly property bool busy: pam.active && !pam.responseRequired

    property bool capsLock: false

    signal unlocked()

    property bool capsKnown: false       // a key has already told us

    // every key press in the field comes here first
    function keyPressed(event) {
        if (event.key === Qt.Key_CapsLock) {
            if (!event.isAutoRepeat) {
                capsLock = !capsLock
                capsKnown = true
            }
            return
        }
        var t = event.text
        if (t.length === 1 && t.toUpperCase() !== t.toLowerCase()) {
            var upper = t === t.toUpperCase()
            var shift = (event.modifiers & Qt.ShiftModifier) !== 0
            capsLock = upper !== shift
            capsKnown = true
        }
    }

    // the state when the lock opens: any keyboard's Caps Lock LED lit
    Process {
        running: true
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (ctx.capsKnown)
                    return
                ctx.capsLock = text.split("\n").some(function(v) {
                    return /^[1-9][0-9]*$/.test(v.trim())
                })
            }
        }
    }

    function submit() {
        if (busy || text === "")
            return
        failed = false

        // PAM asked a second question (a code, a new prompt): this is the answer
        if (pam.active && pam.responseRequired) {
            answer()
            return
        }

        message = ""
        if (!pam.start()) {
            text = ""
            refused("Could not start the password check.")
        }
    }

    function answer() {
        var response = text
        text = ""
        pam.respond(response)
    }

    function refused(why) {
        failed = true
        failures += 1
        message = why
    }

    PamContext {
        id: pam

        config: {
            var service = Quickshell.env("YAKUSHI_PAM_SERVICE") || ""
            return /^[a-z0-9][a-z0-9_-]*$/.test(service) ? service : "login"
        }

        // remembers whether this conversation already used the typed text
        property bool answered: false

        onActiveChanged: {
            if (active)
                answered = false
        }

        onPamMessage: {
            if (responseRequired) {
                if (!answered && ctx.text !== "") {
                    answered = true
                    ctx.answer()
                } else {
                    // a further question: show it and wait for the next Enter
                    ctx.message = message.replace(/:\s*$/, "")
                }
            } else if (message !== "") {
                ctx.message = message
            }
        }

        onCompleted: function(result) {
            ctx.text = ""
            if (result === PamResult.Success) {
                ctx.message = ""
                ctx.unlocked()
            } else if (result === PamResult.MaxTries) {
                ctx.refused("Too many tries. Wait a moment, then try again.")
            } else if (result === PamResult.Failed) {
                // keep a reason PAM gave (e.g. faillock), else say it plainly
                ctx.refused(ctx.message !== "" && pam.messageIsError ? ctx.message : "Wrong password.")
            } else {
                ctx.refused("The password check failed. Try again.")
            }
        }

        onError: function(error) {
            ctx.text = ""
            ctx.refused("The password check failed (" + PamError.toString(error) + ").")
        }
    }
}
