.pragma library

// Settings search: what you type -> the setting you mean.
//
// Every setting has a few words in English and Turkish (what it is called,
// what people call it). A query is cut into words, filler words ("ayarı",
// "değiştir", "how", "change") are dropped, and each word is matched
// against those words:
//   * exactly, or as the start of a longer word: Turkish adds endings
//     ("imlecini" is "imleç" + endings), and you may still be typing
//   * with a typo or two: letters swapped, missing, extra or wrong
//     ("curosr" -> cursor), by Damerau-Levenshtein distance
// Turkish letters are folded (ç->c, ğ->g, ı/İ->i, ö->o, ş->s, ü->u), so
// "imlec" and "imleç" are the same word. Everything runs here, offline.
//
// `find` is text shown on the page next to the setting: Settings scrolls
// to it and lights it up.

var INDEX = [
    // ---- System
    { page: "System", find: ["CHANGE", "ADD IMAGE"], title: "Profile picture",
      keys: "profile picture photo avatar pfp user image profil resmi resim fotograf foto kullanici avatar" },
    { page: "System", find: ["HARDWARE"], title: "Hardware and system info",
      keys: "hardware system info cpu processor gpu graphics card ram memory kernel uptime storage disk specs donanim sistem bilgi islemci ekran karti bellek cekirdek depolama ozellik bilgisayar" },

    // ---- Tasks
    { page: "Tasks", find: ["PROCESSES"], title: "Running programs (task manager)",
      keys: "task manager tasks processes running program kill end frozen stuck service cpu usage memory usage gorev yoneticisi gorevler islem surec calisan program kapat sonlandir donmus takilan servis kullanim" },

    // ---- Programs
    { page: "Programs", find: ["INSTALLED"], title: "Remove programs",
      keys: "programs apps uninstall remove delete installed packages package flatpak program uygulama kaldir sil silme yuklu paket" },
    { page: "Programs", find: ["REMOVED BEFORE"], title: "Undo a removal",
      keys: "undo restore removed reinstall put back geri al geri yukle silinen kaldirilan" },
    { page: "Programs", find: ["CLEAN UP"], title: "Clean up the computer",
      keys: "clean cleanup clean up junk cache caches free space disk space leftovers backups orphans tidy temizlik temizle temizleme cop gereksiz onbellek yer ac alan bosalt artik kalinti yedek disk" },

    // ---- Security
    { page: "Security", find: ["Auto lock"], title: "Auto lock",
      keys: "auto lock lock screen idle timeout screen lock lock after otomatik kilit kilitle kilitlenme ekran kilidi bekleme sure zaman asimi" },
    { page: "Security", find: ["Firewall"], title: "Firewall",
      keys: "firewall ufw ports block guvenlik duvari" },
    { page: "Security", find: ["Updates"], title: "System updates",
      keys: "updates update upgrade system update pacman guncelleme guncelle sistem" },
    { page: "Security", find: ["Disk encryption"], title: "Disk encryption",
      keys: "disk encryption luks encrypted sifreleme sifreli disk" },
    { page: "Security", find: ["Secure Boot"], title: "Secure Boot",
      keys: "secure boot uefi guvenli onyukleme" },
    { page: "Security", find: ["SSH server"], title: "SSH server",
      keys: "ssh server remote access sshd uzak erisim sunucu" },
    { page: "Security", find: ["Open to network"], title: "Open ports",
      keys: "open ports network listening exposed acik port ag dinleyen" },
    { page: "Security", find: ["PASSWORDS AND LOGINS"], title: "Logins and wrong passwords",
      keys: "logins login attempts wrong password failed sudo giris denemesi yanlis sifre parola" },
    { page: "Security", find: ["DEEP SCAN"], title: "Deep scan (system files)",
      keys: "deep scan virus malware rootkit integrity system files check virus tarama butunluk kontrol" },

    // ---- Appearance
    { page: "Appearance", find: ["DARK"], title: "Dark or light apps",
      keys: "dark mode light mode dark theme light theme theme colour scheme night koyu tema acik tema karanlik mod aydinlik tema renk semasi" },
    { page: "Appearance", find: ["Match app colours"], title: "App colours (GTK, Files)",
      keys: "app colours colors gtk nautilus files file manager theme match uygulama renkleri renk dosya yoneticisi tema uyum" },
    { page: "Appearance", find: ["File manager opacity"], title: "File manager transparency",
      keys: "file manager opacity transparency transparent see through blur nautilus files dosya yoneticisi saydamlik seffaflik seffaf transparan opaklik bulanik" },
    { page: "Appearance", find: ["ACCENT"], title: "Accent colour",
      keys: "accent colour color main colour theme colour pink red vurgu rengi ana renk renk tema rengi pembe kirmizi mavi yesil" },
    { page: "Appearance", find: ["Custom colour"], title: "Custom accent colour (hex)",
      keys: "custom colour color hex rgb ozel renk" },
    { page: "Appearance", find: ["PANEL OPACITY"], title: "Settings panel opacity",
      keys: "panel opacity glass transparency settings transparent panel saydamlik seffaflik cam ayarlar paneli" },
    { page: "Appearance", find: ["Opening animation"], title: "Launcher animation speed",
      keys: "launcher animation speed opening app menu start menu baslatici animasyon hiz acilis uygulama menusu" },
    { page: "Appearance", find: ["Screen edge gap"], title: "Gap at the screen edges",
      keys: "gaps gap edge margin space window spacing bosluk kenar pencere araligi" },
    { page: "Appearance", find: ["Gap between windows"], title: "Gap between windows",
      keys: "gaps gap between windows inner spacing bosluk pencereler arasi aralik" },
    { page: "Appearance", find: ["Corner cut"], title: "Window corners",
      keys: "corners corner rounding radius rounded cut sharp kose koseler yuvarlak yuvarlama kesik" },
    { page: "Appearance", find: ["Window shadow"], title: "Window shadow",
      keys: "shadow window shadow golge pencere golgesi" },
    { page: "Appearance", find: ["Window border"], title: "Window border",
      keys: "border outline frame window border colour kenarlik cerceve pencere kenari" },
    { page: "Appearance", find: ["Match terminal colours"], title: "Terminal colours",
      keys: "terminal colours colors kitty fish console terminal renkleri konsol" },
    { page: "Appearance", find: ["Terminal opacity"], title: "Terminal transparency",
      keys: "terminal opacity transparency transparent kitty terminal saydamlik seffaflik" },
    { page: "Appearance", find: ["Background blur"], title: "Terminal blur",
      keys: "blur background blur frosted terminal bulaniklik bulanik" },

    // ---- Top Bar
    { page: "Top Bar", find: ["Top bar opacity"], title: "Top bar opacity",
      keys: "top bar bar panel waybar opacity transparency ust bar ust panel cubuk saydamlik" },
    { page: "Top Bar", find: ["24-hour clock"], title: "24-hour clock",
      keys: "clock 24 hour 12 hour am pm time format saat 24 saat 12 saat bicimi" },
    { page: "Top Bar", find: ["Show seconds"], title: "Seconds on the clock",
      keys: "seconds clock saniye saat" },
    { page: "Top Bar", find: ["Date"], title: "Date in the top bar",
      keys: "date calendar day tarih takvim gun" },
    { page: "Top Bar", find: ["Workspaces"], title: "Workspaces in the top bar",
      keys: "workspaces workspace desktops virtual desktop calisma alani masaustu sanal masaustu" },
    { page: "Top Bar", find: ["Now playing"], title: "Now playing (music)",
      keys: "now playing music song media spotify player muzik sarki calan medya" },
    { page: "Top Bar", find: ["Music visualizer"], title: "Music visualizer",
      keys: "visualizer visualiser cava audio bars spectrum gorsellestirici ses dalgasi muzik" },
    { page: "Top Bar", find: ["CPU temp"], title: "CPU temperature",
      keys: "cpu temperature temp heat sensors islemci sicaklik isi" },
    { page: "Top Bar", find: ["GPU temp"], title: "GPU temperature",
      keys: "gpu temperature graphics temp ekran karti sicaklik" },
    { page: "Top Bar", find: ["CPU usage"], title: "CPU usage in the top bar",
      keys: "cpu usage load processor islemci kullanimi yuk" },
    { page: "Top Bar", find: ["RAM usage"], title: "RAM usage in the top bar",
      keys: "ram memory usage bellek kullanimi" },
    { page: "Top Bar", find: ["Volume"], title: "Volume in the top bar",
      keys: "volume sound ses seviyesi" },
    { page: "Top Bar", find: ["Power"], title: "Power button in the top bar",
      keys: "power shutdown restart button guc kapat yeniden baslat dugme" },
    { page: "Top Bar", find: ["MODULES"], title: "Top bar modules and order",
      keys: "modules order arrange widgets items moduller sira siralama oge" },

    // ---- Notifications
    { page: "Notifications", find: ["Show notifications"], title: "Notifications on or off",
      keys: "notifications notification popups do not disturb dnd silence bildirim bildirimler rahatsiz etme sessiz" },
    { page: "Notifications", find: ["Pop-up time"], title: "How long notifications stay",
      keys: "notification time duration timeout popup bildirim suresi sure" },

    // ---- Login Screen
    { page: "Login Screen", find: ["MATCH THE SHELL"], title: "Login screen (SDDM)",
      keys: "login screen sddm greeter sign in log in login background giris ekrani oturum acma karsilama arka plan" },

    // ---- Keybinds
    { page: "Keybinds", find: ["KEYBINDS"], title: "Keyboard shortcuts",
      keys: "keybinds keybindings shortcuts hotkeys keys bind kisayol kisayollar klavye kisayollari tus atama tuslar" },

    // ---- Default Apps
    { page: "Default Apps", find: ["DEFAULT APPS"], title: "Default apps (browser, terminal, files...)",
      keys: "default apps browser terminal file manager text editor image viewer video player music player pdf email mail open with varsayilan uygulama tarayici dosya yoneticisi metin duzenleyici resim goruntuleyici video oynatici muzik eposta" },
    { page: "Default Apps", find: ["SHELL"], title: "Login shell",
      keys: "shell login shell fish bash zsh kabuk" },
    { page: "Default Apps", find: ["Also save to a folder"], title: "Screenshots",
      keys: "screenshot screenshots screen capture snip print screen save folder ekran goruntusu ekran alintisi ss kaydet klasor" },
    { page: "Default Apps", find: ["Clipboard history"], title: "Clipboard history",
      keys: "clipboard history copy paste copied pano gecmisi kopyala yapistir kopyalanan" },

    // ---- Input
    { page: "Input", find: ["CURSOR"], title: "Mouse cursor",
      keys: "cursor mouse cursor pointer arrow cursor theme imlec fare imleci mouse imleci isaretci ok imlec temasi" },
    { page: "Input", find: ["SIZE"], title: "Cursor size",
      keys: "cursor size big small bigger smaller pointer size imlec boyutu buyukluk buyuk kucuk buyut kucult" },
    { page: "Input", find: ["SHAKE TO FIND"], title: "Shake to find the cursor",
      keys: "shake to find shake cursor find mouse lost pointer salla bul imlec bulma kaybolan" },
    { page: "Input", find: ["POINTER SPEED"], title: "Mouse speed",
      keys: "pointer speed mouse speed sensitivity acceleration dpi touchpad fare hizi hassasiyet ivme" },
    { page: "Input", find: ["KEYBOARD LANGUAGE"], title: "Keyboard language / layout",
      keys: "keyboard language layout turkish english q f keymap klavye dili klavye duzeni turkce ingilizce" },

    // ---- Sound
    { page: "Sound", find: ["OUTPUT DEVICE"], title: "Speakers / headphones",
      keys: "output device speakers headphones headset audio output sound card hoparlor kulaklik ses cikisi ses karti" },
    { page: "Sound", find: ["Output volume"], title: "Volume",
      keys: "volume loudness sound level mute louder quieter ses ses duzeyi ses seviyesi sessiz kis azalt arttir yukselt" },
    { page: "Sound", find: ["APPS"], title: "Volume per app",
      keys: "app volume per app mixer uygulama ses seviyesi karistirici" },

    // ---- Monitors
    { page: "Monitors", find: ["RESOLUTION"], title: "Screen resolution",
      keys: "resolution screen size 1080p 1440p 4k monitor display cozunurluk ekran boyutu monitor" },
    { page: "Monitors", find: ["REFRESH RATE"], title: "Refresh rate",
      keys: "refresh rate hz 144hz 60hz fps yenileme hizi" },
    { page: "Monitors", find: ["SCALE"], title: "Display scale",
      keys: "scale scaling zoom hidpi dpi bigger text olcek olcekleme buyutme" },
    { page: "Monitors", find: ["LAYOUT"], title: "Monitor layout and position",
      keys: "layout position arrange second monitor dual monitor multiple displays duzen konum ikinci ekran cift monitor" },
    { page: "Monitors", find: ["BRIGHTNESS"], title: "Brightness",
      keys: "brightness dim bright backlight parlaklik" },
    { page: "Monitors", find: ["Night light"], title: "Night light",
      keys: "night light blue light filter warm eye strain colour temperature night mode gece isigi mavi isik filtre goz sicak renk sicakligi" },

    // ---- Network
    { page: "Network", find: ["WI-FI"], title: "Wi-Fi",
      keys: "wifi wi-fi wireless network internet connect password ssid kablosuz ag internet baglan sifre" },
    { page: "Network", find: ["ETHERNET"], title: "Ethernet (cable)",
      keys: "ethernet cable wired lan kablo kablolu" },

    // ---- not a page: the wallpaper picker (SUPER + W)
    { run: "wallpaper", title: "Wallpaper (opens the picker, SUPER + W)",
      keys: "wallpaper background desktop picture desktop background image duvar kagidi arka plan masaustu resmi masaustu arka plani" },

    // ---- Bluetooth
    { page: "Bluetooth", find: ["BLUETOOTH"], title: "Bluetooth devices",
      keys: "bluetooth pair pairing headphones earbuds controller devices eslestir eslestirme kulaklik cihaz" }
]

// words that say nothing about which setting
var STOP = {}
;("ayar ayari ayarlar ayarlari ayarini ayarlarini ayarlama degistir degistirme degistirmek degisim nasil nerede nereden " +
  "neresi yap yapmak yapma icin ile bir ve veya ya da de ben benim bana istiyorum istedim olsun var yok ac kapa " +
  "bul goster lazim gerek mi mu ne kapat kapatma kapatmak actir acmak yapayim yapabilirim nasil the a an to of for in " +
  "on off my how where change changing set setting settings " +
  "option options turn make want find show do is it i me can").split(" ").forEach(function(w) { STOP[w] = true })

function fold(text) {
    return String(text)
        .replace(/İ/g, "i").replace(/I/g, "ı")      // Turkish capitals first...
        .toLowerCase()
        .replace(/ı/g, "i")                           // ...then dotless and dotted are one letter
        .replace(/ç/g, "c").replace(/ğ/g, "g").replace(/ö/g, "o").replace(/ş/g, "s").replace(/ü/g, "u")
        .replace(/[âà]/g, "a").replace(/[îì]/g, "i").replace(/[ûù]/g, "u")
        .replace(/-/g, "")
        .replace(/[^a-z0-9]+/g, " ")
        .trim()
}

function words(text) {
    var out = fold(text).split(" ")
    return out.filter(function(w) { return w.length > 0 })
}

// Damerau-Levenshtein (optimal string alignment): swaps count as one
function distance(a, b, limit) {
    if (Math.abs(a.length - b.length) > limit)
        return limit + 1
    var prev2 = null, prev = [], cur
    for (var j = 0; j <= b.length; j++)
        prev.push(j)
    for (var i = 1; i <= a.length; i++) {
        cur = [i]
        var best = i
        for (j = 1; j <= b.length; j++) {
            var cost = a[i - 1] === b[j - 1] ? 0 : 1
            var v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
                v = Math.min(v, prev2[j - 2] + 1)
            cur.push(v)
            if (v < best)
                best = v
        }
        if (best > limit)
            return limit + 1
        prev2 = prev
        prev = cur
    }
    return prev[b.length]
}

function allowed(n) {
    return n <= 3 ? 0 : n <= 5 ? 1 : 2
}

// how well one typed word fits one keyword (0 = not at all)
function fit(q, k) {
    if (q === k)
        return 3
    // a keyword with Turkish endings after it ("ses" + "ini"), or a word
    // still being typed; a short keyword only takes short endings, so
    // "gun" (day) does not swallow "guncelleme" (update)
    if (k.length >= 3 && q.indexOf(k) === 0 && (k.length >= 4 || q.length - k.length <= 3))
        return 2.6
    if (q.length >= 2 && k.indexOf(q) === 0)
        return 1.4 + 1.2 * q.length / k.length
    var limit = allowed(Math.min(q.length, k.length))
    if (limit > 0) {
        var d = distance(q, k, limit)
        if (d <= limit)
            return 2.2 - 0.5 * d
        // a typo in the stem, endings after it: "imlceini"
        if (q.length > k.length && k.length >= 5 && distance(q.slice(0, k.length), k, 1) <= 1)
            return 1.6
    }
    return 0
}

// keyword lists, folded once
var prepared = INDEX.map(function(e) {
    var own = words(e.title + " " + e.keys)
    var seen = {}
    var list = own.filter(function(w) { if (seen[w]) return false; seen[w] = true; return true })
    return { entry: e, keys: list, page: words(e.page || ""), title: words(e.title) }
})

// [{entry, score}], best first
function search(query, limit) {
    var q = words(query).filter(function(w) { return !STOP[w] })
    if (q.length === 0)
        return []
    var scored = []
    for (var i = 0; i < prepared.length; i++) {
        var p = prepared[i]
        var total = 0, hits = 0
        for (var a = 0; a < q.length; a++) {
            var best = 0
            for (var b = 0; b < p.keys.length; b++) {
                var f = fit(q[a], p.keys[b])
                if (f > best)
                    best = f
            }
            for (b = 0; b < p.page.length; b++)
                best = Math.max(best, 0.6 * fit(q[a], p.page[b]))
            // a word of the setting's own name counts a little more
            for (b = 0; b < p.title.length; b++)
                if (fit(q[a], p.title[b]) > 0)
                    best += 0.4
            if (best > 0)
                hits += 1
            total += best
        }
        if (total > 0)
            scored.push({ entry: p.entry, score: total * (hits === q.length ? 1.25 : hits / q.length) })
    }
    scored.sort(function(x, y) { return y.score - x.score })
    if (scored.length === 0)
        return []
    var top = scored[0].score
    return scored.filter(function(s) { return s.score >= top * 0.45 }).slice(0, limit || 8)
}
