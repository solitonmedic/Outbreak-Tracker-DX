-- Purpose: shared health, death and short ad-lib presentation effects.
-- Runtime/location: sources/PlayerEffects.lua; LÖVE/Decky Lua drawing backend.
-- Inputs: existing player state and UI elapsed seconds; outputs drawing/colors.
-- Safety: no memory, file, recording or game writes. Reusable UI helpers only.
-- Run: player cards and maps call these helpers; check maps/check-presentation.lua.
local E={}
E.slotColors={{1,0,0},{115/255,178/255,249/255},{242/255,247/255,61/255},{101/255,218/255,80/255}}
function E.timers(p)
    return (p.antivirustime or 0)>0 or (p.antivirusgtime or 0)>0 or (p.herbtime or 0)>0 or (p.bleedtime or 0)>0
end
function E.badgeY(p,master)
    if E.timers(p) then return master and 6 or 25 end
    return master and 61 or 77
end
function E.health(p)
    if not p then return "normal" end
    local status=type(p.status)=="string" and p.status or ""
    if status=="Dead" or status=="Zombie" then return "dead" end
    if status:find("Down",1,true) or ((p.maxHP or 0)>0 and (p.HP or 0)<=0) then return "down" end
    if (p.maxHP or 0)>0 and (p.HP or 0)/p.maxHP<.25 then return "danger" end
    return "normal"
end
function E.pulse(time) return .5+.5*math.sin((time or 0)*math.pi*3) end
function E.background(p,x,y,w,h,time)
    local state=E.health(p)
    if state~="danger" and state~="down" then return end
    local g=love.graphics;local pulse=E.pulse(time)
    g.setColor(1,0,0,state=="down" and pulse or (.12+.25*pulse))
    g.rectangle("fill",x,y,w,h)
    for n=1,3 do
        g.setColor(1,.02,.02,(.05+.15*pulse)/n)
        g.setLineWidth(n*2);g.rectangle("line",x+n,y+n,w-2*n,h-2*n)
    end
    g.setLineWidth(1);g.setColor(1,1,1,1)
end
function E.adlib(p,time)
    return p and ((p.adlib==true) or (type(p.adlibUntil)=="number" and p.adlibUntil>(time or 0)))
end
function E.markerColor(p,base,time)
    if E.adlib(p,time) then return {0,1,.15,1} end
    return base
end
return E
