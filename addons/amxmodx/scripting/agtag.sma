#include <amxmodx>
#include <amxmisc>
#include <celltrie>
#include <engine>
#include <fakemeta_util>
#include <fun>
#include <hamsandwich>
#include <hl>

#pragma semicolon 1
#pragma ctrlchar '\'

#define MAX_PLAYERS					32
#define TASKID_UNFREEZE_PLAYER 		221309

#define get_bit(%1,%2) (%1 & (1 << (%2 - 1)))
#define set_bit(%1,%2) (%1 |= (1 << (%2 - 1)))
#define clr_bit(%1,%2) (%1 &= ~(1 << (%2 - 1)))

new const PLUGIN[] = "AG Tag";
new const PLUGIN_TAG[] = "AG Tag";
new const VERSION[] = "0.11";
new const AUTHOR[] = "mxpph";

new bool:g_isTagged[MAX_PLAYERS + 1];
new g_baIsFrozen;

public plugin_init()
{
	new ag_gamemode[32];
	get_cvar_string("sv_ag_gamemode", ag_gamemode, charsmax(ag_gamemode));
	if (ag_gamemode[0] && !equal(ag_gamemode, "agtag"))
	{
		server_print("The agtag.amxx plugin can only be run in \"agtag\" mode.");
		pause("ad");
		return;
	}

	register_plugin(PLUGIN, VERSION, AUTHOR);
	RegisterHam(Ham_TakeDamage, "player", "Fw_HamTakeDamagePlayer");
	register_clcmd("say",		"CmdSayHandler");
	register_clcmd("say_team",	"CmdSayHandler");
	register_forward(FM_PlayerPreThink, "Fw_FmPlayerPreThinkPost", 1);
}

public client_putinserver(id)
{
	g_isTagged[id] = false;
}

public client_disconnected(id)
{
	if (g_isTagged[id])
		ChooseTaggedPlayer();

	g_isTagged[id] = false;
}

public CmdSayHandler(id, level, cid)
{
	static args[64];
	read_args(args, charsmax(args));
	remove_quotes(args);
	trim(args);

	if (args[0] != '/' && args[0] != '.' && args[0] != '!')
		return PLUGIN_CONTINUE;

	else if (equali(args[1], "start"))
	{
		if (is_user_admin(id))
			ChooseTaggedPlayer();
	}

	else
		return PLUGIN_CONTINUE;

	return PLUGIN_HANDLED;
}

public ChooseTaggedPlayer()
{
	new players[MAX_PLAYERS];
	new count, randomplayer;

	get_players(players, count, "ach");
	randomplayer = players[random(count)];

	g_isTagged[randomplayer] = true;
	set_user_rendering(randomplayer, kRenderFxGlowShell, 255, 0, 0, kRenderNormal, 75);
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

public TaskUnfreeze(taskId)
{
	UnfreezePlayer(taskId - TASKID_UNFREEZE_PLAYER);
}


// *******************  //
//					  	//
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
	if(g_isTagged[aggressor])
	{
		g_isTagged[victim] = true;
		g_isTagged[aggressor] = false;

		set_user_rendering(victim, kRenderFxGlowShell, 255, 0, 0, kRenderNormal, 75);
		set_user_rendering(aggressor); // reset rendering

		client_print(victim, print_chat, "[%s] You are tagged!", PLUGIN_TAG);
		client_print(aggressor, print_chat, "[%s] You are no longer tagged!", PLUGIN_TAG);

		FreezePlayer(victim);
		set_task(3.00, "TaskUnfreeze", victim + TASKID_UNFREEZE_PLAYER);
		
		return HAM_HANDLED;
	}

	return HAM_IGNORED;
}