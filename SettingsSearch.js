.pragma library
.import "SearchLanguages.js" as Lang

// Settings search: what you type -> the setting you mean, in your language.
//
// Every setting has words in several languages (what it is called, what
// people call it). Which languages are used comes from the system: English
// always, plus the languages of your locale variables (LANGUAGE, LANG,
// LC_MESSAGES, and the regional ones such as LC_TIME), so a system in
// English with Turkish formats searches in English and Turkish.
//
// A query is cut into words, filler words ("ayarı", "change", "ändern")
// are dropped, and each word is matched against the setting's words:
//   * exactly, or as the start of a longer word: many languages add endings
//     ("imlecini" is "imleç" + endings), and you may still be typing
//   * with a typo or two: letters swapped, missing, extra or wrong
//     ("curosr" -> cursor), by Damerau-Levenshtein distance
// Letters are folded first (ç->c, ı/İ->i, ö->o, ß->ss, ł->l, é->e, ё->е ...),
// so accents never decide. Everything runs here, offline.
//
// `find` is text shown on the page next to the setting: Settings scrolls to
// it and lights it up. `run` instead of `page`: a yakushi command (`wait`:
// once Settings has closed). `weight`
// below 1: ranks after an equal match (the top bar's show/hide switches come
// after the setting itself).
//
// Adding a language: its code in LANGS and WORD (SearchLanguages.js), STOPS
// (filler words) and a line per setting in its keys. Languages written
// without spaces between words (Japanese, Chinese) would need another matcher.

var INDEX = [
    // ---- System
    { page: "System", find: ["CHANGE", "ADD IMAGE"], title: "Profile picture", keys: {
        en: "profile picture photo avatar pfp user image",
        tr: "profil resmi resim fotoğraf foto kullanıcı",
        de: "profilbild foto bild benutzerbild",
        es: "foto de perfil imagen usuario",
        fr: "photo de profil image utilisateur",
        pt: "foto de perfil imagem usuário",
        it: "immagine del profilo foto utente",
        ru: "фото профиля аватар изображение пользователь",
        pl: "zdjęcie profilowe awatar obraz użytkownik" } },
    { page: "System", find: ["GPU"], title: "Hardware and system info", keys: {
        en: "hardware system info cpu processor gpu graphics card ram memory kernel uptime storage disk specs",
        tr: "donanım sistem bilgi işlemci ekran kartı bellek çekirdek depolama özellikler bilgisayar",
        de: "systeminfo prozessor grafikkarte arbeitsspeicher speicher festplatte computer",
        es: "información del sistema procesador tarjeta gráfica memoria almacenamiento disco ordenador",
        fr: "matériel informations système processeur carte graphique mémoire stockage disque ordinateur",
        pt: "informações do sistema processador placa de vídeo memória armazenamento disco computador",
        it: "informazioni di sistema processore scheda video memoria archiviazione disco computer",
        ru: "оборудование железо система процессор видеокарта память диск компьютер характеристики",
        pl: "sprzęt informacje o systemie procesor karta graficzna pamięć dysk komputer" } },

    // ---- Tasks
    { page: "Tasks", find: ["PROCESSES"], title: "Running programs (task manager)", keys: {
        en: "task manager tasks processes running program kill end frozen stuck service cpu usage memory usage",
        tr: "görev yöneticisi görevler işlem süreç çalışan program sonlandır donmuş takılan servis kullanım",
        de: "taskmanager aufgaben prozesse laufende programme beenden eingefroren hängt dienst",
        es: "administrador de tareas procesos programas en ejecución finalizar congelado colgado servicio",
        fr: "gestionnaire de tâches processus programmes en cours terminer figé bloqué service",
        pt: "gerenciador de tarefas processos programas em execução finalizar travado congelado serviço",
        it: "gestione attività processi programmi in esecuzione termina bloccato congelato servizio",
        ru: "диспетчер задач процессы запущенные программы завершить зависла служба",
        pl: "menedżer zadań procesy uruchomione programy zakończ zawieszony usługa" } },

    // ---- Programs
    { page: "Programs", find: ["INSTALLED"], title: "Remove programs", keys: {
        en: "programs apps uninstall remove delete installed packages package flatpak",
        tr: "program uygulama kaldır sil silme yüklü paket",
        de: "programme deinstallieren entfernen löschen installiert pakete",
        es: "programas aplicaciones desinstalar quitar eliminar instalados paquetes",
        fr: "programmes applications désinstaller supprimer installés paquets",
        pt: "programas aplicativos desinstalar remover excluir instalados pacotes",
        it: "programmi disinstallare rimuovere eliminare installati pacchetti",
        ru: "программы приложения удалить установленные пакеты",
        pl: "programy aplikacje odinstaluj usuń zainstalowane pakiety" } },
    { page: "Programs", find: ["REMOVED BEFORE"], title: "Undo a removal", keys: {
        en: "undo restore removed reinstall put back",
        tr: "geri al geri yükle silinen kaldırılan",
        de: "rückgängig wiederherstellen entfernt neu installieren",
        es: "deshacer restaurar eliminados reinstalar",
        fr: "annuler restaurer supprimés réinstaller",
        pt: "desfazer restaurar removidos reinstalar",
        it: "annulla ripristina rimossi reinstallare",
        ru: "отменить восстановить удалённые переустановить",
        pl: "cofnij przywróć usunięte zainstaluj ponownie" } },
    { page: "Programs", find: ["CLEAN UP"], title: "Clean up the computer", keys: {
        en: "clean cleanup clean up junk cache caches free space disk space leftovers backups orphans tidy",
        tr: "temizlik temizle temizleme çöp gereksiz önbellek yer aç alan boşalt artık kalıntı yedek disk",
        de: "aufräumen bereinigen säubern müll cache speicherplatz freigeben reste",
        es: "limpiar limpieza basura caché liberar espacio restos",
        fr: "nettoyer nettoyage déchets cache libérer espace restes",
        pt: "limpar limpeza lixo cache liberar espaço restos",
        it: "pulire pulizia spazzatura cache liberare spazio residui",
        ru: "очистка очистить мусор кэш освободить место остатки",
        pl: "wyczyść czyszczenie śmieci pamięć podręczna zwolnij miejsce pozostałości" } },

    // ---- Security
    { page: "Security", find: ["Auto lock"], title: "Auto lock", keys: {
        en: "auto lock lock screen idle timeout screen lock lock after",
        tr: "otomatik kilit kilitle kilitlenme ekran kilidi bekleme süre zaman aşımı",
        de: "automatische sperre bildschirmsperre sperren leerlauf",
        es: "bloqueo automático bloquear pantalla inactividad",
        fr: "verrouillage automatique verrouiller écran inactivité",
        pt: "bloqueio automático bloquear tela inatividade",
        it: "blocco automatico bloccare schermo inattività",
        ru: "автоблокировка блокировка экрана заблокировать бездействие",
        pl: "automatyczna blokada blokada ekranu zablokuj bezczynność" } },
    { page: "Security", find: ["Firewall"], title: "Firewall", keys: {
        en: "firewall ufw ports block", tr: "güvenlik duvarı", de: "firewall", es: "cortafuegos",
        fr: "pare-feu", pt: "firewall", it: "firewall", ru: "брандмауэр файрвол", pl: "zapora" } },
    { page: "Security", find: ["Updates"], title: "System updates", keys: {
        en: "updates update upgrade system update pacman", tr: "güncelleme güncelle sistem",
        de: "aktualisierung aktualisieren", es: "actualizaciones actualizar", fr: "mises à jour mettre à jour",
        pt: "atualizações atualizar", it: "aggiornamenti aggiornare", ru: "обновления обновить",
        pl: "aktualizacje zaktualizuj" } },
    { page: "Security", find: ["Hardening"], title: "Hardening (kernel and network)", keys: {
        en: "hardening harden kernel sysctl llmnr mdns avahi dns over tls protection strengthen secure",
        tr: "sıkılaştırma güçlendirme çekirdek koruma güvenli sertleştirme",
        de: "härtung härten kernel absichern schutz", es: "endurecimiento reforzar núcleo protección",
        fr: "durcissement renforcer noyau protection", pt: "endurecimento reforçar núcleo proteção",
        it: "rafforzamento rafforzare kernel protezione", ru: "усиление защита ядро укрепить",
        pl: "utwardzanie wzmocnienie jądro ochrona" } },
    { page: "Security", find: ["Disk encryption"], title: "Disk encryption", keys: {
        en: "disk encryption luks encrypted", tr: "şifreleme şifreli disk", de: "verschlüsselung festplattenverschlüsselung",
        es: "cifrado de disco", fr: "chiffrement du disque", pt: "criptografia de disco", it: "crittografia del disco",
        ru: "шифрование диска", pl: "szyfrowanie dysku" } },
    { page: "Security", find: ["Secure Boot"], title: "Secure Boot", keys: {
        en: "secure boot uefi", tr: "güvenli önyükleme", de: "sicherer start", es: "arranque seguro",
        fr: "démarrage sécurisé", pt: "inicialização segura", it: "avvio protetto", ru: "безопасная загрузка",
        pl: "bezpieczny rozruch" } },
    { page: "Security", find: ["SSH server"], title: "SSH server", keys: {
        en: "ssh server remote access sshd", tr: "uzak erişim sunucu", de: "fernzugriff server",
        es: "acceso remoto servidor", fr: "accès à distance serveur", pt: "acesso remoto servidor",
        it: "accesso remoto server", ru: "удалённый доступ сервер", pl: "zdalny dostęp serwer" } },
    { page: "Security", find: ["Open to network"], title: "Open ports", keys: {
        en: "open ports network listening exposed", tr: "açık port ağ dinleyen", de: "offene ports netzwerk",
        es: "puertos abiertos red", fr: "ports ouverts réseau", pt: "portas abertas rede", it: "porte aperte rete",
        ru: "открытые порты сеть", pl: "otwarte porty sieć" } },
    { page: "Security", find: ["PASSWORDS AND LOGINS"], title: "Logins and wrong passwords", keys: {
        en: "logins login attempts wrong password failed sudo", tr: "giriş denemesi yanlış şifre parola",
        de: "anmeldungen falsches passwort", es: "inicios de sesión contraseña incorrecta",
        fr: "connexions mot de passe incorrect", pt: "logins senha errada", it: "accessi password errata",
        ru: "входы неверный пароль", pl: "logowania błędne hasło" } },
    { page: "Security", find: ["APP SANDBOX"], title: "App sandbox (Flatpak permissions)", keys: {
        en: "app sandbox flatpak permissions camera devices access files what apps can reach",
        tr: "uygulama izinleri izin kamera erişim korumalı alan dosya aygıt",
        de: "app berechtigungen kamera zugriff sandbox", es: "permisos de aplicaciones cámara acceso",
        fr: "autorisations des applications caméra accès", pt: "permissões de aplicativos câmera acesso",
        it: "permessi delle app fotocamera accesso", ru: "разрешения приложений камера доступ песочница",
        pl: "uprawnienia aplikacji kamera dostęp piaskownica" } },
    { page: "Security", find: ["DEEP SCAN"], title: "Deep scan (system files)", keys: {
        en: "deep scan virus malware rootkit integrity system files check", tr: "virüs tarama bütünlük kontrol",
        de: "virus überprüfung systemdateien", es: "virus escaneo análisis integridad", fr: "virus analyse intégrité",
        pt: "vírus verificação integridade", it: "virus scansione integrità",
        ru: "вирус сканирование проверка целостность", pl: "wirus skanowanie integralność" } },

    // ---- Appearance
    { page: "Appearance", find: ["DARK"], title: "Dark or light apps", keys: {
        en: "dark mode light mode dark theme light theme theme colour scheme night",
        tr: "koyu tema açık tema karanlık mod aydınlık renk şeması",
        de: "dunkler modus heller modus dunkel hell thema", es: "modo oscuro modo claro tema",
        fr: "mode sombre mode clair thème", pt: "modo escuro modo claro tema",
        it: "modalità scura modalità chiara tema", ru: "тёмная тема светлая тема тёмный режим",
        pl: "tryb ciemny tryb jasny motyw" } },
    { page: "Appearance", find: ["Match app colours"], title: "App colours (GTK, Files)", keys: {
        en: "app colours colors gtk nautilus files file manager theme match folder icons accent",
        tr: "uygulama renkleri renk dosya yöneticisi tema uyum klasör simgeleri ikonlar", de: "app farben dateimanager ordner symbole",
        es: "colores de aplicaciones gestor de archivos", fr: "couleurs des applications gestionnaire de fichiers",
        pt: "cores dos aplicativos gerenciador de arquivos", it: "colori delle app file manager",
        ru: "цвета приложений файловый менеджер", pl: "kolory aplikacji menedżer plików" } },
    { page: "Appearance", find: ["File manager opacity"], title: "File manager transparency", keys: {
        en: "file manager opacity transparency transparent see through blur nautilus files",
        tr: "dosya yöneticisi saydamlık şeffaflık şeffaf transparan opaklık bulanık",
        de: "dateimanager transparenz durchsichtig deckkraft",
        es: "gestor de archivos transparencia transparente opacidad",
        fr: "gestionnaire de fichiers transparence transparent opacité",
        pt: "gerenciador de arquivos transparência transparente opacidade",
        it: "file manager trasparenza trasparente opacità",
        ru: "файловый менеджер прозрачность прозрачный", pl: "menedżer plików przezroczystość przezroczysty" } },
    { page: "Appearance", find: ["ACCENT"], title: "Accent colour", keys: {
        en: "accent colour color main colour theme colour pink red",
        tr: "vurgu rengi ana renk renk tema rengi pembe kırmızı mavi yeşil", de: "akzentfarbe farbe",
        es: "color de acento color", fr: "couleur d'accent couleur", pt: "cor de destaque cor",
        it: "colore di accento colore", ru: "цвет акцента цвет", pl: "kolor akcentu kolor" } },
    { page: "Appearance", find: ["Custom colour"], title: "Custom accent colour (hex)", keys: {
        en: "custom colour color hex rgb", tr: "özel renk", de: "eigene farbe", es: "color personalizado",
        fr: "couleur personnalisée", pt: "cor personalizada", it: "colore personalizzato", ru: "свой цвет",
        pl: "własny kolor" } },
    { page: "Appearance", find: ["PANEL OPACITY"], title: "Settings panel opacity", keys: {
        en: "panel opacity glass transparency settings transparent",
        tr: "panel saydamlık şeffaflık cam ayarlar paneli", de: "panel transparenz glas",
        es: "transparencia del panel", fr: "transparence du panneau", pt: "transparência do painel",
        it: "trasparenza del pannello", ru: "прозрачность панели", pl: "przezroczystość panelu" } },
    { page: "Appearance", find: ["Opening animation"], title: "Launcher animation speed", keys: {
        en: "launcher animation speed opening app menu start menu",
        tr: "başlatıcı animasyon hız açılış uygulama menüsü", de: "starter animation geschwindigkeit startmenü",
        es: "lanzador animación velocidad menú de inicio", fr: "lanceur animation vitesse menu démarrer",
        pt: "lançador animação velocidade menu iniciar", it: "launcher animazione velocità menu start",
        ru: "лаунчер анимация скорость меню запуска", pl: "launcher animacja szybkość menu start" } },
    { page: "Appearance", find: ["Launcher opacity"], title: "Launcher opacity", keys: {
        en: "launcher opacity transparency transparent app menu start menu background",
        tr: "başlatıcı saydamlık şeffaflık opaklık uygulama menüsü arka plan",
        de: "starter transparenz deckkraft startmenü", es: "lanzador transparencia opacidad menú de inicio",
        fr: "lanceur transparence opacité menu démarrer", pt: "lançador transparência opacidade menu iniciar",
        it: "launcher trasparenza opacità menu start", ru: "лаунчер прозрачность непрозрачность меню запуска",
        pl: "launcher przezroczystość krycie menu start" } },
    { page: "Appearance", find: ["Screen edge gap"], title: "Gap at the screen edges", keys: {
        en: "gaps gap edge margin space window spacing", tr: "boşluk kenar pencere aralığı",
        de: "abstand rand fenster", es: "espacio margen bordes ventanas", fr: "espace marge bords fenêtres",
        pt: "espaço margem bordas janelas", it: "spazio margine bordi finestre",
        ru: "отступ край окна промежуток", pl: "odstęp margines krawędź okna" } },
    { page: "Appearance", find: ["Gap between windows"], title: "Gap between windows", keys: {
        en: "gaps gap between windows inner spacing", tr: "boşluk pencereler arası aralık",
        de: "abstand zwischen fenstern", es: "espacio entre ventanas", fr: "espace entre fenêtres",
        pt: "espaço entre janelas", it: "spazio tra finestre", ru: "промежуток между окнами",
        pl: "odstęp między oknami" } },
    { page: "Appearance", find: ["Corner cut"], title: "Window corners", keys: {
        en: "corners corner rounding radius rounded cut sharp", tr: "köşe köşeler yuvarlak yuvarlama kesik",
        de: "ecken abgerundet radius", es: "esquinas redondeadas radio", fr: "coins arrondis rayon",
        pt: "cantos arredondados raio", it: "angoli arrotondati raggio", ru: "углы скругление радиус",
        pl: "rogi zaokrąglenie promień" } },
    { page: "Appearance", find: ["Window shadow"], title: "Window shadow", keys: {
        en: "shadow window shadow", tr: "gölge pencere gölgesi", de: "schatten fensterschatten", es: "sombra",
        fr: "ombre", pt: "sombra", it: "ombra", ru: "тень", pl: "cień" } },
    { page: "Appearance", find: ["Window border"], title: "Window border", keys: {
        en: "border outline frame window border colour", tr: "kenarlık çerçeve pencere kenarı",
        de: "rahmen fensterrahmen", es: "borde marco", fr: "bordure cadre", pt: "borda moldura",
        it: "bordo cornice", ru: "рамка граница окна", pl: "obramowanie ramka" } },
    { page: "Appearance", find: ["Match terminal colours"], title: "Terminal colours", keys: {
        en: "terminal colours colors kitty fish console", tr: "terminal renkleri konsol",
        de: "terminal farben konsole", es: "colores del terminal consola", fr: "couleurs du terminal console",
        pt: "cores do terminal console", it: "colori del terminale console", ru: "цвета терминала консоль",
        pl: "kolory terminala konsola" } },
    { page: "Appearance", find: ["Terminal opacity"], title: "Terminal transparency", keys: {
        en: "terminal opacity transparency transparent kitty", tr: "terminal saydamlık şeffaflık",
        de: "terminal transparenz", es: "transparencia del terminal", fr: "transparence du terminal",
        pt: "transparência do terminal", it: "trasparenza del terminale", ru: "прозрачность терминала",
        pl: "przezroczystość terminala" } },
    { page: "Appearance", find: ["Terminal padding"], title: "Terminal padding", keys: {
        en: "terminal padding space edge margin gap border kitty text inset",
        tr: "terminal kenar boşluk boşluğu kenarlardan iç boşluk dolgu yazı",
        de: "terminal innenabstand abstand rand", es: "relleno espacio margen del terminal",
        fr: "marge intérieure espacement bord du terminal", pt: "preenchimento espaço margem do terminal",
        it: "spaziatura margine bordo del terminale", ru: "отступ поля терминала край",
        pl: "dopełnienie odstęp margines terminala" } },
    { page: "Appearance", find: ["Background blur"], title: "Terminal blur", keys: {
        en: "blur background blur frosted terminal", tr: "bulanıklık bulanık", de: "unschärfe weichzeichnen",
        es: "desenfoque", fr: "flou", pt: "desfoque", it: "sfocatura", ru: "размытие", pl: "rozmycie" } },

    // ---- Top Bar
    { page: "Top Bar", find: ["Top bar opacity"], title: "Top bar opacity", keys: {
        en: "top bar bar panel waybar opacity transparency", tr: "üst bar üst panel çubuk saydamlık",
        de: "obere leiste leiste transparenz", es: "barra superior transparencia",
        fr: "barre supérieure transparence", pt: "barra superior transparência",
        it: "barra superiore trasparenza", ru: "верхняя панель прозрачность", pl: "górny pasek przezroczystość" } },
    { page: "Top Bar", find: ["24-hour clock"], title: "24-hour clock", keys: {
        en: "clock 24 hour 12 hour am pm time format", tr: "saat 24 saat 12 saat biçimi",
        de: "uhr 24 stunden zeitformat", es: "reloj 24 horas formato de hora", fr: "horloge 24 heures format de l'heure",
        pt: "relógio 24 horas formato de hora", it: "orologio 24 ore formato ora", ru: "часы 24 часа формат времени",
        pl: "zegar 24 godziny format czasu" } },
    { page: "Top Bar", find: ["Show seconds"], title: "Seconds on the clock", keys: {
        en: "seconds clock", tr: "saniye saat", de: "sekunden uhr", es: "segundos reloj", fr: "secondes horloge",
        pt: "segundos relógio", it: "secondi orologio", ru: "секунды часы", pl: "sekundy zegar" } },
    { page: "Top Bar", find: ["Date"], title: "Date in the top bar", weight: 0.9, keys: {
        en: "date calendar day", tr: "tarih takvim gün", de: "datum kalender", es: "fecha calendario",
        fr: "date calendrier", pt: "data calendário", it: "data calendario", ru: "дата календарь",
        pl: "data kalendarz" } },
    { page: "Top Bar", find: ["Workspaces"], title: "Workspaces in the top bar", weight: 0.9, keys: {
        en: "workspaces workspace desktops virtual desktop", tr: "çalışma alanı masaüstü sanal masaüstü",
        de: "arbeitsbereiche virtuelle desktops", es: "espacios de trabajo escritorios virtuales",
        fr: "espaces de travail bureaux virtuels", pt: "áreas de trabalho espaços de trabalho",
        it: "aree di lavoro desktop virtuali", ru: "рабочие столы рабочие пространства",
        pl: "obszary robocze pulpity wirtualne" } },
    { page: "Top Bar", find: ["Now playing"], title: "Now playing (music)", weight: 0.9, keys: {
        en: "now playing music song media spotify player", tr: "müzik şarkı çalan medya",
        de: "musik lied wiedergabe", es: "reproduciendo música canción", fr: "lecture en cours musique chanson",
        pt: "tocando agora música", it: "in riproduzione musica canzone", ru: "сейчас играет музыка песня",
        pl: "teraz odtwarzane muzyka utwór" } },
    { page: "Top Bar", find: ["Music visualizer"], title: "Music visualizer", weight: 0.9, keys: {
        en: "visualizer visualiser cava audio bars spectrum", tr: "görselleştirici ses dalgası müzik",
        de: "visualisierung spektrum", es: "visualizador espectro", fr: "visualiseur spectre",
        pt: "visualizador espectro", it: "visualizzatore spettro", ru: "визуализатор спектр",
        pl: "wizualizator spektrum" } },
    { page: "Top Bar", find: ["CPU temp"], title: "CPU temperature", weight: 0.9, keys: {
        en: "cpu temperature temp heat sensors", tr: "işlemci sıcaklık ısı", de: "cpu temperatur prozessor",
        es: "temperatura cpu procesador", fr: "température cpu processeur", pt: "temperatura cpu processador",
        it: "temperatura cpu processore", ru: "температура процессора", pl: "temperatura procesora" } },
    { page: "Top Bar", find: ["GPU temp"], title: "GPU temperature", weight: 0.9, keys: {
        en: "gpu temperature graphics temp", tr: "ekran kartı sıcaklık", de: "gpu temperatur grafikkarte",
        es: "temperatura gpu tarjeta gráfica", fr: "température gpu carte graphique",
        pt: "temperatura gpu placa de vídeo", it: "temperatura gpu scheda video",
        ru: "температура видеокарты", pl: "temperatura karty graficznej" } },
    { page: "Top Bar", find: ["CPU usage"], title: "CPU usage in the top bar", weight: 0.9, keys: {
        en: "cpu usage load processor", tr: "işlemci kullanımı yük", de: "cpu auslastung prozessor",
        es: "uso de cpu procesador", fr: "utilisation cpu processeur", pt: "uso de cpu processador",
        it: "utilizzo cpu processore", ru: "загрузка процессора", pl: "użycie procesora" } },
    { page: "Top Bar", find: ["RAM usage"], title: "RAM usage in the top bar", weight: 0.9, keys: {
        en: "ram memory usage", tr: "bellek kullanımı", de: "arbeitsspeicher auslastung",
        es: "uso de memoria ram", fr: "utilisation mémoire ram", pt: "uso de memória ram",
        it: "utilizzo memoria ram", ru: "использование памяти оперативная", pl: "użycie pamięci ram" } },
    { page: "Top Bar", find: ["Volume"], title: "Volume in the top bar", weight: 0.9, keys: {
        en: "volume sound", tr: "ses seviyesi", de: "lautstärke", es: "volumen", fr: "volume", pt: "volume",
        it: "volume", ru: "громкость", pl: "głośność" } },
    { page: "Top Bar", find: ["Power"], title: "Power button in the top bar", weight: 0.9, keys: {
        en: "power shutdown restart button", tr: "güç yeniden başlat düğme kapatma düğmesi",
        de: "ausschalten herunterfahren neustart", es: "apagar reiniciar energía",
        fr: "éteindre redémarrer alimentation", pt: "desligar reiniciar energia",
        it: "spegnere riavviare alimentazione", ru: "выключение перезагрузка питание",
        pl: "wyłącz uruchom ponownie zasilanie" } },
    { page: "Top Bar", find: ["MODULES"], title: "Top bar modules and order", keys: {
        en: "modules order arrange widgets items", tr: "modüller sıra sıralama öğe", de: "module reihenfolge",
        es: "módulos orden", fr: "modules ordre", pt: "módulos ordem", it: "moduli ordine",
        ru: "модули порядок", pl: "moduły kolejność" } },

    // ---- Notifications
    { page: "Notifications", find: ["Show notifications"], title: "Notifications on or off", keys: {
        en: "notifications notification popups do not disturb dnd silence",
        tr: "bildirim bildirimler rahatsız etme sessiz", de: "benachrichtigungen nicht stören",
        es: "notificaciones no molestar", fr: "notifications ne pas déranger", pt: "notificações não perturbe",
        it: "notifiche non disturbare", ru: "уведомления не беспокоить", pl: "powiadomienia nie przeszkadzać" } },
    { page: "Notifications", find: ["Pop-up time"], title: "How long notifications stay", keys: {
        en: "notification time duration timeout popup", tr: "bildirim süresi süre",
        de: "benachrichtigung dauer", es: "duración de notificaciones", fr: "durée des notifications",
        pt: "duração das notificações", it: "durata delle notifiche", ru: "длительность уведомлений",
        pl: "czas powiadomień" } },

    // ---- Login Screen
    { page: "Login Screen", find: ["MATCH THE SHELL"], title: "Login screen (SDDM)", keys: {
        en: "login screen sddm greeter sign in log in login background",
        tr: "giriş ekranı oturum açma karşılama arka plan", de: "anmeldebildschirm anmeldung hintergrund",
        es: "pantalla de inicio de sesión fondo", fr: "écran de connexion fond", pt: "tela de login fundo",
        it: "schermata di accesso sfondo", ru: "экран входа фон", pl: "ekran logowania tło" } },

    // ---- Keybinds
    { page: "Keybinds", find: ["KEYBINDS"], title: "Keyboard shortcuts", keys: {
        en: "keybinds keybindings shortcuts hotkeys keys bind",
        tr: "kısayol kısayollar klavye kısayolları tuş atama tuşlar", de: "tastenkürzel tastenkombinationen",
        es: "atajos de teclado combinaciones", fr: "raccourcis clavier", pt: "atalhos de teclado",
        it: "scorciatoie da tastiera", ru: "горячие клавиши сочетания клавиш", pl: "skróty klawiszowe" } },

    // ---- Default Apps
    { page: "Default Apps", find: ["DEFAULT APPS"], title: "Default apps (browser, terminal, files...)", keys: {
        en: "default apps browser terminal file manager text editor image viewer video player music player pdf email mail open with",
        tr: "varsayılan uygulama tarayıcı dosya yöneticisi metin düzenleyici resim görüntüleyici video oynatıcı müzik eposta",
        de: "standard apps browser dateimanager texteditor bildbetrachter videoplayer",
        es: "aplicaciones predeterminadas navegador gestor de archivos editor de texto",
        fr: "applications par défaut navigateur gestionnaire de fichiers éditeur",
        pt: "aplicativos padrão navegador gerenciador de arquivos editor",
        it: "app predefinite browser file manager editor",
        ru: "приложения по умолчанию браузер файловый менеджер редактор",
        pl: "domyślne aplikacje przeglądarka menedżer plików edytor" } },
    { page: "Default Apps", find: ["SHELL"], title: "Login shell", keys: {
        en: "shell login shell fish bash zsh", tr: "kabuk", de: "shell", es: "intérprete de comandos",
        fr: "interpréteur de commandes", pt: "interpretador de comandos", it: "shell", ru: "оболочка",
        pl: "powłoka" } },
    { page: "Default Apps", find: ["Also save to a folder"], title: "Screenshots", keys: {
        en: "screenshot screenshots screen capture snip print screen save folder",
        tr: "ekran görüntüsü ekran alıntısı ss kaydet klasör", de: "bildschirmfoto screenshot speichern ordner",
        es: "captura de pantalla guardar carpeta", fr: "capture d'écran enregistrer dossier",
        pt: "captura de tela salvar pasta", it: "cattura schermo salvare cartella",
        ru: "снимок экрана скриншот сохранить папка", pl: "zrzut ekranu zapisz folder" } },
    { page: "Default Apps", find: ["Clipboard history"], title: "Clipboard history", keys: {
        en: "clipboard history copy paste copied", tr: "pano geçmişi kopyala yapıştır kopyalanan",
        de: "zwischenablage verlauf kopieren einfügen", es: "portapapeles historial copiar pegar",
        fr: "presse-papiers historique copier coller", pt: "área de transferência histórico copiar colar",
        it: "appunti cronologia copia incolla", ru: "буфер обмена история копировать вставить",
        pl: "schowek historia kopiuj wklej" } },

    // ---- Input
    { page: "Input", find: ["CURSOR"], title: "Mouse cursor", keys: {
        en: "cursor mouse cursor pointer arrow cursor theme",
        tr: "imleç fare imleci mouse imleci işaretçi ok imleç teması", de: "mauszeiger zeiger cursor maus",
        es: "cursor puntero ratón", fr: "curseur pointeur souris", pt: "cursor ponteiro mouse",
        it: "cursore puntatore mouse", ru: "курсор указатель мыши", pl: "kursor wskaźnik myszy" } },
    { page: "Input", find: ["SIZE"], title: "Cursor size", keys: {
        en: "cursor size big small bigger smaller pointer size",
        tr: "imleç boyutu büyüklük büyük küçük büyüt küçült", de: "zeigergröße cursorgröße größer kleiner",
        es: "tamaño del cursor más grande", fr: "taille du curseur plus grand", pt: "tamanho do cursor maior",
        it: "dimensione del cursore più grande", ru: "размер курсора больше", pl: "rozmiar kursora większy" } },
    { page: "Input", find: ["SHAKE TO FIND"], title: "Shake to find the cursor", keys: {
        en: "shake to find shake cursor find mouse lost pointer", tr: "salla bul imleç bulma kaybolan",
        de: "schütteln zeiger finden", es: "agitar para encontrar cursor", fr: "secouer pour trouver curseur",
        pt: "agitar para encontrar cursor", it: "scuoti per trovare cursore", ru: "встряхнуть найти курсор",
        pl: "potrząśnij aby znaleźć kursor" } },
    { page: "Input", find: ["POINTER SPEED"], title: "Mouse speed", keys: {
        en: "pointer speed mouse speed sensitivity acceleration dpi touchpad", tr: "fare hızı hassasiyet ivme",
        de: "mausgeschwindigkeit zeigergeschwindigkeit empfindlichkeit beschleunigung",
        es: "velocidad del ratón sensibilidad aceleración", fr: "vitesse de la souris sensibilité accélération",
        pt: "velocidade do mouse sensibilidade aceleração", it: "velocità del mouse sensibilità accelerazione",
        ru: "скорость мыши чувствительность ускорение", pl: "szybkość myszy czułość przyspieszenie" } },
    { page: "Input", find: ["KEYBOARD LANGUAGE"], title: "Keyboard language / layout", keys: {
        en: "keyboard language layout keymap", tr: "klavye dili klavye düzeni türkçe",
        de: "tastatursprache tastaturlayout deutsch", es: "idioma del teclado distribución español",
        fr: "langue du clavier disposition azerty français", pt: "idioma do teclado layout português",
        it: "lingua della tastiera layout italiano", ru: "раскладка клавиатуры язык русский",
        pl: "język klawiatury układ polski" } },

    // ---- Sound
    { page: "Sound", find: ["OUTPUT DEVICE"], title: "Speakers / headphones", keys: {
        en: "output device speakers headphones headset audio output sound card",
        tr: "hoparlör kulaklık ses çıkışı ses kartı", de: "ausgabegerät lautsprecher kopfhörer",
        es: "dispositivo de salida altavoces auriculares", fr: "périphérique de sortie haut-parleurs casque",
        pt: "dispositivo de saída alto-falantes fones", it: "dispositivo di uscita altoparlanti cuffie",
        ru: "устройство вывода динамики наушники", pl: "urządzenie wyjściowe głośniki słuchawki" } },
    { page: "Sound", find: ["Output volume"], title: "Volume", keys: {
        en: "volume loudness sound level mute louder quieter",
        tr: "ses ses düzeyi ses seviyesi sessiz kıs azalt arttır yükselt", de: "lautstärke ton stumm lauter leiser",
        es: "volumen sonido silenciar", fr: "volume son muet", pt: "volume som mudo", it: "volume audio muto",
        ru: "громкость звук без звука", pl: "głośność dźwięk wycisz" } },
    { page: "Sound", find: ["APPS"], title: "Volume per app", keys: {
        en: "app volume per app mixer", tr: "uygulama ses seviyesi karıştırıcı", de: "app lautstärke mixer",
        es: "volumen por aplicación mezclador", fr: "volume par application mixeur",
        pt: "volume por aplicativo mixer", it: "volume per app mixer", ru: "громкость приложений микшер",
        pl: "głośność aplikacji mikser" } },

    // ---- Monitors
    { page: "Monitors", find: ["RESOLUTION"], title: "Screen resolution", keys: {
        en: "resolution screen size 1080p 1440p 4k monitor display", tr: "çözünürlük ekran boyutu monitör",
        de: "auflösung bildschirm monitor", es: "resolución pantalla monitor", fr: "résolution écran moniteur",
        pt: "resolução tela monitor", it: "risoluzione schermo monitor", ru: "разрешение экрана монитор",
        pl: "rozdzielczość ekran monitor" } },
    { page: "Monitors", find: ["REFRESH RATE"], title: "Refresh rate", keys: {
        en: "refresh rate hz 144hz 60hz fps", tr: "yenileme hızı", de: "bildwiederholrate",
        es: "frecuencia de actualización", fr: "taux de rafraîchissement", pt: "taxa de atualização",
        it: "frequenza di aggiornamento", ru: "частота обновления герц", pl: "częstotliwość odświeżania" } },
    { page: "Monitors", find: ["SCALE"], title: "Display scale", keys: {
        en: "scale scaling zoom hidpi dpi bigger text", tr: "ölçek ölçekleme büyütme", de: "skalierung zoom",
        es: "escala escalado", fr: "mise à l'échelle zoom", pt: "escala dimensionamento",
        it: "scala ridimensionamento", ru: "масштаб масштабирование", pl: "skalowanie skala" } },
    { page: "Monitors", find: ["LAYOUT"], title: "Monitor layout and position", keys: {
        en: "layout position arrange second monitor dual monitor multiple displays",
        tr: "düzen konum ikinci ekran çift monitör", de: "anordnung position zweiter monitor",
        es: "disposición posición segundo monitor", fr: "disposition position deuxième écran",
        pt: "disposição posição segundo monitor", it: "disposizione posizione secondo monitor",
        ru: "расположение второй монитор", pl: "układ pozycja drugi monitor" } },
    { page: "Monitors", find: ["BRIGHTNESS"], title: "Brightness", keys: {
        en: "brightness dim bright backlight", tr: "parlaklık", de: "helligkeit", es: "brillo",
        fr: "luminosité de l'écran", pt: "brilho da tela", it: "luminosità schermo", ru: "яркость экрана",
        pl: "jasność ekranu" } },
    { page: "Monitors", find: ["Night light"], title: "Night light", keys: {
        en: "night light blue light filter warm eye strain colour temperature night mode",
        tr: "gece ışığı mavi ışık filtre göz sıcak renk sıcaklığı", de: "nachtlicht blaulichtfilter warm",
        es: "luz nocturna filtro de luz azul", fr: "éclairage nocturne filtre lumière bleue",
        pt: "luz noturna filtro de luz azul", it: "luce notturna filtro luce blu",
        ru: "ночной свет фильтр синего света", pl: "światło nocne filtr niebieskiego światła" } },

    // ---- Network
    { page: "Network", find: ["WI-FI"], title: "Wi-Fi", keys: {
        en: "wifi wi-fi wireless network internet connect password ssid",
        tr: "kablosuz ağ internet bağlan şifre", de: "wlan drahtlos netzwerk internet verbinden",
        es: "red inalámbrica internet conectar", fr: "réseau sans fil internet connecter",
        pt: "rede sem fio internet conectar", it: "rete wireless internet connettere",
        ru: "вайфай беспроводная сеть интернет подключить", pl: "sieć bezprzewodowa internet połącz" } },
    { page: "Network", find: ["ETHERNET"], title: "Ethernet (cable)", keys: {
        en: "ethernet cable wired lan", tr: "kablo kablolu", de: "kabel kabelgebunden", es: "cable red cableada",
        fr: "câble filaire", pt: "cabo rede cabeada", it: "cavo rete cablata", ru: "кабель проводная сеть",
        pl: "kabel przewodowa" } },

    // ---- not a page: the wallpaper picker (SUPER + W)
    { run: "wallpaper", title: "Wallpaper (opens the picker, SUPER + W)", keys: {
        en: "wallpaper background desktop picture desktop background image",
        tr: "duvar kağıdı arka plan masaüstü resmi masaüstü arka planı", de: "hintergrundbild hintergrund",
        es: "fondo de pantalla fondo", fr: "fond d'écran", pt: "papel de parede plano de fundo", it: "sfondo",
        ru: "обои фон рабочего стола", pl: "tapeta tło pulpitu" } },

    // ---- not a page: the colour picker (SUPER + SHIFT + C); `wait`: after
    // Settings has closed, or it would be in the picture
    { run: "color-picker", wait: true, title: "Colour picker (copies a hex code, SUPER + SHIFT + C)", keys: {
        en: "color colour picker pick eyedropper hex code screen pixel copy",
        tr: "renk seçici seç pipet damlalık hex kodu ekran piksel kopyala",
        de: "farbe farbwähler pipette hex code bildschirm pixel kopieren",
        es: "color selector cuentagotas código hex pantalla píxel copiar",
        fr: "couleur sélecteur pipette code hex écran pixel copier",
        pt: "cor seletor conta-gotas código hex tela pixel copiar",
        it: "colore selettore contagocce codice hex schermo pixel copiare",
        ru: "цвет пипетка выбор цвета hex код экран пиксель копировать",
        pl: "kolor próbnik pipeta kod hex ekran piksel kopiuj" } },

    // ---- Bluetooth
    { page: "Bluetooth", find: ["BLUETOOTH"], title: "Bluetooth devices", keys: {
        en: "bluetooth pair pairing headphones earbuds controller devices", tr: "eşleştir eşleştirme kulaklık cihaz",
        de: "koppeln kopfhörer geräte", es: "emparejar auriculares dispositivos", fr: "appairer casque appareils",
        pt: "parear fones dispositivos", it: "associare cuffie dispositivi", ru: "сопряжение наушники устройства",
        pl: "parowanie słuchawki urządzenia" } }
]

// words that say nothing about which setting
var STOPS = {
    en: "the a an to of for in on off my how where change changing set setting settings option options turn " +
        "make want find show do is it i me can",
    tr: "ayar ayarı ayarlar ayarları ayarını ayarlarını ayarlama değiştir değiştirme değiştirmek değişim nasıl " +
        "nerede nereden neresi yap yapmak yapma için ile bir ve veya ya da de ben benim bana istiyorum istedim " +
        "olsun var yok aç kapa kapat kapatma kapatmak açtır açmak yapayım yapabilirim bul göster lazım gerek mi mu ne",
    de: "einstellung einstellungen ändern wie wo der die das den dem ein eine einen mein meine ich will möchte " +
        "machen zeigen finden für mit und oder zu auf ist",
    es: "configuración ajuste ajustes cambiar cómo dónde el la los las un una mi quiero hacer mostrar buscar " +
        "para con y o de del en es",
    fr: "paramètre paramètres réglage réglages changer modifier comment où le la les un une mon ma mes je veux " +
        "faire afficher trouver pour avec et de du des en est",
    pt: "configuração configurações ajuste alterar mudar como onde o a os as um uma meu minha eu quero fazer " +
        "mostrar encontrar para com e ou de do da em é",
    it: "impostazione impostazioni cambiare modificare come dove il lo la i gli le un una mio mia voglio fare " +
        "mostrare trovare per con e o di del della dello delle degli dei nel nella in è",
    ru: "настройка настройки изменить поменять как где мой моя я хочу сделать показать найти для с и или в на",
    pl: "ustawienie ustawienia zmienić zmiana jak gdzie mój moja chcę zrobić pokaż znajdź dla z i lub w na"
}

function fold(text) {
    return String(text)
        .replace(/İ/g, "i").replace(/I/g, "i")      // Turkish capitals first...
        .toLowerCase()
        .replace(/ı/g, "i")                           // ...then dotless and dotted are one letter
        .replace(/ß/g, "ss").replace(/ł/g, "l").replace(/ø/g, "o").replace(/æ/g, "ae").replace(/œ/g, "oe")
        .replace(/ё/g, "е")
        .normalize("NFD").replace(/[̀-ͯ]/g, "")     // é -> e, ç -> c, й -> и ...
        .replace(/[-']/g, "")
        .replace(/[^a-z0-9а-я]+/g, " ")
        .trim()
}

// one-letter words say nothing, but digits do ("workspace 3")
function words(text) {
    return fold(text).split(" ").filter(function(w) { return w.length > 1 || /[0-9]/.test(w) })
}

// (kept here too for KeybindsSearch.js and older callers)
function languages(env) {
    return Lang.languages(env)
}

function placeholder(langs) {
    return Lang.placeholder(langs)
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
    // a keyword with endings after it ("ses" + "ini"), or a word still being
    // typed; a short keyword only takes short endings, so "gun" (day) does
    // not swallow "guncelleme" (update)
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

// An index folded for one set of languages. `stops` is a table like STOPS
// (Keybinds brings its own: there "open" and "close" are what you mean).
function prepareList(index, langs, stops) {
    var stop = {}
    langs.forEach(function(l) { words((stops || STOPS)[l] || "").forEach(function(w) { stop[w] = true }) })
    var list = index.map(function(e, at) {
        var text = e.title
        langs.forEach(function(l) { text += " " + ((e.keys || {})[l] || "") })
        var seen = {}
        var keys = words(text).filter(function(w) { if (seen[w]) return false; seen[w] = true; return true })
        return { entry: e, at: at, keys: keys, page: words(e.page || ""), title: words(e.title) }
    })
    return { list: list, stop: stop }
}

// [{entry, score}], best first, from a prepareList() result
function rank(prepared, query, limit) {
    var q = words(query).filter(function(w) { return !prepared.stop[w] })
    if (q.length === 0)
        return []
    var scored = []
    for (var i = 0; i < prepared.list.length; i++) {
        var p = prepared.list[i]
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
            scored.push({ entry: p.entry, at: p.at,
                          score: total * (hits === q.length ? 1.25 : hits / q.length) * (p.entry.weight || 1) })
    }
    // equal scores keep the index order (Qt's sort is not stable)
    scored.sort(function(x, y) { return y.score - x.score || x.at - y.at })
    if (scored.length === 0)
        return []
    var top = scored[0].score
    return scored.filter(function(s) { return s.score >= top * 0.45 }).slice(0, limit || 8)
}

// Settings' own index (kept: the languages do not change while Settings is open)
var cache = { key: "", prepared: null }

function search(query, limit, langs) {
    langs = langs && langs.length ? langs : ["en"]
    if (cache.key !== langs.join(","))
        cache = { key: langs.join(","), prepared: prepareList(INDEX, langs) }
    return rank(cache.prepared, query, limit)
}
