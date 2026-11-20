-- Purpose: reusable Japanese map parser, read-only ISO/AFS import and local cache.
-- Runtime/location: sources/MapData.lua; LuaJIT/bit (desktop LÖVE or Decky).
-- Inputs: selected extracted disc folder, NETBIO00.DAT or ISO; cache read/write callbacks.
-- Outputs: validated map tables; cached map bytes and transparent PNG fill/wall masks.
-- Safety: opens discs read-only; no PINE, recordings, workbook or game writes.
-- Run: drag a disc folder/ISO onto the desktop, or use the phone's Import maps form.
-- Check from repo root: luajit tools-n-shit/tracker-tests/maps/check-runtime-maps.lua .
local bit = require "bit"
local M = {}
M.scenarios = {
    [1] = {{"001", "outbreak"}, {"002", "below freezing point"}, {"028", "the hive"},
           {"035", "hellfire"}, {"041", "decisions,decisions"}},
    [2] = {{"006", "end of the road"}, {"010", "underbelly"}, {"015", "desperate times"},
           {"026", "flashback"}, {"040", "wild things"}}
}
local function u16(s, o)
    local a,b = s:byte(o+1,o+2); assert(b, "Truncated map data")
    return a+b*256
end
local function u32(s, o) return u16(s,o)+u16(s,o+2)*65536 end
local function i16(s,o) local v=u16(s,o); return v>=32768 and v-65536 or v end
local function name(s,o)
    local chars={}
    for n=o+1,o+32 do
        local c=s:byte(n)
        if c==0 or c==255 then break end
        c=255-c
        if c<32 or c>126 then return "" end
        chars[#chars+1]=string.char(c)
    end
    return table.concat(chars)
end
function M.parse(s)
    assert(#s>=32 and #s<=2*1024*1024, "Invalid map size")
    local nr,nf,ft,tex=u32(s,4),u32(s,12),u32(s,16),u32(s,28)
    assert(u32(s,0)==#s and u32(s,8)==32 and nr>0 and nr<=256 and nf>0 and nf<=256,
           "Invalid map header")
    assert(32+nr*88<=ft and ft+nf*92<=tex and tex<#s and (#s-tex)%512==0, "Invalid map tables")
    local map={rooms={},floors={},texture=s:sub(tex+1),width=1024,height=(#s-tex)*2/1024}
    for n=0,nr-1 do
        local o=32+n*88
        local page,id,u,v=s:byte(o+1,o+4)
        local r={id=id,x=page%4*256+u,y=math.floor(page/4)*256+v,w=u16(s,o+4),h=u16(s,o+6),name=name(s,o+40)}
        assert(r.x+r.w<=1024 and r.y+r.h<=map.height, "Map crop outside texture")
        map.rooms[n+1]=r
    end
    for n=0,nf-1 do
        local o=ft+n*92
        local count=s:byte(o+67)
        local po=u32(s,o+68)
        assert(po>=ft+nf*92 and po+count*6<=tex, "Invalid map placements")
        local f={name=name(s,o+32),height=i16(s,o+76),ppu=i16(s,o+72),refX=i16(s,o+74),refZ=i16(s,o+78),
                 places={},minX=math.huge,minY=math.huge,maxX=-math.huge,maxY=-math.huge}
        if f.name=="" then f.name="Area "..(n+1) end
        assert(f.ppu>0 and f.ppu<=1000, "Invalid map scale")
        for k=0,count-1 do
            local p=po+k*6
            local rec=s:byte(p+1)+1
            local r=assert(map.rooms[rec], "Missing room record")
            local place={record=rec,x=i16(s,p+2),y=i16(s,p+4)}
            f.places[#f.places+1]=place
            f.minX=math.min(f.minX,place.x); f.minY=math.min(f.minY,place.y)
            f.maxX=math.max(f.maxX,place.x+r.w); f.maxY=math.max(f.maxY,place.y+r.h)
        end
        if count==0 then f.minX,f.minY,f.maxX,f.maxY=0,0,1,1 end
        map.floors[#map.floors+1]=f
    end
    return map
end
function M.position(f,x,z) return (x-f.refX)*f.ppu/100,(z-f.refZ)*f.ppu/100 end

local crcTable={}
for i=0,255 do
    local c=i
    for _=1,8 do c=bit.bxor(bit.rshift(c,1),bit.band(c,1)==1 and 0xEDB88320 or 0) end
    crcTable[i]=c
end
local function crc(s)
    local c=-1
    for i=1,#s do c=bit.bxor(bit.rshift(c,8),crcTable[bit.band(bit.bxor(c,s:byte(i)),255)]) end
    return bit.bnot(c)
end
local function be32(n)
    return string.char(bit.band(bit.rshift(n,24),255),bit.band(bit.rshift(n,16),255),bit.band(bit.rshift(n,8),255),bit.band(n,255))
end
function M.id(s) return bit.tohex(crc(s)) end
-- Indexed PNGs use a transparent background and a white mask. Stored DEFLATE
-- blocks keep the importer dependency-free, including on Windows.
function M.png(map,index)
    local rows={}
    for y=0,map.height-1 do
        local row={"\0"}
        for x=0,1023 do
            local p=y*1024+x
            local v=map.texture:byte(math.floor(p/2)+1)
            v=p%2==0 and v%16 or math.floor(v/16)
            row[#row+1]=v==index and "\1" or "\0"
        end
        rows[#rows+1]=table.concat(row)
    end
    local raw=table.concat(rows)
    local blocks={"\120\1"}; local a,b=1,0
    for i=1,#raw do a=(a+raw:byte(i))%65521; b=(b+a)%65521 end
    for start=1,#raw,65535 do
        local piece=raw:sub(start,start+65534); local len=#piece; local inverse=65535-len
        blocks[#blocks+1]=string.char(start+len>#raw and 1 or 0,len%256,math.floor(len/256),inverse%256,math.floor(inverse/256))..piece
    end
    blocks[#blocks+1]=be32(b*65536+a)
    local function chunk(t,data) return be32(#data)..t..data..be32(crc(t..data)) end
    return "\137PNG\13\10\26\10"..chunk("IHDR",be32(1024)..be32(map.height).."\8\3\0\0\0")..
           chunk("PLTE","\0\0\0\255\255\255")..chunk("tRNS","\0\255")..
           chunk("IDAT",table.concat(blocks))..chunk("IEND","")
end

local function window(file,base,size)
    return function(o,n)
        assert(o>=0 and n>=0 and o+n<=size, "Disc read outside file")
        assert(file:seek("set",base+o))
        local s=file:read(n)
        assert(s and #s==n,"Truncated disc file")
        return s
    end
end
local function afs(read,member)
    local h=read(0,8)
    assert(h:sub(1,4)=="AFS\0", "Not an AFS archive")
    local count=u32(h,4)
    assert(count>0 and count<=20000,"Invalid AFS directory")
    local tableBytes=read(8,count*8+8)
    local no,ns=u32(tableBytes,count*8),u32(tableBytes,count*8+4)
    assert(ns>=count*48 and ns<=20000*48,"Missing AFS names")
    local names=read(no,count*48)
    for i=0,count-1 do
        if names:sub(i*48+1,i*48+32):match("^[^%z]*")==member then
            local off,size=u32(tableBytes,i*8),u32(tableBytes,i*8+4)
            assert(size<0x80000000,"Unsupported AFS member")
            return function(o,n) assert(o+n<=size,"AFS read outside member"); return read(off+o,n) end,size
        end
    end
    error("Disc member missing: "..member)
end
local function isoEntry(read,dir,wanted)
    local data=read(dir.offset,dir.size); local o=0
    while o<#data do
        local len=data:byte(o+1)
        if len==0 then o=(math.floor(o/2048)+1)*2048
        else
            assert(len>=34 and o+len<=#data,"Invalid ISO directory")
            local n=data:sub(o+34,o+33+data:byte(o+33)):gsub(";[0-9]+$","")
            if n:upper()==wanted then
                assert(bit.band(data:byte(o+26),128)==0,"Multi-extent ISO files are unsupported")
                return {offset=u32(data,o+2)*2048,size=u32(data,o+10)}
            end
            o=o+len
        end
    end
end
function M.import(path,write)
    assert(type(path)=="string" and #path>0 and #path<=4096 and not path:find("%z"),"Select a disc folder or ISO")
    local isISO=path:lower():match("%.iso$")
    local folder=path:gsub("[\\/]NETBIO00%.[Dd][Aa][Tt]$",""):gsub("[\\/]$","")
    local file=assert(io.open(isISO and path or folder.."/NETBIO00.DAT","rb"),"Cannot open disc; select an extracted folder or ISO")
    local ok,result=pcall(function()
        local size=assert(file:seek("end")); local read=window(file,0,size); local game
        if isISO then
            local pvd=read(16*2048,2048)
            assert(pvd:sub(1,7)=="\1CD001\1","Expected an ISO9660 disc image")
            local root={offset=u32(pvd,158)*2048,size=u32(pvd,166)}
            if isoEntry(read,root,"SLPM_654.28") then game=1
            elseif isoEntry(read,root,"SLPM_656.92") then game=2 end
            local entry=assert(isoEntry(read,root,"NETBIO00.DAT"),"NETBIO00.DAT missing in ISO")
            read=window(file,entry.offset,entry.size)
        else
            for n,title in ipairs({"SLPM_654.28","SLPM_656.92"}) do
                local f=io.open(folder.."/"..title,"rb")
                if f then f:close(); game=n; break end
            end
        end
        assert(game,"Select a Japanese File 1 or File 2 disc")
        local maps={}
        for _,scenario in ipairs(M.scenarios[game]) do
            local code=scenario[1]
            local sub=afs(read,"r"..code..".afs")
            local member,len=afs(sub,(game==1 and "map" or "pit_s")..code..".dat")
            assert(len<=4*1024*1024,"Invalid map member size")
            local bytes=member(0,len)
            if game==2 then
                assert(bytes:sub(1,4)=="MOMO" and u32(bytes,4)==5,"Expected MOMO v5 map container")
                local off,count=u32(bytes,32),u32(bytes,36)
                assert(off>=64 and off+count<=#bytes,"Embedded map outside member")
                bytes=bytes:sub(off+1,off+count)
            end
            maps[#maps+1]={code=code,bytes=bytes,map=M.parse(bytes)}
        end
        -- The index is committed last. An interrupted/rejected import preserves
        -- the old usable cache; content-addressed art is never overwritten.
        local lines={}
        for _,entry in ipairs(maps) do
            local id=entry.code.."-"..M.id(entry.bytes)
            local prefix="maps/jp"..game.."/"..id
            write(prefix..".dat",entry.bytes)
            write(prefix.."-fill.png",M.png(entry.map,1))
            write(prefix.."-walls.png",M.png(entry.map,2))
            lines[#lines+1]=id
        end
        write("maps/jp"..game.."/index",table.concat(lines,"\n").."\n")
        return game
    end)
    file:close()
    if not ok then error(result,0) end
    return result
end
function M.load(game,scenario,read)
    local code
    for _,s in ipairs(M.scenarios[game] or {}) do if s[2]==scenario then code=s[1] end end
    if not code then return nil,"This scenario has no imported map" end
    local index=read("maps/jp"..game.."/index") or ""
    local id=index:match("("..code.."%-[0-9a-f]+)\n")
    if not id or #id~=12 then return nil,"Import maps from your Japanese disc" end
    local path="maps/jp"..game.."/"..id
    local bytes=assert(read(path..".dat"),"Cached map is missing; import the disc again")
    assert(M.id(bytes)==id:sub(5),"Cached map is damaged; import the disc again")
    local map=M.parse(bytes); map.path=path; map.id=id
    return map
end
return M
