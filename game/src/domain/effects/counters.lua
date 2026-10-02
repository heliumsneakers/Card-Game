local Counters = {}

-- Resolve authoring shorthand into a definition or individual-copy key.
function Counters.key(reference, context)
	--legacy behavior
	if reference.id == "$thisCard" then
		return context.cardId
	end
	if reference.id == "$thisInstance" then
		return "@instance:" .. tostring(assert(context.instanceId, "instance counter requires a card instance"))
	end

	--dynamic card type sorting.

	-- for now face, I'm only going to check for types. the namespace attribute I will leave for any
	-- future implementations using them.
	local namespace, type = reference.id:match("([^.]+)%.([^.]+)")
	if type ~= nil then
		return context.element
	end
	return reference.id
end

-- Choose a counter lifetime, retaining schema-v1 turn behavior by default.
function Counters.scope(reference)
	return reference.scope or "turn"
end

return Counters
