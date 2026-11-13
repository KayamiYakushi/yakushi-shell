.pragma library
.import "SettingsSearch.js" as Core

// Keybinds search: say what you want to do, get the keys.
//
// "how do I open the app launcher", "ekran görüntüsü nasıl alınır",
// "super + c", "workspace 3" all land on the right shortcut. The matcher is
// Settings search's (SettingsSearch.js: folded letters, word endings,
// typos, the system's languages); this file brings the words.
//
// Three kinds of rows:
//   * shortcuts from keybinds.lua (yakushi-keybindctl.py list): WORDS says,
//     per bind id and language, how people describe what it does
//   * shortcuts Hyprland has that keybinds.lua does not mark (readonly,
//     category "Elsewhere"): searched by their label (the command they run)
//   * keys inside Yakushi's own windows (APP_KEYS, readonly): the launcher,
//     the pickers, the lock screen...
//
// Adding a shortcut or a window that takes keys: add its words here.
// scripts/check-keybinds.py (run by the package build) fails when a bind id
// in hypr/keybinds.lua has no WORDS, or a QML file that handles keys has no
// APP_KEYS rows.

// how a question is asked, not what it is about
var STOPS = {
    en: "the a an to of for in on at my me i how do does did can could what which where is are it its way there " +
        "key keys shortcut shortcuts keybind keybinds keybinding keybindings hotkey hotkeys keyboard press pressing " +
        "use using with open opening launch start run bring get want need should would something change changing",
    tr: "nasıl nerede hangi hangisi ne neyle ile için bir ve veya de da ben benim bana tuş tuşu tuşla tuşlar tuşları " +
        "tuşuyla kısayol kısayolu kısayolla kısayolları kısayolunu klavye klavyeden mı mi mu mü yapılır yaparım " +
        "yapabilirim yapmak olur var aç açılır açmak açma açarım açabilirim açıyorum açılıyor başlat başlatmak " +
        "çalıştır lazım gerek istiyorum basınca basarak bas değiştir değiştirmek değiştirme",
    de: "wie wo was welche welcher der die das den dem ein eine einen mein meine ich kann will möchte mit für und " +
        "oder zu ist taste tasten tastenkürzel tastenkombination kürzel drücken öffnen starten tastatur",
    es: "cómo dónde qué cuál el la los las un una mi yo puedo quiero con para y o de del en es tecla teclas " +
        "atajo atajos combinación pulsar presionar abrir iniciar teclado",
    fr: "comment où quoi quel quelle le la les un une mon ma mes je peux veux avec pour et ou de du des en est " +
        "touche touches raccourci raccourcis appuyer ouvrir lancer clavier",
    pt: "como onde qual que os as um uma meu minha eu posso quero com para e ou de do da em é tecla teclas " +
        "atalho atalhos pressionar apertar abrir iniciar teclado",
    it: "come dove quale che il lo la gli le un una mio mia io posso voglio con per e o di del della in è " +
        "tasto tasti scorciatoia scorciatoie premere aprire avviare tastiera",
    ru: "как где какой какая что мой моя я могу хочу с для и или в на клавиша клавиши сочетание горячие " +
        "нажать открыть запустить клавиатура",
    pl: "jak gdzie jaki jaka co mój moja ja mogę chcę z dla i lub w na klawisz klawisze skrót skróty " +
        "nacisnąć otworzyć uruchomić klawiatura"
}

function merge() {
    var out = {}
    for (var i = 0; i < arguments.length; i++)
        for (var l in arguments[i])
            out[l] = (out[l] ? out[l] + " " : "") + arguments[i][l]
    return out
}

var DIRS = {
    left:  { en: "left", tr: "sol sola", de: "links", es: "izquierda", fr: "gauche", pt: "esquerda", it: "sinistra",
             ru: "влево лево", pl: "lewo" },
    right: { en: "right", tr: "sağ sağa", de: "rechts", es: "derecha", fr: "droite", pt: "direita", it: "destra",
             ru: "вправо право", pl: "prawo" },
    up:    { en: "up above", tr: "yukarı üst", de: "hoch oben", es: "arriba", fr: "haut", pt: "cima", it: "su sopra",
             ru: "вверх", pl: "góra" },
    down:  { en: "down below", tr: "aşağı alt", de: "runter unten", es: "abajo", fr: "bas", pt: "baixo", it: "giù sotto",
             ru: "вниз", pl: "dół" }
}
var MOVE = { en: "move window shift", tr: "pencereyi taşı pencere kaydır", de: "fenster verschieben bewegen",
             es: "mover ventana", fr: "déplacer fenêtre", pt: "mover janela", it: "spostare finestra",
             ru: "переместить окно двигать", pl: "przenieś okno przesuń" }
var FOCUS = { en: "focus switch go window select", tr: "odak odakla geç pencere seç", de: "fokus wechseln fenster",
              es: "foco enfocar cambiar ventana", fr: "focus focaliser passer fenêtre", pt: "foco focar mudar janela",
              it: "focus finestra passare", ru: "фокус переключить окно", pl: "fokus przełącz okno" }
var RESIZE = { en: "resize window size", tr: "pencere boyut boyutlandır", de: "fenstergröße größe ändern",
               es: "redimensionar tamaño ventana", fr: "redimensionner taille fenêtre",
               pt: "redimensionar tamanho janela", it: "ridimensionare dimensione finestra",
               ru: "изменить размер окна размер", pl: "zmień rozmiar okna rozmiar" }
var SIZES = {
    left:  { en: "narrower smaller thinner left", tr: "daralt dar küçült sol", de: "schmaler kleiner links",
             es: "estrecha estrechar izquierda", fr: "étroite rétrécir gauche", pt: "estreita estreitar esquerda",
             it: "stretta restringere sinistra", ru: "уже сузить влево", pl: "węższe zwęź lewo" },
    right: { en: "wider bigger right", tr: "genişlet geniş büyüt sağ", de: "breiter größer rechts",
             es: "ancha ensanchar derecha", fr: "large élargir droite", pt: "larga alargar direita",
             it: "larga allargare destra", ru: "шире расширить вправо", pl: "szersze poszerz prawo" },
    up:    { en: "shorter smaller up height", tr: "kısalt kısa yukarı yükseklik", de: "kürzer niedriger höhe",
             es: "baja acortar altura", fr: "raccourcir hauteur", pt: "baixa encurtar altura",
             it: "bassa accorciare altezza", ru: "ниже уменьшить высоту", pl: "niższe skróć wysokość" },
    down:  { en: "taller bigger down height", tr: "uzat uzun aşağı yükseklik", de: "höher größer höhe",
             es: "alta alargar altura", fr: "agrandir hauteur", pt: "alta alongar altura",
             it: "alta allungare altezza", ru: "выше увеличить высоту", pl: "wyższe wydłuż wysokość" }
}
var WORKSPACE = { en: "workspace desktop virtual desktop", tr: "çalışma alanı masaüstü sanal masaüstü",
                  de: "arbeitsbereich arbeitsfläche desktop", es: "espacio de trabajo escritorio",
                  fr: "espace de travail bureau", pt: "área de trabalho espaço", it: "area di lavoro desktop",
                  ru: "рабочий стол рабочее пространство", pl: "obszar roboczy pulpit" }
var GO = { en: "switch go to", tr: "geç git", de: "wechseln gehen", es: "cambiar ir", fr: "changer aller",
           pt: "mudar ir", it: "passare vai", ru: "переключиться перейти", pl: "przełącz przejdź" }
var SEND = { en: "move send window", tr: "pencereyi taşı gönder pencere", de: "fenster verschieben senden",
             es: "mover enviar ventana", fr: "déplacer envoyer fenêtre", pt: "mover enviar janela",
             it: "spostare inviare finestra", ru: "переместить отправить окно", pl: "przenieś wyślij okno" }
var SHOT = { en: "screenshot screen shot capture print screen picture snapshot",
             tr: "ekran görüntüsü ekran resmi yakala ss", de: "bildschirmfoto screenshot aufnehmen",
             es: "captura de pantalla", fr: "capture d'écran", pt: "captura de tela print", it: "screenshot cattura",
             ru: "скриншот снимок экрана", pl: "zrzut ekranu" }
var ZOOM = { en: "zoom magnifier magnify screen", tr: "yakınlaştırma büyüteç ekran zoom", de: "zoom lupe",
             es: "zoom lupa", fr: "zoom loupe", pt: "zoom lupa", it: "zoom lente", ru: "зум лупа масштаб",
             pl: "powiększenie lupa zoom" }
var ZOOM_OUT = { en: "zoom out smaller", tr: "uzaklaştır küçült", de: "herauszoomen verkleinern", es: "alejar",
                 fr: "dézoomer", pt: "diminuir afastar", it: "rimpicciolire", ru: "уменьшить отдалить",
                 pl: "pomniejsz oddal" }
var ZOOM_IN = { en: "zoom in bigger", tr: "yakınlaştır büyüt", de: "hineinzoomen vergrößern", es: "acercar ampliar",
                fr: "zoomer agrandir", pt: "aumentar ampliar", it: "ingrandire", ru: "увеличить приблизить",
                pl: "powiększ przybliż" }
var WHEEL = { en: "wheel scroll mouse", tr: "tekerlek fare kaydır", de: "mausrad", es: "rueda ratón", fr: "molette souris",
              pt: "roda mouse", it: "rotellina mouse", ru: "колесо мышь", pl: "kółko mysz" }
var KEYPAD = { en: "keypad numpad plus minus", tr: "tuş takımı numpad artı eksi", de: "nummernblock plus minus",
               es: "teclado numérico más menos", fr: "pavé numérique plus moins", pt: "teclado numérico mais menos",
               it: "tastierino numerico più meno", ru: "цифровая клавиатура плюс минус",
               pl: "klawiatura numeryczna plus minus" }

var LAUNCHER_WORDS = {
    en: "app apps application applications launcher menu program programs search find app drawer start menu",
    tr: "uygulama uygulamalar başlatıcı uygulama başlatıcı menü program programlar ara",
    de: "anwendungen apps programme starter menü suchen", es: "aplicaciones apps lanzador menú programas buscar",
    fr: "applications apps lanceur menu programmes chercher", pt: "aplicativos apps lançador menu programas procurar",
    it: "applicazioni app launcher menu programmi cercare", ru: "приложения программы лаунчер меню запуска поиск",
    pl: "aplikacje programy launcher menu szukaj" }
var WALLPAPER_WORDS = {
    en: "wallpaper background desktop picture image wallpaper picker",
    tr: "duvar kağıdı arka plan masaüstü resmi", de: "hintergrundbild hintergrund",
    es: "fondo de pantalla fondo", fr: "fond d'écran", pt: "papel de parede plano de fundo", it: "sfondo",
    ru: "обои фон рабочего стола", pl: "tapeta tło pulpitu" }
var COLOUR_WORDS = {
    en: "color colour picker pick eyedropper hex code screen pixel copy",
    tr: "renk seçici seç pipet damlalık hex kodu ekran piksel kopyala",
    de: "farbe farbwähler pipette hex code bildschirm pixel kopieren",
    es: "color selector cuentagotas código hex pantalla píxel copiar",
    fr: "couleur sélecteur pipette code hex écran pixel copier",
    pt: "cor seletor conta-gotas código hex tela pixel copiar",
    it: "colore selettore contagocce codice hex schermo pixel copiare",
    ru: "цвет пипетка выбор цвета hex код экран пиксель копировать",
    pl: "kolor próbnik pipeta kod hex ekran piksel kopiuj" }
var POWER_WORDS = {
    en: "power menu shut down shutdown turn off restart reboot sleep suspend log out logout power off",
    tr: "güç menüsü bilgisayarı kapat yeniden başlat uyku askıya al oturumu kapat",
    de: "energie menü herunterfahren ausschalten neustart ruhezustand abmelden",
    es: "menú de energía apagar reiniciar suspender cerrar sesión",
    fr: "menu alimentation éteindre redémarrer veille déconnexion",
    pt: "menu de energia desligar reiniciar suspender sair", it: "menu alimentazione spegnere riavviare sospendere",
    ru: "меню питания выключить перезагрузить сон выйти", pl: "menu zasilania wyłącz uruchom ponownie uśpij wyloguj" }
var LOCK_WORDS = {
    en: "lock screen lock computer", tr: "ekranı kilitle kilit ekran kilidi", de: "bildschirm sperren sperre",
    es: "bloquear pantalla bloqueo", fr: "verrouiller écran verrouillage", pt: "bloquear tela bloqueio",
    it: "bloccare schermo blocco", ru: "заблокировать экран блокировка", pl: "zablokuj ekran blokada" }
var SETTINGS_WORDS = {
    en: "settings yakushi settings preferences control panel configuration options",
    tr: "ayarlar yakushi ayarları tercihler denetim masası kontrol paneli",
    de: "einstellungen systemsteuerung", es: "configuración ajustes panel de control preferencias",
    fr: "paramètres réglages panneau de configuration préférences",
    pt: "configurações ajustes painel de controle preferências", it: "impostazioni pannello di controllo preferenze",
    ru: "настройки параметры панель управления", pl: "ustawienia panel sterowania preferencje" }
var CLIPBOARD_WORDS = {
    en: "clipboard history copy paste copied clips", tr: "pano geçmişi kopyala yapıştır kopyalanan",
    de: "zwischenablage verlauf kopieren einfügen", es: "portapapeles historial copiar pegar",
    fr: "presse-papiers historique copier coller", pt: "área de transferência histórico copiar colar",
    it: "appunti cronologia copiare incollare", ru: "буфер обмена история копировать вставить",
    pl: "schowek historia kopiuj wklej" }

// bind id (keybinds.lua) -> how people say it
var WORDS = {
    terminal: { en: "terminal console shell command line cli konsole", tr: "terminal konsol komut satırı uçbirim",
                de: "terminal konsole kommandozeile", es: "terminal consola línea de comandos",
                fr: "terminal console ligne de commande", pt: "terminal console linha de comando",
                it: "terminale console riga di comando", ru: "терминал консоль командная строка",
                pl: "terminal konsola wiersz poleceń" },
    launcher: LAUNCHER_WORDS,
    files: { en: "file manager files folders explorer nautilus browse", tr: "dosya yöneticisi dosyalar klasör klasörler gezgin",
             de: "dateimanager dateien ordner explorer", es: "gestor de archivos archivos carpetas explorador",
             fr: "gestionnaire de fichiers fichiers dossiers explorateur",
             pt: "gerenciador de arquivos arquivos pastas explorador", it: "file manager gestore file cartelle",
             ru: "файловый менеджер файлы папки проводник", pl: "menedżer plików pliki foldery eksplorator" },
    browser: { en: "browser web internet firefox chrome website", tr: "tarayıcı internet web site",
               de: "browser webbrowser internet", es: "navegador internet web", fr: "navigateur internet web",
               pt: "navegador internet web", it: "browser internet web", ru: "браузер интернет веб",
               pl: "przeglądarka internet strona" },
    settings: SETTINGS_WORDS,
    wallpaper: WALLPAPER_WORDS,
    close: { en: "close window quit kill app close app", tr: "pencereyi kapat kapat kapatma pencere uygulamayı kapat",
             de: "fenster schließen beenden", es: "cerrar ventana salir", fr: "fermer fenêtre quitter",
             pt: "fechar janela sair", it: "chiudere finestra uscire", ru: "закрыть окно", pl: "zamknij okno" },
    fullscreen: { en: "fullscreen full screen maximize maximise", tr: "tam ekran büyüt ekranı kapla",
                  de: "vollbild maximieren", es: "pantalla completa maximizar", fr: "plein écran maximiser",
                  pt: "tela cheia maximizar", it: "schermo intero massimizzare",
                  ru: "полноэкранный полный экран развернуть", pl: "pełny ekran maksymalizuj" },
    float: { en: "float floating tiling untile free window toggle floating center centre",
             tr: "yüzen pencere serbest pencere döşeme ortala", de: "schwebend fliegend kacheln zentrieren",
             es: "flotante ventana flotante mosaico centrar", fr: "flottante fenêtre flottante mosaïque centrer",
             pt: "flutuante janela flutuante centralizar", it: "flottante finestra mobile centrare",
             ru: "плавающее окно плавающий центр", pl: "pływające okno wyśrodkuj" },
    mouse_move: { en: "move window mouse drag left click", tr: "pencereyi fare ile taşı sürükle sol tık",
                  de: "fenster maus ziehen verschieben", es: "mover ventana ratón arrastrar",
                  fr: "déplacer fenêtre souris glisser", pt: "mover janela mouse arrastar",
                  it: "spostare finestra mouse trascinare", ru: "переместить окно мышь перетащить",
                  pl: "przenieś okno mysz przeciągnij" },
    mouse_resize: { en: "resize window mouse drag right click size", tr: "pencereyi fare ile boyutlandır sağ tık boyut",
                    de: "fenstergröße maus ziehen", es: "redimensionar ventana ratón", fr: "redimensionner fenêtre souris",
                    pt: "redimensionar janela mouse", it: "ridimensionare finestra mouse",
                    ru: "изменить размер окна мышь", pl: "zmień rozmiar okna mysz" },
    lock: LOCK_WORDS,
    power: POWER_WORDS,
    exit: { en: "exit hyprland quit session log out logout leave desktop", tr: "hyprland çık oturumu kapat oturumdan çık",
            de: "hyprland beenden abmelden sitzung", es: "salir de hyprland cerrar sesión",
            fr: "quitter hyprland déconnexion session", pt: "sair do hyprland encerrar sessão",
            it: "uscire da hyprland esci sessione", ru: "выйти из hyprland завершить сеанс",
            pl: "wyjdź z hyprland wyloguj sesja" },
    topbar: { en: "top bar panel bar hide show toggle status bar taskbar",
              tr: "üst bar panel çubuk gizle göster durum çubuğu görev çubuğu",
              de: "obere leiste panel leiste ausblenden einblenden", es: "barra superior panel ocultar mostrar",
              fr: "barre supérieure panneau masquer afficher", pt: "barra superior painel ocultar mostrar",
              it: "barra superiore pannello nascondere mostrare", ru: "верхняя панель панель скрыть показать",
              pl: "górny pasek panel ukryj pokaż" },
    tasks: { en: "tasks task manager processes running programs frozen kill end task what runs",
             tr: "görevler görev yöneticisi işlemler çalışan programlar donmuş sonlandır",
             de: "aufgaben taskmanager prozesse laufende programme beenden",
             es: "tareas administrador de tareas procesos finalizar", fr: "tâches gestionnaire de tâches processus terminer",
             pt: "tarefas gerenciador de tarefas processos finalizar", it: "attività gestione attività processi terminare",
             ru: "задачи диспетчер задач процессы завершить", pl: "zadania menedżer zadań procesy zakończ" },
    unfreeze: { en: "unfreeze frozen stuck bar settings restart shell hang not responding fix",
                tr: "dondu donmuş takıldı bar ayarlar yeniden başlat yanıt vermiyor düzelt",
                de: "eingefroren hängt leiste neustarten reagiert nicht", es: "congelado colgado barra reiniciar no responde",
                fr: "figé bloqué barre redémarrer ne répond pas", pt: "travado congelado barra reiniciar não responde",
                it: "bloccato congelato barra riavviare non risponde", ru: "зависла зависание панель перезапустить не отвечает",
                pl: "zawieszony zamrożony pasek uruchom ponownie nie odpowiada" },
    clipboard: CLIPBOARD_WORDS,
    screenshot_full: merge(SHOT, { en: "whole screen full screen entire display", tr: "tüm ekran ekranın tamamı",
                                   de: "ganzer bildschirm", es: "pantalla completa", fr: "écran entier",
                                   pt: "tela inteira", it: "schermo intero", ru: "весь экран", pl: "cały ekran" }),
    screenshot_area: merge(SHOT, { en: "area region selection part snip crop", tr: "alan bölge seçim kısım kırp",
                                   de: "bereich auswahl ausschnitt", es: "área región selección recorte",
                                   fr: "zone région sélection", pt: "área região seleção recorte",
                                   it: "area regione selezione ritaglio", ru: "область выделение",
                                   pl: "obszar zaznaczenie wycinek" }),
    screenshot_window: merge(SHOT, { en: "window active window", tr: "pencere aktif pencere", de: "fenster",
                                     es: "ventana", fr: "fenêtre", pt: "janela", it: "finestra", ru: "окно", pl: "okno" }),
    color_picker: COLOUR_WORDS,
    keyboard_layout: { en: "keyboard layout language switch layout input language qwerty",
                       tr: "klavye düzeni dil değiştir dil geçiş türkçe ingilizce",
                       de: "tastaturlayout sprache wechseln", es: "distribución del teclado idioma cambiar",
                       fr: "disposition du clavier langue changer", pt: "layout do teclado idioma mudar",
                       it: "layout tastiera lingua cambiare", ru: "раскладка клавиатуры язык переключить",
                       pl: "układ klawiatury język przełącz" },
    zoom_out_wheel: merge(ZOOM, ZOOM_OUT, WHEEL),
    zoom_in_wheel: merge(ZOOM, ZOOM_IN, WHEEL),
    zoom_out_keypad: merge(ZOOM, ZOOM_OUT, KEYPAD),
    zoom_in_keypad: merge(ZOOM, ZOOM_IN, KEYPAD),
    volume_up: { en: "volume up louder sound increase raise", tr: "ses yükselt artır sesi artır sesi yükselt",
                 de: "lauter lautstärke erhöhen ton", es: "subir volumen más alto sonido",
                 fr: "augmenter volume plus fort son", pt: "aumentar volume mais alto som",
                 it: "alzare volume più forte audio", ru: "громче увеличить громкость звук",
                 pl: "głośniej zwiększ głośność dźwięk" },
    volume_down: { en: "volume down quieter lower sound decrease", tr: "sesi kıs ses azalt düşür",
                   de: "leiser lautstärke verringern", es: "bajar volumen más bajo", fr: "baisser volume moins fort",
                   pt: "diminuir volume mais baixo", it: "abbassare volume più piano", ru: "тише уменьшить громкость",
                   pl: "ciszej zmniejsz głośność" },
    volume_mute: { en: "mute unmute sound off silence volume", tr: "sessiz sesi kapat sustur ses",
                   de: "stumm stummschalten ton aus", es: "silenciar mute sonido", fr: "muet couper le son",
                   pt: "mudo silenciar som", it: "muto disattiva audio", ru: "без звука выключить звук",
                   pl: "wycisz dźwięk" },
    brightness_up: { en: "brightness up brighter screen backlight increase raise", tr: "parlaklık artır ekran parlaklığı yükselt aydınlat",
                     de: "heller helligkeit erhöhen bildschirm", es: "subir brillo más brillo pantalla",
                     fr: "augmenter luminosité plus lumineux écran", pt: "aumentar brilho mais brilho tela",
                     it: "aumentare luminosità più luminoso schermo", ru: "ярче увеличить яркость экран",
                     pl: "jaśniej zwiększ jasność ekran" },
    brightness_down: { en: "brightness down dimmer darker screen backlight decrease lower", tr: "parlaklık azalt ekran parlaklığı kıs karart",
                       de: "dunkler helligkeit verringern bildschirm", es: "bajar brillo menos brillo pantalla",
                       fr: "baisser luminosité moins lumineux écran", pt: "diminuir brilho menos brilho tela",
                       it: "diminuire luminosità meno luminoso schermo", ru: "темнее уменьшить яркость экран",
                       pl: "ciemniej zmniejsz jasność ekran" },
    media_play: { en: "play pause music song media resume stop", tr: "oynat duraklat müzik şarkı medya devam",
                  de: "abspielen pause musik lied", es: "reproducir pausa música canción",
                  fr: "lecture pause musique chanson", pt: "reproduzir pausar música",
                  it: "riproduci pausa musica canzone", ru: "воспроизвести пауза музыка песня",
                  pl: "odtwórz pauza muzyka piosenka" },
    media_next: { en: "next track song skip forward music", tr: "sonraki şarkı parça atla ileri müzik",
                  de: "nächster titel lied überspringen", es: "siguiente canción pista", fr: "piste suivante chanson",
                  pt: "próxima faixa música", it: "traccia successiva canzone", ru: "следующий трек песня",
                  pl: "następny utwór piosenka" },
    media_prev: { en: "previous track song back music", tr: "önceki şarkı parça geri müzik",
                  de: "vorheriger titel lied zurück", es: "anterior canción pista", fr: "piste précédente",
                  pt: "faixa anterior", it: "traccia precedente", ru: "предыдущий трек", pl: "poprzedni utwór" }
}

;["left", "right", "up", "down"].forEach(function(d) {
    WORDS["move_" + d] = merge(MOVE, DIRS[d])
    WORDS["focus_" + d] = merge(FOCUS, DIRS[d])
    WORDS["resize_" + d] = merge(RESIZE, SIZES[d])
})
for (var n = 1; n <= 10; n++) {
    WORDS["ws_" + n] = merge(WORKSPACE, GO, { en: String(n) })
    WORDS["move_ws_" + n] = merge(WORKSPACE, SEND, { en: String(n) })
}

// ---- keys inside Yakushi's own windows -------------------------------------
// `combo`: alternatives are separated by " / ", keys by " + ".
// `file`: the QML file that handles these keys (scripts/check-keybinds.py).
var APPS = {
    "Launcher": { file: "launcher/Launcher.qml", words: LAUNCHER_WORDS },
    "Wallpaper picker": { file: "wallpicker/WallpaperPicker.qml", words: WALLPAPER_WORDS },
    "Colour picker": { file: "colorpicker/ColorPicker.qml", words: COLOUR_WORDS },
    "Power menu": { file: "topbar/PowerCard.qml", words: POWER_WORDS },
    "Lock screen": { file: "lock/LockSurface.qml", words: LOCK_WORDS },
    "Lock preview": { file: "lock.qml", words: LOCK_WORDS },
    "Settings": { file: "SettingsWindow.qml", words: SETTINGS_WORDS },
    "Screen share": { file: "SharePicker.qml", words: {
        en: "screen share sharing picker stream", tr: "ekran paylaşımı paylaş yayın", de: "bildschirmfreigabe teilen",
        es: "compartir pantalla", fr: "partage d'écran partager", pt: "compartilhar tela",
        it: "condivisione schermo", ru: "демонстрация экрана поделиться", pl: "udostępnianie ekranu" } },
    "Top bar": { file: "topbar/MediaModule.qml", words: {
        en: "top bar panel", tr: "üst bar panel çubuk", de: "obere leiste", es: "barra superior",
        fr: "barre supérieure", pt: "barra superior", it: "barra superiore", ru: "верхняя панель",
        pl: "górny pasek" } },
    "Login screen": { file: "sddm/yakushi/Main.qml", words: {
        en: "login screen sign in sddm greeter", tr: "giriş ekranı oturum aç", de: "anmeldebildschirm anmelden",
        es: "pantalla de inicio de sesión", fr: "écran de connexion", pt: "tela de login",
        it: "schermata di accesso", ru: "экран входа вход", pl: "ekran logowania" } }
}

var APP_KEYS = [
    { app: "Launcher", combo: "Up / Down / Ctrl + P / Ctrl + N", label: "Move the selection",
      en: "move selection next previous select choose navigate", tr: "seçimi taşı sonraki önceki seç gez" },
    { app: "Launcher", combo: "Page Up / Page Down", label: "Jump six rows",
      en: "page jump scroll faster", tr: "sayfa atla hızlı" },
    { app: "Launcher", combo: "Tab", label: "Switch between apps and clipboard",
      en: "switch clipboard apps tab mode history", tr: "geç pano uygulamalar mod geçmiş" },
    { app: "Launcher", combo: "Enter", label: "Open the app (or copy the clip)",
      en: "choose select app copy clip", tr: "uygulamayı seç kopyala" },
    { app: "Launcher", combo: "Esc", label: "Close the launcher", en: "close hide cancel", tr: "kapat gizle vazgeç iptal" },

    { app: "Wallpaper picker", combo: "Left / Right / Wheel", label: "Browse the wallpapers",
      en: "browse next previous scroll flip", tr: "gez sonraki önceki kaydır" },
    { app: "Wallpaper picker", combo: "Home / End", label: "First / last wallpaper",
      en: "first last beginning end", tr: "ilk son baş" },
    { app: "Wallpaper picker", combo: "Enter / Space", label: "Set as wallpaper",
      en: "set apply choose", tr: "uygula ayarla seç kullan" },
    { app: "Wallpaper picker", combo: "Esc / W / Click outside", label: "Close the picker",
      en: "close cancel hide", tr: "kapat vazgeç gizle" },

    { app: "Colour picker", combo: "Left click", label: "Copy the colour's hex code",
      en: "copy hex code click pick", tr: "hex kodunu kopyala tıkla seç" },
    { app: "Colour picker", combo: "Esc / Right click", label: "Cancel", en: "cancel close quit", tr: "vazgeç iptal kapat" },

    { app: "Power menu", combo: "Left / Right / Tab", label: "Choose an action",
      en: "choose select next previous", tr: "seç sonraki önceki" },
    { app: "Power menu", combo: "Enter / Space", label: "Do it (shut down, restart...)",
      en: "confirm do", tr: "onayla uygula" },
    { app: "Power menu", combo: "Esc", label: "Close the menu", en: "close cancel", tr: "kapat vazgeç" },

    { app: "Lock screen", combo: "Enter", label: "Unlock", en: "unlock password log in submit",
      tr: "kilidi aç şifre parola gir" },
    { app: "Lock screen", combo: "Esc", label: "Clear the password field", en: "clear password erase reset",
      tr: "şifreyi temizle sil parola" },
    { app: "Lock preview", combo: "Esc", label: "Close the preview (it locks nothing)", en: "close preview test",
      tr: "önizlemeyi kapat önizleme deneme" },

    { app: "Settings", combo: "Esc", label: "Close Settings", en: "close hide quit", tr: "kapat gizle" },
    { app: "Settings", combo: "Ctrl + Tab / Ctrl + Shift + Tab", label: "Next / previous tab of a page",
      en: "tab tabs next previous switch page", tr: "sekme sonraki önceki geç sayfa" },
    { app: "Settings", combo: "Up / Down / Enter", label: "Pick a search result",
      en: "search result pick choose", tr: "arama sonuç seç" },

    { app: "Screen share", combo: "Tab / Shift + Tab", label: "Next / previous page",
      en: "next previous page", tr: "sonraki önceki sayfa" },
    { app: "Screen share", combo: "1 / 2 / 3", label: "Screens / Windows / Region",
      en: "screens windows region page monitor", tr: "ekranlar pencereler bölge sayfa monitör" },
    { app: "Screen share", combo: "Left / Right / Up / Down", label: "Move between the choices",
      en: "move select choose", tr: "seç gez" },
    { app: "Screen share", combo: "Enter", label: "Share", en: "share confirm", tr: "paylaş onayla" },
    { app: "Screen share", combo: "Esc", label: "Cancel (or clear the search)", en: "cancel close clear search",
      tr: "vazgeç iptal kapat temizle arama" },

    { app: "Top bar", combo: "Left click", label: "Song: play / pause", en: "song music play pause media",
      tr: "şarkı müzik oynat duraklat" },
    { app: "Top bar", combo: "Right click", label: "Song: next track", en: "song music next track skip",
      tr: "şarkı müzik sonraki atla" },
    { app: "Top bar", combo: "Middle click", label: "Song: previous track", en: "song music previous track back",
      tr: "şarkı müzik önceki geri" },
    { app: "Top bar", combo: "Wheel", label: "Volume: louder / quieter", en: "volume sound louder quieter",
      tr: "ses yükselt kıs" },
    { app: "Top bar", combo: "Left click", label: "Volume: mute", en: "volume sound mute", tr: "ses sessiz sustur" },
    { app: "Top bar", combo: "Right click", label: "Volume: open the mixer", en: "volume sound mixer apps",
      tr: "ses karıştırıcı mikser uygulama" },
    { app: "Top bar", combo: "Wheel", label: "Workspaces: switch workspace", en: "workspaces switch desktop",
      tr: "çalışma alanı geç masaüstü" },

    { app: "Login screen", combo: "Up / Down", label: "Switch user", en: "switch user account",
      tr: "kullanıcı değiştir hesap" },
    { app: "Login screen", combo: "Enter", label: "Log in", en: "log in sign in password", tr: "giriş yap oturum şifre" },
    { app: "Login screen", combo: "Esc", label: "Clear the password field", en: "clear password erase",
      tr: "şifreyi temizle sil" }
]

// APP_KEYS as rows shaped like the bind list's
function appRows() {
    return APP_KEYS.map(function(k, i) {
        return { id: "app:" + i, category: "In " + k.app, label: k.label, combo: k.combo, danger: false,
                 bindEnabled: true, readonly: true, inApp: true, source: "" }
    })
}

function wordsFor(row) {
    if (row.inApp) {
        var k = APP_KEYS[Number(row.id.slice(4))]
        return merge(APPS[k.app].words, { en: k.en || "", tr: k.tr || "" })
    }
    return WORDS[row.id] || { en: row.source || "" }
}

// ---- keys typed as keys: "super + c", "ctrl+tab", "super shift s" ----------
var MODS = { super: "SUPER", win: "SUPER", windows: "SUPER", meta: "SUPER", mod: "SUPER", cmd: "SUPER",
             ctrl: "CTRL", control: "CTRL", ctl: "CTRL", strg: "CTRL", alt: "ALT", shift: "SHIFT" }
var KEYNAMES = { esc: "escape", return: "enter", del: "delete", spacebar: "space", "`": "grave", backtick: "grave" }

function parseCombo(text) {
    var parts = String(text).toLowerCase().split(/[\s+]+/).filter(function(p) { return p !== "" })
    var mods = [], key = ""
    for (var i = 0; i < parts.length; i++) {
        if (MODS[parts[i]]) {
            if (mods.indexOf(MODS[parts[i]]) < 0)
                mods.push(MODS[parts[i]])
        } else if (key === "") {
            key = KEYNAMES[parts[i]] || parts[i]
        } else {
            return null                                  // two keys: words, not a combo
        }
    }
    mods.sort()
    return { mods: mods, key: key }
}

// the query as keys, or null when it reads as words
function comboQuery(query) {
    var q = String(query).trim()
    var m = q.match(/(?:\b(?:super|win|windows|meta|mod|cmd|ctrl|control|ctl|strg|alt|shift)\b\s*\+?\s*)+([^\s+]*)/i)
    if (!m)
        return null
    // the whole query, or the keys inside a sentence ("what does super + c do")
    var whole = parseCombo(q)
    if (whole && (q.indexOf("+") >= 0 || q.split(/\s+/).length <= 3))
        return whole
    return q.indexOf("+") >= 0 ? parseCombo(m[0]) : null
}

function comboMatches(want, combo) {
    var alts = String(combo).split(" / ")
    for (var i = 0; i < alts.length; i++) {
        var have = parseCombo(alts[i])
        if (!have)
            continue
        var sameMods = want.key !== "" ? have.mods.join() === want.mods.join()
                                       : want.mods.every(function(m) { return have.mods.indexOf(m) >= 0 })
        if (sameMods && (want.key === "" || have.key === want.key))
            return true
    }
    return false
}

// ---- search -----------------------------------------------------------------
var cache = { rows: null, key: "", prepared: null }

// { rows, best (a row or null), mode: "all" | "keys" | "words" }
function find(rows, query, langs) {
    langs = langs && langs.length ? langs : ["en"]
    if (String(query).trim() === "")
        return { rows: rows, best: null, mode: "all" }

    var want = comboQuery(query)
    if (want) {
        var hits = rows.filter(function(r) { return comboMatches(want, r.combo) })
        return { rows: hits, best: want.key !== "" && hits.length > 0 ? hits[0] : null, mode: "keys" }
    }

    if (cache.rows !== rows || cache.key !== langs.join(",")) {
        var index = rows.map(function(r) {
            // the keys themselves count a little ("escape", "tab"), like a page name
            return { row: r, title: r.label, page: r.category.replace(/^In /, "") + " " + r.combo,
                     keys: wordsFor(r), weight: r.inApp ? 0.85 : 1 }
        })
        cache = { rows: rows, key: langs.join(","), prepared: Core.prepareList(index, langs, STOPS) }
    }
    var found = Core.rank(cache.prepared, query, 14)
    return { rows: found.map(function(f) { return f.entry.row }),
             best: found.length > 0 ? found[0].entry.row : null, mode: "words" }
}

// a key as people know it: "mouse:272" -> "Left click" (display only)
var PRETTY = { "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
               "mouse_up": "Wheel up", "mouse_down": "Wheel down", "code:82": "Keypad -", "code:86": "Keypad +",
               "GRAVE": "`", "XF86AudioRaiseVolume": "Volume up key", "XF86AudioLowerVolume": "Volume down key",
               "XF86AudioMute": "Mute key", "XF86AudioPlay": "Play key", "XF86AudioNext": "Next key",
               "XF86AudioPrev": "Previous key" }

function prettyKey(key) {
    return PRETTY[key] || key
}

function languages(env) {
    return Core.languages(env)
}

function placeholder(langs) {
    var hint = Core.placeholder(langs)
    return hint + "  —  e.g. how do I open the launcher? · super + c"
}
