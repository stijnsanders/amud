program bottest;

uses
  Forms,
  bottest1 in 'bottest1.pas' {frmBotTest},
  jsonDoc in '..\jsonDoc.pas',
  chatbot in '..\chatbot.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmBotTest, frmBotTest);
  Application.Run;
end.
