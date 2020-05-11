local AddOnName = ...

local GT = LibStub('AceAddon-3.0'):GetAddon(AddOnName)

local L = LibStub("AceLocale-3.0"):GetLocale(AddOnName, true)

local Whisper = GT:NewModule('Whisper')
GT.Whisper = Whisper

Whisper.characters = {}

local TRIGGER_CHAR = '!'
local PREFIX = 'GT'
local SKILLS_PER_PAGE = 5

function Whisper:OnWhisperReceived(_, message, _, _, _, sender)
	GT.Log:Info('Whisper_OnWhisperReceived', sender, message)

	local firstChar = string.sub(message, 1, 1)
	if firstChar ~= TRIGGER_CHAR then
		GT.Log:Info('Whisper_OnWhisperReceived_NoTrigger', sender, message)
		return
	end

	local modMessage = string.sub(message, 2, #message)
	local tokens = GT.Text:Tokenize(modMessage, ' ')
	local professionSearch, tokens = GT.Table:RemoveToken(tokens)
	local searchTerm = table.concat(tokens, ' ')
	if searchTerm == '' then
		searchTerm = nil
	end

	if string.lower(professionSearch) == L['WHISPER_HELP_ME'] then
		Whisper:Help(sender)
		return
	end

	local characterName = UnitName('player')
	local character = GT.DB:GetCharacter(characterName)

	local professions = character.professions
	local finalProfession = nil
	local professionNames = {}
	for professionName, _ in pairs(professions) do
		table.insert(professionNames, professionName)
		if string.lower(professionName) == string.lower(professionSearch) then
			GT.Log:Info('Whisper_OnWhisperReceived_ProfFound', event, sender, message, professionName)
			finalProfession = professionName
			break
		end
	end

	if finalProfession == nil then
		local returnMessage = string.gsub(L['WHISPER_PROFESSION_NOT_FOUND'], '%{{profession_name}}', professionSearch)
		if #professionNames <= 0 then
			table.insert(professionNames, 'none')
		end
		returnMessage = string.gsub(returnMessage, '%{{profession_names}}', table.concat(professionNames, ', '))
		GT.Log:Info('Whisper_OnWhisperReceived_ProfNotFound', sender, message, returnMessage)
		ChatThrottleLib:SendChatMessage('ALERT', PREFIX, returnMessage, 'WHISPER', 'Common', sender)
		return
	end

	Whisper:SendResponse(sender, finalProfession, searchTerm)
end

function Whisper:SendResponse(recipient, professionName, searchTerm)
	GT.Log:Info('Whisper_SendResponse', recipient, professionName, searchTerm)

	if tonumber(searchTerm) == nil then
		Whisper:SendInitialResponse(recipient, professionName, searchTerm)
	else
		Whisper:SendPagedResponse(recipient, professionName, searchTerm)
	end
end

function Whisper:SendInitialResponse(recipient, professionName, searchTerm)
	GT.Log:Info('Whisper_SendInitialResponse', recipient, professionName, searchTerm)
	if Whisper.characters[recipient] == nil then
		Whisper.characters[recipient] = {}
	end
	local character = Whisper.characters[recipient]
	character[professionName] = {}
	character[professionName].searchTerm = searchTerm

	local returnSkills = Whisper:_SearchSkills(professionName, searchTerm)
	Whisper:_SendResponse(recipient, professionName, returnSkills, 1)
end

function Whisper:SendPagedResponse(recipient, professionName, page)
	GT.Log:Info('Whisper_SendPagedResponse', recipient, professionName, page)

	if Whisper.characters[recipient] == nil then
		Whisper:SendInitialResponse(recipient, professionName, nil)
		return
	end

	local whisperCharacter = Whisper.characters[recipient]
	if whisperCharacter[professionName] == nil then
		Whisper:SendInitialResponse(recipient, professionName, nil)
		return
	end
	local whisperProfession = whisperCharacter[professionName]
	local searchTerm = whisperProfession.searchTerm

	local returnSkills = Whisper:_SearchSkills(professionName, searchTerm)
	Whisper:_SendResponse(recipient, professionName, returnSkills, page)
end

function Whisper:_SendResponse(recipient, professionName, skills, page)
	page = tonumber(page)
	skillCount = 0
	for k, v in pairs(skills) do
		skillCount = skillCount + 1
	end
	GT.Log:Info('Whisper_SendResponse', recipient, professionName, page, skills)
	local totalPages = math.ceil(skillCount / SKILLS_PER_PAGE)
	local firstIndex = (page - 1) * SKILLS_PER_PAGE
	local lastIndex = firstIndex + SKILLS_PER_PAGE

	if lastIndex > skillCount then
		GT.Log:Info('Whisper_SendResponse_PageNotFull', recipient, professionName, page, skillCount, skills)
		lastIndex = skillCount
	end

	if firstIndex > skillCount then
		local msg = string.gsub(L['WHISPER_INVALID_PAGE'], '%{{page}}', tostring(page))
		msg = string.gsub(msg, '%{{max_pages}}', totalPages)
		GT.Log:Info('Whisper_SendResponse_InvalidPage', recipient, professionName, msg)
		ChatThrottleLib:SendChatMessage('ALERT', PREFIX, msg, 'WHISPER', 'Common', recipient)
		return
	end

	if totalPages > 1 then
		local msg = string.gsub(L['WHISPER_HEADER'], '%{{current_page}}', page)
		msg = string.gsub(msg, '%{{total_pages}}', tostring(totalPages))
		msg = string.gsub(msg, '%{{total_skills}}', tostring(skillCount))
		GT.Log:Info('Whisper_SendResponse_Header', recipient, professionName, searchTerm, msg)
		ChatThrottleLib:SendChatMessage('ALERT', PREFIX, msg, 'WHISPER', 'Common', recipient)
	end

	local count = firstIndex
	local i = 0
	local sortedKeys = GT.Table:GetSortedKeys(skills, function(a, b) return a < b end, true)
	for _, key in ipairs(sortedKeys) do
		if i + 1 > firstIndex and i < lastIndex then
			local skillLink = skills[key]
			msg = string.gsub(L['WHISPER_ITEM'], '%{{number}}', tostring(count + 1))
			msg = string.gsub(msg, '%{{skill_link}}', skillLink)
			GT.Log:Info('Whisper_SendResponse_Item', recipient, professionName, searchTerm, msg)
			ChatThrottleLib:SendChatMessage('ALERT', PREFIX, msg, 'WHISPER', 'Common', recipient)
			count = count + 1
		end
		i = i + 1
	end

	if totalPages > 1 then
		if page < totalPages then
			msg = string.gsub(L['WHISPER_FOOTER'], '%{{profession_name}}', professionName)
			msg = string.gsub(msg, '%{{next_page}}', tostring(page + 1))
			GT.Log:Info('Whisper_SendResponse_Footer', recipient, professionName, searchTerm, msg)
			ChatThrottleLib:SendChatMessage('ALERT', PREFIX, msg, 'WHISPER', 'Common', recipient)
		else
			msg = string.gsub(L['WHISPER_FOOTER_LAST_PAGE'], '%{{profession_name}}', professionName)
			GT.Log:Info('Whisper_SendResponse_FooterLastPage', recipient, professionName, searchTerm, msg)
			ChatThrottleLib:SendChatMessage('ALERT', PREFIX, msg, 'WHISPER', 'Common', recipient)
		end
	end
end

function Whisper:_SearchSkills(professionName, searchTerm)
	GT.Log:Info('Whisper__SearchSkills', professionName, searchTerm)
	local characterName = UnitName('player')
	local skills = GT.DB:GetProfession(characterName, professionName)
	
	if skills == nil then
		GT.logging.error('GT_Whisper_SendInitialResponse_NilSkills', recipient, professionName)
		return {}
	end
	skills = skills.skills
	GT.Log:Info(skills)

	local returnSkills = {}
	for _, skillName in pairs(skills) do
		local addSkill = true
		if searchTerm ~= nil and not string.find(string.lower(skillName), string.lower(searchTerm)) then
			addSkill = false
		end
		if addSkill then
			local skillLink = GT.DB:GetSkill(characterName, professionName, skillName).skillLink
			local tempSkillName = GT.Text:GetTextBetween(skillLink, '%[', ']')
			returnSkills[tempSkillName] = skillLink
		end
	end
	return returnSkills
end