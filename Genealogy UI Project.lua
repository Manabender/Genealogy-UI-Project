--Genealogy UI Project
--This is a Lua script designed for use with BizHawk 2.9.1 and Fire Emblem: Genealogy of the Holy War.
--This script adds an information overlay to the bottom of the screen showing details about the hovered-over unit.
--The layout of this overlay was heavily inspired by (read: outright ripped-off from) Fire Emblem Engage.
--This script also adds a better combat forecast, inspired by more recent FE games.
--Note that this script REQUIRES the BSNES emulator core to be enabled, which it is not by default. Config > Preferred Cores > Snes > BSNES.

LUA_TABLES_SUCK = 1; --Whenever you see this, it's because I'm using a 0-based index into a Lua table, which is 1-based. LUA WHY DO YOU DO THIS. THIS IS STUPID.

globalToggle = true; --This script listens to the A button on 2P's controller. When it is pressed, the ENTIRE DISPLAY is toggled on and off.
p2ALastFrame = false; --Was A on 2P's controller "down" on the last frame? Important because I only want to detect rising edges.
p2BLastFrame = false;
p2XFrames = 0;

DISPLAY_FLAGS = 0x0349; --These three bytes seem to correspond loosely with what "mode" the game is in, where modes include things like:
                     --cursor active to select unit; unit selected and move range shown; picking unit action; combat; castle; etc.
                     --I use them to determine when overlays should be shown and when they should not.

displayFlagsHistory = {0,1,2,3,4,5}; --Display flags shuffle wildly while transitioning between modes. To avoid showing errant data, I require a handful of the few most recent frames to all have the same flags.
unitIDHistory = {0,1,2,3,4,5}; --$10B5 shuffles wildly at times. I check them like I check the display flags.
targetIDHistory = {0,1,2,3,4,5}; --$056F also shuffles a bit when cycling through available targets.
historyIndex = 1;
HISTORY_SIZE = 6;
UNIT_ID_MINIMUM_VALID = 0x2000;
UNIT_ID_MAXIMUM_VALID = 0x29ff; --Unit IDs always seem to be between $2000 and $29FF. If $10B5 is outside this range, I disable the overlay.
COMBAT_SCENE_PROBE_ADDRESS = 0x15f7; --I have no idea what is actually stored here, but it seems to be 0 outside of combat and nonzero in combat scene. This is a HUGE assumption.

factionColors = {}; --The color/team of factions varies on a per-map basis, and I can't figure out how the game references it internally.
                    --I cheat off the game's homework by looking at the HP bubble displayed when you cursor on a unit, but this has a delay.
					--This table is a cache relating affiliation to unit color.
					--The plan is as follows: If bubble displayed, display that and use it to update cache. If not, use cache to determine color. If cache is nil, fallback to a default.
CGRAM_FACTION_COLOR_ADDRESS = 0x8; --Address in CGRAM used to display the unit's color in its HP bubble.
CGRAM_FACTION_BLUE = 0x62d5; --Values found at that address for each color.
CGRAM_FACTION_RED = 0x5afa;
CGRAM_FACTION_GREEN = 0x4f58;
CGRAM_FACTION_YELLOW = 0x5318;
HP_BUBBLE_CHECK_ADDRESS = 0x0349; --Address in WRAM that always seems to be 82 if the HP bubble is displayed.
HP_BUBBLE_CHECK_VALUE = 82;

tileMarks = {}; --Table denoting what "threat range" marks are placed on the map. Initialized to a 64x64 grid.
for i = 1, 64 do
	tileMarks[i] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
end
markQueued = false; --As a workaround for certain bugs and inconsistancies, threat marks are ONLY placed when the cursor is aligned to the grid. If the player requests a mark while unaligned, I "queue" the request and fulfill it next time cursor is aligned.
CURSOR_X_ADDRESS = 0x1075; --Cursor location is stored quite weirdly. The map-x position of the cursor is equal to [$1076]+([$1075]/16).
CURSOR_Y_ADDRESS = 0x1095; --^ Ditto

FORECAST_VRAM_ADDRESS_CHECKS_RIGHT = {0xa864, 0xaa74, 0xacba, 0xace4}; --I cannot for the life of me find an address in memory that corresponds to 
FORECAST_VRAM_ADDRESS_CHECKS_LEFT = {0xa844, 0xaa54, 0xac9a, 0xacc4}; --"hey, am I showing the combat forecast?". So as a workaround, I instead check
FORECAST_VRAM_VALUE_CHECKS = {0x2368, 0x237b, 0x237a, 0x2378}; --VRAM for a few tiles of the forecast window. If all of them match, I conclude the forecast is up.

OAM_CURSOR_X = 0x00;
OAM_CURSOR_Y = 0x01;
CURSOR_OFFSET_CORRECTION = 3; --The cursor oscillates between being 2 and 3 pixels away from the actual space it's on.
OAM_CURSOR_TILE_ADDRESS = 0x02; --Address of the tile for the upper left corner of the map cursor. A specific tile is used when a unit is selected awaiting a move location. I check for that tile.
OAM_CURSOR_TILE_UNIT_SELECTED = 4; --The tile index used, see above.
OAM_CURSOR_TILE_HAND = 2;

HOVERED_UNIT_POINTER_TABLE_POINTER = 0x10b5; --The value here leads to several pointers with data about the unit the cursor is (or was last) on.
TARGET_UNIT_POINTER_TABLE_POINTER = 0x056f; --For combat forecast, this is the target being attacked.

POINTER_TABLE_DATA_PATTERN_OFFSET = 0; --This byte seems to correspond to how the unit's data should be read. Values of 0 and 2 are "player" patterns, 3 is "enemy". Others probably exist.
POINTER_TABLE_CORE_STATS_OFFSET = 1; --All offsets into the above pointer table designate a three-byte little endian value that points to certain data.
POINTER_TABLE_PLAYER_STATS_OFFSET = 4; --Core stats are stored in RAM for ALL units, but these player stats only exist for player units.
POINTER_TABLE_PLAYER_ROM_STATS_OFFSET = 7; --Some instances of unit stats are not variable and not kept in RAM. This points to ROM data used to calculate them.
POINTER_TABLE_ENEMY_ROM_STATS_OFFSET = 10; --See above.
POINTER_TABLE_WEAPON_DATA_OFFSET = 13; --A block of data describing the unit's inventory.

--[[
Just in case the above discriptions aren't clear, here's an example of what certain parts of RAM (which is bank $7E-7F) look like with the cursor on Sigurd.
$10B5 D4
$10B6 29 --$29D4 is a pointer to more pointers.

$29D4 00 --Data pattern byte, so I believe.
$29D5 31 -- \
$29D6 2D -- |--Pointer to core stats: $7E2D31
$29D7 7E -- /
$29D8 40 -- \
$29D9 2D -- |--Pointer to player stats: $7E2D40
$29DA 7E -- /
$29DB 74 -- \
$29DC B2 -- |--Pointer to player ROM stats: $83B274
$29DD 83 -- /
$29DE 00 -- \
$29DF 00 -- |--Pointer to enemy ROM stats, except Sigurd isn't an enemy, so there isn't one in this case.
$29E0 00 -- /
$29E1 CA -- \
$29E2 3B -- |--Pointer to weapon table: $7E3BCA
$29E3 7E -- /

$2D31 00 -- Start of Sigurd's core stat block. This particular value is his Arena level, I believe.
..
$2D37 00 -- Sigurd's affiliation. 0 means player.
..
$2D3B 00 -- Sigurd's bonus flags. 0 means none.
$2D3C 00 -- Sigurd's big bonus. 0 means none.
..
$2D3E 23 -- Sigurd's current HP. $23 is decimal 35.
--]]

CORE_STATS_AFFILIATION_OFFSET = 6; --Affiliation: Which faction controls the unit?
CORE_STATS_BONUS_FLAGS_OFFSET = 10; --Each bit of this value designates whether the unit has a stat-boosting ring.
CORE_STATS_BIG_BONUS_OFFSET = 11; --Value here corresponds to a "big bonus" array when certain weapons are equipped. 0 by default, which does nothing.
CORE_STATS_CURRENT_HP_OFFSET = 13;
CORE_STATS_ENEMY_FUNDS_OFFSET = 14; --For enemies only, this times 100 is how much gold they have. Unsure what it means for a player.

PLAYER_STATS_MAX_HP_OFFSET = 0;
PLAYER_STATS_STR_OFFSET = 1;
PLAYER_STATS_MAG_OFFSET = 2;
PLAYER_STATS_SKL_OFFSET = 3;
PLAYER_STATS_SPD_OFFSET = 4;
PLAYER_STATS_DEF_OFFSET = 5;
PLAYER_STATS_RES_OFFSET = 6;
PLAYER_STATS_LCK_OFFSET = 7;
PLAYER_STATS_CLASS_OFFSET = 8;
PLAYER_STATS_LEVEL_OFFSET = 9;
PLAYER_STATS_FUNDS_OFFSET = 11;
PLAYER_STATS_EXPERIENCE_OFFSET = 13;

PLAYER_ROM_STATS_PERSONAL_SKILLS_OFFSET = 15; --This byte and the next two are bitmasks that define which skills are personals for the unit.

ENEMY_ROM_STATS_CLASS_OFFSET = 4;
ENEMY_ROM_STATS_LEVEL_OFFSET = 6;

WEAPON_DATA_EQUIPPED_OFFSET = 0; --This is a bitmask that stores which weapon is equipped. $80 is first, $40 is second, $20 is third, etc. No idea why bitmask?
WEAPON_DATA_NUM_ITEMS_OFFSET = 1;
WEAPON_DATA_LIST_OFFSET = 5; --Starting with this byte, weapons in inventory are listed. Indices to a table for players, direct item IDs for enemies.

WEAPON_TABLE_ADDRESS = 0x3d85; --Start of the weapon table. Each entry is one item that exists...somewhere. Weird implementation IMO.
WEAPON_ENTRY_LENGTH = 6; --Each entry into the weapon table is 6 bytes. The address of entry x is 6x bytes offset from the start of the table.
WEAPON_ENTRY_ITEM_ID_OFFSET = 0; --Denotes which item this is.
WEAPON_ENTRY_DURABILITY_OFFSET = 1;
WEAPON_ENTRY_KILLS_OFFSET = 5; --FE4 tracks how many kills each weapon gets.

--The game allocates space for 72 total units on the map at a time. Between $438B and $480A(ish?) are several tables for unit variables.
--These tables are laid out differently than the stat blocks detailed above. Above, all the stats for a single unit are grouped into contiguous memory.
--These tables, however, group the same variable for all units into contiguous memory.
--All of these tables are two-byte little-endian values, even those that never need to use more than one byte. This means each table is 144 ($90) bytes long.
--These tables grow UPWARD; that is, while the X-screen-position table occupies $441B~$44AA, the first-filled entry is at $44A9, the second is $44A7, etc.
--Tables I don't use: $438B: Some sort of status flags?  $465B: No idea.  $477B: Affiliation, as far as I can tell.
UNIT_X_POSITION_TABLE = 0x441b;
UNIT_Y_POSITION_TABLE = 0x44ab;
UNIT_X_SCREEN_POSITION_TABLE = 0x453b; --This is always(?) just 16 times their map position.
UNIT_Y_SCREEN_POSITION_TABLE = 0x45cb;
UNIT_POINTER_TABLE = 0x46eb; --The same pointers I look for at $10B5.
UNIT_VARIABLES_TABLE_SIZE = 72;

BG1_SCREEN_X_SCROLL = 0x0598; --Addresses that helpfully always seem to mirror BG1's scroll registers.
BG1_SCREEN_Y_SCROLL = 0x059a;

--The following block of constants pertain to the combat forecast. Helpfully, once the (game's own) forecast is shown, it has already pre-computed many
--stats pertaining to that combat, including some stats that perhaps should have been shown, but simply aren't.
FORECAST_ATTACKER_WEAPON_ID = 0x4edd; --This is the weapon being used; specifically, its ID in the weapon database. If this is 2 for example, it's a Silver Sword.
FORECAST_TARGET_WEAPON_ID = 0x4f3d; --As above, but with regard to the sad sack of garbage the player is about to hit over the head with [0x4edd].
FORECAST_ATTACKER_HP = 0x4ec5;
FORECAST_TARGET_HP = 0x4f25;
FORECAST_ATTACKER_MAX_HP = 0x4ec7;
FORECAST_TARGET_MAX_HP = 0x4f27;
FORECAST_DISTANCE = 0x4eab; --The distance between the attacker and the target. Compared to target's weapon's attack range to see if it can counter.
FORECAST_TARGET_RANGE_MINIMUM = 0x4f41;
FORECAST_TARGET_RANGE_MAXIMUM = 0x4f43;
FORECAST_ATTACKER_ATK = 0x4eef; --"Atk" is the unit's total raw attack. This is (Str or Mag) + Weapon Might
FORECAST_TARGET_ATK = 0x4f4f;
FORECAST_ATTACKER_DEF = 0x4ef1; --"Def" in this context is the unit's Def or Res, whichever is applicable.
FORECAST_TARGET_DEF = 0x4f51;
FORECAST_ATTACKER_HIT = 0x4ee7; --"Hit" in this context refers to hit chance.
FORECAST_TARGET_HIT = 0x4f47;
FORECAST_ATTACKER_CRIT = 0x4eed;
FORECAST_TARGET_CRIT = 0x4f4d;
FORECAST_ATTACKER_ATTACK_SPEED = 0x4ee5; --Unit's effective speed; their speed stat minus their weapon's weight.
FORECAST_TARGET_ATTACK_SPEED = 0x4f45;
FORECAST_ATTACKER_LEVEL = 0x4ec9;
FORECAST_TARGET_LEVEL = 0x4f29;
FORECAST_ATTACKER_SKILLS = 0x4ed9; --A two-byte bitmask denoting which combat-relevant skills the attacker has.
FORECAST_TARGET_SKILLS = 0x4f39;


BONUS_FLAG_STR = 0x80; --Bits of the Bonus Flags value. A set bit is a present bonus. Bit 0 (least-significant) appears unused.
BONUS_FLAG_MAG = 0x40; --Also I'm sad Lua doesn't support binary literals. 0b01000000 would be so much clearer. (Or maybe it does support and I'm just dumb.)
BONUS_FLAG_SKL = 0x20;
BONUS_FLAG_SPD = 0x10;
BONUS_FLAG_DEF = 0x08;
BONUS_FLAG_RES = 0x04;
BONUS_FLAG_MOV = 0x02;

BONUS_VALUE_STR = 5; --If the bonus flag bit is set, this is the boost applied.
BONUS_VALUE_MAG = 5;
BONUS_VALUE_SKL = 5;
BONUS_VALUE_SPD = 5;
BONUS_VALUE_DEF = 5;
BONUS_VALUE_RES = 5;
BONUS_VALUE_MOV = 3;

--One core stat byte contains a value I dub "Big Bonus". It is 0 by default, which does nothing. Other values apply an array of bonuses.
--I believe this is the implementation of bonus stats from Legendary Weapons.
BIG_BONUS_DATA = {
{ 0,  0,  0,  0,  0,  0},
{ 0,  0, 10, 10,  0, 20},
{ 0,  0, 20, 20, 20, 20},
{10,  0,  0, 10, 10,  0},
{10,  0, 10,  0, 10,  0},
{ 0,  0, 10, 20,  0,  0},
{10,  0,  0, 10,  0,  0},
{ 0,  0,  0,  0, 20, 10},
{ 0, 10,  0,  0, 10, 10},
{ 0,  0, 20, 10,  0,  0},
{ 0,  0, 10, 20,  0,  0},
{ 0,  0,  0,  0,  0,  0},
{ 0,  0, 20,  0,  0, 10},
{ 0,  0,  0,  0,  0,  5},
{ 0,  0,  0,  0,  7,  0},
{ 0,  0,  0,  0,  0,  7}
}
NUM_BIG_BONUSES = #BIG_BONUS_DATA
--Enumeration of indices into the above table.
BIG_BONUS_STR = 1;
BIG_BONUS_MAG = 2;
BIG_BONUS_SKL = 3;
BIG_BONUS_SPD = 4;
BIG_BONUS_DEF = 5;
BIG_BONUS_RES = 6;

--Enumeration of weapon types
WEAPONTYPE_SWORD = 1;
WEAPONTYPE_LANCE = 2;
WEAPONTYPE_AXE = 3;
WEAPONTYPE_BOW = 4;
WEAPONTYPE_FIRE = 5;
WEAPONTYPE_THUNDER = 6;
WEAPONTYPE_WIND = 7;
WEAPONTYPE_LIGHT = 8;
WEAPONTYPE_DARK = 9;
WEAPONTYPE_STAFF = 10;
WEAPONTYPE_OTHER = 11;

WEAPON_TRIANGLE = { --Alright to be fair this is more of an undecagon than a triangle, but "weapon triangle" and "fire emblem" are as linked as peanut butter and jelly.
--Swd Lnc Axe Bow Fir Thn Wnd Lgt Drk Stf Oth <Defender     V Attacker     If WEAPON_TRIANGLE[attacker][defender] = 1, attacker has advantage.
{  0, -1,  1,  0,  0,  0,  0,  0,  0,  0,  0},              --Sword                                             If -1, defender has advantage.
{  1,  0, -1,  0,  0,  0,  0,  0,  0,  0,  0},              --Lance                                             If 0, neither has advantage.
{ -1,  1,  0,  0,  0,  0,  0,  0,  0,  0,  0},              --Axe
{  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0},              --Bow
{  0,  0,  0,  0,  0, -1,  1, -1, -1,  0,  0},              --Fire
{  0,  0,  0,  0,  1,  0, -1, -1, -1,  0,  0},              --Thunder
{  0,  0,  0,  0, -1,  1,  0, -1, -1,  0,  0},              --Wind
{  0,  0,  0,  0,  1,  1,  1,  0,  0,  0,  0},              --Light
{  0,  0,  0,  0,  1,  1,  1,  0,  0,  0,  0},              --Dark
{  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0},              --Staff
{  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0},              --Other
}

--Enumeration of weapon effectives
WEAPONEFFECTIVE_ARMOR = 1;
WEAPONEFFECTIVE_FLYING = 2;
WEAPONEFFECTIVE_HORSE = 3;

--Enumeration of skills
SKILL_PAVISE = 1; --Also known as Big Shield. LV% chance to ignore damage from a hit.
SKILL_WRATH = 2; --Always crit when HP is less than ((max/2)+1).
SKILL_PURSUIT = 3; --Always doubleattack if AS exceeds opponent's. (Unlike later games, even a +1 difference is sufficient.)
SKILL_ADEPT = 4; --Also known as Continue. Gives (AS+20)% chance of extra attack. Does NOT stack with Brave; Brave is considered a 100% Adept proc.
SKILL_STEAL = 5; --On hit, take all of target's gold.
SKILL_DANCE = 6; --Holy shit, quad-dancing was the NORM in FE4!?
SKILL_CHARM = 7; --Also known as Charisma. Allies within 3 tiles get +10 to Hit and Avo.
SKILL_NIHIL = 8; --Also known as Awareness. Prevents crits, sword skills, and effective bonuses.
SKILL_MIRACLE = 9; --Also known as Prayer. Either gives a chance to survive a lethal attack, or a bonus to Avo with low HP. Unclear which.
SKILL_CRITICAL = 10; --Allows random crits. Crit chance is Skl+clamp(wpnKills-50,0,50).
SKILL_VANTAGE = 11; --Also known as Ambush. When attacked, unit swings first anyway as long as HP < max/2. Also prevents Accost.
SKILL_ACCOST = 12; --Also known as Charge. May cause a fight to recursively go another round, if HP >= 25, chance = [myAS-tgtAS+HP/2]
SKILL_ASTRA = 13; --Skl% chance to attack five times.
SKILL_LUNA = 14; --Skl% chance to ignore defense.
SKILL_SOL = 15; --Skl% chance to heal for damage done.
SKILL_RENEWAL = 16; --Also known as Life. Heal for 5-10 at start of turn.
SKILL_PARAGON = 17; --Also known as Elite. Doubled xp gain.
SKILL_BARGAIN = 18; --Halved shop prices.

--Bitmask definition for personal skills as read from ROM. When three bytes are read, little-endian, from PLAYER_ROM_STATS_PERSONAL_SKILLS_OFFSET,
--you get 24 bits, starting with bit 23 and ending with bit 0. This table maps those bits in that order to skills. Index 1 is bit 23, index 2 is bit 22, etc.
PERSONAL_SKILLS_BITMASK = {            0,              0,              0,  SKILL_BARGAIN,              0,              0,  SKILL_PARAGON,  SKILL_RENEWAL,
                                       0,              0,      SKILL_SOL,     SKILL_LUNA,    SKILL_ASTRA,   SKILL_ACCOST,  SKILL_VANTAGE, SKILL_CRITICAL,
                           SKILL_MIRACLE,    SKILL_NIHIL,              0,    SKILL_CHARM,              0,    SKILL_ADEPT,  SKILL_PURSUIT,    SKILL_WRATH};
--Fun fact 1: Bits 15 and 14 correspond to visible skills, but they have glitchy descriptions. Probably planned-but-scrapped?
--Fun fact 2: Pavise, Steal, and Dance don't seem to have entries in the personals bitmask. They are probably only class skills!

SKILL_STRINGS = {"Pavis", "Wrath", "Prsut", "Adept", "Steal", "Dance", "Charm", "Nihil", "Mracl",  "Crit",
                 "Vantg", "Acost", "Astra",  "Luna",   "Sol", "Renew", "Pargn", "Brgin"}; --Strings the script uses to show skills.

SKILL_DISPLAY_X = {120, 165, 210, 120, 165, 210};
SKILL_DISPLAY_Y = {199, 199, 199, 209, 209, 209}; --Screen coordinates to drawText each skill at.

--Enumeration of movement types; an attribute of a unit (derived from its class) that determines what set of movement costs (how much of its Mov does it consume to enter a tile?) it uses.
MOVETYPE_KNIGHT1 = 1;
MOVETYPE_KNIGHT2 = 2;
MOVETYPE_FLYING = 3;
MOVETYPE_FOOT = 4;
MOVETYPE_ARMOR = 5;
MOVETYPE_FIGHTER = 6;
MOVETYPE_BRIGAND = 7;
MOVETYPE_PIRATE = 8;

MOVE_COSTS = { --Table defining the amount of movement required to enter each tile type, for each unit movetype. Values multiplied by 10 because road tiles are technically 0.7, but I don't trust floats like I do ints.
               --999 indicates that a unit can't move into this tile.
--Kn1  Kn2  Fly Foot  Amr  Fgt  Brg  Prt
{ 999, 999,  10, 999, 999, 999, 999, 999}, --Peak
{ 999, 999,  10, 999, 999, 999,  50, 999}, --Thicket
{ 999, 999,  10, 999, 999, 999, 999, 999}, --Cliff
{  10,  10,  10,  10,  10,  10,  10,  10}, --Plain
{  30,  30,  10,  20,  20,  20,  20,  20}, --Woods
{ 999, 999,  10, 999, 999, 999, 999,  50}, --Sea
{ 999, 999,  10, 999, 999, 999, 999,  50}, --Stream
{ 999,  30,  10,  20, 999,  20,  20,  20}, --Mountain
{  40,  40,  10,  20,  30,  30,  20,  20}, --Desert
{ 999, 999, 999, 999, 999, 999, 999, 999}, --Castle (I think this is the tile that a castle defender occupies?)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Fort (Assuming all 1???)
{  10,  10,  10,  10,  10,  10,  10,  10}, --House (Assuming all 1???)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Gate (Assuming all 1???)
{ 999, 999, 999, 999, 999, 999, 999, 999}, --Rampart (I think these are tiles of a castle that aren't movable?)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Sands
{   7,   7,  10,   7,   7,   7,   7,   7}, --Bridge
{  10,  10,  10,  10,  10,  10,  10,  10}, --Bog (What is this???)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Gate (How is this different from the other Gate?)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Village
{  10,  10,  10,  10,  10,  10,  10,  10}, --Ruin (How is this different from the other Ruin?)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Store (Assuming all 1???)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Ruin (How is this different from the other Ruin?)
{  10,  10,  10,  10,  10,  10,  10,  10}, --Chapel
{  10,  10,  10,  10,  10,  10,  10,  10}, --Shrine (Assuming all 1???)
{ 999, 999,  10, 999, 999, 999, 999, 999}, --T. of Bragi
{   7,   7,  10,   7,   7,   7,   7,   7}  --Road
} --Game graphics go completely bonkers if it reads a tile type ID of 26 or greater. This makes me confident that only types 0-25 will appear.

CLASS_DATA = { --           Bases                                 Growths
--Name          HP Str Mag Skl Spd Def Res Mov  Gold   HP  Str Mag Skl Spd Def Res  Effective?              Skill           Skill           Movetype
{"Cavalier"   ,	30,	7,	0,	6,	6,	6,	0,	8,	1000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT1},
{"LanceKnight",	30,	7,	0,	6,	6,	6,	0,	8,	1000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT1},
{"Bow Knight" ,	30,	7,	0,	6,	6,	6,	0,	8,	1000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT1},
{"Axe Knight" ,	30,	7,	0,	6,	6,	6,	0,	8,	1000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT1},
{"SwordKnight",	30,	7,	0,	6,	6,	6,	0,	8,	1000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT1},
{"Troubadour" ,	26,	3,	3,	6,	6,	3,	3,	8,	1000, 100, 30, 10, 30, 30, 20, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT1},
{"Knight Lord",	40,	10,	0,	7,	7,	7,	3,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT2},
{"Duke Knight",	40,	12,	0,	7,	7,	8,	3,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT2},
{"MastrKnight",	40,	12,	7,	12,	12,	12,	7,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,  SKILL_PURSUIT,              0, MOVETYPE_KNIGHT2},
{"Paladin"    ,	40,	9,	5,	9,	9,	9,	5,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT2},
{"Paladin"    ,	40,	9,	5,	9,	9,	9,	5,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT2},
{"Arch Knight",	40,	10,	0,	8,	8,	8,	3,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT2},
{"ForestKnigt",	40,	8,	0,	15,	12,	8,	3,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,    SKILL_ADEPT,              0, MOVETYPE_KNIGHT2},
{"Mage Knight",	40,	5,	10,	7,	7,	5,	7,	9,	3000, 100, 30, 20, 30, 30, 20, 20,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT2},
{"GreatKnight",	40,	12,	0,	7,	7,	10,	3,	9,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_HORSE,              0,              0, MOVETYPE_KNIGHT2},
{"PegasusRidr", 30,	6,	0,	5,	10,	3,	5,	8,	1000, 100, 30, 10, 30, 30, 30, 10, WEAPONEFFECTIVE_FLYING,              0,              0,  MOVETYPE_FLYING},
{"PegasusKngt",	35,	7,	0,	7,	12,	5,	7,	8,	3000, 100, 30, 10, 30, 30, 30, 10, WEAPONEFFECTIVE_FLYING,              0,              0,  MOVETYPE_FLYING},
{"FalconKnigt",	40,	7,	7,	12,	15,	6,	12,	8,	5000, 100, 30, 10, 30, 30, 30, 10, WEAPONEFFECTIVE_FLYING,    SKILL_ADEPT,              0,  MOVETYPE_FLYING},
{"Dracorider" ,	35,	9,	0,	5,	5,	8,	0,	9,	1000, 100, 30, 10, 30, 30, 30, 10, WEAPONEFFECTIVE_FLYING,              0,              0,  MOVETYPE_FLYING},
{"Dracoknight",	40,	10,	0,	7,	6,	11,	0,	9,	3000, 100, 30, 10, 30, 30, 30, 10, WEAPONEFFECTIVE_FLYING,              0,              0,  MOVETYPE_FLYING},
{"Dragonmastr",	40,	12,	0,	9,	7,	14,	0,	9,	5000, 100, 30, 10, 30, 30, 30, 10, WEAPONEFFECTIVE_FLYING,  SKILL_PURSUIT,              0,  MOVETYPE_FLYING},
{"Archer"     ,	30,	7,	0,	10,	10,	5,	0,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,  SKILL_PURSUIT,              0,    MOVETYPE_FOOT},
{"Myrmidon"   ,	30,	7,	0,	10,	10,	5,	0,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,  SKILL_PURSUIT,              0,    MOVETYPE_FOOT},
{"Swordmaster",	40,	12,	0,	15,	15,	7,	3,	6,	3000, 100, 30, 10, 30, 30, 30, 10,                      0,  SKILL_PURSUIT,    SKILL_ADEPT,    MOVETYPE_FOOT},
{"Sniper"     ,	40,	12,	0,	12,	12,	7,	3,	6,	3000, 100, 30, 10, 30, 30, 30, 10,                      0,  SKILL_PURSUIT,              0,    MOVETYPE_FOOT},
{"Hero"       ,	40,	12,	3,	12,	12,	7,	3,	6,	3000, 100, 30, 10, 30, 30, 30, 10,                      0,  SKILL_PURSUIT,              0,    MOVETYPE_FOOT},
{"General"    ,	40,	10,	0,	6,	5,	12,	3,	5,	3000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_ARMOR,   SKILL_PAVISE,              0,   MOVETYPE_ARMOR},
{"Emperor"    ,	45,	15,	15,	15,	15,	15,	15,	5,	6000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_ARMOR,   SKILL_PAVISE,    SKILL_CHARM,   MOVETYPE_ARMOR},
{"Baron"      ,	45,	12,	7,	7,	7,	12,	7,	5,	5000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_ARMOR,   SKILL_PAVISE,              0,   MOVETYPE_ARMOR},
{"Soldier"    ,	30,	6,	0,	5,	5,	7,	0,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Spr Soldier",	30,	6,	0,	5,	5,	7,	0,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Axe Soldier",	30,	6,	0,	5,	5,	7,	0,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Bow Soldier",	30,	6,	0,	5,	5,	7,	0,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Swd Soldier",	30,	6,	0,	5,	5,	7,	0,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Lance Armor",	40,	9,	0,	5,	3,	10,	0,	5,	2000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_ARMOR,              0,              0,   MOVETYPE_ARMOR},
{"Axe Armor"  ,	40,	9,	0,	5,	3,	10,	0,	5,	2000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_ARMOR,              0,              0,   MOVETYPE_ARMOR},
{"Bow Armor"  ,	40,	9,	0,	5,	3,	10,	0,	5,	2000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_ARMOR,              0,              0,   MOVETYPE_ARMOR},
{"Sword Armor",	40,	9,	0,	5,	3,	10,	0,	5,	2000, 100, 30, 10, 30, 30, 30, 10,  WEAPONEFFECTIVE_ARMOR,              0,              0,   MOVETYPE_ARMOR},
{"Barbarian"  ,	35,	5,	0,	0,	7,	5,	0,	6,	1000, 100, 30,  0, 30, 30, 30, 10,                      0,              0,              0, MOVETYPE_BRIGAND},
{"Fighter"    ,	35,	8,	0,	3,	10,	8,	0,	6,	2000, 100, 30,  0, 30, 30, 30, 10,                      0,              0,              0, MOVETYPE_FIGHTER},
{"Brigand"    ,	35,	5,	0,	0,	7,	5,	0,	6,	5000, 100, 30,  0, 30, 30, 30, 10,                      0,              0,              0, MOVETYPE_BRIGAND},
{"Warrior"    ,	40,	11,	0,	5,	12,	10,	3,	6,	3000, 100, 30,  0, 30, 30, 30, 10,                      0,              0,              0, MOVETYPE_FIGHTER},
{"Hunter"     ,	35,	7,	0,	0,	7,	5,	0,	6,	1000, 100, 30,  0, 30, 30, 30, 10,                      0,              0,              0, MOVETYPE_BRIGAND},
{"Pirate"     ,	35,	5,	0,	0,	7,	5,	0,	6,	5000, 100, 30,  0, 30, 30, 30, 10,                      0,              0,              0,  MOVETYPE_PIRATE},
{"Lord"       ,	30,	5,	0,	5,	5,	5,	0,	6,	6000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"War Mage"   ,	30,	5,	12,	10,	10,	7,	7,	6,	3000, 100, 20, 20, 30, 30, 30, 20,                      0,    SKILL_ADEPT,              0,    MOVETYPE_FOOT},
{"Prince"     ,	30,	8,	3,	7,	6,	7,	3,	6,	5000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Princess"   ,	26,	5,	7,	5,	8,	5,	7,	6,	5000, 100, 20, 20, 30, 30, 30, 20,                      0,    SKILL_CHARM,              0,    MOVETYPE_FOOT},
{"War Mage"   ,	26,	3,	12,	9,	12,	5,	10,	6,	3000, 100, 20, 20, 30, 30, 30, 20,                      0,    SKILL_ADEPT,              0,    MOVETYPE_FOOT},
{"Queen"      ,	35,	5,	15,	10,	12,	10,	15,	6,	6000, 100, 20, 20, 30, 30, 30, 20,                      0,    SKILL_CHARM,              0,    MOVETYPE_FOOT},
{"Dancer"     ,	26,	3,	0,	1,	7,	1,	3,	6,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,    SKILL_DANCE,              0,    MOVETYPE_FOOT},
{"Priest"     ,	26,	0,	7,	6,	6,	1,	7,	5,	1000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Mage"       ,	26,	0,	7,	6,	6,	1,	5,	5,	1000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Fire Mage"  ,	26,	0,	10,	6,	6,	1,	5,	5,	1000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"ThunderMage",	26,	0,	7,	9,	6,	1,	5,	5,	1000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Wind Mage"  , 26,	0,	7,	6,	9,	1,	5,	5,	1000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"High Priest",	35,	0,	12,	9,	8,	3,	8,	5,	3000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Bishop"     ,	35,	0,	10,	8,	5,	3,	8,	5,	3000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Sage"       ,	35,	0,	15,	12,	15,	3,	12,	6,	5000, 100, 10, 30, 30, 30, 10, 30,                      0,    SKILL_ADEPT,              0,    MOVETYPE_FOOT},
{"Bard"       ,	30,	0,	7,	7,	10,	3,	7,	6,	2000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Priestess"  ,	30,	0,	8,	7,	7,	3,	10,	5,	2000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Dark Mage"  ,	40,	0,	10,	8,	8,	7,	10,	5,	3000, 100, 10, 30, 30, 30, 10, 30,                      0,              0,              0,    MOVETYPE_FOOT},
{"Dark Bishop",	40,	0,	15,	10,	10,	10,	12,	5,	5000, 100, 10, 30, 30, 30, 10, 30,                      0,  SKILL_PURSUIT,              0,    MOVETYPE_FOOT},
{"Thief"      ,	26,	3,	0,	3,	7,	1,	0,	6,	5000, 100, 30, 10, 30, 30, 30, 10,                      0,    SKILL_STEAL,              0,    MOVETYPE_FOOT},
{"Rogue"      ,	30,	7,	3,	7,	12,	5,	3,	7,	6000, 100, 30, 10, 30, 30, 30, 10,                      0,  SKILL_PURSUIT,    SKILL_STEAL,    MOVETYPE_FOOT},
{"Civilian"   ,	20,	0,	0,	0,	10,	2,	0,	5,	   0, 100,  0,  0, 30, 30,  0,  0,                      0,              0,              0,    MOVETYPE_FOOT},
{"Civilian"   ,	20,	0,	0,	0,	0,	0,	0,	5,	   0, 100,  0,  0, 30, 30,  0,  0,                      0,              0,              0,    MOVETYPE_FOOT},
{"Ballisticin",	30,	0,	0,	0,	0,	0,	0,	0,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Ballisticin",	30,	0,	0,	0,	0,	10,	0,	0,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Ballisticin",	30,	0,	0,	0,	0,	0,	0,	0,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Ballisticin",	30,	0,	0,	0,	0,	0,	0,	0,	1000, 100, 30, 10, 30, 30, 30, 10,                      0,              0,              0,    MOVETYPE_FOOT},
{"Dark Prince",	30,	0,	15,	12,	12,	10,	15,	5,	   0,   0,  0,  0,  0,  0,  0,  0,                      0,              0,              0,    MOVETYPE_FOOT}
}
NUM_CLASSES = #CLASS_DATA; -- # is the "get length" operator of Lua.
--Enumeration of the indices into the above data table.
CLASS_NAME = 1;
CLASS_MHP = 2;
CLASS_STR = 3;
CLASS_MAG = 4;
CLASS_SKL = 5;
CLASS_SPD = 6;
CLASS_DEF = 7;
CLASS_RES = 8;
CLASS_MOV = 9;
CLASS_GOLD = 10;
CLASS_MHP_GROWTH = 11; --Growths are used to calculate enemy stats. Their stats seem to be simply = base + (level * growth)
CLASS_STR_GROWTH = 12;
CLASS_MAG_GROWTH = 13;
CLASS_SKL_GROWTH = 14; --Interestingly, all classes have 0 base luck and 0 luck growth. This is why luck has no data.
CLASS_SPD_GROWTH = 15;
CLASS_DEF_GROWTH = 16;
CLASS_RES_GROWTH = 17;
CLASS_EFFECTIVE = 18; --Is this class vulnerable to Armorslayers, etc.?
CLASS_SKILL1 = 19;
CLASS_SKILL2 = 20;
CLASS_MOVETYPE = 21;

--Name         Mt  Wt  Hit             Type               Effective?          Skill   Brave?
WEAPON_DATA = {
{"Iron Sword",  6,  3,  80,   WEAPONTYPE_SWORD,                      0,              0, 0}, --$00
{"SteelSword", 10,  3,  80,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"SilvrSword", 14,  3,  80,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"Iron Blade", 12,  6,  60,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"SteelBlade", 16,  6,  60,   WEAPONTYPE_SWORD,                      0,              0, 0}, --$04
{"SilvrBlade", 20,  6,  60,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"MiracleSwd", 12,  3,  70,   WEAPONTYPE_SWORD,                      0,  SKILL_MIRACLE, 0},
{"ThiefSword",  3,  2,  50,   WEAPONTYPE_SWORD,                      0,    SKILL_STEAL, 0},
{"BarrierSwd", 10,  3,  70,   WEAPONTYPE_SWORD,                      0,              0, 0}, --$08
{"BerserkEdg",  8, 12,  70,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"BraveSword", 12,  3, 100,   WEAPONTYPE_SWORD,                      0,              0, 1},
{"SilenceEdg",  8, 12,  70,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"Sleep Edge",  8, 12,  70,   WEAPONTYPE_SWORD,                      0,              0, 0}, --$0C
{"Slim Sword",  8,  1,  90,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"ShieldSwrd", 12,  5,  90,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"FlameSword", 12,  5,  70,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"EarthSword", 12,  5,  70,   WEAPONTYPE_SWORD,                      0,              0, 0}, --$10
{"Bolt Sword", 12,  5,  70,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"Wind Sword", 12,  5,  70,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"LightBrand", 12,  5,  70,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"*Mystltain", 30,  5,  80,   WEAPONTYPE_SWORD,                      0, SKILL_CRITICAL, 0}, --$14
{"*Tilfing"  , 30,  7,  80,   WEAPONTYPE_SWORD,                      0,  SKILL_MIRACLE, 0},
{"*Balmung"  , 30,  3,  90,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"Armorslayr",  6,  5,  70,   WEAPONTYPE_SWORD,  WEAPONEFFECTIVE_ARMOR,              0, 0},
{"Wingslayer",  6,  5,  70,   WEAPONTYPE_SWORD, WEAPONEFFECTIVE_FLYING,              0, 0}, --$18
{"BrokenSwdA",  0, 30,  30,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"BrokenSwdB",  0, 30,  30,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"BrokenSwdC",  0, 30,  30,   WEAPONTYPE_SWORD,                      0,              0, 0},
{"Iron Lance", 12, 12,  80,   WEAPONTYPE_LANCE,                      0,              0, 0}, --$1C
{"SteelLance", 16, 12,  80,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"SilvrLance", 20, 12,  80,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"Javelin"   , 12, 18,  60,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"Horseslayr", 10, 16,  60,   WEAPONTYPE_LANCE,  WEAPONEFFECTIVE_HORSE,              0, 0}, --$20
{"BraveLance", 15, 12,  80,   WEAPONTYPE_LANCE,                      0,              0, 1},
{"Slim Lance", 12,  6,  90,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"*Gungnir"  , 30, 15,  70,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"*Gae Bolg" , 30, 15,  70,   WEAPONTYPE_LANCE,                      0,              0, 0}, --$24
{"BrokenLncA",  0, 30,  30,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"BrokenLncB",  0, 30,  30,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"BrokenLncC",  0, 30,  30,   WEAPONTYPE_LANCE,                      0,              0, 0},
{"Iron Axe"  , 14, 18,  70,     WEAPONTYPE_AXE,                      0,              0, 0}, --$28
{"Steel Axe" , 18, 18,  70,     WEAPONTYPE_AXE,                      0,              0, 0},
{"Silver Axe", 22, 18,  70,     WEAPONTYPE_AXE,                      0,              0, 0},
{"Brave Axe" , 22, 18,  70,     WEAPONTYPE_AXE,                      0,              0, 1},
{"*Helswath" , 30, 20,  70,     WEAPONTYPE_AXE,                      0,              0, 0}, --$2C
{"Hand Axe"  , 10, 20,  50,     WEAPONTYPE_AXE,                      0,              0, 0},
{"BrokenAxeA",  0, 30,  30,     WEAPONTYPE_AXE,                      0,              0, 0},
{"BrokenAxeA",  0, 30,  30,     WEAPONTYPE_AXE,                      0,              0, 0},
{"BrokenAxeA",  0, 30,  30,     WEAPONTYPE_AXE,                      0,              0, 0}, --$30
{"Iron Bow"  , 10,  8,  70,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"Steel Bow" , 14,  8,  70,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"Silver Bow", 18,  8,  70,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"Brave Bow" , 14,  8,  80,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 1}, --$34
{"Killer Bow", 14,  3, 100,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING, SKILL_CRITICAL, 0},
{"*Yewfelle" , 30, 13,  70,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,  SKILL_RENEWAL, 0},
{"BrokenBowA",  0, 30,  30,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"BrokenBowB",  0, 30,  30,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0}, --$38
{"BrokenBowC",  0, 30,  30,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"Ballista"  , 15, 30,  60,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"IronBalsta", 25, 30,  60,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"KilrBalsta", 20, 30, 100,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING, SKILL_CRITICAL, 0}, --$3C
{"GreatBlsta", 30, 30,  50,     WEAPONTYPE_BOW, WEAPONEFFECTIVE_FLYING,              0, 0},
{"Fire"      ,  8, 12,  90,    WEAPONTYPE_FIRE,                      0,              0, 0},
{"Elfire"    , 14, 12,  80,    WEAPONTYPE_FIRE,                      0,              0, 0},
{"Bolganone" , 20, 12,  70,    WEAPONTYPE_FIRE,                      0,              0, 0}, --$40
{"*Valflame" , 30, 15,  80,    WEAPONTYPE_FIRE,                      0,              0, 0},
{"Meteor"    , 15, 30,  60,    WEAPONTYPE_FIRE,                      0,              0, 0},
{"Thunder"   ,  8,  7,  90, WEAPONTYPE_THUNDER,                      0,              0, 0},
{"Elthunder" , 14,  7,  80, WEAPONTYPE_THUNDER,                      0,              0, 0}, --$44
{"Thoron"    , 20,  7,  70, WEAPONTYPE_THUNDER,                      0,              0, 0},
{"*Mjolnir"  , 30, 10,  90, WEAPONTYPE_THUNDER,                      0,              0, 0},
{"Bolting"   , 15, 30,  60, WEAPONTYPE_THUNDER,                      0,              0, 0},
{"Wind"      ,  8,  2,  90,    WEAPONTYPE_WIND,                      0,              0, 0}, --$48
{"Elwind"    , 14,  2,  80,    WEAPONTYPE_WIND,                      0,              0, 0},
{"Tornado"   , 20,  2,  70,    WEAPONTYPE_WIND,                      0,              0, 0},
{"*Forseti"  , 30,  5,  90,    WEAPONTYPE_WIND,                      0,              0, 0},
{"Blizzard"  , 15, 30,  60,    WEAPONTYPE_WIND,                      0,              0, 0}, --$4C
{"Light"     , 14,  5,  90,   WEAPONTYPE_LIGHT,                      0,              0, 0},
{"Nosferatu" , 14, 12,  70,   WEAPONTYPE_LIGHT,                      0,              0, 0},
{"Aura"      , 20, 20,  80,   WEAPONTYPE_LIGHT,                      0,              0, 0},
{"*Naga"     , 30, 12,  80,   WEAPONTYPE_LIGHT,                      0,              0, 0}, --$50
{"Jormungand", 20, 12,  90,    WEAPONTYPE_DARK,                      0,              0, 0},
{"Fenrir"    , 14, 20,  70,    WEAPONTYPE_DARK,                      0,              0, 0},
{"Hel"       , 50, 28,  60,    WEAPONTYPE_DARK,                      0,              0, 0}, --     Mt isn't actually 50 but this will show a very high number,
{"*Loptyr"   , 30, 12,  80,    WEAPONTYPE_DARK,                      0,              0, 0}, --$54  because Hel just reduces target to 1 HP, it's a big threat.
{"DrainedTmA",  0,  0,   0,    WEAPONTYPE_FIRE,                      0,              0, 0}, 
{"DrainedTmB",  0,  0,   0,    WEAPONTYPE_FIRE,                      0,              0, 0}, --     Not sure if drained tomes can be used, not sure if their
{"DrainedTmC",  0,  0,   0,    WEAPONTYPE_FIRE,                      0,              0, 0}, --     weapontypes actually matter.
{"Heal"      ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0}, --$58
{"Mend"      ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Recover"   ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Physic"    ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Fortify"   ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0}, --$5C
{"Return"    ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Warp"      ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Rescue"    ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Charm"     ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0}, --$60
{"Restore"   ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"*Valkyria" ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Silence"   ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Sleep"     ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0}, --$64
{"Berserk"   ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"Thief"     ,  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"BrokeStafA",  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"BrokeStafB",  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0}, --$68
{"BrokeStafC",  0,  0,   0,   WEAPONTYPE_STAFF,                      0,              0, 0},
{"RenewalBnd",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"ParagonBnd",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,  SKILL_PARAGON, 0},
{"ThiefsBand",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,    SKILL_STEAL, 0}, --$6C
{"MiracleBnd",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,  SKILL_MIRACLE, 0},
{"PursuitBnd",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,  SKILL_PURSUIT, 0},
{"RecoverBnd",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"BargainBnd",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,  SKILL_BARGAIN, 0}, --$70
{"KnightRing",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"ReturnBand",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"Speed Ring",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"Magic Ring",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0}, --$74
{"Power Ring",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"ShieldRing",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"BarierRing",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0},
{"Leg Ring"  ,  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0}, --$78
{"Skill Ring",  0,  0,   0,   WEAPONTYPE_OTHER,                      0,              0, 0}
}
NUM_WEAPONS = #WEAPON_DATA; -- # is the "get length" operator of Lua.
--Enumeration of the indices into the above data table.
WEAPON_NAME = 1;
WEAPON_MT = 2;
WEAPON_WT = 3;
WEAPON_HIT = 4;
WEAPON_TYPE = 5;
WEAPON_EFFECTIVE = 6; --Does this weapon deal Effective damage to any type of units?
WEAPON_SKILL = 7; --Does this weapon give the unit a skill?
WEAPON_IS_BRAVE = 8; --Is this a "brave" weapon, that strikes twice? 1 if yes, 0 if no.


PLAYER_TEXT_COLOR = "#3F0000FF";
ENEMY_TEXT_COLOR = "#3FFF0000";
GREEN_TEXT_COLOR = "#3F00FF00";
YELLOW_TEXT_COLOR = "#3FFFFF00";
UNKNOWN_TEXT_COLOR = "#3FFF00FF"; --This is used as a stopgap for if both the HP bubble is absent and the cache doesn't have data yet.
UNEXPECTED_TEXT_COLOR = "3F7F7F7F"; --This is used if CGRAM has a color I haven't seen.

--Function: WeaponIsPhysical(weaponID)
--Summary: Returns true if the given weapon deals physical damage, and false if it deals magic damage (or no damage at all).
--Parameters: weaponID: The game's ID of the weapon to test.
--Returns: boolean
function WeaponIsPhysical(weaponID)
	if (WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_TYPE] <= WEAPONTYPE_BOW) then
		return true; --The weapontype enumeration is set up such that <= 4 is physical, and otherwise is magic.
	else
		return false;
	end
end
	
--Function: WeaponIsDamaging(weaponID)
--Summary: Returns true if the given weapon is, in fact, a weapon used for dealing damage. Returns false if it is instead a staff or other item.
--Parameters: weaponID: The game's ID of the weapon to test.
--Returns: boolean
function WeaponIsDamaging(weaponID)
	if (WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_TYPE] <= WEAPONTYPE_DARK) then
		return true; --The weapontype enumeration is set up such that <= 9 is damaging, and otherwise isn't.
	else
		return false;
	end
end

--Function: DisplayUnitStatsOverlay()
--Summary: Runs all the logic required to fetch the stats of the unit pointed to by HOVERED_UNIT_POINTER_TABLE_POINTER in memory, and display them on screen.
--Parameters: None.
--Returns: Nothing.
function DisplayUnitStatsOverlay()
	local unitID = mainmemory.read_u16_le(HOVERED_UNIT_POINTER_TABLE_POINTER); --The pointer to the unit's pointer tables. Also usable as a globally-unique ID.
	local coreStatsPointer = mainmemory.read_u16_le(unitID + POINTER_TABLE_CORE_STATS_OFFSET);
	local playerStatsPointer = mainmemory.read_u24_le(unitID + POINTER_TABLE_PLAYER_STATS_OFFSET);
	local playerRomStatsPointer = mainmemory.read_u24_le(unitID + POINTER_TABLE_PLAYER_ROM_STATS_OFFSET);
	local enemyRomStatsPointer = mainmemory.read_u24_le(unitID + POINTER_TABLE_ENEMY_ROM_STATS_OFFSET);
	local weaponDataPointer = mainmemory.read_u16_le(unitID + POINTER_TABLE_WEAPON_DATA_OFFSET);
	local dataPattern = mainmemory.read_u8(unitID + POINTER_TABLE_DATA_PATTERN_OFFSET); --This byte seems to correspond to how the unit's data should be read. Values of 0 and 2 are "player" patterns, 3 is "enemy". Others probably exist.
	
	--Most stats are read or calculated differently depending on whether the unit is player or not. We need to read affiliation first.
	local unitAffiliation = mainmemory.read_u8(coreStatsPointer + CORE_STATS_AFFILIATION_OFFSET);
	
	local textColor = ""; --To find unit color: If HP bubble displayed, display that and use it to update cache. If not, use cache to determine color. If cache is nil, fallback to a default.
	local unitColor = -1;
	local hpBubbleValue = mainmemory.read_u8(HP_BUBBLE_CHECK_ADDRESS);
	if (hpBubbleValue == HP_BUBBLE_CHECK_VALUE) then
		memory.usememorydomain("CGRAM");
		local cgramColor = memory.read_u16_le(CGRAM_FACTION_COLOR_ADDRESS);
		if (cgramColor == CGRAM_FACTION_BLUE) then
			unitColor = 1;			
			factionColors[unitAffiliation + LUA_TABLES_SUCK] = 1;
		elseif (cgramColor == CGRAM_FACTION_RED) then
			unitColor = 2;			
			factionColors[unitAffiliation + LUA_TABLES_SUCK] = 2;
		elseif (cgramColor == CGRAM_FACTION_GREEN) then
			unitColor = 3;			
			factionColors[unitAffiliation + LUA_TABLES_SUCK] = 3;
		elseif (cgramColor == CGRAM_FACTION_YELLOW) then
			unitColor = 4;			
			factionColors[unitAffiliation + LUA_TABLES_SUCK] = 4;
		else --If we got here, something went wrong, or there's a fifth color I don't know about.
			unitColor = 5;
		end
		memory.usememorydomain("System Bus");
	elseif (factionColors[unitAffiliation + LUA_TABLES_SUCK] ~= nil) then
		unitColor = factionColors[unitAffiliation + LUA_TABLES_SUCK];
	end
	if (unitColor == 1) then
		textColor = PLAYER_TEXT_COLOR;
	elseif (unitColor == 2) then
		textColor = ENEMY_TEXT_COLOR;
	elseif (unitColor == 3) then
		textColor = GREEN_TEXT_COLOR;
	elseif (unitColor == 4) then
		textColor = YELLOW_TEXT_COLOR;
	elseif (unitColor == 5) then
		textColor = UNEXPECTED_TEXT_COLOR;
	else
		textColor = UNKNOWN_TEXT_COLOR;
	end
	
	local level = 0;
	if (dataPattern == 0 or dataPattern == 2) then --Player
		level = memory.read_u8(playerStatsPointer + PLAYER_STATS_LEVEL_OFFSET);
	else
		level = memory.read_u8(enemyRomStatsPointer + ENEMY_ROM_STATS_LEVEL_OFFSET);
	end
	if (level <= 9) then
		gui.drawText(0, 189, "L " .. level, nil, textColor); --Adds a space to keep the ones' digit in the same place.
	else
		gui.drawText(0, 189, "L" .. level, nil, textColor);
	end
	
	local className = "";
	local classID = 0; --Class ID is needed for several calculations, so remember it for later.
	if (dataPattern == 0 or dataPattern == 2) then --Player
		classID = memory.read_u8(playerStatsPointer + PLAYER_STATS_CLASS_OFFSET);
	else
		classID = memory.read_u8(enemyRomStatsPointer + ENEMY_ROM_STATS_CLASS_OFFSET);
	end
	if (classID < NUM_CLASSES) then --Data validity check to avoid index-out-of-bounds error.
		className = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_NAME];
	else
		classID = 0; --Prevent further issues with class lookups by failing back to a known safe value.
	end
	gui.drawText(0, 179, className, nil, textColor);
	
	--Current HP is in the same place for both player and enemy units.
	local currentHP = mainmemory.read_u8(coreStatsPointer + CORE_STATS_CURRENT_HP_OFFSET);
	if (currentHP <= 9) then
		currentHP = " " .. currentHP; --Adds a space to keep the ones' digit in the same place.
	elseif (currentHP >= 100) then
		currentHP = "??"; --Does FE4 do the thing where HP 100+ is just question marks?
	end
	gui.drawText(90, 179, "HP" .. currentHP, nil, textColor);
	
	local maxHP = 0;
	if (dataPattern == 0 or dataPattern == 2) then --Player
		maxHP = memory.read_u8(playerStatsPointer + PLAYER_STATS_MAX_HP_OFFSET);
	else
		--As far as I can tell, max HP (and all other primary stats) for enemies is just auto-calculated based on their class and level.
		maxHP = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MHP] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MHP_GROWTH] / 100);
	end
	if (maxHP <= 9) then
		maxHP = " " .. maxHP; --I don't expect anything to ever have less than 10 max HP, but good coding practice demands I check anyway.
	elseif (maxHP >= 100) then
		maxHP = "??"; --Does FE4 do the thing where HP 100+ is just question marks?
	end
	gui.drawText(105, 189, maxHP, nil, textColor);
	
	local experience = 0;
	if (unitAffiliation == 0) then --Player --Most stats should check dataPattern, but experience ONLY makes sense for player, which is always(?) faction 0.
		experience = memory.read_u8(playerStatsPointer + PLAYER_STATS_EXPERIENCE_OFFSET);
		if (experience <= 9) then --Adds a space to keep the ones' digit in the same place.
			experience = " " .. experience;
		end
	else
		experience = "--" --Nonplayers just flat-out don't have xp. Simple!
	end
	gui.drawText(30, 189, "X" .. experience, nil, textColor);
	
	--Calculate unit stats.	
	local str = 0;
	local mag = 0;
	local skl = 0;
	local spd = 0;
	local def = 0;
	local res = 0;
	local lck = 0;
	--Step 1: Find unit's baseline stats, before ring/big bonuses
	if (dataPattern == 0 or dataPattern == 2) then --Player
		--For some reason, the game stores each characters stats as a value above their class's baseline.
		--For example, Sigurd starts with 14 Str, because he starts with 4 "personal" Str and has 10 Str from his class.
		str = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_STR] + memory.read_u8(playerStatsPointer + PLAYER_STATS_STR_OFFSET);
		mag = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MAG] + memory.read_u8(playerStatsPointer + PLAYER_STATS_MAG_OFFSET);
		skl = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SKL] + memory.read_u8(playerStatsPointer + PLAYER_STATS_SKL_OFFSET);
		spd = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SPD] + memory.read_u8(playerStatsPointer + PLAYER_STATS_SPD_OFFSET);
		def = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_DEF] + memory.read_u8(playerStatsPointer + PLAYER_STATS_DEF_OFFSET);
		res = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_RES] + memory.read_u8(playerStatsPointer + PLAYER_STATS_RES_OFFSET);
		lck = memory.read_u8(playerStatsPointer + PLAYER_STATS_LCK_OFFSET); --Luck is an oddball, every class has 0 base in it.
	else	
		str = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_STR] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_STR_GROWTH] / 100);
		mag = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MAG] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MAG_GROWTH] / 100);
		skl = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SKL] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SKL_GROWTH] / 100);
		spd = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SPD] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SPD_GROWTH] / 100);
		def = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_DEF] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_DEF_GROWTH] / 100);
		res = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_RES] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_RES_GROWTH] / 100);
		lck = 0; --Luck is still an oddball.
	end
	--Step 2: Add ring bonuses
	local bonusFlags = mainmemory.read_u8(coreStatsPointer + CORE_STATS_BONUS_FLAGS_OFFSET);
	if (bonusFlags&BONUS_FLAG_STR == BONUS_FLAG_STR) then str = str + BONUS_VALUE_STR; end
	if (bonusFlags&BONUS_FLAG_MAG == BONUS_FLAG_MAG) then mag = mag + BONUS_VALUE_MAG; end
	if (bonusFlags&BONUS_FLAG_SKL == BONUS_FLAG_SKL) then skl = skl + BONUS_VALUE_SKL; end
	if (bonusFlags&BONUS_FLAG_SPD == BONUS_FLAG_SPD) then spd = spd + BONUS_VALUE_SPD; end
	if (bonusFlags&BONUS_FLAG_DEF == BONUS_FLAG_DEF) then def = def + BONUS_VALUE_DEF; end
	if (bonusFlags&BONUS_FLAG_RES == BONUS_FLAG_RES) then res = res + BONUS_VALUE_RES; end
	--Step 3: Add big bonus
	local bigBonus = mainmemory.read_u8(coreStatsPointer + CORE_STATS_BIG_BONUS_OFFSET);
	if (bigBonus >= NUM_BIG_BONUSES) then
		bigBonus = 0; --Prevent errant array-out-of-bounds issues.
	end
	str = str + BIG_BONUS_DATA[bigBonus + LUA_TABLES_SUCK][BIG_BONUS_STR]
	mag = mag + BIG_BONUS_DATA[bigBonus + LUA_TABLES_SUCK][BIG_BONUS_MAG]
	skl = skl + BIG_BONUS_DATA[bigBonus + LUA_TABLES_SUCK][BIG_BONUS_SKL]
	spd = spd + BIG_BONUS_DATA[bigBonus + LUA_TABLES_SUCK][BIG_BONUS_SPD]
	def = def + BIG_BONUS_DATA[bigBonus + LUA_TABLES_SUCK][BIG_BONUS_DEF]
	res = res + BIG_BONUS_DATA[bigBonus + LUA_TABLES_SUCK][BIG_BONUS_RES]
	--Def and Res are displayed on overlay. The rest are used to calculate other overlay values.
	if (def <= 9) then
		gui.drawText(217, 179, "Df " .. def, nil, textColor); --Adds a space to keep the ones' digit in the same place.
	else
		gui.drawText(217, 179, "Df" .. def, nil, textColor);
	end
	if (res <= 9) then
		gui.drawText(217, 189, "Rs " .. res, nil, textColor); --Adds a space to keep the ones' digit in the same place.
	else
		gui.drawText(217, 189, "Rs" .. res, nil, textColor);
	end
	
	--[[ --For debugging: Show all other stats too.
	gui.drawText(0,20,str,nil,textColor);
	gui.drawText(0,30,mag,nil,textColor);
	gui.drawText(0,40,skl,nil,textColor);
	gui.drawText(0,50,spd,nil,textColor);
	gui.drawText(0,60,lck,nil,textColor);
	]]--
	
	local movement = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MOV];
	if (bonusFlags&BONUS_FLAG_MOV == BONUS_FLAG_MOV) then
		movement = movement + BONUS_VALUE_MOV;
	end
	gui.drawText(60, 189, "Mv" .. movement, nil, textColor);
	
	local weaponID = 0;
	local weaponName = "";
	local durability = "";
	local kills = 0;
	local somethingIsEquipped = true; --Is something equipped? Some calculations run differently if not.
	local equippedWeaponSlot = 0; --The equipped weapon slot is stored as a bitmask, for some reason, so turn that into an offset.
	local equippedWeaponBitmask = mainmemory.read_u8(weaponDataPointer + WEAPON_DATA_EQUIPPED_OFFSET);
	local numWeapons = mainmemory.read_u8(weaponDataPointer + WEAPON_DATA_NUM_ITEMS_OFFSET);
	if (equippedWeaponBitmask >= 128) then equippedWeaponSlot = 0;
	elseif (equippedWeaponBitmask >= 64) then equippedWeaponSlot = 1;
	elseif (equippedWeaponBitmask >= 32) then equippedWeaponSlot = 2;
	elseif (equippedWeaponBitmask >= 16) then equippedWeaponSlot = 3;
	elseif (equippedWeaponBitmask >= 8) then equippedWeaponSlot = 4;
	elseif (equippedWeaponBitmask >= 4) then equippedWeaponSlot = 5;
	elseif (equippedWeaponBitmask >= 2) then equippedWeaponSlot = 6;
	elseif (equippedWeaponBitmask >= 1) then equippedWeaponSlot = 7;
	else equippedWeaponSlot = -1;
	end
	if (equippedWeaponSlot == -1 or numWeapons == 0) then
		somethingIsEquipped = false;
		weaponName = "No Weapon";
	else
		local equippedByte = mainmemory.read_u8(weaponDataPointer + WEAPON_DATA_LIST_OFFSET + equippedWeaponSlot);
		if (dataPattern == 0) then --Player
			local weaponEntryAddress = WEAPON_TABLE_ADDRESS + (WEAPON_ENTRY_LENGTH * equippedByte)
			weaponID = mainmemory.read_u8(weaponEntryAddress + WEAPON_ENTRY_ITEM_ID_OFFSET);
			weaponName = WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_NAME];
			durability = "D"..mainmemory.read_u8(weaponEntryAddress + WEAPON_ENTRY_DURABILITY_OFFSET);
			kills = mainmemory.read_u8(weaponEntryAddress + WEAPON_ENTRY_KILLS_OFFSET);
			gui.drawText(30, 209, "*"..kills, nil, textColor);
		else
			weaponID = equippedByte;
			weaponName = WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_NAME];
		end
	end
	gui.drawText(0, 199, weaponName, nil, textColor);
	gui.drawText(82, 199, "Itm"..numWeapons, nil, textColor);
	gui.drawText(0, 209, durability, nil, textColor);
	
	local gold = 0;
	if (dataPattern == 0) then --Player
		gold = memory.read_u16_le(playerStatsPointer + PLAYER_STATS_FUNDS_OFFSET);
	else
		gold = mainmemory.read_u8(coreStatsPointer + CORE_STATS_ENEMY_FUNDS_OFFSET) * 100;
	end
	gui.drawText(115, 209, gold.."G", nil, textColor, nil, nil, nil, "right");
	

	local attackPower = 0;
	if (not somethingIsEquipped) then
		gui.drawText(135, 179, "At--", nil, textColor);
	elseif (not WeaponIsDamaging(weaponID)) then
		gui.drawText(135, 179, "At--", nil, textColor);
	else
		if (WeaponIsPhysical(weaponID)) then
			attackPower = str + WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_MT];
		else
			attackPower = mag + WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_MT];
		end
		if (attackPower <= 9) then
			gui.drawText(135, 179, "At "..attackPower, nil, textColor); --Adds a space to keep the ones' digit in the same place.
		else
			gui.drawText(135, 179, "At"..attackPower, nil, textColor);
		end
	end
	
	local attackSpeed = spd;
	if (somethingIsEquipped and WeaponIsDamaging(weaponID)) then
		attackSpeed = spd - WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_WT];
	end
	if (attackSpeed >= 0 and attackSpeed <= 9) then
		gui.drawText(135, 189, "AS "..attackSpeed, nil, textColor); --Adds a space to keep the ones' digit in the same place.
	elseif (attackSpeed <= -10) then
		gui.drawText(135, 189, "S"..attackSpeed, nil, textColor); --Below -10 is three characters wide, so one character has to go...
	else
		gui.drawText(135, 189, "AS"..attackSpeed, nil, textColor);
	end
	
	local hitRating = 0;
	if (not somethingIsEquipped) then
		gui.drawText(172, 179, "Ht---", nil, textColor);
	elseif (not WeaponIsDamaging(weaponID)) then
		gui.drawText(172, 179, "Ht---", nil, textColor);
	else
		hitRating = (skl*2) + WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_HIT];
		if (hitRating <= 99) then
			gui.drawText(172, 179, "Ht "..hitRating, nil, textColor); --Adds a space to keep the ones' digit in the same place.
		else
			gui.drawText(172, 179, "Ht"..hitRating, nil, textColor);
		end
	end
	
	local avoidance = (attackSpeed*2) + lck;
	if (avoidance >= 0 and avoidance <= 9) then
		gui.drawText(172, 189, "Av  "..avoidance, nil, textColor); --One character; add two spaces
	elseif (avoidance <= -1 and avoidance >= -9) then
		gui.drawText(172, 189, "Av "..avoidance, nil, textColor); --Two characters; add one space
	elseif (avoidance >= 10 and avoidance <= 99) then
		gui.drawText(172, 189, "Av "..avoidance, nil, textColor); --Also two characters; add one space
	else
		gui.drawText(172, 189, "Av"..avoidance, nil, textColor); --Three characters
	end
	
	local skills = {}; --To be populated with the list of skills the unit has. An index will be set to 1 if that index's skill is present. Others default to nil.
	--There are four (five?) sources of skills: 1. From unit's class, 2. Unit's personal skills, 3. From equipped weapons and held items,
	--4. If equipped weapon has 50+ kills, it grants Critical, 5?. Inherited skills?
	--1. Class skills
	if (CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SKILL1] > 0) then
		skills[CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SKILL1]] = 1;
	end
	if (CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SKILL2] > 0) then
		skills[CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_SKILL2]] = 1;
	end
	--2. Personal skills
	if (dataPattern == 0 or dataPattern == 2) then --Player
		local personalsBitmask = memory.read_u24_le(playerRomStatsPointer + PLAYER_ROM_STATS_PERSONAL_SKILLS_OFFSET);
		for i = 23, 0, -1 do
			if (personalsBitmask&2^i == 2^i) then
				skills[PERSONAL_SKILLS_BITMASK[24-i]] = 1;
			end
		end
	end
	--3. Items with skills
	--3a. Equipped weapon
	if (somethingIsEquipped) then --Can't do both if's at the same time because validity check has to come first.
		if (WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_SKILL] > 0) then
			skills[WEAPON_DATA[weaponID + LUA_TABLES_SUCK][WEAPON_SKILL]] = 1;
		end
	end
	--3b. Passive items
	i = 0;
	local numItems = mainmemory.read_u8(weaponDataPointer + WEAPON_DATA_NUM_ITEMS_OFFSET)
	while (i < numItems) do
		local itemID = 0;
		local itemEntry = mainmemory.read_u8(weaponDataPointer + WEAPON_DATA_LIST_OFFSET + i)
		if (dataPattern == 0 or dataPattern == 2) then --Player
			itemID = mainmemory.read_u8(WEAPON_TABLE_ADDRESS + (WEAPON_ENTRY_LENGTH * itemEntry) + WEAPON_ENTRY_ITEM_ID_OFFSET);
		else
			itemID = itemEntry;
		end
		if (itemID < NUM_WEAPONS) then --Validity check
			if (WEAPON_DATA[itemID + LUA_TABLES_SUCK][WEAPON_TYPE] == WEAPONTYPE_OTHER and WEAPON_DATA[itemID + LUA_TABLES_SUCK][WEAPON_SKILL] > 0) then
				skills[WEAPON_DATA[itemID + LUA_TABLES_SUCK][WEAPON_SKILL]] = 1;
			end
		end
		i = i + 1;
	end
	--4. Weapon with 50+ kills grants Critical
	if (kills >= 50) then
		skills[SKILL_CRITICAL] = 1;
	end
	--Now finally, display skills.
	local numSkills = 0;
	local skillsList = {};
	for i = 1,18,1 do
		if (skills[i] == 1) then
			numSkills = numSkills + 1;
			skillsList[numSkills] = i;
		end
	end
	local tooManySkills = false;
	local skillsToShow = numSkills;
	if (numSkills > 6) then
		tooManySkills = true; --I can only show six skills in the space allocated. If more, I do something else.
		skillsToShow = 5;
	end
	i = 1;
	while (i <= skillsToShow) do
		gui.drawText(SKILL_DISPLAY_X[i], SKILL_DISPLAY_Y[i], SKILL_STRINGS[skillsList[i]], nil, textColor);
		i = i + 1;
	end
	if (tooManySkills) then
		local howManyMore = numSkills - skillsToShow;
		gui.drawText(SKILL_DISPLAY_X[6], SKILL_DISPLAY_Y[6], howManyMore.."more", nil, textColor);
	end
end

--Function: DisplayCombatForecast()
--Summary: Runs all the logic required to fetch the stats of the units to fight and display the improved combat forecast.
--Parameters: None.
--Returns: Nothing.
function DisplayCombatForecast()
	local attackerUnitID = mainmemory.read_u16_le(HOVERED_UNIT_POINTER_TABLE_POINTER);
	local attackerCoreStatsPointer = mainmemory.read_u16_le(attackerUnitID + POINTER_TABLE_CORE_STATS_OFFSET);
	local attackerPlayerStatsPointer = mainmemory.read_u16_le(attackerUnitID + POINTER_TABLE_PLAYER_STATS_OFFSET);
	local attackerPlayerRomStatsPointer = mainmemory.read_u24_le(attackerUnitID + POINTER_TABLE_PLAYER_ROM_STATS_OFFSET);
	local attackerEnemyRomStatsPointer = mainmemory.read_u24_le(attackerUnitID + POINTER_TABLE_ENEMY_ROM_STATS_OFFSET);
	local attackerWeaponDataPointer = mainmemory.read_u16_le(attackerUnitID + POINTER_TABLE_WEAPON_DATA_OFFSET);
	
	local targetUnitID = mainmemory.read_u16_le(TARGET_UNIT_POINTER_TABLE_POINTER);
	local targetCoreStatsPointer = mainmemory.read_u16_le(targetUnitID + POINTER_TABLE_CORE_STATS_OFFSET);
	local targetPlayerStatsPointer = mainmemory.read_u16_le(targetUnitID + POINTER_TABLE_PLAYER_STATS_OFFSET);
	local targetPlayerRomStatsPointer = mainmemory.read_u24_le(targetUnitID + POINTER_TABLE_PLAYER_ROM_STATS_OFFSET);
	local targetEnemyRomStatsPointer = mainmemory.read_u24_le(targetUnitID + POINTER_TABLE_ENEMY_ROM_STATS_OFFSET);
	local targetWeaponDataPointer = mainmemory.read_u16_le(targetUnitID + POINTER_TABLE_WEAPON_DATA_OFFSET);
	
	local attackerClassName = "";
	local attackerClassID = mainmemory.read_u8(attackerPlayerStatsPointer + PLAYER_STATS_CLASS_OFFSET);
	if (attackerClassID < NUM_CLASSES) then --Data validity check to avoid index-out-of-bounds error.
		attackerClassName = CLASS_DATA[attackerClassID + LUA_TABLES_SUCK][CLASS_NAME];
	else
		attackerClassID = 0; --Prevent further issues with class lookups by failing back to a known safe value.
	end
	gui.drawText(0, 159, attackerClassName, nil, PLAYER_TEXT_COLOR);
	
	local targetClassName = "";
	local targetClassID = memory.read_u8(targetEnemyRomStatsPointer + ENEMY_ROM_STATS_CLASS_OFFSET);
	if (targetClassID < NUM_CLASSES) then --Data validity check to avoid index-out-of-bounds error.
		targetClassName = CLASS_DATA[targetClassID + LUA_TABLES_SUCK][CLASS_NAME];
	else
		targetClassID = 0; --Prevent further issues with class lookups by failing back to a known safe value.
	end
	gui.drawText(248, 159, targetClassName, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	
	local attackerWeaponID = mainmemory.read_u8(FORECAST_ATTACKER_WEAPON_ID);
	gui.drawText(0, 169, WEAPON_DATA[attackerWeaponID + LUA_TABLES_SUCK][WEAPON_NAME], nil, PLAYER_TEXT_COLOR);
	
	local targetWeaponID = mainmemory.read_u8(FORECAST_TARGET_WEAPON_ID);
	gui.drawText(248, 169, WEAPON_DATA[targetWeaponID + LUA_TABLES_SUCK][WEAPON_NAME], nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	
	local attackerHPBefore = mainmemory.read_u8(FORECAST_ATTACKER_HP);	
	local targetHPBefore = mainmemory.read_u8(FORECAST_TARGET_HP);
	
	
	local canTargetCounter = true;
	local distance = mainmemory.read_u8(FORECAST_DISTANCE);
	local rangeMin = mainmemory.read_u8(FORECAST_TARGET_RANGE_MINIMUM);
	local rangeMax = mainmemory.read_u8(FORECAST_TARGET_RANGE_MAXIMUM);
	if (distance < rangeMin or distance > rangeMax) then
		canTargetCounter = false;
	end
	
	local attackerHit = mainmemory.read_u8(FORECAST_ATTACKER_HIT);
	gui.drawText(0, 199, "Hit "..attackerHit, nil, PLAYER_TEXT_COLOR);
	
	if (canTargetCounter) then
		local targetHit = mainmemory.read_u8(FORECAST_TARGET_HIT);
		gui.drawText(248, 199, targetHit.." Hit", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	else
		gui.drawText(248, 199, "--- Hit", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	end
	
	local attackerMaxHP = mainmemory.read_u8(FORECAST_ATTACKER_MAX_HP);
	local targetMaxHP = mainmemory.read_u8(FORECAST_TARGET_MAX_HP);
	local attackerAS = mainmemory.read_s8(FORECAST_ATTACKER_ATTACK_SPEED);
	local targetAS = mainmemory.read_s8(FORECAST_TARGET_ATTACK_SPEED);
	local attackerLevel = mainmemory.read_u8(FORECAST_ATTACKER_LEVEL);
	local targetLevel = mainmemory.read_u8(FORECAST_TARGET_LEVEL);
	local attackerSkills = mainmemory.read_u16_le(FORECAST_ATTACKER_SKILLS);
	local targetSkills = mainmemory.read_u16_le(FORECAST_TARGET_SKILLS);
	
	--Display skills for attacker
	local textY = 149; --Start drawing skill text here, and grow upwards.
	local attackerSureCrit = false; --A triggered Wrath skill or an Effective weapon will guarantee a crit, if the target doesn't have Nihil.
	local attackerWillFollowUp = false; --If the attacker will perform what is known in modern FE as a "follow-up attack", or informally a "double".
	if (attackerSkills&0x8000 == 0x8000) then
		if (attackerHPBefore * 2 <= attackerMaxHP and targetSkills&0x1000 == 0) then --If HP is low enough for Wrath to trigger AND target doesn't have Nihil
			gui.drawText(0, textY, "Wrath:100%", nil, PLAYER_TEXT_COLOR);
			attackerSureCrit = true;
		else
			gui.drawText(0, textY, "Wrath:0%", nil, PLAYER_TEXT_COLOR);
		end
		textY = textY - 10;
	end
	if (attackerSkills&0x4000 == 0x4000) then
		if (attackerAS > targetAS) then
			gui.drawText(0, textY, "Pursuit:100%", nil, PLAYER_TEXT_COLOR);
			attackerWillFollowUp = true;
		else
			gui.drawText(0, textY, "Pursuit:0%", nil, PLAYER_TEXT_COLOR);
		end
		textY = textY - 10;
	end
	if (attackerSkills&0x2000 == 0x2000) then
		local adeptChance = attackerAS + 20;
		gui.drawText(0, textY, "Adept:"..adeptChance.."%", nil, PLAYER_TEXT_COLOR);
		textY = textY - 10;
	end
	if (attackerSkills&0x1000 == 0x1000) then
		gui.drawText(0, textY, "Nihil", nil, PLAYER_TEXT_COLOR);
		textY = textY - 10;
	end
	if (attackerSkills&0x0800 == 0x0800) then
		gui.drawText(0, textY, "Miracle", nil, PLAYER_TEXT_COLOR);
		textY = textY - 10;
	end
	if (attackerSkills&0x0400 == 0x0400) then
		gui.drawText(0, textY, "Vantage", nil, PLAYER_TEXT_COLOR);
		textY = textY - 10;
	end
	if (attackerSkills&0x0200 == 0x0200) then
		local accostChance = attackerAS - targetAS + math.floor(attackerHPBefore/2);
		gui.drawText(0, textY, "Accost:"..accostChance.."%", nil, PLAYER_TEXT_COLOR);
		textY = textY - 10;
	end
	if (attackerSkills&0x0100 == 0x0100) then
		gui.drawText(0, textY, "Pavise:"..attackerLevel.."%", nil, PLAYER_TEXT_COLOR);
		textY = textY - 10;
	end
	if (attackerSkills&0x0080 == 0x0080) then
		gui.drawText(0, textY, "Steal", nil, PLAYER_TEXT_COLOR);
		textY = textY - 10;
	end
	if (attackerSkills&0x0040 == 0x0040) then
		if (targetSkills&0x1000 == 0x1000) then --Nihil prevents sword skills
			gui.drawText(0, textY, "Astra:0%", nil, PLAYER_TEXT_COLOR);
		else
			gui.drawText(0, textY, "Astra:Skl%", nil, PLAYER_TEXT_COLOR);
		end
		textY = textY - 10;
	end
	if (attackerSkills&0x0020 == 0x0020) then
		if (targetSkills&0x1000 == 0x1000) then --Nihil prevents sword skills
			gui.drawText(0, textY, "Luna:0%", nil, PLAYER_TEXT_COLOR);
		else
			gui.drawText(0, textY, "Luna:Skl%", nil, PLAYER_TEXT_COLOR);
		end
		textY = textY - 10;
	end
	if (attackerSkills&0x0010 == 0x0010) then
		if (targetSkills&0x1000 == 0x1000) then --Nihil prevents sword skills
			gui.drawText(0, textY, "Sol:0%", nil, PLAYER_TEXT_COLOR);
		else
			gui.drawText(0, textY, "Sol:Skl%", nil, PLAYER_TEXT_COLOR);
		end
		textY = textY - 10;
	end
	
	--Display skills for target
	textY = 149; --Start drawing skill text here, and grow upwards.
	local targetSureCrit = false; --A triggered Wrath skill or an Effective weapon will guarantee a crit, if the target doesn't have Nihil.
	local targetWillFollowUp = false; --If the target will perform what is known in modern FE as a "follow-up attack", or informally a "double".
	local targetWillVantage = false; --If the target has Vantage and low enough HP to proc it.
	if (targetSkills&0x8000 == 0x8000) then
		if (targetHPBefore * 2 <= targetMaxHP and attackerSkills&0x1000 == 0) then --If HP is low enough for Wrath to trigger AND target doesn't have Nihil
			gui.drawText(248, textY, "100%:Wrath", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
			targetSureCrit = true;
		else
			gui.drawText(248, textY, "0%:Wrath", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		end
		textY = textY - 10;
	end
	if (targetSkills&0x4000 == 0x4000) then
		if (targetAS > attackerAS) then
			gui.drawText(248, textY, "100%:Pursuit", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
			targetWillFollowUp = true;
		else
			gui.drawText(248, textY, "0%:Pursuit", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		end
		textY = textY - 10;
	end
	if (targetSkills&0x2000 == 0x2000) then
		local adeptChance = targetAS + 20;
		gui.drawText(248, textY, adeptChance.."%:Adept", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		textY = textY - 10;
	end
	if (targetSkills&0x1000 == 0x1000) then
		gui.drawText(248, textY, "Nihil", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		textY = textY - 10;
	end
	if (targetSkills&0x0800 == 0x0800) then
		gui.drawText(248, textY, "Miracle", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		textY = textY - 10;
	end
	if (targetSkills&0x0400 == 0x0400) then
		if (targetHPBefore * 2 <= targetMaxHP) then
			gui.drawText(248, textY, "100%:Vantage", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
			targetWillVantage = true;
		else
			gui.drawText(248, textY, "0%:Vantage", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		end
		textY = textY - 10;
	end
	if (targetSkills&0x0200 == 0x0200) then
		local accostChance = attackerAS - targetAS + math.floor(attackerHPBefore/2);
		gui.drawText(248, textY, accostChance.."%:Accost:", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		textY = textY - 10;
	end
	if (targetSkills&0x0100 == 0x0100) then
		gui.drawText(248, textY, targetLevel.."%:Pavise", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		textY = textY - 10;
	end
	if (targetSkills&0x0080 == 0x0080) then
		gui.drawText(248, textY, "Steal", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		textY = textY - 10;
	end
	if (targetSkills&0x0040 == 0x0040) then
		if (attackerSkills&0x1000 == 0x1000) then --Nihil prevents sword skills
			gui.drawText(248, textY, "0%:Astra", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		else
			gui.drawText(248, textY, "Skl%:Astra", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		end
		textY = textY - 10;
	end
	if (targetSkills&0x0020 == 0x0020) then
		if (attackerSkills&0x1000 == 0x1000) then --Nihil prevents sword skills
			gui.drawText(248, textY, "0%:Luna", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		else
			gui.drawText(248, textY, "Skl%:Luna", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		end
		textY = textY - 10;
	end
	if (targetSkills&0x0010 == 0x0010) then
		if (attackerSkills&0x1000 == 0x1000) then --Nihil prevents sword skills
			gui.drawText(248, textY, "0%:Sol", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		else
			gui.drawText(248, textY, "Skl%:Sol", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
		end
		textY = textY - 10;
	end
	
	local attackerWeaponType = WEAPON_DATA[attackerWeaponID + LUA_TABLES_SUCK][WEAPON_TYPE];
	local targetWeaponType = WEAPON_DATA[targetWeaponID + LUA_TABLES_SUCK][WEAPON_TYPE];
	if (WEAPON_TRIANGLE[attackerWeaponType][targetWeaponType] == 1) then
		gui.drawText(82, 169, "A", "#FF00FF00", "#FF00FF00"); --Somehow, don't ask me how, this makes really solid triangles that look nothing like letters.
		gui.drawText(157, 169, "V", "#FFFF0000", "#FFFF0000"); --This is an accidental win. I love it.
	elseif (WEAPON_TRIANGLE[attackerWeaponType][targetWeaponType] == -1) then
		gui.drawText(82, 169, "V", "#FFFF0000", "#FFFF0000");
		gui.drawText(157, 169, "A", "#FF00FF00", "#FF00FF00");
	end
	
	local attackerBraveWeapon = WEAPON_DATA[attackerWeaponID + LUA_TABLES_SUCK][WEAPON_IS_BRAVE];
	local targetBraveWeapon = WEAPON_DATA[targetWeaponID + LUA_TABLES_SUCK][WEAPON_IS_BRAVE];
	local attackerNumSwings = 1;
	local targetNumSwings = 1;
	if (attackerWillFollowUp) then
		attackerNumSwings = 2;
	end
	if (attackerBraveWeapon == 1) then
		attackerNumSwings = attackerNumSwings * 2;
	end
	if (not canTargetCounter) then
		targetNumSwings = 0;
	end
	if (targetWillFollowUp) then
		targetNumSwings = targetNumSwings * 2;
	end
	if (targetBraveWeapon == 1) then
		targetNumSwings = targetNumSwings * 2;
	end
	local attackerRawAttack = mainmemory.read_u8(FORECAST_ATTACKER_ATK);
	local attackerDefense = mainmemory.read_u8(FORECAST_ATTACKER_DEF);
	local targetRawAttack = mainmemory.read_u8(FORECAST_TARGET_ATK);
	local targetDefense = mainmemory.read_u8(FORECAST_TARGET_DEF);
	local attackerEffectiveAttack = attackerRawAttack - targetDefense;
	local targetEffectiveAttack = targetRawAttack - attackerDefense;
	local attackerTotalAttack = attackerEffectiveAttack * attackerNumSwings;
	local targetTotalAttack = targetEffectiveAttack * targetNumSwings;
	gui.drawText(0, 189, "Atk "..attackerTotalAttack, nil, PLAYER_TEXT_COLOR);
	if (canTargetCounter) then
		gui.drawText(248, 189, targetTotalAttack.." Atk", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	else
		gui.drawText(248, 189, "--- Atk", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	end
	
	--Weapon effectiveness: If a weapon is "effective" against the target unit, it automatically crits, unless enemy has Nihil.
	local attackerWeaponEffective = WEAPON_DATA[attackerWeaponID + LUA_TABLES_SUCK][WEAPON_EFFECTIVE];
	local targetWeaponEffective = WEAPON_DATA[targetWeaponID + LUA_TABLES_SUCK][WEAPON_EFFECTIVE];
	local attackerUnitEffective = CLASS_DATA[attackerClassID + LUA_TABLES_SUCK][CLASS_EFFECTIVE];
	local targetUnitEffective = CLASS_DATA[targetClassID + LUA_TABLES_SUCK][CLASS_EFFECTIVE];
	if (attackerWeaponEffective ~= 0 and attackerWeaponEffective == targetUnitEffective and targetSkills&0x1000 == 0) then
		attackerSureCrit = true;
		gui.drawText(92, 169, "!!", nil, PLAYER_TEXT_COLOR);
	end
	if (targetWeaponEffective ~= 0 and targetWeaponEffective == attackerUnitEffective and attackerSkills&0x1000 == 0) then
		targetSureCrit = true;
		gui.drawText(139, 169, "!!", nil, ENEMY_TEXT_COLOR);
	end
	
	local attackerCrit = mainmemory.read_u8(FORECAST_ATTACKER_CRIT);
	local targetCrit = mainmemory.read_u8(FORECAST_TARGET_CRIT);	
	gui.drawText(0, 209, "Crt "..attackerCrit, nil, PLAYER_TEXT_COLOR);
	if (canTargetCounter) then
		gui.drawText(248, 209, targetCrit.." Crt", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	else
		gui.drawText(248, 209, "--- Crt", nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	end
	
	local attackerHPAfter = math.max(attackerHPBefore - targetTotalAttack, 0);
	local targetHPAfter = math.max(targetHPBefore - attackerTotalAttack, 0);	
	gui.drawText(0, 179, attackerHPBefore..">"..attackerHPAfter, nil, PLAYER_TEXT_COLOR);
	gui.drawText(248, 179, targetHPAfter.."<"..targetHPBefore, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "right");
	
	gui.drawBox(45, 183, 45+attackerMaxHP+1, 190, nil, "#FF000000");
	gui.drawBox(45, 183, 45+attackerHPBefore+1, 190, "#00000000", "#FFFF0000");
	gui.drawBox(45, 183, 45+attackerHPAfter+1, 190, "#00000000", "#FF00FF00");
	gui.drawBox(203, 183, 203-targetMaxHP-1, 190, nil, "#FF000000");
	gui.drawBox(203, 183, 203-targetHPBefore-1, 190, "#00000000", "#FFFF0000");
	gui.drawBox(203, 183, 203-targetHPAfter-1, 190, "#00000000", "#FF00FF00");
	
	local arrowTail = "----";
	if (attackerSkills&0x0200 == 0x0200 or targetSkills&0x0200 == 0x0200) then
		arrowTail = "-x?-";
	end
	if (targetWillVantage and canTargetCounter) then
		if (targetBraveWeapon == 1) then
			gui.drawText(124, 189, targetEffectiveAttack.."x2<"..arrowTail, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "center");
		else
			gui.drawText(124, 189, targetEffectiveAttack.."<"..arrowTail, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "center");
		end
		if (attackerBraveWeapon == 1) then
			gui.drawText(124, 199, arrowTail..">"..attackerEffectiveAttack.."x2", nil, PLAYER_TEXT_COLOR, nil, nil, nil, "center");
		else
			gui.drawText(124, 199, arrowTail..">"..attackerEffectiveAttack, nil, PLAYER_TEXT_COLOR, nil, nil, nil, "center");
		end
	else
		if (attackerBraveWeapon == 1) then
			gui.drawText(124, 189, arrowTail..">"..attackerEffectiveAttack.."x2", nil, PLAYER_TEXT_COLOR, nil, nil, nil, "center");
		else
			gui.drawText(124, 189, arrowTail..">"..attackerEffectiveAttack, nil, PLAYER_TEXT_COLOR, nil, nil, nil, "center");
		end
		if (canTargetCounter) then
			if (targetBraveWeapon == 1) then
				gui.drawText(124, 199, targetEffectiveAttack.."x2<"..arrowTail, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "center");
			else
				gui.drawText(124, 199, targetEffectiveAttack.."<"..arrowTail, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "center");
			end
		end
	end
	if (attackerWillFollowUp) then
		if (attackerBraveWeapon == 1) then
			gui.drawText(124, 209, arrowTail..">"..attackerEffectiveAttack.."x2", nil, PLAYER_TEXT_COLOR, nil, nil, nil, "center");
		else
			gui.drawText(124, 209, arrowTail..">"..attackerEffectiveAttack, nil, PLAYER_TEXT_COLOR, nil, nil, nil, "center");
		end
	end
	if (targetWillFollowUp and canTargetCounter) then
		if (targetBraveWeapon == 1) then
			gui.drawText(124, 209, targetEffectiveAttack.."x2<"..arrowTail, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "center");
		else
			gui.drawText(124, 209, targetEffectiveAttack.."<"..arrowTail, nil, ENEMY_TEXT_COLOR, nil, nil, nil, "center");
		end
	end
end

--Function: DisplayMapHealthBars()
--Summary: Displays small health bars on every unit on the map screen.
--Parameters: None.
--Returns: Nothing.
function DisplayMapHealthBars()
	local bgScrollX = mainmemory.read_u16_le(BG1_SCREEN_X_SCROLL);
	local bgScrollY = mainmemory.read_u16_le(BG1_SCREEN_Y_SCROLL);
	
	for i = (UNIT_VARIABLES_TABLE_SIZE * 2 - 2), 0, -2 do
		local unitID = mainmemory.read_u16_le(UNIT_POINTER_TABLE + i);
		if (unitID == 0) then --No unit is in this slot. Skip it. (TODO: I suspect the first 0-entry in the list, starting from the bottom of the table, will always come after the last non-0-entry. If so, this continue can be a break.)
			goto continue; --Ugh. goto is such a terrible command. Lua why do you do this? Why don't you have a continue command?
		end
		local coreStatsPointer = mainmemory.read_u16_le(unitID + POINTER_TABLE_CORE_STATS_OFFSET);
		local dataPattern = mainmemory.read_u8(unitID + POINTER_TABLE_DATA_PATTERN_OFFSET);
		
		local currentHP = mainmemory.read_u8(coreStatsPointer + CORE_STATS_CURRENT_HP_OFFSET);
		if (currentHP == 0) then --Unit is dead. Its memory values remain but it's no longer on the map, so don't draw its health bar. (TODO: Is there a better way to check this?)
			goto continue;
		end
				
		local maxHP = 0;
		if (dataPattern == 0 or dataPattern == 2) then --Player
			local playerStatsPointer = mainmemory.read_u24_le(unitID + POINTER_TABLE_PLAYER_STATS_OFFSET);
			maxHP = memory.read_u8(playerStatsPointer + PLAYER_STATS_MAX_HP_OFFSET);
		else
			local enemyRomStatsPointer = mainmemory.read_u24_le(unitID + POINTER_TABLE_ENEMY_ROM_STATS_OFFSET);
			local classID = memory.read_u8(enemyRomStatsPointer + ENEMY_ROM_STATS_CLASS_OFFSET);
			local level = memory.read_u8(enemyRomStatsPointer + ENEMY_ROM_STATS_LEVEL_OFFSET);
			maxHP = CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MHP] + math.floor(level * CLASS_DATA[classID + LUA_TABLES_SUCK][CLASS_MHP_GROWTH] / 100);
		end
		
		local unitScreenX = mainmemory.read_u16_le(UNIT_X_SCREEN_POSITION_TABLE + i);
		local unitScreenY = mainmemory.read_u16_le(UNIT_Y_SCREEN_POSITION_TABLE + i);
		
		local fillLevel = 2 + math.floor(12 * currentHP / maxHP); --Ensures that bar is always at least 1 pixel, and that being even 1 below max will have 1 missing pixel.
		gui.drawBox(unitScreenX - bgScrollX, unitScreenY - bgScrollY + 13, unitScreenX - bgScrollX + 14, unitScreenY - bgScrollY + 15, nil, "#FF000000");
		gui.drawBox(unitScreenX - bgScrollX, unitScreenY - bgScrollY + 13, unitScreenX - bgScrollX + fillLevel, unitScreenY - bgScrollY + 15, "#00000000", "#FF00FF00");
		::continue::
	end
end

--Function: HandleThreatRange()
--Summary: Manages input and display of threat range overlay.
--Parameters: None.
--Returns: Nothing.
function HandleThreatRange()
	local p2ControllerButtons = joypad.get(2);
	local p2B = p2ControllerButtons["B"];
	if (p2B and not p2BLastFrame) then
		markQueued = true;
	end
	if (markQueued) then
		memory.usememorydomain("OAM");
		local cursorX = memory.read_u8(OAM_CURSOR_X) + mainmemory.read_u16_le(BG1_SCREEN_X_SCROLL) + CURSOR_OFFSET_CORRECTION;
		local cursorY = memory.read_u8(OAM_CURSOR_Y) + mainmemory.read_u16_le(BG1_SCREEN_Y_SCROLL) + CURSOR_OFFSET_CORRECTION;
		if (cursorX % 4 ~= 0) then
			cursorX = cursorX - 1; --Sometimes the cursor is 3 away, sometimes it's only 2 away. But it always moves 4 pixels at a time. This adjustment corrects for that.
		end
		if (cursorY % 4 ~= 0) then
			cursorY = cursorY - 1; --Sometimes the cursor is 3 away, sometimes it's only 2 away. But it always moves 4 pixels at a time. This adjustment corrects for that.
		end
		if (cursorX % 16 == 0 and cursorY % 16 == 0) then
			if (tileMarks[cursorX/16][cursorY/16] == 0) then
				tileMarks[cursorX/16][cursorY/16] = 1;
				--print("Added mark at "..cursorX..","..cursorY);
			else
				tileMarks[cursorX/16][cursorY/16] = 0;
				--print("Removed mark at "..cursorX..","..cursorY);
			end
			markQueued = false;
		end
		memory.usememorydomain("System Bus");
	end
	p2BLastFrame = p2B;

	local p2X = p2ControllerButtons["X"];
	if (p2X) then
		p2XFrames = p2XFrames + 1;
		if (p2XFrames <= 59) then
			gui.drawText(0,10,"Resetting threat marks...", nil, PLAYER_TEXT_COLOR);
		else
			for i = 1,64 do
				tileMarks[i] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
			end
			gui.drawText(0,10,"Threat marks reset", nil, PLAYER_TEXT_COLOR);
		end
	else
		p2XFrames = 0;
	end

	local bgScrollX = mainmemory.read_u16_le(BG1_SCREEN_X_SCROLL);
	local bgScrollY = mainmemory.read_u16_le(BG1_SCREEN_Y_SCROLL);

	for i = 1,64 do
		for j = 1,64 do
			if (tileMarks[i][j] == 1) then
				gui.drawBox(i*16-bgScrollX,j*16-bgScrollY,i*16-bgScrollX+15,j*16-bgScrollY+15,"#7feb34c0","#3feb34c0");
			end
		end
	end
end

--Function: IsCombatSceneShown()
--Summary: Attempts to determine if the game is currently showing a combat scene. Returns true if we think it is, and false otherwise.
--Parameters: None.
--Returns: boolean
function IsCombatSceneShown()
	if (mainmemory.read_u8(COMBAT_SCENE_PROBE_ADDRESS) > 0) then --This is a HUGE guess. Five minutes of testing back this claim up. This is not enough testing.
		return true;
	end
	return false;
end
	
--Continually-running BizHawk scripts always take the boilerplate form "while true do [stuff] emu.frameadvance(); end".
--Consider this the "main()" function.
while true do
	memory.usememorydomain("System Bus"); --This is default behavior, but I've learned not to trust defaults and instead state them explicitly.
	

	local p2ControllerButtons = joypad.get(2);
	local p2A = p2ControllerButtons["A"];
	if (p2A and not p2ALastFrame) then
		globalToggle = not globalToggle;
	end
	p2ALastFrame = p2A;
	
	if (globalToggle) then
		local displayFlags = mainmemory.read_u24_le(DISPLAY_FLAGS);
		local unitID = mainmemory.read_u16_le(HOVERED_UNIT_POINTER_TABLE_POINTER);
		local targetID = mainmemory.read_u16_le(TARGET_UNIT_POINTER_TABLE_POINTER);
		displayFlagsHistory[historyIndex] = displayFlags;
		unitIDHistory[historyIndex] = unitID;
		targetIDHistory[historyIndex] = targetID;
		historyIndex = historyIndex + 1;
		if (historyIndex > HISTORY_SIZE) then
			historyIndex = 1;
		end
		
		--Is the game's own combat forecast displayed? Have to check here instead of the if/elseif tree below because we have to temporarily switch memory domains.
		local forecastDisplayed = false;		
		memory.usememorydomain("VRAM");
		if (memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_RIGHT[1]) == FORECAST_VRAM_VALUE_CHECKS[1] and memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_RIGHT[2]) == FORECAST_VRAM_VALUE_CHECKS[2] and memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_RIGHT[3]) == FORECAST_VRAM_VALUE_CHECKS[3] and memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_RIGHT[4]) == FORECAST_VRAM_VALUE_CHECKS[4]) then
			forecastDisplayed = true;
		elseif (memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_LEFT[1]) == FORECAST_VRAM_VALUE_CHECKS[1] and memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_LEFT[2]) == FORECAST_VRAM_VALUE_CHECKS[2] and memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_LEFT[3]) == FORECAST_VRAM_VALUE_CHECKS[3] and memory.read_u16_le(FORECAST_VRAM_ADDRESS_CHECKS_LEFT[4]) == FORECAST_VRAM_VALUE_CHECKS[4]) then
			forecastDisplayed = true;
		end
		
		--Is a unit selected and awaiting a place to move to? Have to check here because we have to temporarily switch memory domains.
		local unitIsSelectedForMovement = false;
		memory.usememorydomain("OAM");
		if (memory.read_u8(OAM_CURSOR_TILE_ADDRESS) == OAM_CURSOR_TILE_UNIT_SELECTED) then
			unitIsSelectedForMovement = true;
		end
		
		--Is the "hand" cursor displayed? Have to check here etc.
		local handCursorDisplayed = false;
		if (memory.read_u8(OAM_CURSOR_TILE_ADDRESS) == OAM_CURSOR_TILE_HAND) then
			handCursorDisplayed = true;
		end
		memory.usememorydomain("System Bus");
			
		--Determine which overlay, if any, to show.
		if (not (displayFlagsHistory[1] == displayFlagsHistory[2] and displayFlagsHistory[1] == displayFlagsHistory[3] and displayFlagsHistory[1] == displayFlagsHistory[4] and displayFlagsHistory[1] == displayFlagsHistory[5] and displayFlagsHistory[1] == displayFlagsHistory[6])) then
			--Do nothing. Clearing screen causes unnecessary flicker.
		elseif (not (unitIDHistory[1] == unitIDHistory[2] and unitIDHistory[1] == unitIDHistory[3] and unitIDHistory[1] == unitIDHistory[4] and unitIDHistory[1] == unitIDHistory[5] and unitIDHistory[1] == unitIDHistory[6])) then
			--Do nothing. Clearing screen causes unnecessary flicker.
		elseif (not (targetIDHistory[1] == targetIDHistory[2] and targetIDHistory[1] == targetIDHistory[3] and targetIDHistory[1] == targetIDHistory[4] and targetIDHistory[1] == targetIDHistory[5] and targetIDHistory[1] == targetIDHistory[6])) then
			--Do nothing. Clearing screen causes unnecessary flicker.
		elseif (not (unitID <= UNIT_ID_MAXIMUM_VALID and unitID >= UNIT_ID_MINIMUM_VALID)) then
			gui.clearGraphics();
		elseif (forecastDisplayed) then
			DisplayCombatForecast();
		elseif (IsCombatSceneShown()) then
			gui.clearGraphics();
		elseif (unitIsSelectedForMovement) then
			HandleThreatRange();
			DisplayMapHealthBars();
			DisplayUnitStatsOverlay();
		elseif (handCursorDisplayed) then
			gui.clearGraphics();
		elseif (displayFlags&126 == 126) then --%01111110 and %01111111 seem to always correspond to cases where it's inappropriate for any overlay, EXCEPT for forecast and when unit move range is shown.
			gui.clearGraphics();
		else --All disable checks have passed; show overlay.
			HandleThreatRange();
			DisplayMapHealthBars();
			DisplayUnitStatsOverlay();
		end		
	else
		gui.clearGraphics();
		gui.drawBox(250,218,256,224,"#FFFF0000","#FFFF0000");
	end
	
	--[[
	The following are templates I assembled before implementing any functionality.
	gui.drawText(0, 179, "ClassName   HP99  At99 Ht999 Df99",nil,"#3F0000FF");
	gui.drawText(0, 189, "L99 X99 Mv99  99  AS99 Av999 Rs99",nil,"#3F0000FF");
	gui.drawText(0, 199, "WeaponName InvX Skill Skill Skill",nil,"#3F0000FF");
	gui.drawText(0, 209, "DXX *KIL        Skill Skill Skill",nil,"#3F0000FF");
	
	                     "Skill:Chn%             Chn%:Skill"
						 "Skill:Chn%             Chn%:Skill"
						 "Skill:Chn%             Chn%:Skill"
						 "ClassName__           ClassName__"
						 "WeaponName / !!   !! \ WeaponName"
						 "99>99 ********** ********** 99<99"
						 "Atk 396       ---->99*2 X 198 Atk"
						 "Hit 100 X 99*2<----       100 Hit"
						 "Crt 100       ---->99*2 X 100 Crt"
	]]--

	--End of BizHawk boilerplate.
	emu.frameadvance();
end