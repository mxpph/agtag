#include <amxmodx>
#include <amxmisc>
#include <celltrie>
#include <engine>
#include <fakemeta_util>
#include <fun>
#include <hamsandwich>
#include <hl>
#include <hl_kreedz_util>

#pragma semicolon 1
#pragma ctrlchar '\'

#define MAX_PLAYERS						32
#define HUD_UPDATE_TIME					0.05
#define TASKID_UNFREEZE_PLAYER 			221309
#define TASKID_REMOVE_WEAPONS			626051
#define TASKID_FIRST_SPAWN				454651

#define get_bit(%1,%2) (%1 & (1 << (%2 - 1)))
#define set_bit(%1,%2) (%1 |= (1 << (%2 - 1)))
#define clr_bit(%1,%2) (%1 &= ~(1 << (%2 - 1)))

new const PLUGIN[] = "AG Tag";
new const PLUGIN_TAG[] = "AG Tag";
new const VERSION[] = "0.17";
new const AUTHOR[] = "mxpph";

new const g_ItemNames[][] =
{
	"weapon_357",
	"weapon_9mmAR",
	"weapon_9mmhandgun",
	"weapon_crossbow",
	"weapon_crowbar",
	"weapon_egon",
	"weapon_gauss",
	"weapon_handgrenade",
	"weapon_hornetgun",
	"weapon_rpg",
	"weapon_satchel",
	"weapon_shotgun",
	"weapon_snark",
	"weapon_tripmine",
	"ammo_357",
	"ammo_9mmAR",
	"ammo_9mmbox",
	"ammo_9mmclip",
	"ammo_ARgrenades",
	"ammo_buckshot",
	"ammo_crossbow",
	"ammo_gaussclip",
	"ammo_rpgclip",
	"item_battery",
	"item_healthkit",
	"item_longjump",
	"item_suit",
	"func_healthcharger",
	"func_recharge"
};

new g_baIsFrozen;
new bool:g_isTagged[MAX_PLAYERS + 1];

new g_SyncHudTagStatus;
new g_TaskEnt;

new taggedPlayerName[33];
new taggedPlayerId;

new pcvar_agtag_glowamount;
new pcvar_agtag_cooldowntime;
new pcvar_agtag_falldamage;
new pcvar_agtag_hp;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	server_cmd("mp_teamplay 0");
	server_exec();

	new ag_gamemode[32];
	get_cvar_string("sv_ag_gamemode", ag_gamemode, charsmax(ag_gamemode));
	if (ag_gamemode[0] && !equal(ag_gamemode, "agtag"))
	{
		server_print("The agtag.amxx plugin can only be run in \"agtag\" mode.");
		pause("ad");
		return;
	}

	pcvar_agtag_glowamount = register_cvar("agtag_glowamount", "125");
	pcvar_agtag_cooldowntime = register_cvar("agtag_cooldowntime", "3.00");
	pcvar_agtag_falldamage = register_cvar("agtag_falldamage", "0");
	pcvar_agtag_hp = register_cvar("agtag_hp", "20");

	register_clcmd("say",		"CmdSayHandler");
	register_clcmd("say_team",	"CmdSayHandler");
	register_clcmd("drop",		"CmdDropHandler");

	register_forward(FM_PlayerPreThink, "Fw_FmPlayerPreThinkPost", 1);
	register_forward(FM_Think, "Fw_FmThinkPre");
	RegisterHam(Ham_TakeDamage, "player", "Fw_HamTakeDamagePlayer");
	RegisterHam(Ham_Spawn, "player", "Fw_HamPlayerSpawnPost", 1);
	RegisterHam(Ham_Spawn, "weaponbox", "Fw_HamSpawnWeaponboxPost", 1);

	g_SyncHudTagStatus = CreateHudSyncObj();

	g_TaskEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	set_pev(g_TaskEnt, pev_classname, engfunc(EngFunc_AllocString, "timer_entity"));
	set_pev(g_TaskEnt, pev_nextthink, get_gametime() + 1.01);

	set_task(0.05, "RemoveWeapons", TASKID_REMOVE_WEAPONS);
}

public client_putinserver(id)
{
	g_isTagged[id] = false;
	set_task(0.50, "FirstSpawn", TASKID_FIRST_SPAWN + id);
}

public client_disconnected(id)
{
	if (g_isTagged[id])
		ChooseRandomTaggedPlayer(false, true);
}

// *******************	//
//						//
//	Player Handling		//
//						//
// *******************	//

public CmdSayHandler(id, level, cid)
{
	static args[64];
	read_args(args, charsmax(args));
	remove_quotes(args);
	trim(args);

	if (args[0] != '/' && args[0] != '.' && args[0] != '!')
		return PLUGIN_CONTINUE;

	else if (equali(args[1], "firsttag"))
	{
		if (is_user_admin(id))
			ChooseRandomTaggedPlayer();
        else
            client_print(id, print_chat, "[%s] Only admins may use that command.", PLUGIN_TAG);
	}

	else
		return PLUGIN_CONTINUE;

	return PLUGIN_HANDLED;
}

public CmdDropHandler(id)
{
	client_print(id, print_chat, "[%s] Weapon dropping is disabled.", PLUGIN_TAG);
	return PLUGIN_HANDLED;
}

ChooseRandomTaggedPlayer(bool:firstPlayer = false, bool:punishPlayer = false)
{
	new players[MAX_PLAYERS];
	new count, randomplayer;

	get_players(players, count);
	randomplayer = players[random(count)]; // FIXME: There is apparently an out of bounds error here. No idea why.

    if(!firstPlayer)
    {
    	if (punishPlayer)
    		ExecuteHamB(Ham_AddPoints, taggedPlayerId, -2, true); // Punish for disconnecting while tagged

        UntagPlayer(taggedPlayerId);
    }

	TagPlayer(randomplayer, firstPlayer);
}

TagPlayer(player, bool:firstPlayer = false)
{
	g_isTagged[player] = true;
	set_user_rendering(player, kRenderFxGlowShell, 255, 0, 0, kRenderNormal, get_pcvar_num(pcvar_agtag_glowamount));

	GetColorlessName(player, taggedPlayerName, charsmax(taggedPlayerName));
    taggedPlayerId = player;

	client_print(player, print_chat, "[%s] You are tagged!", PLUGIN_TAG);
	client_cmd(player, "spk \"sound/tagged\"");

	if(!firstPlayer)
	{
		ExecuteHamB(Ham_AddPoints, player, -1, true);
		FreezePlayer(player);
		set_task(get_pcvar_float(pcvar_agtag_cooldowntime), "TaskUnfreeze", player + TASKID_UNFREEZE_PLAYER);
	}
}

public UntagPlayer(player)
{
	g_isTagged[player] = false;
	set_user_rendering(player); // reset rendering

	client_cmd(0, "spk fvox/bell");
	client_print(player, print_chat, "[%s] You are no longer tagged!", PLUGIN_TAG);
}

public TaskUnfreeze(taskId)
{
	UnfreezePlayer(taskId - TASKID_UNFREEZE_PLAYER);
}

FreezePlayer(id)
{
	set_pev(id, pev_flags, pev(id, pev_flags) | FL_FROZEN);
	set_bit(g_baIsFrozen, id);
}

UnfreezePlayer(id)
{
	set_pev(id, pev_flags, pev(id, pev_flags) & ~FL_FROZEN);
	clr_bit(g_baIsFrozen, id);
}

public FirstSpawn(id)
{
	id -= TASKID_FIRST_SPAWN;
	ExecuteHamB(Ham_Spawn, id);
}


// *******************	//
//						//
//		Forwards		//
//						//
// *******************	//

public Fw_FmPlayerPreThinkPost(id)
{
	if (get_bit(g_baIsFrozen, id) && !(pev(id, pev_flags) & FL_FROZEN))
	{
		FreezePlayer(id);
	}
}

public Fw_HamTakeDamagePlayer(victim, inflictor, aggressor, Float:damage, damagebits)
{
    //    console_print(0, "damagebits: %d", damagebits);
	new bool:dmgOverride;

	if(g_isTagged[aggressor] && (damagebits & DMG_CLUB))
	{
		TagPlayer(victim);
		UntagPlayer(aggressor);
		dmgOverride = true;
	}

	if(!g_isTagged[aggressor] && g_isTagged[victim] && !(pev(victim, pev_flags) & FL_FROZEN) && (damagebits & DMG_CLUB))
	{
		ExecuteHamB(Ham_AddPoints, aggressor, 1, true);
		client_cmd(aggressor, "spk fvox/bell");
		dmgOverride = true;
	}

	if(!(damagebits & DMG_FALL) || !(get_pcvar_num(pcvar_agtag_falldamage)))
		dmgOverride = true;

	if(dmgOverride)
		return HAM_SUPERCEDE;
	else
		return HAM_HANDLED;
}

public Fw_HamPlayerSpawnPost(id)
{
	if(is_user_connected(id))
	{
		strip_user_weapons(id);
		give_item(id, "weapon_crowbar");

		new hp = get_pcvar_num(pcvar_agtag_hp);
		if (hp > 0 && hp < 100 )
			set_user_health(id, hp);
		else
			set_user_health(id, 100);
	}
	 // Check if there is a tagged player. If there is not, choose one.
	 // Checking here is best because, if there are no players in the server,
	 // then when one connects and spawns in, they are tagged.
	if(!taggedPlayerName[0])
	{
		ChooseRandomTaggedPlayer(true);
	}
}

public Fw_HamSpawnWeaponboxPost(weaponboxId)
{
	set_pev(weaponboxId, pev_flags, FL_KILLME);
	dllfunc(DLLFunc_Think, weaponboxId);

	return HAM_IGNORED;
}

// *******************	//
//						//
//	HUD management		//
//						//
// *******************	//

public Fw_FmThinkPre(ent)
{
	if (ent == g_TaskEnt)
	{
		// Hud update task
		static Float:currGameTime;
		currGameTime = get_gametime();
		UpdateHud(currGameTime);

		set_pev(ent, pev_nextthink, currGameTime + HUD_UPDATE_TIME);
	}
}

UpdateHud(Float:currGameTime)
{
	static players[MAX_PLAYERS], playersNum, id, i, playerName[33];

	get_players(players, playersNum);

	for (i = 0; i < playersNum; i++)
	{
		id = players[i];
		GetColorlessName(id, playerName, charsmax(playerName));
		set_hudmessage(255, 160, 0, -1.0, 0.1, 0, 0.0, 999999.0, 0.0, 0.0, -1);

		ShowSyncHudMsg(id, g_SyncHudTagStatus, "Tagged player: %s", taggedPlayerName);
	}
}

// *******************	//
//						//
//	Map management		//
//						//
// *******************	//

public RemoveWeapons()
{
	new ent, i;

	for(i = 0; i < sizeof(g_ItemNames); i++)
	{
		while((ent = find_ent_by_class(ent, g_ItemNames[i])) != 0)
		{
			if(is_valid_ent(ent))
			{
				set_pev(ent, pev_flags, FL_KILLME);
				dllfunc(DLLFunc_Think, ent);
			}
		}
	}

	return PLUGIN_HANDLED;
}
