unit DataLank;

{

DataLank
  Allows straight-forward (but not perfect) switching of data back-ends
  in projects with limited database requirements.

https://github.com/stijnsanders/DataLank

}

interface

uses SQLiteData;

type
  //TDataConnection = TSQLiteConnection;
  TDataConnection = class(TSQLiteConnection)
  private
    FNext:TDataConnection;
  end;
  TQueryResult = TSQLiteStatement;

var
  DBConPath,LogPath,BotsPath:string;

threadvar
  DBCon: TDataConnection;

procedure CheckDBCon;
procedure CloseAllDBCon;

implementation

uses Windows, SysUtils, Classes;

var
  DBConChainLock:TRTLCriticalSection;
  DBConChain:TDataConnection;

procedure GetPaths;
var
  s:string;
begin
  SetLength(s,MAX_PATH);
  SetLength(s,GetModuleFileName(HInstance,PChar(s),MAX_PATH));
  DBConPath:=ChangeFileExt(s,'.db');
  LogPath:=ExtractFilePath(s)+'log\';
  BotsPath:=ExtractFilePath(s)+'bots\';
  DBConChain:=nil;
end;

procedure CheckDBCon;
begin
  if DBCon=nil then
   begin
    DBCon:=TDataConnection.Create(DBConPath);
    EnterCriticalSection(DBConChainLock);
    try
      DBCon.FNext:=DBConChain;
      DBConChain:=DBCon;
    finally
      LeaveCriticalSection(DBConChainLock);
    end;
   end;
  //else check state,transaction?
end;

procedure CloseAllDBCon;
var
  c,d:TDataConnection;
begin
  EnterCriticalSection(DBConChainLock);
  try
    c:=DBConChain;
    while c<>nil do
     begin
      try
        d:=c;
        c:=c.FNext;
        d.Free;//close? disconnect?
      except
        //silent
      end;
     end;
  finally
    LeaveCriticalSection(DBConChainLock);
  end;
end;

initialization
  InitializeCriticalSection(DBConChainLock);
  GetPaths;
finalization
  DeleteCriticalSection(DBConChainLock);
end.
