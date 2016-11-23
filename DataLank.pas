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
  DBConPath,LogPath:string;

threadvar
  DBCon: TDataConnection;

procedure CheckDBCon;
procedure CloseAllDBCon;

implementation

uses Windows, SysUtils, Classes;

var
  DBConChain:TDataConnection;

procedure GetPaths;
var
  s:string;
begin
  SetLength(s,MAX_PATH);
  SetLength(s,GetModuleFileName(HInstance,PChar(s),MAX_PATH));
  DBConPath:=ChangeFileExt(s,'.db');
  LogPath:=ExtractFilePath(s)+'log\';
  DBConChain:=nil;
end;

procedure CheckDBCon;
begin
  if DBCon=nil then
   begin
    DBCon:=TDataConnection.Create(DBConPath);
    //TODO: lock!
    DBCon.FNext:=DBConChain;
    DBConChain:=DBCon;
   end;
  //else check state,transaction?
end;

procedure CloseAllDBCon;
var
  c:TDataConnection;
begin
  c:=DBConChain;
  while c<>nil do
   begin
    try
      c:=c.FNext;
      c.Free;//close? disconnect?
    except
      //silent
    end;
   end;
end;

initialization
  GetPaths;
end.
