-- Reiseführer (früher "Forever Dashboard") 0.12.1 (Beta)
-- Interner Ordner- und Datenname bleibt ForeverDashboard, damit alle Daten erhalten bleiben.
-- Liest Charakter-, Berufs- und Rezeptdaten ausschliesslich ueber die normale
-- Add-on-Schnittstelle und speichert sie in ForeverDashboardData (SavedVariables).
-- Es werden keine Spielhandlungen ausgefuehrt oder automatisiert.

local ADDON_TITEL = "|cffd4af37Reiseführer|r"
local frame = CreateFrame("Frame")
local K = {} -- Konstanten (spart Platz fuer lokale Namen)

local function Melden(text)
    print(ADDON_TITEL .. ": " .. text)
end

local function Zeitstempel()
    return time(), date("%Y-%m-%d %H:%M:%S")
end

local function Grunddaten()
    ForeverDashboardData = ForeverDashboardData or {}
    ForeverDashboardData.characters = ForeverDashboardData.characters or {}
    -- Ueberbleibsel einer frueheren Version entfernen
    ForeverDashboardData.professions = nil
    ForeverDashboardData.character = nil
    ForeverDashboardData.addonVersion = "0.12.1"
end

local function CharakterSchluessel()
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or not realm then
        return nil
    end
    return realm .. "-" .. name, name, realm
end

-- Voller Charaktername (in WoW Forever: Vor- und Zuname), fuer "Entdeckt von".
local function VollerName()
    local charakter = ForeverDashboardData and ForeverDashboardData.characters
        and ForeverDashboardData.characters[(CharakterSchluessel())]
    if charakter and charakter.surnameManual and charakter.surnameManual ~= "" then
        return (UnitName("player") or "?") .. " " .. charakter.surnameManual
    end
    if UnitNameUnmodified then
        local ok, vorname, zuname = pcall(UnitNameUnmodified, "player")
        if ok and vorname and zuname and zuname ~= "" then
            return vorname .. " " .. tostring(zuname)
        end
    end
    if GetUnitName then
        local ok, name = pcall(GetUnitName, "player")
        if ok and name and name ~= "" then
            return name
        end
    end
    return UnitName("player") or "?"
end

-- Texte fuer die Gilden-Synchronisation sicher verpacken (Trennzeichen maskieren)
local function Maskieren(wert)
    if wert == nil then
        return ""
    end
    -- auch Umlaute (Bytes ab 128) maskieren, damit beim Aufteilen nie ein Zeichen zerbricht
    return (string.gsub(tostring(wert), "[%%~^;=,`|\r\n\128-\255]", function(z)
        return string.format("%%%02X", string.byte(z))
    end))
end

local function Demaskieren(text)
    return (string.gsub(text or "", "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- Gemeinsam nutzbare Felder einer Quest als Text (auch als "Fingerabdruck" fuer Aenderungen)
local function QuestText(e)
    local prev = {}
    for id in pairs(e.prev or {}) do
        table.insert(prev, tostring(id))
    end
    table.sort(prev)
    local belohnungen = {}
    for _, r in ipairs(e.rewards or {}) do
        table.insert(belohnungen, table.concat({
            Maskieren(r.name), Maskieren(r.itemID), Maskieren(r.quality), r.choice and "1" or "0",
        }, "`"))
    end
    return table.concat({
        "i=" .. Maskieren(e.id),
        "n=" .. Maskieren(e.name),
        "z=" .. Maskieren(e.zone),
        "g=" .. Maskieren(e.giver),
        "l=" .. Maskieren(e.level),
        "x=" .. Maskieren(e.xp),
        "d=" .. Maskieren(e.discoveredBy),
        "f=" .. Maskieren(e.firstSeen),
        "p=" .. table.concat(prev, ","),
        "w=" .. table.concat(belohnungen, ","),
        -- Annahme-Ort (a/b) und Abgabe (e = Person, o = Gebiet, c/k = Ort)
        "a=" .. Maskieren(e.giverX),
        "b=" .. Maskieren(e.giverY),
        "e=" .. Maskieren(e.ender),
        "o=" .. Maskieren(e.enderZone),
        "c=" .. Maskieren(e.enderX),
        "k=" .. Maskieren(e.enderY),
        -- Fuer wen: h = Fraktion des Auftraggebers, s = gesehen von Fraktionen, j = nur fuer Klasse
        "h=" .. Maskieren(e.giverFaction),
        "s=" .. ((e.seenFactions and e.seenFactions.Alliance) and "A" or "") .. ((e.seenFactions and e.seenFactions.Horde) and "H" or ""),
        "j=" .. Maskieren(e.classOnly),
        "m=" .. Maskieren(e.minSeen),
    }, "^")
end

local function KatalogText(e)
    return table.concat({
        "n=" .. Maskieren(e.name),
        "b=" .. Maskieren(e.profession),
        "s=" .. Maskieren(e.requiredSkill),
        "t=" .. Maskieren(e.sourceType),
        "q=" .. Maskieren(e.sourceName),
        "z=" .. Maskieren(e.zone),
        "u=" .. Maskieren(e.subZone),
        "x=" .. Maskieren(e.x),
        "y=" .. Maskieren(e.y),
        "c=" .. Maskieren(e.cost),
        "d=" .. Maskieren(e.discoveredBy),
        "f=" .. Maskieren(e.firstSeen),
        "h=" .. Maskieren(e.npcFaction),
    }, "^")
end

local function BerufeEinlesen()
    local liste = {}
    local b1, b2, n1, n2, n3 = GetProfessions()
    for _, index in ipairs({ b1, b2, n1, n2, n3 }) do
        if index then
            local name, _, wert, maximum = GetProfessionInfo(index)
            if name then
                table.insert(liste, {
                    name = name,
                    skillLevel = wert or 0,
                    maxSkillLevel = maximum or 0,
                })
            end
        end
    end
    return liste
end

-- Fertigkeitswert eines Berufs ueber andere offizielle Wege suchen (nur lesend).
local function BerufswertSuchen(berufName)
    if C_TradeSkillUI then
        if C_TradeSkillUI.GetBaseProfessionInfo then
            local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
            if ok and type(info) == "table" and info.professionName == berufName and (info.skillLevel or 0) > 0 then
                return info.skillLevel, info.maxSkillLevel
            end
        end
        if C_TradeSkillUI.GetTradeSkillLine then
            local ok, _, name, wert, maximum = pcall(C_TradeSkillUI.GetTradeSkillLine)
            if ok and name == berufName and (wert or 0) > 0 then
                return wert, maximum
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, (GetNumSkillLines() or 0) do
            local name, istUeberschrift, _, wert, _, _, maximum = GetSkillLineInfo(i)
            if name == berufName and not istUeberschrift then
                return wert, maximum
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Rezeptkatalog: Angaben, die das Spiel beim Lehrer oder Haendler anzeigt.
-- Wird nur gelesen, wenn DU das Fenster selbst oeffnest. Es wird nichts gekauft
-- oder gelernt.
-- ---------------------------------------------------------------------------
-- Welcher Gegenstand wird mit einem Rezept hergestellt? (nur lesend)
local function RezeptErgebnis(rezeptID)
    if not rezeptID or not C_TradeSkillUI then
        return nil
    end
    if C_TradeSkillUI.GetRecipeOutputItemData then
        local ok, daten = pcall(C_TradeSkillUI.GetRecipeOutputItemData, rezeptID)
        if ok and type(daten) == "table" then
            if daten.itemID then
                return daten.itemID
            end
            if daten.hyperlink then
                local id = tonumber(string.match(daten.hyperlink, "item:(%d+)"))
                if id then
                    return id
                end
            end
        end
    end
    if C_TradeSkillUI.GetRecipeItemLink then
        local ok, link = pcall(C_TradeSkillUI.GetRecipeItemLink, rezeptID)
        if ok and type(link) == "string" then
            return tonumber(string.match(link, "item:(%d+)"))
        end
    end
    return nil
end

local function Katalog()
    Grunddaten()
    ForeverDashboardData.catalog = ForeverDashboardData.catalog or {}
    ForeverDashboardData.catalog.recipes = ForeverDashboardData.catalog.recipes or {}
    return ForeverDashboardData.catalog.recipes
end

local function Ort()
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local teilgebiet = (GetSubZoneText and GetSubZoneText()) or ""
    local x, y
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local karte = C_Map.GetBestMapForUnit("player")
        if karte then
            local position = C_Map.GetPlayerMapPosition(karte, "player")
            if position then
                local px, py = position:GetXY()
                if px and py then
                    x = math.floor(px * 1000 + 0.5) / 10
                    y = math.floor(py * 1000 + 0.5) / 10
                end
            end
        end
    end
    return zone, teilgebiet, x, y
end

-- Fraktion des gerade angesprochenen NPCs: "Alliance", "Horde", "Neutral" oder nil (unbekannt,
-- z. B. bei Gegenstaenden oder Objekten)
local function NpcFraktion()
    if not UnitExists or not UnitExists("npc") then
        return nil
    end
    local fraktion = UnitFactionGroup and UnitFactionGroup("npc")
    if fraktion == "Alliance" or fraktion == "Horde" then
        return fraktion
    end
    if UnitReaction and UnitReaction("npc", "player") then
        return "Neutral"
    end
    return nil
end

local function Eintragen(eintrag)
    local katalog = Katalog()
    eintrag.npcFaction = eintrag.npcFaction or NpcFraktion()
    local feld = eintrag.profession .. ":" .. eintrag.name .. ":" .. eintrag.sourceType
    -- gibt es dasselbe Rezept schon von einem ANDEREN Lehrer/Haendler? Dann eigener Eintrag
    if katalog[feld] and eintrag.sourceName and katalog[feld].sourceName and katalog[feld].sourceName ~= eintrag.sourceName then
        feld = feld .. ":" .. eintrag.sourceName
    end
    local alt = katalog[feld]
    eintrag.seenAt, eintrag.seenAtText = Zeitstempel()
    if alt then
        eintrag.discoveredBy = alt.discoveredBy
        eintrag.firstSeen = alt.firstSeen
        eintrag.rev = alt.rev
    end
    eintrag.discoveredBy = eintrag.discoveredBy or VollerName()
    eintrag.firstSeen = eintrag.firstSeen or eintrag.seenAt
    if not alt or KatalogText(alt) ~= KatalogText(eintrag) then
        eintrag.rev = time()
    end
    katalog[feld] = eintrag
end

local lehrerLaeuft = false
local lehrerLetzterLauf = 0
local lehrerNachlesen = false

local function Werte(...)
    local liste = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        liste[i] = v == nil and "nil" or tostring(v)
    end
    return table.concat(liste, " | ")
end

-- ---------------------------------------------------------------------------
-- Klassenfaehigkeiten: Klassenlehrer (was es gibt, ab welcher Stufe, Kosten) und
-- Zauberbuch (was der Charakter schon kann). Nur lesen.
-- Gespeichert: ForeverDashboardData.classCatalog[KLASSE]["Name|Rang"] (fuer alle
-- eigenen Charaktere dieser Klasse) und je Charakter spellbook / spellsKnown.
-- ---------------------------------------------------------------------------
local function KlassenKatalog(token)
    Grunddaten()
    ForeverDashboardData.classCatalog = ForeverDashboardData.classCatalog or {}
    if not token then
        return {}
    end
    ForeverDashboardData.classCatalog[token] = ForeverDashboardData.classCatalog[token] or {}
    return ForeverDashboardData.classCatalog[token]
end

local function RangZahl(text)
    if type(text) ~= "string" then
        return nil
    end
    local zahl = string.match(text, "^[Rr]ang%s*(%d+)") or string.match(text, "^[Rr]ank%s*(%d+)")
    return zahl and tonumber(zahl) or nil
end

local function SpielerCharakter()
    Grunddaten()
    local schluessel = CharakterSchluessel()
    if not schluessel then
        return nil
    end
    ForeverDashboardData.characters[schluessel] = ForeverDashboardData.characters[schluessel] or {}
    return ForeverDashboardData.characters[schluessel]
end

-- Zauberbuch lesen: je Name der hoechste Rang, Symbol, Zauber-Nummer und Reiter
local function ZauberbuchEinlesen()
    local c = SpielerCharakter()
    if not c then
        return 0
    end
    local buch, anzahl = {}, 0
    local function eintragen(name, unterText, id, icon, reiter, reiterNr)
        if not name or name == "" then
            return
        end
        local rang = RangZahl(unterText) or 0
        local alt = buch[name]
        if not alt or rang > (alt.rang or 0) then
            buch[name] = { rang = rang, id = id, icon = icon, tab = reiter, tabNr = reiterNr }
            if not alt then
                anzahl = anzahl + 1
            end
        end
    end
    local ok = pcall(function()
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
            local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
            for t = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
                local reiter = C_SpellBook.GetSpellBookSkillLineInfo(t)
                if reiter then
                    for slot = (reiter.itemIndexOffset or 0) + 1, (reiter.itemIndexOffset or 0) + (reiter.numSpellBookItems or 0) do
                        local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                        if info then
                            eintragen(info.name, info.subName, info.spellID or info.actionID, info.iconID, reiter.name, t)
                        end
                    end
                end
            end
        elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
            local art = BOOKTYPE_SPELL or "spell"
            for t = 1, GetNumSpellTabs() or 0 do
                local reiterName, _, offset, anzahlSlots = GetSpellTabInfo(t)
                for slot = (offset or 0) + 1, (offset or 0) + (anzahlSlots or 0) do
                    local name, unterText = GetSpellBookItemName(slot, art)
                    local id
                    if GetSpellBookItemInfo then
                        local _, nummer = GetSpellBookItemInfo(slot, art)
                        id = nummer
                    end
                    local icon = GetSpellBookItemTexture and GetSpellBookItemTexture(slot, art) or nil
                    eintragen(name, unterText, id, icon, reiterName, t)
                end
            end
        end
    end)
    if ok and anzahl > 0 then
        c.spellbook = buch
        c.spellbookTime = time()
    end
    return anzahl
end

-- Ein Angebot des Klassenlehrers merken
local function KlasseVomLehrer(daten)
    local token = select(2, UnitClass("player"))
    local katalog = KlassenKatalog(token)
    local schluessel = daten.name .. "|" .. (daten.rankNr or 0)
    local e = katalog[schluessel] or {}
    katalog[schluessel] = e
    local neu = e.name == nil
    e.name, e.rankNr, e.rank = daten.name, daten.rankNr, daten.rank
    e.level = daten.level or e.level
    e.cost = daten.cost or e.cost
    e.icon = daten.icon or e.icon
    e.category = daten.category or e.category
    e.desc = daten.desc or e.desc
    e.trainer, e.zone, e.x, e.y = daten.trainer, daten.zone, daten.x, daten.y
    e.trainers = e.trainers or {}
    if daten.trainer then
        e.trainers[daten.trainer] = { zone = daten.zone, x = daten.x, y = daten.y, cost = daten.cost, faction = NpcFraktion() }
    end
    if neu then
        e.firstSeen = time()
        e.discoveredBy = VollerName()
    end
    -- Volksfaehigkeiten: welches Volk hat diese Faehigkeit beim Lehrer gesehen?
    local volk = UnitRace and select(2, UnitRace("player"))
    if volk then
        e.races = e.races or {}
        e.races[volk] = true
    end
    e.rev = time()
    -- "used" = dieser Charakter kann es schon
    local c = SpielerCharakter()
    if c then
        c.spellsKnown = c.spellsKnown or {}
        if daten.art == "used" then
            c.spellsKnown[schluessel] = time()
        end
        c.spellsTrainer = c.spellsTrainer or {}
        c.spellsTrainer[schluessel] = daten.art
    end
    return neu
end

local function StufeAusText(zeilen)
    for _, text in ipairs(zeilen or {}) do
        local stufe = string.match(text, "Benötigt Stufe (%d+)") or string.match(text, "Requires Level (%d+)")
            or string.match(text, "^Stufe (%d+)") or string.match(text, "^Level (%d+)")
        if stufe then
            return tonumber(stufe)
        end
    end
    return nil
end

local function BeschreibungAusText(zeilen)
    local beste
    for i = 2, #(zeilen or {}) do
        local text = zeilen[i]
        if text and #text >= 25 and not string.find(text, "Benötigt") and not string.find(text, "Requires") then
            beste = text
        end
    end
    if beste and #beste > 300 then
        beste = string.sub(beste, 1, 297) .. "..."
    end
    return beste
end

-- Berufswert eines Lehrer-Angebots aus der Beschreibung (Tooltip) lesen, falls die
-- direkte Abfrage nichts liefert.
local lehrerTooltip
local function LehrerTooltipZeilen(index)
    local zeilen, rechts = {}, {}
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local ok, daten = pcall(C_TooltipInfo.GetTrainerService, index)
        if ok and daten and daten.lines then
            for _, zeile in ipairs(daten.lines) do
                if zeile.leftText then
                    table.insert(zeilen, zeile.leftText)
                    rechts[#zeilen] = zeile.rightText
                end
            end
            if #zeilen > 0 then
                return zeilen, rechts
            end
        end
    end
    if not lehrerTooltip then
        lehrerTooltip = CreateFrame("GameTooltip", "ForeverDashboardTrainerTooltip", nil, "GameTooltipTemplate")
    end
    if lehrerTooltip.SetTrainerService then
        lehrerTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
        lehrerTooltip:ClearLines()
        pcall(lehrerTooltip.SetTrainerService, lehrerTooltip, index)
        for i = 1, lehrerTooltip:NumLines() do
            local feld = _G["ForeverDashboardTrainerTooltipTextLeft" .. i]
            local text = feld and feld:GetText()
            if text then
                table.insert(zeilen, text)
                local feldR = _G["ForeverDashboardTrainerTooltipTextRight" .. i]
                rechts[#zeilen] = feldR and feldR:GetText() or nil
            end
        end
        lehrerTooltip:Hide()
    end
    return zeilen, rechts
end

local function BerufswertAusText(zeilen)
    for _, text in ipairs(zeilen) do
        local b, w = string.match(text, "Benötigt (.-) %((%d+)%)")
        if not b then
            b, w = string.match(text, "Requires (.-) %((%d+)%)")
        end
        if b then
            return b, tonumber(w)
        end
    end
    return nil
end

local function LehrerEinlesenIntern(anlass)
    Grunddaten()
    local diagnose = {
        anlass = anlass,
        zeit = date("%Y-%m-%d %H:%M:%S"),
        funktionen = Werte(
            "GetNumTrainerServices=" .. tostring(GetNumTrainerServices ~= nil),
            "GetTrainerServiceInfo=" .. tostring(GetTrainerServiceInfo ~= nil),
            "GetTrainerServiceSkillReq=" .. tostring(GetTrainerServiceSkillReq ~= nil),
            "SetTrainerServiceTypeFilter=" .. tostring(SetTrainerServiceTypeFilter ~= nil),
            "C_TooltipInfo.GetTrainerService=" .. tostring(C_TooltipInfo and C_TooltipInfo.GetTrainerService ~= nil)),
        eintraege = {},
    }
    ForeverDashboardData.diagnostics = ForeverDashboardData.diagnostics or {}
    ForeverDashboardData.diagnostics.trainer = diagnose

    if not GetNumTrainerServices or not GetTrainerServiceInfo then
        diagnose.ergebnis = "Lehrer-Schnittstelle fehlt"
        return 0, 0
    end

    -- Anzeige-Filter des Lehrerfensters kurz auf "alles zeigen" stellen und danach
    -- genau so zuruecksetzen, wie er war (reine Fenster-Einstellung).
    local filter = {}
    local filterBar = GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter
    if filterBar then
        for _, art in ipairs({ "available", "unavailable", "used" }) do
            local ok, wert = pcall(GetTrainerServiceTypeFilter, art)
            if ok then
                filter[art] = wert
                pcall(SetTrainerServiceTypeFilter, art, 1)
            end
        end
    end

    local lehrer = UnitName("npc") or UnitName("target") or "Unbekannter Lehrer"
    local zone, teilgebiet, x, y = Ort()
    local anzahl = 0
    local gesamt = GetNumTrainerServices() or 0
    diagnose.lehrer = lehrer
    diagnose.anzahlEintraege = gesamt

    local klassenAnzahl = 0
    local klassenFund = {}
    local berufsLehrer = false
    if IsTradeskillTrainer then
        local okT, wertT = pcall(IsTradeskillTrainer)
        berufsLehrer = okT and wertT and true or false
    end
    local kategorie
    local ARTEN = { header = true, available = true, unavailable = true, used = true }
    local ok, fehler = pcall(function()
        for i = 1, gesamt do
            local werte = { GetTrainerServiceInfo(i) }
            local name, rang, art = werte[1], werte[2], werte[3]
            -- je nach Spielversion steht die Art ("header", "available" ...) an 2. oder 3. Stelle
            if ARTEN[rang] then
                art = rang
                rang = nil
            end
            -- Rang und Symbol stehen je nach Version an unterschiedlicher Stelle
            local rangText, symbol
            for j = 2, 6 do
                local w = werte[j]
                if type(w) == "string" and RangZahl(w) then
                    rangText = w
                elseif type(w) == "number" and w > 1000 and not symbol then
                    symbol = w
                end
            end
            if art == "header" then
                kategorie = name
            end
            local beruf, wert
            if GetTrainerServiceSkillReq then
                beruf, wert = GetTrainerServiceSkillReq(i)
            end
            local quelle = "Abfrage"
            local zeilen, rechtsZeilen
            if name and art ~= "header" and (not beruf or beruf == "" or not wert) then
                zeilen, rechtsZeilen = LehrerTooltipZeilen(i)
                beruf, wert = BerufswertAusText(zeilen)
                quelle = "Beschreibung"
            end
            -- kein Berufswert: Klassen- oder Waffenfaehigkeit
            if name and art ~= "header" and (not beruf or beruf == "" or not wert) then
                if not rangText and rechtsZeilen then
                    for _, t in pairs(rechtsZeilen) do
                        if RangZahl(t) then
                            rangText = t
                        end
                    end
                end
                local stufe
                if GetTrainerServiceLevelReq then
                    local okS, s = pcall(GetTrainerServiceLevelReq, i)
                    if okS and type(s) == "number" and s > 0 then
                        stufe = s
                    end
                end
                stufe = stufe or StufeAusText(zeilen)
                if not symbol and GetTrainerServiceIcon then
                    local okI, s = pcall(GetTrainerServiceIcon, i)
                    symbol = okI and s or nil
                end
                local kostenK = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
                table.insert(klassenFund, {
                    name = name, rank = rangText, rankNr = RangZahl(rangText),
                    level = stufe, cost = kostenK, icon = symbol, category = kategorie,
                    desc = BeschreibungAusText(zeilen), art = art,
                    trainer = lehrer, zone = zone, x = x, y = y,
                })
                klassenAnzahl = klassenAnzahl + 1
                if i <= 15 then
                    table.insert(diagnose.eintraege, Werte(i, unpack(werte, 1, 5)) .. " || Klasse: Stufe "
                        .. tostring(stufe) .. ", " .. tostring(rangText) .. ", " .. tostring(kategorie))
                end
            end
            if i <= 15 then
                table.insert(diagnose.eintraege, Werte(i, name, rang, art)
                    .. " || Wert: " .. Werte(beruf, wert) .. " (" .. quelle .. ")")
            end
            if name and art ~= "header" and beruf and beruf ~= "" and wert then
                local kosten = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
                Eintragen({
                    name = name,
                    profession = beruf,
                    requiredSkill = wert,
                    sourceType = "Lehrer",
                    sourceName = lehrer,
                    zone = zone,
                    subZone = teilgebiet,
                    x = x,
                    y = y,
                    cost = kosten,
                })
                anzahl = anzahl + 1
            end
        end
    end)

    if filterBar then
        for art, wert in pairs(filter) do
            pcall(SetTrainerServiceTypeFilter, art, (wert == true or wert == 1) and 1 or 0)
        end
    end

    if not ok then
        diagnose.fehler = tostring(fehler)
        error(fehler)
    end
    -- Klassenfaehigkeiten nur uebernehmen, wenn es kein Berufslehrer war
    if anzahl == 0 and not berufsLehrer then
        for _, daten in ipairs(klassenFund) do
            KlasseVomLehrer(daten)
        end
        -- merken: dieses Volk hat den Klassenlehrer gesehen (fuer Volksfaehigkeiten)
        local volk = UnitRace and select(2, UnitRace("player"))
        local token = select(2, UnitClass("player"))
        if #klassenFund > 0 and volk and token then
            ForeverDashboardData.classCatalogVisits = ForeverDashboardData.classCatalogVisits or {}
            ForeverDashboardData.classCatalogVisits[token] = ForeverDashboardData.classCatalogVisits[token] or {}
            ForeverDashboardData.classCatalogVisits[token][volk] = time()
        end
    else
        klassenAnzahl = 0
    end
    diagnose.ergebnis = anzahl .. " Angebote mit Berufswert, " .. klassenAnzahl .. " Klassenfähigkeiten"
    if klassenAnzahl > 0 then
        ZauberbuchEinlesen()
    end
    return anzahl, gesamt, klassenAnzahl
end

local function LehrerEinlesen(anlass, laut)
    if lehrerLaeuft then
        return
    end
    lehrerLaeuft = true
    local ok, anzahl, gesamt, klassen = pcall(LehrerEinlesenIntern, anlass or "Fenster geöffnet")
    lehrerLaeuft = false
    lehrerLetzterLauf = time()
    if not ok then
        Melden("|cffff4444Fehler beim Lesen des Lehrers:|r " .. tostring(anzahl)
            .. " - bitte /reload und Claude Bescheid geben.")
        return
    end
    if klassen and klassen > 0 then
        Melden("|cff44ff44Klassenlehrer erfasst:|r " .. (UnitName("npc") or "Lehrer") .. " (" .. klassen
            .. " Fähigkeiten). Zu sehen im Reiter \"Fähigkeiten\".")
    elseif anzahl > 0 then
        Melden("|cff44ff44Lehrer erfasst:|r " .. (UnitName("npc") or "Lehrer") .. " (" .. anzahl
            .. " Angebote mit Berufswert). Mit /reload in die Datei schreiben.")
    elseif (gesamt or 0) > 0 then
        -- Liste hat Eintraege, aber nichts davon passte: das ist ein echtes Problem
        Melden("|cffffaa00Lehrerfenster erkannt (" .. gesamt .. " Einträge), aber nichts davon erkannt.|r "
            .. "Bitte /reload eingeben und Claude Bescheid geben.")
    end
    -- 0 Eintraege: Der Lehrer bietet diesem Charakter nichts an (z. B. ein Lehrer fuer einen
    -- Beruf, den er nicht hat) - das ist kein Fehler, also keine Meldung.
end

local scanTooltip
local function TooltipZeilen(index)
    local zeilen = {}
    if C_TooltipInfo and C_TooltipInfo.GetMerchantItem then
        local ok, daten = pcall(C_TooltipInfo.GetMerchantItem, index)
        if ok and daten and daten.lines then
            for _, zeile in ipairs(daten.lines) do
                if zeile.leftText then
                    table.insert(zeilen, zeile.leftText)
                end
            end
            return zeilen
        end
    end
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "ForeverDashboardScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip:ClearLines()
    scanTooltip:SetMerchantItem(index)
    for i = 1, scanTooltip:NumLines() do
        local feld = _G["ForeverDashboardScanTooltipTextLeft" .. i]
        local text = feld and feld:GetText()
        if text then
            table.insert(zeilen, text)
        end
    end
    scanTooltip:Hide()
    return zeilen
end

local function HaendlerEinlesen()
    if not GetMerchantNumItems then
        return
    end
    local haendler = UnitName("npc") or UnitName("target") or "Unbekannter Haendler"
    local zone, teilgebiet, x, y = Ort()
    local anzahl = 0

    for i = 1, (GetMerchantNumItems() or 0) do
        local gegenstand, preis
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then
                gegenstand, preis = info.name, info.price
            end
        elseif GetMerchantItemInfo then
            local name, _, p = GetMerchantItemInfo(i)
            gegenstand, preis = name, p
        end

        if gegenstand then
            local beruf, wert
            for _, text in ipairs(TooltipZeilen(i)) do
                local b, w = string.match(text, "^Benötigt (.-) %((%d+)%)")
                if not b then
                    b, w = string.match(text, "^Requires (.-) %((%d+)%)")
                end
                if b then
                    beruf, wert = b, tonumber(w)
                    break
                end
            end
            -- Nur Rezept-Gegenstaende ("Pläne: ...", "Rezept: ..." usw.)
            local rezeptName = string.match(gegenstand, "^[^:]+:%s*(.+)$")
            if beruf and wert and rezeptName then
                Eintragen({
                    name = rezeptName,
                    itemName = gegenstand,
                    profession = beruf,
                    requiredSkill = wert,
                    sourceType = "Händler",
                    sourceName = haendler,
                    zone = zone,
                    subZone = teilgebiet,
                    x = x,
                    y = y,
                    cost = preis,
                })
                anzahl = anzahl + 1
            end
        end
    end

    if anzahl > 0 then
        Melden("|cff44ff44Händler erfasst:|r " .. haendler .. " (" .. anzahl .. " Rezepte). "
            .. "Mit /reload in die Datei schreiben.")
    end
end

local function KatalogAnzeigen()
    local katalog = Katalog()
    local proBeruf = {}
    for _, eintrag in pairs(katalog) do
        proBeruf[eintrag.profession] = (proBeruf[eintrag.profession] or 0) + 1
    end
    print(ADDON_TITEL .. " - Rezeptkatalog")
    local leer = true
    for beruf, anzahl in pairs(proBeruf) do
        print("- " .. beruf .. ": " .. anzahl .. " Einträge")
        leer = false
    end
    if leer then
        print("Noch leer: Sprich einen Berufslehrer oder Händler an, dann wird erfasst.")
    end
end

-- Charakterdaten aktualisieren. Vorhandene Rezeptdaten bleiben IMMER erhalten.
local function DatenEinlesen(leise)
    Grunddaten()

    local schluessel, name, realm = CharakterSchluessel()
    if not schluessel then
        if not leise then
            Melden("|cffffaa00Charakter noch nicht bereit, bitte gleich nochmal /fd eingeben.|r")
        end
        return
    end

    local charakter = ForeverDashboardData.characters[schluessel] or {}
    ForeverDashboardData.characters[schluessel] = charakter

    local klasseName, klasseToken, klasseID = UnitClass("player")
    charakter.name = name
    charakter.realm = realm
    charakter.level = UnitLevel("player")
    -- Levelfortschritt und Fraktion (nur lesend)
    charakter.xp = UnitXP and UnitXP("player") or nil
    charakter.xpMax = UnitXPMax and UnitXPMax("player") or nil
    charakter.xpRested = GetXPExhaustion and GetXPExhaustion() or nil
    if UnitFactionGroup then
        local fraktion, fraktionName = UnitFactionGroup("player")
        charakter.faction = fraktion
        charakter.factionName = fraktionName
    end
    if UnitRace then
        local volk, volkToken = UnitRace("player")
        charakter.race = volk
        charakter.raceFile = volkToken
    end
    charakter.fullName = VollerName()
    charakter.className = klasseName
    charakter.classToken = klasseToken
    charakter.classID = klasseID

    -- Berufe nur ersetzen, wenn wirklich welche gefunden wurden
    local berufe = BerufeEinlesen()
    if #berufe > 0 or not charakter.professions then
        charakter.professions = berufe
    end

    charakter.recipeCollections = charakter.recipeCollections or {}
    charakter.lastUpdate, charakter.lastUpdateText = Zeitstempel()
    ForeverDashboardData.lastCharacter = schluessel

    if leise then
        return
    end

    print(ADDON_TITEL)
    print("Charakter: " .. name .. " (" .. (klasseName or "?") .. ", Level " .. charakter.level .. ")")
    print("Realm: " .. realm)
    if #charakter.professions == 0 then
        print("Keine Berufe gefunden.")
    else
        for _, beruf in ipairs(charakter.professions) do
            print("- " .. beruf.name .. ": " .. beruf.skillLevel .. "/" .. beruf.maxSkillLevel)
        end
    end

    local anzahl = 0
    for _, sammlung in pairs(charakter.recipeCollections) do
        anzahl = anzahl + 1
        print("  Rezepte " .. (sammlung.professionName or "?") .. ": "
            .. #(sammlung.known or {}) .. " bekannt, "
            .. #(sammlung.missing or {}) .. " fehlend (Stand "
            .. (sammlung.exportedAtText or "unbekannt") .. ")")
    end
    if anzahl == 0 then
        print("Noch keine Rezepte gespeichert: Berufefenster oeffnen, dann /fd rezepte.")
    end
    print("|cff44ff44Gespeichert.|r Wird beim Ausloggen oder /reload in die Datei geschrieben.")
end

-- Rezepte des gerade geoeffneten Berufefensters einlesen.
-- Ersetzt den gespeicherten Stand NUR, wenn tatsaechlich Rezepte gefunden wurden.
-- Nebenberufe, die GetProfessions() nicht immer liefert
K.NEBENBERUFE = { ["Kochkunst"] = true, ["Angeln"] = true, ["Erste Hilfe"] = true,
    ["Cooking"] = true, ["Fishing"] = true, ["First Aid"] = true }

-- Hat der GERADE GESPIELTE Charakter diesen Beruf wirklich gelernt? (eigene Fertigkeitenliste)
local function BerufGelernt(charakter, berufName)
    for _, b in ipairs(charakter and charakter.professions or {}) do
        if b.name == berufName then
            return true
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, (GetNumSkillLines() or 0) do
            local name, istUeberschrift = GetSkillLineInfo(i)
            if name == berufName and not istUeberschrift then
                return true
            end
        end
    end
    return false
end

-- Zeigt das Berufefenster gerade fremde Rezepte (verlinkter Beruf, Gilde, NPC)?
local function FremdesBerufefenster()
    for _, f in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        local fn = C_TradeSkillUI and C_TradeSkillUI[f]
        if fn then
            local ok, ja = pcall(fn)
            if ok and ja then
                return true
            end
        end
    end
    return false
end

local function RezepteEinlesen(leise)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then
        if not leise then
            Melden("|cffff4444Die Rezept-Schnittstelle fehlt in diesem Spiel.|r")
        end
        return false
    end

    local rezeptIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not rezeptIDs or #rezeptIDs == 0 then
        if not leise then
            Melden("|cffffaa00Keine Rezepte gefunden. Bitte zuerst das Berufefenster oeffnen. "
                .. "Dein bisher gespeicherter Stand bleibt erhalten.|r")
        end
        return false
    end

    DatenEinlesen(true)
    local schluessel = CharakterSchluessel()
    local charakter = schluessel and ForeverDashboardData.characters[schluessel]
    if not charakter then
        return false
    end

    local berufID, berufName = C_TradeSkillUI.GetTradeSkillLineForRecipe(rezeptIDs[1])
    if not berufID or not berufName then
        if not leise then
            Melden("|cffffaa00Der geoeffnete Beruf wurde nicht erkannt. Gespeicherter Stand bleibt erhalten.|r")
        end
        return false
    end

    -- Nur eigene Berufe speichern (kein verlinkter Beruf eines anderen Spielers)
    if FremdesBerufefenster() or not BerufGelernt(charakter, berufName) then
        if not leise then
            Melden("|cffffaa00Das ist nicht dein eigener Beruf - nichts gespeichert.|r")
        end
        return false
    end

    local berufWert, berufMaximum = 0, 0
    for _, beruf in ipairs(charakter.professions or {}) do
        if beruf.name == berufName then
            berufWert, berufMaximum = beruf.skillLevel, beruf.maxSkillLevel
            break
        end
    end

    -- Neben-Berufe (z. B. Kochkunst, Angeln) liefert GetProfessions() hier nicht:
    -- Wert dann aus dem geoeffneten Berufefenster oder der Fertigkeitenliste lesen.
    if (berufWert or 0) == 0 then
        local w, m = BerufswertSuchen(berufName)
        if w then
            berufWert, berufMaximum = w, m or 0
            charakter.secondarySkills = charakter.secondarySkills or {}
            charakter.secondarySkills[berufName] = { skillLevel = w, maxSkillLevel = m or 0 }
        end
    end

    local sammlung = {
        professionID = berufID,
        professionName = berufName,
        skillLevel = berufWert,
        maxSkillLevel = berufMaximum,
        known = {},
        missing = {},
    }

    for _, rezeptID in ipairs(rezeptIDs) do
        local info = C_TradeSkillUI.GetRecipeInfo(rezeptID)
        if info and info.name then
            local rezept = {
                id = rezeptID,
                name = info.name,
                learned = info.learned == true,
                disabled = info.disabled == true,
                craftable = info.craftable == true,
                difficulty = info.relativeDifficulty or -1,
                itemID = RezeptErgebnis(rezeptID),
            }
            -- Gruppe wie im Berufefenster (z. B. "Lederbrustharnische")
            if info.categoryID and C_TradeSkillUI.GetCategoryInfo then
                local okK, kat = pcall(C_TradeSkillUI.GetCategoryInfo, info.categoryID)
                if okK and type(kat) == "table" and kat.name then
                    rezept.kategorie = kat.name
                end
            end
            if rezept.learned then
                table.insert(sammlung.known, rezept)
            else
                table.insert(sammlung.missing, rezept)
            end
        end
    end

    local gesamt = #sammlung.known + #sammlung.missing
    local feld = tostring(berufID)
    local alt = charakter.recipeCollections[feld]

    -- Schutz: leere oder unvollstaendige Daten ueberschreiben keinen gueltigen Stand
    if gesamt == 0 or (alt and #sammlung.known == 0 and #(alt.known or {}) > 0) then
        if not leise then
            Melden("|cffffaa00Die Rezeptliste war noch nicht vollstaendig geladen. "
                .. "Dein letzter gueltiger Stand bleibt erhalten. Bitte gleich nochmal /fd rezepte.|r")
        end
        return false
    end

    sammlung.exportedAt, sammlung.exportedAtText = Zeitstempel()
    sammlung.recipeCount = gesamt

    -- Letzten gueltigen Stand als Sicherung aufheben
    if alt and ((#(alt.known or {}) + #(alt.missing or {})) > 0) then
        alt.backup = nil
        sammlung.backup = alt
    end

    charakter.recipeCollections[feld] = sammlung

    if not leise then
        print(ADDON_TITEL)
        print("|cff44ff44Export erfolgreich:|r " .. berufName .. " (" .. berufWert .. "/" .. berufMaximum .. ")")
        print("Bekannte Rezepte: " .. #sammlung.known .. "  |  Fehlende Rezepte: " .. #sammlung.missing)
        print("Wird beim Ausloggen oder /reload in die Datei geschrieben.")
    end
    return true
end

-- Wenn ein Berufefenster geoeffnet wird, Rezepte automatisch (nur lesend) mitspeichern.
local wartetAufRezepte = false
local function RezepteSpaeterEinlesen()
    if wartetAufRezepte then
        return
    end
    wartetAufRezepte = true
    C_Timer.After(1.5, function()
        wartetAufRezepte = false
        local ok = RezepteEinlesen(true)
        if ok then
            Melden("Rezepte automatisch gespeichert. Mit /fd siehst du den Stand.")
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Quests: Mitlernen beim Spielen (nur lesend).
-- Das Quest-WISSEN (Name, Gebiet, Auftraggeber, EP, Belohnungen, Verkettung) wird
-- accountweit gespeichert, damit alle Charaktere davon profitieren.
-- Der Quest-K.STATUS (aktiv, abgabebereit, abgeschlossen) wird je Charakter gespeichert.
-- ---------------------------------------------------------------------------
local function QuestWissen()
    Grunddaten()
    ForeverDashboardData.questKnowledge = ForeverDashboardData.questKnowledge or {}
    return ForeverDashboardData.questKnowledge
end

local function Charakter()
    Grunddaten()
    local schluessel = CharakterSchluessel()
    if not schluessel then
        return nil
    end
    ForeverDashboardData.characters[schluessel] = ForeverDashboardData.characters[schluessel] or {}
    return ForeverDashboardData.characters[schluessel], schluessel
end

local function WissenEintrag(questID)
    if not questID or questID == 0 then
        return nil
    end
    local wissen = QuestWissen()
    local e = wissen[questID]
    if not e then
        e = { id = questID, prev = {}, seenBy = {} }
        e.firstSeen, e.firstSeenText = Zeitstempel()
        e.discoveredBy = VollerName()
        wissen[questID] = e
    end
    local _, schluessel = Charakter()
    if schluessel then
        e.seenBy[schluessel] = true
    end
    return e
end

local function ItemIDAusLink(link)
    if not link then
        return nil
    end
    return tonumber(string.match(link, "item:(%d+)"))
end

local function QualitaetVonItem(itemID, qualitaet)
    if qualitaet and qualitaet >= 0 then
        return qualitaet
    end
    if itemID then
        if C_Item and C_Item.GetItemQualityByID then
            local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
            if ok and q then
                return q
            end
        end
        if GetItemInfo then
            local _, _, q = GetItemInfo(itemID)
            if q then
                return q
            end
        end
    end
    return nil
end

-- Belohnungen aus dem Gespraechsfenster (Quest wird angeboten oder abgegeben)
local function DialogBelohnungen()
    local liste = {}
    local function art(typ, anzahl, auswahl)
        for i = 1, (anzahl or 0) do
            local name, _, menge, qualitaet = GetQuestItemInfo(typ, i)
            local itemID = ItemIDAusLink(GetQuestItemLink and GetQuestItemLink(typ, i))
            if name then
                table.insert(liste, {
                    name = name, itemID = itemID, count = menge,
                    quality = QualitaetVonItem(itemID, qualitaet), choice = auswahl,
                })
            end
        end
    end
    if GetQuestItemInfo then
        art("reward", GetNumQuestRewards and GetNumQuestRewards() or 0, false)
        art("choice", GetNumQuestChoices and GetNumQuestChoices() or 0, true)
    end
    return liste
end

-- Belohnungen einer Quest im Questlog
local function LogBelohnungen(questID)
    local liste = {}
    if GetNumQuestLogRewards and GetQuestLogRewardInfo then
        local ok, anzahl = pcall(GetNumQuestLogRewards, questID)
        for i = 1, (ok and anzahl or 0) do
            local name, _, menge, qualitaet, _, itemID = GetQuestLogRewardInfo(i, questID)
            if name then
                table.insert(liste, { name = name, itemID = itemID, count = menge,
                    quality = QualitaetVonItem(itemID, qualitaet), choice = false })
            end
        end
    end
    if GetNumQuestLogChoices and GetQuestLogChoiceInfo then
        local ok, anzahl = pcall(GetNumQuestLogChoices, questID)
        for i = 1, (ok and anzahl or 0) do
            local name, _, menge, qualitaet, _, itemID = GetQuestLogChoiceInfo(i, questID)
            if name then
                table.insert(liste, { name = name, itemID = itemID, count = menge,
                    quality = QualitaetVonItem(itemID, qualitaet), choice = true })
            end
        end
    end
    return liste
end

-- Wissen ueber Gebiete (Dungeon/Schlachtzug), accountweit
local function GebietWissen()
    Grunddaten()
    ForeverDashboardData.zoneInfo = ForeverDashboardData.zoneInfo or {}
    return ForeverDashboardData.zoneInfo
end

local function AktuellesGebiet()
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local charakter = Charakter()
    if charakter and zone ~= "" then
        charakter.zone = zone
    end
    -- in einer Instanz? Dann ist das Gebiet ein Dungeon bzw. Schlachtzug
    if zone ~= "" and IsInInstance then
        local drin, art = IsInInstance()
        if drin and (art == "party" or art == "raid") then
            GebietWissen()[zone] = { typ = art == "raid" and "raid" or "dungeon" }
        end
    end
    return zone
end

-- Markierung einer Quest (z. B. "Dungeon", "Schlachtzug", "Elite")
local function QuestMarkierung(questID)
    local id, name
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local ok, info = pcall(C_QuestLog.GetQuestTagInfo, questID)
        if ok and type(info) == "table" then
            id, name = info.tagID, info.tagName
        end
    end
    if not id and GetQuestTagInfo then
        local ok, a, b = pcall(GetQuestTagInfo, questID)
        if ok then
            id, name = a, b
        end
    end
    return id, name
end

-- ---------------------------------------------------------------------------
-- Fraktion und Klasse: Fuer wen ist eine Quest / ein Lehrer / ein Haendler?
-- ---------------------------------------------------------------------------
-- Klassen-Kuerzel zu einem (deutschen) Klassennamen, z. B. "Paladin" -> "PALADIN"
local function KlasseAusName(name)
    if not name or name == "" then
        return nil
    end
    for _, tabelle in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for token, lokal in pairs(tabelle) do
            if lokal == name then
                return token
            end
        end
    end
    return nil
end

local function SpielerFraktion()
    return UnitFactionGroup and UnitFactionGroup("player") or nil
end

-- Bei jeder Begegnung mit einer Quest merken, welche Fraktion sie gesehen hat
local function QuestFraktionMerken(e, mitNpc)
    local geaendert = false
    local meine = SpielerFraktion()
    if meine then
        e.seenFactions = e.seenFactions or {}
        if not e.seenFactions[meine] then
            e.seenFactions[meine] = true
            geaendert = true
        end
    end
    if mitNpc then
        local npc = NpcFraktion()
        if npc and e.giverFaction ~= npc then
            e.giverFaction = npc
            geaendert = true
        end
    end
    return geaendert
end

-- Zuletzt abgegebene Quest: Bietet derselbe Auftraggeber kurz danach eine neue an,
-- wird das als Verkettung (Vorquest -> Folgequest) gelernt.
local letzteAbgabe = nil

local function AngeboteneQuest()
    local questID = GetQuestID and GetQuestID()
    local e = WissenEintrag(questID)
    if not e then
        return
    end
    local vorher = e.rev and QuestText(e) or ""
    local auftraggeber = UnitName("npc") or UnitName("target")
    e.name = GetTitleText and GetTitleText() or e.name
    e.giver = auftraggeber or e.giver
    e.zone = AktuellesGebiet()
    QuestFraktionMerken(e, true)
    local meineStufe = UnitLevel("player")
    if meineStufe and (not e.minSeen or meineStufe < e.minSeen) then
        e.minSeen = meineStufe
    end
    if auftraggeber then
        local _, teil, x, y = Ort()
        e.giverX, e.giverY, e.giverSub = x or e.giverX, y or e.giverY, (teil ~= "" and teil) or e.giverSub
    end
    local xp = GetRewardXP and GetRewardXP()
    if xp and xp > 0 then
        e.xp = xp
    end
    local belohnungen = DialogBelohnungen()
    if #belohnungen > 0 then
        e.rewards = belohnungen
    end
    if letzteAbgabe and letzteAbgabe.questID ~= questID
        and letzteAbgabe.npc == auftraggeber and (time() - letzteAbgabe.zeit) <= 120 then
        e.prev[letzteAbgabe.questID] = true
    end
    -- Probe: Wird mir die Quest angeboten, obwohl eine "Vorquest" laut Spiel nicht erledigt ist,
    -- dann war die Verknuepfung falsch -> entfernen und merken (kommt auch nicht ueber das Teilen zurueck)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        for vor in pairs(e.prev) do
            local ok, fertig = pcall(C_QuestLog.IsQuestFlaggedCompleted, vor)
            local gerade = letzteAbgabe and letzteAbgabe.questID == vor and (time() - letzteAbgabe.zeit) <= 120
            if ok and fertig == false and not gerade then
                e.prev[vor] = nil
                e.notPrev = e.notPrev or {}
                e.notPrev[vor] = true
            end
        end
    end
    if QuestText(e) ~= vorher then
        e.rev = time()
    end
    local charakter = Charakter()
    if charakter then
        charakter.questsOffered = charakter.questsOffered or {}
        charakter.questsOffered[questID] = time()
    end
end

-- Wo wird abgegeben? (beim Belohnungsfenster bzw. bei der Abgabe)
-- ---------------------------------------------------------------------------
-- Beute-Rezepte: Laesst ein Gegner (oder Behaelter) ein Rezept fallen, wird das im
-- gemeinsamen Rezeptkatalog vermerkt (Quelle "Beute"). Nur lesen. Guild ERP zeigt
-- diese Quellen automatisch mit an.
-- ---------------------------------------------------------------------------
local function BeuteQuelle(slot)
    local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
    local art = type(guid) == "string" and string.match(guid, "^(%a+)") or nil
    if art == "GameObject" then
        return "Behälter"
    elseif art == "Item" then
        return "Gegenstand (geöffnet)"
    end
    for _, einheit in ipairs({ "target", "mouseover" }) do
        if UnitGUID and guid and UnitGUID(einheit) == guid then
            return UnitName(einheit)
        end
    end
    if UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target") then
        return UnitName("target")
    end
    return "Unbekannter Gegner"
end

local function BeuteTooltipZeilen(slot, link)
    local zeilen = {}
    local daten
    if C_TooltipInfo then
        local ok, d = false, nil
        if C_TooltipInfo.GetLootItem then
            ok, d = pcall(C_TooltipInfo.GetLootItem, slot)
        end
        if (not ok or not d) and C_TooltipInfo.GetHyperlink and link then
            ok, d = pcall(C_TooltipInfo.GetHyperlink, link)
        end
        daten = ok and d or nil
    end
    for _, zeile in ipairs(daten and daten.lines or {}) do
        if zeile.leftText then
            table.insert(zeilen, zeile.leftText)
        end
    end
    return zeilen
end

local function BeuteEinlesen()
    if not GetNumLootItems or not GetLootSlotLink then
        return
    end
    local zone, teilgebiet, x, y = Ort()
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local klasse
        if link and GetItemInfoInstant then
            klasse = select(6, GetItemInfoInstant(link))
        end
        if link and klasse == 9 then -- 9 = Rezept
            local _, gegenstand = GetLootSlotInfo(slot)
            gegenstand = gegenstand or string.match(link, "%[(.-)%]")
            local beruf, wert
            for _, text in ipairs(BeuteTooltipZeilen(slot, link)) do
                local b, w = string.match(text, "^Benötigt (.-) %((%d+)%)")
                if not b then
                    b, w = string.match(text, "^Requires (.-) %((%d+)%)")
                end
                if b then
                    beruf, wert = b, tonumber(w)
                    break
                end
            end
            local rezeptName = gegenstand and string.match(gegenstand, "^[^:]+:%s*(.+)$")
            if beruf and wert and rezeptName then
                local quelle = BeuteQuelle(slot)
                Eintragen({
                    name = rezeptName, itemName = gegenstand, itemID = ItemIDAusLink(link),
                    profession = beruf, requiredSkill = wert,
                    sourceType = "Beute", sourceName = quelle,
                    zone = zone, subZone = teilgebiet, x = x, y = y,
                    npcFaction = "Neutral", -- Beute gibt es fuer beide Seiten
                })
                Melden("|cff44ff44Beute-Rezept erfasst:|r " .. gegenstand .. " von " .. quelle
                    .. (zone ~= "" and (" (" .. zone .. ")") or ""))
            end
        end
    end
end

-- Erledigte Quests laut Spiel (so macht es auch Questie): zuverlaessig, auch fuer Quests,
-- die vor der Installation des Add-ons erledigt wurden. Nur lesen.
local function ServerErledigtLesen()
    if not (C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs) then
        return
    end
    local c = Charakter()
    if not c then
        return
    end
    local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then
        return
    end
    c.questsCompleted = c.questsCompleted or {}
    local jetzt = time()
    for _, id in ipairs(ids) do
        if not c.questsCompleted[id] then
            c.questsCompleted[id] = jetzt
        end
    end
    c.questsServerAt = jetzt
end

-- Falls das Spiel Questreihen kennt (C_QuestLine), die Reihenfolge von dort uebernehmen
local function QuestreihenVomSpiel()
    if not (C_QuestLine and C_QuestLine.GetQuestLineInfo and C_QuestLine.GetQuestLineQuests) then
        return 0
    end
    local c = Charakter()
    local karte = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local wissen, gelernt = QuestWissen(), 0
    for id in pairs(c and c.questsActive or {}) do
        local ok, info = pcall(C_QuestLine.GetQuestLineInfo, id, karte)
        if ok and type(info) == "table" and info.questLineID then
            local ok2, ids = pcall(C_QuestLine.GetQuestLineQuests, info.questLineID)
            for i, qid in ipairs(ok2 and type(ids) == "table" and ids or {}) do
                local e = wissen[qid]
                if not e and C_QuestLog.GetTitleForQuestID then
                    local titel = C_QuestLog.GetTitleForQuestID(qid)
                    if titel and titel ~= "" then
                        e = WissenEintrag(qid)
                        e.name = titel
                        e.zone = e.zone or (wissen[id] and wissen[id].zone)
                        e.rev = time()
                    end
                end
                if e and i > 1 and not e.prev[ids[i - 1]] then
                    e.prev[ids[i - 1]] = true
                    e.rev = time()
                    gelernt = gelernt + 1
                end
            end
        end
    end
    return gelernt
end

local function AbgabeMerken(questID)
    local npc = UnitName("npc")
    if not questID or questID == 0 or not npc then
        return
    end
    local e = QuestWissen()[questID]
    if not e then
        return
    end
    local zone, teil, x, y = Ort()
    if QuestFraktionMerken(e, false) then
        e.rev = time()
    end
    if e.ender ~= npc or e.enderZone ~= zone or not e.enderX then
        e.ender, e.enderZone, e.enderX, e.enderY = npc, zone ~= "" and zone or e.enderZone, x or e.enderX, y or e.enderY
        e.enderSub = teil ~= "" and teil or e.enderSub
        e.rev = time()
    end
end

local function AbgegebeneQuest(questID, xp)
    if not questID then
        return
    end
    local e = WissenEintrag(questID)
    AbgabeMerken(questID)
    if e and xp and xp > 0 and e.xp ~= xp then
        e.xp = xp
        e.rev = time()
    end
    letzteAbgabe = { questID = questID, npc = UnitName("npc") or UnitName("target"), zeit = time() }
    local charakter = Charakter()
    if charakter then
        charakter.questsCompleted = charakter.questsCompleted or {}
        charakter.questsCompleted[questID] = time()
        if charakter.questsActive then
            charakter.questsActive[questID] = nil
        end
    end
end

-- Questlog lesen (aktive Quests mit Fortschritt)
local function QuestlogEinlesen()
    local charakter = Charakter()
    if not charakter then
        return
    end
    local aktiv = {}
    local ueberschrift = ""

    local anzahl = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        anzahl = C_QuestLog.GetNumQuestLogEntries() or 0
    elseif GetNumQuestLogEntries then
        anzahl = GetNumQuestLogEntries() or 0
    end

    for i = 1, anzahl do
        local titel, istUeberschrift, questID, stufe, fertig
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                titel, istUeberschrift, questID, stufe = info.title, info.isHeader, info.questID, info.level
                fertig = info.isComplete
            end
        elseif GetQuestLogTitle then
            local t, lvl, _, header, _, complete, _, id = GetQuestLogTitle(i)
            titel, istUeberschrift, questID, stufe, fertig = t, header, id, lvl, complete
        end

        if istUeberschrift then
            ueberschrift = titel or ""
        elseif questID and questID > 0 then
            local e = WissenEintrag(questID)
            local vorher = e.rev and QuestText(e) or ""
            e.name = titel or e.name
            e.level = stufe or e.level
            local markID, markName = QuestMarkierung(questID)
            if markID or markName then
                e.tagID, e.tagName = markID, markName
            end
            if ueberschrift ~= "" then
                e.zone = e.zone or ueberschrift
                e.logHeader = ueberschrift
                local klasse = KlasseAusName(ueberschrift)
                if klasse then
                    e.classOnly = klasse
                end
            end
            QuestFraktionMerken(e, false)
            -- Aeltere Spielversionen lesen Belohnungen nur fuer die im Questlog
            -- ausgewaehlte Quest: kurz auswaehlen und danach Auswahl wiederherstellen.
            local alteAuswahl
            local altesAPI = not (C_QuestLog and C_QuestLog.GetInfo) and SelectQuestLogEntry and GetQuestLogSelection
            if altesAPI then
                alteAuswahl = GetQuestLogSelection()
                SelectQuestLogEntry(i)
            end
            if GetQuestLogRewardXP then
                local ok, xp = pcall(GetQuestLogRewardXP, questID)
                if ok and xp and xp > 0 then
                    e.xp = xp
                end
            end
            local belohnungen = LogBelohnungen(questID)
            if #belohnungen > 0 then
                e.rewards = belohnungen
            end
            if altesAPI then
                SelectQuestLogEntry(alteAuswahl or 0)
            end
            if QuestText(e) ~= vorher then
                e.rev = time()
            end

            if C_QuestLog and C_QuestLog.IsComplete then
                local ok, c = pcall(C_QuestLog.IsComplete, questID)
                if ok then
                    fertig = c
                end
            end
            local ziele = {}
            if C_QuestLog and C_QuestLog.GetQuestObjectives then
                local ok, liste = pcall(C_QuestLog.GetQuestObjectives, questID)
                if ok and liste then
                    for _, ziel in ipairs(liste) do
                        if ziel.text then
                            table.insert(ziele, ziel.text)
                        end
                    end
                end
            end
            aktiv[questID] = {
                readyToTurnIn = (fertig == true or fertig == 1),
                progress = table.concat(ziele, "; "),
            }
        end
    end
    charakter.questsActive = aktiv
    charakter.questsUpdate, charakter.questsUpdateText = Zeitstempel()
    AktuellesGebiet()
end

local logWartet = false
local function QuestlogSpaeterEinlesen()
    if logWartet then
        return
    end
    logWartet = true
    C_Timer.After(2, function()
        logWartet = false
        QuestlogEinlesen()
    end)
end

local function QuestStandAnzeigen()
    QuestlogEinlesen()
    local charakter = Charakter()
    if not charakter then
        return
    end
    local wissen = QuestWissen()
    local bekannt, aktiv, bereit = 0, 0, 0
    for _ in pairs(wissen) do
        bekannt = bekannt + 1
    end
    for _, q in pairs(charakter.questsActive or {}) do
        aktiv = aktiv + 1
        if q.readyToTurnIn then
            bereit = bereit + 1
        end
    end
    print(ADDON_TITEL .. " - Quests")
    print("Gebiet: " .. (charakter.zone or "?"))
    print("Aktive Quests: " .. aktiv .. " (davon abgabebereit: " .. bereit .. ")")
    print("Gelerntes Quest-Wissen (alle Charaktere): " .. bekannt .. " Quests")
    print("Mit /reload in die Datei schreiben.")
end

-- ---------------------------------------------------------------------------
-- Synchronisation (Version 2, fuer Gruppen bis etwa 40 Spieler ausgelegt):
-- tauscht Quest-Wissen und Rezeptkatalog mit anderen Nutzern dieses Add-ons in
-- Gilde und Gruppe. Nur offizielle Add-on-Nachrichten, gebremst (hoechstens
-- eine Nachricht je K.SYNC_TAKT Sekunden), Pause im Kampf. Abschaltbar: /fd sync aus
--
-- Ablauf:
--  * Beim Einloggen: "Hallo" mit dem Zeitpunkt der letzten vollstaendigen
--    Synchronisation; dazu die eigenen Neuheiten seit diesem Zeitpunkt.
--  * Auf ein "Hallo" antwortet nur EIN Mitspieler (zufaellige Wartezeit; wer
--    eine fremde Antwort sieht, schweigt) mit seiner Uebersicht.
--  * Fehlendes wird gezielt beim Absender der Uebersicht angefragt; der sendet
--    jeden Eintrag nur einmal, alle Mitlesenden uebernehmen ihn ebenfalls.
--  * Danach werden nur noch Neuheiten verteilt (jede Minute, falls vorhanden).
-- ---------------------------------------------------------------------------
K.SYNC_PREFIX = "FDash2"
K.SYNC_TAKT = 1.2            -- Sekunden zwischen zwei Nachrichten (Blizzard erlaubt ~1 pro Sekunde)
K.SYNC_MAX_NACHRICHT = 240   -- Zeichen je Nachricht (Grenze des Spiels: 255)
K.SYNC_SICHERHEIT = 3600     -- eine Stunde Puffer fuer abweichende Uhren
K.SYNC_MAX_WARTESCHLANGE = 600

local syncWarteschlange = {}
local syncGesendet = {}          -- zuletzt gesendete Eintraege (gegen Doppelsendungen)
local syncTeile = {}             -- eingehende, in Teilen gesendete Daten
local syncAngefragt = {}         -- schon angefragte Eintraege (gegen Doppelanfragen)
local syncAntwortGeplant = {}    -- geplante Antworten auf "Hallo", je Absender
local syncNachrichtNr = 0
local syncEmpfangen, syncNeu, syncPause = 0, 0, 0
local syncLetzteNeuheiten = 0
local syncHalloZeit = {}         -- je Kanalart: wann "Hallo" gesagt wurde
local syncAntwortErhalten = {}   -- je Kanalart: wann zuletzt eine Uebersicht fuer uns kam
local syncPartner = {}           -- wer in dieser Sitzung geantwortet hat

-- Ueber welche Kanaele wird geteilt? Gilde und/oder aktuelle Gruppe
local function SyncKanaele()
    local liste = {}
    if IsInGuild and IsInGuild() then
        table.insert(liste, "GUILD")
    end
    if IsInRaid and IsInRaid() then
        table.insert(liste, "RAID")
    elseif IsInGroup and IsInGroup() then
        local heim = LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)
        if heim == false and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            table.insert(liste, "INSTANCE_CHAT")
        else
            table.insert(liste, "PARTY")
        end
    end
    return liste
end

local function KanalArt(kanal)
    return kanal == "GUILD" and "GUILD" or "GROUP"
end

local function KanalGueltig(kanal)
    for _, k in ipairs(SyncKanaele()) do
        if k == kanal then
            return true
        end
    end
    return false
end

local function SyncAn()
    Grunddaten()
    ForeverDashboardData.settings = ForeverDashboardData.settings or {}
    return ForeverDashboardData.settings.sync ~= false and #SyncKanaele() > 0
end

-- Nachricht einreihen. text darf auch eine Funktion sein, die erst beim Senden den
-- Text erzeugt (oder nil, wenn sich die Nachricht inzwischen erledigt hat).
-- Ohne Kanal: an alle aktiven Kanaele.
local function SyncSenden(text, kanal, verzoegerung)
    local nichtVor = time() + (verzoegerung or 0)
    local function rein(k)
        if #syncWarteschlange < K.SYNC_MAX_WARTESCHLANGE then
            table.insert(syncWarteschlange, { text = text, kanal = k, nichtVor = nichtVor })
        end
    end
    if kanal then
        rein(kanal)
    else
        for _, k in ipairs(SyncKanaele()) do
            rein(k)
        end
    end
end

local function SyncTakt()
    if #syncWarteschlange == 0 or not SyncAn() or time() < syncPause then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local jetzt = time()
    for i, eintrag in ipairs(syncWarteschlange) do
        if eintrag.nichtVor <= jetzt then
            table.remove(syncWarteschlange, i)
            if not KanalGueltig(eintrag.kanal) then
                return -- z. B. Gruppe inzwischen verlassen
            end
            local text = eintrag.text
            if type(text) == "function" then
                text = text()
                if not text then
                    return -- hat sich erledigt
                end
            end
            local ergebnis
            if C_ChatInfo and C_ChatInfo.SendAddonMessage then
                ergebnis = C_ChatInfo.SendAddonMessage(K.SYNC_PREFIX, text, eintrag.kanal)
            elseif SendAddonMessage then
                ergebnis = SendAddonMessage(K.SYNC_PREFIX, text, eintrag.kanal)
            end
            -- vom Spiel gebremst? Dann Nachricht zurueckstellen und kurz pausieren
            if ergebnis == false or (type(ergebnis) == "number" and ergebnis ~= 0) then
                eintrag.text = text
                table.insert(syncWarteschlange, 1, eintrag)
                syncPause = time() + 10
            end
            return
        end
    end
end

local function Kurzschluessel(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + string.byte(text, i)) % 4294967296
    end
    return string.format("%x", h)
end

local function KatalogNachKurzschluessel()
    local liste = {}
    for feld, e in pairs(Katalog()) do
        liste[Kurzschluessel(feld)] = feld
    end
    return liste
end


-- Uebersicht als Nachrichten einreihen: "I~ziel~Q~id:rev,id:rev" bzw. "I~ziel~K~kurz:rev,..."
-- ziel = Name des Hallo-Absenders oder "*" (an alle)
local function IndexSenden(seit, kanal, ziel)
    if not SyncAn() then
        return 0
    end
    ziel = ziel or "*"
    local anzahl = 0
    local function teilen(art, eintraege)
        local kopf = "I~" .. ziel .. "~" .. art .. "~"
        local stueck, laenge = {}, #kopf
        for _, text in ipairs(eintraege) do
            if laenge + #text + 1 > K.SYNC_MAX_NACHRICHT and #stueck > 0 then
                SyncSenden(kopf .. table.concat(stueck, ","), kanal)
                anzahl = anzahl + 1
                stueck, laenge = {}, #kopf
            end
            table.insert(stueck, text)
            laenge = laenge + #text + 1
        end
        if #stueck > 0 then
            SyncSenden(kopf .. table.concat(stueck, ","), kanal)
            anzahl = anzahl + 1
        end
    end
    local quests = {}
    for id, e in pairs(QuestWissen()) do
        if e.rev and e.name and e.rev >= (seit or 0) then
            table.insert(quests, tostring(id) .. ":" .. tostring(math.floor(e.rev)))
        end
    end
    teilen("Q", quests)
    local katalog = {}
    for feld, e in pairs(Katalog()) do
        if e.rev and e.rev >= (seit or 0) then
            table.insert(katalog, Kurzschluessel(feld) .. ":" .. tostring(math.floor(e.rev)))
        end
    end
    teilen("K", katalog)
    return anzahl
end

-- Einen Eintrag (in Teilen) an alle senden: "D~Q~nr~teil~gesamt~text"
local function DatenSenden(art, schluessel, kanal)
    local text
    if art == "Q" then
        local e = QuestWissen()[tonumber(schluessel)]
        if not e or not e.name then
            return
        end
        text = QuestText(e) .. "^r=" .. tostring(math.floor(e.rev or 0))
    else
        local feld = KatalogNachKurzschluessel()[schluessel]
        local e = feld and Katalog()[feld]
        if not e then
            return
        end
        text = KatalogText(e) .. "^r=" .. tostring(math.floor(e.rev or 0))
    end
    -- jeden Eintrag hoechstens alle 5 Minuten je Kanal senden, egal wie oft er angefragt wird
    local merker = art .. schluessel .. "@" .. tostring(kanal)
    if syncGesendet[merker] and time() - syncGesendet[merker] < 300 then
        return
    end
    syncGesendet[merker] = time()
    syncNachrichtNr = (syncNachrichtNr + 1) % 1000
    local laenge = K.SYNC_MAX_NACHRICHT - 20
    local gesamt = math.ceil(#text / laenge)
    for teil = 1, gesamt do
        SyncSenden("D~" .. art .. "~" .. syncNachrichtNr .. "~" .. teil .. "~" .. gesamt .. "~"
            .. string.sub(text, (teil - 1) * laenge + 1, teil * laenge), kanal)
    end
end

-- aktueller Stand eines Eintrags bei mir (nil = unbekannt)
local function MeinStand(art, schluessel, katalogKurz)
    if art == "Q" then
        local e = QuestWissen()[tonumber(schluessel)]
        return e and e.name and e.rev or nil
    end
    local feld = (katalogKurz or KatalogNachKurzschluessel())[schluessel]
    return feld and Katalog()[feld] and Katalog()[feld].rev or nil
end

local function Felder(text)
    local f = {}
    for teil in string.gmatch(text, "[^%^]+") do
        local k, v = string.match(teil, "^(%a)=(.*)$")
        if k then
            f[k] = v
        end
    end
    return f
end

local function Kuerzen(text, max)
    if text and #text > max then
        return string.sub(text, 1, max)
    end
    return text
end

local function Wert(f, k, max)
    local v = f[k]
    if v == nil or v == "" then
        return nil
    end
    return Kuerzen(Demaskieren(v), max or 120)
end

local function Zahl(f, k)
    local v = Wert(f, k, 20)
    return v and tonumber(v) or nil
end

-- Eingehende Quest mit dem eigenen Wissen zusammenfuehren (nichts geht verloren)
local function QuestZusammenfuehren(f)
    local id = Zahl(f, "i")
    local name = Wert(f, "n")
    if not id or id <= 0 or not name then
        return
    end
    local wissen = QuestWissen()
    local e = wissen[id]
    local neu = not e
    if neu then
        e = { id = id, prev = {}, seenBy = {} }
        wissen[id] = e
    end
    local vorher = neu and "" or QuestText(e)
    e.name = e.name or name
    e.zone = e.zone or Wert(f, "z")
    e.giver = e.giver or Wert(f, "g")
    e.level = e.level or Zahl(f, "l")
    e.xp = e.xp or Zahl(f, "x")
    if not e.giverX and Zahl(f, "a") then
        e.giverX, e.giverY = Zahl(f, "a"), Zahl(f, "b")
    end
    local ihreFraktion = Wert(f, "h", 10)
    if not e.giverFaction and (ihreFraktion == "Alliance" or ihreFraktion == "Horde" or ihreFraktion == "Neutral") then
        e.giverFaction = ihreFraktion
    end
    local gesehen = f.s or ""
    -- Gruppen und Gilden gibt es nur innerhalb einer Fraktion: Wer mir etwas schickt,
    -- gehoert zu meiner Fraktion und hat die Quest gesehen.
    local meine = SpielerFraktion()
    if gesehen == "" and meine then
        gesehen = meine == "Alliance" and "A" or (meine == "Horde" and "H" or "")
    end
    if gesehen:find("A") or gesehen:find("H") then
        e.seenFactions = e.seenFactions or {}
        if gesehen:find("A") then e.seenFactions.Alliance = true end
        if gesehen:find("H") then e.seenFactions.Horde = true end
    end
    e.classOnly = e.classOnly or Wert(f, "j", 20)
    local ihrMin = Zahl(f, "m")
    if ihrMin and (not e.minSeen or ihrMin < e.minSeen) then
        e.minSeen = ihrMin
    end
    if not e.ender and Wert(f, "e", 60) then
        e.ender, e.enderZone = Wert(f, "e", 60), Wert(f, "o")
        e.enderX, e.enderY = Zahl(f, "c"), Zahl(f, "k")
    end
    local ihrErstesMal = Zahl(f, "f")
    local ihrEntdecker = Wert(f, "d", 60)
    if ihrEntdecker and ihrErstesMal and (not e.firstSeen or ihrErstesMal < e.firstSeen) then
        e.firstSeen = ihrErstesMal
        e.discoveredBy = ihrEntdecker
    end
    e.discoveredBy = e.discoveredBy or ihrEntdecker
    for vorID in string.gmatch(f.p or "", "%d+") do
        local n = tonumber(vorID)
        if not (e.notPrev and e.notPrev[n]) then
            e.prev[n] = true
        end
    end
    if (not e.rewards or #e.rewards == 0) and f.w and f.w ~= "" then
        local liste = {}
        for r in string.gmatch(f.w, "[^,]+") do
            local n, item, q, wahl = string.match(r, "^([^`]*)`([^`]*)`([^`]*)`([01])$")
            if n and n ~= "" and #liste < 12 then
                table.insert(liste, {
                    name = Kuerzen(Demaskieren(n), 120), itemID = tonumber(Demaskieren(item)),
                    quality = tonumber(Demaskieren(q)), choice = wahl == "1",
                })
            end
        end
        e.rewards = liste
    end
    local ihrStand = Zahl(f, "r") or 0
    -- Habe ich mehr als der Absender (z. B. EP, Belohnungen, Vorquests)? Dann gilt mein
    -- zusammengefuehrter Eintrag als neu und wird bei der naechsten Runde weitergegeben.
    local ihreVor = 0
    for _ in string.gmatch(f.p or "", "%d+") do
        ihreVor = ihreVor + 1
    end
    local meineVor = 0
    for _ in pairs(e.prev or {}) do
        meineVor = meineVor + 1
    end
    local ichHabeMehr = (e.xp and not Zahl(f, "x")) or (e.giver and not f.g) or (e.zone and not f.z)
        or (e.level and not Zahl(f, "l")) or ((e.rewards and #e.rewards > 0) and (not f.w or f.w == ""))
        or (meineVor > ihreVor) or (e.discoveredBy and e.discoveredBy ~= Wert(f, "d", 60))
        or (e.ender and not Wert(f, "e", 60)) or (e.giverX and not Zahl(f, "a"))
        or (e.giverFaction and not Wert(f, "h", 10)) or (e.classOnly and not Wert(f, "j", 20))
        or (e.minSeen and (not ihrMin or e.minSeen < ihrMin))
        or (e.seenFactions and ((e.seenFactions.Alliance and not gesehen:find("A")) or (e.seenFactions.Horde and not gesehen:find("H"))))
    if neu then
        e.rev = ihrStand
        syncNeu = syncNeu + 1
    elseif QuestText(e) ~= vorher then
        e.rev = ichHabeMehr and math.max(time(), ihrStand + 1) or math.max(e.rev or 0, ihrStand)
        syncNeu = syncNeu + 1
    elseif ichHabeMehr then
        e.rev = math.max(e.rev or 0, time())
    else
        e.rev = math.max(e.rev or 0, ihrStand)
    end
end

local function KatalogZusammenfuehren(f)
    local name, beruf, art = Wert(f, "n"), Wert(f, "b", 60), Wert(f, "t", 30)
    if not name or not beruf or not art then
        return
    end
    local katalog = Katalog()
    local feld = beruf .. ":" .. name .. ":" .. art
    local quelle = Wert(f, "q")
    if katalog[feld] and quelle and katalog[feld].sourceName and katalog[feld].sourceName ~= quelle then
        feld = feld .. ":" .. quelle
    end
    local e = katalog[feld]
    local neu = not e
    if neu then
        e = { name = name, profession = beruf, sourceType = art }
        katalog[feld] = e
    end
    local vorher = neu and "" or KatalogText(e)
    e.requiredSkill = e.requiredSkill or Zahl(f, "s")
    e.sourceName = e.sourceName or Wert(f, "q")
    e.zone = e.zone or Wert(f, "z")
    e.subZone = e.subZone or Wert(f, "u")
    e.x = e.x or Zahl(f, "x")
    e.y = e.y or Zahl(f, "y")
    e.cost = e.cost or Zahl(f, "c")
    local npcF = Wert(f, "h", 10)
    if not e.npcFaction and (npcF == "Alliance" or npcF == "Horde" or npcF == "Neutral") then
        e.npcFaction = npcF
    end
    local ihrErstesMal = Zahl(f, "f")
    local ihrEntdecker = Wert(f, "d", 60)
    if ihrEntdecker and ihrErstesMal and (not e.firstSeen or ihrErstesMal < e.firstSeen) then
        e.firstSeen = ihrErstesMal
        e.discoveredBy = ihrEntdecker
    end
    e.discoveredBy = e.discoveredBy or ihrEntdecker
    local ihrStand = Zahl(f, "r") or 0
    local ichHabeMehr = (e.requiredSkill and not Zahl(f, "s")) or (e.sourceName and not f.q) or (e.zone and not f.z)
        or (e.x and not Zahl(f, "x")) or (e.cost and not Zahl(f, "c")) or (e.npcFaction and not Wert(f, "h", 10))
        or (e.discoveredBy and e.discoveredBy ~= Wert(f, "d", 60))
    if neu then
        e.rev = ihrStand
        syncNeu = syncNeu + 1
    elseif KatalogText(e) ~= vorher then
        e.rev = ichHabeMehr and math.max(time(), ihrStand + 1) or math.max(e.rev or 0, ihrStand)
        syncNeu = syncNeu + 1
    elseif ichHabeMehr then
        e.rev = math.max(e.rev or 0, time())
    else
        e.rev = math.max(e.rev or 0, ihrStand)
    end
end

local function VonMirSelbst(absender)
    if not absender then
        return true
    end
    local kurz = string.match(absender, "^([^%-]+)") or absender
    return absender == VollerName() or kurz == UnitName("player")
        or (GetUnitName and absender == GetUnitName("player"))
end


-- Fehlendes beim Besitzer einer Uebersicht anfragen. Die Anfrage prueft erst beim
-- Senden, was dann noch fehlt (andere haben es vielleicht schon besorgt).
local function Anfragen(art, besitzer, liste, kanal, verzoegerung)
    local stueck, laenge = {}, 0
    local function einreihen(schluessel)
        local kopie = schluessel
        SyncSenden(function()
            local offen = {}
            for _, paar in ipairs(kopie) do
                local stand = MeinStand(art, paar[1])
                if not stand or stand < paar[2] then
                    table.insert(offen, paar[1])
                end
            end
            if #offen == 0 then
                return nil
            end
            return "W~" .. besitzer .. "~" .. art .. "~" .. table.concat(offen, ",")
        end, kanal, verzoegerung)
    end
    local kopfLaenge = 5 + #besitzer
    for _, paar in ipairs(liste) do
        if laenge + #paar[1] + 1 + kopfLaenge > K.SYNC_MAX_NACHRICHT and #stueck > 0 then
            einreihen(stueck)
            stueck, laenge = {}, 0
        end
        table.insert(stueck, paar)
        laenge = laenge + #paar[1] + 1
    end
    if #stueck > 0 then
        einreihen(stueck)
    end
end

local function SyncEmpfangen(prefix, text, kanal, absender)
    local erlaubt = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
    if prefix ~= K.SYNC_PREFIX or not erlaubt[kanal] or not SyncAn() or VonMirSelbst(absender) then
        return
    end
    if type(text) ~= "string" or #text > 255 then
        return
    end
    local typ, rest = string.match(text, "^(%a)~(.*)$")
    if typ == "H" then
        -- Jemand hat sich gemeldet: hoechstens EINER antwortet (zufaellige Wartezeit;
        -- wer vorher eine fremde Antwort sieht, bricht ab)
        local seit = tonumber(string.match(rest or "", "^(%d+)")) or 0
        if KanalArt(kanal) == "GROUP" then
            seit = 0
        end
        if syncAntwortGeplant[absender] then
            return
        end
        local plan = { abgebrochen = false }
        syncAntwortGeplant[absender] = plan
        C_Timer.After(2 + math.random(0, 12), function()
            if syncAntwortGeplant[absender] == plan then
                syncAntwortGeplant[absender] = nil
            end
            if not plan.abgebrochen then
                IndexSenden(seit, kanal, absender)
            end
        end)
    elseif typ == "I" then
        local ziel, art, liste = string.match(rest or "", "^([^~]+)~([QK])~(.*)$")
        if not ziel then
            return
        end
        if ziel ~= "*" and not VonMirSelbst(ziel) then
            -- jemand anderes beantwortet gerade ein "Hallo": nicht doppelt antworten
            if syncAntwortGeplant[ziel] then
                syncAntwortGeplant[ziel].abgebrochen = true
            end
            return
        end
        if ziel ~= "*" then
            syncAntwortErhalten[KanalArt(kanal)] = time()
        end
        syncPartner[absender] = true
        local katalogKurz = art == "K" and KatalogNachKurzschluessel() or nil
        local wunsch = {}
        for schluessel, stand in string.gmatch(liste, "([%w]+):(%d+)") do
            stand = tonumber(stand)
            local meins = MeinStand(art, schluessel, katalogKurz)
            local merker = art .. schluessel
            local frueher = syncAngefragt[merker]
            if (not meins or meins < stand) and not (frueher and time() - frueher.zeit < 120 and frueher.stand >= stand) then
                syncAngefragt[merker] = { zeit = time(), stand = stand, art = art, schluessel = schluessel }
                table.insert(wunsch, { schluessel, stand })
            end
        end
        if #wunsch > 0 then
            -- an mich gerichtet: sofort; Neuheiten an alle: zufaellig verzoegert, damit
            -- nicht alle gleichzeitig dasselbe anfragen
            Anfragen(art, absender, wunsch, kanal, ziel == "*" and math.random(2, 20) or 0)
        end
    elseif typ == "W" then
        local ziel, art, liste = string.match(rest or "", "^([^~]+)~([QK])~(.*)$")
        if not ziel or not VonMirSelbst(ziel) then
            return
        end
        for schluessel in string.gmatch(liste, "[%w]+") do
            DatenSenden(art, schluessel, kanal)
        end
    elseif typ == "D" then
        local art, nr, teil, gesamt, inhalt = string.match(rest or "", "^([QK])~(%d+)~(%d+)~(%d+)~(.*)$")
        teil, gesamt = tonumber(teil), tonumber(gesamt)
        if not art or not teil or not gesamt or gesamt > 20 or teil > gesamt then
            return
        end
        local merker = absender .. "#" .. nr
        local puffer = syncTeile[merker] or { zeit = time(), teile = {} }
        syncTeile[merker] = puffer
        puffer.teile[teil] = inhalt
        for i = 1, gesamt do
            if not puffer.teile[i] then
                return
            end
        end
        syncTeile[merker] = nil
        syncEmpfangen = syncEmpfangen + 1
        local f = Felder(table.concat(puffer.teile))
        if art == "Q" then
            QuestZusammenfuehren(f)
        else
            KatalogZusammenfuehren(f)
        end
    end
    -- unvollstaendige Teile nach 5 Minuten verwerfen
    for merker, puffer in pairs(syncTeile) do
        if time() - puffer.zeit > 300 then
            syncTeile[merker] = nil
        end
    end
end

-- "Hallo" sagen und eigene Neuheiten seit der letzten Synchronisation teilen
local function SyncHallo(kanal)
    if not SyncAn() then
        return
    end
    local art = KanalArt(kanal)
    local seit = 0
    if art == "GUILD" then
        seit = math.max(0, (ForeverDashboardData.settings.syncStand or 0) - K.SYNC_SICHERHEIT)
    end
    syncHalloZeit[art] = time()
    SyncSenden("H~" .. seit, kanal)
    IndexSenden(seit, kanal, "*")
end

-- Ist alles Angefragte angekommen? Dann gilt die Gilde als synchron.
local function SyncStandPruefen()
    if not syncAntwortErhalten.GUILD or not syncHalloZeit.GUILD then
        return
    end
    for merker, a in pairs(syncAngefragt) do
        local stand = MeinStand(a.art, a.schluessel)
        if stand and stand >= a.stand then
            syncAngefragt[merker] = nil
        elseif time() - a.zeit > 600 then
            syncAngefragt[merker] = nil -- kam nicht an: beim naechsten Mal erneut
            return
        else
            return
        end
    end
    ForeverDashboardData.settings.syncStand = syncHalloZeit.GUILD
end

local function SyncStarten()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(K.SYNC_PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(K.SYNC_PREFIX)
    end
    C_Timer.NewTicker(K.SYNC_TAKT, SyncTakt)
    -- 20 Sekunden nach dem Einloggen: Hallo in Gilde und Gruppe
    C_Timer.After(20, function()
        for _, k in ipairs(SyncKanaele()) do
            SyncHallo(k)
        end
    end)
    -- Neu Entdecktes etwa eine Minute spaeter mitteilen (nur die neuen Eintraege)
    syncLetzteNeuheiten = time()
    C_Timer.NewTicker(60, function()
        local seit = syncLetzteNeuheiten
        syncLetzteNeuheiten = time()
        IndexSenden(seit, nil, "*")
        SyncStandPruefen()
    end)
end

-- Wenn eine Gruppe entsteht oder jemand dazukommt: in der Gruppe "Hallo" sagen
local syncGruppeGroesse, syncGruppeZeit = 0, 0
local function SyncGruppeGeaendert()
    local anzahl = GetNumGroupMembers and GetNumGroupMembers() or 0
    local vorher = syncGruppeGroesse
    syncGruppeGroesse = anzahl
    if anzahl <= vorher or anzahl < 2 or time() - syncGruppeZeit < 120 then
        return
    end
    syncGruppeZeit = time()
    C_Timer.After(10, function()
        for _, k in ipairs(SyncKanaele()) do
            if k ~= "GUILD" then
                SyncHallo(k)
            end
        end
    end)
end

local function SyncAnzeigen()
    Grunddaten()
    local an = ForeverDashboardData.settings and ForeverDashboardData.settings.sync ~= false
    local namen = { GUILD = "Gilde", PARTY = "Gruppe", RAID = "Schlachtzug", INSTANCE_CHAT = "Instanzgruppe" }
    local aktiv = {}
    for _, k in ipairs(SyncKanaele()) do
        table.insert(aktiv, namen[k] or k)
    end
    local partner = 0
    for _ in pairs(syncPartner) do
        partner = partner + 1
    end
    print(ADDON_TITEL .. " - Synchronisation")
    print("Status: " .. (an and "|cff44ff44an|r" or "|cffff4444aus|r")
        .. (#aktiv > 0 and (" - teilt gerade mit: " .. table.concat(aktiv, ", ")) or " (weder Gilde noch Gruppe - niemand zum Teilen da)"))
    print("Mitspieler mit Add-on in dieser Sitzung: " .. partner)
    print("Seit dem Einloggen empfangen: " .. syncEmpfangen .. " Einträge, davon neu oder ergänzt: " .. syncNeu)
    print("Wartende Nachrichten: " .. #syncWarteschlange)
    print("Ein-/Ausschalten: /fd sync an  bzw.  /fd sync aus")
end

-- ---------------------------------------------------------------------------
-- Fenster im Spiel: zeigt Levelfortschritt, Quests und Rezepte live an.
-- Nur Anzeige, keine Spielhandlungen. Oeffnen/Schliessen mit /fd.
-- Verwendet nur Grafiken, die im Spiel selbst enthalten sind.
-- ---------------------------------------------------------------------------
local Fenster
local fensterReiter = "quests"
local fensterGebiet = nil
local FensterAktualisieren
-- Nur Rezepte, die noch zu lernen sind (Bekanntes zeigt Guild ERP)
K.REZ_FILTER = { "alle", "jetzt", "spaeter" }
K.REZ_FILTER_TEXT = { alle = "Alle zeigen", jetzt = "Jetzt lernbar", spaeter = "Später" }
K.REZ_FILTER_FARBE = { alle = "ffffff", jetzt = "44dd55", spaeter = "ffaa00" }
K.REZ_SORT = { "gruppe", "wert", "wertab", "name", "kosten" }
K.REZ_SORT_TEXT = { gruppe = "Nach Gruppe (wie im Spiel)", wert = "Nach Berufswert", wertab = "Berufswert absteigend", name = "Nach Name", kosten = "Nach Kosten" }
local rezFilter, rezSort, rezBeruf = "alle", "gruppe", nil
local rezUebersicht = { berufe = {}, summen = {} }

-- Klassenfaehigkeiten
K.FERT_BALD = 4
K.ZU_HOCH = 4 -- Quests mehr als 4 Stufen ueber dem Charakter gelten als "noch zu hoch" -- "bald" = in den naechsten 4 Stufen
K.FERT_FILTER = { "alle", "jetzt", "bald", "spaeter" } -- Gelerntes zeigt das Zauberbuch
K.FERT_GRUPPE = {
    jetzt = { text = "Jetzt lernbar", hex = "44dd55", rgb = { 0.27, 0.85, 0.35 } },
    bald = { text = "Bald lernbar", hex = "4aa3ff", rgb = { 0.29, 0.64, 1 } },
    spaeter = { text = "Später", hex = "ffaa00", rgb = { 1, 0.67, 0 } },
    gelernt = { text = "Gelernt", hex = "f0cd63", rgb = { 0.85, 0.68, 0.25 } },
}
K.FERT_SORT = { "stufe", "name", "kosten" }
K.FERT_SORT_TEXT = { stufe = "Nach Stufe", name = "Nach Name", kosten = "Nach Kosten" }
local fertFilter, fertSort, fertKategorie = "alle", "stufe", nil
local fertUebersicht = { kategorien = {}, summen = {} }
K.ICON_FAEHIGKEIT = "Interface\\Icons\\INV_Misc_Book_11"

K.QUALITAET_FARBE = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
K.QUALITAET_RGB = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}
K.STATUS = {
    abgabebereit = { text = "Abgabebereit", rgb = { 0.27, 0.85, 0.35 }, hex = "44dd55", rang = 1 },
    aktiv = { text = "Aktiv", rgb = { 0.94, 0.80, 0.39 }, hex = "f0cd63", rang = 2 },
    verfuegbar = { text = "Verfügbar", rgb = { 0.29, 0.64, 1 }, hex = "4aa3ff", rang = 3 },
    gesperrt = { text = "Gesperrt", rgb = { 0.5, 0.5, 0.5 }, hex = "8c8c8c", rang = 4 },
    zuhoch = { text = "Noch zu hoch", rgb = { 0.85, 0.35, 0.3 }, hex = "d9594d", rang = 5 },
    erledigt = { text = "Erledigt", rgb = { 0.4, 0.4, 0.4 }, hex = "777777", rang = 6 },
}
K.BERUF_ICON = {
    ["Schmiedekunst"] = "Interface\\Icons\\Trade_BlackSmithing",
    ["Bergbau"] = "Interface\\Icons\\Trade_Mining",
    ["Kochkunst"] = "Interface\\Icons\\INV_Misc_Food_15",
    ["Angeln"] = "Interface\\Icons\\Trade_Fishing",
    ["Kürschnerei"] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Lederverarbeitung"] = "Interface\\Icons\\Trade_LeatherWorking",
    ["Kräuterkunde"] = "Interface\\Icons\\Trade_Herbalism",
    ["Alchemie"] = "Interface\\Icons\\Trade_Alchemy",
    ["Schneiderei"] = "Interface\\Icons\\Trade_Tailoring",
    ["Ingenieurskunst"] = "Interface\\Icons\\Trade_Engineering",
    ["Verzauberkunst"] = "Interface\\Icons\\Trade_Engraving",
    ["Erste Hilfe"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}
K.ICON_QUEST = "Interface\\Icons\\INV_Misc_Note_01"
K.ICON_UNBEKANNT = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Zahl3(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local t, laenge = {}, #s
    for i = 1, laenge do
        local z = string.sub(s, i, i)
        table.insert(t, z)
        local hinten = laenge - i
        if hinten > 0 and hinten % 3 == 0 and z ~= "-" then
            table.insert(t, ".")
        end
    end
    return table.concat(t)
end

local function Farbe(hex, text)
    return "|cff" .. hex .. tostring(text) .. "|r"
end

-- Welcher Charakter wird im Fenster gezeigt? (nil = der gerade gespielte)
local fensterChar = nil
local NotizbuchUmschalten, NotizbuchAktualisieren, NotizbuchBauen
local Notizbuch
local function AnsichtCharakter()
    local eigen = CharakterSchluessel()
    if fensterChar and fensterChar ~= eigen and ForeverDashboardData.characters[fensterChar] then
        return ForeverDashboardData.characters[fensterChar], false, fensterChar
    end
    return Charakter(), true, eigen
end

-- Klassen-Kuerzel (z. B. "PALADIN") eines gespeicherten Charakters
local function KlassenKuerzel(c)
    if c.classToken then
        return c.classToken
    end
    if c.className and string.upper(c.className) == c.className then
        return c.className
    end
    return nil
end

-- Fraktionsfarben: Akzent (Text), Banner (Kopf), Rahmen
local function Fraktion()
    local c, live = AnsichtCharakter()
    local fraktion = live and UnitFactionGroup and UnitFactionGroup("player") or (c and c.faction)
    if fraktion == "Horde" then
        return { hex = "e9a24a", akzent = { 0.91, 0.64, 0.29 }, banner = { 0.45, 0.07, 0.05 }, rahmen = { 0.72, 0.45, 0.18 } }
    end
    return { hex = "f0cd63", akzent = { 0.94, 0.80, 0.39 }, banner = { 0.08, 0.20, 0.42 }, rahmen = { 0.85, 0.68, 0.25 } }
end

local function ItemIcon(itemID)
    if not itemID then
        return nil
    end
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then
            return icon
        end
    end
    if GetItemIcon then
        local ok, icon = pcall(GetItemIcon, itemID)
        if ok and icon then
            return icon
        end
    end
    return nil
end

local function Geld(kupfer)
    if not kupfer or kupfer <= 0 then
        return ""
    end
    if GetCoinTextureString then
        return GetCoinTextureString(kupfer)
    end
    return Zahl3(math.floor(kupfer / 100)) .. "s"
end

-- Ist eine Quest fuer diesen Charakter ueberhaupt zu haben? (Fraktion, Klasse)
-- Rueckgabe: true/false und ein kurzer Grund
local function QuestFuerCharakter(e, fraktion, klasse)
    if e.classOnly and klasse and e.classOnly ~= klasse then
        return false, "klasse"
    end
    if not e.classOnly and klasse then
        local k = KlasseAusName(e.logHeader) or KlasseAusName(e.zone)
        if k and k ~= klasse then
            return false, "klasse"
        end
    end
    if not fraktion then
        return true
    end
    if e.giverFaction == "Alliance" or e.giverFaction == "Horde" then
        return e.giverFaction == fraktion, "fraktion"
    elseif e.giverFaction == "Neutral" then
        return true
    end
    -- Auftraggeber unbekannt: Wer hat die Quest schon gesehen?
    local gesehen = e.seenFactions
    if not gesehen or not next(gesehen) then
        gesehen = {}
        for schluessel in pairs(e.seenBy or {}) do
            local c = ForeverDashboardData.characters[schluessel]
            if c and c.faction then
                gesehen[c.faction] = true
            end
        end
    end
    if next(gesehen) and not gesehen[fraktion] then
        return false, "fraktion"
    end
    return true
end

-- Vorquests einer Quest: gelernte Verknuepfungen plus "gleicher Name = gleiche Reihe"
-- (K.namensVor wird in QuestListe berechnet; gesperrte Verknuepfungen bleiben weg)
local function Vorquests(e, id)
    local liste = {}
    for vor in pairs(e and e.prev or {}) do
        if not (e.notPrev and e.notPrev[vor]) then
            liste[vor] = true
        end
    end
    local nv = K.namensVor and K.namensVor[id or (e and e.id)]
    if nv and not next(liste) then
        liste[nv] = true
    end
    return liste
end

-- Quests mit gleichem Namen (fuer diesen Charakter sichtbar) als Reihe ansehen: nach Stufe, dann Nummer
local function NamensReihen(sichtbar)
    local gruppen, vor = {}, {}
    for id, e in pairs(sichtbar) do
        gruppen[e.name] = gruppen[e.name] or {}
        table.insert(gruppen[e.name], id)
    end
    local wissen = QuestWissen()
    for _, ids in pairs(gruppen) do
        if #ids > 1 then
            table.sort(ids, function(a, b)
                local la, lb = wissen[a].level or 0, wissen[b].level or 0
                if la ~= lb then
                    return la < lb
                end
                return a < b
            end)
            for i = 2, #ids do
                vor[ids[i]] = ids[i - 1]
            end
        end
    end
    K.namensVor = vor
end

-- Quests des aktuellen Charakters aufbereiten
local function QuestListe()
    local charakter, live = AnsichtCharakter()
    charakter = charakter or {}
    local fraktion = live and SpielerFraktion() or charakter.faction
    local klasse = live and select(2, UnitClass("player")) or KlassenKuerzel(charakter)
    local stufe = (live and UnitLevel("player")) or charakter.level or 1
    local aktiv = charakter.questsActive or {}
    local erledigt = charakter.questsCompleted or {}
    local liste = {}
    -- zuerst: was ist fuer diesen Charakter sichtbar? (fuer "gleicher Name = gleiche Reihe")
    local sichtbar = {}
    for id, e in pairs(QuestWissen()) do
        -- aktive oder erledigte Quests immer zeigen; sonst nur, was fuer diesen Charakter gilt
        if e.name and (aktiv[id] or erledigt[id] or QuestFuerCharakter(e, fraktion, klasse)) then
            sichtbar[id] = e
        end
    end
    NamensReihen(sichtbar)
    for id, e in pairs(sichtbar) do
        do
            local fehlend = {}
            for vor in pairs(Vorquests(e, id)) do
                if not erledigt[vor] then
                    table.insert(fehlend, vor)
                end
            end
            local status
            if aktiv[id] then
                status = aktiv[id].readyToTurnIn and "abgabebereit" or "aktiv"
            elseif erledigt[id] then
                status = "erledigt"
            elseif #fehlend > 0 then
                status = "gesperrt"
            else
                status = "verfuegbar"
            end
            -- deutlich ueber der eigenen Stufe? (Ausnahme: jemand hat sie schon mit
            -- dieser oder niedrigerer Stufe angeboten bekommen)
            if (status == "verfuegbar" or status == "gesperrt") and e.level
                and e.level > stufe + K.ZU_HOCH and not (e.minSeen and e.minSeen <= stufe) then
                status = "zuhoch"
            end
            local beste
            for _, r in ipairs(e.rewards or {}) do
                if not beste or (r.quality or 0) > (beste.quality or 0) then
                    beste = r
                end
            end
            table.insert(liste, {
                id = id, name = e.name, zone = e.zone or "Unbekannt", level = e.level, xp = e.xp or 0,
                status = status, fehlend = fehlend, beste = beste, giver = e.giver,
                annahme = e.giver and { name = e.giver, zone = e.zone, x = e.giverX, y = e.giverY } or nil,
                abgabe = e.ender and { name = e.ender, zone = e.enderZone, x = e.enderX, y = e.enderY } or nil,
                belohnungen = e.rewards or {},
                discoveredBy = e.discoveredBy, progress = aktiv[id] and aktiv[id].progress or nil,
            })
        end
    end
    return liste
end

-- Kartenverzeichnis des Spiels: Gebietsname -> Karteninfo (fuer Art und Stufenbereich)
local kartenVerzeichnis
local function KarteZuName(name)
    if not C_Map or not C_Map.GetMapChildrenInfo then
        return nil
    end
    if not kartenVerzeichnis then
        kartenVerzeichnis = {}
        for _, oben in ipairs({ 947, 946, 1414, 1415, 1945, 113 }) do
            local ok, liste = pcall(C_Map.GetMapChildrenInfo, oben, nil, true)
            if ok and type(liste) == "table" then
                for _, info in ipairs(liste) do
                    if info.name and not kartenVerzeichnis[info.name] then
                        kartenVerzeichnis[info.name] = info
                    end
                end
            end
        end
    end
    return kartenVerzeichnis[name]
end

K.DUNGEON_MARKEN = { [81] = "dungeon", [62] = "raid", [88] = "raid", [89] = "raid" }

-- Rueckfall, falls das Spiel die Art eines Gebiets nicht verraet: bekannte Instanzen
K.BEKANNTE_INSTANZEN = {
    ["Flammenschlund"] = "dungeon", ["Die Todesminen"] = "dungeon", ["Höhlen des Wehklagens"] = "dungeon",
    ["Burg Schattenfang"] = "dungeon", ["Blackfathom-Tiefe"] = "dungeon", ["Das Verlies"] = "dungeon",
    ["Gnomeregan"] = "dungeon", ["Kral der Klingenhauer"] = "dungeon", ["Scharlachrotes Kloster"] = "dungeon",
    ["Hügel der Klingenhauer"] = "dungeon", ["Uldaman"] = "dungeon", ["Zul'Farrak"] = "dungeon",
    ["Maraudon"] = "dungeon", ["Tempel von Atal'Hakkar"] = "dungeon", ["Der Tempel von Atal'Hakkar"] = "dungeon",
    ["Schwarzfelstiefen"] = "dungeon", ["Untere Schwarzfelsspitze"] = "dungeon", ["Obere Schwarzfelsspitze"] = "dungeon",
    ["Schwarzfelsspitze"] = "dungeon", ["Düsterbruch"] = "dungeon", ["Stratholme"] = "dungeon", ["Scholomance"] = "dungeon",
    ["Geschmolzener Kern"] = "raid", ["Onyxias Hort"] = "raid", ["Pechschwingenhort"] = "raid", ["Zul'Gurub"] = "raid",
    ["Ruinen von Ahn'Qiraj"] = "raid", ["Tempel von Ahn'Qiraj"] = "raid", ["Naxxramas"] = "raid",
    ["Ragefire Chasm"] = "dungeon", ["The Deadmines"] = "dungeon", ["Wailing Caverns"] = "dungeon",
    ["Shadowfang Keep"] = "dungeon", ["Blackfathom Deeps"] = "dungeon", ["The Stockade"] = "dungeon",
}

-- Art (Gebiet/Dungeon/Schlachtzug/Sonstiges) und Stufenbereich eines Gebiets
local function GebietInfo(name, quests)
    local info = { typ = "zone" }
    local karte = KarteZuName(name)
    local gemerkt = GebietWissen()[name]
    if gemerkt and gemerkt.typ then
        info.typ = gemerkt.typ
    elseif karte and karte.mapType == 4 then
        info.typ = "dungeon"
    end
    local wissen = QuestWissen()
    local stufeMin, stufeMax, offen, bereit = nil, nil, 0, 0
    for _, q in ipairs(quests) do
        if q.zone == name then
            if q.level and q.level > 0 then
                stufeMin = math.min(stufeMin or q.level, q.level)
                stufeMax = math.max(stufeMax or q.level, q.level)
            end
            if q.status == "aktiv" or q.status == "abgabebereit" then
                offen = offen + 1
            end
            if q.status == "abgabebereit" then
                bereit = bereit + 1
            end
            local e = wissen[q.id]
            if e and info.typ == "zone" then
                local marke = K.DUNGEON_MARKEN[e.tagID or 0]
                local text = e.tagName and string.lower(e.tagName) or ""
                if marke then
                    info.typ = marke
                elseif string.find(text, "dungeon") then
                    info.typ = "dungeon"
                elseif string.find(text, "schlachtzug") or string.find(text, "raid") then
                    info.typ = "raid"
                end
            end
        end
    end
    -- Ueberschriften wie die eigene Klasse sind keine Gebiete
    if info.typ == "zone" and K.BEKANNTE_INSTANZEN[name] and not (karte and karte.mapType == 3) then
        info.typ = K.BEKANNTE_INSTANZEN[name]
    end
    if not karte and info.typ == "zone" then
        local klasse = UnitClass and UnitClass("player")
        if name == klasse or (LOCALIZED_CLASS_NAMES_MALE and tContains and tContains(LOCALIZED_CLASS_NAMES_MALE, name))
            or (LOCALIZED_CLASS_NAMES_FEMALE and tContains and tContains(LOCALIZED_CLASS_NAMES_FEMALE, name)) then
            info.typ = "sonst"
        end
    end
    -- Stufenbereich: aus der Karte, sonst aus den bekannten Quests
    if karte and C_Map.GetMapLevels then
        local ok, minimum, maximum = pcall(C_Map.GetMapLevels, karte.mapID)
        if ok and minimum and maximum and maximum > 0 then
            info.min, info.max, info.quelle = minimum, maximum, "karte"
        end
    end
    if not info.min and stufeMin then
        info.min, info.max, info.quelle = stufeMin, stufeMax, "quests"
    end
    info.offen, info.bereit = offen, bereit
    return info
end

K.GEBIET_ART = {
    zone = { text = "Gebiete", icon = "Interface\\Icons\\INV_Misc_Map_01", rang = 1 },
    dungeon = { text = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_03", rang = 2 },
    raid = { text = "Schlachtzüge", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", rang = 3 },
    sonst = { text = "Sonstiges", icon = "Interface\\Icons\\INV_Misc_Note_01", rang = 4 },
}

local function StufenText(info)
    if not info.min then
        return ""
    end
    local text = info.min == info.max and ("Stufe " .. info.min) or ("Stufe " .. info.min .. "-" .. info.max)
    return text .. (info.quelle == "quests" and "*" or "")
end

local function GebieteListe(quests)
    local menge, liste = {}, {}
    for _, q in ipairs(quests) do
        if q.status ~= "erledigt" and not menge[q.zone] then
            menge[q.zone] = true
            table.insert(liste, q.zone)
        end
    end
    table.sort(liste)
    return liste
end

-- ---------------------------------------------------------------------------
-- Bausteine
-- ---------------------------------------------------------------------------
K.BACKDROP_RAHMEN = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}
K.BACKDROP_KARTE = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
K.BACKDROP_DUENN = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}
K.BACKDROP_VORLAGE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Titel in der Questbuch-Schrift des Spiels (Morpheus); faellt auf Standardschriften zurueck
K.SCHRIFT_KARTE, K.SCHRIFT_KOPF, K.SCHRIFT_UNTER = "GameFontNormal", "GameFontNormalLarge", "GameFontNormal"
if CreateFont then
    local function questbuch(name, groesse, rueckfall)
        local fo = CreateFont(name)
        local ok = pcall(fo.SetFont, fo, "Fonts\\MORPHEUS.TTF", groesse, "")
        if ok and fo.GetFont and fo:GetFont() then
            fo:SetShadowColor(0, 0, 0, 1)
            fo:SetShadowOffset(1, -1)
            return name
        end
        return rueckfall
    end
    K.SCHRIFT_KARTE = questbuch("ReisefuehrerKartenTitel", 15, "GameFontNormal")
    K.SCHRIFT_KOPF = questbuch("ReisefuehrerUeberschrift", 18, "GameFontNormalLarge")
    K.SCHRIFT_UNTER = questbuch("ReisefuehrerUnterUeberschrift", 15, "GameFontNormal")
end

K.SPIEL_SCHRIFT = _G.Game15Font_Shadow and "Game15Font_Shadow" or "GameFontNormal"

local function Schrift(eltern, vorlage, links)
    local fs = eltern:CreateFontString(nil, "OVERLAY", vorlage)
    fs:SetJustifyH(links == false and "RIGHT" or "LEFT")
    if fs.SetWordWrap then
        fs:SetWordWrap(true)
    end
    return fs
end

-- Zweiter Tooltip: alle Lehrer/Haendler, bei denen es etwas gibt (wenn mehr als einer)
local quellenTooltip
local function QuellenTooltipZeigen(karte)
    local liste = karte.quellen
    if type(liste) ~= "table" or #liste < 2 then
        return
    end
    if not quellenTooltip then
        quellenTooltip = CreateFrame("GameTooltip", "ForeverDashboardQuellenTooltip", UIParent, "GameTooltipTemplate")
    end
    local t = quellenTooltip
    t:SetOwner(karte, "ANCHOR_NONE")
    t:ClearAllPoints()
    if GameTooltip and GameTooltip:IsShown() then
        t:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -4)
    else
        t:SetPoint("TOPLEFT", karte, "TOPRIGHT", 4, 0)
    end
    t:ClearLines()
    t:AddLine("Erhältlich bei " .. #liste .. " Stellen", 1, 0.82, 0)
    local zuletzt
    for _, q in ipairs(liste) do
        if q.zone ~= zuletzt then
            zuletzt = q.zone
            t:AddLine(" ")
            t:AddLine((q.zone or "Unbekanntes Gebiet") .. (q.hier and "  (hier)" or ""), 0.5, 0.75, 1)
        end
        t:AddDoubleLine("  " .. (q.art and (q.art .. ": ") or "") .. (q.name or "?")
            .. (q.x and (" (" .. q.x .. ", " .. q.y .. ")") or ""),
            (q.cost and q.cost > 0) and Geld(q.cost) or "", 1, 1, 1, 1, 1, 1)
    end
    t:Show()
end

-- Quellenliste sortieren: aktuelles Gebiet zuerst, dann nach Gebiet und Name
local function QuellenSortieren(liste)
    local hier = (GetRealZoneText and GetRealZoneText()) or ""
    for _, q in ipairs(liste) do
        q.hier = q.zone == hier
    end
    table.sort(liste, function(a, b)
        if a.hier ~= b.hier then
            return a.hier
        end
        if (a.zone or "") ~= (b.zone or "") then
            return (a.zone or "") < (b.zone or "")
        end
        if (a.art or "") ~= (b.art or "") then
            return (a.art or "") > (b.art or "") -- Lehrer vor Haendler
        end
        return (a.name or "") < (b.name or "")
    end)
    return liste
end

-- Eine Zeile (Karte) in der Liste: Farbstreifen, Symbol, Titel, rechte Angabe, zwei Unterzeilen
local function KarteBauen(eltern)
    local k = CreateFrame("Frame", nil, eltern, K.BACKDROP_VORLAGE)
    if k.SetBackdrop then
        k:SetBackdrop(K.BACKDROP_KARTE)
        k:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
        k:SetBackdropBorderColor(0.35, 0.3, 0.22, 0.9)
    end
    k.streifen = k:CreateTexture(nil, "ARTWORK")
    k.streifen:SetPoint("TOPLEFT", 4, -4)
    k.streifen:SetPoint("BOTTOMLEFT", 4, 4)
    k.streifen:SetWidth(3)
    k.symbol = k:CreateTexture(nil, "ARTWORK")
    k.symbol:SetSize(32, 32)
    k.symbol:SetPoint("TOPLEFT", 12, -8)
    k.symbol:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    k.symbolRand = CreateFrame("Frame", nil, k, K.BACKDROP_VORLAGE)
    k.symbolRand:SetPoint("TOPLEFT", k.symbol, "TOPLEFT", -2, 2)
    k.symbolRand:SetPoint("BOTTOMRIGHT", k.symbol, "BOTTOMRIGHT", 2, -2)
    if k.symbolRand.SetBackdrop then
        k.symbolRand:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    end
    k.titel = Schrift(k, K.SCHRIFT_KARTE)
    k.rechts = Schrift(k, "GameFontHighlightSmall", false)
    k.rechts:SetPoint("TOPRIGHT", -10, -9)
    k.zeile1 = Schrift(k, "GameFontHighlightSmall")
    k.zeile1:SetPoint("TOPLEFT", k.titel, "BOTTOMLEFT", 0, -3)
    k.zeile2 = Schrift(k, "GameFontHighlightSmall")
    k.zeile2:SetPoint("TOPLEFT", k.zeile1, "BOTTOMLEFT", 0, -2)
    -- kleine Symbolleiste (z. B. Quest-Belohnungen): unten rechts, Tooltip beim Ueberfahren
    k.icons = {}
    k.trenner = k:CreateTexture(nil, "ARTWORK")
    k.trenner:SetSize(1, 14)
    k.trenner:SetColorTexture(0.6, 0.55, 0.4, 0.6)
    k.trenner:Hide()
    k.IconFeld = function(self, i)
        local z = self.icons[i]
        if not z then
            z = CreateFrame("Button", nil, self, K.BACKDROP_VORLAGE)
            z:SetSize(18, 18)
            if z.SetBackdrop then
                z:SetBackdrop(K.BACKDROP_DUENN)
                z:SetBackdropColor(0, 0, 0, 0.6)
            end
            z.bild = z:CreateTexture(nil, "ARTWORK")
            z.bild:SetPoint("TOPLEFT", 1, -1)
            z.bild:SetPoint("BOTTOMRIGHT", -1, 1)
            z.bild:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            z.anzahl = z:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            z.anzahl:SetPoint("BOTTOMRIGHT", 1, -1)
            z:SetScript("OnEnter", function(feld)
                if feld.itemID and GameTooltip then
                    GameTooltip:SetOwner(feld, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. feld.itemID)
                    if feld.wahl then
                        GameTooltip:AddLine("Belohnung zur Wahl", 0.6, 0.8, 1)
                    end
                    GameTooltip:Show()
                end
            end)
            z:SetScript("OnLeave", function()
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end)
            self.icons[i] = z
        end
        return z
    end
    -- Zeilen fuer einzelne Belohnungen (Symbol + Name, Tooltip beim Ueberfahren)
    k.belohnungen = {}
    k.BelohnungZeile = function(self, i)
        local z = self.belohnungen[i]
        if not z then
            z = CreateFrame("Button", nil, self)
            z:SetHeight(18)
            z.icon = z:CreateTexture(nil, "ARTWORK")
            z.icon:SetSize(16, 16)
            z.icon:SetPoint("LEFT", 0, 0)
            z.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            z.text = Schrift(z, "GameFontHighlightSmall")
            z.text:SetPoint("LEFT", z.icon, "RIGHT", 6, 0)
            z.text:SetPoint("RIGHT", z, "RIGHT", 0, 0)
            if z.text.SetWordWrap then
                z.text:SetWordWrap(false)
            end
            local hl = z:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            z:SetScript("OnEnter", function(zeile)
                if zeile.itemID and GameTooltip then
                    GameTooltip:SetOwner(zeile, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. zeile.itemID)
                    GameTooltip:Show()
                end
            end)
            z:SetScript("OnLeave", function()
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end)
            self.belohnungen[i] = z
        end
        return z
    end
    k.aktion = CreateFrame("Button", nil, k, "UIPanelButtonTemplate")
    k.aktion:SetSize(110, 18)
    k.aktion:SetPoint("BOTTOMLEFT", 12, 7)
    k.aktion:Hide()
    k:EnableMouse(true)
    local function hauptTooltip(self)
        if not GameTooltip then
            return
        end
        if self.spellID and pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
        end) and GameTooltip:NumLines() > 0 then
            if self.zusatz then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.zusatz, 1, 0.82, 0, true)
            end
            GameTooltip:Show()
            return
        end
        local itemID = self.itemID
        if self.rezeptID then
            itemID = RezeptErgebnis(self.rezeptID) or itemID
        end
        if itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. itemID)
            if self.zusatz then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.zusatz, 1, 0.82, 0, true)
            end
            GameTooltip:Show()
        elseif self.rezeptID and pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. self.rezeptID)
        end) then
            if self.zusatz then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.zusatz, 1, 0.82, 0, true)
            end
            GameTooltip:Show()
        elseif self.hinweis then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.hinweis, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end
    k:SetScript("OnEnter", function(self)
        if self.spielHoverOk and type(self.spielHover) == "table" then
            self.spielHover:Show()
        end
        hauptTooltip(self)
        QuellenTooltipZeigen(self)
    end)
    k:SetScript("OnLeave", function(self)
        if type(self.spielHover) == "table" then
            self.spielHover:Hide()
        end
        if GameTooltip then
            GameTooltip:Hide()
        end
        if quellenTooltip then
            quellenTooltip:Hide()
        end
    end)
    return k
end

-- Auf-/Zuklappen merken (Einstellung bleibt nach dem Ausloggen erhalten)
local function IstZu(schluessel, standard)
    local zu = ForeverDashboardData.settings and ForeverDashboardData.settings.zu
    if zu and zu[schluessel] ~= nil then
        return zu[schluessel]
    end
    return standard and true or false
end

local function Umklappen(schluessel, standard)
    ForeverDashboardData.settings = ForeverDashboardData.settings or {}
    ForeverDashboardData.settings.zu = ForeverDashboardData.settings.zu or {}
    ForeverDashboardData.settings.zu[schluessel] = not IstZu(schluessel, standard)
end

local function UeberschriftBauen(eltern)
    local u = CreateFrame("Button", nil, eltern)
    u.hl = u:CreateTexture(nil, "HIGHLIGHT")
    u.hl:SetAllPoints()
    u.hl:SetColorTexture(1, 1, 1, 0.06)
    u.knopf = u:CreateTexture(nil, "ARTWORK")
    u.knopf:SetSize(14, 14)
    u.knopf:SetPoint("LEFT", 2, 0)
    u.symbol = u:CreateTexture(nil, "ARTWORK")
    u.symbol:SetSize(22, 22)
    u.symbol:SetPoint("LEFT", u.knopf, "RIGHT", 4, 0)
    u.symbol:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    u.text = Schrift(u, "GameFontNormalLarge")
    u.rechts = Schrift(u, "GameFontHighlightSmall", false)
    u.rechts:SetPoint("RIGHT", -4, 0)
    u.linie = u:CreateTexture(nil, "ARTWORK")
    u.linie:SetHeight(1)
    u.linie:SetPoint("BOTTOMLEFT", 0, 0)
    u.linie:SetPoint("BOTTOMRIGHT", 0, 0)
    -- kleiner Fortschrittsbalken (fuer Berufe)
    u.balkenHg = u:CreateTexture(nil, "BACKGROUND")
    u.balkenHg:SetHeight(6)
    u.balkenHg:SetPoint("BOTTOMLEFT", u.text, "BOTTOMRIGHT", 10, 3)
    u.balkenHg:SetPoint("RIGHT", u.rechts, "LEFT", -10, 0)
    u.balkenHg:SetColorTexture(0, 0, 0, 0.6)
    u.balken = u:CreateTexture(nil, "ARTWORK")
    u.balken:SetHeight(6)
    u.balken:SetPoint("LEFT", u.balkenHg, "LEFT", 0, 0)
    u.balken:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    u:SetScript("OnClick", function(self)
        if self.schluessel then
            Umklappen(self.schluessel, self.standardZu)
            FensterAktualisieren()
        end
    end)
    return u
end

-- ---------------------------------------------------------------------------
-- Optionen, Knopf an der Minimap und Aussehen (klassisch / Spiel-Look).
-- Alles in einer Tabelle (spart lokale Namen). Grafiken nur aus dem Spielclient;
-- fehlt eine Grafik, bleibt es beim klassischen Aussehen.
-- ---------------------------------------------------------------------------
local O = { teile = {} }
local AuswahlBauen -- weiter unten gebaut
O.STANDARD = { look = "klassisch", minimap = true, winkel = 225 }
-- Quests: Auswahl "Zeigen" (Vorlage A)
O.QUEST_FILTER = { "alle", "abgabebereit", "aktiv", "verfuegbar" }
O.QUEST_FILTER_TEXT = { alle = "Alle offenen", abgabebereit = "Abgabebereit", aktiv = "Aktiv", verfuegbar = "Verfügbar" }
O.questFilter = "alle"
O.questZaehler = {}
O.ZEILEN_SCHRIFT = "GameFontHighlight" -- normale Listenschrift fuer Zeilen
O.ICON = "Interface\\Icons\\INV_Misc_Map_01"

function O.Wert(name)
    local e = ForeverDashboardData and ForeverDashboardData.settings
    local o = e and e.optionen
    if o and o[name] ~= nil then
        return o[name]
    end
    return O.STANDARD[name]
end

function O.Setzen(name, wert)
    Grunddaten()
    ForeverDashboardData.settings = ForeverDashboardData.settings or {}
    ForeverDashboardData.settings.optionen = ForeverDashboardData.settings.optionen or {}
    ForeverDashboardData.settings.optionen[name] = wert
end

function O.HatAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then
        return false
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

function O.Atlas(tex, name, groesse)
    if tex and tex.SetAtlas and O.HatAtlas(name) then
        tex:SetAtlas(name, groesse and true or false)
        return true
    end
    return false
end

-- Spiel-Look aktiv (und die Rahmen-Grafik im Spiel vorhanden)?
function O.Spiel()
    return O.Wert("look") == "spiel" and O.HatAtlas("UI-Frame-PortraitMetal-CornerTopLeft")
end

-- Teil anmelden: fn(spiel) laeuft jetzt und bei jedem Umschalten
function O.Teil(fn)
    table.insert(O.teile, fn)
    local ok, fehler = pcall(fn, O.Spiel())
    if not ok then
        ForeverDashboardData.diagnostics = ForeverDashboardData.diagnostics or {}
        ForeverDashboardData.diagnostics.lookFehler = tostring(fehler)
    end
end

function O.LookAnwenden()
    local spiel = O.Spiel()
    for _, fn in ipairs(O.teile) do
        local ok, fehler = pcall(fn, spiel)
        if not ok then
            ForeverDashboardData.diagnostics = ForeverDashboardData.diagnostics or {}
            ForeverDashboardData.diagnostics.lookFehler = tostring(fehler)
        end
    end
    if FensterAktualisieren then
        FensterAktualisieren()
    end
end

-- Knopf an der Minimap: Linksklick Fenster, Rechtsklick Optionen, Ziehen = verschieben
function O.KnopfPosition()
    local k = O.knopf
    if not k or not Minimap then
        return
    end
    local w = math.rad(O.Wert("winkel") or 225)
    local r = (Minimap:GetWidth() or 140) / 2 + 8
    k:ClearAllPoints()
    k:SetPoint("CENTER", Minimap, "CENTER", math.cos(w) * r, math.sin(w) * r)
end

function O.KnopfBauen()
    if O.knopf or not Minimap then
        return O.knopf
    end
    local k = CreateFrame("Button", "ForeverDashboardMinimapKnopf", Minimap)
    k:SetSize(32, 32)
    k:SetFrameStrata("MEDIUM")
    k:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    k:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    k:RegisterForDrag("LeftButton")
    k.hg = k:CreateTexture(nil, "BACKGROUND")
    k.hg:SetSize(22, 22)
    k.hg:SetPoint("CENTER")
    k.hg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    k.icon = k:CreateTexture(nil, "ARTWORK")
    k.icon:SetSize(18, 18)
    k.icon:SetPoint("CENTER")
    k.icon:SetTexture(O.ICON)
    k.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    k.rand = k:CreateTexture(nil, "OVERLAY")
    k.rand:SetSize(52, 52)
    k.rand:SetPoint("TOPLEFT")
    k.rand:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    k:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    k:SetScript("OnClick", function(_, taste)
        if taste == "RightButton" then
            O.Zeigen()
        else
            SlashCmdList.FOREVERDASHBOARD("")
        end
    end)
    k:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local skala = Minimap:GetEffectiveScale()
            if mx and cx then
                local atan2 = math.atan2 or function(a, b) return math.atan(a, b) end
                O.Setzen("winkel", math.deg(atan2(cy / skala - my, cx / skala - mx)))
                O.KnopfPosition()
            end
        end)
    end)
    k:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    k:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Reiseführer")
        GameTooltip:AddLine("Linksklick: öffnen oder schließen", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Rechtsklick: Optionen", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Ziehen: am Rand verschieben", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    k:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    O.knopf = k
    O.KnopfPosition()
    return k
end

function O.KnopfZeigen()
    if O.Wert("minimap") then
        local k = O.KnopfBauen()
        if k then
            O.KnopfPosition()
            k:Show()
        end
    elseif O.knopf then
        O.knopf:Hide()
    end
end

-- Optionen-Fenster
function O.Zeigen()
    local f = O.fenster
    if f then
        f:SetShown(not f:IsShown())
        if f:IsShown() then
            O.Auffrischen()
        end
        return
    end
    f = CreateFrame("Frame", "ForeverDashboardOptionen", UIParent, K.BACKDROP_VORLAGE)
    f:SetSize(340, 214)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop(K.BACKDROP_RAHMEN)
    end
    table.insert(UISpecialFrames, "ForeverDashboardOptionen")
    local titel = Schrift(f, K.SCHRIFT_KOPF)
    titel:SetPoint("TOPLEFT", 20, -18)
    titel:SetText("Reiseführer - Optionen")
    local zu = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    zu:SetPoint("TOPRIGHT", -4, -4)
    zu:SetScript("OnClick", function() f:Hide() end)

    local function zeile(text, y, hilfe)
        local t = Schrift(f, "GameFontNormal")
        t:SetPoint("TOPLEFT", 20, y)
        t:SetText(text)
        if hilfe then
            local h = Schrift(f, "GameFontDisableSmall")
            h:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
            h:SetPoint("RIGHT", f, "RIGHT", -20, 0)
            h:SetText(hilfe)
        end
        return t
    end
    zeile("Aussehen", -56, "Spiel-Look: Rahmen und Reiter wie in den modernen Fenstern des Spiels.")
    f.look = AuswahlBauen(f, 150, 200, true, function()
        local liste = {}
        for _, e in ipairs({ { "klassisch", "Klassisch" }, { "spiel", "Spiel-Look" } }) do
            table.insert(liste, { wert = e[1], text = e[2], gewaehlt = O.Wert("look") == e[1] })
        end
        return liste
    end, function(wert)
        O.Setzen("look", wert)
        O.LookAnwenden()
        O.Auffrischen()
    end)
    f.look:SetPoint("TOPRIGHT", -20, -52)

    local function haken(text, y, holen, setzen)
        local h = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        h:SetSize(24, 24)
        h:SetPoint("TOPLEFT", 16, y)
        local t = Schrift(f, "GameFontHighlight")
        t:SetPoint("LEFT", h, "RIGHT", 4, 0)
        t:SetText(text)
        h:SetScript("OnClick", function(self)
            setzen(self:GetChecked() and true or false)
        end)
        h.holen = holen
        return h
    end
    f.minimap = haken("Knopf an der Minimap zeigen", -112, function() return O.Wert("minimap") end, function(an)
        O.Setzen("minimap", an)
        O.KnopfZeigen()
    end)
    f.sync = haken("Wissen mit Gruppe und Gilde teilen", -140, function()
        return not (ForeverDashboardData.settings and ForeverDashboardData.settings.sync == false)
    end, function(an)
        ForeverDashboardData.settings = ForeverDashboardData.settings or {}
        ForeverDashboardData.settings.sync = an
    end)
    local fuss = Schrift(f, "GameFontDisableSmall")
    fuss:SetPoint("BOTTOMLEFT", 20, 16)
    fuss:SetText("Auch mit /fd optionen. Ohne Minimap-Knopf öffnet /fd das Fenster.")
    O.fenster = f
    O.Auffrischen()
    f:Show()
end

function O.Auffrischen()
    local f = O.fenster
    if not f then
        return
    end
    f.look:Setzen(O.Wert("look") == "spiel" and "Spiel-Look" or "Klassisch")
    f.minimap:SetChecked(f.minimap.holen() and true or false)
    f.sync:SetChecked(f.sync.holen() and true or false)
end

-- "/fd questtest": prueft NUR, welche Quest-Abfragen WoW Forever anbietet (erledigte Quests
-- laut Server, Questreihen, annehmbare Quests auf der Karte). Ergebnis in diagnostics.questtest.
function O.QuestTest()
    Grunddaten()
    local t = { zeit = date("%Y-%m-%d %H:%M:%S"), funktionen = {} }
    ForeverDashboardData.diagnostics = ForeverDashboardData.diagnostics or {}
    ForeverDashboardData.diagnostics.questtest = t
    local function da(tab, name)
        local ok = tab ~= nil and type(tab[name]) == "function"
        t.funktionen[name] = ok
        return ok
    end
    local QL, QLine = C_QuestLog, C_QuestLine
    da(QL, "IsQuestFlaggedCompleted")
    da(QL, "GetAllCompletedQuestIDs")
    t.funktionen.GetQuestsCompleted = type(GetQuestsCompleted) == "function"
    da(QLine, "GetQuestLineInfo")
    da(QLine, "GetQuestLineQuests")
    da(QLine, "GetAvailableQuestLines")
    da(QLine, "RequestQuestLinesForMap")
    da(QL, "GetQuestDifficultyLevel")
    -- erledigte Quests laut Server
    local anzahl = 0
    if t.funktionen.GetAllCompletedQuestIDs then
        local ok, liste = pcall(QL.GetAllCompletedQuestIDs)
        anzahl = ok and type(liste) == "table" and #liste or 0
    elseif t.funktionen.GetQuestsCompleted then
        local ok, liste = pcall(GetQuestsCompleted)
        for _ in pairs(ok and type(liste) == "table" and liste or {}) do
            anzahl = anzahl + 1
        end
    end
    t.erledigtLautServer = anzahl
    -- Questreihen der aktiven Quests
    local karte = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    t.karte = karte
    t.reihen = {}
    local c = Charakter()
    for id in pairs(c and c.questsActive or {}) do
        if t.funktionen.GetQuestLineInfo then
            local ok, info = pcall(QLine.GetQuestLineInfo, id, karte)
            if ok and type(info) == "table" and info.questLineID then
                local eintrag = { quest = id, reihe = info.questLineID, name = info.questLineName }
                if t.funktionen.GetQuestLineQuests then
                    local ok2, ids = pcall(QLine.GetQuestLineQuests, info.questLineID)
                    eintrag.quests = ok2 and type(ids) == "table" and table.concat(ids, ",") or nil
                end
                table.insert(t.reihen, eintrag)
            end
        end
    end
    -- annehmbare Quests auf der Karte (wie die "!" auf der Weltkarte)
    if karte and t.funktionen.RequestQuestLinesForMap then
        pcall(QLine.RequestQuestLinesForMap, karte)
    end
    C_Timer.After(2, function()
        t.verfuegbar = {}
        if karte and t.funktionen.GetAvailableQuestLines then
            local ok, liste = pcall(QLine.GetAvailableQuestLines, karte)
            for _, q in ipairs(ok and type(liste) == "table" and liste or {}) do
                table.insert(t.verfuegbar, { quest = q.questID, name = q.questName, reihe = q.questLineName,
                    x = q.x and math.floor(q.x * 1000) / 10, y = q.y and math.floor(q.y * 1000) / 10 })
            end
        end
        Melden("Quest-Test: erledigt laut Server " .. t.erledigtLautServer .. " Quests, Questreihen gefunden: "
            .. #t.reihen .. ", annehmbar auf dieser Karte: " .. #t.verfuegbar .. ". Bitte /reload und Claude Bescheid geben.")
    end)
end

-- Questfarbe nach Stufe wie im Spiel: rot (5+ drueber), orange (3-4), gelb (etwa deine Stufe),
-- gruen (darunter), grau (lohnt nicht mehr)
function O.StufenFarbe(questStufe, meineStufe)
    if not questStufe or not meineStufe or questStufe <= 0 then
        return nil
    end
    local d = questStufe - meineStufe
    if d >= 5 then
        return { 1, 0.1, 0.1 }
    elseif d >= 3 then
        return { 1, 0.5, 0.25 }
    elseif d >= -2 then
        return { 1, 1, 0 }
    end
    local gruen
    if GetQuestGreenRange then
        local ok, w = pcall(GetQuestGreenRange)
        gruen = ok and type(w) == "number" and w or nil
    end
    gruen = gruen or (meineStufe <= 5 and 5 or math.floor(meineStufe / 10) + 5)
    if -d <= gruen then
        return { 0.25, 0.75, 0.25 }
    end
    return { 0.5, 0.5, 0.5 }
end

-- Aktive Quest im Questlog des Spiels zeigen (oeffnet nur ein Fenster)
function O.QuestlogOeffnen(questID)
    if InCombatLockdown and InCombatLockdown() then
        Melden("Im Kampf lässt sich das Questlog nicht öffnen.")
        return
    end
    if QuestMapFrame_OpenToQuestDetails and pcall(QuestMapFrame_OpenToQuestDetails, questID) then
        return
    end
    local index
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        index = C_QuestLog.GetLogIndexForQuestID(questID)
    elseif GetQuestLogIndexByID then
        index = GetQuestLogIndexByID(questID)
    end
    if index and QuestLog_OpenToQuest and pcall(QuestLog_OpenToQuest, index) then
        return
    end
    if ToggleQuestLog then
        ToggleQuestLog()
    end
end

-- Spiel-Look fuer das Hauptfenster: Metallrahmen mit rundem Bild, Seitenreiter rechts
function O.RahmenBauen(f)
    local r = CreateFrame("Frame", nil, f)
    r:SetAllPoints()
    r:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
    local ok = NineSliceUtil and NineSliceUtil.ApplyLayoutByName and pcall(NineSliceUtil.ApplyLayoutByName, r, "PortraitFrameTemplate")
    if not ok then
        local function teil(atlas, ...)
            local t = r:CreateTexture(nil, "OVERLAY")
            O.Atlas(t, atlas, true)
            t:SetPoint(...)
            return t
        end
        local tl = teil("UI-Frame-PortraitMetal-CornerTopLeft", "TOPLEFT", -13, 16)
        local tr = teil("UI-Frame-Metal-CornerTopRight", "TOPRIGHT", 4, 16)
        local bl = teil("UI-Frame-Metal-CornerBottomLeft", "BOTTOMLEFT", -13, -3)
        local br = teil("UI-Frame-Metal-CornerBottomRight", "BOTTOMRIGHT", 4, -3)
        local function kante(atlas, a, b, quer)
            local t = r:CreateTexture(nil, "OVERLAY")
            O.Atlas(t, atlas, true)
            t:SetPoint("TOPLEFT", a, quer and "TOPRIGHT" or "BOTTOMLEFT")
            t:SetPoint("BOTTOMRIGHT", b, quer and "BOTTOMLEFT" or "TOPRIGHT")
            if quer and t.SetHorizTile then
                t:SetHorizTile(true)
            elseif t.SetVertTile then
                t:SetVertTile(true)
            end
        end
        kante("_UI-Frame-Metal-EdgeTop", tl, tr, true)
        kante("_UI-Frame-Metal-EdgeBottom", bl, br, true)
        kante("!UI-Frame-Metal-EdgeLeft", tl, bl, false)
        kante("!UI-Frame-Metal-EdgeRight", tr, br, false)
    end
    -- rundes Bild oben links (liegt unter dem Ring des Rahmens)
    f.rundbild = f:CreateTexture(nil, "ARTWORK", nil, 7)
    f.rundbild:SetSize(62, 62)
    f.rundbild:SetPoint("TOPLEFT", -5, 7)
    f.rundbild:SetTexture(O.ICON)
    if f.CreateMaskTexture and f.rundbild.AddMaskTexture then
        local m = f:CreateMaskTexture()
        if m then
            m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(f.rundbild)
            f.rundbild:AddMaskTexture(m)
        end
    end
    r.titel = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.titel:SetPoint("TOP", 0, -5)
    r.titel:SetText("Reiseführer")
    -- Seitenreiter rechts aussen
    f.seiten = {}
    local liste = {
        { "quests", "Interface\\Icons\\INV_Misc_Note_01", "Quests" },
        { "rezepte", "Interface\\Icons\\INV_Scroll_03", "Rezepte" },
        { "faehigkeiten", "Interface\\Icons\\INV_Misc_Book_11", "Fähigkeiten" },
        { "notizen", "Interface\\Icons\\INV_Misc_Book_09", "Notizen" },
    }
    for i, e in ipairs(liste) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(55, 60)
        b:SetPoint("TOPLEFT", f, "TOPRIGHT", -2, -44 - (i - 1) * 62)
        b.wert = e[1]
        b.hg = b:CreateTexture(nil, "BACKGROUND")
        b.hg:SetAllPoints()
        O.Atlas(b.hg, "common-sidetab")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(34, 34)
        b.icon:SetPoint("CENTER", -3, 0)
        b.icon:SetTexture(e[2])
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.wahl = b:CreateTexture(nil, "OVERLAY")
        b.wahl:SetAllPoints()
        O.Atlas(b.wahl, "common-sidetab-selected")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        if not O.Atlas(hl, "common-sidetab-hover") then
            hl:SetColorTexture(1, 1, 1, 0.1)
        end
        -- kleine Zahl unten rechts am Symbol (offene Quests, lernbare Rezepte ...)
        b.zahl = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.zahl:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 1, 1)
        b.zahl:SetText("")
        local name = e[3]
        b:SetScript("OnClick", function()
            fensterReiter = b.wert
            if f.scroll and f.scroll.SetVerticalScroll then
                f.scroll:SetVerticalScroll(0)
            end
            FensterAktualisieren()
        end)
        b:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(name, 1, 0.82, 0)
                if self.tipp then
                    GameTooltip:AddLine(self.tipp, 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        f.seiten[i] = b
    end
    return r
end

-- Lage der Bedienelemente.
-- Spiel-Look (Vorlage A): Zeile 1 Charakter + "Zeigen", Zeile 2 Gebiet bzw. Beruf + Sortierung,
-- darunter das schmale Banner und die Liste. Klassisch: Aufbau wie bisher.
function O.Lage(f, spiel)
    local function setze(el, ...)
        if el then
            el:ClearAllPoints()
            el:SetPoint(...)
        end
    end
    local function breite(el, w)
        if el and w then
            el:SetWidth(w)
        end
    end
    f.zu:ClearAllPoints()
    if spiel then
        f.zu:SetPoint("TOPRIGHT", 1, 0)
        f.zu:SetFrameLevel((f:GetFrameLevel() or 1) + 45)
    else
        f.zu:SetPoint("TOPRIGHT", -4, -4)
    end
    f.buchKnopf:ClearAllPoints()
    f.buchKnopf:SetPoint("RIGHT", f.zu, "LEFT", -4, 0)
    f.kopf:ClearAllPoints()
    if spiel then
        local Z1, Z2, BANNER, LISTE = -30, -60, -90, -136
        setze(f.charWahl, "TOPLEFT", f, "TOPLEFT", 66, Z1)
        breite(f.charWahl, 205)
        f.charWahl:SetHeight(24)
        for _, el in ipairs({ f.questFilter, f.rezFilter, f.fertFilter }) do
            setze(el, "TOPLEFT", f, "TOPLEFT", 277, Z1)
            breite(el, 211)
        end
        for _, el in ipairs({ f.rezBerufWahl, f.fertKatWahl }) do
            setze(el, "TOPLEFT", f, "TOPLEFT", 12, Z2)
            breite(el, 290)
        end
        for _, el in ipairs({ f.rezSort, f.fertSort }) do
            setze(el, "TOPLEFT", f, "TOPLEFT", 308, Z2)
            breite(el, 180)
        end
        -- Gebiet ueber die volle Breite, ohne Blaetter-Pfeile
        f.gebietWahl:ClearAllPoints()
        f.gebietWahl:SetPoint("TOPLEFT", f, "TOPLEFT", 12, Z2)
        f.gebietWahl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, Z2)
        f.gebietLinks:Hide()
        f.gebietRechts:Hide()
        f.kopf:SetPoint("TOPLEFT", f, "TOPLEFT", 12, BANNER)
        f.kopf:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, BANNER)
        f.info:Hide()
        f.scroll:ClearAllPoints()
        f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, LISTE - 4)
        f.scroll:SetPoint("BOTTOMRIGHT", -32, 14)
        if f.listeHg then
            f.listeHg:ClearAllPoints()
            f.listeHg:SetPoint("TOPLEFT", f, "TOPLEFT", 8, LISTE)
            f.listeHg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
        end
        if Notizbuch then
            Notizbuch:ClearAllPoints()
            Notizbuch:SetPoint("TOPLEFT", f, "TOPLEFT", 12, Z2)
            Notizbuch:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
        end
    else
        setze(f.charWahl, "TOPLEFT", 150, -9)
        breite(f.charWahl, 300)
        f.charWahl:SetHeight(22)
        f.kopf:SetPoint("TOPLEFT", 10, -38)
        f.kopf:SetPoint("TOPRIGHT", -10, -38)
        for _, e in ipairs({ { f.rezBerufWahl, 0, 196 }, { f.rezFilter, 200, 136 }, { f.rezSort, 340, 140 },
            { f.fertKatWahl, 0, 196 }, { f.fertFilter, 200, 136 }, { f.fertSort, 340, 140 } }) do
            setze(e[1], "TOPLEFT", f.kopf, "BOTTOMLEFT", e[2], -36)
            breite(e[1], e[3])
        end
        -- Gebiet mit Pfeilen, rechts daneben "Zeigen"
        setze(f.questFilter, "TOPRIGHT", f.kopf, "BOTTOMRIGHT", 0, -36)
        breite(f.questFilter, 140)
        setze(f.gebietLinks, "TOPLEFT", f.kopf, "BOTTOMLEFT", 0, -35)
        setze(f.gebietRechts, "TOPRIGHT", f.kopf, "BOTTOMRIGHT", -146, -35)
        f.gebietWahl:ClearAllPoints()
        f.gebietWahl:SetPoint("LEFT", f.gebietLinks, "RIGHT", 2, 0)
        f.gebietWahl:SetPoint("RIGHT", f.gebietRechts, "LEFT", -2, 0)
        f.info:ClearAllPoints()
        f.info:SetPoint("TOPLEFT", f.kopf, "BOTTOMLEFT", 4, -66)
        f.info:SetPoint("TOPRIGHT", f.kopf, "BOTTOMRIGHT", -4, -66)
        f.info:Show()
        f.scroll:ClearAllPoints()
        f.scroll:SetPoint("TOPLEFT", f.kopf, "BOTTOMLEFT", 0, -84)
        f.scroll:SetPoint("BOTTOMRIGHT", -32, 14)
        if f.listeHg then
            f.listeHg:ClearAllPoints()
            f.listeHg:SetPoint("TOPLEFT", f.kopf, "BOTTOMLEFT", -4, -80)
            f.listeHg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
        end
        if Notizbuch then
            Notizbuch:ClearAllPoints()
            Notizbuch:SetPoint("TOPLEFT", f.kopf, "BOTTOMLEFT", 0, -36)
            Notizbuch:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
        end
    end
    O.BannerLage(f, spiel)
end

-- Banner: Spiel-Look schmal (Name, Stufe, EP in einer Zeile, duenner Balken), klassisch gross
function O.BannerLage(f, spiel)
    local kopf, b = f.kopf, f.balken
    kopf:SetHeight(spiel and 40 or 112)
    for _, el in ipairs({ f.portraitRahmen, f.levelZahl, f.levelText, f.unter, f.epText, kopf.glanz, b.text }) do
        el:SetShown(not spiel)
    end
    f.bannerMitte:SetShown(spiel and true or false)
    f.bannerRechts:SetShown(spiel and true or false)
    f.name:ClearAllPoints()
    b:ClearAllPoints()
    if spiel then
        if f.name.SetFontObject then
            f.name:SetFontObject("GameFontNormal")
        end
        f.name:SetPoint("TOPLEFT", kopf, "TOPLEFT", 8, -7)
        b:SetPoint("BOTTOMLEFT", 8, 7)
        b:SetPoint("BOTTOMRIGHT", -8, 7)
        b:SetHeight(6)
    else
        if f.name.SetFontObject then
            f.name:SetFontObject("GameFontNormalHuge")
        end
        f.name:SetPoint("TOPLEFT", f.portraitRahmen, "TOPRIGHT", 12, -4)
        b:SetPoint("BOTTOMLEFT", 12, 24)
        b:SetPoint("BOTTOMRIGHT", -12, 24)
        b:SetHeight(16)
    end
end

function O.FensterLook(f)
    f.spielHg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.spielHg:SetPoint("TOPLEFT", 2, -2)
    f.spielHg:SetPoint("BOTTOMRIGHT", -2, 2)
    f.spielHg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
    f.spielHg:Hide()
    f.listeHg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    f.listeHg:Hide()
    f.kopf.spielRand = f.kopf:CreateTexture(nil, "OVERLAY")
    f.kopf.spielRand:SetPoint("TOPLEFT", -3, 3)
    f.kopf.spielRand:SetPoint("BOTTOMRIGHT", 3, -3)
    f.kopf.spielRand:Hide()
    O.Teil(function(spiel)
        if spiel and type(f.spielRahmen) ~= "table" then
            f.spielRahmen = O.RahmenBauen(f)
        end
        if type(f.spielRahmen) == "table" then
            f.spielRahmen:SetShown(spiel and true or false)
            f.rundbild:SetShown(spiel and true or false)
            for _, b in ipairs(f.seiten) do
                b:SetShown(spiel and true or false)
            end
        end
        if f.SetBackdrop then
            f:SetBackdrop(not spiel and K.BACKDROP_RAHMEN or nil)
        end
        -- Hintergruende wie in Guild ERP: Holz fuer das Fenster, dunkle Liste, Rahmen um das Banner
        f.spielHg:ClearAllPoints()
        if spiel and O.Atlas(f.spielHg, "Profession-Background-Template2") then
            f.spielHg:SetVertexColor(1, 1, 1, 1)
        else
            f.spielHg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
        end
        f.spielHg:SetPoint("TOPLEFT", 2, -2)
        f.spielHg:SetPoint("BOTTOMRIGHT", -2, 2)
        f.spielHg:SetShown(spiel and true or false)
        f.listeHg:SetShown(spiel and O.Atlas(f.listeHg, "Professions-background-summarylist") or false)
        f.kopf.spielRand:SetShown(spiel and O.Atlas(f.kopf.spielRand, "common-insideframe") or false)
        if f.kopf.SetBackdrop then
            f.kopf:SetBackdrop(K.BACKDROP_DUENN)
        end
        f.buchKnopf:Hide() -- Notizen haben jetzt einen eigenen Reiter
        f.titel:SetShown(not spiel)
        for _, r in ipairs(f.reiter) do
            r:SetShown(not spiel)
        end
        O.Lage(f, spiel)
        f:SetHeight(spiel and 638 or 650)
        if Notizbuch and Notizbuch.LookSetzen then
            Notizbuch:LookSetzen(spiel)
        end
    end)
end

-- Seitenreiter markieren
function O.SeitenSync(f)
    for _, b in ipairs(type(f.seiten) == "table" and f.seiten or {}) do
        b.wahl:SetShown(b.wert == fensterReiter)
    end
end

-- Auswahlknopf und Gruppenkopf im Spiel-Look
function O.WahlLook(b, spiel)
    if spiel and type(b.spielHg) ~= "table" then
        b.spielHg = b:CreateTexture(nil, "BACKGROUND")
        b.spielHg:SetAllPoints()
        b.spielOk = O.Atlas(b.spielHg, "common-dropdown-b-button")
    end
    local an = spiel and b.spielOk == true
    if type(b.spielHg) == "table" then
        b.spielHg:SetShown(an and true or false)
    end
    if b.SetBackdrop then
        if an then
            b:SetBackdrop(nil)
        else
            b:SetBackdrop(K.BACKDROP_KARTE)
            b:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Auswahlliste: Knopf, der eine Liste aufklappt (wie die Gebietswahl).
-- eintraege() liefert { {wert=, text=, rechts=, icon=, gewaehlt=}, {kopf="Text"}, ... }
-- und optional einen Fusstext als zweiten Wert.
-- ---------------------------------------------------------------------------
local alleAuswahllisten = {}
local function AuswahllistenZu(ausser)
    for _, l in ipairs(alleAuswahllisten) do
        if l ~= ausser then
            l:Hide()
        end
    end
end

AuswahlBauen = function(eltern, breite, listeBreite, rechtsBuendig, eintraege, waehlen)
    local b = CreateFrame("Button", nil, eltern, K.BACKDROP_VORLAGE)
    b:SetSize(breite, 24)
    if b.SetBackdrop then
        b:SetBackdrop(K.BACKDROP_KARTE)
        b:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:Hide()
    b.text = Schrift(b, "GameFontNormalSmall")
    b.text:SetPoint("RIGHT", b, "RIGHT", -20, 0)
    if b.text.SetWordWrap then
        b.text:SetWordWrap(false)
    end
    local pfeil = b:CreateTexture(nil, "ARTWORK")
    pfeil:SetSize(14, 14)
    pfeil:SetPoint("RIGHT", -4, 0)
    pfeil:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    if pfeil.SetRotation then
        pfeil:SetRotation(-math.pi / 2)
    end
    -- Anzeige im Knopf setzen (mit oder ohne Symbol)
    b.Setzen = function(self, text, icon)
        self.text:ClearAllPoints()
        self.text:SetPoint("RIGHT", self, "RIGHT", -20, 0)
        if icon then
            self.icon:SetTexture(icon)
            self.icon:Show()
            self.text:SetPoint("LEFT", self.icon, "RIGHT", 5, 0)
        else
            self.icon:Hide()
            self.text:SetPoint("LEFT", self, "LEFT", 8, 0)
        end
        self.text:SetText(text or "")
    end

    local l = CreateFrame("Frame", nil, eltern, K.BACKDROP_VORLAGE)
    if rechtsBuendig then
        l:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2)
    else
        l:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    end
    l:SetWidth(listeBreite or breite)
    l:SetFrameStrata("DIALOG")
    if l.SetBackdrop then
        l:SetBackdrop(K.BACKDROP_KARTE)
        l:SetBackdropColor(0.03, 0.03, 0.04, 0.97)
    end
    l.zeilen = {}
    l.fuss = Schrift(l, "GameFontDisableSmall")
    l:Hide()
    b.liste = l
    table.insert(alleAuswahllisten, l)

    b:SetScript("OnClick", function()
        if l:IsShown() then
            l:Hide()
            return
        end
        AuswahllistenZu(l)
        local liste, fussText = eintraege()
        local fr = Fraktion()
        local y = 6
        for i, e in ipairs(liste) do
            local z = l.zeilen[i]
            if not z then
                z = CreateFrame("Button", nil, l)
                z:SetHeight(20)
                z.icon = z:CreateTexture(nil, "ARTWORK")
                z.icon:SetSize(16, 16)
                z.icon:SetPoint("LEFT", 4, 0)
                z.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                z.text = Schrift(z, "GameFontHighlightSmall")
                z.rechts = Schrift(z, "GameFontHighlightSmall", false)
                z.rechts:SetPoint("RIGHT", -6, 0)
                if z.text.SetWordWrap then
                    z.text:SetWordWrap(false)
                end
                z.hl = z:CreateTexture(nil, "HIGHLIGHT")
                z.hl:SetAllPoints()
                z.hl:SetColorTexture(1, 1, 1, 0.1)
                l.zeilen[i] = z
            end
            z:ClearAllPoints()
            z:SetPoint("TOPLEFT", 4, -y)
            z:SetPoint("RIGHT", -4, 0)
            z.text:ClearAllPoints()
            z.text:SetPoint("RIGHT", z.rechts, "LEFT", -6, 0)
            if e.kopf then
                z.icon:Hide()
                z.text:SetPoint("LEFT", z, "LEFT", 4, 0)
                z.text:SetText(Farbe(fr.hex, e.kopf))
                z.rechts:SetText("")
                z:SetScript("OnClick", nil)
                z:EnableMouse(false)
            else
                z:EnableMouse(true)
                if e.icon then
                    z.icon:SetTexture(e.icon)
                    z.icon:Show()
                    z.text:SetPoint("LEFT", z.icon, "RIGHT", 6, 0)
                else
                    z.icon:Hide()
                    z.text:SetPoint("LEFT", z, "LEFT", 8, 0)
                end
                z.text:SetText((e.gewaehlt and "|cff44dd55" or "|cffffffff") .. (e.text or "") .. "|r")
                z.rechts:SetText(e.rechts or "")
                z:SetScript("OnClick", function()
                    l:Hide()
                    waehlen(e.wert)
                    if Fenster and Fenster.scroll.SetVerticalScroll then
                        Fenster.scroll:SetVerticalScroll(0)
                    end
                    FensterAktualisieren()
                end)
            end
            z:Show()
            y = y + 20
        end
        for j = #liste + 1, #l.zeilen do
            l.zeilen[j]:Hide()
        end
        if fussText then
            l.fuss:ClearAllPoints()
            l.fuss:SetPoint("TOPLEFT", 10, -(y + 2))
            l.fuss:SetText(fussText)
            l.fuss:Show()
            y = y + 18
        else
            l.fuss:Hide()
        end
        l:SetHeight(y + 6)
        l:Show()
    end)
    O.Teil(function(spiel) O.WahlLook(b, spiel) end)
    return b
end

-- ---------------------------------------------------------------------------
-- Fenster
-- ---------------------------------------------------------------------------
local function FensterBauen()
    local f = CreateFrame("Frame", "ForeverDashboardFenster", UIParent, K.BACKDROP_VORLAGE)
    f:SetSize(500, 650)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop(K.BACKDROP_RAHMEN)
    end
    local pos = ForeverDashboardData.settings and ForeverDashboardData.settings.window
    if pos then
        f:SetPoint(pos.punkt or "CENTER", UIParent, pos.relPunkt or "CENTER", pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end
    table.insert(UISpecialFrames, "ForeverDashboardFenster") -- mit Esc schliessen

    -- Kopf-Banner (zum Verschieben anfassen)
    local kopf = CreateFrame("Frame", nil, f, K.BACKDROP_VORLAGE)
    kopf:SetPoint("TOPLEFT", 10, -38)
    kopf:SetPoint("TOPRIGHT", -10, -38)
    kopf:SetHeight(112)
    if kopf.SetBackdrop then
        kopf:SetBackdrop(K.BACKDROP_DUENN)
    end
    -- Verschieben: am ganzen Fenster (Titelleiste, Rand, freie Flaechen) und am Banner
    local function ziehenStart()
        f:StartMoving()
    end
    local function ziehenEnde()
        f:StopMovingOrSizing()
        local punkt, _, relPunkt, x, y = f:GetPoint()
        ForeverDashboardData.settings = ForeverDashboardData.settings or {}
        ForeverDashboardData.settings.window = { punkt = punkt, relPunkt = relPunkt, x = x, y = y }
    end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", ziehenStart)
    f:SetScript("OnDragStop", ziehenEnde)
    kopf:EnableMouse(true)
    kopf:RegisterForDrag("LeftButton")
    kopf:SetScript("OnDragStart", ziehenStart)
    kopf:SetScript("OnDragStop", ziehenEnde)
    kopf.glanz = kopf:CreateTexture(nil, "BORDER")
    kopf.glanz:SetPoint("TOPLEFT", 1, -1)
    kopf.glanz:SetPoint("TOPRIGHT", -1, -1)
    kopf.glanz:SetHeight(40)
    kopf.glanz:SetColorTexture(1, 1, 1, 0.06)
    f.kopf = kopf

    -- Porträt mit Rahmen
    local rahmen = CreateFrame("Frame", nil, kopf, K.BACKDROP_VORLAGE)
    rahmen:SetSize(64, 64)
    rahmen:SetPoint("TOPLEFT", 12, -12)
    if rahmen.SetBackdrop then
        rahmen:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        rahmen:SetBackdropColor(0, 0, 0, 1)
    end
    f.portraitRahmen = rahmen
    f.portrait = rahmen:CreateTexture(nil, "ARTWORK")
    f.portrait:SetPoint("TOPLEFT", 3, -3)
    f.portrait:SetPoint("BOTTOMRIGHT", -3, 3)

    f.name = Schrift(kopf, "GameFontNormalHuge")
    f.name:SetPoint("TOPLEFT", rahmen, "TOPRIGHT", 12, -4)
    f.unter = Schrift(kopf, "GameFontHighlightSmall")
    f.unter:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)

    -- Level-Abzeichen rechts
    f.levelZahl = Schrift(kopf, "GameFontNormalHuge", false)
    f.levelZahl:SetPoint("TOPRIGHT", -16, -14)
    f.levelText = Schrift(kopf, "GameFontDisableSmall", false)
    f.levelText:SetPoint("TOPRIGHT", f.levelZahl, "BOTTOMRIGHT", 0, -2)
    f.levelText:SetText("LEVEL")

    -- schmales Banner (Spiel-Look): Stufe und EP mittig, Quest-EP rechts; Details im Tooltip
    f.bannerRechts = Schrift(kopf, "GameFontHighlightSmall", false)
    f.bannerRechts:SetPoint("TOPRIGHT", kopf, "TOPRIGHT", -8, -8)
    if f.bannerRechts.SetWordWrap then
        f.bannerRechts:SetWordWrap(false)
    end
    f.bannerMitte = Schrift(kopf, "GameFontHighlightSmall")
    f.bannerMitte:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
    f.bannerMitte:SetPoint("RIGHT", f.bannerRechts, "LEFT", -8, 0)
    if f.bannerMitte.SetWordWrap then
        f.bannerMitte:SetWordWrap(false)
    end
    f.bannerMitte:Hide()
    f.bannerRechts:Hide()
    kopf:SetScript("OnEnter", function(self)
        if O.Spiel() and GameTooltip and type(f.bannerTipp) == "table" then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            for i, zeile in ipairs(f.bannerTipp) do
                if i == 1 then
                    GameTooltip:AddLine(zeile, 1, 0.82, 0)
                else
                    GameTooltip:AddLine(zeile, 1, 1, 1, true)
                end
            end
            GameTooltip:Show()
        end
    end)
    kopf:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Schliessen-Knopf
    local zu = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    zu:SetPoint("TOPRIGHT", -4, -4)
    zu:SetScript("OnClick", function() f:Hide() end)
    f.zu = zu

    -- Werkzeugleiste: Titel, Charakterwahl (Auswahlliste), Notizbuch
    f.titel = Schrift(f, "GameFontNormal")
    f.titel:SetPoint("TOPLEFT", 16, -14)
    f.titel:SetText("Reiseführer")
    local wahl = CreateFrame("Button", nil, f, K.BACKDROP_VORLAGE)
    wahl:SetSize(190, 22)
    wahl:SetPoint("TOPLEFT", 150, -9)
    if wahl.SetBackdrop then
        wahl:SetBackdrop(K.BACKDROP_KARTE)
        wahl:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
    end
    wahl.text = Schrift(wahl, "GameFontHighlightSmall")
    wahl.text:SetPoint("LEFT", 8, 0)
    wahl.text:SetPoint("RIGHT", -22, 0)
    if wahl.text.SetWordWrap then
        wahl.text:SetWordWrap(false)
    end
    wahl.pfeil = wahl:CreateTexture(nil, "ARTWORK")
    wahl.pfeil:SetSize(16, 16)
    wahl.pfeil:SetPoint("RIGHT", -4, 0)
    wahl.pfeil:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    if wahl.pfeil.SetRotation then
        wahl.pfeil:SetRotation(-math.pi / 2)
    end
    local hlw = wahl:CreateTexture(nil, "HIGHLIGHT")
    hlw:SetPoint("TOPLEFT", 3, -3)
    hlw:SetPoint("BOTTOMRIGHT", -3, 3)
    hlw:SetColorTexture(1, 1, 1, 0.08)
    f.charWahl = wahl
    -- aufklappende Liste der eigenen Charaktere
    local liste = CreateFrame("Frame", nil, f, K.BACKDROP_VORLAGE)
    liste:SetPoint("TOPLEFT", wahl, "BOTTOMLEFT", 0, -2)
    liste:SetWidth(240)
    liste:SetFrameStrata("DIALOG")
    if liste.SetBackdrop then
        liste:SetBackdrop(K.BACKDROP_KARTE)
        liste:SetBackdropColor(0.03, 0.03, 0.04, 0.97)
    end
    liste:Hide()
    liste.knoepfe = {}
    f.charListe = liste
    table.insert(alleAuswahllisten, liste)
    wahl:SetScript("OnClick", function()
        if liste:IsShown() then
            liste:Hide()
            return
        end
        AuswahllistenZu(liste)
        local eigen = CharakterSchluessel()
        local schluessel = {}
        for k in pairs(ForeverDashboardData.characters or {}) do
            table.insert(schluessel, k)
        end
        table.sort(schluessel, function(a, b)
            if a == eigen then
                return true
            elseif b == eigen then
                return false
            end
            local la, lb = ForeverDashboardData.characters[a].level or 0, ForeverDashboardData.characters[b].level or 0
            if la ~= lb then
                return la > lb
            end
            return a < b
        end)
        for i, k in ipairs(schluessel) do
            local c = ForeverDashboardData.characters[k]
            local b = liste.knoepfe[i]
            if not b then
                b = CreateFrame("Button", nil, liste)
                b:SetHeight(20)
                b.text = Schrift(b, "GameFontHighlightSmall")
                b.text:SetPoint("LEFT", 8, 0)
                b.text:SetPoint("RIGHT", -8, 0)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.1)
                liste.knoepfe[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
            b:SetPoint("RIGHT", -4, 0)
            local name = c.fullName or c.name or k
            local gewaehlt = (fensterChar or eigen) == k
            b.text:SetText((gewaehlt and "|cff44dd55> |r" or "   ") .. name
                .. "|cff9d9d9d  (" .. (c.level or "?") .. ")" .. (k == eigen and "  - gerade gespielt" or "") .. "|r")
            b:SetScript("OnClick", function()
                fensterChar = (k ~= eigen) and k or nil
                fensterGebiet = nil
                liste:Hide()
                FensterAktualisieren()
            end)
            b:Show()
        end
        for i = #schluessel + 1, #liste.knoepfe do
            liste.knoepfe[i]:Hide()
        end
        liste:SetHeight(8 + #schluessel * 20)
        liste:Show()
    end)

    -- Notizbuch-Knopf
    local buchKnopf = CreateFrame("Button", nil, f, K.BACKDROP_VORLAGE)
    buchKnopf:SetSize(110, 22)
    buchKnopf:SetPoint("RIGHT", zu, "LEFT", -4, 0)
    if buchKnopf.SetBackdrop then
        buchKnopf:SetBackdrop(K.BACKDROP_KARTE)
        buchKnopf:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
    end
    buchKnopf.icon = buchKnopf:CreateTexture(nil, "ARTWORK")
    buchKnopf.icon:SetSize(16, 16)
    buchKnopf.icon:SetPoint("LEFT", 6, 0)
    buchKnopf.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    buchKnopf.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    buchKnopf.text = Schrift(buchKnopf, "GameFontNormalSmall")
    buchKnopf.text:SetPoint("LEFT", buchKnopf.icon, "RIGHT", 6, 0)
    buchKnopf.text:SetText("Notizbuch")
    local hlb = buchKnopf:CreateTexture(nil, "HIGHLIGHT")
    hlb:SetPoint("TOPLEFT", 3, -3)
    hlb:SetPoint("BOTTOMRIGHT", -3, 3)
    hlb:SetColorTexture(1, 1, 1, 0.08)
    buchKnopf:SetScript("OnClick", function()
        NotizbuchUmschalten()
    end)
    f.buchKnopf = buchKnopf

    -- Levelbalken
    local balken = CreateFrame("Frame", nil, kopf, K.BACKDROP_VORLAGE)
    balken:SetPoint("BOTTOMLEFT", 12, 24)
    balken:SetPoint("BOTTOMRIGHT", -12, 24)
    balken:SetHeight(16)
    if balken.SetBackdrop then
        balken:SetBackdrop(K.BACKDROP_DUENN)
        balken:SetBackdropColor(0, 0, 0, 0.7)
    end
    local function teil(r, g, b, a, schicht)
        local t = balken:CreateTexture(nil, schicht or "ARTWORK")
        t:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        t:SetVertexColor(r, g, b, a)
        t:Hide()
        return t
    end
    balken.cur = teil(0.58, 0.32, 0.86, 1)
    balken.ready = teil(0.20, 0.80, 0.30, 1)
    balken.open = teil(0.20, 0.80, 0.30, 0.45)
    balken.rest = balken:CreateTexture(nil, "OVERLAY")
    balken.rest:SetColorTexture(0.5, 0.72, 1, 1)
    balken.rest:Hide()
    balken.text = Schrift(balken, "TextStatusBarText")
    balken.text:SetJustifyH("CENTER")
    balken.text:SetPoint("CENTER", 0, 0)
    f.balken = balken
    f.epText = Schrift(kopf, "GameFontHighlightSmall")
    f.epText:SetPoint("TOPLEFT", balken, "BOTTOMLEFT", 0, -4)
    f.epText:SetPoint("TOPRIGHT", balken, "BOTTOMRIGHT", 0, -4)

    -- Reiter (eigene Knoepfe im Stil von Karteikarten)
    local function reiter(text, wert, x)
        local b = CreateFrame("Button", nil, f, K.BACKDROP_VORLAGE)
        b:SetSize(117, 26)
        b:SetPoint("TOPLEFT", kopf, "BOTTOMLEFT", x, -6)
        if b.SetBackdrop then
            b:SetBackdrop(K.BACKDROP_KARTE)
        end
        b.text = Schrift(b, "GameFontNormal")
        b.text:SetJustifyH("CENTER")
        b.text:SetPoint("CENTER", 0, 0)
        b.text:SetText(text)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 4, -4)
        hl:SetPoint("BOTTOMRIGHT", -4, 4)
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.wert = wert
        b:SetScript("OnClick", function()
            fensterReiter = wert
            if Fenster.scroll.SetVerticalScroll then
                Fenster.scroll:SetVerticalScroll(0)
            end
            FensterAktualisieren()
        end)
        return b
    end
    f.reiter = { reiter("Quests", "quests", 0), reiter("Rezepte", "rezepte", 121), reiter("Fähigkeiten", "faehigkeiten", 242),
        reiter("Notizen", "notizen", 363) }

    -- Zweite Zeile: Auswahllisten (je nach Reiter)
    local function speichern(feld, wert)
        ForeverDashboardData.settings = ForeverDashboardData.settings or {}
        ForeverDashboardData.settings[feld] = wert
    end
    local function zeile2(b, x)
        b:SetPoint("TOPLEFT", kopf, "BOTTOMLEFT", x, -36)
        return b
    end
    -- Rezepte: Beruf
    f.rezBerufWahl = zeile2(AuswahlBauen(f, 196, 300, false, function()
        local liste = { { wert = false, text = "Alle Berufe", icon = "Interface\\Icons\\INV_Misc_Book_09", gewaehlt = rezBeruf == nil,
            rechts = Farbe("44dd55", (rezUebersicht.summen.jetzt or 0) .. " lernbar") } }
        if #rezUebersicht.berufe > 0 then
            table.insert(liste, { kopf = "Berufe" })
        end
        for _, info in ipairs(rezUebersicht.berufe) do
            table.insert(liste, {
                wert = info.beruf, icon = K.BERUF_ICON[info.beruf] or K.ICON_UNBEKANNT, gewaehlt = rezBeruf == info.beruf,
                text = info.beruf .. Farbe("9d9d9d", "  " .. (info.wert and (info.wert .. (info.max and info.max > 0 and ("/" .. info.max) or "")) or "?")),
                rechts = (info.jetzt > 0 and Farbe("44dd55", info.jetzt .. " lernbar  ") or "")
                    .. (info.spaeter > 0 and Farbe("ffaa00", info.spaeter .. " später") or ""),
            })
        end
        return liste
    end, function(wert)
        rezBeruf = wert or nil
        speichern("rezBeruf", rezBeruf or false)
    end), 0)
    -- Rezepte: Zeigen
    f.rezFilter = zeile2(AuswahlBauen(f, 136, 190, false, function()
        local liste = {}
        for _, w in ipairs(K.REZ_FILTER) do
            local anzahl = w == "alle" and ((rezUebersicht.summen.jetzt or 0) + (rezUebersicht.summen.spaeter or 0))
                or (rezUebersicht.summen[w] or 0)
            table.insert(liste, { wert = w, text = Farbe(K.REZ_FILTER_FARBE[w], K.REZ_FILTER_TEXT[w]), gewaehlt = rezFilter == w,
                rechts = Farbe("9d9d9d", anzahl) })
        end
        return liste
    end, function(wert)
        rezFilter = wert
        speichern("rezFilter", wert)
    end), 200)
    -- Rezepte: Sortieren
    f.rezSort = zeile2(AuswahlBauen(f, 140, 190, true, function()
        local liste = {}
        for _, w in ipairs(K.REZ_SORT) do
            table.insert(liste, { wert = w, text = K.REZ_SORT_TEXT[w], gewaehlt = rezSort == w })
        end
        return liste
    end, function(wert)
        rezSort = wert
        speichern("rezSort", wert)
    end), 340)
    -- Faehigkeiten: Kategorie
    f.fertKatWahl = zeile2(AuswahlBauen(f, 196, 300, false, function()
        local liste = { { wert = false, text = "Alle Kategorien", icon = K.ICON_FAEHIGKEIT, gewaehlt = fertKategorie == nil,
            rechts = Farbe("44dd55", (fertUebersicht.summen.jetzt or 0) .. " lernbar") } }
        if #fertUebersicht.kategorien > 0 then
            table.insert(liste, { kopf = "Kategorien" })
        end
        for _, info in ipairs(fertUebersicht.kategorien) do
            table.insert(liste, {
                wert = info.name, icon = info.icon or K.ICON_FAEHIGKEIT, gewaehlt = fertKategorie == info.name, text = info.name,
                rechts = (info.jetzt > 0 and Farbe("44dd55", info.jetzt .. " lernbar  ") or "")
                    .. (info.bald > 0 and Farbe("4aa3ff", info.bald .. " bald  ") or "")
                    .. (info.spaeter > 0 and Farbe("ffaa00", info.spaeter .. " später") or ""),
            })
        end
        return liste
    end, function(wert)
        fertKategorie = wert or nil
    end), 0)
    -- Faehigkeiten: Zeigen
    f.fertFilter = zeile2(AuswahlBauen(f, 136, 210, false, function()
        local liste = {}
        for _, w in ipairs(K.FERT_FILTER) do
            local g = K.FERT_GRUPPE[w]
            local anzahl = 0
            if w == "alle" then
                for art, v in pairs(fertUebersicht.summen) do
                    if art ~= "gelernt" then
                        anzahl = anzahl + v
                    end
                end
            else
                anzahl = fertUebersicht.summen[w] or 0
            end
            table.insert(liste, { wert = w, text = g and Farbe(g.hex, g.text) or "Alle zeigen", gewaehlt = fertFilter == w,
                rechts = Farbe("9d9d9d", anzahl) })
        end
        return liste, "\"Bald\" = in den nächsten " .. K.FERT_BALD .. " Stufen"
    end, function(wert)
        fertFilter = wert
        speichern("fertFilter", wert)
    end), 200)
    -- Faehigkeiten: Sortieren
    f.fertSort = zeile2(AuswahlBauen(f, 140, 190, true, function()
        local liste = {}
        for _, w in ipairs(K.FERT_SORT) do
            table.insert(liste, { wert = w, text = K.FERT_SORT_TEXT[w], gewaehlt = fertSort == w })
        end
        return liste
    end, function(wert)
        fertSort = wert
        speichern("fertSort", wert)
    end), 340)
    if ForeverDashboardData.settings then
        local e = ForeverDashboardData.settings
        rezFilter = e.rezFilter or rezFilter
        rezSort = e.rezSort or rezSort
        rezBeruf = e.rezBeruf or nil
        fertFilter = e.fertFilter or fertFilter
        fertSort = e.fertSort or fertSort
    end
    -- alte Einstellungen, die es nicht mehr gibt, abfangen
    if not K.REZ_FILTER_TEXT[rezFilter] then rezFilter = "alle" end
    if not K.REZ_SORT_TEXT[rezSort] then rezSort = "wert" end
    if not K.FERT_SORT_TEXT[fertSort] then fertSort = "stufe" end
    if fertFilter ~= "alle" and (not K.FERT_GRUPPE[fertFilter] or fertFilter == "gelernt") then fertFilter = "alle" end

    -- Quests: Zeigen (mit Anzahl je Status im aktuellen Gebiet)
    if ForeverDashboardData.settings and O.QUEST_FILTER_TEXT[ForeverDashboardData.settings.questFilter or ""] then
        O.questFilter = ForeverDashboardData.settings.questFilter
    end
    f.questFilter = AuswahlBauen(f, 140, 211, false, function()
        local liste, z = {}, O.questZaehler or {}
        for _, w in ipairs(O.QUEST_FILTER) do
            local anzahl = w == "alle" and ((z.abgabebereit or 0) + (z.aktiv or 0) + (z.verfuegbar or 0) + (z.gesperrt or 0) + (z.zuhoch or 0))
                or (z[w] or 0)
            local st = K.STATUS[w]
            table.insert(liste, { wert = w, gewaehlt = O.questFilter == w, rechts = Farbe("9d9d9d", anzahl),
                text = st and Farbe(st.hex, O.QUEST_FILTER_TEXT[w]) or O.QUEST_FILTER_TEXT[w] })
        end
        return liste, "Zahlen gelten für das gewählte Gebiet"
    end, function(wert)
        O.questFilter = wert
        speichern("questFilter", wert)
    end)

    -- Gebietswahl
    local function pfeil(textur, punkt, x)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(26, 26)
        b:SetPoint("TOP" .. punkt, kopf, "BOTTOM" .. punkt, x, -35)
        b:SetNormalTexture(textur .. "-Up")
        b:SetPushedTexture(textur .. "-Down")
        b:SetDisabledTexture(textur .. "-Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        return b
    end
    f.gebietLinks = pfeil("Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "LEFT", 0)
    f.gebietRechts = pfeil("Interface\\Buttons\\UI-SpellbookIcon-NextPage", "RIGHT", 0)
    local gwahl = CreateFrame("Button", nil, f, K.BACKDROP_VORLAGE)
    gwahl:SetPoint("LEFT", f.gebietLinks, "RIGHT", 2, 0)
    gwahl:SetPoint("RIGHT", f.gebietRechts, "LEFT", -2, 0)
    gwahl:SetHeight(24)
    if gwahl.SetBackdrop then
        gwahl:SetBackdrop(K.BACKDROP_KARTE)
        gwahl:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
    end
    local ghl = gwahl:CreateTexture(nil, "HIGHLIGHT")
    ghl:SetPoint("TOPLEFT", 3, -3)
    ghl:SetPoint("BOTTOMRIGHT", -3, 3)
    ghl:SetColorTexture(1, 1, 1, 0.08)
    gwahl.icon = gwahl:CreateTexture(nil, "ARTWORK")
    gwahl.icon:SetSize(16, 16)
    gwahl.icon:SetPoint("LEFT", 6, 0)
    gwahl.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.gebietText = Schrift(gwahl, "GameFontNormalSmall")
    f.gebietText:SetPoint("LEFT", gwahl.icon, "RIGHT", 5, 0)
    f.gebietText:SetPoint("RIGHT", gwahl, "RIGHT", -20, 0)
    if f.gebietText.SetWordWrap then
        f.gebietText:SetWordWrap(false)
    end
    local gpfeil = gwahl:CreateTexture(nil, "ARTWORK")
    gpfeil:SetSize(14, 14)
    gpfeil:SetPoint("RIGHT", -4, 0)
    gpfeil:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    if gpfeil.SetRotation then
        gpfeil:SetRotation(-math.pi / 2)
    end
    f.gebietWahl = gwahl
    -- aufklappende Gebietsliste
    local gliste = CreateFrame("Frame", nil, f, K.BACKDROP_VORLAGE)
    gliste:SetPoint("TOPRIGHT", gwahl, "BOTTOMRIGHT", 0, -2)
    gliste:SetWidth(330)
    gliste:SetFrameStrata("DIALOG")
    if gliste.SetBackdrop then
        gliste:SetBackdrop(K.BACKDROP_KARTE)
        gliste:SetBackdropColor(0.03, 0.03, 0.04, 0.97)
    end
    gliste.zeilen = {}
    gliste.fuss = Schrift(gliste, "GameFontDisableSmall")
    gliste:Hide()
    f.gebietListe = gliste
    table.insert(alleAuswahllisten, gliste)
    gwahl:SetScript("OnClick", function()
        if gliste:IsShown() then
            gliste:Hide()
            return
        end
        AuswahllistenZu(gliste)
        local quests = QuestListe()
        local eintraege = {}
        for _, name in ipairs(GebieteListe(quests)) do
            local info = GebietInfo(name, quests)
            info.name = name
            table.insert(eintraege, info)
        end
        table.sort(eintraege, function(a, b)
            local ra, rb = K.GEBIET_ART[a.typ].rang, K.GEBIET_ART[b.typ].rang
            if ra ~= rb then
                return ra < rb
            end
            if (a.min or 999) ~= (b.min or 999) then
                return (a.min or 999) < (b.min or 999)
            end
            return a.name < b.name
        end)
        local y, i, letzteArt = 6, 0, nil
        local function zeile()
            i = i + 1
            local z = gliste.zeilen[i]
            if not z then
                z = CreateFrame("Button", nil, gliste)
                z:SetHeight(20)
                z.icon = z:CreateTexture(nil, "ARTWORK")
                z.icon:SetSize(16, 16)
                z.icon:SetPoint("LEFT", 4, 0)
                z.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                z.text = Schrift(z, "GameFontHighlightSmall")
                z.text:SetPoint("LEFT", z.icon, "RIGHT", 6, 0)
                z.rechts = Schrift(z, "GameFontHighlightSmall", false)
                z.rechts:SetPoint("RIGHT", -6, 0)
                z.text:SetPoint("RIGHT", z.rechts, "LEFT", -6, 0)
                if z.text.SetWordWrap then
                    z.text:SetWordWrap(false)
                end
                z.hl = z:CreateTexture(nil, "HIGHLIGHT")
                z.hl:SetAllPoints()
                z.hl:SetColorTexture(1, 1, 1, 0.1)
                gliste.zeilen[i] = z
            end
            z:ClearAllPoints()
            z:SetPoint("TOPLEFT", 4, -y)
            z:SetPoint("RIGHT", -4, 0)
            z:Show()
            y = y + 20
            return z
        end
        local fr = Fraktion()
        for _, e in ipairs(eintraege) do
            if e.typ ~= letzteArt then
                letzteArt = e.typ
                local kopf = zeile()
                kopf.icon:Hide()
                kopf.text:SetText(Farbe(fr.hex, K.GEBIET_ART[e.typ].text))
                kopf.rechts:SetText("")
                kopf:SetScript("OnClick", nil)
                kopf:EnableMouse(false)
            end
            local z = zeile()
            z:EnableMouse(true)
            z.icon:Show()
            z.icon:SetTexture(K.GEBIET_ART[e.typ].icon)
            z.text:SetText((e.name == fensterGebiet and "|cff44dd55" or "|cffffffff") .. e.name .. "|r"
                .. Farbe("9d9d9d", "  " .. StufenText(e)))
            z.rechts:SetText((e.bereit > 0 and Farbe("44dd55", e.bereit .. " fertig  ") or "")
                .. (e.offen > 0 and Farbe("f0cd63", e.offen .. " offen") or Farbe("777777", "-")))
            z:SetScript("OnClick", function()
                fensterGebiet = e.name
                gliste:Hide()
                if Fenster.scroll.SetVerticalScroll then
                    Fenster.scroll:SetVerticalScroll(0)
                end
                FensterAktualisieren()
            end)
        end
        for j = i + 1, #gliste.zeilen do
            gliste.zeilen[j]:Hide()
        end
        local fuss = gliste.fuss
        fuss:ClearAllPoints()
        fuss:SetPoint("TOPLEFT", 10, -(y + 2))
        fuss:SetText("* Stufen geschätzt aus den bekannten Quests")
        gliste:SetHeight(y + 22)
        gliste:Show()
    end)
    local function blaettern(richtung)
        local gebiete = GebieteListe(QuestListe())
        if #gebiete == 0 then
            return
        end
        local index = 1
        for i, g in ipairs(gebiete) do
            if g == fensterGebiet then
                index = i
            end
        end
        index = ((index - 1 + richtung) % #gebiete) + 1
        fensterGebiet = gebiete[index]
        if Fenster.scroll.SetVerticalScroll then
            Fenster.scroll:SetVerticalScroll(0)
        end
        FensterAktualisieren()
    end
    f.gebietLinks:SetScript("OnClick", function() blaettern(-1) end)
    f.gebietRechts:SetScript("OnClick", function() blaettern(1) end)

    -- Zusammenfassung ueber der Liste
    f.info = Schrift(f, "GameFontHighlightSmall")
    f.info:SetPoint("TOPLEFT", kopf, "BOTTOMLEFT", 4, -66)
    f.info:SetPoint("TOPRIGHT", kopf, "BOTTOMRIGHT", -4, -66)

    -- Liste mit Bildlauf
    -- moderne, schmale Scrollleiste (wie im Spiel und in Guild ERP), sonst die alte Vorlage
    local okS, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "ScrollFrameTemplate")
    if not okS or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", kopf, "BOTTOMLEFT", 0, -84)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)
    local inhalt = CreateFrame("Frame", nil, scroll)
    inhalt:SetSize(446, 10)
    scroll:SetScrollChild(inhalt)
    scroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 50 then
            inhalt:SetWidth(w)
        end
    end)
    f.scroll, f.inhalt = scroll, inhalt
    f.karten, f.ueberschriften = {}, {}

    f:SetScript("OnShow", function() FensterAktualisieren() end)
    -- Aussehen (klassisch / Spiel-Look) und Auswahlknoepfe im Spiel-Look
    for _, b in ipairs({ f.charWahl, f.gebietWahl, f.buchKnopf }) do
        O.Teil(function(spiel) O.WahlLook(b, spiel) end)
    end
    O.FensterLook(f)
    f:Hide()
    return f
end

-- ---------------------------------------------------------------------------
-- Liste fuellen
-- ---------------------------------------------------------------------------
local function ListeLeeren(f)
    for _, k in ipairs(f.karten) do
        k:Hide()
        k.benutzt = false
    end
    for _, u in ipairs(f.ueberschriften) do
        u:Hide()
        u.benutzt = false
    end
    f.y = 0
    f.einzug = 0
end

local function Frei(liste, bauen)
    for _, el in ipairs(liste) do
        if not el.benutzt then
            el.benutzt = true
            return el
        end
    end
    local el = bauen(Fenster.inhalt)
    el.benutzt = true
    table.insert(liste, el)
    return el
end

local function Ueberschrift(text, symbol, rechts, anteil, schluessel, standardZu, ebene)
    local f = Fenster
    local u = Frei(f.ueberschriften, UeberschriftBauen)
    local fr = Fraktion()
    ebene = ebene or 1
    local unter = ebene >= 2
    local spiel = O.Spiel()
    local einzug = (ebene - 1) * 16
    local hoehe = spiel and (ebene == 1 and 30 or 26) or (unter and 22 or 28)
    u:ClearAllPoints()
    u:SetPoint("TOPLEFT", f.inhalt, "TOPLEFT", einzug, -f.y - (unter and 2 or 4))
    u:SetPoint("RIGHT", f.inhalt, "RIGHT", -2, 0)
    u:SetHeight(hoehe)
    u.schluessel, u.standardZu = schluessel, standardZu
    local zu = schluessel and IstZu(schluessel, standardZu) or false
    if type(u.spielHg) ~= "table" then
        u.spielHg = u:CreateTexture(nil, "BACKGROUND")
        u.spielHg:SetAllPoints()
    end
    local balkenAn = spiel and O.Atlas(u.spielHg, "common-button-list-collapseExpand")
    u.spielHg:SetShown(balkenAn and true or false)
    u.knopf:ClearAllPoints()
    u.rechts:ClearAllPoints()
    u.text:ClearAllPoints()
    local mitSymbol = symbol ~= false and symbol ~= nil
    if balkenAn then
        -- wie Guild ERP: Balken des Spiels, Text links, Plus/Minus rechts, ohne Symbol und Linie
        u.symbol:Hide()
        u.linie:Hide()
        u.knopf:SetSize(14, 14)
        u.knopf:SetPoint("RIGHT", -10, 0)
        if schluessel then
            if not O.Atlas(u.knopf, zu and "common-button-list-plus" or "common-button-list-minus", true) then
                u.knopf:SetTexture(zu and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            end
            u.knopf:Show()
        else
            u.knopf:Hide()
        end
        u.rechts:SetPoint("RIGHT", -34, 0)
        u.text:SetPoint("LEFT", 10, 0)
        u.text:SetPoint("RIGHT", u.rechts, "LEFT", -8, 0)
        if u.text.SetFontObject then
            u.text:SetFontObject(ebene == 1 and K.SPIEL_SCHRIFT or "GameFontNormal")
        end
    else
        u.linie:Show()
        u.knopf:SetSize(14, 14)
        u.knopf:SetPoint("LEFT", 2, 0)
        u.rechts:SetPoint("RIGHT", -4, 0)
        if schluessel then
            u.knopf:SetTexture(zu and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            u.knopf:SetTexCoord(0, 1, 0, 1)
            u.knopf:Show()
        else
            u.knopf:Hide()
        end
        u.symbol:SetTexture(symbol or K.ICON_UNBEKANNT)
        u.symbol:SetShown(mitSymbol)
        if mitSymbol then
            u.text:SetPoint("LEFT", u.symbol, "RIGHT", 8, 0)
        else
            u.text:SetPoint("LEFT", u.knopf, "RIGHT", 6, 0)
        end
        if u.text.SetFontObject then
            u.text:SetFontObject(unter and K.SCHRIFT_UNTER or K.SCHRIFT_KOPF)
        end
    end
    u.text:SetText(text)
    if ebene == 1 then
        u.text:SetTextColor(fr.akzent[1], fr.akzent[2], fr.akzent[3])
    else
        u.text:SetTextColor(1, 0.82, 0)
    end
    u.rechts:SetText(rechts or "")
    u.linie:SetColorTexture(fr.rahmen[1], fr.rahmen[2], fr.rahmen[3], unter and 0.25 or 0.6)
    -- Fortschrittsbalken (Berufswert) nur im klassischen Look
    if anteil and not balkenAn then
        u.balkenHg:Show()
        local breite = u.balkenHg:GetWidth()
        if breite and breite > 0 then
            u.balken:SetWidth(math.max(1, breite * math.min(1, anteil)))
            u.balken:SetVertexColor(fr.akzent[1], fr.akzent[2], fr.akzent[3], 1)
            u.balken:Show()
        else
            u.balken:Hide()
        end
    else
        u.balkenHg:Hide()
        u.balken:Hide()
    end
    u:Show()
    f.y = f.y + hoehe + (spiel and 4 or (unter and 6 or 8))
    return not zu
end

local function Karte(daten)
    local f = Fenster
    local k = Frei(f.karten, KarteBauen)
    k:ClearAllPoints()
    k:SetPoint("TOPLEFT", f.inhalt, "TOPLEFT", f.einzug or 0, -f.y)
    k:SetPoint("RIGHT", f.inhalt, "RIGHT", -2, 0)
    local rgb = daten.farbe or { 0.5, 0.5, 0.5 }
    local spielZeile = O.Spiel()
    k.streifen:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    k.streifen:SetShown(not spielZeile)
    local mitSymbol = daten.symbol ~= false
    k.symbol:SetShown(mitSymbol)
    k.symbolRand:SetShown(mitSymbol and not spielZeile)
    -- Spiel-Look: kompakte Zeile wie im Rezeptbuch von Guild ERP (kleines Symbol, normale Schrift)
    k.symbol:ClearAllPoints()
    if spielZeile then
        k.symbol:SetSize(24, 24)
        k.symbol:SetPoint("TOPLEFT", 8, -6)
    else
        k.symbol:SetSize(32, 32)
        k.symbol:SetPoint("TOPLEFT", 12, -8)
    end
    if k.titel.SetFontObject then
        k.titel:SetFontObject(spielZeile and O.ZEILEN_SCHRIFT or K.SCHRIFT_KARTE)
    end
    -- einzeilig: Titel und Unterzeile werden abgeschnitten statt umbrochen (Rest im Tooltip)
    local einzeilig = spielZeile and daten.einzeilig
    if k.titel.SetWordWrap then
        k.titel:SetWordWrap(not einzeilig)
        k.zeile1:SetWordWrap(not einzeilig)
    end
    k.rechts:ClearAllPoints()
    k.rechts:SetPoint("TOPRIGHT", -10, spielZeile and -7 or -9)
    -- kleiner Knopf "Auftragsnetz" (Spiel-Look) links neben der EP-Angabe
    if type(k.netzKnopf) ~= "table" then
        k.netzKnopf = CreateFrame("Button", nil, k)
        k.netzKnopf:SetSize(16, 16)
        local bild = k.netzKnopf:CreateTexture(nil, "ARTWORK")
        bild:SetAllPoints()
        bild:SetTexture(O.ICON)
        bild:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local hl = k.netzKnopf:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.25)
        k.netzKnopf:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Auftragsnetz", 1, 0.82, 0)
                GameTooltip:AddLine("Zeigt die ganze Questreihe mit Vor- und Folgequests.", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        k.netzKnopf:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
    end
    local kleinerNetzKnopf = spielZeile and daten.aktion ~= nil
    k.netzKnopf:ClearAllPoints()
    k.netzKnopf:SetPoint("RIGHT", k.rechts, "LEFT", (daten.rechts and daten.rechts ~= "") and -6 or 0, 0)
    k.netzKnopf:SetShown(kleinerNetzKnopf and true or false)
    k.netzKnopf:SetScript("OnClick", kleinerNetzKnopf and daten.aktion.fn or nil)
    k.titel:ClearAllPoints()
    if mitSymbol then
        k.titel:SetPoint("TOPLEFT", k.symbol, "TOPRIGHT", spielZeile and 8 or 10, spielZeile and -4 or -1)
    else
        k.titel:SetPoint("TOPLEFT", k, "TOPLEFT", spielZeile and 10 or 14, spielZeile and -7 or -8)
    end
    if kleinerNetzKnopf then
        k.titel:SetPoint("RIGHT", k.netzKnopf, "LEFT", -6, 0)
    else
        k.titel:SetPoint("RIGHT", k.rechts, "LEFT", -6, 0)
    end
    k.symbol:SetTexture(mitSymbol and (daten.symbol or K.ICON_QUEST) or nil)
    local q = daten.qualitaet and K.QUALITAET_RGB[daten.qualitaet]
    if k.symbolRand.SetBackdropBorderColor then
        if q then
            k.symbolRand:SetBackdropBorderColor(q[1], q[2], q[3], 1)
        else
            k.symbolRand:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end
    k.titel:SetText(daten.titel or "")
    if daten.titelFarbe then
        k.titel:SetTextColor(daten.titelFarbe[1], daten.titelFarbe[2], daten.titelFarbe[3])
    elseif spielZeile then
        -- Farbe traegt den Status (wie gruene Namen im Berufefenster)
        k.titel:SetTextColor(math.min(1, rgb[1] + 0.15), math.min(1, rgb[2] + 0.15), math.min(1, rgb[3] + 0.15))
    else
        k.titel:SetTextColor(1, 0.95, 0.85)
    end
    k.rechts:SetText(daten.rechts or "")
    k.zeile1:SetText(daten.zeile1 or "")
    k.zeile2:SetText(daten.zeile2 or "")
    k.zeile2:SetShown(daten.zeile2 ~= nil and daten.zeile2 ~= "")
    -- Symbolleiste rechts unten; Textzeilen machen ihr Platz
    local icons = daten.icons or {}
    local leisteBreite = 0
    if #icons > 0 then
        local wahlAb
        for i, r in ipairs(icons) do
            if r.choice and not wahlAb then
                wahlAb = i
            end
        end
        leisteBreite = #icons * 21 + ((wahlAb and wahlAb > 1) and 8 or 0)
    end
    k.zeile1:ClearAllPoints()
    k.zeile1:SetPoint("TOPLEFT", k.titel, "BOTTOMLEFT", 0, -3)
    k.zeile1:SetPoint("RIGHT", k, "RIGHT", -(10 + (leisteBreite > 0 and leisteBreite + 6 or 0)), 0)
    k.zeile2:ClearAllPoints()
    k.zeile2:SetPoint("TOPLEFT", k.zeile1, "BOTTOMLEFT", 0, -2)
    k.zeile2:SetPoint("RIGHT", k, "RIGHT", -(10 + (leisteBreite > 0 and leisteBreite + 6 or 0)), 0)
    k.itemID = daten.itemID
    k.spellID = daten.spellID
    -- Klick auf die Karte (z. B. Quest im Questlog oeffnen)
    if daten.klick then
        local fn = daten.klick
        k:SetScript("OnMouseUp", function(_, taste)
            if taste == "LeftButton" then
                fn()
            end
        end)
    else
        k:SetScript("OnMouseUp", nil)
    end
    k.quellen = daten.quellen
    k.rezeptID = daten.rezeptID
    k.zusatz = daten.zusatz
    k.hinweis = daten.hinweis
    -- Spiel-Look: Karten wie die Zeilen im Berufefenster (leichter Grund, kein Rand,
    -- Hervorhebung mit der Spielgrafik); klassisch: dunkle Karte mit Rand
    local spiel = O.Spiel()
    if type(k.spielAktiv) ~= "table" then
        k.spielAktiv = k:CreateTexture(nil, "BACKGROUND", nil, 1)
        k.spielAktiv:SetPoint("TOPLEFT", 2, -2)
        k.spielAktiv:SetPoint("BOTTOMRIGHT", -2, 2)
        k.spielAktiv:Hide()
    end
    k.spielAktiv:Hide()
    if k.SetBackdropColor then
        if spiel then
            -- wie die Zeilen im Berufefenster: kein Kasten, nur eine feine Trennlinie unten
            k:SetBackdropColor(0, 0, 0, 0)
            k:SetBackdropBorderColor(0, 0, 0, 0)
        elseif daten.hervorheben then
            k:SetBackdropColor(rgb[1] * 0.18, rgb[2] * 0.18, rgb[3] * 0.18, 0.95)
            k:SetBackdropBorderColor(0.35, 0.3, 0.22, 0.9)
        else
            k:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
            k:SetBackdropBorderColor(0.35, 0.3, 0.22, 0.9)
        end
    end
    if type(k.spielLinie) ~= "table" then
        k.spielLinie = k:CreateTexture(nil, "BACKGROUND", nil, 2)
        k.spielLinie:SetHeight(1)
        k.spielLinie:SetPoint("BOTTOMLEFT", 6, 0)
        k.spielLinie:SetPoint("BOTTOMRIGHT", -6, 0)
        k.spielLinie:SetColorTexture(1, 1, 1, 0.06)
        k.spielHover = k:CreateTexture(nil, "BACKGROUND", nil, 3)
        k.spielHover:SetAllPoints()
        k.spielHover:Hide()
    end
    k.spielLinie:SetShown(spiel and true or false)
    k.spielHoverOk = spiel and O.Atlas(k.spielHover, "Professions_Recipe_Hover") or false
    k.spielHover:SetAlpha(0.5)
    k.spielHover:Hide()
    local textHoehe = (k.titel:GetStringHeight() or 12) + 3 + (k.zeile1:GetStringHeight() or 12)
        + ((daten.zeile2 and daten.zeile2 ~= "") and ((k.zeile2:GetStringHeight() or 12) + 2) or 0)
    -- alle Belohnungen untereinander
    local liste = daten.belohnungen or {}
    for i, r in ipairs(liste) do
        local z = k:BelohnungZeile(i)
        z:ClearAllPoints()
        z:SetPoint("TOPLEFT", k, "TOPLEFT", 54, -(8 + textHoehe + 4 + (i - 1) * 18))
        z:SetPoint("RIGHT", k, "RIGHT", -10, 0)
        z.icon:SetTexture(ItemIcon(r.itemID) or K.ICON_UNBEKANNT)
        local hex = K.QUALITAET_FARBE[r.quality or 1] or "ffffff"
        z.text:SetText(Farbe(hex, "[" .. (r.name or "?") .. "]")
            .. ((r.count and r.count > 1) and Farbe("cccccc", " x" .. r.count) or "")
            .. (r.choice and Farbe("9d9d9d", "  - zur Wahl") or ""))
        z.itemID = r.itemID
        z:Show()
    end
    for i = #liste + 1, #k.belohnungen do
        k.belohnungen[i]:Hide()
    end
    local hoehe = (einzeilig and 10 or (spielZeile and 16 or 14)) + math.max(mitSymbol and (spielZeile and 24 or 32) or 0, textHoehe + (#liste > 0 and (4 + #liste * 18) or 0))
    if #icons > 0 then
        hoehe = math.max(hoehe, 14 + textHoehe, 40)
    end
    -- Symbolleiste setzen: rechts, unter der EP-/Preis-Angabe (von rechts nach links)
    local oben = einzeilig and -21 or -28
    if #icons > 0 then
        hoehe = math.max(hoehe, -oben + 18 + (einzeilig and 3 or 8))
    end
    local x = -10
    local trennerGesetzt = false
    k.trenner:Hide()
    for i = #icons, 1, -1 do
        local r = icons[i]
        local z = k:IconFeld(i)
        z:ClearAllPoints()
        z:SetPoint("TOPRIGHT", k, "TOPRIGHT", x, oben)
        z.bild:SetTexture(ItemIcon(r.itemID) or K.ICON_UNBEKANNT)
        local q = K.QUALITAET_RGB[r.quality or 1] or K.QUALITAET_RGB[1]
        if z.SetBackdropBorderColor then
            z:SetBackdropBorderColor(q[1], q[2], q[3], 1)
        end
        z.anzahl:SetText((r.count and r.count > 1) and r.count or "")
        z.itemID, z.wahl = r.itemID, r.choice
        z:Show()
        x = x - 21
        -- Trennstrich zwischen festen Belohnungen und Belohnungen zur Wahl
        if r.choice and i > 1 and not icons[i - 1].choice and not trennerGesetzt then
            k.trenner:ClearAllPoints()
            k.trenner:SetPoint("TOPRIGHT", k, "TOPRIGHT", x - 1, oben - 2)
            k.trenner:Show()
            trennerGesetzt = true
            x = x - 8
        end
    end
    for i = #icons + 1, #k.icons do
        k.icons[i]:Hide()
    end
    if daten.aktion and not kleinerNetzKnopf then
        k.aktion:SetText(daten.aktion.text)
        k.aktion:SetScript("OnClick", daten.aktion.fn)
        k.aktion:Show()
        hoehe = hoehe + 22
    else
        k.aktion:Hide()
    end
    k:SetHeight(hoehe)
    k:Show()
    f.y = f.y + hoehe + (O.Spiel() and 0 or 4)
end

local function Hinweis(text)
    Karte({ titel = Farbe("aaaaaa", text), farbe = { 0.3, 0.3, 0.3 }, symbol = K.ICON_UNBEKANNT, zeile1 = "" })
end

-- ---------------------------------------------------------------------------
-- Auftragsnetz: eigenes Fenster, zeigt eine Questreihe als Kacheln mit Pfeilen.
-- ---------------------------------------------------------------------------
local Netzfenster

-- Kinder je Quest (umgekehrte Vorquest-Verknuepfung)
local function QuestKinder()
    local kinder = {}
    for id, e in pairs(QuestWissen()) do
        for vor in pairs(Vorquests(e, id)) do
            kinder[vor] = kinder[vor] or {}
            table.insert(kinder[vor], id)
        end
    end
    return kinder
end

-- alle Quests, die ueber Vor-/Folgequests mit questID verbunden sind
local function Questreihe(questID, kinder)
    kinder = kinder or QuestKinder()
    local wissen = QuestWissen()
    local reihe, offen = {}, { questID }
    while #offen > 0 and #offen < 500 do
        local id = table.remove(offen)
        if not reihe[id] and wissen[id] and wissen[id].name then
            reihe[id] = true
            for vor in pairs(Vorquests(wissen[id], id)) do
                table.insert(offen, vor)
            end
            for _, kind in ipairs(kinder[id] or {}) do
                table.insert(offen, kind)
            end
        end
    end
    return reihe
end

local function NetzBauen()
    local n = CreateFrame("Frame", "ForeverDashboardAuftragsnetz", UIParent, K.BACKDROP_VORLAGE)
    n:SetSize(600, 400)
    n:SetPoint("CENTER", 0, 40)
    n:SetFrameStrata("HIGH")
    n:SetToplevel(true)
    n:SetMovable(true)
    n:SetClampedToScreen(true)
    n:EnableMouse(true)
    n:RegisterForDrag("LeftButton")
    n:SetScript("OnDragStart", n.StartMoving)
    n:SetScript("OnDragStop", n.StopMovingOrSizing)
    if n.SetBackdrop then
        n:SetBackdrop(K.BACKDROP_RAHMEN)
    end
    table.insert(UISpecialFrames, "ForeverDashboardAuftragsnetz")
    local zu = CreateFrame("Button", nil, n, "UIPanelCloseButton")
    zu:SetPoint("TOPRIGHT", -4, -4)
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetSize(22, 22)
    n.icon:SetPoint("TOPLEFT", 16, -14)
    n.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_02")
    n.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    n.titel = Schrift(n, "GameFontNormalLarge")
    n.titel:SetPoint("LEFT", n.icon, "RIGHT", 8, 0)
    n.titel:SetPoint("RIGHT", zu, "LEFT", -8, 0)
    if n.titel.SetWordWrap then
        n.titel:SetWordWrap(false)
    end
    n.legende = Schrift(n, "GameFontHighlightSmall")
    n.legende:SetPoint("BOTTOMLEFT", 18, 14)
    n.legende:SetPoint("RIGHT", -18, 0)

    -- Flaeche mit Bildlauf (Mausrad: hoch/runter, mit Umschalttaste: links/rechts)
    local scroll = CreateFrame("ScrollFrame", nil, n)
    scroll:SetPoint("TOPLEFT", 14, -44)
    scroll:SetPoint("BOTTOMRIGHT", -14, 34)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown and IsShiftKeyDown() then
            local neu = math.max(0, math.min(self:GetHorizontalScrollRange(), self:GetHorizontalScroll() - delta * 60))
            self:SetHorizontalScroll(neu)
        else
            local neu = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40))
            self:SetVerticalScroll(neu)
        end
    end)
    local flaeche = CreateFrame("Frame", nil, scroll)
    flaeche:SetSize(10, 10)
    scroll:SetScrollChild(flaeche)
    n.scroll, n.flaeche = scroll, flaeche
    n.kacheln, n.linien, n.spitzen = {}, {}, {}
    n:Hide()
    return n
end

local function NetzKachel(i)
    local n = Netzfenster
    local k = n.kacheln[i]
    if k then
        return k
    end
    k = CreateFrame("Button", nil, n.flaeche, K.BACKDROP_VORLAGE)
    if k.SetBackdrop then
        k:SetBackdrop(K.BACKDROP_KARTE)
    end
    k.icon = k:CreateTexture(nil, "ARTWORK")
    k.icon:SetSize(28, 28)
    k.icon:SetPoint("LEFT", 8, 0)
    k.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    k.name = Schrift(k, "GameFontNormalSmall")
    k.name:SetPoint("TOPLEFT", k.icon, "TOPRIGHT", 6, 0)
    k.name:SetPoint("RIGHT", -6, 0)
    if k.name.SetWordWrap then
        k.name:SetWordWrap(false)
    end
    k.unter = Schrift(k, "GameFontHighlightSmall")
    k.unter:SetPoint("TOPLEFT", k.name, "BOTTOMLEFT", 0, -3)
    k.unter:SetPoint("RIGHT", -6, 0)
    if k.unter.SetWordWrap then
        k.unter:SetWordWrap(false)
    end
    local hl = k:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.08)
    k:SetScript("OnEnter", function(self)
        local q = self.quest
        if not q or not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(q.name, 1, 0.82, 0)
        local st = K.STATUS[q.status]
        GameTooltip:AddLine(st.text .. (q.level and ("  -  Stufe " .. q.level) or "") .. (q.xp > 0 and ("  -  " .. Zahl3(q.xp) .. " EP") or ""),
            st.rgb[1], st.rgb[2], st.rgb[3])
        GameTooltip:AddLine(q.zone, 0.8, 0.8, 0.8)
        local function wo(t)
            return t.name .. ((t.zone and t.zone ~= q.zone) and ("  -  " .. t.zone) or "")
                .. (t.x and (" (" .. t.x .. ", " .. t.y .. ")") or "")
        end
        if q.annahme then
            GameTooltip:AddLine("Annahme: " .. wo(q.annahme), 0.85, 0.85, 0.85)
        end
        if q.abgabe then
            GameTooltip:AddLine("Abgabe: " .. wo(q.abgabe), 0.85, 0.85, 0.85)
        end
        if q.progress and q.progress ~= "" then
            GameTooltip:AddLine(q.progress, 1, 1, 1, true)
        end
        if #q.belohnungen > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Belohnung:", 1, 0.82, 0)
            for _, r in ipairs(q.belohnungen) do
                local rgb = K.QUALITAET_RGB[r.quality or 1] or K.QUALITAET_RGB[1]
                GameTooltip:AddLine("  " .. r.name .. (r.choice and "  (zur Wahl)" or ""), rgb[1], rgb[2], rgb[3])
            end
        end
        if q.discoveredBy then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("entdeckt von " .. q.discoveredBy, 0.55, 0.48, 0.35)
        end
        GameTooltip:Show()
    end)
    k:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    n.kacheln[i] = k
    return k
end

local function NetzLinie(i)
    local n = Netzfenster
    local l = n.linien[i]
    if l then
        return l
    end
    if n.flaeche.CreateLine then
        l = n.flaeche:CreateLine(nil, "BACKGROUND")
        l:SetThickness(2)
    else
        l = n.flaeche:CreateTexture(nil, "BACKGROUND") -- sehr alte Spielversion: ohne Linien
        l.SetStartPoint = function() end
        l.SetEndPoint = function() end
    end
    n.linien[i] = l
    return l
end

local function NetzZeigen(questID)
    if not Netzfenster then
        Netzfenster = NetzBauen()
    end
    local n = Netzfenster
    local kinder = QuestKinder()
    local reihe = Questreihe(questID, kinder)
    local alle = {}
    for _, q in ipairs(QuestListe()) do
        alle[q.id] = q
    end
    local knoten = {}
    for id in pairs(reihe) do
        if alle[id] then
            table.insert(knoten, alle[id])
        end
    end
    local wissen = QuestWissen()
    -- Ebene (Spalte) = laengster Weg von einem Anfang
    local ebene = {}
    local function tiefe(id, besucht)
        if ebene[id] then
            return ebene[id]
        end
        if besucht[id] then
            return 0
        end
        besucht[id] = true
        local t = 0
        for vor in pairs(Vorquests(wissen[id], id)) do
            if reihe[vor] and alle[vor] then
                t = math.max(t, tiefe(vor, besucht) + 1)
            end
        end
        ebene[id] = t
        return t
    end
    for _, q in ipairs(knoten) do
        tiefe(q.id, {})
    end
    -- Bahn (Zeile): Kinder bleiben moeglichst in der Zeile der Vorquest
    local bahn, naechste = {}, 0
    local function setze(id, b)
        if bahn[id] then
            return
        end
        bahn[id] = b
        local liste = {}
        for _, kind in ipairs(kinder[id] or {}) do
            if reihe[kind] and alle[kind] then
                table.insert(liste, kind)
            end
        end
        table.sort(liste)
        for i, kind in ipairs(liste) do
            if i == 1 then
                setze(kind, b)
            else
                naechste = naechste + 1
                setze(kind, naechste)
            end
        end
    end
    table.sort(knoten, function(a, b) return a.id < b.id end)
    for _, q in ipairs(knoten) do
        if ebene[q.id] == 0 and not bahn[q.id] then
            setze(q.id, naechste)
            naechste = naechste + 1
        end
    end
    for _, q in ipairs(knoten) do
        if not bahn[q.id] then
            bahn[q.id] = naechste
            naechste = naechste + 1
        end
    end
    -- Bahnen ohne Luecken durchnummerieren
    local benutzt, ordnung = {}, {}
    for _, b in pairs(bahn) do
        if not benutzt[b] then
            benutzt[b] = true
            table.insert(ordnung, b)
        end
    end
    table.sort(ordnung)
    local neu = {}
    for i, b in ipairs(ordnung) do
        neu[b] = i - 1
    end

    -- Zeilenumbruch: hoechstens PRO_ZEILE Kacheln nebeneinander, dann geht es eine Zeile tiefer
    -- weiter. Pfeile laufen nur durch die Luecken zwischen den Kacheln (keine Ueberlappung).
    local B, H, ABST_X, ABST_Y, LUECKE = 190, 52, 46, 14, 34
    local LINKS = ABST_X / 2 + 4
    local spalten, zeilen = 0, 0
    for _, q in ipairs(knoten) do
        spalten = math.max(spalten, ebene[q.id] + 1)
        zeilen = math.max(zeilen, neu[bahn[q.id]] + 1)
    end
    local PRO_ZEILE = math.max(1, math.min(3, spalten))
    local baender = math.floor((spalten - 1) / PRO_ZEILE) + 1
    -- je Umbruch-Zeile nur so viele Bahnen, wie dort wirklich belegt sind
    local bahnenJeBand = {}
    for _, q in ipairs(knoten) do
        local band = math.floor(ebene[q.id] / PRO_ZEILE)
        bahnenJeBand[band] = bahnenJeBand[band] or {}
        bahnenJeBand[band][neu[bahn[q.id]]] = true
    end
    local ortJeBand, bandOben, bandInhalt = {}, {}, {}
    local y0 = 4
    for band = 0, baender - 1 do
        local liste = {}
        for b in pairs(bahnenJeBand[band] or {}) do
            table.insert(liste, b)
        end
        table.sort(liste)
        ortJeBand[band] = {}
        for i, b in ipairs(liste) do
            ortJeBand[band][b] = i - 1
        end
        bandOben[band] = y0
        bandInhalt[band] = math.max(1, #liste) * (H + ABST_Y) - ABST_Y
        y0 = y0 + bandInhalt[band] + LUECKE
    end
    local pos = {}
    for _, q in ipairs(knoten) do
        local d = ebene[q.id]
        local band, spalte = math.floor(d / PRO_ZEILE), d % PRO_ZEILE
        pos[q.id] = {
            x = LINKS + spalte * (B + ABST_X),
            y = bandOben[band] + ortJeBand[band][neu[bahn[q.id]]] * (H + ABST_Y),
            band = band, spalte = spalte,
        }
    end
    local breite = LINKS + PRO_ZEILE * (B + ABST_X)
    local hoehe = y0 - LUECKE + 4
    n.flaeche:SetSize(math.max(10, breite), math.max(10, hoehe))
    local maxB = (UIParent:GetWidth() or 1200) - 100
    local maxH = (UIParent:GetHeight() or 800) - 160
    n:SetSize(math.max(380, math.min(breite + 44, maxB)), math.max(200, math.min(hoehe + 92, maxH)))

    -- Kacheln
    local fr = Fraktion()
    for i, q in ipairs(knoten) do
        local k = NetzKachel(i)
        local p = pos[q.id]
        k:ClearAllPoints()
        k:SetSize(B, H)
        k:SetPoint("TOPLEFT", n.flaeche, "TOPLEFT", p.x, -p.y)
        local st = K.STATUS[q.status]
        if k.SetBackdropColor then
            local hervor = q.id == questID
            k:SetBackdropColor(st.rgb[1] * 0.2, st.rgb[2] * 0.2, st.rgb[3] * 0.2, 0.95)
            if hervor then
                k:SetBackdropBorderColor(fr.akzent[1], fr.akzent[2], fr.akzent[3], 1)
            else
                k:SetBackdropBorderColor(st.rgb[1], st.rgb[2], st.rgb[3], 0.9)
            end
        end
        k.icon:SetTexture((q.beste and ItemIcon(q.beste.itemID)) or K.ICON_QUEST)
        k.name:SetText(q.name)
        local sf = O.StufenFarbe(q.level, (select(2, AnsichtCharakter()) and UnitLevel("player")) or (AnsichtCharakter() or {}).level)
        if sf then
            k.name:SetTextColor(sf[1], sf[2], sf[3])
        else
            k.name:SetTextColor(1, 0.95, 0.85)
        end
        local blau = q.beste and (q.beste.quality or 0) >= 3
        k.unter:SetText(Farbe(st.hex, st.text) .. (q.level and Farbe("9d9d9d", "  [" .. q.level .. "]") or "")
            .. (q.xp > 0 and Farbe("c79cf0", "  " .. Zahl3(q.xp)) or "")
            .. (blau and "  |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12|t" or ""))
        k.quest = q
        k:Show()
    end
    for i = #knoten + 1, #n.kacheln do
        n.kacheln[i]:Hide()
    end

    -- Pfeile: Vorquest -> Folgequest (waagrecht, senkrecht, waagrecht)
    local li = 0
    local function strich(x1, y1, x2, y2, r, g, b, a)
        li = li + 1
        local l = NetzLinie(li)
        l:SetStartPoint("TOPLEFT", n.flaeche, x1, -y1)
        l:SetEndPoint("TOPLEFT", n.flaeche, x2, -y2)
        if l.SetColorTexture then
            l:SetColorTexture(r, g, b, a)
        end
        l:Show()
    end
    local si = 0
    for _, q in ipairs(knoten) do
        for vor in pairs(Vorquests(wissen[q.id], q.id)) do
            if pos[vor] then
                local a, z = pos[vor], pos[q.id]
                local x1, y1 = a.x + B, a.y + H / 2
                local x2, y2 = z.x, z.y + H / 2
                local gesperrt = q.status == "gesperrt"
                local r, g, b, al = 0.85, 0.75, 0.5, gesperrt and 0.45 or 0.9
                if a.band == z.band and z.spalte == a.spalte + 1 then
                    -- direkt daneben: waagrecht, senkrecht, waagrecht in der Spaltenluecke
                    local m = x1 + ABST_X / 2
                    strich(x1, y1, m, y1, r, g, b, al)
                    if math.abs(y2 - y1) > 0.5 then
                        strich(m, y1, m, y2, r, g, b, al)
                    end
                    strich(m, y2, x2 - 6, y2, r, g, b, al)
                else
                    -- Umbruch oder weiter weg: rechts raus, in der Luecke unter der Zeile entlang,
                    -- links neben der Zielkachel hoch oder runter, dann hinein
                    local xr = x1 + ABST_X / 2
                    local yl = bandOben[a.band] + bandInhalt[a.band] + LUECKE / 2
                    local xl = x2 - ABST_X / 2
                    strich(x1, y1, xr, y1, r, g, b, al)
                    strich(xr, y1, xr, yl, r, g, b, al)
                    strich(xr, yl, xl, yl, r, g, b, al)
                    strich(xl, yl, xl, y2, r, g, b, al)
                    strich(xl, y2, x2 - 6, y2, r, g, b, al)
                end
                si = si + 1
                local sp = n.spitzen[si]
                if not sp then
                    sp = n.flaeche:CreateTexture(nil, "ARTWORK")
                    sp:SetSize(12, 12)
                    sp:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
                    n.spitzen[si] = sp
                end
                sp:ClearAllPoints()
                sp:SetPoint("CENTER", n.flaeche, "TOPLEFT", x2 - 5, -y2)
                sp:SetVertexColor(r, g, b, al)
                sp:Show()
            end
        end
    end
    for i = li + 1, #n.linien do
        n.linien[i]:Hide()
    end
    for i = si + 1, #n.spitzen do
        n.spitzen[i]:Hide()
    end

    local erste = knoten[1]
    for _, q in ipairs(knoten) do
        if ebene[q.id] == 0 then
            erste = q
            break
        end
    end
    n.titel:SetText("Auftragsnetz: " .. (erste and erste.name or "?") .. Farbe("9d9d9d", "  (" .. #knoten .. " Quests)"))
    n.legende:SetText(Farbe(K.STATUS.abgabebereit.hex, "Abgabebereit") .. "   " .. Farbe(K.STATUS.aktiv.hex, "Aktiv") .. "   "
        .. Farbe(K.STATUS.verfuegbar.hex, "Verfügbar") .. "   " .. Farbe(K.STATUS.gesperrt.hex, "Gesperrt") .. "   "
        .. Farbe(K.STATUS.zuhoch.hex, "Zu hoch") .. "   "
        .. Farbe(K.STATUS.erledigt.hex, "Erledigt") .. Farbe("777777", "     Mausrad: blättern"))
    n.scroll:SetVerticalScroll(0)
    n.scroll:SetHorizontalScroll(0)
    n:Show()
end

local function QuestsZeigen(quests)
    local f = Fenster
    local wissen = QuestWissen()
    local ansicht, istLive = AnsichtCharakter()
    local meineStufe = (istLive and UnitLevel("player")) or (ansicht and ansicht.level) or 1
    local inGebiet = {}
    local zaehler = { abgabebereit = 0, aktiv = 0, verfuegbar = 0, gesperrt = 0, zuhoch = 0 }
    local filter = O.QUEST_FILTER_TEXT[O.questFilter] and O.questFilter or "alle"
    for _, q in ipairs(quests) do
        if q.zone == fensterGebiet and q.status ~= "erledigt" then
            zaehler[q.status] = (zaehler[q.status] or 0) + 1
            if filter == "alle" or q.status == filter then
                table.insert(inGebiet, q)
            end
        end
    end
    O.questZaehler = zaehler
    local spiel = O.Spiel()
    table.sort(inGebiet, function(a, b)
        if K.STATUS[a.status].rang ~= K.STATUS[b.status].rang then
            return K.STATUS[a.status].rang < K.STATUS[b.status].rang
        end
        local ba, bb = a.beste and a.beste.quality or 0, b.beste and b.beste.quality or 0
        if ba ~= bb then
            return ba > bb
        end
        return (a.level or 0) < (b.level or 0)
    end)
    f.info:SetText(Farbe(K.STATUS.abgabebereit.hex, zaehler.abgabebereit .. " abgabebereit") .. "   "
        .. Farbe(K.STATUS.aktiv.hex, zaehler.aktiv .. " aktiv") .. "   "
        .. Farbe(K.STATUS.verfuegbar.hex, zaehler.verfuegbar .. " verfügbar") .. "   "
        .. Farbe(K.STATUS.gesperrt.hex, zaehler.gesperrt .. " gesperrt")
        .. (zaehler.zuhoch > 0 and ("   " .. Farbe(K.STATUS.zuhoch.hex, zaehler.zuhoch .. " zu hoch")) or ""))

    local kinder = QuestKinder()
    local letzterStatus, gruppeOffen = nil, true
    for _, q in ipairs(inGebiet) do
        if q.status ~= letzterStatus then
            letzterStatus = q.status
            local summe, anzahl = 0, 0
            for _, x in ipairs(inGebiet) do
                if x.status == q.status then
                    summe, anzahl = summe + x.xp, anzahl + 1
                end
            end
            gruppeOffen = Ueberschrift(K.STATUS[q.status].text .. Farbe("9d9d9d", "  (" .. anzahl .. ")"), false,
                summe > 0 and Farbe("c79cf0", Zahl3(summe) .. " EP") or "", nil, "quest:" .. q.status, q.status == "gesperrt" or q.status == "zuhoch")
        end
        if gruppeOffen then
        local st = K.STATUS[q.status]
        -- Zeile 1: Stufe und Fortschritt (der Status steht schon in der Ueberschrift)
        local zeile1 = q.level and Farbe("9d9d9d", "Stufe " .. q.level) or ""
        if q.status == "zuhoch" then
            local ich = (select(2, AnsichtCharakter()) and UnitLevel("player")) or (AnsichtCharakter() or {}).level or 1
            zeile1 = zeile1 .. Farbe(K.STATUS.zuhoch.hex, "  (du: " .. ich .. ")")
        end
        if q.progress and q.progress ~= "" then
            zeile1 = zeile1 .. (zeile1 ~= "" and "   " or "") .. Farbe("ffffff", q.progress)
        end
        -- Zeile 2: wohin jetzt? Aktiv/abgabebereit -> Abgabe, sonst -> Annahme
        local function wo(t)
            local text = t.name
            if t.zone and t.zone ~= "" and t.zone ~= q.zone then
                text = text .. "  -  " .. t.zone
            end
            if t.x then
                text = text .. " (" .. t.x .. ", " .. t.y .. ")"
            end
            return text
        end
        local zeile2
        if q.status == "abgabebereit" or q.status == "aktiv" then
            if q.abgabe then
                zeile2 = Farbe("9d9d9d", "Abgabe: ") .. Farbe(q.status == "abgabebereit" and "44dd55" or "e6d7b3", wo(q.abgabe))
            else
                zeile2 = Farbe("777777", "Abgabe: noch unbekannt")
            end
        elseif q.annahme then
            zeile2 = Farbe("9d9d9d", "Annahme: ") .. Farbe("e6d7b3", wo(q.annahme))
        end
        local vorher
        if q.status == "gesperrt" then
            local namen = {}
            for _, vor in ipairs(q.fehlend) do
                table.insert(namen, (wissen[vor] and wissen[vor].name) or ("Quest " .. vor))
            end
            vorher = "Vorher: " .. table.concat(namen, ", ")
            zeile2 = zeile2 and (Farbe("ff9966", vorher) .. "\n" .. zeile2) or Farbe("ff9966", vorher)
        end
        -- Spiel-Look (Vorlage A): "[Stufe] Name", darunter eine graue Zeile "Fortschritt · Ort"
        local titel = q.name
        if spiel then
            titel = (q.level and ("[" .. q.level .. "] ") or "") .. q.name
            local teile = {}
            if vorher then
                table.insert(teile, Farbe("ff9966", vorher))
            end
            if q.progress and q.progress ~= "" then
                table.insert(teile, Farbe("dddddd", q.progress))
            end
            if q.status == "abgabebereit" or q.status == "aktiv" then
                table.insert(teile, q.abgabe and (Farbe("9d9d9d", "Abgabe: ") .. Farbe(q.status == "abgabebereit" and "44dd55" or "c8b98f", wo(q.abgabe)))
                    or Farbe("777777", "Abgabe unbekannt"))
            elseif q.annahme then
                table.insert(teile, Farbe("9d9d9d", "Annahme: ") .. Farbe("c8b98f", wo(q.annahme)))
            else
                table.insert(teile, Farbe("777777", "Annahme unbekannt"))
            end
            if q.status == "zuhoch" then
                table.insert(teile, Farbe(K.STATUS.zuhoch.hex, "du: " .. meineStufe))
            end
            zeile1 = table.concat(teile, Farbe("777777", "  ·  "))
            zeile2 = nil
        end
        -- Tooltip der Karte: alles Weitere
        local tip = { q.name, (q.level and ("Stufe " .. q.level) or "") .. (q.xp > 0 and ("  -  " .. Zahl3(q.xp) .. " EP") or "") }
        if q.annahme then
            table.insert(tip, "Annahme: " .. wo(q.annahme))
        end
        if q.abgabe then
            table.insert(tip, "Abgabe: " .. wo(q.abgabe))
        end
        local wahl = 0
        for _, r in ipairs(q.belohnungen) do
            if r.choice then
                wahl = wahl + 1
            end
        end
        if #q.belohnungen > 0 then
            table.insert(tip, wahl > 1 and ("Belohnung: eine von " .. wahl .. " zur Wahl (Symbole rechts unten)")
                or "Belohnung: Symbole rechts unten")
        end
        if q.discoveredBy then
            table.insert(tip, "entdeckt von " .. q.discoveredBy)
        end
        local imLog = istLive and (q.status == "aktiv" or q.status == "abgabebereit")
        if q.progress and q.progress ~= "" then
            table.insert(tip, "Fortschritt: " .. q.progress)
        end
        if vorher then
            table.insert(tip, vorher)
        end
        if imLog then
            table.insert(tip, " ")
            table.insert(tip, "Klick: im Questlog des Spiels öffnen")
        end
        -- feste Belohnungen zuerst, dann die zur Wahl
        local icons = {}
        for _, r in ipairs(q.belohnungen) do
            if not r.choice then
                table.insert(icons, r)
            end
        end
        for _, r in ipairs(q.belohnungen) do
            if r.choice then
                table.insert(icons, r)
            end
        end
        Karte({
            titel = titel,
            einzeilig = spiel,
            titelFarbe = O.StufenFarbe(q.level, meineStufe), -- Farbe nach Stufe wie im Spiel
            klick = imLog and function() O.QuestlogOeffnen(q.id) end or nil,
            rechts = q.xp > 0 and Farbe("c79cf0", Zahl3(q.xp) .. " EP") or "",
            zeile1 = zeile1,
            zeile2 = zeile2,
            farbe = st.rgb,
            symbol = false,
            hervorheben = q.status == "abgabebereit",
            hinweis = table.concat(tip, "\n"),
            icons = icons,
            aktion = (next(Vorquests(wissen[q.id], q.id)) or kinder[q.id]) and {
                text = "Auftragsnetz", fn = function() NetzZeigen(q.id) end,
            } or nil,
        })
        end
    end
    if #inGebiet == 0 then
        Hinweis(filter ~= "alle" and "Keine Quests passen zu dieser Auswahl."
            or "In diesem Gebiet sind noch keine offenen Quests bekannt.")
    end
end

K.SCHWIERIGKEIT = {
    [0] = { hex = "ff8040", text = "bringt sicher Punkte" },
    [1] = { hex = "ffff00", text = "bringt meist Punkte" },
    [2] = { hex = "40bf40", text = "bringt selten Punkte" },
    [3] = { hex = "909090", text = "keine Punkte mehr" },
}

local function RezepteZeigen()
    local f = Fenster
    local charakter = AnsichtCharakter() or {}
    local werte, maxima = {}, {}
    for _, b in ipairs(charakter.professions or {}) do
        werte[b.name], maxima[b.name] = b.skillLevel, b.maxSkillLevel
    end
    for name, b in pairs(charakter.secondarySkills or {}) do
        werte[name] = werte[name] or b.skillLevel
        maxima[name] = maxima[name] or b.maxSkillLevel
    end
    local fehlend, bekannt = {}, {}
    for _, sammlung in pairs(charakter.recipeCollections or {}) do
        local beruf = sammlung.professionName
        if beruf then
            fehlend[beruf] = fehlend[beruf] or {}
            for _, r in ipairs(sammlung.missing or {}) do
                fehlend[beruf][r.name] = r
            end
            bekannt[beruf] = sammlung.known or {}
            if not werte[beruf] and (sammlung.skillLevel or 0) > 0 then
                werte[beruf], maxima[beruf] = sammlung.skillLevel, sammlung.maxSkillLevel
            end
        end
    end
    -- Katalog: beste Quelle je fehlendem Rezept; Berufswert auch fuer bekannte Rezepte merken
    local proBeruf, wertVon, alleQuellen = {}, {}, {}
    local hierZone = (GetRealZoneText and GetRealZoneText()) or ""
    local _, live = AnsichtCharakter()
    local fraktion = live and SpielerFraktion() or charakter.faction
    -- Entdecker (eigene Charaktere) -> Fraktion, fuer aeltere Eintraege ohne NPC-Fraktion
    local entdeckerFraktion = {}
    for _, c in pairs(ForeverDashboardData.characters or {}) do
        if c.fullName and c.faction then
            entdeckerFraktion[c.fullName] = c.faction
        end
    end
    local function fuerMich(e)
        local f = e.npcFaction
        if f == "Neutral" or not fraktion then
            return true
        end
        if not f and e.discoveredBy then
            f = entdeckerFraktion[e.discoveredBy]
        end
        return not ((f == "Alliance" or f == "Horde") and f ~= fraktion)
    end
    for _, e in pairs(Katalog()) do
        if e.profession and e.requiredSkill then
            wertVon[e.profession .. ":" .. e.name] = e.requiredSkill
            if fehlend[e.profession] and fehlend[e.profession][e.name] and fuerMich(e) then
                proBeruf[e.profession] = proBeruf[e.profession] or {}
                local alt = proBeruf[e.profession][e.name]
                -- beste Quelle: Lehrer vor Haendler, sonst eine im aktuellen Gebiet
                local rang = { Lehrer = 1, ["Händler"] = 2, Beute = 3 }
                local rNeu, rAlt = rang[e.sourceType] or 4, alt and (rang[alt.sourceType] or 4) or 9
                if not alt or rNeu < rAlt or (rNeu == rAlt and e.zone == hierZone and alt.zone ~= hierZone) then
                    proBeruf[e.profession][e.name] = e
                end
                local schl = e.profession .. ":" .. e.name
                alleQuellen[schl] = alleQuellen[schl] or {}
                table.insert(alleQuellen[schl], { art = e.sourceType, name = e.sourceName, zone = e.zone, x = e.x, y = e.y, cost = e.cost })
            end
        end
    end
    local function quellenVon(e)
        local liste = alleQuellen[e.profession .. ":" .. e.name]
        return liste and #liste > 1 and QuellenSortieren(liste) or nil
    end
    local function mehr(e)
        local liste = alleQuellen[e.profession .. ":" .. e.name]
        return (liste and #liste > 1) and Farbe("4aa3ff", "  +" .. (#liste - 1) .. " weitere (Maus darüber)") or ""
    end
    -- nur Berufe, die der gezeigte Charakter wirklich hat
    local seine = {}
    for _, b in ipairs(charakter.professions or {}) do
        seine[b.name] = true
    end
    local berufe = {}
    for beruf in pairs(fehlend) do
        if not next(seine) or seine[beruf] or K.NEBENBERUFE[beruf] then
            table.insert(berufe, beruf)
        end
    end
    table.sort(berufe, function(a, b) return (werte[a] or 0) > (werte[b] or 0) end)

    local function sortieren(liste, wertFeld)
        table.sort(liste, function(a, b)
            if rezSort == "gruppe" then
                -- wie im Berufefenster: nach Gruppe, darin nach Name
                if (a._kat or "") ~= (b._kat or "") then
                    if a._kat == "Sonstiges" then return false end
                    if b._kat == "Sonstiges" then return true end
                    return (a._kat or "") < (b._kat or "")
                end
                return a.name < b.name
            elseif rezSort == "name" then
                return a.name < b.name
            elseif rezSort == "kosten" then
                local ka, kb = a.cost or 0, b.cost or 0
                if ka ~= kb then
                    return ka < kb
                end
                return a.name < b.name
            end
            local wa, wb = wertFeld(a) or -1, wertFeld(b) or -1
            if wa ~= wb then
                if rezSort == "wertab" then
                    return wa > wb
                end
                return wa < wb
            end
            return a.name < b.name
        end)
    end
    local function ort(e)
        local text = (e.sourceType or "") .. ": " .. (e.sourceName or "?")
        if e.zone then
            text = text .. "  -  " .. e.zone .. (e.x and (" (" .. e.x .. ", " .. e.y .. ")") or "")
        end
        return Farbe("aaaaaa", text)
    end

    local summen = { jetzt = 0, spaeter = 0, bekannt = 0 }
    local gruppenFehlen = false
    local gueltig = false
    for _, beruf in ipairs(berufe) do
        if beruf == rezBeruf then
            gueltig = true
        end
    end
    if not gueltig then
        rezBeruf = nil
    end
    rezUebersicht = { berufe = {}, summen = summen }
    for _, beruf in ipairs(berufe) do
        local wert, max = werte[beruf], maxima[beruf]
        local jetzt, spaeter = {}, {}
        for _, e in pairs(proBeruf[beruf] or {}) do
            if wert and wert >= e.requiredSkill then
                table.insert(jetzt, e)
            else
                table.insert(spaeter, e)
            end
        end
        local gelernt = {}
        for _, r in ipairs(bekannt[beruf] or {}) do
            table.insert(gelernt, { name = r.name, id = r.id, itemID = r.itemID, difficulty = r.difficulty,
                requiredSkill = wertVon[beruf .. ":" .. r.name] })
        end
        table.insert(rezUebersicht.berufe, { beruf = beruf, wert = wert, max = max, jetzt = #jetzt, spaeter = #spaeter, bekannt = #gelernt })
        if not rezBeruf or rezBeruf == beruf then
        summen.jetzt, summen.spaeter, summen.bekannt = summen.jetzt + #jetzt, summen.spaeter + #spaeter, summen.bekannt + #gelernt
        local zeigeJetzt = (rezFilter == "alle" or rezFilter == "jetzt") and #jetzt > 0
        local zeigeSpaeter = (rezFilter == "alle" or rezFilter == "spaeter") and #spaeter > 0
        if zeigeJetzt or zeigeSpaeter or rezFilter == "alle" then
        local rechts = wert and (Farbe("ffffff", wert) .. Farbe("9d9d9d", max and max > 0 and (" / " .. max) or "")) or Farbe("9d9d9d", "Wert unbekannt")
        local berufOffen = Ueberschrift(beruf, K.BERUF_ICON[beruf] or K.ICON_UNBEKANNT, rechts,
            (wert and max and max > 0) and (wert / max) or nil, "rez:" .. beruf, false, 1)
        local symbol = K.BERUF_ICON[beruf] or K.ICON_UNBEKANNT
        local function rezeptZu(e)
            return fehlend[beruf] and fehlend[beruf][e.name]
        end
        local function gruppe(titel, hex, anzahl, teil, standardZu)
            local offen = Ueberschrift(Farbe(hex, titel) .. Farbe("9d9d9d", "  (" .. anzahl .. ")"), false, "", nil,
                "rez:" .. beruf .. ":" .. teil, standardZu, 2)
            Fenster.einzug = 16
            return offen
        end
        -- Gruppe des Spiels (aus dem eigenen Berufefenster, sonst aus Guild ERP, falls installiert)
        local erp = type(GuildERPData) == "table" and type(GuildERPData.recipes) == "table" and GuildERPData.recipes or {}
        local function kategorieVon(e)
            local r = rezeptZu(e)
            local k = r and (r.kategorie or (type(erp[r.id]) == "table" and erp[r.id].kategorie))
            -- noch unbekannt: beim Spiel nachfragen und merken (klappt, wenn das Spiel den Beruf kennt)
            if not k and r and r.id and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetCategoryInfo
                and not (K.kategorieGefragt and K.kategorieGefragt[r.id]) then
                K.kategorieGefragt = K.kategorieGefragt or {} -- nur fuer diese Sitzung
                K.kategorieGefragt[r.id] = true
                local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, r.id)
                if ok and type(info) == "table" and info.categoryID then
                    local ok2, kat = pcall(C_TradeSkillUI.GetCategoryInfo, info.categoryID)
                    if ok2 and type(kat) == "table" and kat.name and kat.name ~= "" then
                        r.kategorie = kat.name
                        k = kat.name
                    end
                end
            end
            if not k then
                gruppenFehlen = true
            end
            return (type(k) == "string" and k ~= "") and k or "Sonstiges"
        end
        -- Zeilen einer Liste zeigen; bei "Nach Gruppe" mit Gruppen-Balken (dritte Ebene)
        local function zeigen(liste, teil, karte)
            for _, e in ipairs(liste) do
                e._kat = kategorieVon(e)
            end
            sortieren(liste, function(e) return e.requiredSkill end)
            -- Gruppen-Balken nur, wenn die Gruppen bekannt sind (nicht alles "Sonstiges")
            local mitGruppen = false
            for _, e in ipairs(liste) do
                if e._kat ~= "Sonstiges" then
                    mitGruppen = true
                end
            end
            local letzte, offen = nil, true
            for _, e in ipairs(liste) do
                if rezSort == "gruppe" and mitGruppen and e._kat ~= letzte then
                    letzte = e._kat
                    local n = 0
                    for _, x in ipairs(liste) do
                        if x._kat == letzte then
                            n = n + 1
                        end
                    end
                    Fenster.einzug = 0
                    offen = Ueberschrift(letzte, false, Farbe("9d9d9d", n), nil, "rez:" .. beruf .. ":" .. teil .. ":" .. letzte, false, 3)
                    Fenster.einzug = 32
                end
                if offen then
                    karte(e)
                end
            end
        end
        if berufOffen then
            if zeigeJetzt and gruppe("Jetzt lernbar", "44dd55", #jetzt, "jetzt", false) then
                zeigen(jetzt, "jetzt", function(e)
                    local r = rezeptZu(e)
                    Karte({
                        titel = e.name,
                        rechts = Geld(e.cost),
                        zeile1 = Farbe("9d9d9d", "ab Berufswert " .. e.requiredSkill),
                        zeile2 = ort(e) .. mehr(e) .. ((e.sourceType ~= "Lehrer" and e.discoveredBy) and Farbe("8a7a5a", "   entdeckt von " .. e.discoveredBy) or ""),
                        quellen = quellenVon(e),
                        farbe = { 0.27, 0.85, 0.35 },
                        symbol = (r and ItemIcon(r.itemID)) or symbol,
                        rezeptID = r and r.id, itemID = r and r.itemID,
                        zusatz = "Jetzt lernbar bei " .. (e.sourceName or "?"),
                        hervorheben = true,
                    })
                end)
            end
            Fenster.einzug = 0
            if zeigeSpaeter and gruppe("Später", "ffaa00", #spaeter, "spaeter", false) then
                zeigen(spaeter, "spaeter", function(e)
                    local r = rezeptZu(e)
                    Karte({
                        titel = e.name,
                        rechts = Farbe("ffaa00", "ab " .. e.requiredSkill),
                        zeile1 = Farbe("9d9d9d", wert and ("noch " .. (e.requiredSkill - wert) .. " Punkte") or ("ab Berufswert " .. e.requiredSkill))
                            .. (e.cost and e.cost > 0 and ("   " .. Geld(e.cost)) or ""),
                        zeile2 = ort(e) .. mehr(e),
                        quellen = quellenVon(e),
                        farbe = { 1, 0.67, 0 },
                        symbol = (r and ItemIcon(r.itemID)) or symbol,
                        rezeptID = r and r.id, itemID = r and r.itemID,
                        zusatz = "Lernbar ab Berufswert " .. e.requiredSkill,
                    })
                end)
            end
            Fenster.einzug = 0
            Fenster.einzug = 0
            if rezFilter == "alle" and #jetzt == 0 and #spaeter == 0 then
                Hinweis(#gelernt > 0 and "Alles Bekannte gelernt - sprich weitere Lehrer und Händler an, um Neues zu finden."
                    or "Noch keine Katalogdaten - einen Lehrer oder Händler ansprechen.")
            end
        end
        end
        f.y = f.y + 6
        end
    end
    f.info:SetText(#berufe > 0 and (Farbe("44dd55", summen.jetzt .. " jetzt lernbar") .. "   "
        .. Farbe("ffaa00", summen.spaeter .. " später")
        .. Farbe("777777", (rezSort == "gruppe" and gruppenFehlen) and "      Gruppen: Berufefenster einmal öffnen"
            or "      Gelerntes siehst du im Guild ERP")) or "")
    if #berufe == 0 then
        Hinweis("Noch keine Rezepte erfasst - einmal das Berufefenster öffnen.")
    elseif f.y == 0 then
        Hinweis("Keine Rezepte passen zu dieser Auswahl.")
    elseif O.Spiel() and rezSort == "gruppe" and gruppenFehlen then
        -- im Spiel-Look gibt es keine Infozeile: Hinweis ans Ende der Liste
        Hinweis("Gruppen fehlen noch: das Berufefenster einmal öffnen.")
    end
end

-- ---------------------------------------------------------------------------
-- Reiter "Faehigkeiten": Klassenfaehigkeiten nach Status
-- ---------------------------------------------------------------------------
local function FaehigkeitenListe()
    local c, live = AnsichtCharakter()
    c = c or {}
    local token = live and select(2, UnitClass("player")) or KlassenKuerzel(c)
    local level = (live and UnitLevel("player")) or c.level or 1
    local katalog = KlassenKatalog(token)
    local fraktion = live and SpielerFraktion() or c.faction
    local volk = live and UnitRace and select(2, UnitRace("player")) or c.raceFile
    local besuche = ForeverDashboardData.classCatalogVisits and ForeverDashboardData.classCatalogVisits[token or ""] or {}
    local volkKennt = volk and besuche[volk]
    local buch = c.spellbook or {}
    local bekannt = c.spellsKnown or {}
    local liste, gelerntNachName, katalogNamen = {}, {}, {}
    for schluessel, e in pairs(katalog) do
        -- Volksfaehigkeit eines anderen Volks? (nur sicher, wenn dein Volk den Lehrer schon gesehen hat)
        local fremdesVolk = volkKennt and e.races and next(e.races) and not e.races[volk]
        if e.name and not fremdesVolk then
            katalogNamen[e.name] = e
            local imBuch = buch[e.name]
            local rang = e.rankNr or 0
            local kann = bekannt[schluessel] or (imBuch and (imBuch.rang or 0) >= rang)
            if kann then
                local alt = gelerntNachName[e.name]
                if not alt or rang > (alt.rankNr or 0) then
                    gelerntNachName[e.name] = { name = e.name, rankNr = rang, level = e.level, icon = e.icon or (imBuch and imBuch.icon),
                        category = e.category or (imBuch and imBuch.tab), desc = e.desc, status = "gelernt",
                        spellID = imBuch and imBuch.id }
                end
            else
                local status
                if not e.level or e.level <= level then
                    status = "jetzt"
                elseif e.level <= level + K.FERT_BALD then
                    status = "bald"
                else
                    status = "spaeter"
                end
                table.insert(liste, { name = e.name, rankNr = e.rankNr, level = e.level, cost = e.cost, icon = e.icon,
                    category = e.category or (imBuch and imBuch.tab) or "Allgemein", desc = e.desc, status = status,
                    trainer = e.trainer, zone = e.zone, x = e.x, y = e.y, trainers = e.trainers,
                    gesperrt = live and c.spellsTrainer and c.spellsTrainer[schluessel] == "unavailable" and status == "jetzt" })
            end
        end
    end
    -- Zauberbuch: gelernte Faehigkeiten, die (noch) kein Lehrer gezeigt hat; Reiter 1 = Allgemein
    for name, b in pairs(buch) do
        if not gelerntNachName[name] and (b.tabNr or 2) >= 2 then
            local e = katalogNamen[name]
            gelerntNachName[name] = { name = name, rankNr = b.rang, icon = b.icon or (e and e.icon), category = (e and e.category) or b.tab or "Allgemein",
                status = "gelernt", spellID = b.id, level = e and e.level, desc = e and e.desc }
        end
    end
    for _, e in pairs(gelerntNachName) do
        e.category = e.category or "Allgemein"
        table.insert(liste, e)
    end
    return liste, level, next(katalog) ~= nil, c.spellbook ~= nil, fraktion
end

local function FaehigkeitenZeigen()
    local f = Fenster
    local liste, level, hatKatalog, hatBuch, fraktion = FaehigkeitenListe()
    -- Uebersicht fuer die Auswahllisten
    local kategorien, summen = {}, { jetzt = 0, bald = 0, spaeter = 0, gelernt = 0 }
    local gueltig = false
    for _, e in ipairs(liste) do
        local k = kategorien[e.category]
        if not k then
            k = { name = e.category, jetzt = 0, bald = 0, spaeter = 0, gelernt = 0, icon = e.icon }
            kategorien[e.category] = k
        end
        k[e.status] = k[e.status] + 1
        if e.category == fertKategorie then
            gueltig = true
        end
    end
    if not gueltig then
        fertKategorie = nil
    end
    fertUebersicht = { kategorien = {}, summen = summen }
    for _, k in pairs(kategorien) do
        table.insert(fertUebersicht.kategorien, k)
    end
    table.sort(fertUebersicht.kategorien, function(a, b) return a.name < b.name end)

    local gruppen = { jetzt = {}, bald = {}, spaeter = {}, gelernt = {} }
    local kostenJetzt = 0
    for _, e in ipairs(liste) do
        if not fertKategorie or e.category == fertKategorie then
            table.insert(gruppen[e.status], e)
            summen[e.status] = summen[e.status] + 1
            if e.status == "jetzt" and not e.gesperrt then
                kostenJetzt = kostenJetzt + (e.cost or 0)
            end
        end
    end
    local function sortieren(t)
        table.sort(t, function(a, b)
            if fertSort == "name" then
                if a.name ~= b.name then
                    return a.name < b.name
                end
                return (a.rankNr or 0) < (b.rankNr or 0)
            elseif fertSort == "kosten" then
                if (a.cost or 0) ~= (b.cost or 0) then
                    return (a.cost or 0) < (b.cost or 0)
                end
            end
            if (a.level or 0) ~= (b.level or 0) then
                return (a.level or 0) < (b.level or 0)
            end
            if a.name ~= b.name then
                return a.name < b.name
            end
            return (a.rankNr or 0) < (b.rankNr or 0)
        end)
    end
    local hierZone = (GetRealZoneText and GetRealZoneText()) or ""
    local function lehrerListe(e)
        local liste = {}
        for name, t in pairs(e.trainers or {}) do
            -- nur Lehrer der eigenen Fraktion (oder neutrale / unbekannte)
            if not (fraktion and (t.faction == "Alliance" or t.faction == "Horde") and t.faction ~= fraktion) then
                table.insert(liste, { art = "Lehrer", name = name, zone = t.zone, x = t.x, y = t.y, cost = t.cost })
            end
        end
        return QuellenSortieren(liste)
    end
    local function ort(e)
        local liste = lehrerListe(e)
        if #liste > 0 then
            local erster = liste[1]
            return Farbe("aaaaaa", "Lehrer: " .. erster.name .. (erster.zone and ("  -  " .. erster.zone) or "")
                .. (erster.x and (" (" .. erster.x .. ", " .. erster.y .. ")") or ""))
                .. (#liste > 1 and Farbe("4aa3ff", "  +" .. (#liste - 1) .. " weitere (Maus darüber)") or "")
        end
        if e.trainers and next(e.trainers) then
            return Farbe("aaaaaa", "Lehrer deiner Fraktion: noch keiner besucht")
        end
        if not e.trainer then
            return ""
        end
        return Farbe("aaaaaa", "Lehrer: " .. e.trainer .. (e.zone and ("  -  " .. e.zone) or "")
            .. (e.x and (" (" .. e.x .. ", " .. e.y .. ")") or ""))
    end
    local function rangText(e)
        return (e.rankNr and e.rankNr > 0) and Farbe("9d9d9d", "  Rang " .. e.rankNr) or ""
    end
    local function hinweis(e)
        local t = e.name .. ((e.rankNr and e.rankNr > 0) and (" (Rang " .. e.rankNr .. ")") or "")
        if e.level then
            t = t .. "\nAb Stufe " .. e.level
        end
        if e.cost and e.cost > 0 then
            t = t .. "  -  " .. Geld(e.cost)
        end
        if e.desc then
            t = t .. "\n\n" .. e.desc
        end
        return t
    end

    for _, art in ipairs({ "jetzt", "bald", "spaeter" }) do
        local t = gruppen[art]
        local g = K.FERT_GRUPPE[art]
        if (fertFilter == "alle" or fertFilter == art) and #t > 0 then
            local rechts = ""
            if art == "jetzt" and kostenJetzt > 0 then
                rechts = Farbe("9d9d9d", "zusammen ") .. Geld(kostenJetzt)
            elseif art == "bald" then
                rechts = Farbe("9d9d9d", "bis Stufe " .. (level + K.FERT_BALD))
            end
            local offen = Ueberschrift(Farbe(g.hex, g.text) .. Farbe("9d9d9d", "  (" .. #t .. ")"), false, rechts, nil,
                "fert:" .. art, art == "gelernt" and fertFilter ~= "gelernt", 1)
            if offen then
                sortieren(t)
                for _, e in ipairs(t) do
                    local daten = {
                        titel = e.name .. rangText(e),
                        symbol = e.icon or K.ICON_FAEHIGKEIT,
                        farbe = g.rgb,
                        spellID = e.spellID,
                        hinweis = hinweis(e),
                        quellen = (art ~= "gelernt" and e.trainers) and (function()
                            local l = lehrerListe(e)
                            return #l > 1 and l or nil
                        end)() or nil,
                    }
                    -- Status steht in der Ueberschrift; die Karte nennt nur, was dazu wichtig ist
                    local kat = Farbe("9d9d9d", e.category or "")
                    if art == "jetzt" then
                        daten.rechts = Geld(e.cost)
                        daten.zeile1 = e.gesperrt and (Farbe("ff6655", "Voraussetzung fehlt (z. B. niedrigerer Rang)   ") .. kat) or kat
                        daten.zeile2 = ort(e)
                        daten.hervorheben = not e.gesperrt
                    elseif art == "gelernt" then
                        daten.rechts = e.level and Farbe("9d9d9d", "Stufe " .. e.level) or ""
                        daten.zeile1 = Farbe(g.hex, "Gelernt") .. kat
                        daten.zeile2 = Farbe("777777", "Maus darüber: Beschreibung")
                    else
                        daten.rechts = Farbe(g.hex, "ab Stufe " .. (e.level or "?"))
                        local fehlt = (e.level or level) - level
                        daten.zeile1 = (art == "bald" and Farbe(g.hex, "in " .. fehlt .. " Stufe" .. (fehlt == 1 and "" or "n") .. "   ") or "")
                            .. kat .. ((e.cost and e.cost > 0) and ("   " .. Geld(e.cost)) or "")
                        daten.zeile2 = ort(e)
                    end
                    Karte(daten)
                end
            end
            f.y = f.y + 6
        end
    end

    f.info:SetText(Farbe("44dd55", summen.jetzt .. " jetzt lernbar") .. "   " .. Farbe("4aa3ff", summen.bald .. " bald")
        .. "   " .. Farbe("ffaa00", summen.spaeter .. " später"))
    if not hatKatalog then
        Hinweis("Sprich einmal deinen Klassenlehrer an (Fenster öffnen genügt) - dann erscheint hier, was du lernen kannst.")
    end
    if not hatKatalog and not hatBuch then
        f.info:SetText("")
    elseif f.y == 0 then
        Hinweis("Keine Fähigkeiten passen zu dieser Auswahl.")
    end
end

FensterAktualisieren = function()
    if not Fenster or not Fenster:IsShown() then
        return
    end
    local f = Fenster
    local fr = Fraktion()

    -- Farben je Fraktion
    if f.SetBackdropBorderColor and not O.Spiel() then
        f:SetBackdropBorderColor(fr.rahmen[1], fr.rahmen[2], fr.rahmen[3], 1)
    end
    O.SeitenSync(f)
    local spiel = O.Spiel()
    if f.kopf.SetBackdropColor then
        if spiel then
            -- schmales Banner: dunkler, durchscheinender Grund im Spielrahmen
            f.kopf:SetBackdropColor(0, 0, 0, 0.35)
            f.kopf:SetBackdropBorderColor(0, 0, 0, 0)
        else
            f.kopf:SetBackdropColor(fr.banner[1], fr.banner[2], fr.banner[3], 0.95)
            f.kopf:SetBackdropBorderColor(fr.rahmen[1], fr.rahmen[2], fr.rahmen[3], 0.9)
        end
    end
    if f.portraitRahmen.SetBackdropBorderColor then
        f.portraitRahmen:SetBackdropBorderColor(fr.rahmen[1], fr.rahmen[2], fr.rahmen[3], 1)
    end
    local ansicht, live = AnsichtCharakter()
    ansicht = ansicht or {}
    AuswahllistenZu()
    f.titel:SetText(Farbe(fr.hex, "Reiseführer"))
    if spiel then
        f.charWahl.text:SetText(Farbe("9d9d9d", "Charakter: ") .. (ansicht.fullName or ansicht.name or "?")
            .. Farbe("9d9d9d", " (" .. ((live and UnitLevel("player")) or ansicht.level or "?") .. ")"))
    else
        f.charWahl.text:SetText((ansicht.fullName or ansicht.name or "?") .. Farbe("9d9d9d", live and "  (gerade gespielt)" or "  (letzter Logout)"))
    end
    local token = KlassenKuerzel(ansicht)
    if live and SetPortraitTexture then
        f.portrait:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(f.portrait, "player")
    elseif token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token] then
        f.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        f.portrait:SetTexCoord(unpack(CLASS_ICON_TCOORDS[token]))
    else
        f.portrait:SetTexture(K.ICON_UNBEKANNT)
        f.portrait:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    f.name:SetText(live and VollerName() or (ansicht.fullName or ansicht.name or "?"))
    if spiel then
        f.name:SetTextColor(1, 0.82, 0)
    else
        f.name:SetTextColor(1, 1, 1)
    end
    local klasse, volk, gilde, zone, level
    if live then
        klasse = UnitClass and UnitClass("player") or ""
        volk = UnitRace and UnitRace("player") or ""
        gilde = GetGuildInfo and GetGuildInfo("player")
        zone = (GetRealZoneText and GetRealZoneText()) or ""
        level = UnitLevel("player")
    else
        klasse = (token and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or ansicht.className or ""
        volk = ansicht.race or ""
        zone = (ansicht.zone and (ansicht.zone .. "  -  ") or "") .. "Stand: " .. (ansicht.lastUpdateText or "unbekannt")
        level = ansicht.level
    end
    f.unter:SetText(Farbe(fr.hex, klasse) .. "  " .. Farbe("dddddd", volk)
        .. (gilde and Farbe("aaaaaa", "  <" .. gilde .. ">") or "")
        .. "\n" .. Farbe("aaaaaa", zone))
    f.levelZahl:SetText(level or "?")
    f.levelZahl:SetTextColor(fr.akzent[1], fr.akzent[2], fr.akzent[3])

    -- Levelfortschritt live
    local quests = QuestListe()
    local bereit, offen = 0, 0
    for _, q in ipairs(quests) do
        if q.status == "abgabebereit" then
            bereit = bereit + q.xp
        elseif q.status == "aktiv" then
            offen = offen + q.xp
        end
    end
    local xp, max, erholt
    if live then
        xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
        erholt = GetXPExhaustion and GetXPExhaustion() or 0
    else
        xp, max, erholt = ansicht.xp or 0, ansicht.xpMax or 0, ansicht.xpRested or 0
    end
    local b = f.balken
    local breite = b:GetWidth() - 2
    if max > 0 and breite > 0 then
        local function teilSetzen(t, von, menge)
            local anfang = math.min(von, max) / max * breite
            local laenge = math.min(menge, math.max(0, max - von)) / max * breite
            if laenge < 1 then
                t:Hide()
                return
            end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", b, "TOPLEFT", 1 + anfang, -1)
            t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1 + anfang, 1)
            t:SetWidth(laenge)
            t:Show()
        end
        teilSetzen(b.cur, 0, xp)
        teilSetzen(b.ready, xp, bereit)
        teilSetzen(b.open, xp + bereit, offen)
        if erholt > 0 then
            local stelle = math.min(xp + erholt, max) / max * breite
            b.rest:ClearAllPoints()
            b.rest:SetPoint("TOPLEFT", b, "TOPLEFT", math.max(1, stelle - 1), -1)
            b.rest:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", math.max(1, stelle - 1), 1)
            b.rest:SetWidth(2)
            b.rest:Show()
        else
            b.rest:Hide()
        end
        b.text:SetText(Zahl3(xp) .. " / " .. Zahl3(max) .. "  (" .. math.floor(xp / max * 100) .. " %)")
        local gesamt = xp + bereit + offen
        local fazit
        if xp + bereit >= max then
            fazit = Farbe("44dd55", "Abgabebereite Quests reichen fürs nächste Level!")
        elseif gesamt >= max then
            fazit = Farbe("44dd55", "Mit allen Quests schaffst du das nächste Level.")
        else
            fazit = Farbe("aaaaaa", "Mit allen Quests " .. math.floor(gesamt / max * 100) .. " %")
        end
        f.epText:SetText(Farbe("44dd55", "+" .. Zahl3(bereit) .. " abgabebereit") .. "   "
            .. Farbe("88cc88", "+" .. Zahl3(offen) .. " offen")
            .. (erholt > 0 and ("   " .. Farbe("80b3ff", Zahl3(erholt) .. " erholt")) or "")
            .. "   " .. fazit)
    else
        for _, t in ipairs({ b.cur, b.ready, b.open, b.rest }) do
            t:Hide()
        end
        b.text:SetText("")
        f.epText:SetText(Farbe("aaaaaa", live and "Höchststufe erreicht." or "Levelfortschritt dieses Charakters noch unbekannt - einmal mit ihm einloggen."))
    end
    -- schmales Banner (Spiel-Look) und sein Tooltip
    f.bannerMitte:SetText(Farbe("dddddd", "Stufe " .. (level or "?"))
        .. (max > 0 and Farbe("9d9d9d", "  ·  " .. Zahl3(xp) .. " / " .. Zahl3(max) .. " EP") or ""))
    if max > 0 then
        f.bannerRechts:SetText(Farbe("44dd55", "+" .. Zahl3(bereit) .. " abgabebereit") .. Farbe("9d9d9d", "  ·  ")
            .. Farbe("88cc88", "+" .. Zahl3(offen) .. " offen"))
    else
        f.bannerRechts:SetText(Farbe("9d9d9d", live and "Höchststufe" or "EP unbekannt"))
    end
    f.bannerTipp = { (live and VollerName() or (ansicht.fullName or ansicht.name or "?")),
        Farbe(fr.hex, klasse) .. "  " .. volk .. (gilde and ("  <" .. gilde .. ">") or ""), zone }
    if max > 0 then
        table.insert(f.bannerTipp, " ")
        table.insert(f.bannerTipp, Zahl3(xp) .. " / " .. Zahl3(max) .. " EP  (" .. math.floor(xp / max * 100) .. " %)")
        if erholt > 0 then
            table.insert(f.bannerTipp, Farbe("80b3ff", Zahl3(erholt) .. " EP erholt"))
        end
        local gesamt = xp + bereit + offen
        table.insert(f.bannerTipp, (xp + bereit >= max) and Farbe("44dd55", "Abgabebereite Quests reichen fürs nächste Level!")
            or (gesamt >= max) and Farbe("44dd55", "Mit allen Quests schaffst du das nächste Level.")
            or Farbe("aaaaaa", "Mit allen Quests " .. math.floor(gesamt / max * 100) .. " % des Levels"))
        table.insert(f.bannerTipp, Farbe("9d9d9d", "Balken: lila = erreicht, grün = abgabebereit, hellgrün = offene Quests, blauer Strich = erholt"))
    elseif not live then
        table.insert(f.bannerTipp, Farbe("aaaaaa", "Levelfortschritt noch unbekannt - einmal mit diesem Charakter einloggen."))
    end

    -- Reiter optisch markieren
    for _, r in ipairs(f.reiter) do
        local aktivReiter = r.wert == fensterReiter
        if r.SetBackdropColor then
            if aktivReiter then
                r:SetBackdropColor(fr.banner[1], fr.banner[2], fr.banner[3], 1)
                r:SetBackdropBorderColor(fr.rahmen[1], fr.rahmen[2], fr.rahmen[3], 1)
            else
                r:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
                r:SetBackdropBorderColor(0.35, 0.3, 0.22, 0.9)
            end
        end
        if aktivReiter then
            r.text:SetTextColor(1, 1, 1)
        else
            r.text:SetTextColor(fr.akzent[1] * 0.75, fr.akzent[2] * 0.75, fr.akzent[3] * 0.75)
        end
    end

    -- Zahlen an den Seitenreitern: Rezepte und Faehigkeiten einmal still durchrechnen
    if spiel and type(f.seiten) == "table" and #f.seiten > 0 then
        ListeLeeren(f)
        if fensterReiter ~= "rezepte" then
            RezepteZeigen()
            ListeLeeren(f)
        end
        if fensterReiter ~= "faehigkeiten" then
            FaehigkeitenZeigen()
            ListeLeeren(f)
        end
    end
    ListeLeeren(f)
    local zeigeGebiet = fensterReiter == "quests"
    local zeigeRez = fensterReiter == "rezepte"
    local zeigeFert = fensterReiter == "faehigkeiten"
    local zeigeNotiz = fensterReiter == "notizen"
    if zeigeNotiz and not Notizbuch then
        Notizbuch = NotizbuchBauen()
        O.Lage(f, O.Spiel())
    end
    if Notizbuch then
        Notizbuch:SetShown(zeigeNotiz)
        if not zeigeNotiz and Notizbuch.feld:HasFocus() then
            Notizbuch.feld:ClearFocus()
        end
    end
    f.scroll:SetShown(not zeigeNotiz)
    for _, b in ipairs({ f.rezBerufWahl, f.rezFilter, f.rezSort }) do
        b:SetShown(zeigeRez)
    end
    for _, b in ipairs({ f.fertKatWahl, f.fertFilter, f.fertSort }) do
        b:SetShown(zeigeFert)
    end
    f.gebietLinks:SetShown(zeigeGebiet and not spiel)
    f.gebietRechts:SetShown(zeigeGebiet and not spiel)
    f.gebietWahl:SetShown(zeigeGebiet)
    f.questFilter:SetShown(zeigeGebiet)
    f.kopf:SetShown(not (spiel and zeigeNotiz))
    if zeigeGebiet then
        local gebiete = GebieteListe(quests)
        local hier = live and AktuellesGebiet() or ansicht.zone
        local gueltig = false
        for _, g in ipairs(gebiete) do
            if g == fensterGebiet then
                gueltig = true
            end
        end
        if not gueltig then
            fensterGebiet = nil
            for _, g in ipairs(gebiete) do
                if g == hier then
                    fensterGebiet = hier
                end
            end
            if not fensterGebiet then
                local beste, besteAnzahl = nil, -1
                for _, g in ipairs(gebiete) do
                    local anzahl = 0
                    for _, q in ipairs(quests) do
                        if q.zone == g and (q.status == "aktiv" or q.status == "abgabebereit") then
                            anzahl = anzahl + 1
                        end
                    end
                    if anzahl > besteAnzahl then
                        beste, besteAnzahl = g, anzahl
                    end
                end
                fensterGebiet = beste or hier
            end
        end
        local ginfo = fensterGebiet and GebietInfo(fensterGebiet, quests) or { typ = "zone" }
        f.gebietWahl.icon:SetTexture(K.GEBIET_ART[ginfo.typ].icon)
        f.gebietText:SetText((spiel and Farbe("9d9d9d", "Gebiet: ") or "") .. (fensterGebiet or "?") .. Farbe("9d9d9d", "  " .. StufenText(ginfo))
            .. (fensterGebiet == hier and Farbe("44dd55", "  (hier)") or ""))
        f.gebietLinks:SetEnabled(#gebiete > 1)
        f.gebietRechts:SetEnabled(#gebiete > 1)
        QuestsZeigen(quests)
        f.questFilter:Setzen(Farbe("9d9d9d", "Zeigen: ") .. (K.STATUS[O.questFilter] and Farbe(K.STATUS[O.questFilter].hex, O.QUEST_FILTER_TEXT[O.questFilter])
            or (O.QUEST_FILTER_TEXT[O.questFilter] or "Alle offenen")))
    elseif zeigeNotiz then
        f.info:SetText("")
    elseif zeigeRez then
        RezepteZeigen()
        f.rezBerufWahl:Setzen(rezBeruf or "Alle Berufe", rezBeruf and (K.BERUF_ICON[rezBeruf] or K.ICON_UNBEKANNT) or "Interface\\Icons\\INV_Misc_Book_09")
        f.rezFilter:Setzen(Farbe("9d9d9d", "Zeigen: ") .. Farbe(K.REZ_FILTER_FARBE[rezFilter] or "ffffff", rezFilter == "alle" and "Alle" or (K.REZ_FILTER_TEXT[rezFilter] or rezFilter)))
        f.rezSort:Setzen(K.REZ_SORT_TEXT[rezSort] or rezSort)
    else
        FaehigkeitenZeigen()
        local katIcon
        for _, info in ipairs(fertUebersicht.kategorien) do
            if info.name == fertKategorie then
                katIcon = info.icon
            end
        end
        f.fertKatWahl:Setzen(fertKategorie or "Alle Kategorien", katIcon or K.ICON_FAEHIGKEIT)
        local g = K.FERT_GRUPPE[fertFilter]
        f.fertFilter:Setzen(Farbe("9d9d9d", "Zeigen: ") .. (g and Farbe(g.hex, g.text) or "Alle"))
        f.fertSort:Setzen(K.FERT_SORT_TEXT[fertSort] or fertSort)
    end
    f.inhalt:SetHeight(math.max(10, f.y))
    if spiel and type(f.seiten) == "table" then
        local aktiv, fertig = 0, 0
        for _, q in ipairs(quests) do
            if q.status == "aktiv" then
                aktiv = aktiv + 1
            elseif q.status == "abgabebereit" then
                fertig = fertig + 1
            end
        end
        local rz, fz = rezUebersicht.summen or {}, fertUebersicht.summen or {}
        local zahlen = {
            quests = { aktiv + fertig, (aktiv + fertig) .. " im Questlog" .. (fertig > 0 and (", davon " .. fertig .. " abgabebereit") or "") },
            rezepte = { rz.jetzt or 0, (rz.jetzt or 0) .. " Rezepte jetzt lernbar" },
            faehigkeiten = { fz.jetzt or 0, (fz.jetzt or 0) .. " Fähigkeiten jetzt lernbar" },
        }
        for _, b in ipairs(f.seiten) do
            local z = zahlen[b.wert]
            if b.zahl then
                b.zahl:SetText((z and z[1] > 0) and z[1] or "")
            end
            b.tipp = z and z[2] or nil
        end
    end
    if NotizbuchAktualisieren then
        NotizbuchAktualisieren()
    end
end

local fensterWartet = false
local function FensterSpaeterAktualisieren()
    if not Fenster or not Fenster:IsShown() or fensterWartet then
        return
    end
    fensterWartet = true
    C_Timer.After(1, function()
        fensterWartet = false
        FensterAktualisieren()
    end)
end

-- ---------------------------------------------------------------------------
-- Notizbuch: klappt rechts neben dem Fenster auf. Notizen je Charakter oder fuer
-- den ganzen Account; Umschalten per Auswahlknopf. Gespeichert in den Add-on-Daten.
-- ---------------------------------------------------------------------------

local function NotizModus()
    ForeverDashboardData.settings = ForeverDashboardData.settings or {}
    return ForeverDashboardData.settings.notizModus or "charakter"
end

local function NotizLesen()
    if NotizModus() == "account" then
        return ForeverDashboardData.accountNotes or ""
    end
    local c = AnsichtCharakter()
    return (c and c.notes) or ""
end

local function NotizSchreiben(text)
    if NotizModus() == "account" then
        ForeverDashboardData.accountNotes = text
    else
        local c = AnsichtCharakter()
        if c then
            c.notes = text
        end
    end
end

local function AuswahlKnopf(eltern, text, wert)
    local b = CreateFrame("Button", nil, eltern)
    b:SetSize(130, 20)
    b.kreis = b:CreateTexture(nil, "ARTWORK")
    b.kreis:SetSize(16, 16)
    b.kreis:SetPoint("LEFT", 0, 0)
    b.kreis:SetTexture("Interface\\Buttons\\UI-RadioButton")
    b.text = Schrift(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.kreis, "RIGHT", 6, 0)
    b.text:SetText(text)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.wert = wert
    b.Setzen = function(self, an)
        if an then
            self.kreis:SetTexCoord(0.25, 0.5, 0, 1)
        else
            self.kreis:SetTexCoord(0, 0.25, 0, 1)
        end
    end
    b:SetScript("OnClick", function(self)
        if Notizbuch.feld:HasFocus() then
            Notizbuch.feld:ClearFocus()
        end
        ForeverDashboardData.settings.notizModus = self.wert
        NotizbuchAktualisieren()
    end)
    return b
end

NotizbuchBauen = function()
    -- Notizen als eigener Reiter im Hauptfenster (Platz und Lage setzt O.Lage)
    local n = CreateFrame("Frame", "ForeverDashboardNotizbuch", Fenster)
    n:EnableMouse(true)

    n.wahlChar = AuswahlKnopf(n, "Charakter", "charakter")
    n.wahlChar:SetPoint("TOPLEFT", 4, -2)
    n.wahlAccount = AuswahlKnopf(n, "Ganzer Account", "account")
    n.wahlAccount:SetPoint("LEFT", n.wahlChar, "RIGHT", 10, 0)
    n.fuer = Schrift(n, "GameFontDisableSmall")
    n.fuer:SetPoint("TOPLEFT", 4, -28)
    n.fuer:SetPoint("RIGHT", -4, 0)

    -- Schreibflaeche mit Bildlauf
    local flaeche = CreateFrame("Frame", nil, n, K.BACKDROP_VORLAGE)
    flaeche:SetPoint("TOPLEFT", 0, -46)
    flaeche:SetPoint("BOTTOMRIGHT", 0, 22)
    flaeche.rand = flaeche:CreateTexture(nil, "OVERLAY")
    flaeche.rand:SetPoint("TOPLEFT", -3, 3)
    flaeche.rand:SetPoint("BOTTOMRIGHT", 3, -3)
    flaeche.rand:Hide()
    -- Aussehen: klassisch dunkler Kasten, im Spiel-Look Rahmen wie in Guild ERP
    n.LookSetzen = function(_, spiel)
        local an = spiel and O.Atlas(flaeche.rand, "common-insideframe")
        flaeche.rand:SetShown(an and true or false)
        if flaeche.SetBackdrop then
            if an then
                flaeche:SetBackdrop(K.BACKDROP_DUENN)
                flaeche:SetBackdropColor(0, 0, 0, 0.55)
                flaeche:SetBackdropBorderColor(0, 0, 0, 0)
            else
                flaeche:SetBackdrop(K.BACKDROP_KARTE)
                flaeche:SetBackdropColor(0.02, 0.02, 0.03, 0.9)
                flaeche:SetBackdropBorderColor(0.35, 0.3, 0.22, 0.9)
            end
        end
    end
    local okS, scroll = pcall(CreateFrame, "ScrollFrame", nil, flaeche, "ScrollFrameTemplate")
    if not okS or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, flaeche, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local feld = CreateFrame("EditBox", nil, scroll)
    feld:SetMultiLine(true)
    feld:SetAutoFocus(false)
    feld:SetFontObject("ChatFontNormal")
    feld:SetWidth(400)
    scroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 50 then
            feld:SetWidth(w - 4)
        end
    end)
    feld:SetTextInsets(4, 4, 4, 4)
    if feld.SetMaxLetters then
        feld:SetMaxLetters(0)
    end
    scroll:SetScrollChild(feld)
    feld:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    feld:SetScript("OnTextChanged", function(self, vomSpieler)
        if vomSpieler then
            NotizSchreiben(self:GetText())
            n.gespeichert:SetText("gespeichert")
        end
        n.leer:SetShown(self:GetText() == "" and not self:HasFocus())
    end)
    feld:SetScript("OnEditFocusGained", function() n.leer:Hide() end)
    feld:SetScript("OnEditFocusLost", function(self) n.leer:SetShown(self:GetText() == "") end)
    -- Schreibmarke immer sichtbar halten
    feld:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local oben = -y
        local sicht = scroll:GetVerticalScroll()
        local hoehe = scroll:GetHeight()
        if oben < sicht then
            scroll:SetVerticalScroll(oben)
        elseif oben + h > sicht + hoehe then
            scroll:SetVerticalScroll(oben + h - hoehe)
        end
    end)
    -- Klick irgendwo in die Flaeche setzt die Schreibmarke
    local klick = CreateFrame("Button", nil, flaeche)
    klick:SetAllPoints(scroll)
    klick:SetScript("OnClick", function() feld:SetFocus() end)
    n.leer = Schrift(flaeche, "GameFontDisable")
    n.leer:SetPoint("TOPLEFT", 12, -12)
    n.leer:SetPoint("RIGHT", -30, 0)
    n.leer:SetText("Hier klicken und schreiben ...\n\nz. B. Einkaufsliste, Questziele, Wegpunkte, Termine mit der Gruppe")
    n.feld, n.scroll = feld, scroll

    n.gespeichert = Schrift(n, "GameFontDisableSmall")
    n.gespeichert:SetPoint("BOTTOMLEFT", 4, 4)
    n.hinweis = Schrift(n, "GameFontDisableSmall", false)
    n.hinweis:SetPoint("BOTTOMRIGHT", -4, 4)
    n.hinweis:SetText("Speichert von selbst  -  Esc beendet das Schreiben")
    n:Hide()
    n:LookSetzen(O.Spiel())
    return n
end

NotizbuchAktualisieren = function()
    if not Notizbuch or not Notizbuch:IsShown() then
        return
    end
    local n = Notizbuch
    local modus = NotizModus()
    n.wahlChar:Setzen(modus == "charakter")
    n.wahlAccount:Setzen(modus == "account")
    local c = AnsichtCharakter() or {}
    if modus == "account" then
        n.fuer:SetText("Notizen für alle Charaktere dieses Accounts")
    else
        n.fuer:SetText("Notizen für " .. (c.fullName or c.name or "?"))
    end
    if not n.feld:HasFocus() then
        local text = NotizLesen()
        if n.feld:GetText() ~= text then
            n.feld:SetText(text)
            n.scroll:SetVerticalScroll(0)
        end
        n.leer:SetShown(text == "")
        n.gespeichert:SetText("")
    end
end

-- Notizen-Reiter oeffnen (z. B. mit /fd notiz)
NotizbuchUmschalten = function()
    fensterReiter = "notizen"
    if Fenster and Fenster:IsShown() then
        FensterAktualisieren()
    end
end

local function FensterUmschalten()
    if not Fenster then
        Fenster = FensterBauen()
    end
    if Fenster:IsShown() then
        Fenster:Hide()
    else
        QuestlogEinlesen()
        Fenster:Show()
        -- Breiten stehen erst nach dem ersten Zeichnen fest: einmal kurz danach neu aufbauen
        C_Timer.After(0.05, FensterAktualisieren)
    end
end

-- Nach einem Stufenaufstieg: neu lernbare Faehigkeiten im Chat nennen
local zauberbuchWartet = false
local function FaehigkeitenNachLevelUp(neuesLevel)
    local c = Charakter()
    local token = select(2, UnitClass("player"))
    if not c or not token or not neuesLevel then
        return
    end
    local namen = {}
    for schluessel, e in pairs(KlassenKatalog(token)) do
        local imBuch = c.spellbook and c.spellbook[e.name]
        local kann = (c.spellsKnown and c.spellsKnown[schluessel]) or (imBuch and (imBuch.rang or 0) >= (e.rankNr or 0))
        if e.level == neuesLevel and not kann then
            table.insert(namen, e.name .. ((e.rankNr and e.rankNr > 0) and (" " .. e.rankNr) or ""))
        end
    end
    if #namen > 0 then
        table.sort(namen)
        Melden("|cff44ff44Neu beim Klassenlehrer:|r " .. table.concat(namen, ", "))
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
pcall(frame.RegisterEvent, frame, "PLAYER_XP_UPDATE")
pcall(frame.RegisterEvent, frame, "TRADE_SKILL_SHOW")
pcall(frame.RegisterEvent, frame, "TRADE_SKILL_LIST_UPDATE")
pcall(frame.RegisterEvent, frame, "TRAINER_SHOW")
pcall(frame.RegisterEvent, frame, "TRAINER_UPDATE")
pcall(frame.RegisterEvent, frame, "MERCHANT_SHOW")
pcall(frame.RegisterEvent, frame, "QUEST_DETAIL")
pcall(frame.RegisterEvent, frame, "QUEST_PROGRESS")
pcall(frame.RegisterEvent, frame, "QUEST_COMPLETE")
pcall(frame.RegisterEvent, frame, "QUEST_TURNED_IN")
pcall(frame.RegisterEvent, frame, "QUEST_LOG_UPDATE")
pcall(frame.RegisterEvent, frame, "ZONE_CHANGED_NEW_AREA")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_ADDON")
pcall(frame.RegisterEvent, frame, "GROUP_ROSTER_UPDATE")
pcall(frame.RegisterEvent, frame, "SPELLS_CHANGED")
pcall(frame.RegisterEvent, frame, "LOOT_OPENED")
pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_TAB")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            DatenEinlesen(true)
            local charakter = Charakter()
            if charakter then
                charakter.fullName = VollerName()
            end
            QuestlogEinlesen()
            ZauberbuchEinlesen()
            pcall(O.KnopfZeigen)
            pcall(ServerErledigtLesen)
            pcall(QuestreihenVomSpiel)
            -- Berufe aufraeumen, die einem Charakter faelschlich zugeordnet wurden
            -- (z. B. verlinktes Berufefenster eines anderen Spielers)
            for schl, c in pairs(ForeverDashboardData.characters or {}) do
                local erlaubt = {}
                for _, b in ipairs(c.professions or {}) do
                    erlaubt[b.name] = true
                end
                local live = schl == CharakterSchluessel()
                -- ohne bekannte Berufsliste nichts loeschen (sonst gingen alle Rezepte verloren)
                if next(erlaubt) then
                for feld, sammlung in pairs(c.recipeCollections or {}) do
                    local name = sammlung.professionName
                    if name and not erlaubt[name] and not K.NEBENBERUFE[name] and not (live and BerufGelernt(c, name)) then
                        c.recipeCollections[feld] = nil
                    end
                end
                for name in pairs(c.secondarySkills or {}) do
                    if not erlaubt[name] and not K.NEBENBERUFE[name] and not (live and BerufGelernt(c, name)) then
                        c.secondarySkills[name] = nil
                    end
                end
                end
            end
            -- einmalig (0.9.3): vor dieser Version geteilte Quests ohne Fraktionsangabe.
            -- "Zwerg Pudel" spielt laut Barlor Allianz.
            local e = ForeverDashboardData.settings or {}
            ForeverDashboardData.settings = e
            if not e.umstellung093 then
                e.umstellung093 = true
                for _, q in pairs(QuestWissen()) do
                    if q.discoveredBy == "Zwerg Pudel" and not (q.seenBy and next(q.seenBy)) and not q.seenFactions then
                        q.seenFactions = { Alliance = true }
                    end
                end
            end
            Melden("Version 0.12.1 (Beta) geladen. /fd öffnet das Fenster, /fd info zeigt den Stand im Chat.")
        end)
        SyncStarten()
    elseif event == "SKILL_LINES_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE" then
        C_Timer.After(1.5, FensterSpaeterAktualisieren)
        C_Timer.After(1, function() DatenEinlesen(true) end)
        if event == "PLAYER_LEVEL_UP" then
            local neuesLevel = ...
            C_Timer.After(3, function() FaehigkeitenNachLevelUp(neuesLevel) end)
        end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        if not zauberbuchWartet then
            zauberbuchWartet = true
            C_Timer.After(2, function()
                zauberbuchWartet = false
                ZauberbuchEinlesen()
                FensterSpaeterAktualisieren()
            end)
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        RezepteSpaeterEinlesen()
    elseif event == "TRAINER_SHOW" then
        Grunddaten()
        ForeverDashboardData.diagnostics = ForeverDashboardData.diagnostics or {}
        ForeverDashboardData.diagnostics.trainerShow = date("%Y-%m-%d %H:%M:%S")
        lehrerNachlesen = true
        C_Timer.After(0.5, function() LehrerEinlesen("TRAINER_SHOW", true) end)
    elseif event == "TRAINER_UPDATE" then
        -- die Liste kann erst nach dem Oeffnen vollstaendig sein: pro Fenster EINMAL nachlesen
        if lehrerNachlesen and time() - lehrerLetzterLauf >= 2 then
            lehrerNachlesen = false
            C_Timer.After(1, function() LehrerEinlesen("TRAINER_UPDATE", false) end)
        end
    elseif event == "LOOT_OPENED" then
        C_Timer.After(0.1, function() pcall(BeuteEinlesen) end)
    elseif event == "MERCHANT_SHOW" then
        C_Timer.After(0.5, HaendlerEinlesen)
    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        -- Abgabe-Gespraech: hier steht, wer die Quest annimmt
        C_Timer.After(0.2, function() AbgabeMerken(GetQuestID and GetQuestID()) end)
    elseif event == "QUEST_DETAIL" then
        C_Timer.After(0.3, AngeboteneQuest)
    elseif event == "QUEST_TURNED_IN" then
        local questID, xp = ...
        AbgegebeneQuest(questID, xp)
        QuestlogSpaeterEinlesen()
        C_Timer.After(2, function() pcall(ServerErledigtLesen) end)
    elseif event == "QUEST_LOG_UPDATE" then
        QuestlogSpaeterEinlesen()
        C_Timer.After(2.5, FensterSpaeterAktualisieren)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        AktuellesGebiet()
        C_Timer.After(3, function() pcall(QuestreihenVomSpiel) end)
        if Fenster and Fenster:IsShown() then
            fensterGebiet = nil -- beim Gebietswechsel das neue Gebiet zeigen
            FensterSpaeterAktualisieren()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        SyncGruppeGeaendert()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, kanal, absender = ...
        if prefix == K.SYNC_PREFIX then
            local ok = pcall(SyncEmpfangen, prefix, text, kanal, absender)
            if not ok then
                -- fehlerhafte Nachricht eines anderen Spielers einfach ignorieren
            end
        end
    end
end)

SLASH_FOREVERDASHBOARD1 = "/fd"
SlashCmdList["FOREVERDASHBOARD"] = function(eingabe)
    local roh = strtrim(eingabe or "")
    eingabe = string.lower(roh)
    local zuname = string.match(roh, "^[Zz]uname%s+(.+)$")
    if zuname then
        local charakter = Charakter()
        if charakter then
            charakter.surnameManual = strtrim(zuname)
            charakter.fullName = VollerName()
            Melden("Dein Name als Entdecker: " .. charakter.fullName)
        end
        return
    end
    if eingabe == "zuname" or eingabe == "name" then
        Melden("Dein Name als Entdecker: " .. VollerName()
            .. ". Falsch? Mit /fd zuname <Zuname> festlegen.")
        return
    end
    if eingabe == "sync aus" or eingabe == "sync an" then
        Grunddaten()
        ForeverDashboardData.settings = ForeverDashboardData.settings or {}
        ForeverDashboardData.settings.sync = (eingabe == "sync an")
        SyncAnzeigen()
        return
    end
    if eingabe == "optionen" or eingabe == "options" then
        O.Zeigen()
        return
    end
    if eingabe == "sync" then
        SyncAnzeigen()
        return
    end
    if eingabe == "notiz" or eingabe == "notizen" or eingabe == "notizbuch" then
        if not Fenster or not Fenster:IsShown() then
            FensterUmschalten()
        end
        if not (Notizbuch and Notizbuch:IsShown()) then
            NotizbuchUmschalten()
        end
        return
    end
    if eingabe == "questtest" then
        O.QuestTest()
        return
    end
    if eingabe == "lehrer" then
        LehrerEinlesen("Befehl /fd lehrer", true)
        local d = ForeverDashboardData.diagnostics and ForeverDashboardData.diagnostics.trainer
        if d then
            print("Einträge im Fenster: " .. tostring(d.anzahlEintraege) .. ", Ergebnis: " .. tostring(d.ergebnis))
            for i = 1, math.min(3, #(d.eintraege or {})) do
                print("  " .. d.eintraege[i])
            end
        end
        return
    end
    if eingabe == "recipes" or eingabe == "rezepte" then
        RezepteEinlesen(false)
    elseif eingabe == "quests" or eingabe == "quest" then
        QuestStandAnzeigen()
    elseif eingabe == "katalog" or eingabe == "catalog" then
        KatalogAnzeigen()
    elseif eingabe == "info" or eingabe == "stand" then
        DatenEinlesen(false)
    else
        DatenEinlesen(true)
        FensterUmschalten()
    end
end
