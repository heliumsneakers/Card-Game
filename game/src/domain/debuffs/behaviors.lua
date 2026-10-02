local Behaviors = {}

-- Consume one stack and skip this enemy action; other debuffs still receive their hook.
function Behaviors.skipAction(definition, stacks, actions)
	local remaining = stacks - 1
	actions.setStacks(remaining)
	-- Feedback uses metadata so a second action-skipping debuff needs no new code.
	if actions.notice then
		local suffix = remaining > 0 and ("  •  " .. remaining .. " LEFT") or ""
		actions.notice(actions.name .. " " .. definition.actionText .. suffix)
	end
	return true
end

-- Deal Burn’s base damage; the registry applies any card-authored bonus separately.
function Behaviors.burn(definition, stacks, actions)
	-- Keep the base tick independent from duration and optional bonus damage.
	actions.damage(1)
	actions.setStacks(stacks - 1)
	return false
end

return Behaviors
