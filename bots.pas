unit bots;

interface

uses Windows, SysUtils, Classes, chatbot, jsonDoc;

type
  TAMUDBotCmd=(
    bcNone,
    bcStatement,
    bcCommand
  );

  TAMUDBots=class(TThread)
  private
    FLock:TRTLCriticalSection;
    FBots:array of record
      ItemID,RoomID,DefaultWaitMS:integer;
      Bot:TChatBot;
    end;
    FBotsIndex,FBotsCount:integer;
    FScripts:array of record
      Name:string;
      Bot:TChatBot;
    end;
    FScriptsIndex,FScriptsCount:integer;
    FQueue:array of record
      WaitTC:cardinal;
      RoomID,PersonID,BotID:integer;
      Cmd:TAMUDBotCmd;
      Txt:UTF8String;
    end;
    FQueueIndex,FQueueCount:integer;
    FState:IJSONDocument;
    procedure LoadBots;
    function BotByScriptName(const ScriptName:string):TChatBot;
    procedure QueueInt(WaitMS:cardinal;Cmd:TAMUDBotCmd;
      RoomID,PersonID,BotID:integer;const Txt:UTF8String);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Queue(RoomID,PersonID:integer;const Statement:UTF8String);
  end;

var
  AMUDBots:TAMUDBots;

implementation

uses
  DataLank, ActiveX, feed, tools;

{ TAMUDBots }

constructor TAMUDBots.Create;
begin
  inherited Create(false);
  InitializeCriticalSection(FLock);
  FBotsIndex:=0;
  FBotsCount:=0;
  FScriptsIndex:=0;
  FScriptsCount:=0;
  FQueueIndex:=0;
  FQueueCount:=0;
end;

destructor TAMUDBots.Destroy;
begin
  DeleteCriticalSection(FLock);
  inherited;
end;

procedure TAMUDBots.LoadBots;
var
  qr:TQueryResult;
begin
  FBotsIndex:=0;//?
  qr:=TQueryResult.Create(DbCon,'select * from Bot');
  try
    while qr.Read do
     begin
      if FBotsIndex=FBotsCount then
       begin
        inc(FBotsCount,$20);//growstep
        SetLength(FBots,FBotsCount);
       end;
      FBots[FBotsIndex].ItemID:=qr.GetInt('ItemID');
      FBots[FBotsIndex].RoomID:=qr.GetInt('RoomID');
      FBots[FBotsIndex].DefaultWaitMS:=250;//?
      FBots[FBotsIndex].Bot:=BotByScriptName(qr.GetStr('Script'));
      inc(FBotsIndex);
     end;
  finally
    qr.Free;
  end;
end;

function TAMUDBots.BotByScriptName(const ScriptName: string): TChatBot;
var
  i:integer;
begin
  i:=0;
  //TODO: sorted, a/b-lookup
  while (i<FScriptsIndex) and (FScripts[i].Name<>ScriptName) do inc(i);
  if i=FScriptsIndex then
   begin
    Result:=TChatBot.Create;
    try
      Result.LoadFromFile(BotsPath+ScriptName+'.txt');
    except
      //TODO: log? store? show in-game?
    end;

    if FScriptsIndex=FScriptsCount then
     begin
      inc(FScriptsCount,$20);//growstep
      SetLength(FScripts,FScriptsCount);
     end;
    FScripts[FScriptsIndex].Name:=ScriptName;
    FScripts[FScriptsIndex].Bot:=Result;
    inc(FScriptsIndex);
   end
  else
    Result:=FScripts[i].Bot;
end;

procedure TAMUDBots.Execute;
var
  i,j,l,qi,ms,RoomID,PersonID,BotID,id:integer;
  Cmd:TAMUDBotCmd;
  Txt,s:UTF8String;
  q:UTF8Strings;
  tc:cardinal;
  d:IJSONDocument;
begin
  CoInitialize(nil);
  CheckDBCon;
  FState:=JSON;
  LoadBots;//TODO: schedule periodic refresh? detect change? on signal?
  SetLength(q,0);//counter warning
  while not Terminated do
    try

      EnterCriticalSection(FLock);
      try
        //
        tc:=GetTickCount;
        i:=0;
        while (i<>FQueueIndex) and not(
          (FQueue[i].Cmd<>bcNone) and
          ((FQueue[i].WaitTC=0) or (FQueue[i].WaitTC-tc>$1000000))
        ) do inc(i);
        if i=FQueueIndex then
         begin
          RoomID:=0;
          PersonID:=0;
          BotID:=0;
          Cmd:=bcNone;
          Txt:='';
         end
        else
         begin
          RoomID:=FQueue[i].RoomID;
          PersonID:=FQueue[i].PersonID;
          BotID:=FQueue[i].BotID;
          Cmd:=FQueue[i].Cmd;
          Txt:=FQueue[i].Txt;
          FQueue[i].Cmd:=bcNone;
          FQueue[i].Txt:='';
         end;
      finally
        LeaveCriticalSection(FLock);
      end;

      case Cmd of
        bcStatement:
          for i:=0 to FBotsIndex-1 do
            if FBots[i].RoomID=RoomID then
             begin
              //TODO: not i when storing state but real db BotID
              s:=Format('s%db%d',[PersonID,i]);
              d:=JSON(FState[s]);
              if d=nil then
               begin
                d:=JSON;
                FState[s]:=d;
               end;
              BotID:=FBots[i].ItemID;
              Txt:=FBots[i].Bot.GetNextResponse(Txt,d);

              if Txt<>'' then
                if Txt[1]='|' then
                  Txt:=Copy(Txt,2,Length(Txt))
                else
                  Txt:='s'+ss(Txt);
              q:=Split(Txt,'|');
              for qi:=0 to Length(q)-1 do
                if q[qi]<>'' then
                 begin
                  j:=1;
                  l:=Length(q[qi]);
                  if not(q[qi][1] in ['0'..'9']) then
                    ms:=FBots[i].DefaultWaitMS
                  else
                   begin
                    ms:=0;
                    while (j<=l) and (q[qi][j] in ['0'..'9']) do
                     begin
                      ms:=ms*10+(byte(q[qi][j]) and $F);
                      inc(j);
                     end;
                    if (j<=l) and (q[qi][j]=#$60) then inc(j);
                   end;
                  QueueInt(ms,bcCommand,RoomID,PersonID,BotID,Copy(q[qi],j,l-j+1));
                 end;
             end;
        bcCommand:
          if Txt<>'' then
            case Txt[1] of
              's'://speak
               begin
                if Txt[2]=#$60 then j:=3 else j:=2;
                AMUDData.SendToRoom(RoomID,'s'+ss(BotID)+
                  ss(Copy(Txt,j,Length(Txt)-j+1)));
               end;
              'c'://create
               begin
                q:=Split(Txt,#$60);
                if Length(q)>3 then d:=JSON.Parse(q[3]) else d:=JSON;
                id:=DBCon.Insert('Item',
                  ['what',q[1]
                  ,'ParentID',RoomID
                  ,'name',q[2]
                  //,'key',
                  ,'data',d.ToString
                  ,'createdby',BotID
                  ,'createdon',Now
                  ],'ID');
                AMUDData.SendToRoom(RoomID,'r+'+ss(id)+ss(q[1])+ss(q[2]));
               end;
              'g'://give
               begin
                q:=Split(Txt,#$60);
                if Length(q)>3 then d:=JSON.Parse(q[3]) else d:=JSON;
                id:=DBCon.Insert('Item',
                  ['what',q[1]
                  ,'ParentID',PersonID
                  ,'name',q[2]
                  //,'key',
                  ,'data',d.ToString
                  ,'createdby',BotID
                  ,'createdon',Now
                  ],'ID');
                //AMUDData.SendToPerson(PersonID,qx('i+',id));
                AMUDData.SendToPerson(PersonID,'i+'+ss(id)+ss(q[1])+ss(q[2]));
               end;
              else AMUDData.SendToRoom(RoomID,'s'+ss(FBots[i].ItemID)+
                ss('[Unkown command "'+Txt+'"]'));//TODO error message?
            end;
        else Sleep(10);
      end;
    except
      //silent (log?)
    end;
end;

procedure TAMUDBots.Queue(RoomID,PersonID:integer;const Statement:UTF8String);
begin
  QueueInt(0,bcStatement,RoomID,PersonID,0,Statement);
end;

procedure TAMUDBots.QueueInt(WaitMS:cardinal;Cmd:TAMUDBotCmd;RoomID,
  PersonID,BotID:integer;const Txt:UTF8String);
var
  i:integer;
begin
  EnterCriticalSection(FLock);
  try
    i:=0;
    while (i<>FQueueIndex) and (FQueue[i].Cmd<>bcNone) do inc(i);
    if i=FQueueIndex then
     begin
      inc(FQueueCount,$20);//growstep
      SetLength(FQueue,FQueueCount);
      inc(FQueueIndex);
     end;
    if WaitMS=0 then
      FQueue[i].WaitTC:=0
    else
      FQueue[i].WaitTC:=GetTickCount+WaitMS;
    FQueue[i].RoomID:=RoomID;
    FQueue[i].PersonID:=PersonID;
    FQueue[i].BotID:=BotID;
    FQueue[i].Cmd:=Cmd;
    FQueue[i].Txt:=Txt;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

initialization
  AMUDBots:=nil;
finalization
  //FreeAndNil(AMUDBots);
end.
