(*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

Copyright (c) Alexey Torgashin
*)
unit formconsole;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StrUtils, Menus, LclType,
  PythonEngine,
  ATStrings,
  ATSynEdit,
  ATSynEdit_Options,
  ATSynEdit_Edits,
  ATSynEdit_Commands,
  ATSynEdit_Adapter_Simple,
  ATStringProc,
  ec_SyntAnal,
  ec_syntax_format,
  proc_py,
  proc_str,
  proc_colors,
  proc_globdata,
  proc_customdialog,
  proc_customdialog_dummy,
  proc_msg;

type
  TAppStrEvent = procedure(const Str: string) of object;
  TAppConsoleEvent = function(const Str: string): boolean of object;
  TAppConsoleCommandEvent = procedure(ACommand: integer; const AText: string; var AHandled: boolean) of object;

  TAppConsoleLineKind = (
    acLineUsual,
    acLinePrompt,
    acLineNote,
    acLineError
    );

type
  { TfmConsole }

  //inherit from TFormDummy to support dlg_proc API for this form
  TfmConsole = class(TFormDummy)
  private
    { private declarations }
    FAdapter: TATAdapterSimple;
    FOnNavigate: TAppConsoleEvent;
    FOnNumberChange: TNotifyEvent;
    FCudatextImported: boolean;
    FInputFirstChanged: boolean;
    mnuTextClear: TMenuItem;
    mnuTextNav: TMenuItem;
    mnuTextWrap: TMenuItem;
    procedure InputOnCommand(Sender: TObject; ACmd: integer; AInvoke: TATEditorCommandInvoke; const AText: string; var AHandled: boolean);
    procedure InputOnChange(Sender: TObject);
    procedure DoGetLineColor(Ed: TATSynEdit; ALineIndex: integer; var AColorFont, AColorBg: TColor);
    procedure MemoClickDbl(Sender: TObject; var AHandled: boolean);
    procedure MemoCommand(Sender: TObject; ACmd: integer; AInvoke: TATEditorCommandInvoke; const AText: string; var AHandled: boolean);
    procedure MemoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure DoNavigate(Sender: TObject);
    procedure DoToggleWrap(Sender: TObject);
    function ParseLine(const S: string): TAppConsoleLineKind;
    procedure SetIsDoubleBuffered(AValue: boolean);
    function GetWordWrap: boolean;
    procedure SetWordWrap(AValue: boolean);
    procedure DoRunLine(Str: string);
  public
    { public declarations }
    EdInput: TATComboEdit;
    EdMemo: TATSynEdit;
    ErrorCounter: integer;
    constructor Create(AOwner: TComponent); override;
    property OnConsoleNav: TAppConsoleEvent read FOnNavigate write FOnNavigate;
    property OnNumberChange: TNotifyEvent read FOnNumberChange write FOnNumberChange;
    procedure DoAddLine(const AText: UnicodeString);
    procedure DoClearMemo(Sender: TObject);
    procedure DoClearInput(Sender: TObject);
    procedure DoClearHistory;
    procedure DoUpdateMemo;
    property IsDoubleBuffered: boolean write SetIsDoubleBuffered;
    property MemoWordWrap: boolean read GetWordWrap write SetWordWrap;
    procedure SetFocus; override;
  end;

var
  fmConsole: TfmConsole = nil;

procedure InitConsole;

const
  cConsoleMaxLines = 1000;
  cConsoleMaxComboboxItems: integer = 20;
  cConsolePrompt = '>>> ';
  cConsolePrintPrefix = '=';

implementation

//{$R *.lfm} //not needed for console

function IsConsoleErrorLine(const S: string): boolean;
var
  N, i: integer;
begin
  Result:= false;
  N:= Pos('Error: ', S);
  if N<=1 then exit;
  if S[1]='.' then exit;
  for i:= 1 to N-1 do
    if not (S[i] in ['.', 'a'..'z', 'A'..'Z', '_']) then
      exit;
  Result:= true;
end;

{ TfmConsole }

function TfmConsole.ParseLine(const S: string): TAppConsoleLineKind;
begin
  if StartsStr(cConsolePrompt, S) then
    exit(acLinePrompt);

  if StartsText('NOTE:', S) then
    exit(acLineNote);

  if StartsText('ERROR:', S) then
    exit(acLineError);

  //EndsText is better than compare, to find FindInFiles4 log string added to 'traceback'
  if EndsText('Traceback (most recent call last):', S) then
    exit(acLineError);

  if IsConsoleErrorLine(S) then
    exit(acLineError);

  Result:= acLineUsual;
end;

procedure TfmConsole.DoGetLineColor(Ed: TATSynEdit; ALineIndex: integer;
  var AColorFont, AColorBg: TColor);
var
  Str: UnicodeString;
  fmt: TecSyntaxFormat;
begin
  Str:= Ed.Strings.Lines[ALineIndex];
  case ParseLine(Str) of
    acLinePrompt:
      begin
        fmt:= GetAppStyle(apstId2);
        AColorFont:= fmt.Font.Color;
        exit;
      end;
    acLineNote:
      begin
        fmt:= GetAppStyle(apstLightBG2);
        AColorBg:= fmt.BgColor;
        fmt:= GetAppStyle(apstId);
        AColorFont:= fmt.Font.Color;
        exit
      end;
    acLineError:
      begin
        fmt:= GetAppStyle(apstLightBG1);
        AColorBg:= fmt.BgColor;
        fmt:= GetAppStyle(apstId);
        AColorFont:= fmt.Font.Color;
        exit
      end;
  end;
end;

procedure TfmConsole.DoAddLine(const AText: UnicodeString);
var
  Strs: TATStrings;
  i: integer;
begin
  with EdMemo do
  begin
    ModeReadOnly:= false;
    Strs:= Strings;

    //this is to remove 1st empty line
    if (Strs.Count=1) and (Strs.LinesLen[0]=0) then
      Strs.Lines[0]:= AText
    else
    begin
      Strs.LineAddRaw_NoUndo(AText, cEndUnix);
      for i:= 1 to Strs.Count-cConsoleMaxLines do
        Strs.LineDelete(0, false, false, false);
    end;

    ModeReadOnly:= true;

    if ParseLine(AText) in [acLineError, acLineNote] then
    begin
      Inc(ErrorCounter);
      if Assigned(FOnNumberChange) then
        FOnNumberChange(Self);
    end;
  end;
end;

procedure TfmConsole.DoUpdateMemo;
//This must be called after some DoAddLine calls
//
//Note: don't call Application.ProcessMessages here!
// https://github.com/Alexey-T/CudaText/issues/2326
begin
  with EdMemo do
  begin
    //we added some lines directly to EdMemo.Strings, so update WrapInfo
    UpdateWrapInfo(true);
    DoCommand(cCommand_GotoTextEnd, cInvokeAppInternal);
    ColumnLeft:= 0;

    //console was not repainted with "renderer_anti_flicker":20, this fixes it:
    InvalidateEx(true, false);
  end;
end;

procedure TfmConsole.SetFocus;
begin
  inherited;
  EdInput.SetFocus;
end;

procedure TfmConsole.DoRunLine(Str: string);
var
  Obj: PPyObject;
  bNoLog: boolean;
  bExpr: boolean;
begin
  bNoLog:= EndsStr(';', Str);
  if bNoLog then
    Delete(Str, Length(Str), 1)
  else
    EdInput.DoAddLineToHistory(Utf8Decode(Str), cConsoleMaxComboboxItems);

  DoAddLine(cConsolePrompt+Str);
  DoUpdateMemo;

  try
    if StartsStr(cConsolePrintPrefix, Str) then
    begin
      Str:= 'print('+Copy(Str, 2, MaxInt) + ')';
      bExpr:= false;
    end
    else
      bExpr:= IsPythonExpression(Str);

    if not FCudatextImported then
    begin
      FCudatextImported:= true;
      AppPython.Exec('from cudatext import *');
    end;

    Obj:= AppPython.Eval(Str, not bExpr);
    //if 2nd param is True, this won't return PyObject

    if Assigned(Obj) then
      with AppPython.Engine do
      try
        if Pointer(Obj)<>Pointer(Py_None) then
          MsgLogConsole(PyObjectAsString(Obj));
      finally
        Py_DECREF(Obj);
      end;
  except
  end;
end;

constructor TfmConsole.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  ShowInTaskBar:= stNever;
  BorderStyle:= bsNone;
  IsDlgCounterIgnored:= true;

  FAdapter:= TATAdapterSimple.Create(Self);
  FAdapter.OnGetLineColor:= @DoGetLineColor;

  EdInput:= TATComboEdit.Create(Self);
  EdInput.Name:= 'input';
  EdInput.Parent:= Self;
  EdInput.Align:= alBottom;
  EdInput.WantTabs:= false;
  EdInput.TabStop:= true;
  EdInput.OnCommand:= @InputOnCommand;
  EdInput.OnChange:= @InputOnChange;

  EdInput.OptTabSize:= 4;
  EdInput.OptBorderWidth:= 1;
  EdInput.OptBorderWidthFocused:= 1;

  EdMemo:= TATSynEdit.Create(Self);
  EdMemo.Name:= 'memo';
  EdMemo.Parent:= Self;
  EdMemo.Align:= alClient;
  EdMemo.BorderStyle:= bsNone;

  EdMemo.WantTabs:= false;
  EdMemo.TabStop:= true;
  EdMemo.AdapterForHilite:= FAdapter;

  IsDoubleBuffered:= UiOps.DoubleBuffered;

  EdMemo.OptWrapMode:= cWrapOn;
  EdMemo.OptScrollbarsNew:= EditorOps.OpScrollbarsNew;
  EdMemo.OptUndoLimit:= 0;

  EdMemo.OptTabSize:= 4;
  EdMemo.OptBorderFocusedActive:= EditorOps.OpActiveBorderInControls;
  EdMemo.OptBorderWidthFocused:= ATEditorScale(EditorOps.OpActiveBorderWidth);
  EdMemo.OptBorderWidth:= 0;
  EdMemo.OptShowURLs:= false;
  EdMemo.OptCaretVirtual:= false;
  EdMemo.OptCaretManyAllowed:= false;
  EdMemo.OptGutterVisible:= false;
  EdMemo.OptRulerVisible:= false;
  EdMemo.OptUnprintedVisible:= false;
  EdMemo.OptMarginRight:= 2000;
  EdMemo.ModeReadOnly:= true;
  EdMemo.OptMouseRightClickMovesCaret:= true;
  EdMemo.OptMouseWheelZooms:= false;
  EdMemo.OptShowMouseSelFrame:= false;

  //support dlg_proc API, it needs PropsObject
  DoControl_InitPropsObject(EdInput, Self, 'editor_edit');
  DoControl_InitPropsObject(EdMemo, Self, 'editor');

  EdMemo.OnClickDouble:= @MemoClickDbl;
  EdMemo.OnCommand:= @MemoCommand;
  //after DoControl_InitPropsObject, because it did set custom OnContextMenu
  EdMemo.OnContextPopup:= @MemoContextPopup;
end;


procedure InitConsole;
begin
  if fmConsole=nil then
    fmConsole:= TfmConsole.Create(nil);
end;

procedure TfmConsole.InputOnCommand(Sender: TObject; ACmd: integer;
  AInvoke: TATEditorCommandInvoke; const AText: string; var AHandled: boolean);
var
  s: string;
begin
  if ACmd=cCommand_KeyEnter then
  begin
    s:= UTF8Encode(EdInput.Text);
    DoRunLine(s);

    EdInput.Text:= '';
    EdInput.DoCaretSingle(0, 0);

    AHandled:= true;
    Exit
  end;

  //if Assigned(FOnEditCommand) then
  //  FOnEditCommand(ACmd, AText, AHandled);
end;

function TfmConsole.GetWordWrap: boolean;
begin
  Result:= EdMemo.OptWrapMode=cWrapOn;
end;

procedure TfmConsole.DoClearMemo(Sender: TObject);
begin
  EdMemo.ModeReadOnly:= false;
  EdMemo.Text:= '';
  EdMemo.DoCaretSingle(0, 0);
  EdMemo.ModeReadOnly:= true;

  ErrorCounter:= 0;
  if Assigned(FOnNumberChange) then
    FOnNumberChange(Self);
end;

procedure TfmConsole.DoClearInput(Sender: TObject);
begin
  EdInput.DoCommand(cCommand_GotoTextBegin, cInvokeAppInternal);
  EdInput.DoCommand(cCommand_TextDeleteToTextEnd, cInvokeAppInternal);
  EdInput.DoCaretSingle(0, 0);
end;

procedure TfmConsole.DoClearHistory;
begin
  EdInput.Items.Clear;
end;

procedure TfmConsole.DoNavigate(Sender: TObject);
var
  S: string;
  N: integer;
begin
  if Assigned(FOnNavigate) then
  begin
    N:= EdMemo.Carets[0].PosY;
    if not EdMemo.Strings.IsIndexValid(N) then exit;
    S:= EdMemo.Strings.Lines[N];
    FOnNavigate(S);
  end;
end;

procedure TfmConsole.DoToggleWrap(Sender: TObject);
begin
  MemoWordWrap:= not MemoWordWrap;
end;

procedure TfmConsole.MemoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  if mnuTextClear=nil then
  begin
    mnuTextClear:= TMenuItem.Create(Self);
    mnuTextClear.OnClick:= @DoClearMemo;
    EdMemo.PopupTextDefault.Items.Add(mnuTextClear);

    mnuTextWrap:= TMenuItem.Create(Self);
    mnuTextWrap.OnClick:= @DoToggleWrap;
    EdMemo.PopupTextDefault.Items.Add(mnuTextWrap);

    mnuTextNav:= TMenuItem.Create(Self);
    mnuTextNav.OnClick:= @DoNavigate;
    EdMemo.PopupTextDefault.Items.Add(mnuTextNav);
  end;

  mnuTextClear.Caption:= msgConsoleClear;
  mnuTextWrap.Caption:= msgConsoleToggleWrap;
  mnuTextNav.Caption:= msgConsoleNavigate;
  mnuTextWrap.Checked:= MemoWordWrap;

  Handled:= false;
end;

procedure TfmConsole.InputOnChange(Sender: TObject);
begin
  if not FInputFirstChanged then
  begin
    if Assigned(FOnNavigate) then
      FOnNavigate('(console_input_change)');
  end;
  FInputFirstChanged:= true;
end;

procedure TfmConsole.SetIsDoubleBuffered(AValue: boolean);
begin
  EdInput.DoubleBuffered:= AValue;
  EdMemo.DoubleBuffered:= AValue;
end;

procedure TfmConsole.SetWordWrap(AValue: boolean);
begin
  if AValue then
    EdMemo.OptWrapMode:= cWrapOn
  else
    EdMemo.OptWrapMode:= cWrapOff;
  //EdMemo.OptAllowScrollbarHorz:= not AValue;
  EdMemo.Update;
end;

procedure TfmConsole.MemoCommand(Sender: TObject; ACmd: integer;
  AInvoke: TATEditorCommandInvoke; const AText: string; var AHandled: boolean);
begin
  if ACmd=cCommand_KeyEnter then
  begin
    MemoClickDbl(nil, AHandled);
    AHandled:= true;
  end;
end;


procedure TfmConsole.MemoClickDbl(Sender: TObject; var AHandled: boolean);
var
  s: string;
  n: integer;
begin
  n:= EdMemo.Carets[0].PosY;
  if EdMemo.Strings.IsIndexValid(n) then
  begin
    s:= EdMemo.Strings.Lines[n];
    if StartsStr(cConsolePrompt, s) then
    begin
      Delete(s, 1, Length(cConsolePrompt));
      DoRunLine(s);
    end
    else
      DoNavigate(Self);
  end;
  AHandled:= true;
end;

finalization
  if Assigned(fmConsole) then
    FreeAndNil(fmConsole);

end.

