{$ifdef nnn}begin end;{$endif}

function TATSynEdit.DoCommand_TextTabulation: TATCommandResults;
var
  N1, N2: integer;
  bBlockSel: boolean;
begin
  Result:= [];
  if ModeReadOnly then Exit;

  //multiline selection?
  //instead of tabulation, do indent
  if FOptKeyTabIndents then
  begin
    if not IsSelRectEmpty then
      bBlockSel:= FOptKeyTabIndentsVerticalBlock
    else
    if Carets.Count<>1 then
      bBlockSel:= false
    else
    begin
      Carets[0].GetSelLines(N1, N2);
      bBlockSel:= (N1>=0) and (N2>N1);
    end;

    if bBlockSel then
      Exit(DoCommand_TextIndentUnindent(true));
  end;

  if FOptTabSpaces then
    Result:= DoCommand_TextInsertTabSpacesAtCarets(FOverwrite)
  else
    Result:= DoCommand_TextInsertAtCarets(#9, false, FOverwrite, false, false);
end;


function TATSynEdit.DoCommand_TextInsertAtCarets(const AText: atString;
  AKeepCaret, AOvrMode, ASelectThen, AInsertAtLineStarts: boolean
  ): TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  Shift, PosAfter: TPoint;
  TextItems: TStringList;
  TextItem: atString;
  X1, Y1, X2, Y2, X_saved: integer;
  bSel, bNeedGroup, bInsertLinePerCaret: boolean;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  TextItems:= nil;
  St:= Strings;

  try
    //bNeedGroup:= (Carets.Count>1) or (Carets.IsSelection);
    bNeedGroup:= false; //CudaText issue #3274
    bInsertLinePerCaret:= false;

    if bNeedGroup then
      St.BeginUndoGroup;

    //TextItems allows to insert each clipboard line into its own caret
    //when count of carets = count of clipboard lines
    if FOptPasteMultilineTextSpreadsToCarets then
      if (AText<>sLineBreak) and (Length(AText)>1) and (Carets.Count>1) then
        if SCountTextLines(AText, sLineBreak) = Carets.Count then
        begin
          TextItems:= TStringList.Create;
          TextItems.Text:= UTF8Encode(AText);
          bInsertLinePerCaret:= Carets.Count=TextItems.Count;
          //if Carets.Count<>TextItems.Count then
          //  raise Exception.CreateFmt('Unexpected lines count in clipboard text (found %d, expected %d)',
          //    [TextItems.Count, Carets.Count]);
        end;

    //avoid 2 non-compatable modes of paste
    if bInsertLinePerCaret then
      AInsertAtLineStarts:= false;

    for i:= Carets.Count-1 downto 0 do
    begin
      Caret:= Carets[i];
      Caret.GetRange(X1, Y1, X2, Y2, bSel);

      X_saved:= -1;
      if AInsertAtLineStarts and not bSel then
      begin
        if not ASelectThen then
          X_saved:= X1;
        X1:= 0;
      end;

      if bInsertLinePerCaret then
        TextItem:= UTF8Decode(TextItems[i])
      else
        TextItem:= AText;

      if bSel then
        St.TextReplaceRange(X1, Y1, X2, Y2, TextItem, Shift, PosAfter, false)
      else
        St.TextInsert(X1, Y1, TextItem, AOvrMode, Shift, PosAfter);
      DoCaretsShift(i+1, X1, Y1, Shift.X, Shift.Y, PosAfter);

      if not AKeepCaret then
      begin
        Caret.EndX:= IfThen(ASelectThen, X1, -1);
        Caret.EndY:= IfThen(ASelectThen, Y1, -1);
        Caret.PosX:= PosAfter.X;
        Caret.PosY:= PosAfter.Y;
        if X_saved>=0 then
          Caret.PosX:= X_saved;
      end;
    end;
  finally
    if Assigned(TextItems) then
      FreeAndNil(TextItems);
    if bNeedGroup then
      St.EndUndoGroup;
  end;

  //changed for issue CudaText#3065
  Result:= [cResultText, cResultCaretBottom, cResultCaretLazy];
end;

function TATSynEdit.DoCommand_TextInsertTabSpacesAtCarets(AOvrMode: boolean): TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  Shift, PosAfter: TPoint;
  StrSpaces: atString;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;

  St:= Strings;
  St.BeginUndoGroup;

  try
    DoSelectionDeleteOrReset;

    for i:= Carets.Count-1 downto 0 do
    begin
      Caret:= Carets[i];
      StrSpaces:= StringOfCharW(' ', FTabSize - Caret.PosX mod FTabSize);
      St.TextInsert(Caret.PosX, Caret.PosY, StrSpaces, AOvrMode, Shift, PosAfter);
      DoCaretsShift(i, Caret.PosX, Caret.PosY, Shift.X, Shift.Y, PosAfter);

      Caret.PosX:= PosAfter.X;
      Caret.PosY:= PosAfter.Y;
      Caret.EndX:= -1;
      Caret.EndY:= -1;
    end;
  finally
    St.EndUndoGroup;
  end;

  Result:= [cResultText, cResultCaretBottom];
end;

function TATSynEdit.DoCalcIndentCharsFromPrevLines(AX, AY: integer): integer;
var
  St: TATStrings;
  Str: atString;
  NIndent, i: integer;
begin
  Result:= -1;
  St:= Strings;
  if not St.IsIndexValid(AY) then Exit;

  //allow smart unindent only if caret on 1st nonspace char
  //(else Bksp must delete 1 char)
  Str:= St.Lines[AY];
  NIndent:= SGetIndentChars(Str);
  if not ((AX=NIndent) and (NIndent>0)) then Exit;

  //calc indent of N prev lines.
  //if indent<AX then ok
  for i:= 1 to FOptMaxLinesToCountUnindent do
  begin
    Dec(AY);
    if not St.IsIndexValid(AY) then Exit;

    Str:= St.Lines[AY];
    NIndent:= SGetIndentChars(Str);
    if NIndent<AX then
      Exit(NIndent);
  end;
end;

function TATSynEdit.DoCommand_TextDeleteLeft(ADeleteLen: integer; AAllowUnindent: boolean): TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  Shift, PosAfter: TPoint;
  NIndent, NDeleteLen: integer;
  bNeedGroup: boolean;
  bChange, bChangeOne: boolean;
  ch: WideChar;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  //selection? delete it, exit.
  if Carets.IsSelection then
  begin
    Result:= DoCommand_TextDeleteSelection;
    Exit
  end;

  bNeedGroup:= Carets.Count>1;
  if bNeedGroup then
    St.BeginUndoGroup;

  bChange:= false;

  for i:= 0 to Carets.Count-1 do
  begin
    Caret:= Carets[i];
    if not St.IsIndexValid(Caret.PosY) then Continue;
    NDeleteLen:= ADeleteLen;

    if AAllowUnindent then
    begin
      NIndent:= DoCalcIndentCharsFromPrevLines(Caret.PosX, Caret.PosY);
      if NIndent>=0 then
        if Caret.PosX>NIndent then
          NDeleteLen:= Caret.PosX-NIndent
        else
          NDeleteLen:= Caret.PosX;
    end;

    //handle deletion of emoji (2 surrogate chars: high+low)
    if Caret.PosX>1 then
    begin
      ch:= St.LineCharAt(Caret.PosY, Caret.PosX);
      if IsCharSurrogateLow(ch) then
        Inc(NDeleteLen);
    end;

    St.TextDeleteLeft(Caret.PosX, Caret.PosY, NDeleteLen, Shift, PosAfter, FOptKeyBackspaceGoesToPrevLine, bChangeOne);
    DoCaretsShift(i, Caret.PosX, Caret.PosY, Shift.X, Shift.Y, PosAfter);
    Caret.PosX:= PosAfter.X;
    Caret.PosY:= PosAfter.Y;
    Caret.EndX:= -1;
    Caret.EndY:= -1;

    if bChangeOne then
      bChange:= true;
  end;

  if bNeedGroup then
    St.EndUndoGroup;

  //changed for CudaText issue #3065
  Result:= [cResultCaretTop, cResultCaretLazy];
  //changed for CudaText issue #3883
  if bChange then
    Include(Result, cResultText);
end;

function TATSynEdit.DoCommand_TextDelete: TATCommandResults;
var
  bColBlock: boolean;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  bColBlock:= not IsSelRectEmpty;

  if bColBlock then
    if FSelRect.Left=FSelRect.Right then
    begin
      DoSelect_None;
      bColBlock:= false;
    end;

  if bColBlock or Carets.IsSelection then
    Result:= DoCommand_TextDeleteSelection
  else
    Result:= DoCommand_TextDeleteRight(1);
end;


function TATSynEdit.DoCommand_TextDeleteSelection: TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  Shift, PosAfter: TPoint;
  X1, Y1, X2, Y2: integer;
  bSel: boolean;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  if not IsSelRectEmpty and not OptCaretManyAllowed then
  begin
    DoSelectionDeleteColumnBlock;
    Result:= [cResultText, cResultCaretTop];
    Exit
  end;

  if not Carets.IsSelection then Exit;

  St.BeginUndoGroup;
  try
    for i:= Carets.Count-1 downto 0 do
    begin
      Caret:= Carets[i];
      Caret.GetRange(X1, Y1, X2, Y2, bSel);

      if Assigned(FMarkers) then
        FMarkers.DeleteInRange(X1, Y1, X2, Y2);

      if Assigned(FAttribs) then
        FAttribs.DeleteInRange(X1, Y1, X2, Y2);

      St.TextDeleteRange(X1, Y1, X2, Y2, Shift, PosAfter);

      Caret.PosX:= X1;
      Caret.PosY:= Y1;
      Caret.EndX:= -1;
      Caret.EndY:= -1;

      //tested on these cases:
      //CudaText issue #1615
      //CudaText issue #2261
      DoCaretsShift(i, X1, Y1, Shift.X, Shift.Y, PosAfter);
    end;
  finally
    St.EndUndoGroup;
  end;

  //CudaText issue #1615
  Carets.Sort;

  Result:= [cResultText, cResultCaretTop];
end;


function TATSynEdit.DoCommand_TextDeleteRight(ADeleteLen: integer): TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  NLineLen, NDeleteLen, ShiftBelowX: integer;
  Shift, PosAfter: TPoint;
  bNeedGroup: boolean;
  ch: WideChar;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  //selection? delete it, exit.
  if Carets.IsSelection then
  begin
    Result:= DoCommand_TextDeleteSelection;
    exit
  end;

  bNeedGroup:= Carets.Count>1;
  if bNeedGroup then
    St.BeginUndoGroup;

  for i:= 0 to Carets.Count-1 do
  begin
    Caret:= Carets[i];
    if not St.IsIndexValid(Caret.PosY) then Continue;

    //offsetX for carets in line[PosY+1]
    ShiftBelowX:= 0;
    NLineLen:= St.LinesLen[Caret.PosY];
    if Caret.PosX=NLineLen then
      ShiftBelowX:= NLineLen;

    NDeleteLen:= ADeleteLen;

    //handle deletion of emoji (2 surrogate chars: high+low)
    ch:= St.LineCharAt(Caret.PosY, Caret.PosX+1);
    if IsCharSurrogateHigh(ch) then
      Inc(NDeleteLen);

    St.TextDeleteRight(Caret.PosX, Caret.PosY, NDeleteLen, Shift, PosAfter);
    DoCaretsShift(i, Caret.PosX, Caret.PosY, Shift.X, Shift.Y, PosAfter, ShiftBelowX);
    Caret.PosX:= PosAfter.X;
    Caret.PosY:= PosAfter.Y;
  end;

  if bNeedGroup then
    St.EndUndoGroup;

  Result:= [cResultText, cResultCaretAny];
end;

function TATSynEdit.DoCommand_TextInsertEol(AKeepCaret: boolean): TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  Shift, PosAfter: TPoint;
  Str: atString;
  bNeedGroup, bBetterBrackets: boolean;
  NShiftX, NShiftY, i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  if ModeOneLine then Exit;

  St:= Strings;
  bNeedGroup:= Carets.Count>1;

  if bNeedGroup then
    St.BeginUndoGroup;

  DoSelectionDeleteOrReset;

  for i:= FCarets.Count-1 downto 0 do
  begin
    Caret:= FCarets[i];
    if not St.IsIndexValid(Caret.PosY) then Continue;

    NShiftX:= 0;
    NShiftY:= 0;
    bBetterBrackets:= false;

    Str:= St.Lines[Caret.PosY];
    if (Caret.PosX>0) and (Caret.PosX<Length(Str)) then
    begin
      Str:= Copy(Str, Caret.PosX, 2);
      if (FOptAutoIndentBetterBracketsCurly and (Str='{}')) or
         (FOptAutoIndentBetterBracketsRound and (Str='()')) or
         (FOptAutoIndentBetterBracketsSquare and (Str='[]')) then
        bBetterBrackets:= true;
    end;

    Str:= GetAutoIndentString(Caret.PosX, Caret.PosY, not bBetterBrackets);
    St.TextInsertEol(Caret.PosX, Caret.PosY, AKeepCaret, Str, Shift, PosAfter);

    //work to move } to next line, leave caret at current line
    if bBetterBrackets then
    begin
      St.LineInsert(Caret.PosY+1, Str+GetIndentString);
      NShiftX:= Length(GetIndentString);
      NShiftY:= 1;
    end;

    DoCaretsShift(i, Caret.PosX, Caret.PosY, Shift.X+NShiftX, Shift.Y+NShiftY, PosAfter);
    Caret.PosX:= PosAfter.X+NShiftX;
    Caret.PosY:= PosAfter.Y;
    //on Enter reset prev column for up/down
    Caret.SavedX:= 0;
  end;

  if bNeedGroup then
    St.EndUndoGroup;

  Result:= [cResultText, cResultCaretBottom];
end;

function TATSynEdit.DoCommand_TextDeleteLines: TATCommandResults;
var
  St: TATStrings;
  Caret: TATCaretItem;
  Shift, PosAfter: TPoint;
  NLineFrom, NLineTo: integer;
  iCaret, iLine: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  St.BeginUndoGroup;
  try
    DoCaretsDeleteOnSameLines;

    for iCaret:= Carets.Count-1 downto 0 do
    begin
      Caret:= Carets[iCaret];
      if not St.IsIndexValid(Caret.PosY) then Continue;
      Caret.GetSelLines(NLineFrom, NLineTo, true);

      //Caret.PosX:= 0;
      Caret.PosY:= NLineFrom;
      Caret.EndX:= -1;
      Caret.EndY:= -1;

      for iLine:= NLineTo downto NLineFrom do
      begin
        St.TextDeleteLine(0, iLine, Shift, PosAfter);
        DoCaretsShift(iCaret, 0, iLine, Shift.X, Shift.Y, PosAfter);
      end;
    end;

    DoCaretsFixIncorrectPos(false);
  finally
    St.EndUndoGroup;
  end;

  Result:= [cResultText, cResultCaretTop];
end;

function TATSynEdit.DoCommand_TextDuplicateLine: TATCommandResults;
var
  St: TATStrings;
  Caret: TATCaretItem;
  Line1, Line2, iCaret, iLine: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;

  DoCaretsDeleteOnSameLines;

  St:= Strings;
  St.BeginUndoGroup;
  try
    for iCaret:= Carets.Count-1 downto 0 do
    begin
      Caret:= Carets[iCaret];
      if not St.IsIndexValid(Caret.PosY) then Continue;

      //universal code, for selection or not
      Caret.GetSelLines(Line1, Line2, true);
      if St.LinesEnds[Line2]=cEndNone then
        St.LinesEnds[Line2]:= St.Endings;
      for iLine:= Line2 downto Line1 do
      begin
        St.LineInsert(Line2+1, St.Lines[iLine]);
        St.LinesEnds[Line2+1]:= St.Endings;
      end;

      DoCaretsShift(iCaret+1, Caret.PosX, Caret.PosY, 0, (Line2-Line1+1), Point(0, 0));
    end;
  finally
    St.EndUndoGroup;
  end;

  Result:= [cResultText, cResultCaretTop];
end;

function TATSynEdit.DoCommand_TextDeleteToLineBegin: TATCommandResults;
var
  St: TATStrings;
  Str: atString;
  Caret: TATCaretItem;
  bChange: boolean;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  DoCaretsDeleteOnSameLines;
  bChange:= false;
  St:= Strings;

  for i:= FCarets.Count-1 downto 0 do
  begin
    Caret:= FCarets[i];
    if not St.IsIndexValid(Caret.PosY) then Continue;
    if Caret.PosX=0 then Continue;
    Str:= St.Lines[Caret.PosY];
    if Str='' then Continue;
    Delete(Str, 1, Caret.PosX);
    St.Lines[Caret.PosY]:= Str;
    Caret.PosX:= 0;
    bChange:= true;
  end;

  Result:= [cResultCaretLeft];
  if bChange then
    Include(Result, cResultText);
end;

function TATSynEdit.DoCommand_TextDeleteToLineEnd: TATCommandResults;
var
  St: TATStrings;
  Str: atString;
  Caret: TATCaretItem;
  bChange: boolean;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  DoCaretsDeleteOnSameLines;
  bChange:= false;
  St:= Strings;

  for i:= FCarets.Count-1 downto 0 do
  begin
    Caret:= FCarets[i];
    if not St.IsIndexValid(Caret.PosY) then Continue;
    if Caret.PosX<St.LinesLen[Caret.PosY] then
    begin
      Str:= St.Lines[Caret.PosY];
      SetLength(Str, Caret.PosX);
      St.Lines[Caret.PosY]:= Str;
      bChange:= true;
    end;
  end;

  Result:= [cResultCaretAny];
  if bChange then
    Include(Result, cResultText);
end;

function TATSynEdit.DoCommand_TextDeleteWord(ANext: boolean): TATCommandResults;
const
  cWordJumps: array[boolean] of TATWordJump =
    (cWordjumpToPrev, cWordjumpToNext);
var
  Caret: TATCaretItem;
  St: TATStrings;
  Str: atString;
  Shift, PosAfter: TPoint;
  bNeedGroup: boolean;
  bChange, bChangeOne: boolean;
  iCaret: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  bChange:= false;
  St:= Strings;

  bNeedGroup:= Carets.Count>1;
  if bNeedGroup then
    St.BeginUndoGroup;

  for iCaret:= FCarets.Count-1 downto 0 do
  begin
    Caret:= FCarets[iCaret];
    if not St.IsIndexValid(Caret.PosY) then Continue;
    Str:= St.Lines[Caret.PosY];
    Shift.X:= 0;
    Shift.Y:= 0;
    PosAfter.X:= Caret.PosX;
    PosAfter.Y:= Caret.PosY;

    //delete to prev line?
    if (Caret.PosX=0) and (not ANext) then
    begin
      St.TextDeleteLeft(Caret.PosX, Caret.PosY, 1, Shift, PosAfter, FOptKeyBackspaceGoesToPrevLine, bChangeOne);
      if bChangeOne then
        bChange:= true;
    end
    else
    //delete to next line?
    if (Caret.PosX>=Length(Str)) and ANext then
    begin
      St.TextDeleteRight(Caret.PosX, Caret.PosY, 1, Shift, PosAfter);
      bChange:= true;
    end
    else
    //jump from beyond eol to eol?
    if (Caret.PosX>Length(Str)) and (not ANext) then
    begin
      Caret.PosX:= Length(Str);
      PosAfter.X:= Caret.PosX;
    end
    else
    //delete inside line?
    if (Caret.PosX<=Length(Str)) then
    begin
      PosAfter.X:= SFindWordOffset(Str, Caret.PosX, cWordJumps[ANext], false, FOptNonWordChars);
      if PosAfter.X<>Caret.PosX then
      begin
        System.Delete(Str, Min(Caret.PosX, PosAfter.X)+1, Abs(Caret.PosX-PosAfter.X));
        St.Lines[Caret.PosY]:= Str;
        Shift.X:= -Abs(Caret.PosX-PosAfter.X);
        PosAfter.X:= Min(Caret.PosX, PosAfter.X);
        bChange:= true;
      end;
    end;

    DoCaretsShift(iCaret, Caret.PosX, Caret.PosY, Shift.X, Shift.Y, PosAfter);

    if ((Caret.PosX<>PosAfter.X) or (Caret.PosY<>PosAfter.Y)) and
      (FCarets.IndexOfPosXY(PosAfter.X, PosAfter.Y)>=0) then
    begin
      if FCarets.Count>1 then
        FCarets.Delete(iCaret);
    end
    else
    begin
      Caret.PosX:= PosAfter.X;
      Caret.PosY:= PosAfter.Y;
    end;
  end;

  if bNeedGroup then
    St.EndUndoGroup;

  //cResultCaretLazy is to fix CudaText #3065
  if ANext then
    Result:= [cResultCaretBottom, cResultCaretLazy]
  else
    Result:= [cResultCaretTop, cResultCaretLazy];

  if bChange then
    Include(Result, cResultText);
end;

function TATSynEdit.DoCommand_TextDeleteWordEntire: TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  Str: atString;
  Shift, PosAfter: TPoint;
  bNeedGroup: boolean;
  NLen, N1, N2, i: integer;
  bChange: boolean;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  bChange:= false;
  bNeedGroup:= Carets.Count>1;
  if bNeedGroup then
    St.BeginUndoGroup;

  for i:= FCarets.Count-1 downto 0 do
  begin
    Caret:= FCarets[i];
    if not St.IsIndexValid(Caret.PosY) then Continue;
    Str:= St.Lines[Caret.PosY];
    NLen:= Length(Str);

    N1:= Caret.PosX;
    N2:= N1;

    //command is supposed to delete word-chars, so avoid using SFindWordOffset()
    if N1<0 then
      Continue;
    if N1>=NLen then
    begin
      Caret.PosX:= NLen;
      Continue;
    end;
    if not IsCharWord(Str[N1+1]) then
      Continue;

    while (N1>0) and IsCharWord(Str[N1]) do
      Dec(N1);
    while (N2<NLen) and IsCharWord(Str[N2+1]) do
      Inc(N2);

    if N1=N2 then Continue;
    System.Delete(Str, N1+1, N2-N1);
    if St.Lines[Caret.PosY]<>Str then
    begin
      St.Lines[Caret.PosY]:= Str;
      bChange:= true;
    end;

    Shift.X:= N1-N2;
    Shift.Y:= 0;
    PosAfter.X:= N1;
    PosAfter.Y:= Caret.PosY;
    Caret.PosX:= N1;

    DoCaretsShift(i, Caret.PosX, Caret.PosY, Shift.X, Shift.Y, PosAfter);
  end;

  if bNeedGroup then
    St.EndUndoGroup;

  Result:= [cResultCaretBottom];
  if bChange then
    Include(Result, cResultText);
end;


function TATSynEdit.DoCommand_TextIndentUnindent(ARight: boolean): TATCommandResults;
begin
  Result:= [];
  if ModeReadOnly then exit;
  if Strings.Count=0 then exit;
  if Carets.Count=0 then exit;

  if IsSelRectEmpty then
    Result:= DoCommand_TextIndentUnindent_StreamBlock(ARight)
  else
    Result:= DoCommand_TextIndentUnindent_ColumnBlock(ARight);
end;

function TATSynEdit.DoCommand_TextIndentUnindent_StreamBlock(ARight: boolean): TATCommandResults;
var
  bChange, bChangeOne: boolean;
  i: integer;
begin
  DoCaretsDeleteOnSameLines;

  bChange:= false;
  bChangeOne:= false;

  for i:= Carets.Count-1 downto 0 do
  begin
    DoCommand_TextIndentUnindent_StreamBlock_OneCaret(ARight, Carets[i], bChangeOne);
    if bChangeOne then
      bChange:= true;
  end;

  Result:= [cResultCaretAny];
  if bChange then
    Include(Result, cResultText);
end;

procedure TATSynEdit.DoCommand_TextIndentUnindent_StreamBlock_OneCaret(ARight: boolean;
  Caret: TATCaretItem; out ATextChanged: boolean);
var
  St: TATStrings;
  Str: atString;
  NDecSpaces, NMinSpaces, i: integer;
  NShift1, NShift2, NShiftChars, NIndentChars1, NIndentChars2: integer;
  NBlockBeginY, NBlockEndY: integer;
begin
  ATextChanged:= false;
  St:= Strings;
  Caret.PosY:= Min(Caret.PosY, St.Count-1);
  Caret.EndY:= Min(Caret.EndY, St.Count-1);

  Caret.GetSelLines(NBlockBeginY, NBlockEndY, true{Allow no sel});
  if NBlockBeginY<0 then exit;
  if Caret.EndY<0 then
  begin
    Caret.EndX:= Caret.PosX;
    Caret.EndY:= Caret.PosY;
  end;

  if FOptIndentSize=0 then
  begin
    NDecSpaces:= FTabSize;
    if FOptTabSpaces then
      NShiftChars:= FTabSize
    else
      NShiftChars:= 1;
  end
  else
  if FOptIndentSize>0 then
  begin
    NDecSpaces:= FOptIndentSize;
    NShiftChars:= FOptIndentSize;
  end
  else
  begin
    NDecSpaces:= Abs(FOptIndentSize)*FTabSize;
    NShiftChars:= Abs(FOptIndentSize);
  end;

  //calc minimal indent of all
  NMinSpaces:= MaxInt;
  for i:= NBlockBeginY to NBlockEndY do
  begin
    //don't skip blank-only lines, like ST3
    Str:= St.Lines[i];
    NMinSpaces:= Min(NMinSpaces, FTabHelper.GetIndentExpanded(i, Str));
  end;
  if NMinSpaces=MaxInt then Exit;

  //consider "Unindent keeps align"
  if FOptIndentKeepsAlign then
    if (not ARight) and (NMinSpaces<NDecSpaces) then Exit;

  if ARight then
  begin
    NShift1:= IfThen(Caret.PosX>0, NShiftChars, 0);
    NShift2:= IfThen(Caret.EndX>0, NShiftChars, 0);
  end
  else
  begin
    NIndentChars1:= SGetIndentChars(St.Lines[Caret.PosY]);
    NIndentChars2:= SGetIndentChars(St.Lines[Caret.EndY]);
    NShift1:= -Min(NIndentChars1, NShiftChars);
    NShift2:= -Min(NIndentChars2, NShiftChars);
  end;

  //do indent
  St.BeginUndoGroup;
  try
    for i:= NBlockBeginY to NBlockEndY do
    begin
      Str:= St.Lines[i];
      Str:= FTabHelper.IndentUnindent(i, Str, ARight);
      if St.Lines[i]<>Str then
      begin
        St.Lines[i]:= Str;
        ATextChanged:= true;
      end;
    end;
  finally
    St.EndUndoGroup;
  end;

  //correct selection
  if FOptIndentMakesWholeLinesSelection then
  begin
    Caret.EndX:= 0;
    Caret.EndY:= NBlockBeginY;
    if St.IsIndexValid(NBlockEndY+1) then
    begin
      Caret.PosX:= 0;
      Caret.PosY:= NBlockEndY+1;
    end
    else
    begin
      Caret.PosY:= NBlockEndY;
      Caret.PosX:= St.LinesLen[NBlockEndY];
    end;
  end
  else
  begin
    if Caret.PosX>0 then
      Caret.PosX:= Max(0, Caret.PosX+NShift1);
    if Caret.EndX>0 then
      Caret.EndX:= Max(0, Caret.EndX+NShift2);
  end;
end;


function TATSynEdit.DoCommand_TextIndentUnindent_ColumnBlock(ARight: boolean): TATCommandResults;
var
  St: TATStrings;
  Str: atString;
  NBlockBeginY, NBlockEndY, NIndentAtCol: integer;
  bChange: boolean;
  i: integer;
begin
  St:= Strings;
  NBlockBeginY:= Min(SelRect.Top, St.Count-1);
  NBlockEndY:= Min(SelRect.Bottom, St.Count-1);
  NIndentAtCol:= SelRect.Left;
  bChange:= false;

  St.BeginUndoGroup;
  try
    for i:= NBlockBeginY to NBlockEndY do
    begin
      Str:= St.Lines[i];
      if Trim(Str)='' then Continue;

      Str:= Copy(Str, 1, NIndentAtCol) +
            FTabHelper.IndentUnindent(
              i,
              Copy(Str, NIndentAtCol+1, MaxInt),
              ARight);

      if St.Lines[i]<>Str then
      begin
        St.Lines[i]:= Str;
        bChange:= true;
      end;
    end;
  finally
    St.EndUndoGroup;
  end;

  Result:= [cResultCaretAny, cResultKeepColumnSel];
  if bChange then
    Include(Result, cResultText);
end;


function TATSynEdit.DoCommand_UndoRedo(AUndo: boolean): TATCommandResults;
//undo/redo runs App.ProcessMessages, need to lock
var
  St: TATStrings;
  bLock, bFocus: boolean;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  if AUndo then
  begin
    if St.UndoEmpty then Exit;
    bLock:= (GetUndoCount>0) and (OptUndoPause>0);
  end
  else
  begin
    if St.RedoEmpty then Exit;
    bLock:= (GetRedoCount>0) and (OptUndoPause>0);
  end;

  if bLock then
  begin
    bFocus:= _IsFocused;
    Enabled:= false;
  end;

  FLastUndoTick:= 0;

  try
    if not AUndo then
      St.SetGroupMark;

    St.UndoOrRedo(AUndo, FOptUndoGrouped)
  finally
    if bLock then
    begin
      Enabled:= true;
      if bFocus and CanSetFocus then
        SetFocus;
    end;
  end;

  Result:= [cResultText, cResultCaretBottom, cResultCaretLazy, cResultUndoRedo];
end;


function TATSynEdit.DoCommand_TextInsertColumnBlockOnce(const AText: string;
  AKeepCaret: boolean): TATCommandResults;
var
  Caret: TATCaretItem;
  Block: TATStrings;
begin
  Result:= [];
  if ModeReadOnly then Exit;

  //cannot handle carets/selections for colblock
  DoCaretSingleAsIs;
  DoSelect_None;
  Caret:= FCarets[0];

  Block:= TATStrings.Create(FOptUndoLimit);
  try
    Block.LoadFromString(AText);
    Block.ActionDeleteFakeLine;
    if Block.Count=0 then Exit;

    Strings.TextInsertColumnBlock(Caret.PosX, Caret.PosY, Block, FOverwrite);

    //fix limiting of resulting carets-column (OptCaretPosAfterPasteColumn=cPasteCaretColumnRight)
    //by short lines, CudaText issue #3826
    UpdateWrapInfo(true{AForceUpdate});

    if not AKeepCaret then
      case FOptCaretPosAfterPasteColumn of
        cPasteCaretNoChange:
          begin
          end;
        cPasteCaretLeftBottom:
          begin
            Inc(Caret.PosY, Block.Count-1);
          end;
        cPasteCaretRightBottom:
          begin
            Inc(Caret.PosX, Block.LinesLen[0]);
            Inc(Caret.PosY, Block.Count-1);
          end;
        cPasteCaretRightTop:
          begin
            Inc(Caret.PosX, Block.LinesLen[0]);
          end;
        cPasteCaretColumnLeft:
          begin
            DoCaretsColumnToPoint(Caret.PosX, Caret.PosY + Block.Count-1);
          end;
        cPasteCaretColumnRight:
          begin
            Inc(Caret.PosX, Block.LinesLen[0]);
            DoCaretsColumnToPoint(Caret.PosX, Caret.PosY + Block.Count-1);
          end;
      end;
  finally
    FreeAndNil(Block);
  end;

  Result:= [cResultText, cResultCaretBottom];
end;

function TATSynEdit.DoCommand_TextDeleteToDocumentBegin: TATCommandResults;
var
  Caret: TATCaretItem;
  St: TATStrings;
  Str: atString;
  Shift, PosAfter: TPoint;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  DoCaretSingleAsIs;
  Caret:= FCarets[0];

  St.ChangeBlockActive:= true;
  St.DoOnChangeBlock(
    0, 0,
    Caret.PosX, Caret.PosY,
    cBlockDeleteLines,
    nil
    );

  if Caret.PosX>0 then
  begin
    Str:= St.Lines[Caret.PosY];
    Delete(Str, 1, Caret.PosX);
    St.Lines[Caret.PosY]:= Str;
  end;

  //do it with fast method, not "for loop"
  if Caret.PosY>0 then
    St.TextDeleteRange(0, 0, 0, Caret.PosY, Shift, PosAfter);

  St.ChangeBlockActive:= false;

  //move caret to beginning
  DoCaretSingle(0, 0);

  Result:= [cResultText, cResultCaretBottom];
end;


function TATSynEdit.DoCommand_TextDeleteToDocumentEnd: TATCommandResults;
var
  St: TATStrings;
  Caret: TATCaretItem;
  Shift, PosAfter: TPoint;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;

  DoCaretSingleAsIs;
  Caret:= FCarets[0];

  St.ChangeBlockActive:= true;
  St.DoOnChangeBlock(
    Caret.PosX, Caret.PosY,
    0, St.Count,
    cBlockDeleteLines,
    nil
    );

  St.TextDeleteRange(Caret.PosX, Caret.PosY, 0, St.Count, Shift, PosAfter);

  if Caret.PosY>=St.Count-1 then
    St.LinesEnds[Caret.PosY]:= cEndNone;

  St.ChangeBlockActive:= false;

  Result:= [cResultText, cResultCaretBottom];
end;


function TATSynEdit.DoCommand_TextInsertEmptyAboveBelow(ADown: boolean): TATCommandResults;
var
  Caret: TATCaretItem;
  PosAfter: TPoint;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;

  DoCaretsDeleteOnSameLines;

  for i:= Carets.Count-1 downto 0 do
  begin
    Caret:= Carets[i];
    Strings.LineInsert(Caret.PosY + IfThen(ADown, 1), '');

    PosAfter.X:= 0;
    PosAfter.Y:= Caret.PosY+IfThen(ADown, 1);

    DoCaretsShift(i, 0, Caret.PosY, 0, 1, PosAfter);

    Caret.PosX:= PosAfter.X;
    Caret.PosY:= PosAfter.Y;
  end;

  Result:= [cResultText, cResultCaretAny];
end;

function TATSynEdit.DoCommand_TextChangeCase(AMode: TATEditorCaseConvert): TATCommandResults;
var
  St: TATStrings;
  Caret: TATCaretItem;
  Str1, Str2: atString;
  X1, Y1, X2, Y2: integer;
  Shift, PosAfter: TPoint;
  bSel, bChange: boolean;
  i: integer;
begin
  Result:= [];
  if ModeReadOnly then Exit;
  St:= Strings;
  bChange:= false;

  St.BeginUndoGroup;
  try
    for i:= Carets.Count-1 downto 0 do
    begin
      Caret:= Carets[i];
      if not St.IsIndexValid(Caret.PosY) then Continue;
      Caret.GetRange(X1, Y1, X2, Y2, bSel);
      if not bSel then
      begin
        SFindWordBounds(St.Lines[Caret.PosY], Caret.PosX, X1, X2, FOptNonWordChars);
        if X1<0 then Continue;
        Y1:= Caret.PosY;
        Y2:= Caret.PosY;
      end;

      Str1:= St.TextSubstring(X1, Y1, X2, Y2);
      case AMode of
        cCaseLower:
          Str2:= UnicodeLowerCase(Str1);
        cCaseUpper:
          Str2:= UnicodeUpperCase(Str1);
        cCaseTitle:
          Str2:= SCaseTitle(Str1, FOptNonWordChars);
        cCaseInvert:
          Str2:= SCaseInvert(Str1);
        cCaseSentence:
          Str2:= SCaseSentence(Str1, FOptNonWordChars);
      end;

      if Str1<>Str2 then
      begin
        St.TextReplaceRange(X1, Y1, X2, Y2, Str2, Shift, PosAfter, false);
        bChange:= true;
      end;
    end;
  finally
    St.EndUndoGroup;
  end;

  Result:= [cResultCaretAny];
  if bChange then
    Include(Result, cResultText);
end;


function TATSynEdit.DoCommand_TextTrimSpaces(AMode: TATTrimSpaces): TATCommandResults;
begin
  Result:= [];
  if ModeReadOnly then Exit;

  if Strings.ActionTrimSpaces(AMode) then
  begin
    DoCaretsFixIncorrectPos(true);
    Result:= [cResultCaretAny, cResultText];
  end;
end;

function TATSynEdit.DoCommand_ForceFinalEndOfLine: TATCommandResults;
var
  St: TATStrings;
begin
  if ModeReadOnly then exit([]);

  St:= Strings;
  if St.ActionEnsureFinalEol then
  begin
    St.ActionAddFakeLineIfNeeded;
    Result:= [cResultText];
  end
  else
    Result:= [];
end;

function TATSynEdit.DoCommand_DeleteFinalEndOfLine: TATCommandResults;
var
  St: TATStrings;
  N: integer;
begin
  if ModeReadOnly then exit([]);

  St:= Strings;
  N:= St.Count;
  if (N>0) and (St.LinesLen[N-1]=0) then
  begin
    St.ActionDeleteFakeLineAndFinalEol;
    Result:= [cResultText];
  end
  else
    Result:= [];
end;

function TATSynEdit.DoCommand_Sort(AAction: TATStringsSortAction): TATCommandResults;
var
  Caret: TATCaretItem;
  NFrom, NTo: integer;
begin
  if ModeReadOnly then exit([]);

  NFrom:= -1;
  NTo:= -1;
  if Carets.Count>0 then
  begin
    Caret:= Carets[0];
    Caret.GetSelLines(NFrom, NTo);
  end;

  Strings.ActionSort(AAction, NFrom, NTo);
  Result:= [cResultText];
end;

function TATSynEdit.DoCommand_DeleteAllBlanks: TATCommandResults;
begin
  if ModeReadOnly then exit([]);
  DoCaretSingle(0, 0);
  if Strings.ActionDeleteAllBlanks then
    Result:= [cResultText, cResultCaretTop]
  else
    Result:= [cResultCaretTop];
end;

function TATSynEdit.DoCommand_DeleteAdjacentBlanks: TATCommandResults;
begin
  if ModeReadOnly then exit([]);
  DoCaretSingle(0, 0);
  if Strings.ActionDeleteAdjacentBlanks then
    Result:= [cResultText, cResultCaretTop]
  else
    Result:= [cResultCaretTop]
end;

function TATSynEdit.DoCommand_DeleteAdjacentDups: TATCommandResults;
begin
  if ModeReadOnly then exit([]);
  DoCaretSingle(0, 0);
  if Strings.ActionDeleteAdjacentDups then
    Result:= [cResultText, cResultCaretTop]
  else
    Result:= [cResultCaretTop];
end;

function TATSynEdit.DoCommand_DeleteAllDups(AKeepBlanks: boolean): TATCommandResults;
begin
  if ModeReadOnly then exit([]);
  DoCaretSingle(0, 0);
  if Strings.ActionDeleteAllDups(AKeepBlanks) then
    Result:= [cResultText, cResultCaretTop]
  else
    Result:= [cResultCaretTop];
end;

function TATSynEdit.DoCommand_ReverseLines: TATCommandResults;
begin
  if ModeReadOnly then exit([]);
  DoCaretSingle(0, 0);
  Strings.ActionReverseLines;
  Result:= [cResultText, cResultCaretTop];
end;

function TATSynEdit.DoCommand_ShuffleLines: TATCommandResults;
begin
  if ModeReadOnly then exit([]);
  DoCaretSingle(0, 0);
  Strings.ActionShuffleLines;
  Result:= [cResultText, cResultCaretTop];
end;

