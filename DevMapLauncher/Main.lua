scriptTitle = "Dev Map Launcher"
scriptAuthor = "Shmees"
scriptVersion = 0.3
scriptDescription = "Boot Call of Duty dev builds straight into a level, or any executable with startup options, using only the controller."
scriptIcon = "icon.png"
scriptPermissions = { "http", "filesystem" }

-- ---------------------------------------------------------------------------
-- HOW THIS WORKS
-- PC-side launchers send one text line to the Xbdm plugin (port 730):
--     magicboot title="<exe>" directory="<folder>" cmdline="+devmap <level>"
-- Aurora scripts have no socket API and no "launch with command line" call.
-- The only network call is Http.Get. This script asks Http.Get to open
-- http://<this console>:730/ with the magicboot line smuggled into the URL
-- after a line break, so Xbdm sees it as its own command line.
--
-- STATUS: booting executables and loading levels this way is confirmed on one
-- console (see README).
-- It depends on Aurora's HTTP client passing a line break in the URL through
-- unchanged. If yours does not, nothing happens and nothing is harmed; see
-- launcher.log next to this script.
-- ---------------------------------------------------------------------------

-- Aurora drive name -> Xbdm drive name (Xbdm calls the hard drive "HDD").
-- Only "Hdd1" is confirmed. Edit if your builds live elsewhere.
local XbdmDriveNames = {
    ["hdd1"] = "HDD",
    ["usb0"] = "USB0",
    ["usb1"] = "USB1",
}

-- Folders (under each drive root) that are searched for builds.
local BuildParents = { "Games", "games\\dev", "Debuilds" }

local KnownMaps = {
    zm_tomb = "Origins", zm_buried = "Buried", zm_prison = "Mob of the Dead",
    zm_highrise = "Die Rise", zm_nuked = "Nuketown Zombies", zm_transit = "TranZit",
    zm_transit_dr = "Diner",
    zm_prototype = "Nacht der Untoten (cut DLC5)", zm_asylum = "Verruckt (cut DLC5)",
    zm_sumpf = "Shi No Numa (cut DLC5)", zm_factory = "Der Riese (cut DLC5)",
    zm_theater = "Kino der Toten (cut DLC5)", zm_pentagon = "Five (cut DLC5)",
    zm_cosmodrome = "Ascension (cut DLC5)", zm_temple = "Shangri-La (cut DLC5)",
    zm_moon = "Moon (cut DLC5)", char_museum = "Character museum (hidden)",
    mp_firingrange = "Firing Range (test)", mp_shipment = "Shipment (MW2 test)",
    embassy = "Embassy (cut)", school = "School (cut)", wetwork = "Wet Work",
    pilotcobra_day = "Pilot Cobra day (cut)", pilotcobra_night = "Pilot Cobra night (cut)",
    cobra_down_a = "Cobra Down A (cut)", cobra_down_b = "Cobra Down B (cut)",
    interior_concept = "Interior concept (test)", javelin_test = "Javelin test",
    javelin_test_night = "Javelin test night", dog_ai = "Dog AI test",
    vehicledamage = "Vehicle damage test", mp_dusk = "Dusk (cut MP)", mp_hill = "Hill (cut MP)",
    mp_overgrown_night = "Overgrown night (cut MP)", mp_strike_night = "Strike night (cut MP)",
    firingrange_assaultrifle = "Firing range: assault rifles",
    firingrange_non_assault = "Firing range: other weapons",
    proto = "Proto (2007 test level)", descent = "Descent (2006 test level)",
}

-- Zone files that are not levels (same rules as the PC launcher).
local NotMapPrefixes = { "common", "code_post_gfx", "ui", "patch", "localized", "ez_", "en_", "fr_",
    "de_", "it_", "es_", "ja_", "ru_", "pl_", "frontend", "mptype", "iw4_credits", "default",
    "weapon", "dlc", "faction_", "core_", "seasonpass", "ffotd" }
local NotMapSuffixes = { "_load", "_patch", "_ignore", "_mp_patch", "_extract" }

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function startsWith(s, p) return string.sub(s, 1, string.len(p)) == p end
local function endsWith(s, p) return p == "" or string.sub(s, -string.len(p)) == p end

local function trimSlash(p)
    while endsWith(p, "\\") do p = string.sub(p, 1, -2) end
    return p
end

local function listFiles(dir)
    local out = {}
    local items = FileSystem.GetFiles(trimSlash(dir) .. "\\*")
    if items ~= nil then
        for _, f in pairs(items) do
            if f.Name ~= nil then table.insert(out, f.Name) end
        end
    end
    return out
end

local function listDirs(dir)
    local out = {}
    local items = FileSystem.GetDirectories(trimSlash(dir) .. "\\*")
    if items ~= nil then
        for _, d in pairs(items) do
            if d.Name ~= nil and d.Name ~= "." and d.Name ~= ".." then table.insert(out, d.Name) end
        end
    end
    return out
end

local function isExecutable(name)
    local n = string.lower(name)
    return endsWith(n, ".xex") or endsWith(n, ".exe")
end

local function mapNameFromFile(name)
    local n = string.lower(name)
    local base = string.match(n, "^([a-z0-9_]+)%.ffm?$")
    if base == nil then return nil end
    for _, p in ipairs(NotMapPrefixes) do
        if startsWith(base, p) then return nil end
    end
    for _, s in ipairs(NotMapSuffixes) do
        if endsWith(base, s) then return nil end
    end
    if string.find(base, "_load", 1, true) ~= nil then return nil end   -- loading-screen files
    return base
end

local function logLine(text)
    local path = Script.GetBasePath() .. "launcher.log"
    local old = FileSystem.ReadFile(path)
    if old == nil then old = "" end
    if string.len(old) > 20000 then old = string.sub(old, -10000) end
    FileSystem.WriteFile(path, old .. text .. "\r\n")
end

local function pick(title, list)
    local ret = Script.ShowPopupList(title, "Nothing found", list)
    if ret == nil or ret.Canceled then return nil end
    return ret.Selected.Key
end

-- ---------------------------------------------------------------------------
-- finding builds, executables and levels
-- ---------------------------------------------------------------------------

local function inspectFolder(folder)
    local exes, hasLevels = {}, false
    for _, f in ipairs(listFiles(folder)) do
        if isExecutable(f) then table.insert(exes, f) end
        local n = string.lower(f)
        if endsWith(n, ".ff") or endsWith(n, ".ffm") then hasLevels = true end
    end
    for _, d in ipairs(listDirs(folder)) do
        if string.lower(d) == "zone" then hasLevels = true end
    end
    table.sort(exes)
    return exes, hasLevels
end

local function findBuilds()
    local builds = {}
    local drives = FileSystem.GetDrives(false)
    if drives == nil then return builds end
    for _, drive in pairs(drives) do
        if drive.MountPoint ~= nil then
            local root = trimSlash(drive.MountPoint)
            for _, parent in ipairs(BuildParents) do
                local parentPath = root .. "\\" .. parent
                for _, d in ipairs(listDirs(parentPath)) do
                    local folder = parentPath .. "\\" .. d
                    local exes, hasLevels = inspectFolder(folder)
                    if hasLevels and #exes > 0 then
                        table.insert(builds, { folder = folder, name = d, exes = exes })
                    end
                end
            end
        end
    end
    return builds
end

local function findMaps(folder)
    local seen, maps = {}, {}
    local function add(dir)
        for _, f in ipairs(listFiles(dir)) do
            local m = mapNameFromFile(f)
            if m ~= nil and not seen[m] then
                seen[m] = true
                table.insert(maps, m)
            end
        end
    end
    add(folder)
    local zone = folder .. "\\zone"
    add(zone)
    for _, d in ipairs(listDirs(zone)) do add(zone .. "\\" .. d) end
    table.sort(maps)
    return maps
end

local function mapsForExe(maps, exe)
    -- multiplayer executables get mp_ and zm_ levels, the others get the rest
    local isMp = string.find(string.lower(exe), "mp", 1, true) ~= nil
    local out = {}
    for _, m in ipairs(maps) do
        local mpLevel = startsWith(m, "mp_") or startsWith(m, "zm_")
        if mpLevel == isMp then table.insert(out, m) end
    end
    if #out == 0 then return maps end
    return out
end

-- ---------------------------------------------------------------------------
-- launching
-- ---------------------------------------------------------------------------

local function toXbdmPath(path)
    local drive, rest = string.match(path, "^([^:]+):(.*)$")
    if drive == nil then return nil end
    local name = XbdmDriveNames[string.lower(drive)]
    if name == nil then return nil end
    return name .. ":" .. rest
end

local function hayzenActive()
    -- returns true / false, or nil when it can't tell
    local drives = FileSystem.GetDrives(false)
    if drives == nil then return nil end
    for _, drive in pairs(drives) do
        if drive.MountPoint ~= nil then
            local ini = FileSystem.ReadFile(trimSlash(drive.MountPoint) .. "\\launch.ini")
            if ini ~= nil and string.find(ini, "[Plugins]", 1, true) ~= nil then
                for line in string.gmatch(ini, "[^\r\n]+") do
                    if string.match(line, "^%s*plugin%d%s*=") and string.find(string.lower(line), "hayzen.xex", 1, true) then
                        return true
                    end
                end
                return false
            end
        end
    end
    return nil
end

local function launch(build, exe, cmdline)
    if string.find(cmdline, '"', 1, true) ~= nil then
        Script.ShowMessageBox("Dev Map Launcher", "Commands cannot contain double quotes.", "OK")
        return
    end
    local folder = toXbdmPath(build.folder)
    if folder == nil then
        Script.ShowMessageBox("Dev Map Launcher",
            "Don't know the Xbdm name for the drive in:\n" .. build.folder ..
            "\n\nAdd it to XbdmDriveNames at the top of Main.lua.", "OK")
        return
    end

    if endsWith(string.lower(exe), ".exe") and hayzenActive() == false then
        local r = Script.ShowMessageBox("Dev Map Launcher",
            "This is a devkit .exe and the Hayzen plugin is not in launch.ini.\n" ..
            "Devkit .exe files usually need Hayzen (or another loader) to run.\n\nTry anyway?",
            "Try anyway", "Cancel")
        if r == nil or r.Canceled or r.Button ~= 1 then return end
    end

    local command = 'magicboot title="' .. folder .. "\\" .. exe .. '" directory="' .. folder .. '"'
    if cmdline ~= "" then command = command .. ' cmdline="' .. cmdline .. '"' end

    local hosts = {}
    local ip = Aurora.GetIPAddress()
    if ip ~= nil and ip ~= "" and ip ~= "0.0.0.0" then table.insert(hosts, ip) end
    table.insert(hosts, "127.0.0.1")

    for _, host in ipairs(hosts) do
        logLine("try " .. host .. " : " .. command)
        -- first line reaches Xbdm as "GET /x" (ignored), second line is our command,
        -- the trailing line break keeps " HTTP/1.1" off the end of it.
        local url = "http://" .. host .. ":730/x\r\n" .. command .. "\r\n"
        local http = Http.Get(url)
        local result = "nil"
        if http ~= nil then
            result = "Success=" .. tostring(http.Success)
            if http.OutputData ~= nil then
                result = result .. " Output=" .. string.sub(tostring(http.OutputData), 1, 200)
            end
        end
        logLine("  result " .. result)
    end

    -- If the command was accepted the console is already rebooting into the build
    -- and this box never appears.
    Script.ShowMessageBox("Dev Map Launcher",
        "The Xbox did not boot the build.\n\n" ..
        "Check that Xbdm.xex is listed under [Plugins] in launch.ini. If it is, this\n" ..
        "Aurora version may not pass the command through. Details are in launcher.log\n" ..
        "next to the script.", "OK")
end

-- ---------------------------------------------------------------------------
-- favorites (one per line:  folder|exe|cmdline)
-- ---------------------------------------------------------------------------

local function favoritesPath() return Script.GetBasePath() .. "favorites.txt" end

local function loadFavorites()
    local favs = {}
    local data = FileSystem.ReadFile(favoritesPath())
    if data == nil then return favs end
    for line in string.gmatch(data, "[^\r\n]+") do
        local folder, exe, cmd = string.match(line, "^([^|]*)|([^|]*)|(.*)$")
        if folder ~= nil and folder ~= "" then
            table.insert(favs, { folder = folder, exe = exe, cmdline = cmd })
        end
    end
    return favs
end

local function saveFavorite(build, exe, cmdline)
    local data = FileSystem.ReadFile(favoritesPath())
    if data == nil then data = "" end
    local line = build.folder .. "|" .. exe .. "|" .. cmdline
    if string.find(data, line, 1, true) == nil then
        FileSystem.WriteFile(favoritesPath(), data .. line .. "\r\n")
    end
    Script.ShowNotification("Saved to favorites")
end

-- ---------------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------------

local function confirmAndLaunch(build, exe, cmdline)
    local shown = cmdline
    if shown == "" then shown = "(none - main menu)" end
    local r = Script.ShowMessageBox("Boot this?",
        build.folder .. "\\" .. exe .. "\n\nStartup commands: " .. shown,
        "Boot", "Save favorite", "Cancel")
    if r == nil or r.Canceled then return end
    if r.Button == 1 then
        launch(build, exe, cmdline)
    elseif r.Button == 2 then
        saveFavorite(build, exe, cmdline)
    end
end

local function levelMenu(build, exe)
    local allMaps = findMaps(build.folder)
    local showAll = false
    while true do
        local maps = allMaps
        if not showAll then maps = mapsForExe(allMaps, exe) end
        local list, actions = {}, {}
        local function add(label, action)
            table.insert(list, label)
            table.insert(actions, action)
        end
        add("[ Boot to the main menu ]", { kind = "boot" })
        add("[ Type startup commands ]", { kind = "custom" })
        if showAll then add("[ Show only levels for this exe ]", { kind = "toggle" })
        else add("[ Show every level ]", { kind = "toggle" }) end
        for _, m in ipairs(maps) do
            local label = m
            if KnownMaps[m] ~= nil then label = m .. "  -  " .. KnownMaps[m] end
            add(label, { kind = "map", map = m })
        end

        local key = pick(build.name .. " / " .. exe, list)
        if key == nil then return end
        local action = actions[key]
        if action == nil then return end

        if action.kind == "boot" then
            confirmAndLaunch(build, exe, "")
        elseif action.kind == "toggle" then
            showAll = not showAll
        elseif action.kind == "custom" then
            local kb = Script.ShowKeyboard("Startup commands", "Example: +set g_speed 400 +devmap mp_rust", "+devmap ", 0)
            if kb ~= nil and kb.Canceled == false and kb.Buffer ~= nil and kb.Buffer ~= "" then
                confirmAndLaunch(build, exe, kb.Buffer)
            end
        elseif action.kind == "map" then
            local go = true
            local mpLevel = startsWith(action.map, "mp_") or startsWith(action.map, "zm_")
            local mpExe = string.find(string.lower(exe), "mp", 1, true) ~= nil
            if mpLevel ~= mpExe then
                local r = Script.ShowMessageBox("Wrong executable?",
                    "Levels starting with mp_ or zm_ (multiplayer and Zombies) normally need the\n" ..
                    "multiplayer executable, and other levels need the single-player one.\n\n" ..
                    exe .. " does not look like the right one for " .. action.map .. ".",
                    "Boot anyway", "Cancel")
                go = (r ~= nil and r.Canceled ~= true and r.Button == 1)
            end
            if go then confirmAndLaunch(build, exe, "+devmap " .. action.map) end
        end
    end
end

local function exeMenu(build)
    while true do
        local list = {}
        for i, e in ipairs(build.exes) do
            local note = ""
            local n = string.lower(e)
            if endsWith(n, ".exe") then note = "   [devkit exe - needs Hayzen]" end
            if string.find(n, "mp", 1, true) ~= nil then note = note .. "   [multiplayer + zombies]" end
            list[i] = e .. note
        end
        local key = pick(build.name .. " - executable", list)
        if key == nil or build.exes[key] == nil then return end
        levelMenu(build, build.exes[key])
    end
end

local function favoritesMenu()
    local favs = loadFavorites()
    local list = {}
    for i, f in ipairs(favs) do
        list[i] = f.folder .. "\\" .. f.exe .. "   " .. f.cmdline
    end
    local key = pick("Favorites", list)
    if key == nil or favs[key] == nil then return end
    local f = favs[key]
    local name = string.match(f.folder, "([^\\]+)$")
    if name == nil then name = f.folder end
    launch({ folder = f.folder, name = name }, f.exe, f.cmdline)
end

local function optionsMenu(folder, exe)
    local name = string.match(folder, "([^\\]+)$")
    if name == nil then name = folder end
    local build = { folder = folder, name = name }
    while true do
        local key = pick(exe, { "[ Boot with no startup options ]", "[ Type startup options ]" })
        if key == nil then return end
        if key == 1 then
            confirmAndLaunch(build, exe, "")
        elseif key == 2 then
            local kb = Script.ShowKeyboard("Startup options", "Passed to the executable as its command line", "", 0)
            if kb ~= nil and kb.Canceled == false and kb.Buffer ~= nil and kb.Buffer ~= "" then
                confirmAndLaunch(build, exe, kb.Buffer)
            end
        end
    end
end

local function browseMenu()
    -- walk the drives with the controller and boot any .xex / .exe
    local path = nil
    while true do
        local list, actions = {}, {}
        if path == nil then
            local drives = FileSystem.GetDrives(false)
            if drives ~= nil then
                for _, drive in pairs(drives) do
                    if drive.MountPoint ~= nil then
                        table.insert(list, trimSlash(drive.MountPoint))
                        table.insert(actions, { kind = "dir", path = trimSlash(drive.MountPoint) })
                    end
                end
            end
        else
            table.insert(list, "[ .. up one folder ]")
            table.insert(actions, { kind = "up" })
            local dirs = listDirs(path)
            table.sort(dirs)
            for _, d in ipairs(dirs) do
                table.insert(list, "[" .. d .. "]")
                table.insert(actions, { kind = "dir", path = path .. "\\" .. d })
            end
            local files = listFiles(path)
            table.sort(files)
            for _, f in ipairs(files) do
                if isExecutable(f) then
                    table.insert(list, f)
                    table.insert(actions, { kind = "exe", exe = f })
                end
            end
        end

        local title = "Browse - pick a drive"
        if path ~= nil then title = path end
        local key = pick(title, list)
        if key == nil then return end
        local action = actions[key]
        if action == nil then return end

        if action.kind == "dir" then
            path = action.path
        elseif action.kind == "up" then
            local parent = string.match(path, "^(.*)\\[^\\]+$")
            path = parent          -- nil at a drive root, which shows the drive list again
        elseif action.kind == "exe" then
            optionsMenu(path, action.exe)
        end
    end
end

function main()
    Script.SetStatus("Looking for builds...")
    local builds = findBuilds()
    while true do
        local list, actions = {}, {}
        table.insert(list, "[ Favorites ]")
        table.insert(actions, { kind = "fav" })
        table.insert(list, "[ Browse for any executable ]")
        table.insert(actions, { kind = "browse" })
        for _, b in ipairs(builds) do
            table.insert(list, b.folder .. "   (" .. #b.exes .. " executables)")
            table.insert(actions, { kind = "build", build = b })
        end
        local key = pick("XBOX 360 DEVELOPER MAP LAUNCHER", list)
        if key == nil then return end
        local action = actions[key]
        if action == nil then return end
        if action.kind == "fav" then favoritesMenu()
        elseif action.kind == "browse" then browseMenu()
        else exeMenu(action.build) end
    end
end
