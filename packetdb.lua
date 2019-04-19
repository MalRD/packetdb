--[[
 *  The MIT License (MIT)
 *
 *  Copyright (c) 2015 MalRD
 *  
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to 
 *  deal in the Software without restriction, including without limitation the 
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or 
 *  sell copies of the Software, and to permit persons to whom the Software is 
 *  furnished to do so, subject to the following conditions:
 *  
 *  The above copyright notice and this permission notice shall be included in 
 *  all copies or substantial portions of the Software.
 *  
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
 *  DEALINGS IN THE SOFTWARE.
]]--

require 'pack'
file = require 'files'
sqlite = require 'sqlite3'
res = require 'resources'
bit = require('bit')

_addon.version = '1.0.1'
_addon.name = 'PacketDB'
_addon.author = 'MalRD'
_addon.commands = {'pdb','packetdb'}

local settings = 
{
    isRunning	=	true,
    playerName	=	nil,
    batchSize	=	100,
    packet_file	=	nil,
    packetBatch	=	0,
    text_file	=	nil,
    textBatch	=	0
};

local PACKET_SQL	= 'INSERT INTO PACKETS (DIRECTION, ZONE_ID, PACKET_TYPE, PACKET_SIZE, PACKET_SYNC, PACKET_DATA) VALUES (?, ?, ?, ?, ?, ?);';
local TEXT_SQL		= 'INSERT INTO CHATLOG (DIRECTION, ZONE_ID, CHAT_TEXT) VALUES (?, ?, ?);';

local db = nil;
local QUERY = 
{
    INSERT_PACKET	=	nil,
    INSERT_TEXT		=	nil
};

local DIRECTION = 
{
    INCOMING	=	0,
    OUTGOING	=	1
};

windower.register_event('load', function()
    if not windower.dir_exists(windower.addon_path..'data\\') then
        windower.create_dir(windower.addon_path..'data\\')
    end
    
    if windower.ffxi.get_player() then
        settings.playerName = windower.ffxi.get_player().name;
    end
    
    print(sqlite.version());
    db = openDB(nil);
end)

windower.register_event('unload', function()
    if settings.packet_file ~= nil then
        settings.packet_file:flush();
        settings.packet_file:close();
        settings.packet_file = nil;
    end
    
    if settings.text_file ~= nil then
        settings.text_file:flush();
        settings.text_file:close();
        settings.text_file = nil;
    end
    
    if QUERY.INSERT_PACKET ~= nil then
        QUERY.INSERT_PACKET:finalize();
    end
    
    if QUERY.INSERT_TEXT ~= nil then
        QUERY.INSERT_TEXT:finalize();
    end
    
    if db ~= nil then
        db:close();
    end
end)

windower.register_event('login', function(name)
    settings.playerName = windower.ffxi.get_player().name;
end)

windower.register_event('logout', function(name)
    settings.playerName = nil;
end)

windower.register_event('addon command', function(command, ...)
    local args = {...}
    command = command and command:lower()
    if command then
        if command:lower() == 'start' then
            settings.isRunning = true;
        elseif command:lower() == 'stop' then
            settings.isRunning = false;
        end
    end
end)

windower.register_event('incoming text',function (original, modified, original_mode, modified_mode, is_blocked)
    if settings.isRunning then
        insertText(DIRECTION.INCOMING, original);
    end
    
    return false;
end)

windower.register_event('incoming chunk',function (id,original,modified,is_injected,is_blocked)
    if settings.isRunning then
        insertPacket(DIRECTION.INCOMING, original);
    end
    
    return false;
end)

windower.register_event('outgoing text',function (original, modified, is_blocked)
    if settings.isRunning then
        insertText(DIRECTION.OUTGOING, original);
    end
    
    return false;
end)

windower.register_event('outgoing chunk',function (id,original,modified,is_injected,is_blocked)
    if settings.isRunning then
        insertPacket(DIRECTION.OUTGOING, original);
    end
    
    return false;
end)

function openDB(filename)
    if db ~= nil then
        db:close();
        db = nil;
    end
    
    if filename == nil then
        local filestamp = os.date('%Y%m%d%H%M%S',os.time());
        local prefix = settings.playerName;
        if prefix == nil then
            prefix = 'Default';
        end
        filename = string.format('data\\%s.%s.sqlite', prefix, filestamp);
    end
    
    db, code, msg = sqlite.open(windower.addon_path .. filename);
    if db == nil then
        print(string.format('Unable to open database [%s] [%s]', code, msg));
    end
    
    setupDB();
    return db;
end

function setupDB()	
    db:exec[=[
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS PACKETS 
      (
        PACKET_ID	INTEGER 	PRIMARY KEY	ASC,
        RECEIVED_DT DATETIME 	NOT NULL	DEFAULT CURRENT_TIMESTAMP,
        DIRECTION	INT(1)		NOT NULL,
        ZONE_ID		INT(5),
        PACKET_TYPE	INT(5)		NOT NULL,
        PACKET_SIZE	INT(5)		NOT NULL,
        PACKET_SYNC INT(5)		NOT NULL,
        PACKET_DATA	TEXT		NOT NULL
      );
      
      CREATE TABLE IF NOT EXISTS CHATLOG 
      (
        CHAT_ID		INTEGER 	PRIMARY KEY ASC,
        RECEIVED_DT DATETIME 	NOT NULL	DEFAULT CURRENT_TIMESTAMP,
        DIRECTION	INT(1)		NOT NULL,
        ZONE_ID		INT(5),
        CHAT_TEXT	TEXT		NOT NULL
      );	  
      
      CREATE TABLE IF NOT EXISTS ZONES 
      (
        ZONE_ID		INT(12) 	NOT NULL 	PRIMARY KEY,
        ZONE_NAME	TEXT
      );
      
      CREATE TABLE IF NOT EXISTS PACKET_DEFINITION
      (
        DEFINITION_ID	INTEGER		PRIMARY KEY	ASC,
        DIRECTION		INT(1)		NOT NULL,
        PACKET_TYPE		INT(5)		NOT NULL,
        PACKET_SIZE		INT(5)		NOT NULL,
        PACKET_NAME		TEXT		,
        PACKET_DESC		TEXT
      );
      
      INSERT INTO PACKET_DEFINITION (DIRECTION, PACKET_TYPE, PACKET_SIZE, PACKET_NAME, PACKET_DESC) VALUES
      (1, 0x00A, 0, 'LogIntoZone', 'Sent when player reaches a zone line.'),
      (1, 0x00C, 0, 'CharInfoRequest', 'Requests information on player when zoning or logging in.'),
      (1, 0x00D, 0, 'LogOutOfZone', 'Sent when a player leaves a zone or logs out.'),
      (1, 0x00F, 0, 'PlayerInfoRequest', 'Requests information on player.'),
      (1, 0x011, 0, 'ZoneTransitionConfirmation', 'Client confirmation sent after zoning or logging in.'),
      (1, 0x015, 0, 'PlayerSync', 'Updates player position and other status.'),
      (1, 0x016, 0, 'EntityInfoRequest', 'Requests information on an entity.'),
      (1, 0x017, 0, 'InvalidNPCInforequest', 'UNKNOWN'),
      (1, 0x01A, 0, 'PlayerAction', 'Sents a packet with information about characater action.'),
      (1, 0x01B, 0, 'WorldPassRequest', 'Requests information about world pass.'),
      (1, 0x01C, 0, 'GenericInfoRequest', 'UNKNOWN - appears to be the client trying to get missing information (sent during DCs and etc).'),
      (1, 0x028, 0, 'ItemDispose', 'Informs server an item is being dropped.'),
      (1, 0x029, 0, 'ItemMovement', 'Informs server an item is being moved between inventories.'),
      (1, 0x032, 0, 'TradeRequest', 'Requests a trade between charid and targid.'),
      (1, 0x033, 0, 'TradeActionRequst', 'Sent when accept / cancel / deny trade request.'),
      (1, 0x034, 0, 'TradeSlotUpdate', 'Sends updated trade slot information.'),
      (1, 0x036, 0, 'TradeComplete', 'Finalizes trade.'),
      (1, 0x037, 0, 'ItemUse', 'Sends attempt to use an item.'),
      (1, 0x03A, 0, 'SortInventory', 'Sends a request to sort a player''s inventory.'),
      (1, 0x03C, 0, 'Unknown', 'UNKNOWN - Empty response for NPCs/monsters/players?'),
      (1, 0x03D, 0, 'UpdateBlacklist', 'Attempt to add or remove someone from blacklist.'),
      (1, 0x041, 0, 'TreasurePoolLot', 'Lot on an item in the treasure pool.'),
      (1, 0x042, 0, 'TreasurePoolPass', 'Pass on item in the treasure pool.'),
      (1, 0x04B, 0, 'ServerMessageRequest', 'Requests the server message.'),
      (1, 0x04D, 0, 'DeliveryBox', 'Working with delivery boxes.'),
      (1, 0x04E, 0, 'AuctionHouse', 'Working with the auction house.'),
      (1, 0x050, 0, 'EquipmentChange', 'Attempt to change equipment in a slot.'),
      (1, 0x051, 0, 'EquipmentSetChange', 'Attempt to change to an equipment set.'),
      (1, 0x052, 0, 'AddToEquipSet', 'Checks if an item can be added to a gear / lockstyle set.'),
      (1, 0x053, 0, 'LockStyleSet', 'Requests a style to be locked.'),
      (1, 0x058, 0, 'SynthesisSuggestionRequest', 'Requests a synthesis based on skill and level.'),
      (1, 0x059, 0, 'SynthesisComplete', 'Informs server of synthesis completion.'),
      (1, 0x05A, 0, 'MapUpdate', 'Requests information to update conquest / besigned / campaign.'),
      (1, 0x05B, 0, 'EventUpdate', 'Request event update or event completion.'),
      (1, 0x05C, 0, 'EventUpdatePosition', 'Updates player position during event.'),
      (1, 0x05D, 0, 'EmoteJob', 'Attempt to use a job emote.'),
      (1, 0x05E, 0, 'ZoneLineRequest', 'Request zoning.'),
      (1, 0x060, 0, 'EventStringUpdate', 'Send string for user entered text during events (Oztroja password).'),
      (1, 0x061, 0, 'CharUpdateRequest', 'Request update for character data.'),
      (1, 0x063, 0, 'ChocoboDigging', 'UNKNOWN - Chocobo digging.'),
      (1, 0x064, 0, 'KeyItemSeen', 'Mark key item as seen.'),
      (1, 0x066, 0, 'FishingAction', 'OLD - fishing action from old fishing.'),
      (1, 0x06E, 0, 'PartyInvite', 'Invite a player to join a party or alliance.'),
      (1, 0x06F, 0, 'PartyLeave', 'Leave a party or alliance.'),
      (1, 0x070, 0, 'PartyDissolve', 'Dissolve a party or alliance.'),
      (1, 0x071, 0, 'KickCommand', 'Kick a player from a party or linkshell or a party from an alliance.'),
      (1, 0x074, 0, 'PartyInviteResponse', 'Respond to a party/alliance invite (accept, decline, leave).'),
      (1, 0x076, 0, 'PartyListRequest', 'Requst information on party members.'),
      (1, 0x077, 0, 'ChangeRank', 'Change a player''s rank in party, alliance, or linkshell.'),
      (1, 0x078, 0, 'PartySearch', 'UNKNOWN - party search stuff?'),
      (1, 0x083, 0, 'ItemPurchaseVendor', 'Purchase an item from a vendor.'),
      (1, 0x084, 0, 'ItemAppraiseVendor', 'Appraise an item at a vendor.'),
      (1, 0x085, 0, 'ItemSellVendor', 'Sell an item to a vendor.'),
      (1, 0x096, 0, 'SynthesisBegin', 'Begin synthesis of an item.'),
      (1, 0x0AA, 0, 'ItemPurchaseGuild', 'Purchase an item from a guild.'),
      (1, 0x0A2, 0, 'DiceRoll', 'Roll some dice.'),
      (1, 0x0AB, 0, 'GuildVendorStockRequest', 'Requests the items a guild vendor sells.'),
      (1, 0x0AC, 0, 'ItemSellGuild', 'Sell item to a guild.'),
      (1, 0x0AD, 0, 'GuildVendorStockRequest', 'Requests the items a guild vendor sells.'),
      (1, 0x085, 0, 'ChatMessage', 'Sends chat.'),
      (1, 0x0B6, 0, 'TellMessage', 'Sends a tell to a player.'),
      (1, 0x0BE, 0, 'MeritMode', 'Set experience mode to normal/merit or raise/lower merit.'),
      (1, 0x0C3, 0, 'CreateLinkpearl', 'Creates a linkperl for the specified shell.'),
      (1, 0x0C4, 0, 'CreateLinkshell', 'Creates a new linkshell.'),
      (1, 0x0CB, 0, 'OpenCloseMogHouse', 'Allow or disallow other players from entering your house.'),
      (1, 0x0D2, 0, 'PartyMapRequest', 'Requests positions of party members for map.'),
      (1, 0x0D3, 0, 'HelpDeskreport', 'Sent when using the help desk option.'),
      (1, 0x0DC, 0, 'NameFlag', 'Set name plate flags (invite, anon, autoTarget).'),
      (1, 0x0DB, 0, 'PreferredLanguage', 'Set the preferred language for search.'),
      (1, 0x0DD, 0, 'CheckTarget', 'Checks a target''s statistics.'),
      (1, 0x0DE, 0, 'SetBazaarMessage', 'Sets the player''s bazaar message.'),
      (1, 0x0E0, 0, 'SetSearchMessage', 'Sets the player''s search message.'),
      (1, 0x0E1, 0, 'LinkshellMessageRequest', 'Request linkshell message.'),
      (1, 0x0E2, 0, 'LinkshellMessageUpdate', 'Update linkshell mesage.'),
      (1, 0x0E7, 0, 'ExitGame', 'Logout or shutdown the game.'),
      (1, 0x0E8, 0, 'Heal', '/heal command.'),
      (1, 0x0EA, 0, 'Sit', '/sit command.'),
      (1, 0x0F1, 0, 'CancelStatusEffect', 'Requests status effect cancel.'),
      (1, 0x0F2, 0, 'UpdatePlayerZoneBoundary', 'UNKNOWN'),
      (1, 0x0F4, 0, 'WideScan', 'Attempt to populate widescan information.'),
      (1, 0x0F5, 0, 'WideScanTrack', 'Track an entity with widescan.'),
      (1, 0x0F6, 0, 'WideScanCancel', 'Cancel tracking an entity.'),
      (1, 0x0FA, 0, 'PlaceFurniture', 'Place furniture in the Mog House.'),
      (1, 0x0FB, 0, 'RemoveFurniture', 'Remove furniture from Mog House.'),
      (1, 0x100, 0, 'ChangeJob', 'Change character''s main or sub job.'),
      (1, 0x102, 0, 'SetBlueMagic', 'Set blue magic spell.'),
      (1, 0x104, 0, 'ExitBazaar', 'Exits a character''s bazaar.'),
      (1, 0x105, 0, 'EnterBazaar', 'Enters a character''s bazaar.'),
      (1, 0x106, 0, 'PurchaseBazaar', 'Purchase an item from a bazaar.'),
      (1, 0x109, 0, 'EndPricingBazaar', 'Finalizes items for sale in bazaar.'),
      (1, 0x10A, 0, 'SetPriceBazaar', 'Sets the bazaar price on an item.'),
      (1, 0x10B, 0, 'StartPricingBazaar', 'Opens the bazaar to set prices on items.'),
      (1, 0x10F, 0, 'Currency1Request', 'Requests currency 1 tab information.'),
      (1, 0x111, 0, 'LockStyleRequest', 'Old lockstyle request.'),
      (1, 0x115, 0, 'Currency2Request', 'Requests currency 2 tab information.')
      ;

      INSERT INTO PACKET_DEFINITION (DIRECTION, PACKET_TYPE, PACKET_SIZE, PACKET_NAME, PACKET_DESC) VALUES
      (0, 0x008, 0x1A, 'ZoneVisited', 'Sends a list of zones the character has visited.'),
      (0, 0x009, 0x00, 'MessageStandard', 'Sends message ID and up to four parameters with size varying.'),
      (0, 0x009, 0x08, 'MessageStandard', 'Sends message ID.'),
      (0, 0x009, 0x12, 'MessageStandard', 'Sends message ID with character and target IDs or param0 and param1.'),
      (0, 0x009, 0x18, 'MessageStandard', 'Sends message ID character name and one param.'),
      (0, 0x009, 0x30, 'MessageStandard', 'Sends message ID with character and target IDs and character name.'),
      (0, 0x00A, 0x82, 'ZoneIn', 'Sends information to client about new zone and character.'),
      (0, 0x00B, 0x0E, 'ServerIP', 'Sends the server IP.'),
      (0, 0x00D, 0x36, 'Char', 'Entity spawn/despawn/update.'),
      (0, 0x00E, 0x1C, 'EntityUpdate', 'Updates NPCs, mobs, and pets.'),
      (0, 0x00E, 0x24, 'EntityUpdate', 'Updates names, equipped/chocobo/door/elevator/ship.'),
      (0, 0x013, 0x6F, 'Currency1', 'Sends currency 1 information.'), -- May be 113
      (0, 0x016, 0x23, 'AddToEquip', 'Tells the client if the supplied item can be added to the set.'),
      (0, 0x017, 0x00, 'ChatMessage', 'Sends a chat message. Size varies with message length between 32 and 128.'),
      (0, 0x018, 0x25, 'Currency2', 'Sends currency 2 information.'), -- May be 118
      (0, 0x019, 0x7F, 'CharRecast', 'Sends ability recast information'),
      (0, 0x01B, 0x32, 'CharJobs', 'Sends character race, current jobs, hp/mp, unlocked jobs, etc.'),
      (0, 0x01C, 0x1A, 'InventorySize', 'Sends size of each inventory and Mog Locker access status.'),
      (0, 0x01D, 0x04, 'InventoryFinish', 'Finalizes inventory modification.'),
      (0, 0x01E, 0x08, 'InventoryModify', 'Sends container/slot id and quantity.'),
      (0, 0x01F, 0x08, 'InventoryAssign', 'Sends container/slot id, quantity, item id, and a flag (no drop, linkshell, etc).'),
      (0, 0x020, 0x16, 'InventoryItem', 'Sends container/slot id, quantity, price, ID, extra, and etc for an item in the player''s inventory.'),
      (0, 0x021, 0x06, 'TradeRequest', 'Sends character ID and target ID for trade.'),
      (0, 0x022, 0x08, 'TradeAction', 'Sends character ID, target ID, and trade action.'),
      (0, 0x023, 0x14, 'TradeUpdate', 'Sends updated trade slot information to trade target from trade slot update.'),
      (0, 0x025, 0x06, 'TradeItem', 'Sends updated inventory information based on trade slot update.'),
      (0, 0x027, 0x38, 'CaughtFish', 'Sends caught fish message.'),
      (0, 0x028, 0x00, 'Action', 'Sends action information.'),
      (0, 0x029, 0x0E, 'MessageBasic', 'Displays a message on the client based on supplied parameters.'),
      (0, 0x02A, 0x10, 'MessageSpecial', 'Displays a message based on parameters.'),
      (0, 0x02A, 0x18, 'MessageSpecial', 'Displays a message based on parameters.'),
      (0, 0x02D, 0x0E, 'MessageDebug', 'Displays a message on the client based on supplied parameters.'),
      (0, 0x02E, 0x02, 'MenuMog', 'UNKNOWN'),
      (0, 0x02F, 0x06, 'ChocoboDigging', 'Sends character ID and target ID for successful digging with a chocobo.'),
      (0, 0x030, 0x08, 'SynthAnimation', 'Sends synthesis animation.'),
      (0, 0x031, 0x1A, 'SynthSuggestion', 'Sends synthesis suggestion packet.'),
      (0, 0x032, 0x0A, 'Event', 'Sends event start.'),
      (0, 0x033, 0x38, 'EventString', 'Sends event string with up to 8 parameters.'),
      (0, 0x034, 0x1A, 'Event', 'Sends event start with up to 8 parameters.'),
      (0, 0x036, 0x08, 'MessageText', 'Displays a message in a specific mode.'),
      (0, 0x037, 0x2E, 'CharUpdate', 'Updates character status, name plate, speed, animations, and etc.'),
      (0, 0x038, 0x0A, 'EntityAnimation', 'Animates entity.'),
      (0, 0x039, 0x0A, 'EntityVisual', 'Some entity visual stuff.'),
      (0, 0x03C, 0x00, 'ShopItems', 'Sends shop items. Size varies depending on number the NPC sells.'),
      (0, 0x03D, 0x08, 'ShopAppraise', 'Sends slot ID and price.'),
      (0, 0x03E, 0x04, 'ShopMenu', 'Sends count of items in the menu.'),
      (0, 0x03F, 0x06, 'ShopBuy', 'Sends slot ID and quantity.'),
      (0, 0x041, 0x7C, 'StopDownloading', 'Sends blacklist information and ends the downloading data screen.'),
      (0, 0x042, 0x0E, 'Blacklist', 'Sends add, remove, or error response for blacklist management.'),
      (0, 0x044, 0x4E, 'CharJobExtra', 'Sends extra information for BLU and PUP.'),
      (0, 0x04B, 0x0A, 'DeliveryBox', 'Sends delivery box errors.'),
      (0, 0x04B, 0x2C, 'DeliveryBox', 'Sends delivery box status.'),
      (0, 0x04C, 0x1E, 'AuctionHouse', 'Sends auction house status.'),
      (0, 0x04D, 0x00, 'ServerMessage', 'Sends server message. Size depends on message size.'),
      (0, 0x04F, 0x04, 'DownloadingData', 'Starts the downloading data screen.'),
      (0, 0x050, 0x04, 'Equip', 'Sends equip slot id, item slot id, and container id.'),
      (0, 0x051, 0x0C, 'CharAppearance', 'Sends updated character appearance.'),
      (0, 0x052, 0x04, 'Release', 'Releases character from movement lock (cutscenes and dialog ending, etc).'),
      (0, 0x053, 0x08, 'MessageSystem', 'Sends param0, param1, and messageID.'),
      (0, 0x055, 0x44, 'KeyItems', 'Sends owned key items.'),
      (0, 0x056, 0x14, 'QuestMissionLog', 'Sends mission log information.'),
      (0, 0x057, 0x06, 'Weather', 'Sends weather change information.'),
      (0, 0x058, 0x08, 'LockOn', 'Sends lock on packet.'),
      (0, 0x05A, 0x0C, 'CharEmotion', 'Sends emote statut to client.'),
      (0, 0x05B, 0x0E, 'Position', 'Sends character position update.'),
      (0, 0x05C, 0x12, 'EventUpdate', 'Sends event update with up to 8 parameters.'),
      (0, 0x05E, 0x5A, 'Conquest', 'Sends conquest/besieged/campaign status.'),
      (0, 0x05F, 0x04, 'ChangeMusic', 'Changes game music.'),
      (0, 0x059, 0x12, 'WorldPass', 'Sends information about world pass (uses, time valid, etc).'),
      (0, 0x061, 0x30, 'CharStats', 'Sends character stats.'),
      (0, 0x062, 0x80, 'CharSkills', 'Sends character skills.'),
      (0, 0x063, 0x08, 'MenuMerit', 'Sends current limit and merit points, if merits are enabled, if XP is called, and max merit point cap.'),
      (0, 0x063, 0x6E, 'MenuMerit', 'Previous packet with different 0x04 bytes (JP?).'),
      (0, 0x063, 0x44, 'MenuMerit', 'Previous packet with different 0x04 bytes (Gifts?).'),
      (0, 0x065, 0x10, 'CSPosition', 'Sends cutscene position update.'),
      (0, 0x067, 0x12, 'PetSync', 'Sync pet information.'),
      (0, 0x067, 0x14, 'CharSync', 'Sends character sync for level sync status and main job.'),
      (0, 0x06F, 0x12, 'SynthMessage', 'Sends synthesis message.'),
      (0, 0x070, 0x30, 'SynthResultMessage', 'Sends synthesis result message.'),
      (0, 0x071, 0x66, 'Campaign', 'Sends campaign information.'),
      (0, 0x081, 0x0C, 'Fishing', 'UNKNOWN - fishing packet.'),
      (0, 0x082, 0x04, 'GuildMenuBuyUpdate', 'Sends updated information for guild vendor items.'),
      (0, 0x083, 0x7C, 'GuildMenuBuy', 'Sends items a guild vendor is selling.'),
      (0, 0x084, 0x04, 'GuildMenuSellUpdate', 'Sends updated information for guild vendor items.'),
      (0, 0x085, 0x7C, 'GuildMenuSell', 'Sends items a guild vendor is selling.'),
      (0, 0x086, 0x06, 'GuildMenu', 'Displays guild status (open, closed, holiday).'),
      (0, 0x08C, 0x80, 'MeritPointCategories', 'Sends data for all merit point categories.'),
      (0, 0x08C, 0x08, 'MeritPointType', 'Sends data for a single merit type when raising/lowering level.'),
      (0, 0x0A0, 0x0C, 'PartyMap', 'Sends location data for party member.'),
      (0, 0x0AA, 0x42, 'CharSpells', 'Sends known spells.'),
      (0, 0x0AC, 0x72, 'CharAbilities', 'Sends known weaponskills, abilities, pet commands, and traits.'),
      (0, 0x0B4, 0x0C, 'MenuConfig', 'Sends character name plate information (icon displayed).'),
      (0, 0x0BF, 0x0E, 'InstanceEntry', 'Sends BCNM instance entry response.'),
      (0, 0x0C8, 0x7C, 'PartyDefine', 'Sends information about party members.'),
      (0, 0x0C9, 0x00, 'CheckPacket', 'Sends multiple packets of varying sizes to supply player check information'),
      (0, 0x0CA, 0x4A, 'BazaarMessage', 'Sends bazaar message and character title and name.'),
      (0, 0x0CC, 0x58, 'LinkshellMessage', 'Sends linkshell message.'),
      (0, 0x0D2, 0x1E, 'TreasureFindItem', 'Sends item find information (You find an on the).'),
      (0, 0x0D3, 0x1E, 'TreasureLotItem', 'Sends response to lotting, passing, or winning.'),
      (0, 0x0DC, 0x10, 'PartyInvite', 'Sends a party invite message to a player.'),
      (0, 0x0DD, 0x20, 'PartyMemberUpdate', 'Sends updates about party members.'),
      (0, 0x0DF, 0x12, 'CharHealth', 'Sends character HP/MP/TP, HPP/MPP and jobs (if not anon).'),
      (0, 0x0E0, 0x04, 'LinkshellEquip', 'Sends which linkshell slot to equip a linkshell to.'),
      (0, 0x0E1, 0x04, 'PartySearch', 'Sends party ID.'),
      (0, 0x0F5, 0x0C, 'WideScanTrack', 'Updates information on the entity being tracked via WideScan.'),
      (0, 0x0F6, 0x04, 'WideScan', 'Sends WideScan status to client.'),
      (0, 0x0F6, 0x0E, 'WideScan', 'Sends WideScan entity position to client.'),
      (0, 0x0F9, 0x06, 'MenuRaiseTractor', 'Displays the raise/tractor menu.'),
      (0, 0x105, 0x17, 'BazaarItem', 'Sends a bazaar item message.'), -- Size has packed bit.
      (0, 0x106, 0x0D, 'BazaarPurchase', 'Sends a bazaar purchase message.'), -- Size has packed bit.
      (0, 0x107, 0x0B, 'BazaarClose', 'Sends bazaar close.'), -- Size has packed bit.
      (0, 0x108, 0x11, 'BazaarCheck', 'Sends a bazaar check message.'), -- Size has packed bit.
      (0, 0x109, 0x13, 'BazaarConfirmation', 'Sends bazaar purchase confirmation.') -- Size has packed bit.
      ;
    ]=]
    
    db:exec('BEGIN TRANSACTION');
    query = db:prepare('INSERT INTO ZONES VALUES(?, ?)');
    for i = 0, 512, 1 do
        if res.zones[i] then
            query:bind(1, i);
            query:bind(2, res.zones[i].english);
            
            if query:step() ~= sqlite.DONE then
                print(string.format('%s %s', i, res.zones[i].english));
            end
            query:reset();
        end
    end
    db:exec('COMMIT TRANSACTION');
    query:finalize();
    
    QUERY.INSERT_PACKET = db:prepare(PACKET_SQL);
    QUERY.INSERT_TEXT	= db:prepare(TEXT_SQL);
end

function insertPacket(direction, packet)
    if db == nil then return; end;
    
    local id = bit.band(packet:unpack('CC', 1), 0x01FF);
    local size = bit.band(packet:unpack('C', 2), 0x0FE) * 2;
    local sync = packet:unpack('H', 3);
    local zoneId = -1;
    if windower == nil or windower.ffxi == nil or windower.ffxi.get_party() == nil or
        windower.ffxi.get_party().p0 == nil then
        zoneId = 0;
    else
        zoneId = windower.ffxi.get_party().p0.zone;
    end;
    
    local data = string.format('%02x', packet:unpack('C', 1));
    for i = 2, size do
        data = string.format('%s %02x', data, packet:unpack('C', i));
    end
    
    QUERY.INSERT_PACKET:bind(1, direction);
    QUERY.INSERT_PACKET:bind(2, zoneId);
    QUERY.INSERT_PACKET:bind(3, id);
    QUERY.INSERT_PACKET:bind(4, size);
    QUERY.INSERT_PACKET:bind(5, sync);
    QUERY.INSERT_PACKET:bind(6, data:upper());
    --QUERY.INSERT_PACKET:bind_blob(6, packet);
    local result = QUERY.INSERT_PACKET:step();
    
    if result == sqlite.ERROR then
        local err = QUERY.INSERT_PACKET:reset();
        print(string.format('[%s] [%s] %s', result, err, db:errmsg()));
    else
        QUERY.INSERT_PACKET:reset();
    end
end

function insertText(direction, text)
    if db == nil then return; end;
    
    local zoneId = windower.ffxi.get_party().p0.zone;
    direction = (direction == 'O' and 1 or 0);
        
    QUERY.INSERT_TEXT:bind(1, direction);
    QUERY.INSERT_TEXT:bind(2, zoneId);
    QUERY.INSERT_TEXT:bind(3, text);
    local result = QUERY.INSERT_TEXT:step();
        
    if result == sqlite.ERROR then
        local err = QUERY.INSERT_TEXT:reset();
        print(string.format('[%s] [%s] %s', result, err, db:errmsg()));
    else
        QUERY.INSERT_TEXT:reset();
    end
end

function bitAnd(a, b)
    local p, result = 1, 0
    while a > 0 and b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb > 1 then 
            result = result + p 
        end
        a, b, p = (a-ra) / 2, (b-rb) / 2, p * 2
    end
    return result	
end
