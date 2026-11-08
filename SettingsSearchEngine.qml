import QtQuick
import "SettingsSearch.js" as SettingsSearch

// Settings search, loaded by Settings with the first letter typed (by file:
// the index is not even compiled before that).
Item {
    function search(query, limit, langs) {
        return SettingsSearch.search(query, limit, langs)
    }
}
