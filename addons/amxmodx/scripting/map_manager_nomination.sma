#include <amxmodx>
#include <map_manager>
#include <map_manager_blocklist>

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#endif

#define PLUGIN "Map Manager: Nomination"
#define VERSION "0.0.2"
#define AUTHOR "Mistrick"

#pragma semicolon 1

#define get_num(%0) get_pcvar_num(g_pCvars[%0])

#if !defined client_disconnected
#define client_disconnected client_disconnect
#endif

enum {
	NOMINATION_FAIL,
	NOMINATION_SUCCESS,
	NOMINATION_REMOVED
};

enum {
	TYPE_STANDART,
	TYPE_FIXED
};

enum Cvars {
	TYPE,
	MAPS_IN_VOTE,
	MAPS_PER_PLAYER,
	DONT_CLOSE_MENU,
	DENOMINATE_TIME,
	RANDOM_SORT
};

new g_pCvars[Cvars];

new Array:g_aNomList;
new Array:g_aMapsList;
new g_hCallbackDisabled;
new g_iNomMaps[33];
new g_iLastDenominate[33];

new PREFIX[32];

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	g_pCvars[TYPE] = register_cvar("mapm_nom_type", "0"); // 0 - standart, 1 - fixed
	g_pCvars[MAPS_IN_VOTE] = register_cvar("mapm_nom_maps_in_vote", "3");
	g_pCvars[MAPS_PER_PLAYER] = register_cvar("mapm_nom_maps_per_player", "3");
	g_pCvars[DONT_CLOSE_MENU] = register_cvar("mapm_nom_dont_close_menu", "1"); // 0 - disable, 1 - enable
	g_pCvars[DENOMINATE_TIME] = register_cvar("mapm_nom_denominate_time", "5"); // seconds
	g_pCvars[RANDOM_SORT] = register_cvar("mapm_nom_random_sort", "0"); // 0 - disable, 1 - enable

	register_clcmd("say", "clcmd_say");
	register_clcmd("say_team", "clcmd_say");
	register_clcmd("say maps", "clcmd_mapslist");
	register_clcmd("say /maps", "clcmd_mapslist");

	g_hCallbackDisabled = menu_makecallback("callback_disable_item");
}
public plugin_natives()
{
	set_module_filter("module_filter_handler");
	set_native_filter("native_filter_handler");
}
public module_filter_handler(const library[], LibType:type)
{
	if(equal(library, "map_manager_blocklist")) {
		return PLUGIN_HANDLED;
	}
	return PLUGIN_CONTINUE;
}
public native_filter_handler(const native_func[], index, trap)
{
	if(equal(native_func, "mapm_get_blocked_count")) {
		return PLUGIN_HANDLED;
	}
	return PLUGIN_CONTINUE;
}
public callback_disable_item()
{
	return ITEM_DISABLED;
}
public mapm_maplist_loaded(Array:maplist)
{
	g_aMapsList = maplist;
	g_aNomList = ArrayCreate(NomStruct, 1);
	mapm_get_prefix(PREFIX, charsmax(PREFIX));
}
public client_disconnected(id)
{
	if(g_iNomMaps[id]) {
		clear_nominated_maps(id);
	}
}
public clcmd_say(id)
{
	new text[MAPNAME_LENGTH]; read_args(text, charsmax(text));
	remove_quotes(text); trim(text); strtolower(text);
	
	if(is_string_with_space(text)) return PLUGIN_CONTINUE;
	
	new map_index = mapm_get_map_index(text);

	if(map_index != INVALID_MAP_INDEX) {
		nominate_map(id, text, map_index);
	} else if(strlen(text) >= 4) {
		new Array:nominate_list = ArrayCreate(1, 1), array_size;

		map_index = 0;
		while( (map_index = find_similar_map(map_index, text)) != INVALID_MAP_INDEX ) {
			ArrayPushCell(nominate_list, map_index);
			array_size++;
			map_index++;
		}
		
		if(array_size == 1) {
			map_index = ArrayGetCell(nominate_list, 0);
			new map_info[MapStruct]; ArrayGetArray(g_aMapsList, map_index, map_info);
			nominate_map(id, map_info[MapName], map_index);
		} else if(array_size > 1) {
			show_nomlist(id, nominate_list, array_size);
		}
		
		ArrayDestroy(nominate_list);
	}

	return PLUGIN_CONTINUE;
}
nominate_map(id, map[], index)
{
	new map_info[MapStruct]; ArrayGetArray(g_aMapsList, index, map_info);
	
	if(mapm_get_blocked_count(map)) {
		client_print_color(id, print_team_default, "%s^1 %L", PREFIX, id, "MAPM_NOM_NOT_AVAILABLE_MAP");
		return NOMINATION_FAIL;
	}

	if(get_num(TYPE) == TYPE_FIXED && ArraySize(g_aNomList) >= get_num(MAPS_IN_VOTE)) {
		// TODO: add ML
		client_print_color(id, print_team_default, "%s^1 All nomination slots are reserved.", PREFIX);
		return NOMINATION_FAIL;
	}
	
	new nom_info[NomStruct], name[32];
	get_user_name(id, name, charsmax(name));
	
	new nom_index = map_nominated(index);
	if(nom_index != INVALID_MAP_INDEX) {
		ArrayGetArray(g_aNomList, nom_index, nom_info);
		if(id != nom_info[NomPlayer]) {
			client_print_color(id, print_team_default, "%s^1 %L", PREFIX, id, "MAPM_NOM_ALREADY_NOM");
			return NOMINATION_FAIL;
		}

		new systime = get_systime();
		if(g_iLastDenominate[id] + get_num(DENOMINATE_TIME) >= systime) {
			client_print_color(id, print_team_default, "%s^1 %L", PREFIX, id, "MAPM_NOM_SPAM");
			return NOMINATION_FAIL;
		}

		g_iLastDenominate[id] = systime;
		g_iNomMaps[id]--;
		ArrayDeleteItem(g_aNomList, nom_index);
		
		client_print_color(0, id, "%s^3 %L", PREFIX, LANG_PLAYER, "MAPM_NOM_REMOVE_NOM", name, map);
		return NOMINATION_REMOVED;
	}
	
	if(g_iNomMaps[id] >= get_num(MAPS_PER_PLAYER)) {
		client_print_color(id, print_team_default, "%s^1 %L", PREFIX, id, "MAPM_NOM_CANT_NOM");
		return NOMINATION_FAIL;
	}
	
	nom_info[NomPlayer] = id;
	nom_info[NomMapIndex] = index;
	ArrayPushArray(g_aNomList, nom_info);
	
	g_iNomMaps[id]++;
	
	client_print_color(0, id, "%s^3 %L", PREFIX, LANG_PLAYER, "MAPM_NOM_MAP", name, map);
	
	return NOMINATION_SUCCESS;
}
show_nomlist(id, Array: array, size)
{
	new text[64]; formatex(text, charsmax(text), "%L", LANG_PLAYER, "MAPM_MENU_FAST_NOM");
	new menu = menu_create(text, "nomlist_handler");
	new map_info[MapStruct], item_info[48], map_index, nom_index, block_count;
	
	for(new i, str_num[6]; i < size; i++) {
		map_index = ArrayGetCell(array, i);
		ArrayGetArray(g_aMapsList, map_index, map_info);
		
		num_to_str(map_index, str_num, charsmax(str_num));
		nom_index = map_nominated(map_index);
		block_count = mapm_get_blocked_count(map_info[MapName]);

		if(block_count) {
			formatex(item_info, charsmax(item_info), "%s[\r%d\d]", map_info[MapName], block_count);
			menu_additem(menu, item_info, str_num, _, g_hCallbackDisabled);
		} else if(nom_index != INVALID_MAP_INDEX) {
			new nom_info[NomStruct]; ArrayGetArray(g_aNomList, nom_index, nom_info);
			if(id == nom_info[NomPlayer]) {
				formatex(item_info, charsmax(item_info), "%s[\y*\w]", map_info[MapName]);
				menu_additem(menu, item_info, str_num);
			} else {
				formatex(item_info, charsmax(item_info), "%s[\y*\d]", map_info[MapName]);
				menu_additem(menu, item_info, str_num, _, g_hCallbackDisabled);
			}
		} else {
			menu_additem(menu, map_info[MapName], str_num);
		}
	}
	
	formatex(text, charsmax(text), "%L", id, "MAPM_MENU_BACK");
	menu_setprop(menu, MPROP_BACKNAME, text);
	formatex(text, charsmax(text), "%L", id, "MAPM_MENU_NEXT");
	menu_setprop(menu, MPROP_NEXTNAME, text);
	formatex(text, charsmax(text), "%L", id, "MAPM_MENU_EXIT");
	menu_setprop(menu, MPROP_EXITNAME, text);
	
	menu_display(id, menu);
}
public nomlist_handler(id, menu, item)
{
	if(item == MENU_EXIT) {
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}
	
	new item_info[8], item_name[MAPNAME_LENGTH + 16], access, callback;
	menu_item_getinfo(menu, item, access, item_info, charsmax(item_info), item_name, charsmax(item_name), callback);
	
	new map_index = str_to_num(item_info);
	trim_bracket(item_name);
	new map_nominated = nominate_map(id, item_name, map_index);
	
	if(map_nominated == NOMINATION_REMOVED || get_num(DONT_CLOSE_MENU)) {
		if(map_nominated == NOMINATION_SUCCESS) {
			format(item_name, charsmax(item_name), "%s[\y*\w]", item_name);
			menu_item_setname(menu, item, item_name);
		} else if(map_nominated == NOMINATION_REMOVED) {
			menu_item_setname(menu, item, item_name);
		}
		menu_display(id, menu);
	} else {
		menu_destroy(menu);
	}
	
	return PLUGIN_HANDLED;
}
public clcmd_mapslist(id)
{
	new text[64]; formatex(text, charsmax(text), "%L", LANG_PLAYER, "MAPM_MENU_MAP_LIST");
	new menu = menu_create(text, "mapslist_handler");
	
	new map_info[MapStruct], item_info[48], block_count, size = ArraySize(g_aMapsList);
	new random_sort = get_num(RANDOM_SORT), Array:array = ArrayCreate(1, 1);

	for(new i = 0, index, nom_index, num[8]; i < size; i++) {
		if(random_sort) {
			do {
				index = random(size);
			} while(in_array(array, index));
			ArrayPushCell(array, index);
		} else {
			index = i;
		}

		num_to_str(index, num, charsmax(num));
		ArrayGetArray(g_aMapsList, index, map_info);
		nom_index = map_nominated(index);
		block_count = mapm_get_blocked_count(map_info[MapName]);
		
		if(block_count) {
			formatex(item_info, charsmax(item_info), "%s[\r%d\d]", map_info[MapName], block_count);
			menu_additem(menu, item_info, _, _, g_hCallbackDisabled);
		} else if(nom_index != INVALID_MAP_INDEX) {
			new nom_info[NomStruct]; ArrayGetArray(g_aNomList, nom_index, nom_info);
			if(id == nom_info[NomPlayer]) {
				formatex(item_info, charsmax(item_info), "%s[\y*\w]", map_info[MapName]);
				menu_additem(menu, item_info, num);
			} else {
				formatex(item_info, charsmax(item_info), "%s[\y*\d]", map_info[MapName]);
				menu_additem(menu, item_info, num, _, g_hCallbackDisabled);
			}
		} else {
			menu_additem(menu, map_info[MapName], num);
		}
	}

	ArrayDestroy(array);

	formatex(text, charsmax(text), "%L", id, "MAPM_MENU_BACK");
	menu_setprop(menu, MPROP_BACKNAME, text);
	formatex(text, charsmax(text), "%L", id, "MAPM_MENU_NEXT");
	menu_setprop(menu, MPROP_NEXTNAME, text);
	formatex(text, charsmax(text), "%L", id, "MAPM_MENU_EXIT");
	menu_setprop(menu, MPROP_EXITNAME, text);
	
	menu_display(id, menu);
}
bool:in_array(Array:array, index)
{
	for(new i, size = ArraySize(array); i < size; i++) {
		if(ArrayGetCell(array, i) == index) {
			return true;
		}
	}
	return false;
}
public mapslist_handler(id, menu, item)
{
	if(item == MENU_EXIT) {
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}
	
	new item_info[8], item_name[MAPNAME_LENGTH + 16], access, callback;
	menu_item_getinfo(menu, item, access, item_info, charsmax(item_info), item_name, charsmax(item_name), callback);
	
	new map_index = str_to_num(item_info);
	trim_bracket(item_name);
	new map_nominated = nominate_map(id, item_name, map_index);
	
	if(g_iNomMaps[id] < get_num(MAPS_PER_PLAYER) || get_num(DONT_CLOSE_MENU)) {
		if(map_nominated == NOMINATION_SUCCESS) {
			format(item_name, charsmax(item_name), "%s[\y*\w]", item_name);
			menu_item_setname(menu, item, item_name);
		} else if(map_nominated == NOMINATION_REMOVED) {
			menu_item_setname(menu, item, item_name);
		}
		menu_display(id, menu, item / 7);
	} else {
		menu_destroy(menu);
	}
	
	return PLUGIN_HANDLED;
}

public mapm_prepare_votelist(type)
{
	if(type == VOTE_BY_SCHEDULER_SECOND) {
		return;
	}
	new nom_info[NomStruct], map_info[MapStruct];
	for(new i, index; i < get_num(MAPS_IN_VOTE) && ArraySize(g_aNomList); i++) {
		index = random(ArraySize(g_aNomList));
		ArrayGetArray(g_aNomList, index, nom_info);
		ArrayGetArray(g_aMapsList, nom_info[NomMapIndex], map_info);
		ArrayDeleteItem(g_aNomList, index);
		g_iNomMaps[nom_info[NomPlayer]]--;

		if(mapm_push_map_to_votelist(map_info[MapName], PUSH_BY_NOMINATION) == PUSH_BLOCKED) {
			i--;
		}
	}
}

map_nominated(index)
{
	new nom_info[NomStruct], size = ArraySize(g_aNomList);
	for(new i; i < size; i++) {
		ArrayGetArray(g_aNomList, i, nom_info);
		if(index == nom_info[NomMapIndex]) {
			return i;
		}
	}
	return INVALID_MAP_INDEX;
}
clear_nominated_maps(id)
{
	new nom_info[NomStruct];
	for(new i = 0; i < ArraySize(g_aNomList); i++) {
		ArrayGetArray(g_aNomList, i, nom_info);
		if(id == nom_info[NomPlayer]) {
			ArrayDeleteItem(g_aNomList, i--);
			if(!--g_iNomMaps[id]) {
				break;
			}
		}
	}
}
find_similar_map(map_index, string[MAPNAME_LENGTH])
{
	new map_info[MapStruct], end = ArraySize(g_aMapsList);
	for(new i = map_index; i < end; i++) {
		ArrayGetArray(g_aMapsList, i, map_info);
		if(containi(map_info[MapName], string) != -1) {
			return i;
		}
	}
	return INVALID_MAP_INDEX;
}
