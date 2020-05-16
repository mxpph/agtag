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

#define MAX_PLAYERS					32
#define HUD_UPDATE_TIME				0.05
#define TASKID_UNFREEZE_PLAYER 		221309

#define get_bit(%1,%2) (%1 & (1 << (%2 - 1)))
#define set_bit(%1,%2) (%1 |= (1 << (%2 - 1)))
#define clr_bit(%1,%2) (%1 &= ~(1 << (%2 - 1)))

new const PLUGIN[] = "AG Tag";
new const PLUGIN_TAG[] = "AG Tag";
new const VERSION[] = "0.13";
new const AUTHOR[] = "mxpph";

new g_baIsFrozen;
new bool:g_isTagged[MAX_PLAYERS + 1];

new g_SyncHudTagStatus;
new g_TaskEnt;

new taggedPlayerName[33];
new taggedPlayerId;

new pcvar_agtag_glowamount;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	new ag_gamemode[32];
	get_cvar_string("sv_ag_gamemode", ag_gamemode, charsmax(ag_gamemode));
	if (ag_gamemode[0] && !equal(ag_gamemode, "agtag"))
	{
		server_print("The agtag.amxx plugin can only be run in \"agtag\" mode.");
		pause("ad");
		return;
	}

	pcvar_agtag_glowamount = register_cvar("agtag_glowamount", "125");

	RegisterHam(Ham_TakeDamage, "player", "Fw_HamTakeDamagePlayer");
	register_clcmd("say",		"CmdSayHandler");
	register_clcmd("say_team",	"CmdSayHandler");
	register_forward(FM_PlayerPreThink, "Fw_FmPlayerPreThinkPost", 1);
	register_forward(FM_Think, "Fw_FmThinkPre");

	g_SyncHudTagStatus = CreateHudSyncObj();

	g_TaskEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	set_pev(g_TaskEnt, pev_classname, engfunc(EngFunc_AllocString, "timer_entity"));
	set_pev(g_TaskEnt, pev_nextthink, get_gametime() + 1.01);
}

public client_putinserver(id)
{
	g_isTagged[id] = false;
}

public client_disconnected(id)
{
	if (g_isTagged[id])
		ChooseRandomTaggedPlayer();
}

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
			ChooseRandomTaggedPlayer(true);
        else
            client_print(id, print_chat, "[%s] Only admins may use that command.", PLUGIN_TAG);
	}

	else
		return PLUGIN_CONTINUE;

	return PLUGIN_HANDLED;
}

ChooseRandomTaggedPlayer(bool:firstPlayer = false)
{
	new players[MAX_PLAYERS];
	new count, randomplayer;

	get_players(players, count, "ach");
	randomplayer = players[random(count)];

    if(!firstPlayer)
        UntagPlayer(taggedPlayerId);

	TagPlayer(randomplayer);
}

public TagPlayer(player)
{
	g_isTagged[player] = true;
	set_user_rendering(player, kRenderFxGlowShell, 255, 0, 0, kRenderNormal, get_pcvar_num(pcvar_agtag_glowamount));

	GetColorlessName(player, taggedPlayerName, charsmax(taggedPlayerName));
    taggedPlayerId = player;

	client_print(player, print_chat, "[%s] You are tagged!", PLUGIN_TAG);
	client_cmd(player, "spk \"sound/tagged\"");

	FreezePlayer(player);
	set_task(3.00, "TaskUnfreeze", player + TASKID_UNFREEZE_PLAYER);
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
	if(g_isTagged[aggressor] && (damagebits & DMG_CLUB))
	{
		TagPlayer(victim);
		UntagPlayer(aggressor);
	}

	return HAM_SUPERCEDE;
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
