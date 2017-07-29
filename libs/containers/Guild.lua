local Cache = require('iterables/Cache')
local SecondaryCache = require('iterables/SecondaryCache')
local Role = require('containers/Role')
local Emoji = require('containers/Emoji')
local Invite = require('containers/Invite')
local Webhook = require('containers/Webhook')
local Member = require('containers/Member')
local Resolver = require('client/Resolver')
local GuildTextChannel = require('containers/GuildTextChannel')
local GuildVoiceChannel = require('containers/GuildVoiceChannel')
local Snowflake = require('containers/abstract/Snowflake')

local json = require('json')
local enums = require('enums')

local channelType = enums.channelType
local floor = math.floor
local format = string.format

local Guild = require('class')('Guild', Snowflake)
local get = Guild.__getters

function Guild:__init(data, parent)
	Snowflake.__init(self, data, parent)
	self._roles = Cache({}, Role, self)
	self._emojis = Cache({}, Emoji, self)
	self._members = Cache({}, Member, self)
	self._text_channels = Cache({}, GuildTextChannel, self)
	self._voice_channels = Cache({}, GuildVoiceChannel, self)
	if not data.unavailable then
		return self:_makeAvailable(data)
	end
end

function Guild:_makeAvailable(data)

	self._roles:_load(data.roles)
	self._emojis:_load(data.emojis)

	local voice_states = data.voice_states
	for i, state in ipairs(voice_states) do
		voice_states[state.user_id] = state
		voice_states[i] = nil
	end
	self._voice_states = voice_states

	local text_channels = self._text_channels
	local voice_channels = self._voice_channels
	for _, channel in ipairs(data.channels) do
		if channel.type == channelType.text then
			text_channels:_insert(channel)
		elseif channel.type == channelType.voice then
			voice_channels:_insert(channel)
		end
	end

	self._features = data.features -- raw table of strings

	return self:_loadMembers(data)

end

function Guild:_loadMembers(data)
	local members = self._members
	members:_load(data.members)
	for _, presence in ipairs(data.presences) do
		local member = members:get(presence.user.id)
		if member then -- rogue presence check
			member:_loadPresence(presence)
		end
	end
	if self._large and self.client._options.fetchMembers then
		return self:requestMembers()
	end
end

function Guild:_modify(payload)
	local data, err = self.client._api:modifyGuild(self._id, payload)
	if data then
		self:_load(data)
		return true
	else
		return false, err
	end
end

function Guild:requestMembers()
	local shard = self.client._shards[self.shardId]
	if shard._loading then
		shard._loading.chunks[self._id] = true
	end
	return shard:requestGuildMembers(self._id)
end

function Guild:sync()
	local shard = self.client._shards[self.shardId]
	if shard._loading then
		shard._loading.syncs[self._id] = true
	end
	return shard:syncGuilds({self._id})
end

function Guild:getMember(id)
	id = Resolver.userId(id)
	local member = self._members:get(id)
	if member then
		return member
	else
		local data, err = self.client._api:getGuildMember(self._id, id)
		if data then
			return self._members:_insert(data)
		else
			return nil, err
		end
	end
end

function Guild:getRole(id)
	id = Resolver.roleId(id)
	return self._roles:get(id)
end

function Guild:getChannel(id)
	id = Resolver.channelId(id)
	return self._text_channels:get(id) or self._voice_channels:get(id)
end

function Guild:createTextChannel(name)
	local data, err = self.client._api:createGuildChannel(self._id, {name = name, type = channelType.text})
	if data then
		return self._text_channels:_insert(data)
	else
		return nil, err
	end
end

function Guild:createVoiceChannel(name)
	local data, err = self.client._api:createGuildChannel(self._id, {name = name, type = channelType.voice})
	if data then
		return self._voice_channels:_insert(data)
	else
		return nil, err
	end
end

function Guild:createRole(name)
	local data, err = self.client._api:createGuildRole(self._id, {name = name})
	if data then
		return self._roles:_insert(data)
	else
		return nil, err
	end
end

function Guild:setName(name)
	return self:_modify({name = name or json.null})
end

function Guild:setRegion(region)
	return self:_modify({region = region or json.null})
end

function Guild:setVerificationLevel(verification_level)
	return self:_modify({verification_level = verification_level or json.null})
end

function Guild:setNotificationSetting(default_message_notifications)
	return self:_modify({default_message_notifications = default_message_notifications or json.null})
end

function Guild:setExplicitContentSetting(explicit_content_filter)
	return self:_modify({explicit_content_filter = explicit_content_filter or json.null})
end

function Guild:setAFKTimeout(afk_timeout)
	return self:_modify({afk_timeout = afk_timeout or json.null})
end

function Guild:setAFKChannel(afk_channel)
	afk_channel = afk_channel and Resolver.channelId(afk_channel)
	return self:_modify({afk_channel_id = afk_channel or json.null})
end

function Guild:setOwner(owner)
	owner = owner and Resolver.userId(owner)
	return self:_modify({owner_id = owner or json.null})
end

function Guild:setIcon(icon)
	icon = icon and Resolver.base64(icon)
	return self:_modify({icon = icon or json.null})
end

function Guild:setSplash(splash)
	splash = splash and Resolver.base64(splash)
	return self:_modify({splash = splash or json.null})
end

function Guild:getPruneCount(days)
	local data, err = self.client._api:getGuildPruneCount(self._id, days and {days = days} or nil)
	if data then
		return data.pruned
	else
		return nil, err
	end
end

function Guild:pruneMembers(days)
	local data, err = self.client._api:beginGuildPrune(self._id, nil, days and {days = days} or nil)
	if data then
		return data.pruned
	else
		return nil, err
	end
end

function Guild:getBans()
	local data, err = self.client._api:getGuildBans(self._id)
	if data then
		return SecondaryCache(data, self.client._users)
	else
		return nil, err
	end
end

function Guild:getInvites()
	local data, err = self.client._api:getGuildInvites(self._id)
	if data then
		return Cache(data, Invite, self.client)
	else
		return nil, err
	end
end

function Guild:getWebhooks()
	local data, err = self.client._api:getGuildWebhooks(self._id)
	if data then
		return Cache(data, Webhook, self.client)
	else
		return nil, err
	end
end

function Guild:listVoiceRegions()
	return self.client._api:getGuildVoiceRegions()
end

function Guild:leave()
	local data, err = self.client._api:leaveGuild(self._id)
	if data then
		return true
	else
		return false, err
	end
end

function Guild:delete()
	local data, err = self.client._api:deleteGuild(self._id)
	if data then
		return true
	else
		return false, err
	end
end

function Guild:kickUser(user, reason)
	user = Resolver.userId(user)
	local query = reason and {reason = reason}
	local data, err = self.client._api:removeGuildMember(self._id, user, query)
	if data then
		return true
	else
		return false, err
	end
end

function Guild:banUser(user, reason, days)
	local query = reason and {reason = reason}
	if days then
		query = query or {}
		query['delete-message-days'] = days
	end
	user = Resolver.userId(user)
	local data, err = self.client._api:createGuildBan(self._id, user, query)
	if data then
		return true
	else
		return false, err
	end
end

function Guild:unbanUser(user, reason)
	user = Resolver.userId(user)
	local query = reason and {reason = reason}
	local data, err = self.client._api:removeGuildBan(self._id, user, query)
	if data then
		return true
	else
		return false, err
	end
end

function get.shardId(self)
	return floor(self._id / 2^22) % self.client._shard_count
end

function get.name(self)
	return self._name
end

function get.icon(self)
	return self._icon
end

function get.iconURL(self)
	local icon = self._icon
	return icon and format('https://cdn.discordapp.com/icons/%s/%s.png', self._id, icon) or nil
end

function get.splash(self)
	return self._splash
end

function get.splashURL(self)
	local splash = self._splash
	return splash and format('https://cdn.discordapp.com/splashs/%s/%s.png', self._id, splash) or nil
end

function get.large(self)
	return self._large
end

function get.region(self)
	return self._region
end

function get.mfaLevel(self)
	return self._mfa_level
end

function get.joinedAt(self)
	return self._joined_at
end

function get.afkTimeout(self)
	return self._afk_timeout
end

function get.unavailable(self)
	return self._unavailable
end

function get.totalMemberCount(self)
	return self._member_count
end

function get.verificationLevel(self)
	return self._verification_level
end

function get.notificationSetting(self)
	return self._default_message_notifications
end

function get.explicitContentSetting(self)
	return self._explicit_content_filter or 0
end

function get.me(self)
	return self._members:get(self.client._user._id)
end

function get.owner(self)
	return self._members:get(self._owner_id)
end

function get.ownerId(self)
	return self._owner_id
end

function get.afkChannelId(self)
	return self._afk_channel_id
end

function get.afkChannel(self)
	return self._voice_channels:get(self._afk_channel_id)
end

function get.defaultRole(self)
	return self._roles:get(self._id)
end

function get.defaultChannel(self)
	return self._text_channels:get(self._id)
end

function get.roles(self)
	return self._roles
end

function get.emojis(self)
	return self._emojis
end

function get.members(self)
	return self._members
end

function get.textChannels(self)
	return self._text_channels
end

function get.voiceChannels(self)
	return self._voice_channels
end

return Guild
