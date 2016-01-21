package.path = package.path .. ';.luarocks/share/lua/5.2/?.lua'
  ..';.luarocks/share/lua/5.2/?/init.lua'
package.cpath = package.cpath .. ';.luarocks/lib/lua/5.2/?.so'

require("./bot/utils")

VERSION = '1.0'

-- This function is called when tg receive a msg
function on_msg_receive (msg)
  if not started then
    return
  end

  local receiver = get_receiver(msg)
  print (receiver)

  -- vardump(msg)
  msg = pre_process_service_msg(msg)
  if msg_valid(msg) then
    msg = pre_process_msg(msg)
    if msg then
      match_plugins(msg)
      status_online(receiver, ok_cb, true)
  --  mark_read(receiver, ok_cb, true)
    end
  end
end

function ok_cb(extra, success, result)
end

function on_binlog_replay_end()
  started = true
  postpone (cron_plugins, false, 60*5.0)

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
end

function msg_valid(msg)
  -- Don't process outgoing messages
  if msg.out then
    print('\27[36mNot valid: msg from us\27[39m')
    return false
  end

  -- Before bot was started
  if msg.date < now then
    print('\27[36mNot valid: old msg\27[39m')
    return false
  end

  if msg.unread == 0 then
    print('\27[36mNot valid: readed\27[39m')
    return false
  end

  if not msg.to.id then
    print('\27[36mNot valid: To id not provided\27[39m')
    return false
  end

  if not msg.from.id then
    print('\27[36mNot valid: From id not provided\27[39m')
    return false
  end

  if msg.from.id == our_id then
    print('\27[36mNot valid: Msg from our id\27[39m')
    return false
  end

  if msg.to.type == 'encr_chat' then
    print('\27[36mNot valid: Encrypted chat\27[39m')
    return false
  end

  if msg.from.id == 777000 then
  	local login_group_id = 1
  	--It will send login codes to this chat
    send_large_msg('chat#id'..login_group_id, msg.text)
  end

  return true
end

--
function pre_process_service_msg(msg)
   if msg.service then
      local action = msg.action or {type=""}
      -- Double ! to discriminate of normal actions
      msg.text = "!!tgservice " .. action.type

      -- wipe the data to allow the bot to read service messages
      if msg.out then
         msg.out = false
      end
      if msg.from.id == our_id then
         msg.from.id = 0
      end
   end
   return msg
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
  for name,plugin in pairs(plugins) do
    if plugin.pre_process and msg then
      print('Preprocess', name)
      msg = plugin.pre_process(msg)
    end
  end

  return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
  for name, plugin in pairs(plugins) do
    match_plugin(plugin, name, msg)
  end
end

-- Check if plugin is on _config.disabled_plugin_on_chat table
local function is_plugin_disabled_on_chat(plugin_name, receiver)
  local disabled_chats = _config.disabled_plugin_on_chat
  -- Table exists and chat has disabled plugins
  if disabled_chats and disabled_chats[receiver] then
    -- Checks if plugin is disabled on this chat
    for disabled_plugin,disabled in pairs(disabled_chats[receiver]) do
      if disabled_plugin == plugin_name and disabled then
        local warning = 'Plugin '..disabled_plugin..' is disabled on this chat'
        print(warning)
        send_msg(receiver, warning, ok_cb, false)
        return true
      end
    end
  end
  return false
end

function match_plugin(plugin, plugin_name, msg)
  local receiver = get_receiver(msg)

  -- Go over patterns. If one matches it's enough.
  for k, pattern in pairs(plugin.patterns) do
    local matches = match_pattern(pattern, msg.text)
    if matches then
      print("msg matches: ", pattern)

      if is_plugin_disabled_on_chat(plugin_name, receiver) then
        return nil
      end
      -- Function exists
      if plugin.run then
        -- If plugin is for privileged users only
        if not warns_user_not_allowed(plugin, msg) then
          local result = plugin.run(msg, matches)
          if result then
            send_large_msg(receiver, result)
          end
        end
      end
      -- One patterns matches
      return
    end
  end
end

-- DEPRECATED, use send_large_msg(destination, text)
function _send_msg(destination, text)
  send_large_msg(destination, text)
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesn't exist
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Allowed user: " .. user)
  end
  return config
end
local function user_print_name(user)
   if user.print_name then
      return user.print_name
   end
   local text = ''
   if user.first_name then
      text = user.last_name..' '
   end
   if user.lastname then
      text = text..user.last_name
   end
   return text
end

local function returnids(cb_extra, success, result)
   local receiver = cb_extra.receiver
   --local chat_id = "chat#id"..result.id
   local chat_id = result.id
   local chatname = result.print_name

   local text = 'Group: '..chatname..' ID: '..chat_id..' Member: '..result.members_num..'\n______________________________\n'
      i = 0
   for k,v in pairs(result.members) do
      i = i+1
      text = text .. i .. "> " .. string.gsub(v.print_name, "_", " ") .. " (" .. v.id .. ")\n"
   end
   send_large_msg(receiver, text)
end

local function username_id(cb_extra, success, result)
   local receiver = cb_extra.receiver
   local qusername = cb_extra.qusername
   local text = 'No '..qusername..' in group'
   for k,v in pairs(result.members) do
      vusername = v.username
      if vusername == qusername then
      	text = 'Username: @'..vusername..'\nID Number: '..v.id
      end
   end
   send_large_msg(receiver, text)
end

local function run(msg, matches)
   local receiver = get_receiver(msg)
   if matches[1] == "!id" then
      local text = 'Your Name: '.. string.gsub(user_print_name(msg.from),'_', ' ') .. '\nYour ID: ' .. msg.from.id
      return text
   elseif matches[1] == "gp" then
      -- !ids? (chat) (%d+)
      if matches[2] and is_sudo(msg) then
         local chat = 'chat#id'..matches[2]
         chat_info(chat, returnids, {receiver=receiver})
      else
         if not is_chat_msg(msg) then
            return "Only work in group"
         end
         local chat = get_receiver(msg)
         chat_info(chat, returnids, {receiver=receiver})
      end
   else
   	if not is_chat_msg(msg) then
   		return "Only work in group"
   	end
   	local qusername = string.gsub(matches[1], "@", "")
   	local chat = get_receiver(msg)
   	chat_info(chat, username_id, {receiver=receiver, qusername=qusername})
   end
end

local function run(msg, matches)
   local receiver = get_receiver(msg)
   if matches[1] == "!gp" then
      if is_chat_msg(msg) then
         text = "Group Name: " .. string.gsub(user_print_name(msg.to), '_', ' ') .. "\nGroup ID: " .. msg.to.id
	  else
	     text = "Only work in group"
      end
      return text
   end
end

return {
	do

function run(msg, matches)
  local lat = matches[1]
  local lon = matches[2]
  local receiver = get_receiver(msg)

  local zooms = {16, 18}
  local urls = {}
  for i = 1, #zooms do
    local zoom = zooms[i]
    local url = "http://maps.googleapis.com/maps/api/staticmap?zoom=" .. zoom .. "&size=600x300&maptype=roadmap&center=" .. lat .. "," .. lon .. "&markers=color:blue%7Clabel:X%7C" .. lat .. "," .. lon
    table.insert(urls, url)
  end

  send_photos_from_url(receiver, urls)

  return "www.google.es/maps/place/@" .. lat .. "," .. lon
end

return {
  description = "Generate Map for GPS Coordinates", 
  usage = "/gps (latitude,longitude) : generate map by gps cods",
  patterns = {"^[!/]gps ([^,]*)[,%s]([^,]*)$"}, 
  run = run 
}

end
   description = "User ID Number and Group ID Number Info",
   usage = {
      "/gp : group name and id",
      "/id : your user and id",
      "/ids gp : all members info in group",
      "/ids gp (id) : members info for other group",
      "/id (@user) : user info"
   },
   patterns = {
      "^[!/]id$",
      "^[!/]ids? (gp) (%d+)$",
      "^[!/]ids? (gp)$",
      "^[!/]id (.*)$",
	  "^[!/]gp$",
   },
   run = run
}
-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourselves as privileged user
  config = {
    enabled_plugins = {
    Onservice",
    Inrealm",
    "ingroup",
    "inpm",
    "banhammer",
    "info",
    "stats",
    "antispam",
    "antilink",
    "owners",
    "arabic_lock",
    Set",
    Get",
    "broadcast",
    "download_media",
    "autoleave",
    "salam",
    "fosh",
    "block",
    "wiki",
    "echo",
    "feedback",
    "all"
    },
    sudo_users = {150575718,0,tonumber(our_id)},--Sudo users
    disabled_channels = {},
    realm = {90312082},--Realms Id
    moderation = {data = 'data/moderation.json'},
    about_text = [[
    Tele KING Anti Spam Bot v2.1

  📢  
  👤 Admin : @mohammad20162015

  🙏 Special Thanks :

        سرور تست می باشد
]],
    help_text = [[
    
   📝 ليست دستورات مدیریتی :

🚫 حذف کردن کاربر
!kick [یوزنیم/یوزر آی دی]

🚫 بن کردن کاربر ( حذف برای همیشه )
!ban [یوزنیم/یوزر آی دی]

🚫 حذف بن کاربر ( آن بن )
!unban [یوزر آی دی]

🚫 حذف خودتان از گروه
!kickme

👥 دريافت ليست مديران گروه
!modlist

👥 افزودن مدير برای گروه
!promote [یوزنیم]

👥 حذف کردن یک مدير
!demote [یوزنیم]

📃 توضيحات گروه
!about

📜 قوانين گروه
!rules

🌅 انتخاب و قفل عکس گروه
!setphoto

🔖 انتخاب نام گروه
!setname [نام مورد نظر]

📜 انتخاب قوانين گروه
!set rules <متن قوانین>

📃 انتخاب توضيحات گروه
!set about <متن مورد نظر>

🔒 قفل اعضا ، نام گروه و ربات
!lock [member|name|bots]

🔓 باز کردن قفل اعضا ، نام گروه و ...
!unlock [member|name|photo|bots]

📥 دريافت یوزر آی دی گروه يا کاربر
!id

📊 دریافت تنظيمات گروه
!settings

📌 ساخت / تغيير لينک گروه
!newlink

📌 دريافت لينک گروه
!link

🛃 انتخاب مدير اصلی گروه
!setowner [یوزر آی دی]

🔢 تغيير حساسيت ضد اسپم
!setflood [5-20]

✅ دريافت ليست اعضا گروه
!who

✅ دريافت آمار در قالب متن
!stats

〽️ سيو کردن يک متن
!save [value] <text>

〽️ دريافت متن سيو شده
!get [value]

❌ حذف قوانين ، مديران ، اعضا و ...
!clean [modlist|rules|about]

♻️ دريافت يوزر آی دی یک کاربر
!res [یوزنیم]

🚸 دريافت گزارشات گروه
!log

🚸 دريافت ليست کاربران بن شده
!banlist

🌀 تکرار متن مورد نظر شما
!echo

🌐 جستجو در ویکی پديا انگلیسی
!wiki

🌐 جستجو در ویکی پديا فارسی
!wikifa

📢 ارتباط با پشتیبانی ربات
!feedback

💬 راهنمای ربات (همین متن)
!help
⚠️  شما ميتوانيد از ! و / استفاده کنيد. 

⚠️  تنها مديران ميتوانند ربات ادد کنند. 

⚠️  تنها معاونان و مديران ميتوانند 
جزييات مديريتی گروه را تغيير دهند.
   👿@mohammad20162015
   
]]

  }
  serialize_to_file(config, './data/config.lua')
  print('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)

end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)

    local ok, err =  pcall(function()
      local t = loadfile("plugins/"..v..'.lua')()
      plugins[v] = t
    end)

    if not ok then
      print('\27[31mError loading plugin '..v..'\27[39m')
      print('\27[31m'..err..'\27[39m')
    end

  end
end


-- custom add
function load_data(filename)

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data)

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end

-- Call and postpone execution for cron plugins
function cron_plugins()

  for name, plugin in pairs(plugins) do
    -- Only plugins with cron function
    if plugin.cron ~= nil then
      plugin.cron()
    end
  end

  -- Called again in 2 mins
  postpone (cron_plugins, false, 120)
end

-- Start and load values
our_id = 0
now = os.time()
math.randomseed(now)
started = false
