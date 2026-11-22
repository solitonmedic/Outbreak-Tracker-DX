/* Purpose: bounded SP room-marker/count reader shared by desktop platforms.
   Runtime: C11/C++17 included by main.c; LuaJIT and existing memory connection.
   Inputs: detected release, supported profile/code guards and loaded room list.
   Outputs: Lua SP state (numeric IDs/positions; names come from MapCatalog.lua).
   Safety: reads only, <=128 linked records, <=32 SP records, no scans or strings.
   Run: tracker.getSPMapState(), sampled at most every .25s by main.lua.
   Check: tracker-tests/sp/check-sp-map-reader.sh (synthetic guard/list failures).
   Evidence: workbook F1/F2 SP datasets, SP code notes of 2026-10-26/27.
   The private Deck provider supplies its richer radar state instead when present. */
#include <stdint.h>
#include <math.h>

typedef struct {
    unsigned frames,state,slot,count,room,head,collected,player,stride,mask;
} SPMapProfile;
typedef struct { unsigned id; int enabled,collected; double x,y,height; } SPMapItem;
static int SPMapRead(unsigned a,void* out,unsigned n)
{
    memset(out,0,n);
    return a>0 && a<=0x2000000-n && ReadProcessMemory(ProcessHandle,(char*)BasePointer+a,out,n,NULL);
}
static unsigned SPMapU32(unsigned a) { unsigned v=0;SPMapRead(a,&v,4);return v; }
static unsigned SPMapU16(unsigned a) { unsigned short v=0;SPMapRead(a,&v,2);return v; }
static unsigned SPMapU8(unsigned a) { unsigned char v=0;SPMapRead(a,&v,1);return v; }
static int SPMapGuards(int profile)
{
    if (profile==2) return SPMapU32(0x59A880)==0x96840052 && SPMapU32(0x59A8A0)==0x30841FFF &&
        SPMapU32(0x58F9AC)==0x3C020049 && SPMapU32(0x58F9E0)==0xA0220109;
    if (profile==0) return SPMapU32(0x594068)==0x96840052 && SPMapU32(0x594118)==0x30A53FFF &&
        SPMapU32(0x58A77C)==0x2442BE02 && SPMapU32(0x58A7A8)==0xA022AEA9 && SPMapU32(0x6D6D14)==0x593FE0;
    if (!(SPMapU32(0x5C4688)==0x96840052 && SPMapU32(0x5C4738)==0x30A53FFF &&
        SPMapU32(0x5BACFC)==0x2442AC72 && SPMapU32(0x5BAD28)==0xA0229D19 &&
        SPMapU32(0x581034)==0x8C265160 && SPMapU32(0x581054)==0x8CC60028 && SPMapU32(0x70A6F4)==0x5C4600)) return 0;
    if (SPMapU32(0x367080)==0x2D4F4942) return 1;
    return SPMapU32(0x367080)==0 && SPMapU32(0x1F7160)==0x27BDFFE0 && SPMapU32(0x1F71F0)==0x27BDFFB0 &&
        SPMapU32(0x1FBC000)==0 && SPMapU32(0x1FD3820)==0;
}
static void SPMapNumber(lua_State* L,const char* k,double v) { lua_pushnumber(L,v);lua_setfield(L,-2,k); }
static void SPMapBool(lua_State* L,const char* k,int v) { lua_pushboolean(L,v);lua_setfield(L,-2,k); }
static int LGetSPMapState(lua_State* L)
{
    const SPMapProfile profiles[]={
        {0x48BF78,0x48BF60,0x48BF7D,0x48AEA9,0x3065AC,0x23BD90,0x48BE02,0x476DD0,0x10E0,0x3FFF},
        {0x4BADE8,0x4BADD0,0x4BADED,0x4B9D19,0x3243DC,0x3B5160,0x4BAC72,0x4A5C30,0x10E0,0x3FFF},
        {0x4912B8,0x4912A0,0x4912BD,0x490109,0x3137BC,0x24AF48,0x491166,0x47BD30,0x1100,0x1FFF}};
    SPMapItem items[32];unsigned visited[128],ids[8];unsigned used=0,num=0,prev=0;
    unsigned frame,slot,count,room,state,head,node,player;
    int profile=info.CurrentFile==2?2:(F1_Release==F1_RELEASE_US?1:0);
    const SPMapProfile* p=&profiles[profile];
    lua_newtable(L);SPMapBool(L,"available",0);SPMapNumber(L,"limit",8);
    if ((info.CurrentFile!=1 && info.CurrentFile!=2) || !SPMapGuards(profile)) return 1;
    frame=SPMapU32(p->frames);slot=SPMapU8(p->slot);count=SPMapU8(p->count);
    room=SPMapU16(p->room);state=SPMapU8(p->state);head=SPMapU32(p->head);node=head;
    if (!frame || slot>3 || count>8 || state<2 || state>4 || !head || !room) return 1;
    player=p->player+slot*p->stride;
    if (SPMapU8(player)!=1 || SPMapU8(player+1)!=1 || SPMapU16(player+0x1E2)!=room) return 1;
    for (unsigned i=0;i<count;i++) {
        ids[i]=SPMapU16(p->collected+2*i);if (ids[i]>259) return 1;
        for (unsigned j=0;j<i;j++) if (ids[j]==ids[i]) return 1;
    }
    while (node) {
        unsigned char b[84];unsigned next,previous;unsigned short tag;
        if (used>=128 || node%4 || node>0x2000000-196) return 1;
        for (unsigned i=0;i<used;i++) if (visited[i]==node) return 1;
        if (!SPMapRead(node,b,sizeof(b))) return 1;
        visited[used++]=node;memcpy(&previous,b+44,4);memcpy(&next,b+40,4);memcpy(&tag,b+82,2);
        if (previous!=prev) return 1;
        if (b[48]==5 && (tag&0x4000) && !(tag&~(0x4000|p->mask)) && (tag&p->mask)<=259) {
            double xmin=1e9,xmax=-1e9,ymin=1e9,ymax=-1e9,area=0;
            int32_t low,high;SPMapItem* it;
            if (num>=32 || b[60]>1) return 1;
            for (unsigned i=0;i<4;i++) {
                int32_t x,y,nx,ny;memcpy(&x,b+i*8,4);memcpy(&y,b+i*8+4,4);
                memcpy(&nx,b+((i+1)%4)*8,4);memcpy(&ny,b+((i+1)%4)*8+4,4);
                if (x<=-1000000 || x>=1000000 || y<=-1000000 || y>=1000000) return 1;
                if (x<xmin)xmin=x;if(x>xmax)xmax=x;if(y<ymin)ymin=y;if(y>ymax)ymax=y;
                area+=(double)x*ny-(double)nx*y;
            }
            if (fabs(area)<1 || fabs(area)>200000000) return 1;
            memcpy(&low,b+32,4);memcpy(&high,b+36,4);
            if (low>high || low<=-1000000 || low>=1000000 || high<=-1000000 || high>=1000000) return 1;
            it=&items[num++];it->id=tag&p->mask;it->enabled=b[60];it->collected=0;
            it->x=(xmin+xmax)/2;it->y=(ymin+ymax)/2;it->height=((double)low+high)/2;
            if (profile==2) {
                float x,y,h;memcpy(&x,b+0x44,4);memcpy(&h,b+0x48,4);memcpy(&y,b+0x4C,4);
                if (!isfinite(x)||!isfinite(y)||!isfinite(h)||fabs(x)>=1000000||fabs(y)>=1000000||fabs(h)>=1000000)return 1;
                it->x=x;it->y=y;it->height=h;
            }
            for (unsigned i=0;i<count;i++) if (ids[i]==it->id)it->collected=1;
        }
        prev=node;node=next;
    }
    /* Drop room/slot transitions rather than attaching old records to a new room. */
    if (SPMapU32(p->frames)<frame || SPMapU8(p->slot)!=slot || SPMapU8(p->count)!=count ||
        SPMapU16(p->room)!=room || SPMapU8(p->state)!=state || SPMapU32(p->head)!=head) return 1;
    SPMapBool(L,"available",1);SPMapNumber(L,"collected",count);SPMapNumber(L,"room",room);
    lua_newtable(L);
    for (unsigned i=0;i<count;i++) {lua_pushnumber(L,ids[i]);lua_rawseti(L,-2,i+1);}lua_setfield(L,-2,"collectedIds");
    lua_newtable(L);
    for (unsigned i=0;i<num;i++) {
        SPMapItem* it=&items[i];lua_newtable(L);SPMapNumber(L,"id",it->id);
        SPMapBool(L,"enabled",it->enabled);SPMapBool(L,"collected",it->collected);
        SPMapNumber(L,"x",it->x);SPMapNumber(L,"y",it->y);SPMapNumber(L,"height",it->height);
        lua_rawseti(L,-2,i+1);
    }
    lua_setfield(L,-2,"roomItems");return 1;
}
