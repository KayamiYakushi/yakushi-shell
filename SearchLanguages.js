.pragma library

// Which languages Settings search speaks, from the system's locale variables,
// and the word for "search" in them. Kept apart from SettingsSearch.js so
// Settings can show its search field without loading the whole index: that
// loads with the first letter typed (SettingsSearchEngine.qml).

var LANGS = ["en", "tr", "de", "es", "fr", "pt", "it", "ru", "pl"]

// "SEARCH  ·  <this>" in the search field
var WORD = { tr: "ara", de: "suchen", es: "buscar", fr: "rechercher", pt: "pesquisar", it: "cerca",
             ru: "поиск", pl: "szukaj" }

// the languages to search in, from the locale variables (`env` reads one)
function languages(env) {
    var found = ["en"]
    var names = ["LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG", "LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_PAPER",
                 "LC_MEASUREMENT", "LC_ADDRESS", "LC_TELEPHONE", "LC_NAME"]
    for (var i = 0; i < names.length; i++) {
        var parts = String(env(names[i]) || "").split(":")      // LANGUAGE is a list
        for (var j = 0; j < parts.length; j++) {
            var code = parts[j].split(/[_.@]/)[0].toLowerCase()
            if (LANGS.indexOf(code) >= 0 && found.indexOf(code) < 0)
                found.push(code)
        }
    }
    return found
}

// the hint in the search field: "SEARCH", plus the word in your language
function placeholder(langs) {
    for (var i = 0; i < langs.length; i++)
        if (WORD[langs[i]])
            return "SEARCH  ·  " + WORD[langs[i]]
    return "SEARCH"
}
