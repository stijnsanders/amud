unit bottest1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls;

type
  TfrmBotTest = class(TForm)
    txtConversation: TMemo;
    txtState: TMemo;
    OpenDialog1: TOpenDialog;
    Splitter1: TSplitter;
    txtInput: TMemo;
    procedure txtInputKeyPress(Sender: TObject; var Key: Char);
    procedure FormShow(Sender: TObject);
  private
    FScriptFilePath:string;
  end;

var
  frmBotTest: TfrmBotTest;

implementation

uses
  jsonDoc, chatbot;

{$R *.dfm}

procedure TfrmBotTest.FormShow(Sender: TObject);
begin
  if ParamCount=0 then
    if OpenDialog1.Execute then
      FScriptFilePath:=OpenDialog1.FileName
    else
      Application.Terminate
  else
    FScriptFilePath:=ParamStr(1);
end;

procedure TfrmBotTest.txtInputKeyPress(Sender: TObject; var Key: Char);
var
  s:string;
  d:IJSONDocument;
  bot:TChatBot;
begin
  if Key=#13 then
   begin
    Key:=#0;
    s:=txtInput.Text;
    txtInput.Text:='';

    d:=JSON.Parse(txtState.Text);

    bot:=TChatBot.Create;
    try
      bot.LoadFromFile(FScriptFilePath);

      txtConversation.Lines.Add('< '+s);
      txtConversation.Lines.Add('> '+bot.GetNextResponse(s,d));
      txtConversation.Perform(EM_SCROLLCARET,0,0);
      txtConversation.Perform(EM_LINESCROLL,0,txtConversation.Lines.Count);

      txtState.Text:=d.ToString;
    finally
      bot.Free;
    end;

   end;
end;

end.
