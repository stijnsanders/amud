object frmBotTest: TfrmBotTest
  Left = 192
  Top = 125
  Width = 433
  Height = 384
  BorderWidth = 4
  Caption = 'BotTest'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -16
  Font.Name = 'Georgia'
  Font.Style = []
  OldCreateOrder = False
  Position = poDefaultPosOnly
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 18
  object Splitter1: TSplitter
    Left = 0
    Top = 172
    Width = 409
    Height = 4
    Cursor = crVSplit
    Align = alBottom
  end
  object txtConversation: TMemo
    Left = 0
    Top = 176
    Width = 409
    Height = 130
    Align = alBottom
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 1
  end
  object txtState: TMemo
    Left = 0
    Top = 0
    Width = 409
    Height = 172
    Align = alClient
    Lines.Strings = (
      '{}')
    ScrollBars = ssBoth
    TabOrder = 2
    WordWrap = False
  end
  object txtInput: TMemo
    Left = 0
    Top = 306
    Width = 409
    Height = 31
    Align = alBottom
    TabOrder = 0
    WordWrap = False
    OnKeyPress = txtInputKeyPress
  end
  object OpenDialog1: TOpenDialog
    DefaultExt = 'txt'
    Filter = 'ChatBot script (*.txt)|*.txt|All files (*.*)|*.*'
    InitialDir = '.'
    Title = 'Load ChatBot Script'
    Left = 16
    Top = 16
  end
end
