local L = LibStub("AceLocale-3.0"):GetLocale("MythicAudit");

-------------------------------------------------------------------------------
-- The message passed between clients is structured as such:
--     "PlayerName-PlayerClass-PlayerHighestCompleted"
-- as a single string, and should be treated with types as such:
--     "String-String-Integer"
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Globals, constants, statics, enums, etc.
-------------------------------------------------------------------------------

local gVersion       = "1.0.1.1";
local gPlayerName    = UnitName("player");
local _,gPlayerClass = UnitClass("player");
local gWeekInSeconds = 604800;
local gResetTime_NA  = 1486479600;
local gResetTime_EU  = 1485327600;

local gClassColors = {
    ["DEATHKNIGHT"] = "|cffC41F3B",
    ["DEMONHUNTER"] = "|cffA330C9",
    ["DRUID"]   = "|cffFF7D0A",
    ["HUNTER"]  = "|cffABD473",
    ["MAGE"]    = "|cff69CCF0",
    ["MONK"]    = "|cff00FF96",
    ["PALADIN"] = "|cffF58CBA",
    ["PRIEST"]  = "|cffffffff",
    ["ROGUE"]   = "|cffFFF569",
    ["SHAMAN"]  = "|cff0070DE",
    ["WARLOCK"] = "|cff9482C9",
    ["WARRIOR"] = "|cffC79C6E"
};

local gWeeklyChestItemLevels = {
    [2]  = 875,
    [3]  = 880,
    [4]  = 885,
    [5]  = 890,
    [6]  = 890,
    [7]  = 895,
    [8]  = 895,
    [9]  = 900,
    [10] = 905
};

MADB = { week = 604800, resetTime };

-------------------------------------------------------------------------------
-- pragma mark Application Impl and Event Handling
-------------------------------------------------------------------------------
local addon = CreateFrame("Frame", nil, UIParent);
addon:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end);
addon:RegisterEvent("ADDON_LOADED");
addon:RegisterEvent("PLAYER_LOGIN");
addon:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE");
addon:RegisterEvent("GUILD_ROSTER_UPDATE");
addon:RegisterEvent("UNIT_QUEST_LOG_CHANGED");
addon:RegisterEvent("CHAT_MSG_ADDON");

function addon:ADDON_LOADED(addonName)
    if addonName == "Mythic Audit" then
        addon:UnregisterEvent("ADDON_LOADED");
        MAPlayerDB = MAPlayerDB or {};
    end
end

function addon:PLAYER_LOGIN()
    MA_WeeklyReset();
    C_ChallengeMode.RequestMapInfo(); -- MA_UpdateMyHighestCompleted();
    DEFAULT_CHAT_FRAME:AddMessage(MA_GetGreetingString());
end

function addon:CHALLENGE_MODE_MAPS_UPDATE()
    if MA_UpdateMyHighestCompleted() then
        DEFAULT_CHAT_FRAME:AddMessage(MA_GetNewHighestCompletedString());
    end
end

function addon:GUILD_ROSTER_UPDATE()
    MA_SendDatabase();
end

function addon:UNIT_QUEST_LOG_CHANGED()
    MA_WeeklyReset();
end

-------------------------------------------------------------------------------
-- Database Management and Client Communication
-------------------------------------------------------------------------------

function addon:CHAT_MSG_ADDON(prefix, message, channel, sender)
    -- this is to make sure we're able to register to the addon (lua errors, permission, etc.)
    local wasAbleToRegister = RegisterAddonMessagePrefix(MA_GetAddonMessagePrefixString());
    if prefix == MA_GetAddonMessagePrefixString() then
        if wasAbleToRegister == true then
            local senderName = string.match(sender, "%a+");
            if senderName == gPlayerName or string.find(message, gPlayerName) then
                -- do nothing, because we do not want to process or own info
            else
                -- otherwise, store this users info in our local database
                MA_WriteToDatabase(message);
            end
        end
    end
end

function MA_SendDatabase()
    for data in pairs(MAPlayerDB) do
        local char = MAPlayerDB[data];
        if char.NAME ~= gPlayerName then
            MA_SendKey(MA_ConstructFullKeyMessageString(char.NAME, char.CLASS, char.HIGHEST));
        end
    end
end

function MA_SendKey(message)
    SendAddonMessage(MA_GetAddonMessagePrefixString(), message, "GUILD");
end

function MA_WriteToDatabase(message)
    local name, class, highest = MA_DeconstructFullKeyMessageString(message);
    MAPlayerDB[name] = {
        NAME    = name,
        CLASS   = class,
        HIGHEST = highest
    };
end

-------------------------------------------------------------------------------
-- Utility and Helper Functions
-------------------------------------------------------------------------------
function MA_ConstructFullKeyMessageString(playerName, playerClass, highestCompleted)
    -- local playerName     = UnitName("player");
    -- local _, playerClass = UnitClass("player");

    if highestCompleted == nil then highestCompleted = 0; end
    return playerName .. "-" .. playerClass .. "-" .. highestCompleted;
end

function MA_DeconstructFullKeyMessageString(message)
    return strsplit("-", message);
end

function MA_UpdateMyHighestCompleted()
    -- it was reported to me on 04.07.2017 that this always returns 0 for some users.
    -- that sounds impossible/highly unlikely, but test it anyways.

    -- this might be the reason why
    -- ==> C_ChallengeMode.RequestMapInfo();

    local maps = C_ChallengeMode.GetMapTable();
    local maxCompleted = 0;

    for _, mapID in pairs(maps) do
        local _, _, level, affixes = C_ChallengeMode.GetMapPlayerStats(mapID);
        if level and level > maxCompleted then
            maxCompleted = level;
        end
    end

    if not maxCompleted then maxCompleted = 0; end

    if MAPlayerDB[gPlayerName] then
        local completedNewHigher = false;
        local currentHighest = tonumber(MAPlayerDB[gPlayerName].HIGHEST);
        if currentHighest <= maxCompleted then
            completedNewHigher = false;
        else
            completedNewHigher = true;
        end

        local message = MA_ConstructFullKeyMessageString(gPlayerName, gPlayerClass, maxCompleted);
        MA_WriteToDatabase(message);
        MA_SendKey(message);

        return completedNewHigher;
    else
        local message = MA_ConstructFullKeyMessageString(gPlayerName, gPlayerClass, maxCompleted);
        MA_WriteToDatabase(message);
        MA_SendKey(message);

        return false;
    end

    return false;
end

function MA_WeeklyReset()
    local currentTime = GetServerTime();
    local region      = GetCurrentRegion();
    local week        = gWeekInSeconds;
    local resetNA     = gResetTime_NA;
    local resetEU     = gResetTime_EU;
    local resetTime;

    if (region == 1) then
        resetTime = resetNA;
    elseif (region == 3) then
        resetTime = resetEU;
    else
        resetTime = resetNA;
    end
    
    if (MADB.resetTime ~= nil) then
        resetTime = MADB.resetTime;
    end

    if (resetTime < currentTime) then
        repeat
            resetTime = resetTime + week;
        until (resetTime > currentTime);
        DEFAULT_CHAT_FRAME:AddMessage(MA_GetResettingDatabaseString());
        MAPlayerDB = {};
    end
    MADB.resetTime = resetTime;
end

function MA_DumpDatabase()
    for data in pairs(MAPlayerDB) do
        local toon = MAPlayerDB[data];
        local str = gClassColors[toon.CLASS]..toon.NAME.."|r: "..((tonumber(toon.HIGHEST) >= 10 and '|cff00ff00' .. toon.HIGHEST) or toon.HIGHEST);
        if tonumber(toon.HIGHEST) > 0 then
            str = str .. string.format('|r (%d)', gWeeklyChestItemLevels[tonumber(toon.HIGHEST)] or 9005);
        end
        DEFAULT_CHAT_FRAME:AddMessage(str);
    end
end

function MA_GetCurrentTime()
    -- this function is currently unused
    local date = date();
    local hour, minute = GetGameTime();

    local j   = 0;
    local day = {};
    for tod in string.gmatch(date, "[^ ]+") do
        day[j] = tod;
        j = j + 1;
    end

    return (day[0] .. "-" .. hour .. ":" .. minute);
end

-------------------------------------------------------------------------------
-- GUI
-------------------------------------------------------------------------------
MyModData = {}

function MyMod_OnLoad()
    MyMod:Hide()
end

function MyMod_OnShow()
    local index = 1;
    for data in pairs(MAPlayerDB) do
        local toon = MAPlayerDB[data];
        local str = gClassColors[toon.CLASS]..toon.NAME.."|r - "..((tonumber(toon.HIGHEST) >= 10 and '|cff00ff00' .. toon.HIGHEST) or toon.HIGHEST);
        if tonumber(toon.HIGHEST) > 0 then
            str = str .. string.format('|r (%d)', gWeeklyChestItemLevels[tonumber(toon.HIGHEST)] or 905);
        end
        MyModData[index] = str;
        index = index + 1;
    end
    MyMod:EnableMouse(true)
    MyMod:SetMovable(true)
    MyMod:RegisterForDrag("LeftButton")
    MyMod:SetScript("OnDragStart", MyMod.StartMoving)
    MyMod:SetScript("OnDragStop", MyMod.StopMovingOrSizing)
    MyMod:Show()
end

function MyModScrollBar_Update()
    local line; -- 1 through 5 of our window to scroll
    local lineplusoffset; -- an index into our data calculated from the scroll offset
    FauxScrollFrame_Update(MyModScrollBar, 50, 8, 16);
    for line = 1, 8 do
        lineplusoffset = line + FauxScrollFrame_GetOffset(MyModScrollBar);
        if lineplusoffset <= 50 then
            getglobal("MyModEntry"..line):SetText(MyModData[lineplusoffset]);
            getglobal("MyModEntry"..line):Show();
        else
            getglobal("MyModEntry"..line):Hide();
        end
    end
end

-------------------------------------------------------------------------------
-- Localization and Global String Retrieval and Construction
-------------------------------------------------------------------------------

function MA_GetGreetingString()
    return "|cff965573" .. L["Mythic Audit: "] .. "|r" .. L[" Loaded - v"] .. gVersion;
end

function MA_GetMyHighestCompletedString()
    return "|cff965573" .. L["Mythic Audit: "] .. "|r" .. L["Highest Mythic+ Dungeon Completed This Week: "] .. MAPlayerDB[gPlayerName].HIGHEST;
end

function MA_GetNewHighestCompletedString()
    return "|cff965573" .. L["Mythic Audit: "] .. "|r" .. L["Congratulations! New Highest Weekly Mythic+: "] .. MAPlayerDB[gPlayerName].HIGHEST;
end

function MA_GetResettingDatabaseString()
    return "|cff965573" .. L["Mythic Audit: "] .. "|r" .. L["Weekly Server Reset - Resetting MADatabase..."];
end

function MA_GetAddonMessagePrefixString()
    -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    -- NOTE: this cannot change, if it does, it requires a full powercycle on the addon
    -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    return "MAuditK";
end

-------------------------------------------------------------------------------
-- Forward Slash Commands
-------------------------------------------------------------------------------

SLASH_MYTHICAUDIT1 = "/maudit";
SlashCmdList["MYTHICAUDIT"] = function(msg)
    if msg and msg == 'reset' then
        MADB.resetTime = 0;
        MA_WeeklyReset();
        C_ChallengeMode.RequestMapInfo();
    else
        MyMod_OnShow();
        -- MA_DumpDatabase();
    end
end
