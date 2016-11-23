unit tools;

interface

uses SysUtils, DataLank;

function ss(i:integer):UTF8String; overload;
function ss(const x:UTF8String):UTF8String; overload;
function ss(const x:WideString):UTF8String; overload;
function ix(qr:TQueryResult;const Prefix:UTF8String):UTF8String;
function qx(id:integer;const Prefix:UTF8String):UTF8String;
function nx(id:integer;const Key:UTF8String):boolean;

type
  UTF8Strings=array of UTF8String;

function Split(const Data,Separator:UTF8String):UTF8Strings;
function RKey(Len:integer):UTF8String;

implementation

function ss(i:integer):UTF8String; overload;
begin
  Result:=Format(#$60'%d',[i]);
end;

function ss(const x:UTF8String):UTF8String; overload;
var
  i,l:integer;
begin
  Result:=#$60+x;
  l:=Length(Result);
  for i:=2 to l do
    if Result[i]=#$60 then Result[i]:=#$27;
end;

function ss(const x:WideString):UTF8String; overload;
var
  i,l:integer;
begin
  Result:=#$60+UTF8Encode(x);
  l:=Length(Result);
  for i:=2 to l do
    if Result[i]=#$60 then Result[i]:=#$27;
end;

function ix(qr:TQueryResult;const Prefix:UTF8String):UTF8String;
begin
  Result:=Prefix
    +ss(qr.GetInt('ID'))
    +ss(qr.GetStr('what'))
    +ss(qr.GetStr('name'))
    //+ss(qr.GetStr('data'))//don't make this public!!!
    ;
  //TODO: more?
end;

function qx(id:integer;const Prefix:UTF8String):UTF8String;
var
  qr:TQueryResult;
begin
  qr:=TQueryResult.Create(DBCon,'select * from Item where ID=?',[id]);
  try
    Result:=ix(qr,Prefix);
  finally
    qr.Free;
  end;
end;

function nx(id:integer;const Key:UTF8String):boolean;
var
  qr:TQueryResult;
begin
  qr:=TQueryResult.Create(DBCon,'select ID from Item where ParentID=? and key=?',[id,Key]);
  try
    Result:=qr.EOF;
  finally
    qr.Free;
  end;
end;

function Split(const Data,Separator:UTF8String):UTF8Strings;
var
  ri,rx,i,j,k,l,m:integer;
const
  rGrowStep=32;
begin
  ri:=0;
  rx:=0;
  i:=1;
  l:=Length(Data);
  m:=Length(Separator);
  while i<=l do
   begin
    j:=i;
    k:=0;
    while (j<=l) and (k<>m) do
     begin
      k:=0;
      while (j+k<=l) and (k<>m) and (Data[j+k]=Separator[k+1]) do inc(k);
      if k<>m then inc(j);
     end;
    if ri=rx then
     begin
      inc(rx,rGrowStep);
      SetLength(Result,rx);
     end;
    Result[ri]:=Copy(Data,i,j-i);
    inc(ri);
    i:=j+m;
   end;
  SetLength(Result,ri);
end;

function RKey(Len:integer):UTF8String;
const
  KeyMap='0123456789abcdefghjklmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
var
  i:integer;
begin
  SetLength(Result,Len);
  for i:=1 to Len do Result[i]:=KeyMap[Trunc(Random*Length(KeyMap))+1];
end;

end.
