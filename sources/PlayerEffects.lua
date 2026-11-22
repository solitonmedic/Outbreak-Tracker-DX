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
-- The more urgent of two health states for flashing: down, then danger, else nil.
function E.worst(a,b)
    if a=="down" or b=="down" then return "down" end
    if a=="danger" or b=="danger" then return "danger" end
end
function E.pulse(time) return .5+.5*math.sin((time or 0)*math.pi*3) end
-- Danger breathes slowly; Down flashes faster. Hz.
E.rates={danger=1,down=2.4}
-- Smooth raised-cosine wave from 0 to 1.
function E.wave(time,rate) return .5-.5*math.cos(2*math.pi*rate*(time or 0)) end
-- Set a pulsing colour whose alpha moves between floor*a and a. On the Decky
-- bridge the browser animates the alpha at display rate (setPulse); desktop
-- LÖVE computes it every frame. Call E.endPulse() after the pulsing shapes.
function E.pulseColor(state,time,r,g,b,a,floor)
    local gr=love.graphics;local rate=E.rates[state] or E.rates.danger
    if gr.setPulse then gr.setPulse(rate,floor);gr.setColor(r,g,b,a)
    else gr.setColor(r,g,b,a*(floor+(1-floor)*E.wave(time,rate))) end
end
function E.endPulse() if love.graphics.setPulse then love.graphics.setPulse() end end
function E.background(p,x,y,w,h,time)
    local state=E.health(p)
    if state~="danger" and state~="down" then return end
    local g=love.graphics
    E.pulseColor(state,time,1,0,0,state=="down" and .8 or .36,state=="down" and .05 or .3)
    g.rectangle("fill",x,y,w,h)
    for n=1,3 do
        E.pulseColor(state,time,1,.02,.02,.22/n,.2)
        g.setLineWidth(n*2);g.rectangle("line",x+n,y+n,w-2*n,h-2*n)
    end
    E.endPulse()
    g.setLineWidth(1);g.setColor(1,1,1,1)
end
-- Timer: Elimination shows its countdown (game.eliminationtime, 30 ticks per
-- second, JP File 2 0x491230) instead of the game clock. Under 3:00 (5400
-- ticks; the game keeps a second counter exactly 3:00 behind, 0x491234) the
-- countdown is red with a pulsing red glow. Returns text and the warning flag.
E.lastMinutes=5400
function E.clockText(game)
    local left=tonumber(game and game.eliminationtime) or 0
    -- In Elimination the countdown stays shown once the game clock runs, so
    -- time running out reads 00:00:00.0 with the warning (run of 2026-11-21).
    local running=(tonumber(game and game.frames) or 0)>0
    if (left>0 or running) and tostring(game and game.scenario or ""):find("^elimination") then
        return Time2string(left/.03),left<=E.lastMinutes
    end
    return Time2string(((game and game.frames) or 0)/.03),false
end
-- draw(dx,dy) prints the timer text offset by dx,dy with the current colour.
function E.drawClock(draw,warning,time)
    local g=love.graphics
    if warning then
        for _,o in ipairs{{-2,0},{2,0},{0,-2},{0,2},{-1,-1},{1,1},{-1,1},{1,-1}} do
            E.pulseColor("danger",time,1,0,0,.55,.15);draw(o[1],o[2])
        end
        E.endPulse()
        g.setColor(1,.3,.25,1)
    else
        g.setColor(1,1,1,1)
    end
    draw(0,0)
    g.setColor(1,1,1,1)
end
-- Voice IDs feed the game's map pulse. Rising duration also catches repeats.
-- Baseline the first snapshot; never announce a stale line on opening the UI.
local voices={};local runKey,frames
function E.update(game,players,time)
    local key=tostring(game.currentFile)..":"..tostring(game.release)..":"..tostring(game.scenario)
    local clock=tonumber(game.frames) or 0
    if key~=runKey or game.scenario=="" or (frames and clock+60<frames) then voices={};runKey=key end
    frames=clock
    for i=1,4 do
        local p=players[i]
        if p and p.enabled then
            local id=tonumber(p.voiceId) or 0;local ticks=tonumber(p.voiceTicks) or 0
            local old=voices[i]
            local untilTime=old and old.untilTime or 0
            if old and clock>0 and id>0 and (id~=old.id or (ticks>0 and ticks>old.ticks)) then untilTime=time+3 end
            voices[i]={id=id,ticks=ticks,untilTime=untilTime};p.adlibUntil=untilTime
        else voices[i]=nil end
    end
end
function E.adlib(p,time)
    return p and ((p.adlib==true) or (type(p.adlibUntil)=="number" and p.adlibUntil>(time or 0)))
end
function E.markerColor(p,base,time)
    if E.adlib(p,time) then return {0,1,.15,1} end
    return base
end
return E
