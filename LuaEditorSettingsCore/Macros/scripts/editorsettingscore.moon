﻿F=far.Flags
K=far.Colors
ffi=require"ffi"
ffi.cdef[[int lstrcmpW(const wchar_t* lpString1,const wchar_t* lpString2);]]
ec=ffi.cast("struct PluginStartupInfo*",far.CPluginStartupInfo!).EditorControl
egs=ffi.new "struct EditorGetString"
egs.StructSize=ffi.sizeof egs
ess=ffi.new "struct EditorSetString"
ess.StructSize=ffi.sizeof ess
editors={}
colorguid=win.Uuid "F018DA49-6EB9-49C3-84D8-0F5E7BA20EFB"
abguid="9860393A-918D-450F-A3EA-84186F21B0A2"
configguid='A0C8F0AA-7180-4E4E-A496-339E7A6D27C7'
farguid=string.rep('\0',16)
modeline=require"modeline"
IsMms=(str)->return str[0]==45 and str[1]==45 and str[2]==32 and str[3]==0
IsSpace=(char)->return char==32 or char==9
KillSpaces1=(id,lineno,mms=false,spaces=true,eol)->
  egs.StringNumber=lineno-1
  if (ec id,"ECTL_GETSTRING",0,egs)~=0
    raw=->ffi.cast "const wchar_t*",eol
    ess.StringNumber=egs.StringNumber
    ess.StringLength=egs.StringLength
    ess.StringText=egs.StringText
    ess.StringEOL,neweol=if eol and egs.StringEOL[0]~=0 and do
        eol=win.Utf8ToUtf16 eol..'\0'
        0~=ffi.C.lstrcmpW raw!,egs.StringEOL
      raw!,true
    else
      egs.StringEOL,false
    if spaces and (not mms or not IsMms ess.StringText)
      while ess.StringLength>0
        if not IsSpace ess.StringText[ess.StringLength-1] then break
        ess.StringLength-=1
    if ess.StringLength~=egs.StringLength or neweol then ec id,"ECTL_SETSTRING",0,ess

KillSpaces=(id,mms,spaces,eol)->
  total=(editor.GetInfo id).TotalLines
  for ii=1,total
    KillSpaces1 id,ii,mms,spaces,eol

KillEmptyLines=(id)->
  info=editor.GetInfo id
  total=info.TotalLines
  getlen=(row)->editor.GetString(id,row,1).StringLength
  if 0==getlen total then while total>1
    if 0==getlen total-1
      editor.DeleteString id
      total-=1
    else
      break
  editor.SetPosition id,info

SmartHome=->
  info=editor.GetInfo!
  pp1,pp2=info.CurPos,editor.GetString(-1,0,3)\find('%S') or 1
  editor.SetPosition -1,0,(pp1==1 or pp1>pp2) and pp2 or 1
  if 0==bit64.band info.Options,F.EOPT_PERSISTENTBLOCKS then editor.Select -1,'BTYPE_NONE'
  editor.Redraw!

FindIndent=(lineno,pos,lines,compare,brk)->
  for _=1,lines
    lineno-=1
    line=editor.GetString -1,lineno,3
    if line and line\len!>0
      pos2=line\find('%S') or line\len!+1
      if compare(pos,pos2) then return pos2,line\sub 1,pos2-1
      if brk then break
  nil

SmartTabBs=(lines,tab)->
  info=editor.GetInfo!
  ll,pp=info.CurLine,info.CurPos
  line,eol=editor.GetString -1,0,3
  if (line\sub 1,pp-1)\match "^%s*$"
    pp2,newprefix=FindIndent ll,pp,lines,(if tab then (x,y)->x<y else (x,y)->x>y),tab
    if newprefix
      suffix=line\sub pp
      editor.SetString -1,0,newprefix..suffix,eol
      editor.SetPosition -1,0,pp2
      editor.Redraw!
      return true
  false

dump=(o)->
  if type(o)=='table'
    s='{ '
    for k,v in pairs(o)
      if type(k)~='number' then k='"'..k..'"'
      s=s..'['..k..'] = '..dump(v)..','
    s .. '} '
  else
    tostring(o)

Tokens={'Keywords','Numbers','Operators'}

Schemes=require"editorsettings"

FixSchemes=(Sch)->
  default=far.AdvControl F.ACTL_GETCOLOR,K.COL_EDITORTEXT
  color=(fg,bg)->
    flag=(c,f)->c and (c<0x10 and f or 0) or bit64.bor default.Flags,f
    cnorm=(c,d)->c and (bit64.bor c,0xff000000) or d
    flags=bit64.bor (flag fg,F.FCF_FG_4BIT),(flag bg,F.FCF_BG_4BIT)
    (fg or bg) and {Flags:flags,ForegroundColor:(cnorm fg,default.ForegroundColor),BackgroundColor:(cnorm bg,default.BackgroundColor)}
  invert=(c)->
    if c
      fix=(v1,v2)->(v1==bit64.band c.Flags,v1) and v2 or 0
      {ForegroundColor:c.BackgroundColor,BackgroundColor:c.ForegroundColor,Flags:bit64.bor (bit64.band c.Flags,bit64.bnot 3),(fix 1,2),(fix 2,1)}
  decodeK=(c)->color if 'table'==type c then c[1],c[2] else c
  decodeR=(c)->
    if 'table'==type c
      if c[2] then c[3] or=c[1] else c[2],c[3]=c[1],c[1]
      for ii=1,3 do c[ii]=decodeK c[ii]
    else
      c=color c
      c={c,c,c}
    c
  fix=(region)->
    regions=rawget region,'Regions'
    if regions
      for r in *regions
        fix r
    for name in *Tokens
      token=region[name]
      if token
        token.ColorFull or=decodeK token.Color
        for ii=1,#token
          token[ii]={token[ii]} if 'string'==type token[ii]
          token[ii].ColorFull or=(decodeK token[ii].Color) or token.ColorFull
    with region
      .ColorFull or=decodeR .Color
      .Pair=true if .Left and .Right and 'nil'==type .Pair
  for s in *Sch
    s.First={s.First} if 'string'==type s.First
    if 'table'==type s.Highlite
      fix with s.Highlite
        if not .Pairs then .Pairs={}
        .Pairs.ColorFull or=decodeK .Pairs.Color
        .Pairs.ColorErrorFull or=invert .Pairs.ColorFull
        .Case=true if 'nil'==type .Case
        .Simple=true
      with s.Highlite
        if .Regions
          for r in *.Regions
            if r.Right or r.Regions or r.Pair
              .Simple=false
              break

FixSchemes Schemes

Highlite=(id,tt,top)->
  if tt.o.Highlite
    simple=('table'~=type tt.o.Highlite) or tt.o.Highlite.Simple
    tocache=(v)->1+math.floor (v-1)/50
    fromcache=(v)->(v-1)*50+1
    clone=(t)->{k,('table'==type v) and (clone v) or v for k,v in pairs t}
    insert,remove=table.insert,table.remove
    ei=editor.GetInfo id
    start,finish=(if simple then ei.TopScreenLine else math.min ei.TopScreenLine,tt.startline,top),math.min ei.TopScreenLine+ei.WindowSizeY,ei.TotalLines
    if not simple
      start=tocache start
      if start>#tt.cache
        start=#tt.cache
      else if start<#tt.cache
        for ii=start+1,#tt.cache
          tt.cache[ii]=nil
    left,right=ei.LeftPos,ei.LeftPos+ei.WindowSizeX
    margins=top:ei.TopScreenLine,bottom:math.min ei.TopScreenLine+ei.WindowSizeY,ei.TotalLines+1
    addcolor=(line,s,e,c,p=0)->
      if c and line>=margins.top and line<margins.bottom and not (s>=margins[line].right or e<margins[line].left)
        editor.AddColor id,line,s,e,F.ECF_AUTODELETE,c,p,colorguid
    state,state_data,pairs=if simple then {0},{},{} else (clone tt.cache[start].state),(clone tt.cache[start].data),(clone tt.cache[start].pairs)
    {CurPos:curpos,CurLine:curline}=editor.GetInfo id
    checkCursor=(line,pos,len)->(line==curline) and curpos>=pos and curpos<(pos+len)
    getRegion=->
      r=tt.o.Highlite
      if 'table'==type r
        for s in *state
          if 0==s then break
          r=r.Regions[s]
      r
    region,regionstart=getRegion!,1
    updateRegion=(s,line=false,pos=1,len)->
      add=(c,p=0)->addcolor line,pos,pos+len-1,c,p
      curpair=line and len and checkCursor line,pos,len
      if line
        addcolor line,regionstart,pos-1,region.ColorFull[2]
        if s==0 and len
          add region.ColorFull[3]
          if region.Pair
            pair=remove pairs
            if curpair or (pair and pair.cur)
              addcolor pair.line,pair.pos1,pair.pos2,tt.o.Highlite.Pairs.ColorFull,100 if pair and curpair
              add tt.o.Highlite.Pairs.ColorFull,100
          pos+=len
      if 0==state[#state]
        if 0==s
          if #state>1
            remove state
            state[#state]=0
        else
          state[#state]=s
      else
        if 0==s
          state[#state]=s
        else
          insert state,s
      region=getRegion!
      regionstart=pos
      if s>0 and len
        pos1,pos2=pos,pos+len-1
        add region.ColorFull[1]
        if region.Pair
          insert pairs,{:line,:pos1,:pos2,cur:curpair}
          if curpair
            add tt.o.Highlite.Pairs.ColorFull,100
        regionstart+=len
    match=(str,patt,init)->
      switch type patt
        when 'string'
          str\match '^'..patt,init.U
        when 'userdata'
          res=patt\match str,init.B
          if res then string.sub str,init.B,res-1 else false
        when 'function'
          res,next=patt state_data,str,init
          if next then match str,res,init else res
    start=fromcache start if not simple
    for ii=start,finish
      regionstart=1
      tt.cache[tocache ii]=state:(clone state),data:(clone state_data),pairs:(clone pairs) if not simple and ii%50==1
      {StringText:line,StringLength:len}=editor.GetString id,ii,0
      margins[ii]=:left,:right
      if 0==bit64.band ei.Options,F.EOPT_EXPANDALLTABS
        with margins[ii]=left:0,right:len+1
          pos,symb=0,0
          tab=ei.TabSize
          for fix,chars,tabs in line\gmatch"()[^\t]*()[\t]*()"
            tabs-=chars
            chars-=fix
            pos+=chars
            symb+=chars
            if .left==0 and pos>=left
              .left=symb-pos+left
            if right>symb and pos>=right
              .right=symb-pos+right
              break
            if tabs>0
              pos+=tab-pos%tab+tab*(tabs-1)
              symb+=tabs
              if .left==0 and pos>=left
                .left=symb-math.floor (pos-left)/tab
              if right>symb and pos>=right
                .right=symb-math.floor (pos-right)/tab
                break
          if 0==.left then .right=0
      switch type tt.o.Highlite
        when 'table'
          line=line\lower! if not tt.o.Highlite.Case
          posU,posB=1,1
          match2=(patt)->match line,patt,{B:posB,U:posU}
          while posU<=len
            stepU,stepB=1,string.len (line\match '.',posU) or ''
            updStep=(word)->stepU,stepB=word\len!,string.len word
            match3=(patt)->
              m=match2 patt
              if m
                updStep m
                true
            matchR=(patt,s)->
              if match3 patt
                updateRegion s,ii,posU,stepU
                true
            skip=false
            if region.Regions
              for kk=1,#region.Regions
                if not (region.Regions[kk].Start and posU>1)
                  if matchR region.Regions[kk].Left,kk
                    skip=true
                    break
            if not skip and region.Right
              if matchR region.Right,0
                skip=true
            for name in *Tokens
              break if skip
              token=region[name]
              if token
                word=token.Word and match2 token.Word
                if word
                  updStep word
                  skip=true
                for keyword in *token
                  if not (keyword.Start and posU>1)
                    if if word and not keyword.Skip then (word==match word,keyword[1],{B:1,U:1}) else match3 keyword[1]
                      add=(c,p)->addcolor ii,posU,posU+stepU-1,c,p
                      addcolor ii,regionstart,posU-1,region.ColorFull[2]
                      add keyword.ColorFull
                      regionstart=posU+stepU
                      skip=true
                      if keyword.Open or keyword.Close
                        curpair=checkCursor ii,posU,stepU
                        if keyword.Open
                          insert pairs,{line:ii,pos1:posU,pos2:posU+stepU-1,cur:curpair,type:keyword.Open}
                          if curpair
                            add tt.o.Highlite.Pairs.ColorFull,100
                        else
                          pair=remove pairs
                          if curpair or (pair and pair.cur)
                            addcolor pair.line,pair.pos1,pair.pos2,pair.type==keyword.Close and tt.o.Highlite.Pairs.ColorFull or tt.o.Highlite.Pairs.ColorErrorFull,100 if pair and curpair
                            add (pair and pair.cur and pair.type~=keyword.Close) and tt.o.Highlite.Pairs.ColorErrorFull or tt.o.Highlite.Pairs.ColorFull,100
                      break
            posU+=stepU
            posB+=stepB
          if not region.Right or match2 region.Right then updateRegion 0,ii,len+1
          else addcolor ii,regionstart,len,region.ColorFull[2]
        when 'function'
          tt.o.Highlite line,(s,e,color,p=0)->addcolor ii,s,e,color,p
    tt.startline=fromcache #tt.cache

InitType=(obj)->{o:obj,cache:{{state:{0},data:{},pairs:{}}},startline:1}

GetType1=(FileName,FirstLine)->
  for scheme in *Schemes
    tt=type scheme.Type
    cmp=(mask,fn)->far.ProcessName F.PN_CMPNAMELIST,mask,fn,F.PN_SKIPPATH
    if (tt=='string' and cmp scheme.Type,FileName) or (tt=='function' and scheme.Type cmp,FileName)
      return scheme
    if 'table'==type scheme.First
      for first in *scheme.First
        if FirstLine\match first
          return scheme
  nil

GetType=(id,FileName)->
  tt=editors[id]
  if not tt
    tt=InitType GetType1 FileName,editor.GetString id,1,3
    editors[id]=tt
  tt

ApplyType=(id,tt,startup,fn)->
  params={
    {F.ESPT_TABSIZE         ,"TabSize"}
    {F.ESPT_EXPANDTABS      ,"ExpandTabs"}
    {F.ESPT_AUTOINDENT      ,"AutoIndent"}
    {F.ESPT_CURSORBEYONDEOL ,"CursorBeyondEol"}
    {F.ESPT_CHARCODEBASE    ,"CharCodeBase"}
    {F.ESPT_CODEPAGE        ,"CodePage",true}
    {F.ESPT_SAVEFILEPOSITION,"SaveFilePosition"}
    {F.ESPT_LOCKMODE        ,"LockMode"}
    {F.ESPT_SETWORDDIV      ,"WordDiv"}
    {F.ESPT_SHOWWHITESPACE  ,"ShowWhiteSpace"}
    {F.ESPT_SETBOM          ,"SetBOM",true}
  }
  for param in *params do if type(tt.o[param[2]])~='nil' and (not param[3] or (startup and not mf.fexist fn)) then editor.SetParam id,param[1],tt.o[param[2]]

ApplyModeline=(id,ml)->
  params={
    {F.ESPT_TABSIZE       ,'tabstop','ts',tonumber}
    {F.ESPT_EXPANDTABS    ,'expandtab','et',(v)->v}
    {F.ESPT_AUTOINDENT    ,'autoindent','ai',(v)->v}
    {F.ESPT_SHOWWHITESPACE,'list','list',(v)->v and 2 or 0}
  }
  syntaxes={
    asm:'405026D5-E610-4C87-94E7-AD1EC5F7FBFA'
    awk:'40F55654-B2B0-4289-93B3-C84A16FEBB73'
    c:'208B30EE-E89E-4050-BADF-299B80D02FFE'
    cpp:'208B30EE-E89E-4050-BADF-299B80D02FFE'
    html:'E408256A-42AC-47EA-82F3-C7208AEBCECD'
    lex:'93730FF0-7E4B-4BA9-882E-A8F0F65F7243'
    lua:'00B5C3B7-C768-4EA6-9D0B-30843B29C1D9'
    moon:'88DFA357-4B2A-4401-A12C-493202247396'
    pascal:'CC22AA95-EED1-473E-AAB7-AA6535A8CF23'
    php:'142DE201-733C-48AB-AF9C-F413445D7FE4'
    python:'D9FAF60C-08AA-4D59-A5AB-EA67B886D99B'
    rust:'28421DC4-BF41-46B6-B021-65125455F3F9'
    sql:'50B1CA20-8758-442F-A51E-4CD3DB8D04CA'
    xml:'2AEA7052-CF0D-47EB-981B-00CD220F0D66'
    yacc:'93730FF0-7E4B-4BA9-882E-A8F0F65F7243'
  }
  isset=(v)->nil~=v
  for {p,l,s,def} in *params
    l,s=ml[l],ml[s]
    editor.SetParam id,p,def (isset l) and l or s if (isset l) or isset s
  syntax=ml.filetype or ml.ft
  if syntax and syntaxes[syntax]
    Plugin.SyncCall(abguid,0,id,syntaxes[syntax])

ReadSettings=->
  with far.CreateSettings!
    sk=\CreateSubkey F.FSSF_ROOT,configguid,'Editor Settings'
    hl,ml=((\Get sk,'highlite',F.FST_QWORD) or 0),((\Get sk,'maxlines',F.FST_QWORD) or 0)
    \Free!
    return hl,ml
WriteSettings=(hl,ml)->
  with far.CreateSettings!
    sk=\CreateSubkey F.FSSF_ROOT,configguid,'Editor Settings'
    \Set sk,'highlite',F.FST_QWORD,hl
    \Set sk,'maxlines',F.FST_QWORD,ml
    \Free!
highlite,maxlines=ReadSettings!

redraw=0
Event
  group:"EditorEvent"
  action:(id,Event)->
    if Event==F.EE_CLOSE
      editors[id]=nil
    elseif Event==F.EE_SAVE or Event==F.EE_READ or Event==F.EE_REDRAW
      fn=editor.GetFileName id
      tt=GetType id,fn
      if tt
        if Event==F.EE_SAVE
          if tt.o.KillSpaces or tt.o.Eol then KillSpaces id,tt.o.MinusMinusSpace,tt.o.KillSpaces,tt.o.Eol
          if tt.o.KillEmptyLines then KillEmptyLines id
        elseif Event==F.EE_READ
          ml=modeline id
          if ml then ApplyModeline id,ml else ApplyType id,tt,true,fn
        elseif Event==F.EE_REDRAW and redraw==0
          redraw+=1
          ab,guid,top=Plugin.SyncCall(abguid,2,id)
          guid,top={farguid},math.huge if not ab
          if 1==highlite or (2==highlite and (editor.GetInfo id).TotalLines<=maxlines)
            Highlite id,tt,top if guid[1]==farguid
          if tt.o.WhiteSpaceColor
            ei=editor.GetInfo id
            if 0~=bit64.band ei.Options,F.EOPT_SHOWWHITESPACE
              start,finish=ei.TopScreenLine,math.min ei.TopScreenLine+ei.WindowSizeY,ei.TotalLines
              for ii=start,finish
                line,pos=editor.GetString(id,ii),1
                while true
                  jj,kk=line.StringText\cfind("([%s]+)",pos)
                  if not jj then break
                  editor.AddColor id,ii,jj,kk,F.ECF_AUTODELETE,tt.o.WhiteSpaceColor,100,colorguid
                  pos=kk+1
                if 0~=bit64.band ei.Options,F.EOPT_SHOWLINEBREAK then editor.AddColor id,ii,line.StringLength+1,line.StringLength+line.StringEOL\len!,F.ECF_AUTODELETE,tt.o.WhiteSpaceColor,100,colorguid
          redraw-=1


KeyData={
  {
    Key:0x23 --VK_END
    Shift:0x13 --shift|lalt|ralt
    Option:"KillSpaces"
    Action:(_,mms)->
      KillSpaces1 -1,0,mms
      false
  }
  {
    Key:0x24 --VK_HOME
    Shift:0
    Option:"SmartHome"
    Action:->
      SmartHome!
      true
  }
  {
    Key:9 --VK_TAB
    Shift:0
    Option:"SmartTab"
    Action:(lines)->SmartTabBs lines,true
  }
  {
    Key:8 --VK_BACK
    Shift:0
    Option:"SmartBs"
    Action:(lines)->SmartTabBs lines
  }
}

Event
  group:"EditorInput"
  action:(rec)->
    if rec.EventType==F.KEY_EVENT and rec.KeyDown
      cc=bit.band(rec.ControlKeyState,0x1f)
      for key in *KeyData
        if (cc==0 or (bit.band(cc,key.Shift)~=0 and bit.band(cc,bit.bnot(key.Shift))==0)) and rec.VirtualKeyCode==key.Key
          tt=GetType editor.GetInfo!.EditorID,editor.GetFileName!
          if tt and tt.o[key.Option] then return key.Action tt.o.Lines or 10,tt.o.MinusMinusSpace
    false

Editor=->
  id=editor.GetInfo!.EditorID
  tt=editors[id]
  if tt
    check=(c)->c.__name==tt.o.__name
    hotkeys="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    gethotkey=->(if hotkeys\len!>0 then "&"..(hotkeys\sub 1,1)..". " else "   "),do hotkeys=hotkeys\sub 2
    result=far.Menu{Id:win.Uuid"34BB1EE6-E7E1-44F4-A8DC-D51CF1B85E4C"},[{text:gethotkey!..scheme.Title,checked:check(scheme),selected:check(scheme),value:InitType scheme} for scheme in *Schemes]
    if result
      editors[id]=result.value
      ApplyType id,result.value
      editor.Redraw id

Config=->
  KCheck,KLabel,KEdit=2,3,4
  highlite,maxlines=ReadSettings!
  items={
    {'DI_DOUBLEBOX', 3,1,36,4,0,       0,0,0,           'Editor Settings'}
    {'DI_CHECKBOX',  5,2, 0,0,highlite,0,0,F.DIF_3STATE,'&highlite'}
    {'DI_TEXT',      5,3, 0,0,0,       0,0,0,           '&max lines:'}
    {'DI_EDIT',     16,3,34,0,0,       0,0,0,           tostring maxlines}
  }
  DlgProc=(dlg,msg,param1,param2)->
    update=(state)->for item in *{KLabel,KEdit} do dlg\send F.DM_ENABLE,item,(state==2 and 1 or 0)
    switch msg
      when F.DN_INITDIALOG
        update dlg\send F.DM_GETCHECK,KCheck
      when F.DN_BTNCLICK
        if param1==KCheck
          update param2
          true
    nil
  dialog=far.DialogInit (win.Uuid'2E2C46E6-9248-4AB2-BFA7-7A8B0FECDD64'),-1,-1,40,6,nil,items,0,DlgProc
  if 0<far.DialogRun dialog then WriteSettings (dialog\send F.DM_GETCHECK,KCheck),(tonumber dialog\send F.DM_GETTEXT,KEdit)
  far.DialogFree dialog
  highlite,maxlines=ReadSettings!

MenuItem
  menu:'Plugins Config'
  area:'Editor'
  guid:'4DDEE94D-F1B4-440E-982F-26AAA826CEE9'
  text:'Editor Settings'
  action:(OpenFrom)->
    switch OpenFrom
      when F.OPEN_EDITOR
        Editor!
      when nil
        Config!
