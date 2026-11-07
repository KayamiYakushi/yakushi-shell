-- Yakushi · window and layer rules

-- Blur behind the launcher card (SUPER + Space), but not the clear screen
-- around it. No Hyprland fade: the card animates itself, at the speed set in
-- Settings -> Appearance -> Launcher.
hl.layer_rule({ match = { namespace = "yakushi-launcher" }, blur = true, ignore_alpha = 0.15, no_anim = true })
-- The same for the wallpaper picker card (SUPER + W).
hl.layer_rule({ match = { namespace = "yakushi-wallpaper" }, blur = true, ignore_alpha = 0.15, no_anim = true })

-- Window opacity lives in hyprland.lua (decoration -> active/inactive_opacity),
-- not in a catch-all rule: in a rule, `fullscreen` can also act
-- as the "force fullscreen" effect.

-- Apps may ask to open maximized (kitty does when it was closed that way).
-- Ignore that so every new window takes its place in the tiling; SUPER + F
-- still makes a window fullscreen.
hl.window_rule({ name = "yakushi-tile-new-windows", match = { class = ".*" }, suppress_event = "maximize" })

-- Small tool windows open floating.
local floating = {
    class = { "pavucontrol", "nm-connection-editor", "blueman-manager" },
    title = { "Open File", "Save File" },
}

for field, names in pairs(floating) do
    for _, value in ipairs(names) do
        hl.window_rule({
            name = "yakushi-float-" .. value:lower():gsub("%s+", "-"),
            match = { [field] = "^(" .. value .. ")$" },
            float = true,
        })
    end
end
