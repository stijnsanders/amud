unit chatbot;

interface

uses SysUtils, jsonDoc;

{

ChatBot
=======
based on
  https://en.wikipedia.org/wiki/ELIZA
  http://www.chayden.net/eliza/Eliza.html

ChatBot script directives
-------------------------

initial: x
    not used
final: x
    not used
valid: x
    limit processing to these characters, default "abcdefghijklmnopqrstuvwxyz'" (case-insensitive
xvalid: x
    limit pricessing to these characters and swictch to case-sensitive
quit: x
    not used
pre: x y
    translate word x into y before processing
post: x y
    translate word x into y after processing
syn: x y*
    treat word(s) y as synonymous for x when using "@x" in patterns
default: p
    define 'default' patterns, used when no keywords match and no answers were stored, priority p
key: x p
    define patterns for keyword x, priority p
xkey: x p
    define patterns, keywords x is only available for goto answers, priority p
pat: x
    define pattern x (need preceding "key", "xkey" or "default")
store: x
    define pattern x, but store the answer for later (need preceding "key", "xkey" or "default")
a: x
    define answer (need preceding "pat" or "store")
goto: x
    process key x when constructing an answer (need preceding "pat" or "store")

//TODO: regex

}

type
  TChatBot=class(TObject)
  private
    FScript,FValid,FInitial,FFinal:UTF8String;
    FPattern:array of record
      pr:cardinal;
      ax,ay,bx,by,rx,ry,ln:integer;
      //r:IRegExp...
    end;
    FResponse:array of record
      ax,ay:integer;
    end;
    FCaseSensitive:boolean;
    procedure SkipNonValid(const ss:UTF8String;var ax:integer;ay:integer);
    procedure GetNextWord(const ss:UTF8String;
      var ax:integer;ay:integer;var bx,by:integer);
    function ProcessPost(const ss:UTF8String):UTF8String;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromFile(const FilePath:string);
    function GetNextResponse(const Statement:UTF8String;
      State:IJSONDocument):UTF8String;
    property CaseSensitive:boolean read FCaseSensitive write FCaseSensitive;
    property Initial: UTF8String read FInitial;
    property Final:UTF8String read FFinal;
  end;

  EChatBotError=class(Exception);

implementation

uses Classes, Variants;

const
  priorityPre=1;
  priorityPost=2;
  prioritySynonym=3;
  priorityPattern=4;

//xkey: FPattern[].ay<0, use with 'goto' only
//default: FPattern[].ay=0
//store: FPattern[].rx<0
//goto: FResponse[].ay<0

{ TChatBot }

constructor TChatBot.Create;
begin
  inherited Create;
  FScript:='';
  //FToLower:=true;//default
  FValid:='abcdefghijklmnopqrstuvwxyz''';//default
  FInitial:='';
  FFinal:='';
  FCaseSensitive:=false;
  SetLength(FPattern,0);
  SetLength(FResponse,0);
end;

destructor TChatBot.Destroy;
begin
  FScript:='';
  SetLength(FPattern,0);
  SetLength(FResponse,0);
  inherited;
end;

function Eq(const s:UTF8String;sx,sy:integer;
  const t:UTF8String;tx,ty:integer):boolean;
var
  i,si,ti:integer;
begin
  if (sy=ty) and (sy>=0) and (ty>=0) then
   begin
    i:=0;
    si:=sx;
    ti:=tx;
    while (i<>sy) and (s[si]=t[ti]) do
     begin
      inc(i);
      inc(si);
      inc(ti);
     end;
    Result:=i=sy;
   end
  else
    Result:=false;//unequal length, can't be identical
end;

function iAbs(x:integer):integer;
begin
  if x<0 then Result:=-x else Result:=x;
end;

function ReadFile(const FilePath:string):UTF8String;
var
  f:TFileStream;
  w:AnsiString;
  l:integer;
begin
  f:=TFileStream.Create(FilePath,fmOpenRead or fmShareDenyWrite);
  try
    l:=f.Size;
    SetLength(w,l);
    if f.Read(w[1],l)<>l then RaiseLastOSError;
    if (l>=3) and (w[1]=#$EF) and (w[2]=#$BB) and (w[3]=#$BF) then
     begin
      dec(l,3);
      SetLength(w,l);
      Move(w[4],Result[1],l);
     end
    else
    if (l>=2) and (w[1]=#$FF) and (w[2]=#$FE) then
      w:=UTF8Encode(PWideChar(pointer(@w[3])))
    else
      Result:=PAnsiChar(pointer(@w[1]));
  finally
    f.Free;
  end;
end;

procedure TChatBot.LoadFromFile(const FilePath: string);
var
  di,dl:integer;

  procedure NextWord(var ax,ay:integer);
  var
    dj:integer;
  begin
    ax:=di;
    dj:=di;
    while (dj<=dl) and (FScript[dj]>' ') do inc(dj);
    ay:=dj-di;
    //Result:=Copy(FScript,ax,ay);
    di:=dj+1;
    while (di<=dl) and (FScript[di] in [' ',#9]) do inc(di);//skip whitespace
  end;

var
  ln:integer;

  function AtEOL:boolean;
  begin
    //while (di<=dl) and (FScript[di] in [' ',#9]) do inc(di);//skip whitespace
    if di<=dl then
      if FScript[di] in [#10,#12,#13] then
       begin
        inc(ln);
        inc(di);
        if (di<=dl) and (FScript[di-1]=#13) and (FScript[di]=#10) then inc(di);
        Result:=true;
       end
      else
        Result:=false
    else
      Result:=true;
  end;

  procedure UpToEOL(var ax,ay:integer);
  var
    dj:integer;
  begin
    //while (di<=dl) and (FScript[di] in [' ',#9]) do inc(di);//skip whitespace
    ax:=di;
    dj:=di;
    while (di<=dl) and not(FScript[di] in [#10,#12,#13]) do inc(di);
    ay:=di-dj;
    //Result:=Copy(FScript,ax,ay);
    inc(ln);
    inc(di);
    if (di<=dl) and (FScript[di-1]=#13) and (FScript[di]=#10) then inc(di);
  end;

  procedure Fail(const Msg:string);
  begin
    raise EChatBotError.CreateFmt('%s, line %d',[Msg,ln]);//at?
  end;

var
  PIndex,PCount:integer;

  function AddPat(priority:cardinal;ax,ay,bx,by,rx,ry:integer):integer;
  begin
    if PIndex=PCount then
     begin
      inc(PCount,$100);//growstep
      SetLength(FPattern,PCount);
     end;
    FPattern[PIndex].pr:=priority;
    FPattern[PIndex].ax:=ax;
    FPattern[PIndex].ay:=ay;
    FPattern[PIndex].bx:=bx;
    FPattern[PIndex].by:=by;
    FPattern[PIndex].rx:=rx;
    FPattern[PIndex].ry:=ry;
    FPattern[PIndex].ln:=ln;
    Result:=PIndex;
    inc(PIndex);
  end;

var
  w:UTF8String;
  UnknownDirective:boolean;
  ax,ay,bx,by,kx,ky,priorityKey,
  PCurrent,RIndex,RCount:integer;
begin
  FScript:=ReadFile(FilePath);
  dl:=Length(FScript);

  PIndex:=0;
  PCount:=0;
  PCurrent:=-1;
  RIndex:=0;
  RCount:=0;
  kx:=0;
  ky:=0;
  priorityKey:=priorityPattern;

  ln:=1;
  di:=1;
  while (di<=dl) do
   begin
    //get keyword
    while (di<=dl) and (FScript[di] in [' ',#9]) do inc(di);//skip whitespace
    ax:=di;
    while (di<=dl) and not(FScript[di] in [#9,#10,#12,#13,':',' ']) do inc(di);
    w:=Copy(FScript,ax,di-ax);
    while (di<=dl) and (FScript[di] in [#9,':',' ']) do inc(di);
    //which keyword
    UnknownDirective:=false;//default
    if w='' then w:=';';
    case w[1] of
      'k':
        if w='key' then
         begin
          NextWord(kx,ky);
          if ky=0 then Fail('Key requires name');
          NextWord(bx,by);
          if not(TryStrToInt(Copy(FScript,bx,by),priorityKey)) then
            Fail('Key invalid priority');
          inc(priorityKey,priorityPattern);
          //AddPat: see below (pat,regex)
          //TODO: more? store?
         end
        else UnknownDirective:=true;
      'p':
        if w='pat' then
         begin
          if (kx=0) and (ky=0) then Fail('Pattern without Key');
          UpToEOL(bx,by);
          PCurrent:=AddPat(priorityKey,kx,ky,bx,by,RIndex,0);
         end
        else
        if w='pre' then
         begin
          //TODO: pre regex
          NextWord(ax,ay);
          UpToEOL(bx,by);
          if (ay=0) or (by=0) then Fail('Pre rule requires two words');
          AddPat(priorityPre,ax,ay,bx,by,0,0);
         end
        else
        if w='post' then
         begin
          //TODO: post regex
          NextWord(ax,ay);
          UpToEOL(bx,by);
          if (ay=0) or (by=0) then Fail('Post rule requires two words');
          AddPat(priorityPost,ax,ay,bx,by,0,0);
         end
        else UnknownDirective:=true;
      's':
        if w='syn' then
         begin
          //TODO: syn regex
          NextWord(ax,ay);
          if ay=0 then Fail('Syn rule requires name');
          while not AtEOL do
           begin
            NextWord(bx,by);
            if by=0 then Fail('Syn rule doesn''t allow blank words');
            AddPat(prioritySynonym,ax,ay,bx,by,0,0);
           end;
         end
        else
        if w='store' then
         begin
          if (kx=0) and (ky=0) then Fail('Store without Key');
          UpToEOL(bx,by);
          PCurrent:=AddPat(priorityKey,kx,ky,bx,by,-RIndex,0);
         end
        else UnknownDirective:=true;
      {
      'r':
        if w='regex' then
         begin
          if (kx=0) and (ky=0) then Fail('Regex pattern without Key');

         end
        else UnknownDirective:=true;
      }
      'a':
        if w='a' then
         begin
          if PCurrent=-1 then Fail('Answer without Pattern');
          UpToEOL(bx,by);
          inc(FPattern[PCurrent].ry);
          if RIndex=RCount then
           begin
            inc(RCount,$100);//growstep
            SetLength(FResponse,RCount);
           end;
          FResponse[RIndex].ax:=bx;
          FResponse[RIndex].ay:=by;
          //FResponse[RIndex].ln:=ln;
          inc(RIndex);
         end
        {
        else
        if w='all' then
          ...
        }
        else UnknownDirective:=true;
      'g':
        if w='goto' then
         begin
          if PCurrent=-1 then Fail('Goto without Pattern');
          UpToEOL(bx,by);
          if by=0 then Fail('Goto without destination Key');
          inc(FPattern[PCurrent].ry);
          if RIndex=RCount then
           begin
            inc(RCount,$100);//growstep
            SetLength(FResponse,RCount);
           end;
          FResponse[RIndex].ax:=bx;
          FResponse[RIndex].ay:=-by;
          //FResponse[RIndex].ln:=ln;
          inc(RIndex);
         end
        else UnknownDirective:=true;
      'd':
        if w='default' then
         begin
          kx:=ax;
          ky:=0;
          NextWord(bx,by);
          if not(TryStrToInt(Copy(FScript,bx,by),priorityKey)) then
            Fail('None invalid priority');
          inc(priorityKey,priorityPattern);
         end
        else UnknownDirective:=true;
      'v':
        if w='valid' then
         begin
          UpToEOL(bx,by);
          FValid:=Copy(FScript,bx,by);//TODO: allow only once?
         end
        else UnknownDirective:=true;
      'x':
        if w='xkey' then
         begin
          NextWord(kx,ky);
          if ky=0 then Fail('XKey requires name');
          NextWord(bx,by);
          if not(TryStrToInt(Copy(FScript,bx,by),priorityKey)) then
            Fail('Key invalid priority');
          inc(priorityKey,priorityPattern);
          ky:=-ky;
         end
        else
        if w='xvalid' then
         begin
          UpToEOL(bx,by);
          FValid:=Copy(FScript,bx,by);//TODO: allow only once?
          FCaseSensitive:=true;
         end
        else UnknownDirective:=true;
      '#',';','/'://ignore line
          UpToEOL(bx,by);
      'i':
        if w='initial' then
         begin
          UpToEOL(bx,by);
          FInitial:=Copy(FScript,bx,by);
         end
        else UnknownDirective:=true;
      'f':
        if w='final' then
         begin
          UpToEOL(bx,by);
          FFinal:=Copy(FScript,bx,by);
         end
        else UnknownDirective:=true;
      'q':
        if w='quit' then UpToEOL(bx,by)//TODO
        else UnknownDirective:=true;
      else UnknownDirective:=true;
    end;
    if UnknownDirective then
      raise EChatBotError.CreateFmt('Unknown keyword at line %d: "%s"',[ln,w]);
   end;

  //check
  for di:=0 to PIndex-1 do
    if (FPattern[di].pr>=priorityPattern) and (FPattern[di].ry=0) then
     begin
      ln:=FPattern[di].ln;
      Fail('Key without Answers');
     end;

  SetLength(FPattern,PIndex);
  SetLength(FResponse,RIndex);
end;

function TChatBot.ProcessPost(const ss: UTF8String): UTF8String;
var
  tt:UTF8String;
  tx,ty,ax,i:integer;
begin
  if FCaseSensitive then tt:=ss else tt:=LowerCase(ss);
  tx:=1;
  ty:=Length(tt);
  while (tx<=ty) and (tt[tx]=' ') do inc(tx);
  Result:=Copy(tt,1,tx-1);
  while (tx<=ty) do
   begin
    //SkipNonValid,GetNextWord here?
    ax:=tx;
    while (tx<=ty) and (tt[tx]<>' ') do inc(tx);
    i:=0;
    while (i<>Length(FPattern)) and not((FPattern[i].pr=priorityPost) and
      Eq(tt,ax,tx-ax,FScript,FPattern[i].ax,FPattern[i].ay)) do inc(i);
    if i=Length(FPattern) then
      Result:=Result+Copy(ss,ax,tx-ax)//Copy(tt,?
    else
      Result:=Result+Copy(FScript,FPattern[i].bx,FPattern[i].by);
    ax:=tx;
    while (tx<=ty) and (tt[tx]=' ') do inc(tx);
    Result:=Result+Copy(tt,ax,tx-ax);
   end;
end;

procedure TChatBot.SkipNonValid(const ss:UTF8String;var ax:integer;ay:integer);
var
  vx,vy:integer;
begin
  vy:=Length(FValid);
  vx:=vy;
  while (ax<=ay) and (vx=vy) do
   begin
    vx:=0;
    while (vx<>vy) and (FValid[vx+1]<>ss[ax]) do inc(vx);
    if vx=vy then inc(ax);
   end;
end;

procedure TChatBot.GetNextWord(const ss:UTF8String;
  var ax:integer;ay:integer;var bx,by:integer);
var
  vx,vy:integer;
begin
  bx:=ax;
  vy:=Length(FValid);
  vx:=0;
  while (ax<=ay) and (vx<>vy) do
   begin
    vx:=0;
    while (vx<>vy) and (FValid[vx+1]<>ss[ax]) do inc(vx);
    if vx<>vy then inc(ax);
   end;
  by:=ax-bx;
  SkipNonValid(ss,ax,ay);
end;

function TChatBot.GetNextResponse(const Statement:UTF8String;
  State:IJSONDocument):UTF8String;
var
  s:UTF8String;
  w:array of record
    dx,dy,ax,ay:integer;
  end;
  wi,wl:integer;

  procedure AddWord(dx,dy,ax,ay:integer);
  begin
    if wi=wl then
     begin
      inc(wl,$100);//growstep
      SetLength(w,wl);
     end;
    w[wi].dx:=dx;
    w[wi].dy:=dy;
    w[wi].ax:=ax;
    w[wi].ay:=ay;
    inc(wi);
  end;

var
  sm:array of record
    sx,sy:integer;
  end;
  sml:integer;

  function EqW(wj,ax,ay:integer):boolean;
  begin
    //assert wj<wi
    if w[wj].dy=0 then
      Result:=Eq(s,w[wj].ax,w[wj].ay,FScript,ax,ay)
    else
      Result:=Eq(FScript,w[wj].dx,w[wj].dy,FScript,ax,ay);
  end;

  function Match(pat:integer):boolean;
  var
    bx,by:integer;
    q:array of record
      ax,ay,sx,sy,wj:integer;
    end;
    i,qi,ql,wj:integer;
  begin
    //assert pat<Length(FPattern)
    //assert FPattern[pat].priority>=priorityPattern
    //TODO: if IRegExp then Match

    //parse match pattern
    bx:=FPattern[pat].bx;
    by:=FPattern[pat].bx+FPattern[pat].by;
    ql:=1;
    for i:=bx to by-1 do if FScript[i]=' ' then inc(ql);
    SetLength(q,ql);
    i:=bx;
    qi:=0;
    while i<by do
     begin
      //assert qi<ql
      q[qi].ax:=i;
      while (i<by) and (FScript[i]<>' ') do inc(i);
      q[qi].ay:=i-q[qi].ax;
      q[qi].sx:=-1;
      q[qi].sy:=-1;
      q[qi].wj:=-1;
      inc(qi);
      inc(i);
     end;

    //detect pattern
    Result:=true;//default
    qi:=0;
    wj:=0;
    while Result and (qi<ql) and (wj<wi) do
     begin
      if (q[qi].ay=1) and (FScript[q[qi].ax]='*') then
       begin
        if q[qi].sx=-1 then
         begin
          q[qi].sx:=w[wj].ax;
          if qi=ql-1 then //trailing '*'? match to end
           begin
            q[qi].sy:=w[wi-1].ax+w[wi-1].ay;
            wj:=wi;
           end
          else
            q[qi].sy:=w[wj].ax;
         end
        else
          q[qi].sy:=w[wj].ax;
        q[qi].wj:=wj+1;//retry from here when nothing found
        inc(qi);
       end
      else
      if FScript[q[qi].ax]='@' then //synonyms
       begin
        i:=0;
        while (i<>Length(FPattern)) and not((FPattern[i].pr=prioritySynonym) and
          Eq(FScript,q[qi].ax+1,q[qi].ay-1,FScript,FPattern[i].ax,FPattern[i].ay) and
          (EqW(wj,FPattern[i].ax,FPattern[i].ay) or
          EqW(wj,FPattern[i].bx,FPattern[i].by))) do inc(i);
        if i<>Length(FPattern) then
         begin
          q[qi].sx:=w[wj].ax;
          q[qi].sy:=w[wj].ax+w[wj].ay;
          inc(qi);
          inc(wj);
         end
        else
          Result:=false;
       end
      else
      if EqW(wj,q[qi].ax,q[qi].ay) then
       begin
        inc(qi);
        inc(wj);
       end
      else
        Result:=false;
      //if nothing found: any retry points set?
      while not(Result) and (qi<>0) do
       begin
        i:=qi;
        while (i<>0) and (q[i-1].wj=-1) do dec(i);
        if i=0 then
          qi:=0
        else
         begin
          qi:=i-1;
          if q[qi].wj<wi then
           begin
            wj:=q[qi].wj;
            Result:=true;
           end;
          q[qi].wj:=-1;
         end;
       end;
     end;
    if Result and not((qi=ql) and (wj=wi)) then Result:=false;//only partial match

    //store submatches
    if Result then
     begin
      qi:=0;
      i:=0;
      while qi<ql do
       begin
        if q[qi].sx<>-1 then
         begin
          if i=sml then
           begin
            inc(sml,$100);//growstep
            SetLength(sm,sml);
           end;
          sm[i].sx:=q[qi].sx;
          sm[i].sy:=q[qi].sy-q[qi].sx;
          inc(i);
         end;
        inc(qi);
       end;
     end;
     
  end;

var
  ax,ay,bx,by,cx,cy,dx,dy,i,j:integer;
  k:array of integer;
  ki,kl:integer;
  t:UTF8String;
  DefaultsLoaded:boolean;

begin
  if FCaseSensitive then s:=Statement else s:=LowerCase(Statement);
  wi:=0;
  wl:=0;
  ax:=1;
  ay:=Length(s);
  //split words
  SkipNonValid(s,ax,ay);
  while ax<=ay do
   begin
    GetNextWord(s,ax,ay,bx,by);
    //check pre translation
    i:=0;
    while (i<>Length(FPattern)) and not((FPattern[i].pr=priorityPre) and
      Eq(s,bx,by,FScript,FPattern[i].ax,FPattern[i].ay)) do inc(i);
    if i=Length(FPattern) then
      AddWord(0,0,bx,by)
    else
     begin
      dx:=FPattern[i].bx;
      dy:=FPattern[i].bx+FPattern[i].by-1;
      SkipNonValid(FScript,dx,dy);
      while dx<=dy do
       begin
        GetNextWord(FScript,dx,dy,cx,cy);
        AddWord(cx,cy,bx,by);
       end;
     end;
   end;

  //TODO: detect sentences?

  //check keys
  ki:=0;
  kl:=0;
  for i:=0 to Length(FPattern)-1 do
    if FPattern[i].pr>=priorityPattern then
     begin
      j:=0;
      while (j<wi) and not(EqW(j,FPattern[i].ax,FPattern[i].ay)) do inc(j);
      if j<wi then //keyword found
       begin
        //push key (sort descending)
        if ki=kl then
         begin
          inc(kl,$10);//growstep
          SetLength(k,kl);
         end;
        j:=ki;
        while (j<>0) and (FPattern[k[j-1]].pr<FPattern[i].pr) do
         begin
          k[j]:=k[j-1];
          dec(j);
         end;
        k[j]:=i;
        inc(ki);
       end;
     end;

  //evaluate keys
  sml:=0;
  DefaultsLoaded:=false;
  Result:='';//default
  dy:=0;//goto count
  i:=-1;
  while i=-1 do
   begin
    i:=0;
    while (i<ki) and not((k[i]<>-1) and Match(k[i])) do inc(i);
    if i=ki then
     begin
      //any stored?
      if VarIsNull(State['stored']) then j:=0 else j:=State['stored'];
      if j=0 then
       begin
        //defaults
        if not DefaultsLoaded then
         begin
          i:=0;
          while i<Length(FPattern) do
           begin
            if (FPattern[i].pr>=priorityPattern) and (FPattern[i].ay=0) then
             begin
              j:=0;
              while (j<ki) and (k[j]<>i) do inc(j);
              if j=ki then
               begin
                //add default
                if ki=kl then
                 begin
                  inc(kl,$10);//growstep
                  SetLength(k,kl);
                 end;
                j:=ki;
                while (j<>0) and (FPattern[k[j-1]].pr<FPattern[i].pr) do
                 begin
                  k[j]:=k[j-1];
                  dec(j);
                 end;
                k[j]:=i;
                inc(ki);
                inc(i);
               end
              else
               begin
                //defaults already added!
                Result:='';//'I am at a loss for words.';
                i:=Length(FPattern);
               end;
             end
            else
              inc(i);
           end;
          DefaultsLoaded:=true;
          i:=-1;
         end;
       end
      else
       begin
        t:=Format('stored%d',[j]);
        Result:=VarToStr(State[t]);
        State.Delete(t);
        State['stored']:=j-1;
        i:=0;
       end;
     end
    else
     begin
      //find (next) response
      t:=Format('ln%d',[FPattern[k[i]].ln]);
      if VarIsNull(State[t]) then j:=0 else j:=State[t];
      if j>=FPattern[k[i]].ry then j:=0;
      State[t]:=j+1;
      j:=iAbs(FPattern[k[i]].rx)+j;
      //assert j<Length(FResponse)
      if FResponse[j].ay<0 then
       begin
        //goto
        inc(dy);
        if dy=10 then raise EChatBotError.Create('Maximum sequential Goto count exceeded');
        cx:=FResponse[j].ax;
        cy:=-FResponse[j].ay;
        k[i]:=-1;
        for j:=0 to Length(FPattern)-1 do
          if (FPattern[j].pr>=priorityPattern) and
            Eq(FScript,FPattern[j].ax,FPattern[j].ay,FScript,cx,cy) then
           begin
            //insert here(j) (or by priority?)
            if k[i]=-1 then
              k[i]:=j
            else
             begin
              if ki=kl then
               begin
                inc(kl,$10);//growstep
                SetLength(k,kl);
               end;
              dx:=ki;
              inc(ki);
              while dx>i do
               begin
                k[dx]:=k[dx-1];
                dec(dx);
               end;
              k[i]:=j;
             end;
            inc(i);
           end;
        i:=-1;
       end
      else
       begin
        //construct response
        ax:=FResponse[j].ax;
        ay:=FResponse[j].ax+FResponse[j].ay-1;
        Result:='';
        while ax<=ay do
         begin
          bx:=ax;
          while (ax<=ay) and (FScript[ax]<>'$') do inc(ax);
          Result:=Result+Copy(FScript,bx,ax-bx);
          if (ax<=ay) and (FScript[ax]='$') then
           begin
            inc(ax);
            dx:=0;
            while (ax<=ay) and (FScript[ax] in ['0'..'9']) do
             begin
              dx:=dx*10+(byte(FScript[ax]) and $0F);
              inc(ax);
             end;
            if dx=0 then
              Result:=Result+ProcessPost(Statement) //?
            else
             begin
              dec(dx);
              Result:=Result+ProcessPost(Copy(Statement,sm[dx].sx,sm[dx].sy));//Copy(s,?
             end;
           end;
         end;
        if FPattern[k[i]].rx<0 then
         begin
          //store
          if VarIsNull(State['stored']) then j:=0 else j:=State['stored'];
          inc(j);
          t:=Format('stored%d',[j]);
          State[t]:=Result;
          State['stored']:=j;
          //take next
          k[i]:=-1;
          i:=-1;
         end;
       end;
     end;
   end;
end;

end.
