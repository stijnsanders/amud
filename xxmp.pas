unit xxmp;

{
  xxm Project

This is a default xxm Project class inheriting from TXxmProject. You are free to change this one for your project.
Use LoadPage to process URL's as a requests is about to start.
(Be carefull with sending content from here though.)
It is advised to link each request to a session here, if you want session management.
(See  an example xxmSession.pas in the public folder.)
Use LoadFragment to handle calls made to Context.Include.

  $Rev: 331 $ $Date: 2014-06-20 23:12:52 +0200 (vr, 20 jun 2014) $
}

interface

uses xxm;

type
  TXxmamud=class(TXxmProject, IXxmProjectEvents1)
  protected
    function HandleException(Context: IXxmContext; PageClass,
      ExceptionClass, ExceptionMessage: WideString): boolean;
    procedure ReleasingContexts;
    procedure ReleasingProject;
  public
    procedure AfterConstruction; override;
    function LoadPage(Context: IXxmContext; Address: WideString): IXxmFragment; override;
    function LoadFragment(Context: IXxmContext; Address, RelativeTo: WideString): IXxmFragment; override;
    procedure UnloadFragment(Fragment: IXxmFragment); override;
  end;

function XxmProjectLoad(AProjectName:WideString): IXxmProject; stdcall;

implementation

uses xxmFReg, DataLank, feed, bots;

function XxmProjectLoad(AProjectName:WideString): IXxmProject;
begin
  Result:=TXxmamud.Create(AProjectName);
end;

{ TXxmamud }

procedure TXxmamud.AfterConstruction;
begin
  inherited;
  AMUDData:=TAMUDData.Create;
  AMUDBots:=TAMUDBots.Create;
end;

function TXxmamud.LoadPage(Context: IXxmContext; Address: WideString): IXxmFragment;
begin
  inherited;
  //TODO: link session to request

  Context.BufferSize:=$1000;
  Context.AutoEncoding:=aeUTF8;
  CheckDbCon;


  if Address='feed' then
    Result:=TAMUDDataFeed.Create(Self)
  else if Address='view' then
    Result:=TAMUDViewFeed.Create(Self)
  else
    Result:=XxmFragmentRegistry.GetFragment(Self,Address,'');
  //TODO: if Context.ContextString(csVerb)='OPTION' then...
end;

function TXxmamud.LoadFragment(Context: IXxmContext; Address, RelativeTo: WideString): IXxmFragment;
begin
  Result:=XxmFragmentRegistry.GetFragment(Self,Address,RelativeTo);
end;

procedure TXxmamud.UnloadFragment(Fragment: IXxmFragment);
begin
  inherited;
  //TODO: set cache TTL, decrease ref count
  //Fragment.Free;
end;

function TXxmamud.HandleException(Context: IXxmContext; PageClass,
  ExceptionClass, ExceptionMessage: WideString): boolean;
begin
  Result:=false;
end;

procedure TXxmamud.ReleasingContexts;
begin
  try
    if AMUDView<>nil then AMUDView.Terminate;
    if AMUDBots<>nil then AMUDBots.Terminate;
    AMUDData.CloseAllFeeds;
  except
    //silent
  end;
  try
    CloseAllDBCon;
  except
    //silent
  end;
end;

procedure TXxmamud.ReleasingProject;
begin
  //
end;

initialization
  IsMultiThread:=true;
  Randomize;
end.
