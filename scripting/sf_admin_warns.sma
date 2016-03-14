/*
*	SF Warn Menu			       v. 0.1.2
*	by serfreeman1337		http://1337.uz/
*/

/*
*	Credits:
*		neugomon - подсказки по оптимизации
*/

#include <amxmodx>
#include <amxmisc>

#define PLUGIN "SF Warn Menu"
#define VERSION "0.1.2"
#define AUTHOR "serfreeman1337"

#if AMXX_VERSION_NUM < 183
	#include <colorchat>
	
	#define print_team_default DontChange
	#define print_team_grey Grey
	#define print_team_red Red
	#define print_team_blue Blue

	#define MAX_PLAYERS 32
	#define MAX_NAME_LENGTH 32
#endif

// * -- КОНСТАНТЫ -- * //

enum _:reasons_struct
{
	REASON_NAME[64],
	REASON_HUD[256]
}

enum _:plugin_cvars
{
	CVAR_DEF_ACT,
	CVAR_DEF_WARNS
}

enum _:player_data_struct
{
	PLAYER_TARGET,
	PLAYER_TARGET_REASON[64]
}

// * -- ПЕРЕМЕННЫЕ -- * //

new cvar[plugin_cvars]
new players_data[MAX_PLAYERS + 1][player_data_struct]
new Array:reasons_array
new Trie:warns_trie
new hud_warn



public plugin_init()
{
	register_plugin(PLUGIN,VERSION,AUTHOR)
	
	register_dictionary("sf_warn_menu.txt")
	register_dictionary("common.txt")

	register_srvcmd("sf_warn_add","CmdHook_WarnAdd",-1,"<name for menu>;<name for hud>")
	register_clcmd("sf_warn_menu","CmdHook_WarnMenu",ADMIN_KICK,"[name or #userid] [reason or #reasonid] - open warn menu or warn player")
	register_clcmd("sf_warn_reason","CmdHook_Reason",ADMIN_KICK,"")
	
	hud_warn = CreateHudSyncObj()
	
	//
	// Действите, которое будет выполнено по дефолту
	//
	cvar[CVAR_DEF_ACT] = register_cvar("sf_warn_defact","kick [userid] [reason]")
	
	//
	// Макс. кол-во предупреждений
	//
	cvar[CVAR_DEF_WARNS] = register_cvar("sf_warn_max","3")
	
	// huyak huyak and production
	server_cmd("sf_warn_add WARN_SELF")
	
	warns_trie = TrieCreate()
}

//
// Меню со списком игроков
//
public Menu_PlayersList(id)
{
	new fmt[96]
	formatex(fmt,charsmax(fmt),"%L",id,"WARN_MENU1")
	
	new menu = menu_create(fmt,"MenuHandler_Global")
	
	new players[32],pnum,info[2],plr_name[MAX_NAME_LENGTH * 2]
	get_players(players,pnum)
	
	info[0] = 'p' // запоминаем что это меню игроков
	
	for(new i,player,paccess = 0 ; i < pnum ; i++)
	{
		player = players[i]
		get_user_name(player,plr_name,charsmax(plr_name))
		
		info[1] = player
		paccess = 0
		
		// помечаем что игрок имеет флаги на иммунтиет
		if(get_user_flags(player) & ADMIN_IMMUNITY)
		{
			add(plr_name,charsmax(plr_name)," \r*\w")
			paccess = ADMIN_RCON // игроков с иммунитетом могут кикать только игроки с флагом l
		}
		// помечаем что это hltv
		else if(is_user_hltv(player))
		{
			add(plr_name,charsmax(plr_name)," \r(HLTV)\w")
		}
		// помечаем что это бот
		else if(is_user_bot(player))
		{
			add(plr_name,charsmax(plr_name)," \r(BOT)\w")
		}
		
		menu_additem(menu,plr_name,info,paccess)
	}
	
	Menu_PostFormat(id,menu)
	menu_display(id,menu)
	
	return PLUGIN_HANDLED
}

//
// Меню с выбором причины
//
public Menu_ReasonsList(id,target)
{
	// причины предупреждений не заданы, сразу выполняем действие
	if(!reasons_array)
	{
		return PLUGIN_HANDLED
	}
	
	new fmt[96]
	formatex(fmt,charsmax(fmt),"%L",id,"WARN_MENU2")
	
	new menu = menu_create(fmt,"MenuHandler_Global")
	new size = ArraySize(reasons_array)
	
	new info[2]
	
	info[0] = 'r'
	info[1] = target
	
	for(new i,reason_info[reasons_struct] ; i < size ; i++)
	{
		ArrayGetArray(reasons_array,i,reason_info)
		
		if(strfind(reason_info[REASON_NAME],"WARN_") != -1)
		{
			formatex(fmt,charsmax(fmt),"%L",id,reason_info[REASON_NAME])
		}
		else
		{
			copy(fmt,charsmax(fmt),reason_info[REASON_NAME])
		}
		
		menu_additem(menu,fmt,info)
	}
	
	Menu_PostFormat(id,menu)
	menu_display(id,menu)

	return PLUGIN_HANDLED
}

//
// Меню подтверждения действия
//
public Menu_ReasonConfirm(id,target,reason_id)
{
	// всякие проверки
	if(!is_user_connected(target))
	{
		client_print_color(id,print_team_default,"%L",id,"CL_NOT_FOUND")
		return Menu_PlayersList(id)
	}
	
	new fmt[96]
	formatex(fmt,charsmax(fmt),"%L",id,"WARN_MENU3")
	
	new menu = menu_create(fmt,"MenuHandler_Global")
	
	new target_name[MAX_NAME_LENGTH]
	get_user_name(target,target_name,charsmax(target_name))
	
	new info[6]
	
	info[0] = 'c'
	info[1] = target
	info[3] = reason_id
	
	// 1. Игрок
	info[2] = 1
	formatex(fmt,charsmax(fmt),"%L \y%s\w",id,"PLAYER",target_name)
	menu_additem(menu,fmt,info)
	
	// 2. Причина
	info[2] = 2
	
	if(reason_id == 0)
	{
		formatex(fmt,charsmax(fmt),"%L \y%s\w",id,"WARN_TXT1",players_data[id][PLAYER_TARGET_REASON])
	}
	else
	{
		new reason_info[reasons_struct]
		ArrayGetArray(reasons_array,reason_id,reason_info)
		
		// ML
		if(strfind(reason_info[REASON_NAME],"WARN_") == 0)
		{
			formatex(fmt,charsmax(fmt),"%L \y%L\w",id,"WARN_TXT1",id,reason_info[REASON_NAME])
		}
		else
		{
			formatex(fmt,charsmax(fmt),"%L \y%s\w",id,"WARN_TXT1",reason_info[REASON_NAME])
		}
	}
	
	menu_additem(menu,fmt,info)
	
	// 3. Действие
	info[2] = 3
	formatex(fmt,charsmax(fmt),"%L",id,"WARN_TXT2")
	menu_additem(menu,fmt,info,ADMIN_RCON)
	
	// 4. Предупреждение
	info[2] = 4
	formatex(fmt,charsmax(fmt),"%L",id,"WARN_TXT3")
	menu_additem(menu,fmt,info)
	
	Menu_PostFormat(id,menu)
	menu_display(id,menu)
	
	return PLUGIN_HANDLED
}

//
// Действия меню
//
public MenuHandler_Global(id,menu,item)
{
	if(item == MENU_EXIT || (menu_items(menu) == 10 && item == 9))
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	new paccess,info[6],dummy
	menu_item_getinfo(menu,item,paccess,info,charsmax(info),.callback = dummy)
	
	new player = info[1]
	
	// всякие проверки
	if(!is_user_connected(player))
	{
		client_print_color(id,print_team_default,"%L",id,"CL_NOT_FOUND")
		
		menu_destroy(menu)
		return Menu_PlayersList(id)
	}
	else if((get_user_flags(player) & ADMIN_IMMUNITY) && !(get_user_flags(id) & ADMIN_RCON))
	{
		new name[MAX_NAME_LENGTH]
		get_user_name(player,name,charsmax(name))
		
		client_print_color(id,print_team_default,"%L",id,"CLIENT_IMM",name)
		
		menu_destroy(menu)
		return Menu_PlayersList(id)
	}
	
	switch(info[0])
	{
		case 'p': // меню игроков
		{
			if(!is_user_bot(player) && !is_user_hltv(player))
			{
				Menu_ReasonsList(id,player)
			}
			// выполняем действия для ботов и hltv сразу
			else
			{
				copy(players_data[id][PLAYER_TARGET_REASON],
					charsmax(players_data[][PLAYER_TARGET_REASON]),
					"?"
				)
				
				Warn_PerformAction(id,player,0,true)
			}
		}
		case 'r':
		{
			// своя причина
			if(item == 0)
			{
				players_data[id][PLAYER_TARGET] = player
				client_cmd(id,"messagemode sf_warn_reason")
			}
			// предустановленная причина
			else
			{
				Menu_ReasonConfirm(id,player,item)
			}
		}
		case 'c':
		{
			switch(info[2])
			{
				// возвращаем в меню выбора игрока
				case 1:
				{
					Menu_PlayersList(id)
				}
				// возвращаем в меню выбора причины
				case 2:
				{
					Menu_ReasonsList(id,player)
				}
				// выполняем действие сразу
				case 3:
				{
					Warn_PerformAction(id,player,info[3],true)
				}
				case 4:
				{
					Warn_PerformAction(id,player,info[3],false)
				}
			}
		}
	}
	
	menu_destroy(menu)
	return PLUGIN_HANDLED
}

//
// Пост обработка меню
//
Menu_PostFormat(id,menu)
{
	new fmt[96]
	new items = menu_items(menu)
	
	// не используем пагинацию если меньше 10 игроков
	if(items < 10)
	{
		menu_setprop(menu,MPROP_PERPAGE,false)
		
		for(new i,null_items = (9 - items) ; i < null_items ; i++)
		{
			menu_addblank(menu)
		}
		
		#if AMXX_VERSION_NUM >= 183
			menu_setprop(menu,MPROP_EXIT,MEXIT_FORCE)
		#else
			formatex(fmt,charsmax(fmt),"%L",id,"EXIT")
			menu_additem(menu,fmt,"e")
			
			return
		#endif
	}
	// текст кнопок ДАЛЕЕ и НАЗАД
	else
	{
		formatex(fmt,charsmax(fmt),"%L",id,"BACK")
		menu_setprop(menu,MPROP_BACKNAME,fmt)
		
		formatex(fmt,charsmax(fmt),"%L",id,"MORE")
		menu_setprop(menu,MPROP_NEXTNAME,fmt)
	}
	
	// текст кнопки ВЫХОД
	formatex(fmt,charsmax(fmt),"%L",id,"EXIT")
	menu_setprop(menu,MPROP_EXITNAME,fmt)
}

//
// Предупреждаем или кикаем
//
public Warn_PerformAction(id,target,reason_id,bool:is_action)
{
	// всякие проверки
	if(!is_user_connected(target))
	{
		client_print_color(id,print_team_default,"%L",id,"CL_NOT_FOUND")
		
		return Menu_PlayersList(id)
	}
	else if((get_user_flags(target) & ADMIN_IMMUNITY) && !(get_user_flags(id) & ADMIN_RCON))
	{
		new name[MAX_NAME_LENGTH]
		get_user_name(target,name,charsmax(name))
		
		client_print_color(id,print_team_default,"%L",id,"CLIENT_IMM",name)
		
		return Menu_PlayersList(id)
	}
	
	new reason_info[reasons_struct],max_warns = get_pcvar_num(cvar[CVAR_DEF_WARNS])
	new admin_name[MAX_NAME_LENGTH],target_name[MAX_NAME_LENGTH],target_warns
	new admin_steamid[36],target_steamid[36]
	
	get_user_name(id,admin_name,charsmax(admin_name))
	get_user_name(target,target_name,charsmax(target_name))
	
	get_user_name(id,admin_steamid,charsmax(admin_steamid))
	get_user_name(target,target_steamid,charsmax(target_steamid))
	
	ArrayGetArray(reasons_array,reason_id,reason_info)
	
	// устанавливаем название своей причины
	if(reason_id == 0)
	{
		copy(reason_info[REASON_NAME],
			charsmax(reason_info[REASON_NAME]),
			players_data[id][PLAYER_TARGET_REASON]
		)
		
		copy(reason_info[REASON_HUD],
			charsmax(reason_info[REASON_HUD]),
			players_data[id][PLAYER_TARGET_REASON]
		)
	}
	
	// увеличиваем уровень предупреждений и выполняем действие, если достигнут максимум
	if(!is_action)
	{
		new target_ip[16]
		get_user_ip(target,target_ip,charsmax(target_ip),true)
		
		TrieGetCell(warns_trie,target_ip,target_warns)
		TrieSetCell(warns_trie,target_ip,++ target_warns)
		
		if(target_warns >= max_warns)
		{
			is_action = true
			TrieDeleteKey(warns_trie,target_ip) // сбрасываем счетчик предупреждений
		}
		
		log_amx("Warn: ^"%s<%d><%s><>^" warn ^"%s<%d><%s><>^" for ^"%s^" [%d/%d]",
			admin_name,get_user_userid(id),admin_steamid,
			target_name,get_user_userid(target),target_steamid,
			
			reason_info[REASON_NAME],
			target_warns,max_warns
		)
	}
	
	new wkey1[12],wkey2[12],wkey3[12]
	
	// huyak huyak and production
	if(!is_action)
	{
		copy(wkey1,charsmax(wkey1),"WARN_TXT4")
		copy(wkey2,charsmax(wkey2),"WARN_TXT5")
		copy(wkey3,charsmax(wkey3),"WARN_TXT8")
	
	}
	else
	{
		copy(wkey1,charsmax(wkey1),"WARN_TXT6")
		copy(wkey2,charsmax(wkey2),"WARN_TXT7")
	}
	
	// с поддержкой ML
	if(reason_id == 0 || strfind(reason_info[REASON_NAME],"WARN_") == -1)
	{
		show_activity_key_colored(wkey1,wkey2,admin_name,
			target_name,
			
			LANG_PLAYER,
			"WARN_NULL",
			reason_info[REASON_NAME],
			
			target_warns,
			max_warns
		)
	}
	// без поддержки ML
	else
	{
		show_activity_key_colored(wkey1,wkey2,admin_name,
			target_name,
			
			LANG_PLAYER,
			reason_info[REASON_NAME],
			
			target_warns,
			max_warns
		)
		
	}
	
	// предупреждение
	if(!is_action)
	{
		ClearSyncHud(target,hud_warn)
		set_hudmessage(255,75,75)
		
		// с именем администратора
		if(get_cvar_num("amx_show_activity") == 2)
		{
			// поддержкой ML
			if(strfind(reason_info[REASON_HUD],"WARN_") == 0)
			{
				ShowSyncHudMsg(target,hud_warn,"%L",
					target,"WARN_TXT9",
					
					target_warns,
					max_warns,
					
					admin_name,
					
					target,reason_info[REASON_HUD]
				)
			}
			// без поддержки ML
			else
			{
				ShowSyncHudMsg(target,hud_warn,"%L",
					target,"WARN_TXT9",
					
					target_warns,
					max_warns,
					
					admin_name,
					
					target,"WARN_NULL",reason_info[REASON_HUD]
				)
			}
		}
		// без имени администратора
		else
		{
			// поддержкой ML
			if(strfind(reason_info[REASON_HUD],"WARN_") == 0)
			{
				ShowSyncHudMsg(target,hud_warn,"%L",
					target,"WARN_TXT8",
					
					target_warns,
					max_warns,
					
					target,reason_info[REASON_HUD]
				)
			}
			// без поддержки ML
			else
			{
				ShowSyncHudMsg(target,hud_warn,"%L",
					target,"WARN_TXT8",
					
					target_warns,
					max_warns,
					
					target,"WARN_NULL",reason_info[REASON_HUD]
				)
			}
		}
	}
	// выполняем действие
	else
	{
		new action_string[256],reason_for_target[128]
		
		if(strfind(reason_info[REASON_NAME],"WARN_") == 0)
		{
			formatex(reason_for_target,charsmax(reason_for_target),"%L",target,reason_info[REASON_NAME])
		}
		else
		{
			formatex(reason_for_target,charsmax(reason_for_target),reason_info[REASON_NAME])
		}
		
		get_pcvar_string(cvar[CVAR_DEF_ACT],action_string,charsmax(action_string))
		
		new target_authid[36],target_userid[10]
		
		get_user_authid(target,target_authid,charsmax(target_authid))
		formatex(target_userid,charsmax(target_userid),"#%d",get_user_userid(target))
		
		replace(action_string,charsmax(action_string),"[userid]",target_userid)
		replace(action_string,charsmax(action_string),"[authid]",target_authid)
		replace(action_string,charsmax(action_string),"[reason]",reason_for_target)
		
		server_cmd(action_string)
		server_exec()
		
		log_amx("Action: ^"%s<%d><%s><>^" on ^"%s<%d><%s><>^" for ^"%s^" [%s]",
			admin_name,get_user_userid(id),admin_steamid,
			target_name,get_user_userid(target),target_steamid,
			
			reason_info[REASON_NAME],
			action_string
		)
	}

	return PLUGIN_HANDLED
}

public CmdHook_WarnMenu(id,level,cid)
{
	if(!cmd_access(id,level,cid,0))
	{
		return PLUGIN_HANDLED
	}
	
	if(read_argc() >= 2)
	{
		new name_or_userid[MAX_NAME_LENGTH]
		read_argv(1,name_or_userid,charsmax(name_or_userid))
		
		players_data[id][PLAYER_TARGET] = cmd_target(id,name_or_userid,0)
		
		if(!players_data[id][PLAYER_TARGET])
			return PLUGIN_HANDLED
		
		if(read_argc() == 2)
			return Menu_ReasonsList(id,players_data[id][PLAYER_TARGET])
	}
	
	if(read_argc() == 3)
	{
		read_argv(2,players_data[id][PLAYER_TARGET_REASON],charsmax(players_data[][PLAYER_TARGET_REASON]))
		return Warn_PerformAction(id,players_data[id][PLAYER_TARGET],0,false)
	}
	
	return Menu_PlayersList(id)
}

//
// Ввод своей причины
//
public CmdHook_Reason(id,level,cid)
{
	if(!cmd_access(id,level,cid,1))
	{
		return PLUGIN_HANDLED
	}
	
	if(!players_data[id][PLAYER_TARGET])
	{
		return PLUGIN_HANDLED
	}
	
	read_argv(1,players_data[id][PLAYER_TARGET_REASON],charsmax(players_data[][PLAYER_TARGET_REASON]))
	
	if(!players_data[id][PLAYER_TARGET_REASON][0])
	{
		return Menu_ReasonsList(id,players_data[id][PLAYER_TARGET])
	}
	
	return Menu_ReasonConfirm(id,players_data[id][PLAYER_TARGET],0)
}

//
// Регистрация причины предупреждения
//
public CmdHook_WarnAdd()
{
	new cmd_str[512],l,reason_info[reasons_struct]
	read_args(cmd_str,charsmax(cmd_str))
	remove_quotes(cmd_str)
	
	// парсим команду
	for(;;)
	{
		switch(l)
		{
			// название причины в меню
			case 0:
			{
				strtok(cmd_str,reason_info[REASON_NAME],charsmax(reason_info[REASON_NAME]),cmd_str,charsmax(cmd_str),';')
				copy(reason_info[REASON_HUD],charsmax(reason_info[REASON_HUD]),reason_info[REASON_NAME])
			}
			// название причины в HUD
			case 1:
			{
				strtok(cmd_str,reason_info[REASON_HUD],charsmax(reason_info[REASON_HUD]),cmd_str,charsmax(cmd_str),';')
			}
			// narkoman wole suka
			default:
			{
				break
			}
		}
		
		
		if(!cmd_str[0])
		{
			break
		}
		
		l ++
	}
	
	// в массив
	if(!reasons_array)
	{
		reasons_array = ArrayCreate(reasons_struct)
	}
	
	ArrayPushArray(reasons_array,reason_info)
}

//
// КЛАЛ Я НА ВАШИ ЗАМЕЧАНИЯ К МОЕМУ КОДУ
//

stock show_activity_key_colored(const KeyWithoutName[], const KeyWithName[], const ___AdminName[], any:...)
{
// The variable gets used via vformat, but the compiler doesn't know that, so it still cries.
#pragma unused ___AdminName
	static __amx_show_activity;
	if (__amx_show_activity == 0)
	{
		__amx_show_activity = get_cvar_pointer("amx_show_activity");
	
		// if still not found, then register the cvar as a dummy
		if (__amx_show_activity == 0)
		{
			__amx_show_activity = register_cvar("amx_show_activity", "2");
		}
	}
	
	new buffer[512];
	new keyfmt[256];
	new i;
	
	new __maxclients=get_maxplayers();
	
	switch( get_pcvar_num(__amx_show_activity) )
	{
	case 5: // hide name to admins, display nothing to normal players
		while (i++ < __maxclients)
		{
			if ( is_user_connected(i) )
			{
				if ( is_user_admin(i) )
				{
					LookupLangKey(keyfmt, charsmax(keyfmt), KeyWithoutName, i);

					// skip the "adminname" argument if not showing name
					vformat(buffer, charsmax(buffer), keyfmt, 4);
					client_print_color(i, print_team_default, "%s", buffer);
				}
			}
		}
	case 4: // show name only to admins, display nothing to normal players
		while (i++ < __maxclients)
		{
			if ( is_user_connected(i) )
			{
				if ( is_user_admin(i) )
				{
					LookupLangKey(keyfmt, charsmax(keyfmt), KeyWithName, i);
					vformat(buffer, charsmax(buffer), keyfmt, 3);
					client_print_color(i, print_team_default, "%s", buffer);
				}
			}
		}
	case 3: // show name only to admins, hide name from normal users
		while (i++ < __maxclients)
		{
			if ( is_user_connected(i) )
			{
				if ( is_user_admin(i) )
				{
					LookupLangKey(keyfmt, charsmax(keyfmt), KeyWithName, i);
					vformat(buffer, charsmax(buffer), keyfmt, 3);
				}
				else
				{
					LookupLangKey(keyfmt, charsmax(keyfmt), KeyWithoutName, i);
					
					// skip the "adminname" argument if not showing name
					vformat(buffer, charsmax(buffer), keyfmt, 4);
				}
				client_print_color(i, print_team_default, "%s", buffer);
			}
		}
	case 2: // show name to all users
		while (i++ < __maxclients)
		{
			if ( is_user_connected(i) )
			{
				LookupLangKey(keyfmt, charsmax(keyfmt), KeyWithName, i);
				vformat(buffer, charsmax(buffer), keyfmt, 3);
				client_print_color(i, print_team_default, "%s", buffer);
			}
		}
	case 1: // hide name from all users
		while (i++ < __maxclients)
		{
			if ( is_user_connected(i) )
			{
				LookupLangKey(keyfmt, charsmax(keyfmt), KeyWithoutName, i);

				// skip the "adminname" argument if not showing name
				vformat(buffer, charsmax(buffer), keyfmt, 4);
				client_print_color(i, print_team_default, "%s", buffer);
			}
		}
		
	}
}
