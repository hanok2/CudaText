{$ifdef nn}begin end;{$endif}

procedure TATStrings.SaveToStream(AStream: TStream; AEncoding: TATFileEncoding; AWithSignature: boolean);
var
  Item: PATStringItem;
  ItemEnd: TATLineEnds;
  SAnsi, Sign: string;
  SWide: UnicodeString;
  SQuad: UCS4String;
  NLast, i: integer;
begin
  AStream.Size:= 0;
  AStream.Seek(0, soFromBeginning);

  EncConvErrorMode:= eemException;

  if AWithSignature then
  begin
    case FEncoding of
      cEncUTF8:
        Sign:= cSignUTF8;
      cEncWideLE:
        Sign:= cSignWideLE;
      cEncWideBE:
        Sign:= cSignWideBE;
      cEnc32LE:
        Sign:= cSign32LE;
      cEnc32BE:
        Sign:= cSign32BE;
      else
        Sign:= '';
    end;
    if Sign<>'' then
      AStream.WriteBuffer(Sign[1], Length(Sign));
  end;

  NLast:= Count-1;
  for i:= 0 to NLast do
  begin
    Item:= FList.GetItem(i);

    ItemEnd:= Item^.LineEnds;
    //don't break file if ending of some non-last line is unset
    if i<NLast then
      if ItemEnd=cEndNone then
        ItemEnd:= FEndings;

    SWide:= Item^.Line + cLineEndStrings[ItemEnd];

    if SWide<>'' then
    case AEncoding of
      cEncAnsi:
        begin
          SAnsi:= UTF8Encode(SWide);
          SAnsi:= EncConvertFromUTF8(SAnsi, FEncodingCodepage);
          AStream.WriteBuffer(SAnsi[1], Length(SAnsi));
        end;

      cEncUTF8:
        begin
          SAnsi:= UTF8Encode(SWide);
          AStream.WriteBuffer(SAnsi[1], Length(SAnsi));
        end;

      cEncWideLE,
      cEncWideBE:
        begin
          if AEncoding=cEncWideBE then
            SSwapEndianWide(SWide);
          AStream.WriteBuffer(SWide[1], Length(SWide)*2);
        end;

      cEnc32LE,
      cEnc32BE:
        begin
          SQuad:= UnicodeStringToUCS4String(SWide);
          if AEncoding=cEnc32BE then
            SSwapEndianUCS4(SQuad);
          AStream.WriteBuffer(SQuad[0], (Length(SQuad)-1)*4);
        end;

      else
        DoEncError;
    end;

    if (i mod TATEditorOptions.ProgressSaveLines) = TATEditorOptions.ProgressSaveLines div 2 then
    begin
      FProgressKind:= cStringsProgressSaving;
      FProgressValue:= Int64(i)*100 div Count;
      if Assigned(FOnProgress) then
        FOnProgress(Self);
    end;
  end;

  FProgressValue:= 0;
  FProgressKind:= cStringsProgressNone;
end;

function TATStrings.IsSavingWithSignature: boolean;
begin
  case FEncoding of
    cEncAnsi:
      Result:= false;
    cEncUTF8:
      Result:= FSaveSignUtf8;
    cEncWideLE,
    cEncWideBE,
    cEnc32LE,
    cEnc32BE:
      Result:= FSaveSignWide;
    else
      raise Exception.Create('Unknown encoding on saving');
  end;
end;

procedure TATStrings.SaveToFile(const AFilename: string);
var
  fs: TFileStream;
  NMode: word;
begin
  NMode:= fmOpenWrite or fmShareDenyWrite;
  //don't set fmCreate for existing file, to keep NTFS file streams
  if not FileExists(AFilename) then
    NMode:= NMode or fmCreate;

  fs:= TFileStream.Create(AFilename, NMode);
  try
    SaveToStream(fs, FEncoding, IsSavingWithSignature);
  finally
    FreeAndNil(fs);
  end;

  DoFinalizeSaving;
end;

procedure TATStrings.DoFinalizeSaving;
begin
  ClearLineStates(true);

  if not FUndoAfterSave then
    ClearUndo
  else
  begin
    FUndoList.DeleteUnmodifiedMarks;
    FRedoList.DeleteUnmodifiedMarks;
  end;

  Modified:= false;
end;

