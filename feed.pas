unit feed;

interface

uses Windows, SysUtils, Classes, xxm, xxmWebSocket, world;

const
  MaxFeeds=1000;

type
  TAMUDDataFeed=class(TXxmWebSocket)
  private
    FLog:TFileStream;
    FAdminKey,FLogHeader:UTF8String;
    procedure InitUser(const UserKey:UTF8String);
    procedure EnterRoom(ARoomID,ADoorID:integer);
  protected
    procedure ConnectSuccess; override;
    procedure ConnectionLost; override;
    procedure ReceiveText(const Data:UTF8String); override;
  public
    Info:TUserInfo;
    LastRoom,LastTx,LastTx1:UTF8String;
    procedure AfterConstruction; override;
    destructor Destroy; override;
    procedure Build(const Context: IXxmContext; const Caller: IXxmFragment;
      const Values: array of OleVariant; const Objects: array of TObject); override;
    procedure SendText(const Data:UTF8String); override;
    function NewKey:UTF8String;
    function CheckKey(const Key:UTF8String):UTF8String;
  end;

  TAMUDData=class(TObject)
  private
    FLock:TRTLCriticalSection;
    FFeeds:array[0..MaxFeeds-1] of TAMUDDataFeed;
    function GetFeed(Idx:integer):TAMUDDataFeed;
  public
    constructor Create;
    destructor Destroy; override;

    function RegisterFeed(Feed:TAMUDDataFeed):boolean;
    procedure ClearFeed(Feed:TAMUDDataFeed);
    procedure CloseAllFeeds;
    procedure SendAll(const Msg:UTF8String);
    function PersonsInRoom(RoomID:integer):integer;
    procedure SendToRoom(RoomID:integer;const Msg:UTF8String);
    procedure SendToPerson(PersonID:integer;const Msg:UTF8String);
    property Feed[Idx:integer]:TAMUDDataFeed read GetFeed; default;
  end;

  TAMUDViewFeed=class(TXxmWebSocket)
  protected
    procedure ConnectSuccess; override;
  public
    destructor Destroy; override;
  end;

  TAMUDViewThread=class(TThread)
  protected
    procedure Execute; override;
  public
    Feed:TAMUDViewFeed;
    constructor Create(AFeed:TAMUDViewFeed);
  end;

var
  AMUDData:TAMUDData;
  AMUDView:TAMUDViewThread;

implementation

uses Variants, DataLank, tools, bots;

{ TAMUDData }

constructor TAMUDData.Create;
var
  i:integer;
begin
  inherited;
  InitializeCriticalSection(FLock);
  for i:=0 to MaxFeeds-1 do FFeeds[i]:=nil;
end;

destructor TAMUDData.Destroy;
var
  i:integer;
begin
  //FLock?
  for i:=0 to MaxFeeds-1 do
    try
      if FFeeds[i]<>nil then FFeeds[i].Disconnect;//?
    except
      //silent
    end;
  DeleteCriticalSection(FLock);
  inherited;
end;

function TAMUDData.RegisterFeed(Feed: TAMUDDataFeed): boolean;
var
  i:integer;
begin
  EnterCriticalSection(FLock);
  try
    //assert Feed.FeedID=-1;
    i:=0;
    while (i<MaxFeeds) and (FFeeds[i]<>nil) do inc(i);
    if i=MaxFeeds then
      Result:=false
    else
     begin
      Result:=true;
      FFeeds[i]:=Feed;
      Feed.Info.FeedID:=i;
     end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TAMUDData.ClearFeed(Feed: TAMUDDataFeed);
begin
  EnterCriticalSection(FLock);
  try
    //assert Feed.FeedID<>-1;
    FFeeds[Feed.Info.FeedID]:=nil;
    Feed.Info.FeedID:=-1;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TAMUDData.CloseAllFeeds;
var
  i:integer;
begin
  //FLock?
  for i:=0 to MaxFeeds-1 do
    try
      if FFeeds[i]<>nil then FFeeds[i].Disconnect;
    except
    end;
end;

procedure TAMUDData.SendAll(const Msg: UTF8String);
var
  i:integer;
begin
  //FLock?
  for i:=0 to MaxFeeds-1 do
    try
      if FFeeds[i]<>nil then FFeeds[i].SendText(Msg);
    except
    end;
end;

function TAMUDData.PersonsInRoom(RoomID: integer): integer;
var
  i:integer;
begin
  Result:=0;
  //FLock?
  for i:=0 to MaxFeeds-1 do
    try
      if (FFeeds[i]<>nil) and (FFeeds[i].Info.RoomID=RoomID) then
        inc(Result);
    except
    end;
end;

procedure TAMUDData.SendToRoom(RoomID:integer;const Msg: UTF8String);
var
  i:integer;
begin
  //FLock?
  for i:=0 to MaxFeeds-1 do
    try
      if (FFeeds[i]<>nil) and (FFeeds[i].Info.RoomID=RoomID) then
        FFeeds[i].SendText(Msg);
    except
    end;
end;

procedure TAMUDData.SendToPerson(PersonID: integer; const Msg: UTF8String);
var
  i:integer;
begin
  //FLock?
  for i:=0 to MaxFeeds-1 do
    try
      if (FFeeds[i]<>nil) and (FFeeds[i].Info.PersonID=PersonID) then
        FFeeds[i].SendText(Msg);
    except
    end;
end;

function TAMUDData.GetFeed(Idx: integer): TAMUDDataFeed;
begin
  if (Idx<0) or (Idx>=MaxFeeds) then
    raise Exception.Create('Invalid feed index');
  Result:=FFeeds[Idx];
  //caller must use CheckKey!
end;

{ TAMUDDataFeed }

procedure TAMUDDataFeed.AfterConstruction;
begin
  inherited;
  Info:=TUserInfo.Create;
  FLog:=nil;
  FAdminKey:='';
  FLogHeader:='...';
  LastTx:='';
  LastRoom:='';
end;

procedure TAMUDDataFeed.Build(const Context: IXxmContext; const Caller: IXxmFragment;
  const Values: array of OleVariant; const Objects: array of TObject);
begin
  FLogHeader:=Context.ContextString(csRemoteAddress)
    +';'+Context.ContextString(csUserAgent);
    //TODO: more?
  inherited;
end;

procedure TAMUDDataFeed.ConnectSuccess;
var
  s:UTF8String;
begin
  inherited;
  //
  if AMUDData.RegisterFeed(Self) then
   begin
    FLog:=TFileStream.Create(LogPath+FormatDateTime('yyyymmddhhnnsszzz',Now)+'_'+
      IntToHex(integer(@Self),8)+'.log',fmCreate);
    s:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)+' : '+AmudVersion
      +';'+IntToStr(Info.FeedID)
      +';'+FAdminKey
      +';'+FLogHeader
      +#13#10;
    FLog.Write(s[1],Length(s));
    FLogHeader:='';
   end
  else
   begin
    SendText('#'#$60'Server is currently at maximum user feeds, please try again later');
    Disconnect;
   end;
end;

procedure TAMUDDataFeed.ConnectionLost;
var
  i:integer;
begin
  inherited;
  if AMUDData<>nil then
    try
      //TODO: drop things?
      if Info.RoomID<>0 then
       begin
        i:=Info.RoomID;
        Info.RoomID:=0;
        AMUDData.SendToRoom(i,'l'+ss(Info.PersonID));
       end;
      AMUDData.ClearFeed(Self);
    except
      //silent
    end;
  //
end;

destructor TAMUDDataFeed.Destroy;
var
  s:UTF8String;
begin
  try
    if Info.RoomID<>0 then ConnectionLost;
  except
    //silent
  end;
  if FLog<>nil then
   begin
    s:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)+' -';
    FLog.Write(s[1],Length(s));
   end;
  FLog.Free;
  Info.Free;
  inherited;
end;

procedure TAMUDDataFeed.ReceiveText(const Data: UTF8String);
var
  i,j,id,id1:integer;
  s,u:UTF8String;
  t:UTF8Strings;
begin
  inherited;
  s:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)+' < '+Data+#13#10;
  FLog.Write(s[1],Length(s));
  //
  SetLength(t,0);
  CheckDBCon;
  try
    case Data[1] of

      '#'://authentication
        if Info.PersonID=0 then
          InitUser(Copy(Data,2,Length(Data)-1))
        else
          SendText('#'#$60'Unexpected authentication');
      'n'://new user ID
        if Info.PersonID=0 then
         begin
          s:=RKey(80);
          SendText('#n'#$60+s);
          InitUser(s);
         end
        else
          SendText('#'#$60'Unexpected new UserID request');

      'c'://commands for thing
       begin
        i:=StrToInt(Copy(Data,2,Length(Data)-1));
        SendText('c'+ss(i)+Info.ListCommands(i));
       end;
      'a'://actions for a thing to someone
       begin
        t:=Split(Copy(Data,2,Length(Data)-1),',');
        i:=StrToInt(t[0]);
        if (Length(t)=1) or (t[1]='') then j:=0 else j:=StrToInt(t[1]);
        SendText('a'+ss(i)+Info.ListActions(j,i));
       end;
      's'://speak
       begin
        Info.LastTalk:=Copy(Data,2,Length(Data)-1);
        LastTx:=FormatDateTime('hh:nn:ss.zzz | ',Now)+LastRoom+' | '+Info.LastTalk;
        AMUDData.SendToRoom(Info.RoomID,'s'+ss(Info.PersonID)+ss(Info.LastTalk));
        AMUDBots.Queue(Info.RoomID,Info.PersonID,Info.LastTalk);
       end;
      'd'://do something
        try
          t:=Split(Copy(Data,2,Length(Data)-1),',');
          u:=t[0];
          if Length(t)>1 then i:=StrToInt(t[1]) else i:=0;
          t:=Split(Info.DoCommand(u,i,id),#10);
          for i:=0 to Length(t)-1 do
           begin
            s:=Copy(t[i],2,Length(t[i])-1);
            case t[i][1] of
              ':':SendText(s);
              '.':AMUDData.SendToPerson(Info.PersonID,s);
              '*':AMUDData.SendToRoom(Info.RoomID,s);
              '>':EnterRoom(StrToInt(s),id);
              //else raise ?
              else SendText('#'+ss('Unknown resolution "'+t[i][1]+'"'));
            end;
           end;
        finally
          SendText('c.'+ss(u));//command done
        end;
      'p'://perform action
        try
          t:=Split(Info.DoAction(Copy(Data,2,Length(Data)-1),id1,id),#10);
          for i:=0 to Length(t)-1 do
           begin
            s:=Copy(t[i],2,Length(t[i])-1);
            case t[i][1] of
              ':':SendText(s);
              '.':AMUDData.SendToPerson(Info.PersonID,s);
              '*':AMUDData.SendToRoom(Info.RoomID,s);
              '!':AMUDData.SendToPerson(id,s);
              //else raise?
              else SendText('#'+ss('Unknown resolution "'+t[i][1]+'"'));
            end;
           end;
        finally
          SendText('a.'+ss(Copy(Data,2,Length(Data)-1)));//action done
        end;

      else
        SendText('#'+ss('Unknown command "'+Data[1]+'"'));

    end;
  except
    on e:Exception do
     begin
      //TODO:  log
      SendText('#'+ss('Error"'+Data[1]+'"['+e.ClassName+']'+e.Message));//?
     end;
  end;
end;

procedure TAMUDDataFeed.SendText(const Data: UTF8String);
var
  s:UTF8String;
begin
  s:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)+' > '+Data+#13#10;
  FLog.Write(s[1],Length(s));
  inherited;
end;

procedure TAMUDDataFeed.InitUser(const UserKey:UTF8String);
var
  qr:TQueryResult;
begin
  SendText('#d'+ss(AmudVersion));
  //TODO: GetSelfVersion, MOTD

  DBCon.BeginTrans;
  try
    qr:=TQueryResult.Create(DBCon,'select * from Item where key=?',['user:'+UserKey]);
    try
      if qr.EOF then
       begin
        Info.PersonID:=DBCon.Insert('Item',
          ['what','person'
          ,'name','someone'
          ,'key',UTF8Decode('user:'+UserKey)
          //,'ParentID',
          ,'data','{}'//? JSON([]).ToString
          ,'createdon',Now
          ],'ID');
       end
      else
       begin
        Info.PersonID:=qr.GetInt('ID');
       end;
    finally
      qr.Free;
    end;

    DBCon.CommitTrans;
  except
    DBCon.RollbackTrans;
    raise;
  end;

  //inventory
  qr:=TQueryResult.Create(DBCon,'select * from Item where ParentID=?',[Info.PersonID]);
  try
    while qr.Read do SendText(ix('i+',qr));
  finally
    qr.Free;
  end;

  //enter 'welcome' room
  EnterRoom(Info.UserWelcomeRoom,0);
end;

procedure TAMUDDataFeed.EnterRoom(ARoomID,ADoorID:integer);
var
  qr:TQueryResult;
  i:integer;
  s,t:UTF8String;
begin
  //notify others leaving
  if Info.RoomID<>0 then
   begin
    AMUDData.SendToRoom(Info.RoomID,qx('r-',Info.PersonID)+qx('',ADoorID));
    AMUDBots.QueueUserLeaves(Info.RoomID,Info.PersonID);
   end;
  s:=qx('r+',Info.PersonID);
  t:=qx('r',ARoomID);
  LastRoom:=s+' | '+t;
  LastTx:=FormatDateTime('hh:nn:ss.zzz | ',Now)+LastRoom;

  //notify new room
  s:=s+qx('',Info.RoomID);
  Info.RoomID:=ARoomID;
  Info.LastTalk:='';

  //things
  qr:=TQueryResult.Create(DBCon,'select * from Item where ParentID=?',[ARoomID]);
  //TODO: orderby, minlevel...
  try
    while qr.Read do t:=t+ix(#$60't',qr);
  finally
    qr.Free;
  end;

  SendText(t);

  //bots
  qr:=TQueryResult.Create(DBCon,'select Item.* from Bot'+
    ' inner join Item on Item.ID=Bot.ItemID where Bot.RoomID=?',
    [ARoomID]);
  try
    while qr.Read do SendText(ix('r+',qr));
  finally
    qr.Free;
  end;
  AMUDBots.QueueUserEnters(Info.RoomID,Info.PersonID);

  //persons
  for i:=0 to MaxFeeds-1 do //TODO: lock?
    try
      if AMUDData.FFeeds[i]<>nil then
       begin
        if AMUDData.FFeeds[i].Info.RoomID=ARoomID then
          AMUDData.FFeeds[i].SendText(s);//'r+'
        if Self<>AMUDData.FFeeds[i] then
          SendText(qx('r+',AMUDData.FFeeds[i].Info.PersonID));
       end;
    except
      //silent
    end;
end;

function TAMUDDataFeed.NewKey: UTF8String;
begin
  FAdminKey:=RKey(200);
  Result:=FAdminKey;
end;

function TAMUDDataFeed.CheckKey(const Key: UTF8String): UTF8String;
begin
  if Key<>FAdminKey then
   begin
    //FAdminKey:='';//?
    raise Exception.Create('Access denied');
   end;
  FAdminKey:=RKey(200);
  Result:=FAdminKey;
end;

{ TAMUDViewThread }

constructor TAMUDViewThread.Create(AFeed: TAMUDViewFeed);
begin
  inherited Create(false);
  Feed:=AFeed;
end;

procedure TAMUDViewThread.Execute;
var
  i:integer;
begin
  while not Terminated do
    try
      Sleep(100);
      if Feed<>nil then
        for i:=0 to MaxFeeds-1 do
          if AMUDData.FFeeds[i].LastTx<>AMUDData.FFeeds[i].LastTx1 then
           begin
            Feed.SendText(Format('%.4d%s',[i,AMUDData.FFeeds[i].LastTx]));
            AMUDData.FFeeds[i].LastTx1:=AMUDData.FFeeds[i].LastTx;
           end;
        //TODO: clear on fresh disconnect
    except
      //silent
    end;
end;

{ TAMUDViewFeed }

procedure TAMUDViewFeed.ConnectSuccess;
begin
  inherited;
  if AMUDView=nil then
    AMUDView:=TAMUDViewThread.Create(Self)
  else
    if AMUDView.Feed=nil then
      AMUDView.Feed:=Self
    else
     begin
      //SendText();?
      Disconnect;
     end;
end;

destructor TAMUDViewFeed.Destroy;
begin
  AMUDView.Feed:=nil;
  inherited;
end;

initialization
  //see xxmp since that's in CoInit'ed thread
  //AMUDData:=TAMUDData.Create;
  AMUDData:=nil;
  AMUDView:=nil;
finalization
  FreeAndNil(AMUDData);
end.
