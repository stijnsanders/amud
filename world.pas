unit world;

interface

uses SysUtils, jsonDoc;

const
  AmudVersion='amud v1.0.0.2';

type
  TUserInfo=class;//forward

  TCmdHandler=function(ThingID,SubjectID:integer):UTF8String of object;

  TUserInfo=class(TObject)
  private
    FCmd:array of record
      ThingID,SubjectID:integer;
      Cmd:UTF8String;
      Handler:TCmdHandler;
    end;
    FCmdIndex,FCmdSize:integer;
    FConfirm,FIsAdmin:boolean;
    function NewCmd: integer;
    function qName(ThingID:integer):UTF8String;
    function qData(ThingID:integer):IJSONDocument;
  protected
    function TakeThing(ThingID,SubjectID:integer):UTF8String;
    function DropThing(ThingID,SubjectID:integer):UTF8String;
    function TrashThing(ThingID,SubjectID:integer):UTF8String;
    function GiveThing(ThingID,SubjectID:integer):UTF8String;
    function AdminEdit(ThingID,SubjectID:integer):UTF8String;
    function TakeMoney(ThingID,SubjectID:integer):UTF8String;
    function DropMoney(ThingID,SubjectID:integer):UTF8String;
    function GiveMoney(ThingID,SubjectID:integer):UTF8String;
    function Bed_LieDown(ThingID,SubjectID:integer):UTF8String;
    function Door_Go(ThingID,SubjectID:integer):UTF8String;
    function Leaflet_Read(ThingID,SubjectID:integer):UTF8String;
    function RoomMaker_MakeRoom(ThingID,SubjectID:integer):UTF8String;
    function LockMaker_LockDoor(ThingID,SubjectID:integer):UTF8String;
    function LockMaker_DuplicateKey(ThingID,SubjectID:integer):UTF8String;
    function NoteBloc_WriteNote(ThingID,SubjectID:integer):UTF8String;
    function PowerTool_OnOff(ThingID,SubjectID:integer):UTF8String;
    function Form_Fill(ThingID,SubjectID:integer):UTF8String;
  public
    FeedID,PersonID,RoomID:integer;
    LastTalk:UTF8String;
    constructor Create;
    function UserWelcomeRoom:integer;
    function ListCommands(ThingID:integer):UTF8String;
    function DoCommand(const Cmd:UTF8String;SubjectID:integer;var ThingID:integer):UTF8String;
    function ListActions(ThingID,SubjectID:integer):UTF8String;
    function DoAction(const Cmd:UTF8String;
      var ThingID,SubjectID:integer):UTF8String;
    procedure ClearCommands;
  end;

implementation

uses Variants, DataLank, feed, tools;

{ TUserInfo }

constructor TUserInfo.Create;
begin
  inherited Create;
  FeedID:=-1;
  PersonID:=0;
  RoomID:=0;
  LastTalk:='';
  FCmdSize:=0;
  FCmdIndex:=0;
  FConfirm:=false;
  FIsAdmin:=false;
end;

function TUserInfo.UserWelcomeRoom: integer;
var
  i,HallID,id1:integer;
  qr:TQueryResult;
  s:string;
begin
  Result:=0;
  HallID:=0;//counter warning
  FIsAdmin:=false;

  qr:=TQueryResult.Create(DBCon,'select * from Item where what=? and key=?',['room','welcome:hall']);
  try
    if qr.EOF then
      raise Exception.Create('Unable to initiate avatar')//TODO: create hotel/hallway?
    else
      HallID:=qr.GetInt('ID');
  finally
    qr.Free;
  end;

  DBCon.BeginTrans;
  try
    i:=400;
    qr:=TQueryResult.Create(DBCon,'select ID,key from Item where what=? and key like ? order by key',['room','welcome:room%']);
    try
      while (Result=0) and qr.Read do
       begin
        id1:=qr.GetInt('ID');
        s:=qr.GetStr('key');
        if Copy(s,1,12)='welcome:room' then
         begin
          i:=StrToInt(Copy(s,13,8));
          if AMUDData.PersonsInRoom(id1)=0 then Result:=id1;
         end;
       end;
    finally
      qr.Free;
    end;
    if Result=0 then
     begin
      inc(i);
      Result:=DBCon.Insert('Item',
        ['what','room'
        ,'name','Sunburst Hotel, Room '+IntToStr(i)
        ,'key',Format('welcome:room%.8d',[i])
        //,'ParentID',HallID
        ,'data','{"max":3}'
        ,'createdon',Now
        ],'ID');
      DBCon.Insert('Item',
        ['what','door'
        ,'name','exit'
        ,'ParentID',Result
        ,'data','{"to":'+IntToStr(HallID)+'}'
        ,'createdon',Now
        ],'ID');
      DBCon.Insert('Item',
        ['what','door'
        ,'name','Room '+IntToStr(i)
        ,'ParentID',HallID
        ,'data','{"to":'+IntToStr(Result)+'}'
        ,'createdon',Now
        ],'ID');
      end;

    //TODO: basic items
    s:=Format('welcome:bed%.8d',[Result]);
    if nx(Result,s) then DBCon.Insert('Item',
      ['what','bed'
      ,'name',''
      ,'key',s
      ,'ParentID',Result
      ,'data','{"fixed":true}'
      ,'createdon',Now
      ],'ID');
    if nx(Result,'welcome:leaflet') then DBCon.Insert('Item',
      ['what','leaflet'
      ,'name','welcome'
      ,'key','welcome:leaflet'
      ,'ParentID',Result
      ,'data','{"url":"welcome.html"}'//TODO: welcome text URL
      ,'createdon',Now
      ],'ID');

    DBCon.CommitTrans;
  except
    DBCon.RollbackTrans;
    raise;
  end;
end;

procedure TUserInfo.ClearCommands;
begin
  FCmdIndex:=0;
  //keep allocated array
end;

function TUserInfo.NewCmd:integer;
const
  CmdGrowSize=$100;
begin
  if FCmdIndex=FCmdSize then
   begin
    inc(FCmdSize,CmdGrowSize);
    SetLength(FCmd,FCmdSize);
   end;
  Result:=FCmdIndex;
  //caller sets FCmd[FCmdIndex]
  inc(FCmdIndex);
end;

function TUserInfo.ListCommands(ThingID: integer): UTF8String;
var
  qr:TQueryResult;
  d:IJSONDocument;
  what:string;
  DefaultThing,InInv:boolean;

  procedure AddCmd(const Cmd:UTF8String;Handler:TCmdHandler);
  var
    c:integer;
  begin
    c:=NewCmd;
    FCmd[c].ThingID:=ThingID;
    FCmd[c].SubjectID:=0;
    FCmd[c].Cmd:=IntToStr(ThingID)+Cmd;
    FCmd[c].Handler:=Handler;
    Result:=Result+#$60+Cmd;
  end;

begin
  Result:='';//default
  qr:=TQueryResult.Create(DBCon,'select * from Item where ID=?',[ThingID]);
  try
    what:=qr.GetStr('what');
    d:=JSON.Parse(qr.GetStr('data'));
    InInv:=qr.GetInt('ParentID')=PersonID;//TODO: cascading!
    if FIsAdmin then AddCmd('x',AdminEdit);

    DefaultThing:=false;//default
    case what[1] of
      'b':
        if what='bed' then AddCmd('lie down',Bed_LieDown)
        else DefaultThing:=true;
      'd':
        if what='door' then AddCmd('go',Door_Go)
        else DefaultThing:=true;
      'f':
        if what='form' then AddCmd('fill',Form_Fill)
        else DefaultThing:=true;
      'l':
        if what='leaflet' then
         begin
          AddCmd('read',Leaflet_Read);
          DefaultThing:=true;
         end
        else DefaultThing:=true;
      'n':
        if what='note' then
         begin
          if InInv then AddCmd('trash',TrashThing);
          DefaultThing:=true;
         end
        else DefaultThing:=true;
      'm':
        if what='money' then
         begin
          if InInv then AddCmd('drop',DropMoney) else AddCmd('take',TakeMoney);
         end;
      'p':
        if what='passage' then AddCmd('go',Door_Go)
        else DefaultThing:=true;
      'L':
        if what='LockMaker' then
         begin
          AddCmd('add lock',LockMaker_LockDoor);
          AddCmd('duplicate key',LockMaker_DuplicateKey);
         end
        else DefaultThing:=true;
      'N':
        if what='NoteBloc' then AddCmd('write a note',NoteBloc_WriteNote)
        else DefaultThing:=true;
      'P':
        if what='PowerTool' then
         begin
          if InInv then AddCmd('switch',PowerTool_OnOff);
          DefaultThing:=true;//?
         end
        else DefaultThing:=true;
      'R':
        if what='RoomMaker' then AddCmd('make a room',RoomMaker_MakeRoom)
        else DefaultThing:=true;
      else DefaultThing:=true;
    end;
    if DefaultThing then
      if InInv then AddCmd('drop',DropThing) else
       begin
        if (VarIsNull(d['fixed'])) or (d['fixed']=false) then
          AddCmd('take',TakeThing);
       end;
  finally
    qr.Free;
  end;
end;

function TUserInfo.DoCommand(const Cmd:UTF8String;SubjectID:integer;var ThingID:integer):UTF8String;
var
  c:integer;
  b:boolean;
begin
  c:=0;
  while (c<FCmdIndex) and (FCmd[c].Cmd<>Cmd) do inc(c);
  if c=FCmdIndex then
    raise Exception.Create('Unknown command "'+Cmd+'"')
  else
   begin
    ThingID:=FCmd[c].ThingID;
    //assert FCmd[c].SubjectID=0
    b:=FConfirm;
    Result:=FCmd[c].Handler(ThingID,SubjectID);
    if b then FConfirm:=false;
   end;
end;

function TUserInfo.ListActions(ThingID,SubjectID:integer): UTF8String;
var
  qr:TQueryResult;
  d:IJSONDocument;
  what:string;
  DefaultThing:boolean;
  ParentID:integer;

  procedure AddCmd(const Cmd:UTF8String;Handler:TCmdHandler);
  var
    c:integer;
  begin
    c:=NewCmd;
    FCmd[c].ThingID:=ThingID;
    FCmd[c].SubjectID:=SubjectID;
    FCmd[c].Cmd:=IntToStr(SubjectID)+Cmd+IntToStr(ThingID);
    FCmd[c].Handler:=Handler;
    Result:=Result+#$60+Cmd+#$60+IntToStr(ThingID);
  end;

begin
  Result:='';//default
  qr:=TQueryResult.Create(DBCon,'select * from Item where ID=?',[ThingID]);
  try
    what:=qr.GetStr('what');
    d:=JSON.Parse(qr.GetStr('data'));
    ParentID:=qr.GetInt('ParentID');
    if FIsAdmin then AddCmd('x',AdminEdit);

    DefaultThing:=false;//default
    case what[1] of
      'd':
        if what='door' then //nothing?
        else DefaultThing:=true;
      'm':
        if what='money' then
          if ParentID=PersonID then //TODO: cascading!
            if SubjectID<>PersonID then
              AddCmd('give',GiveMoney);
      else DefaultThing:=true;
    end;
    if DefaultThing then
      if ParentID=PersonID then //TODO: cascading!
        if SubjectID<>PersonID then
          AddCmd('give',GiveThing);
  finally
    qr.Free;
  end;
end;

function TUserInfo.DoAction(const Cmd:UTF8String;
  var ThingID,SubjectID:integer): UTF8String;
var
  c:integer;
  b:boolean;
begin
  c:=0;
  while (c<FCmdIndex) and (FCmd[c].Cmd<>Cmd) do inc(c);
  if c=FCmdIndex then
    raise Exception.Create('Unknown command "'+Cmd+'"')
  else
   begin
    ThingID:=FCmd[c].ThingID;
    SubjectID:=FCmd[c].SubjectID;
    b:=FConfirm;
    Result:=FCmd[c].Handler(ThingID,SubjectID);
    if b then FConfirm:=false;
   end;
end;

function TUserInfo.qName(ThingID: integer): UTF8String;
var
  qr:TQueryResult;
begin
  qr:=TQueryResult.Create(DBCon,'select name from Item where ID=?',[ThingID]);
  try
    Result:=UTF8Encode(qr.GetStr('name'));
  finally
    qr.Free;
  end;
end;

function TUserInfo.qData(ThingID: integer): IJSONDocument;
var
  qr:TQueryResult;
begin
  qr:=TQueryResult.Create(DBCon,'select data from Item where ID=?',[ThingID]);
  try
    Result:=JSON.Parse(qr.GetStr('data'));
  finally
    qr.Free;
  end;
end;

function TUserInfo.TakeThing(ThingID,SubjectID:integer):UTF8String;
begin
  //TODO: checks?
  DBCon.BeginTrans;
  try
    DBCon.Execute('update Item set ParentID=? where ID=?',[PersonID,ThingID]);
    DBCon.CommitTrans;
  except
    DBCon.RollbackTrans;
    raise;
  end;
  Result:='*t-'+ss(ThingID)+qx(#10'.i+',ThingID);
end;

function TUserInfo.DropThing(ThingID,SubjectID:integer):UTF8String;
begin
  //TODO: checks?
  DBCon.BeginTrans;
  try
    DBCon.Execute('update Item set ParentID=? where ID=?',[RoomID,ThingID]);
    DBCon.CommitTrans;
  except
    DBCon.RollbackTrans;
    raise;
  end;
  Result:='.i-'+ss(ThingID)+qx(#10'*t+',ThingID);
end;

function TUserInfo.TrashThing(ThingID,SubjectID:integer):UTF8String;
begin
  //TODO: checks? confirm y/n? undo?
  if FConfirm then
   begin
    DBCon.BeginTrans;
    try
      DBCon.Execute('delete from Item where ID=?',[ThingID]);
      DBCon.CommitTrans;
    except
      DBCon.RollbackTrans;
      raise;
    end;
    Result:='.i-'+ss(ThingID);
   end
  else
   begin
    FConfirm:=true;
    Result:=':m'+ss(ThingID)+
      #$60'Are you sure? (There''s no undo.) Click again.';
   end;
  //+#10'*t-'+ss(ThingID);//which?
end;

function TUserInfo.GiveThing(ThingID,SubjectID:integer):UTF8String;
begin
  //TODO: checks?
  DBCon.BeginTrans;
  try
    DBCon.Execute('update Item set ParentID=? where ID=?',[SubjectID,ThingID]);
    DBCon.CommitTrans;
  except
    DBCon.RollbackTrans;
    raise;
  end;
  Result:='.i-'+ss(ThingID)+qx(#10'!i+',ThingID);
end;

function TUserInfo.AdminEdit(ThingID,SubjectID:integer): UTF8String;
begin
  if not FIsAdmin then raise Exception.Create('Access denied');
  Result:=':u'+ss(Format('Admin.xxm?i=%d&a=%d&r=%d&f=%d&k=%s',
    [ThingID,SubjectID,RoomID,FeedID,AMUDData[FeedID].NewKey]));
end;

function TUserInfo.TakeMoney(ThingID,SubjectID:integer):UTF8String;
var
  WalletID,i,l,m1,m2:integer;
  qr:TQueryResult;
  s:UTF8String;
begin
  DBCon.BeginTrans;
  try
    qr:=TQueryResult.Create(DBCon,'select * from Item where ParentID=? and what=?',[PersonID,'money']);
    try
      if qr.EOF then
       begin
        WalletID:=0;
        m1:=0;
       end
      else
       begin
        WalletID:=qr.GetInt('ID');
        s:=UTF8Encode(qr.GetStr('name'));
        l:=Length(s);
        i:=1;
        while (i<=l) and (s[i]<>' ') do inc(i);
        m1:=StrToInt(Copy(s,1,i-1));
       end;
    finally
      qr.Free;
    end;
    qr:=TQueryResult.Create(DBCon,'select * from Item where ID=?',[ThingID]);
    try
      s:=UTF8Encode(qr.GetStr('name'));
      l:=Length(s);
      i:=1;
      while (i<=l) and (s[i]<>' ') do inc(i);
      m2:=StrToInt(Copy(s,1,i-1));
    finally
      qr.Free;
    end;
    if WalletID=0 then
     begin
      DBCon.Execute('update Item set ParentID=? where ID=?',[PersonID,ThingID]);
      Result:='*t-'+ss(ThingID)+qx(#10'.i+',ThingID);
     end
    else
     begin
      s:=IntToStr(m1+m2)+' credits';
      DBCon.Execute('update Item set name=? where ID=?',[UTF8Decode(s),WalletID]);
      DBCon.Execute('delete from Item where ID=?',[ThingID]);
      Result:='*t-'+ss(ThingID)+#10'.ii'+ss(WalletID)+#$60'money'+ss(s);//+qx(#10':ii',WalletID);
     end;
    DBCon.CommitTrans;
  except
    DBCon.RollbackTrans;
    raise;
  end;
end;

function TUserInfo.DropMoney(ThingID,SubjectID:integer):UTF8String;
var
  i,l,m1,m2:integer;
  s:UTF8String;
begin
  m1:=0;
  if (LastTalk='all') or TryStrToInt(LastTalk,m1) then
   begin
    DBCon.BeginTrans;
    try
      s:=qName(ThingID);
      l:=Length(s);
      i:=1;
      while (i<=l) and (s[i]<>' ') do inc(i);
      m2:=StrToInt(Copy(s,1,i-1));
      if LastTalk='all' then m1:=m2;
      if m2<m1 then
       begin
        Result:=':m'+ss(ThingID)+#$60'You don''t have that much.';
       end
      else if m2=m1 then
       begin
        DBCon.Execute('update Item set ParentID=? where ID=?',[RoomID,ThingID]);
        Result:='.i-'+ss(ThingID)+qx(#10'*t+',ThingID);
       end
      else
       begin
        m2:=m2-m1;
        if m2=1 then s:='1 credit' else s:=IntToStr(m2)+' credits';
        DBCon.Execute('update Item set name=? where ID=?',[UTF8Decode(s),ThingID]);
        Result:='.ii'+ss(ThingID)+#$60'money'+ss(s);//qx('.ii',ThingID)
        if m1=1 then s:='1 credit' else s:=IntToStr(m1)+' credits';
        i:=DBCon.Insert('Item',
          ['what','money'
          ,'name',s
          ,'ParentID',RoomID
          ,'data','{}'
          ,'createdon',Now
          ,'createdby',PersonID
          ],'ID');
        Result:=Result+#10'*t+'+ss(i)+#$60'money'+ss(s);//+qx(#10'*t+',i);
       end;
      DBCon.CommitTrans;
    except
      DBCon.RollbackTrans;
      raise;
    end;
   end
  else
    Result:=':m'+ss(ThingID)+#$60'State how moch credits to drop.';
end;

function TUserInfo.GiveMoney(ThingID,SubjectID:integer):UTF8String;
var
  i,l,m1,m2,m3,WalletID:integer;
  s:UTF8String;
  qr:TQueryResult;
begin
  if (LastTalk='all') or TryStrToInt(LastTalk,m1) then
   begin
    DBCon.BeginTrans;
    try
      s:=qName(ThingID);
      l:=Length(s);
      i:=1;
      while (i<=l) and (s[i]<>' ') do inc(i);
      m2:=StrToInt(Copy(s,1,i-1));
      if LastTalk='all' then m1:=m2;
      if m2<m1 then
       begin
        Result:=':m'+ss(ThingID)+#$60'You don''t have that much.';
       end
      else
       begin
        qr:=TQueryResult.Create(DBCon,'select * from Item where ParentID=? and what=?',[SubjectID,'money']);
        try
          if qr.EOF then
           begin
            WalletID:=0;
            m3:=0;
           end
          else
           begin
            WalletID:=qr.GetInt('ID');
            s:=UTF8Encode(qr.GetStr('name'));
            l:=Length(s);
            i:=1;
            while (i<=l) and (s[i]<>' ') do inc(i);
            m3:=StrToInt(Copy(s,1,i-1));
           end;
        finally
          qr.Free;
        end;
        if m2=m1 then
         begin
          DBCon.Execute('delete from Item where ID=?',[ThingID]);
          if WalletID=0 then
           begin
            DBCon.Execute('update Item set ParentID=? where ID=?',[SubjectID,ThingID]);
            Result:='.i-'+ss(ThingID)+qx(#10'!i+',ThingID);
           end
          else
           begin
            s:=IntToStr(m3+m1)+' credits';
            DBCon.Execute('update Item set name=? where ID=?',[UTF8Decode(s),WalletID]);
            Result:='.i-'+ss(ThingID)+#10'!ii'+ss(WalletID)+#$60'money'+ss(s);//+qx(#10'!ii',WalletID);
           end
         end
        else
         begin
          m2:=m2-m1;
          if m2=1 then s:='1 credit' else s:=IntToStr(m2)+' credits';
          DBCon.Execute('update Item set name=? where ID=?',[UTF8Decode(s),ThingID]);
          Result:='.ii'+ss(ThingID)+#$60'money'+ss(s);//qx('.ii',ThingID)
          s:=IntToStr(m3+m1)+' credits';
          DBCon.Execute('update Item set name=? where ID=?',[UTF8Decode(s),WalletID]);
          Result:=Result+#10'!ii'+ss(WalletID)+#$60'money'+ss(s);//+qx(#10'!ii',WalletID);
         end;
       end;
      DBCon.CommitTrans;
    except
      DBCon.RollbackTrans;
      raise;
    end;
   end
  else
    Result:=':m'+ss(ThingID)+#$60'State how moch credits to give.';
end;
function TUserInfo.Bed_LieDown(ThingID,SubjectID:integer):UTF8String;
begin
  Result:='*m'+ss(ThingID)+#$60'*squeak*';
end;

function TUserInfo.Door_Go(ThingID,SubjectID:integer):UTF8String;
var
  d1,d2:IJSONDocument;
  RoomID,i:integer;
  qr:TQueryResult;
begin
  d1:=qData(ThingID);
  RoomID:=d1['to'];
  Result:='>'+IntToStr(RoomID);//default;
  if not(VarIsNull(d1['key'])) then
   begin
    //TODO: cascaded
    qr:=TQueryResult.Create(DBCon,'select ID from Item where ParentID=? and what=? and key=?',
      [PersonID,'key','key:'+d1['key']]);
    try
      if qr.EOF then Result:=':m'+ss(ThingID)+#$60'Door is locked, you don''t have the key.';
    finally
      qr.Free;
    end;
   end;
  d2:=qData(RoomID);
  if not(VarIsNull(d2['max'])) then
   begin
    i:=d2['max'];
    if AMUDData.PersonsInRoom(RoomID)>=i then Result:=':m'+ss(ThingID)+
      #$60'Room currently has maximum number of occupants';
   end;
end;

function TUserInfo.Leaflet_Read(ThingID,SubjectID:integer):UTF8String;
begin
  Result:=':u'+ss(VarToStr(qData(ThingID)['url']));
end;

function TUserInfo.RoomMaker_MakeRoom(ThingID,SubjectID:integer):UTF8String;
var
  s:UTF8Strings;
  t:UTF8String;
  d:IJSONDocument;
  NewRoomID,NewDoorID,left:integer;
begin
  s:=Split(LastTalk,';');
  if Length(s)<3 then
    Result:=':m'+ss(ThingID)+#$60'first state "<name room> ;'+
      ' <name door to room> ; <name door from room to here>"'
  else
   begin
    //checks
    if s[0]='' then
      raise Exception.Create('RoomMaker_MakeRoom: room name required');
    if s[1]='' then s[1]:=s[0];

    DBCon.BeginTrans;
    try
      //counter
      d:=qData(ThingID);
      if VarIsNull(d['left']) then left:=0 else
       begin
        left:=d['left']-1;
        if left<=0 then
          DBCon.Execute('delete from Item where ID=?',[ThingID])
        else
         begin
          d['left']:=left;
          DBCon.Execute('update Item set data=? where ID=?',[d.ToString,ThingID]);
         end;
       end;

      d:=JSON;
      if (Length(s)>3) and (s[3]<>'') then d.Parse(s[3]);
      //TODO: more checks d?
      t:='door';
      if s[0][1]='-' then
       begin
        s[0]:=Copy(s[0],2,Length(s[0])-1);
        t:='passage';
       end;

      NewRoomID:=DBCon.Insert('Item',
        ['what','room'
        ,'name',UTF8Decode(s[0])
        ,'data',d.ToString
        ,'createdon',Now
        ,'createdby',PersonID
        ],'ID');
      NewDoorID:=DBCon.Insert('Item',
        ['what',t
        ,'name',UTF8Decode(s[1])
        ,'ParentID',RoomID
        ,'data','{"to":'+IntToStr(NewRoomID)+'}'
        ,'createdon',Now
        ,'createdby',PersonID
        ],'ID');
      DBCon.Insert('Item',
        ['what',t
        ,'name',UTF8Decode(s[2])
        ,'ParentID',NewRoomID
        ,'data','{"to":'+IntToStr(RoomID)+'}'
        ,'createdon',Now
        ,'createdby',PersonID
        ],'ID');
      DBCon.CommitTrans;
    except
      DBCon.RollbackTrans;
      raise;
    end;
    Result:='*t+'+ss(NewDoorID)+ss(t)+ss(s[1]);//qx()
    if left>1 then
      Result:=Result+#10':m'+ss(ThingID)+ss(left)+' rooms left'
    else if left=1 then
      Result:=Result+#10':m'+ss(ThingID)+#$60'1 room left!';
   end;
end;

function TUserInfo.LockMaker_LockDoor(ThingID,SubjectID:integer):UTF8String;
var
  qr:TQueryResult;
  d:IJSONDocument;
  s:UTF8String;
  id:integer;
begin
  if SubjectID=0 then
    Result:=':m'+ss(ThingID)+#$60'select a door to add a lock to'
  else
   begin
    qr:=TQueryResult.Create(DBCon,'select * from Item where ID=?',[SubjectID]);
    try
      if qr.GetStr('what')<>'door' then
        Result:=':m'+ss(ThingID)+#$60'select a door to add a lock to'
      else
       begin
        d:=JSON.Parse(qr.GetStr('data'));
        if not(VarIsNull(d['key'])) then
          Result:=':m'+ss(ThingID)+#$60'door already has a lock'
        else
         begin
          s:=RKey(40);
          d['key']:=s;
          DBCon.Execute('update Item set data=? where ID=?',[d.ToString,SubjectID]);
          id:=DBCon.Insert('Item',
            ['what','key'
            ,'ParentID',PersonID
            ,'name',qr['name']
            ,'key','key:'+s
            ,'data','{"door":'+IntToStr(SubjectID)+'}'
            ,'createdby',PersonID
            ,'createdon',Now
            ],'ID');
          Result:='.i+'+ss(id)+#$60'key'+ss(qr.GetStr('name'));
         end;
       end;
    finally
      qr.Free;
    end;
   end;
end;

function TUserInfo.LockMaker_DuplicateKey(ThingID,SubjectID:integer):UTF8String;
var
  qr:TQueryResult;
  id:integer;
begin
  if SubjectID=0 then
    Result:=':m'+ss(ThingID)+#$60'select a key to duplicate'
  else
   begin
    qr:=TQueryResult.Create(DBCon,'select * from Item where ID=?',[SubjectID]);
    try
      if qr.GetStr('what')<>'key' then
        Result:=':m'+ss(ThingID)+#$60'select a key to duplicate'
      else
       begin
        id:=DBCon.Insert('Item',
          ['what','key'
          ,'ParentID',PersonID
          ,'name',qr['name']
          ,'key',qr['key']
          ,'data',qr['data']
          ,'createdby',PersonID
          ,'createdon',Now
          ],'ID');
        Result:='.i+'+ss(id)+#$60'key'+ss(qr['name']);
       end;
    finally
      qr.Free;
    end;
   end;
end;

function TUserInfo.NoteBloc_WriteNote(ThingID,SubjectID:integer):UTF8String;
var
  id,left:integer;
  d:IJSONDocument;
begin
  if LastTalk='' then
    Result:=':m'+ss(ThingID)+#$60'first state a message for the note'
  else
   begin
    DBCon.BeginTrans;
    try
      d:=qData(ThingID);
      if VarIsNull(d['left']) then left:=0 else
       begin
        left:=d['left']-1;
        if left<=0 then
          DBCon.Execute('delete from Item where ID=?',[ThingID])
        else
         begin
          d['left']:=left;
          DBCon.Execute('update Item set data=? where ID=?',[d.ToString,ThingID]);
         end;
       end;
      id:=DBCon.Insert('Item',
        ['what','note'
        ,'name',UTF8Decode(LastTalk)
        ,'ParentID',RoomID
        ,'data','{}'
        ,'createdon',Now
        ,'createdby',PersonID
        ],'ID');
      DBCon.CommitTrans;
    except
      DBCon.RollbackTrans;
      raise;
    end;
    //':i+'?
    Result:='*t+'+ss(id)+#$60'note'+ss(LastTalk);
    if left>1 then
      Result:=Result+#10':m'+ss(ThingID)+ss(left)+' notes left'
    else if left=1 then
      Result:=Result+#10':m'+ss(ThingID)+#$60'1 note left!';
   end;
end;

function TUserInfo.PowerTool_OnOff(ThingID,SubjectID:integer): UTF8String;
const
  msg:array[boolean] of UTF8String=('off','on');
begin
  FIsAdmin:=not(FIsAdmin);//log? check?
  Result:=':m'+ss(ThingID)+ss(msg[FIsAdmin]);
end;

function TUserInfo.Form_Fill(ThingID,SubjectID:integer):UTF8String;
begin
  Result:=Format(':u'#$60'%s.xxm?i=%d&p=%d&r=%d&f=%d&k=%s',
    [VarToStr(qData(ThingID)['form'])
    ,ThingID//,SubjectID
    ,AMUDData[FeedID].Info.PersonID
    ,RoomID,FeedID,AMUDData[FeedID].NewKey]);
end;

end.
