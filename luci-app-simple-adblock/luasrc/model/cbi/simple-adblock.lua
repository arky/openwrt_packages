-- Copyright 2016-2018 Stan Grishin <stangri@melmac.net>
-- Licensed to the public under the Apache License 2.0.

local packageName = "simple-adblock"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local sys = require "luci.sys"
local enabledFlag = uci:get(packageName, "config", "enabled")
local command

m = Map("simple-adblock", translate("Simple AdBlock Settings"))
m.apply_on_parse = true
m.on_after_apply = function(self)
 	sys.call("/etc/init.d/simple-adblock restart")
end

h = m:section(NamedSection, "config", "simple-adblock", translate("Service Status"))

local status 
local error
local ubusStatus = util.ubus("service", "list", { name = packageName })
if ubusStatus and ubusStatus[packageName] and ubusStatus[packageName]["instances"] and ubusStatus[packageName]["instances"]["status"] and ubusStatus[packageName]["instances"]["status"]["data"] then
	if ubusStatus[packageName]["instances"]["status"]["data"]["status"] then
		status = ubusStatus[packageName]["instances"]["status"]["data"]["status"]
	else
		status = "Stopped"
	end
	if ubusStatus[packageName]["instances"]["status"]["data"]["message"] and ubusStatus[packageName]["instances"]["status"]["data"]["message"] ~= "" then
		status = status .. ": " .. ubusStatus[packageName]["instances"]["status"]["data"]["message"]
	end
	if ubusStatus[packageName]["instances"]["status"]["data"]["error"] and ubusStatus[packageName]["instances"]["status"]["data"]["error"] ~= "" then
		error = ubusStatus[packageName]["instances"]["status"]["data"]["error"]
	end
else
	status = "Stopped"
end
if status:match("ing") then
	ds = h:option(DummyValue, "_dummy", translate("Service Status"))
	ds.template = "simple-adblock/status"
	ds.value = status
else
	en = h:option(Button, "__toggle")
	if enabledFlag ~= "1" or status:match("Stopped") then
		en.title      = translate("Service is disabled/stopped")
		en.inputtitle = translate("Enable/Start")
		en.inputstyle = "apply important"
		if nixio.fs.access("/var/run/simple-adblock.cache") then
			ds = h:option(DummyValue, "_dummy", translate("Service Status"))
			ds.template = "simple-adblock/status"
			ds.value = "Cache file containing " .. luci.util.trim(luci.sys.exec("wc -l < /var/run/simple-adblock.cache")) .. " domains found."
		end
	else
		en.title      = translate("Service is enabled/started")
		en.inputtitle = translate("Stop/Disable")
		en.inputstyle = "reset important"
		ds = h:option(DummyValue, "_dummy", translate("Service Status"))
		ds.template = "simple-adblock/status"
		ds.value = status
		if status:match("Fail") or error then
			if error then
				es = h:option(DummyValue, "_dummy", translate("Collected Errors"))
				es.template = "simple-adblock/status"
				es.value = error
			end
			reload = h:option(Button, "__reload")
			reload.title      = translate("Service started with error")
			reload.inputtitle = translate("Reload")
			reload.inputstyle = "apply important"
			function reload.write()
				luci.sys.exec("/etc/init.d/simple-adblock reload")
				luci.http.redirect(luci.dispatcher.build_url("admin/services/" .. packageName))
			end
		end
	end
	function en.write()
		if status:match("Stopped") then
			enabledFlag = "1"
		else
			enabledFlag = enabledFlag == "1" and "0" or "1"
		end
		uci:set(packageName, "config", "enabled", enabledFlag)
		uci:save(packageName)
		uci:commit(packageName)
		if enabledFlag == "0" then
			luci.sys.init.stop(packageName)
--			luci.sys.exec("/etc/init.d/simple-adblock killcache")
		else
			luci.sys.init.enable(packageName)
			luci.sys.init.start(packageName)
		end
		luci.http.redirect(luci.dispatcher.build_url("admin/services/" .. packageName))
	end
end

s = m:section(NamedSection, "config", "simple-adblock", translate("Configuration"))
-- General options
s:tab("basic", translate("Basic Configuration"))

o2 = s:taboption("basic", ListValue, "verbosity", translate("Output Verbosity Setting"),translate("Controls system log and console output verbosity"))
o2:value("0", translate("Suppress output"))
o2:value("1", translate("Some output"))
o2:value("2", translate("Verbose output"))
o2.rmempty = false
o2.default = 2

o3 = s:taboption("basic", ListValue, "force_dns", translate("Force Router DNS"), translate("Forces Router DNS use on local devices, also known as DNS Hijacking"))
o3:value("0", translate("Let local devices use their own DNS servers if set"))
o3:value("1", translate("Force Router DNS server to all local devices"))
o3.rmempty = false
o3.default = 1

local sysfs_path = "/sys/class/leds/"
local leds = {}
if nixio.fs.access(sysfs_path) then
	leds = nixio.util.consume((nixio.fs.dir(sysfs_path)))
end
if #leds ~= 0 then
	o4 = s:taboption("basic", Value, "led", translate("LED to indicate status"), translate("Pick the LED not already used in")
		.. [[ <a href="]] .. luci.dispatcher.build_url("admin/system/leds") .. [[">]]
		.. translate("System LED Configuration") .. [[</a>]])
	o4.rmempty = false
	o4:value("", translate("none"))
	for k, v in ipairs(leds) do
		o4:value(v)
	end
end

s:tab("advanced", translate("Advanced Configuration"))

o6 = s:taboption("advanced", Value, "boot_delay", translate("Delay (in seconds) for on-boot start"), translate("Run service after set delay on boot"))
o6.default = 120
o6.datatype = "range(1,600)"

o7 = s:taboption("advanced", Value, "download_timeout", translate("Download time-out (in seconds)"), translate("Stop the download if it is stalled for set number of seconds"))
o7.default = 10
o7.datatype = "range(1,60)"

o5 = s:taboption("advanced", ListValue, "parallel_downloads", translate("Simultaneous processing"), translate("Launch all lists downloads and processing simultaneously, reducing service start time"))
o5:value("0", translate("Do not use simultaneous processing"))
o5:value("1", translate("Use simultaneous processing"))
o5.rmempty = false
o5.default = 1

o9 = s:taboption("advanced", ListValue, "allow_non_ascii", translate("Allow Non-ASCII characters in DNSMASQ file"), translate("Only enable if your version of DNSMASQ supports the use of Non-ASCII characters, otherwise DNSMASQ will fail to start."))
o9:value("0", translate("Do not allow Non-ASCII"))
o9:value("1", translate("Allow Non-ASCII"))
o9.rmempty = false
o9.default = "0"

o10 = s:taboption("advanced", ListValue, "compressed_cache", translate("Store compressed cache file on router"), translate("Attempt to create a compressed cache of final block-list on the router."))
o10:value("0", translate("Do not store compressed cache"))
o10:value("1", translate("Store compressed cache"))
o10.rmempty = false
o10.default = "0"

o8 = s:taboption("advanced", ListValue, "debug", translate("Enable Debugging"), translate("Enables debug output to /tmp/simple-adblock.log"))
o8:value("0", translate("Disable Debugging"))
o8:value("1", translate("Enable Debugging"))
o8.rmempty = false
o8.default = "0"


s2 = m:section(NamedSection, "config", "simple-adblock", translate("Whitelist and Blocklist Management"))
-- Whitelisted Domains
d1 = s2:option(DynamicList, "whitelist_domain", translate("Whitelisted Domains"), translate("Individual domains to be whitelisted"))
d1.addremove = false
d1.optional = false

-- Blacklisted Domains
d3 = s2:option(DynamicList, "blacklist_domain", translate("Blacklisted Domains"), translate("Individual domains to be blacklisted"))
d3.addremove = false
d3.optional = false

-- Whitelisted Domains URLs
d2 = s2:option(DynamicList, "whitelist_domains_url", translate("Whitelisted Domain URLs"), translate("URLs to lists of domains to be whitelisted"))
d2.addremove = false
d2.optional = false

-- Blacklisted Domains URLs
d4 = s2:option(DynamicList, "blacklist_domains_url", translate("Blacklisted Domain URLs"), translate("URLs to lists of domains to be blacklisted"))
d4.addremove = false
d4.optional = false

-- Blacklisted Hosts URLs
d5 = s2:option(DynamicList, "blacklist_hosts_url", translate("Blacklisted Hosts URLs"), translate("URLs to lists of hosts to be blacklisted"))
d5.addremove = false
d5.optional = false

return m
