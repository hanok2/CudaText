{
Copyright (C) Alexey Torgashin, uvviewsoft.com
License: MPL 2.0 or LGPL
}

{$mode objfpc}{$H+}
{$ModeSwitch advancedrecords}

{$I atsynedit_defines.inc}

unit ATSynEdit;

interface

uses
  {$ifdef Windows}
  Windows, Messages,
  ATSynEdit_Adapter_IME,
  {$endif}
  InterfaceBase,
  Classes, SysUtils, Graphics,
  Controls, ExtCtrls, Menus, Forms, Clipbrd,
  syncobjs, gdeque,
  LMessages, LCLType, LCLVersion,
  LazUTF8,
  EncConv,
  BGRABitmap,
  BGRABitmapTypes,
  ATStringProc,
  ATStringProc_Separator,
  ATStrings,
  ATStringProc_WordJump,
  ATCanvasPrimitives,
  ATSynEdit_Options,
  ATSynEdit_CharSizer,
  {$ifdef USE_FPC_REGEXPR}
  RegExpr,
  {$else}
  ATSynEdit_RegExpr,
  {$endif}
  ATSynEdit_Colors,
  ATSynEdit_Keymap,
  ATSynEdit_LineParts,
  ATSynEdit_CanvasProc,
  ATSynEdit_Carets,
  ATSynEdit_Markers,
  ATSynEdit_Gutter,
  ATSynEdit_Gutter_Decor,
  ATSynEdit_WrapInfo,
  ATSynEdit_Bookmarks,
  ATSynEdit_Ranges,
  ATSynEdit_DimRanges,
  ATSynEdit_Gaps,
  ATSynEdit_Hotspots,
  ATSynEdit_Micromap,
  ATSynEdit_Adapters,
  ATSynEdit_LinkCache,
  ATSynEdit_FGL,
  ATScrollBar;

{$ifdef LCLGTK2}
  {$if (LCL_FULLVERSION >= 2030000)}
    {$define GTK2_IME_CODE}
  {$endif}
{$endif}

type
  TATPoint64 = record
    X, Y: Int64
  end;

  TATRect64 = record
    Left, Top, Right, Bottom: Int64;
  end;

type
  TATEditorCommandInvoke = (
    cInvokeInternal,
    cInvokeHotkey,
    cInvokeHotkeyChar,
    cInvokeMenuContext,
    cInvokeMenuMain,
    cInvokeMenuAPI,
    cInvokeAppInternal,
    cInvokeAppPalette,
    cInvokeAppToolbar,
    cInvokeAppSidebar,
    cInvokeAppCharMap,
    cInvokeAppDragDrop,
    cInvokeAppAPI
    );

const
  cEditorCommandInvoke: array[TATEditorCommandInvoke] of string = (
    'int',
    'key',
    'key_char',
    'menu_ctx',
    'menu_main',
    'menu_api',
    'app_int',
    'app_pal',
    'app_toolbar',
    'app_sidebar',
    'app_charmap',
    'app_dragdrop',
    'app_api'
    );

type
  TATEditorCommandLogItem = record
  public
    ItemInvoke: TATEditorCommandInvoke;
    ItemCode: integer;
    //don't use 'string' here! it gives crashes on freeing of editor objects
    ItemText: string[220];
  end;

  { TATEditorCommandLog }

  TATEditorCommandLog = class(specialize TDeque<TATEditorCommandLogItem>)
  public
    MaxCount: integer;
    constructor Create;
    procedure Add(ACode: integer; AInvoke: TATEditorCommandInvoke; const AText: string);
  end;

  TATEditorWheelRecord = record
    Kind: (wqkVert, wqkHorz, wqkZoom);
    Delta: integer;
  end;

  //TATEditorWheelQueue = specialize TQueue<TATEditorWheelRecord>;

type
  TATTokenKind = (
    atkOther,
    atkComment,
    atkString
    );

  TATEditorScrollbarStyle = (
    aessHide,
    aessShow,
    aessAuto
    );

  TATEditorMiddleClickAction = (
    mcaNone,
    mcaScrolling,
    mcaPaste,
    mcaGotoDefinition
    );

  TATEditorPosDetails = record
    EndOfWrappedLine: boolean;
    OnGapItem: TATGapItem;
    OnGapPos: TPoint;
  end;

  TATEditorDoubleClickAction = (
    cMouseDblClickNone,
    cMouseDblClickSelectWordChars,
    cMouseDblClickSelectAnyChars,
    cMouseDblClickSelectEntireLine
    );

  TATEditorMouseAction = (
    cMouseActionNone,
    cMouseActionClickSimple,
    cMouseActionClickRight,
    cMouseActionClickAndSelNormalBlock,
    cMouseActionClickAndSelVerticalBlock,
    cMouseActionClickMiddle,
    cMouseActionMakeCaret,
    cMouseActionMakeCaretsColumn
    );

  TATEditorMouseActionRecord = record
    MouseState: TShiftState;
    MouseActionId: TATEditorMouseAction;
  end;

  TATEditorMouseActions = array of TATEditorMouseActionRecord;

  TATFoldBarState = (
    cFoldbarNone,
    cFoldbarBegin,
    cFoldbarEnd,
    cFoldbarMiddle
    );

  TATFoldBarProps = record
    State: TATFoldBarState;
    IsPlus: boolean;
    IsLineUp: boolean;
    IsLineDown: boolean;
    HiliteLines: boolean;
  end;

  TATFoldBarPropsArray = array of TATFoldBarProps;

  TATEditorDirection = (
    cDirNone,
    cDirLeft,
    cDirRight,
    cDirUp,
    cDirDown
    );

  TATEditorRulerNumeration = (
    cRulerNumeration_0_10_20,
    cRulerNumeration_1_11_21,
    cRulerNumeration_1_10_20
    );

  TATEditorSelectColumnDirection = (
    cDirColumnLeft,
    cDirColumnRight,
    cDirColumnUp,
    cDirColumnDown,
    cDirColumnPageUp,
    cDirColumnPageDown
    );

  TATEditorScrollbarsArrowsKind = (
    cScrollArrowsNormal,
    cScrollArrowsHidden,
    cScrollArrowsAbove,
    cScrollArrowsBelow,
    cScrollArrowsCorner
    );

  TATEditorCaseConvert = (
    cCaseLower,
    cCaseUpper,
    cCaseTitle,
    cCaseInvert,
    cCaseSentence
    );

  TATCommandResult = (
    cResultText,             //Text was changed.
    cResultFoldChange,       //Folding range(s) were changed or folded/unfolded.
    cResultCaretAny,         //Caret(s) pos/selection was changed. Don't scroll to caret.
    cResultCaretLeft,        //Caret(s) pos/selection was changed. Scroll to the most left caret.
    cResultCaretTop,         //Caret(s) pos/selection was changed. Scroll to the first caret.
    cResultCaretRight,       //Caret(s) pos/selection was changed. Scroll to the most right caret.
    cResultCaretBottom,      //Caret(s) pos/selection was changed. Scroll to the last caret.
    cResultCaretLazy,  //Additional to CaretLeft/CaretRight/CaretTop/CaretBottom, scrolls only if no carets are left in visible area.
    cResultCaretFarFromEdge, //Before running the command, caret was far from both vertical edges
    cResultKeepColumnSel,    //Restore previous column selection, if command changed it.
    cResultScroll,           //Some scrolling was made.
    cResultUndoRedo,         //Undo or Redo action was made.
    cResultState             //Some properties of editor were changed (e.g. word-wrap state).
    );
  TATCommandResults = set of TATCommandResult;

  TATEditorGapCoordAction = (
    cGapCoordIgnore,
    cGapCoordToLineEnd,
    cGapCoordMoveDown
    );

  TATEditorGutterIcons = (
    cGutterIconsPlusMinus,
    cGutterIconsTriangles
    );

  TATEditorPasteCaret = (
    cPasteCaretNoChange,
    cPasteCaretLeftBottom,
    cPasteCaretRightBottom,
    cPasteCaretRightTop,
    cPasteCaretColumnLeft,
    cPasteCaretColumnRight
    );

  TATEditorFoldStyle = ( //affects folding of blocks without "text hint" passed from adapter
    cFoldHereWithDots, //show "..." from fold-pos
    cFoldHereWithTruncatedText, //show truncated line instead of "..."
    cFoldFromEndOfLine, //looks like Lazarus: show "..." after line, bad with 2 blocks starting at the same line
    cFoldFromEndOfLineAlways, //same, even if HintText not empty
    cFoldFromNextLine //looks like SynWrite: don't show "...", show separator line
    );

  TATEditorFoldRangeCommand = (
    cFoldingFold,
    cFoldingUnfold,
    cFoldingToggle
    );

  TATEditorStapleEdge = (
    cStapleEdgeNone,
    cStapleEdgeAngle,
    cStapleEdgeLine
    );

type
  TATEditorAutoIndentKind = (
    cIndentAsPrevLine,
    cIndentSpacesOnly,
    cIndentTabsAndSpaces,
    cIndentTabsOnly,
    cIndentToOpeningBracket
    );

  TATEditorPageDownSize = (
    cPageSizeFull,
    cPageSizeFullMinus1,
    cPageSizeHalf
    );

  TATEditorWrapMode = (
    cWrapOff,
    cWrapOn,
    cWrapAtWindowOrMargin
    );

  TATEditorNumbersStyle = (
    cNumbersAll,
    cNumbersNone,
    cNumbersEach10th,
    cNumbersEach5th,
    cNumbersRelative
    );

  TATEditorInternalFlag = (
    cIntFlagBitmap,
    cIntFlagScrolled,
    cIntFlagResize
    );
  TATEditorInternalFlags = set of TATEditorInternalFlag;

  { TATEditorScrollInfo }

  TATEditorScrollInfo = record
  private
    NPosInternal: Int64;
    procedure SetNPos(const AValue: Int64);
  public
    Vertical: boolean;
    NMax: Int64;
    NPage: Int64;
    NPosLast: Int64;
    NPixelOffset: Int64;
    CharSizeScaled: Int64; //char width/height, multiplied by ATEditorCharXScale
    SmoothMax: Int64;
    SmoothPage: Int64;
    SmoothPos: Int64;
    SmoothPosLast: Int64;
    property NPos: Int64 //property is only for debugging
      read NPosInternal
      write NPosInternal;
      //write SetNPos;
    procedure Clear;
    procedure SetZero; inline;
    procedure SetLast; inline;
    function TopGapVisible: boolean; inline;
    function TotalOffset: Int64;
    class operator =(const A, B: TATEditorScrollInfo): boolean;
  end;

type
  { TATCaretShape }

  TATCaretShape = class
  public
    //Value>=0: in pixels
    //Value<0: in percents
    //Value<-100: caret is bigger than cell and overlaps nearest cells
    Width: integer;
    Height: integer;
    EmptyInside: boolean;
    function IsNarrow: boolean;
    procedure Assign(Obj: TATCaretShape);
  end;

type
  { TMinimapThread }

  TATMinimapThread = class(TThread)
  public
    Editor: TObject;
  protected
    procedure Execute; override;
  end;

const
  cInitTextOffsetLeft = 0;
  cInitTextOffsetTop = 2;
  cInitHighlightGitConflicts = true;
  cInitAutoPairForMultiCarets = true;
  cInitInputNumberAllowNegative = true;
  cInitMaskChar = '*';
  cInitScrollAnimationSteps = 4;
  cInitScrollAnimationSleep = 0;
  cInitUndoLimit = 5000;
  cInitUndoMaxCarets = 20000;
  cInitUndoIndentVert = 15;
  cInitUndoIndentHorz = 20;
  cInitUndoPause = 300;
  cInitUndoPause2 = 1000;
  cInitUndoPauseHighlightLine = true;
  cInitUndoForCaretJump = true;
  cInitMicromapShowForMinCount = 2;
  cInitScrollbarHorzAddSpace = 2;
  cInitIdleInterval = 0; //1000; //0 dont fire OnIdle, faster
  cInitCaretsPrimitiveColumnSelection = true;
  cInitCaretsMultiToColumnSel = true;
  cInitBorderVisible = true;
  cInitBorderWidth = 1;
  cInitBorderWidthFocused = 1;
  cInitBorderWidthMacro = 3;
  cInitRulerNumeration = cRulerNumeration_0_10_20;
  cInitRulerHeightPercents = 120;
  cInitRulerFontSizePercents = 80;
  cInitRulerMarkCaret = 1;
  cInitRulerMarkSmall = 3;
  cInitRulerMarkBig = 7;
  cInitWrapMode = cWrapOff;
  cInitWrapEnabledForMaxLines = 60*1000;
  cInitSpacingY = 1;
  cInitCaretBlinkTime = 600;
  cInitMinimapVisible = false;
  cInitMinimapSelColorChange = 6; //how much minimap sel-rect is darker, in %
  cInitMinimapTooltipVisible = true;
  cInitMinimapTooltipLinesCount = 6;
  cInitMinimapTooltipWidthPercents = 60;
  cInitMicromapVisible = false;
  cInitMicromapOnScrollbar = false;
  cInitMicromapBookmarks = false;
  cInitShowMouseSelFrame = true;
  cInitMarginRight = 80;
  cInitTabSize = 8;
  cInitNumbersStyle = cNumbersEach5th;
  cInitNumbersIndentPercents = 60;
  cInitBitmapWidth = 1000;
  cInitBitmapHeight = 800;
  cInitGutterPlusSize = 4;
  cInitMarkerSize = 30;
  cInitFoldStyle = cFoldHereWithTruncatedText;
  cInitFoldUnderlineOffset = 3;
  cInitFoldTooltipVisible = true;
  cInitFoldTooltipLineCount = 15;
  cInitFoldTooltipWidthPercents = 80;
  cInitMaxLineLenToTokenize = 4000;
  cInitMinLineLenToCalcURL = 4;
  cInitMaxLineLenToCalcURL = 300;
  cInitDragDropMarkerWidth = 4;
  cInitStapleHiliteAlpha = 180;
  cInitZebraAlphaBlend = 235;
  cInitDimUnfocusedBack = 0;
  cInitShowFoldedMarkWithSelectionBG = true;

const
  cUrlRegex_Email = '\b(mailto:)?\w[\w\-\+\.]*@\w[\w\-\.]*\.\w{2,}\b';
  cUrlRegex_WebBegin = 'https?://|ftp://|magnet:\?|www\.|ftp\.';
  cUrlRegex_WebSite = '\w[\w\-\.@]*(:\d+)?'; // @ for password; :\d+ is port
  cUrlRegex_WebAnchor = '(\#[\w\-/]*)?';
  cUrlRegex_WebParams = '(\?[^<>''"\s]+)?';
  cUrlRegex_Web =
    '\b(' + cUrlRegex_WebBegin + ')'
    + cUrlRegex_WebSite
    + '(/[~\w\.\-\+\/%@]*)?' //folders
    + cUrlRegex_WebParams
    + cUrlRegex_WebAnchor;
  cUrlRegexInitial = cUrlRegex_Email + '|' + cUrlRegex_Web;

var
  cRectEmpty: TRect = (Left: 0; Top: 0; Right: 0; Bottom: 0);

type
  TATSynEditClickEvent = procedure(Sender: TObject; var AHandled: boolean) of object;
  TATSynEditClickMoveCaretEvent = procedure(Sender: TObject; APrevPnt, ANewPnt: TPoint) of object;
  TATSynEditClickGapEvent = procedure(Sender: TObject; AGapItem: TATGapItem; APos: TPoint) of object;
  TATSynEditCommandEvent = procedure(Sender: TObject; ACommand: integer; AInvoke: TATEditorCommandInvoke; const AText: string; var AHandled: boolean) of object;
  TATSynEditCommandAfterEvent = procedure(Sender: TObject; ACommand: integer; const AText: string) of object;
  TATSynEditClickGutterEvent = procedure(Sender: TObject; ABand: integer; ALineNum: integer) of object;
  TATSynEditClickMicromapEvent = procedure(Sender: TObject; AX, AY: integer) of object;
  TATSynEditClickLinkEvent = procedure(Sender: TObject; const ALink: string) of object;
  TATSynEditDrawBookmarkEvent = procedure(Sender: TObject; C: TCanvas; ALineNum: integer; const ARect: TRect) of object;
  TATSynEditDrawRectEvent = procedure(Sender: TObject; C: TCanvas; const ARect: TRect) of object;
  TATSynEditDrawGapEvent = procedure(Sender: TObject; C: TCanvas; const ARect: TRect; AGap: TATGapItem) of object;
  TATSynEditCalcBookmarkColorEvent = procedure(Sender: TObject; ABookmarkKind: integer; var AColor: TColor) of object;
  TATSynEditCalcStapleEvent = procedure(Sender: TObject; ALine, AIndent: integer; var AStapleColor: TColor) of object;
  TATSynEditCalcHiliteEvent = procedure(Sender: TObject; var AParts: TATLineParts;
    ALineIndex, ACharIndex, ALineLen: integer; var AColorAfterEol: TColor) of object;
  TATSynEditPasteEvent = procedure(Sender: TObject; var AHandled: boolean;
    AKeepCaret, ASelectThen: boolean) of object;
  TATSynEditHotspotEvent = procedure(Sender: TObject; AHotspotIndex: integer) of object;
  TATSynEditCheckInputEvent = procedure(Sender: TObject; AChar: WideChar; var AllowInput: boolean) of object;

type
  { TATFoldedMark }

  TATFoldedMark = record
  public
    Coord: TRect;
    LineFrom, LineTo: integer;
    procedure Init(const ACoord: TRect; ALineFrom, ALineTo: integer);
    procedure InitNone;
    function IsInited: boolean;
    class operator =(const a, b: TATFoldedMark): boolean;
  end;

  { TATFoldedMarks }

  TATFoldedMarks = class(specialize TFPGList<TATFoldedMark>)
  public
    function FindByCoord(ACoord: TPoint): TATFoldedMark;
  end;

  TATEditorTempOptions = record
    FontSize: integer;
    WrapMode: TATEditorWrapMode;
    ShowMinimap: boolean;
    ShowMicromap: boolean;
    ShowRuler: boolean;
    ShowNumbers: boolean;
    ShowFolding: boolean;
    ShowUnprinted: boolean;
    UnprintedSpaces: boolean;
    UnprintedSpacesTrail: boolean;
    UnprintedSpacesInSel: boolean;
    UnprintedEnds: boolean;
    UnprintedEndsDetails: boolean;
  end;

type
  { TATSynEdit }

  TATSynEdit = class(TCustomControl)
  private
    FFontItalic: TFont;
    FFontBold: TFont;
    FFontBoldItalic: TFont;
    FTimersEnabled: boolean;
    FTimerIdle: TTimer;
    FTimerBlink: TTimer;
    FTimerScroll: TTimer;
    FTimerNiceScroll: TTimer;
    FTimerDelayedParsing: TTimer;
    FTimerFlicker: TTimer;
    FPaintFlags: TATEditorInternalFlags;
    FPaintLocked: integer;
    FBitmap: TBitmap;
    FKeymap: TATKeymap;
    FKeymapHistory: TATKeyArray;
    FParentFrameObject: TCustomFrame;
    FWantTabs: boolean;
    FWantReturns: boolean;
    FEditorIndex: integer;
    FMarginRight: integer;
    FMarginList: array of integer;
    FStringsInt: TATStrings;
    FStringsExternal: TATStrings;
    FTabHelper: TATStringTabHelper;
    FAdapterHilite: TATAdapterHilite;
    FAdapterIME: TATAdapterIME;
    FFold: TATSynRanges;
    FFoldImageList: TImageList;
    FFoldStyle: TATEditorFoldStyle;
    FFoldUnderlineOffset: integer;
    FFoldEnabled: boolean;
    FFoldCacheEnabled: boolean;
    FFoldTooltipVisible: boolean;
    FFoldTooltipWidthPercents: integer;
    FFoldTooltipLineCount: integer;
    FFoldIconForMinimalRange: integer;
    FCursorText: TCursor;
    FCursorColumnSel: TCursor;
    FCursorGutterBookmark: TCursor;
    FCursorGutterNumbers: TCursor;
    FCursorMinimap: TCursor;
    FCursorMicromap: TCursor;
    FTextOffset: TPoint;
    FTextOffsetFromTop: integer;
    FTextOffsetFromTop1: integer;
    FTextHint: string;
    FTextHintFontStyle: TFontStyles;
    FTextHintCenter: boolean;
    FSel: TATCaretSelections;
    FSelRect: TRect;
    FSelRectBegin: TPoint;
    FSelRectEnd: TPoint;
    FVisibleColumns: integer;
    FCommandLog: TATEditorCommandLog;
    FCarets: TATCarets;
    FCaretShowEnabled: boolean;
    FCaretShown: boolean;
    FCaretBlinkEnabled: boolean;
    FCaretBlinkTime: integer;
    FCaretShapeNormal: TATCaretShape;
    FCaretShapeOverwrite: TATCaretShape;
    FCaretShapeReadonly: TATCaretShape;
    FCaretVirtual: boolean;
    FCaretSpecPos: boolean;
    FCaretStopUnfocused: boolean;
    FCaretHideUnfocused: boolean;
    FCaretAllowNextBlink: boolean;
    FIsEntered: boolean;
    FMarkers: TATMarkers;
    FAttribs: TATMarkers;
    FMarkedRange: TATMarkers;
    FDimRanges: TATDimRanges;
    FHotspots: TATHotspots;
    FRegexLinks: TRegExpr;
    FLinkCache: TATLinkCache;
    FFileName: string;
    FMenuStd: TPopupMenu;
    FMenuText: TPopupMenu;
    FMenuGutterBm: TPopupMenu;
    FMenuGutterNum: TPopupMenu;
    FMenuGutterFold: TPopupMenu;
    FMenuGutterFoldStd: TPopupMenu;
    FMenuMinimap: TPopupMenu;
    FMenuMicromap: TPopupMenu;
    FMenuRuler: TPopupMenu;
    MenuitemTextCut: TMenuItem;
    MenuitemTextCopy: TMenuItem;
    MenuitemTextPaste: TMenuItem;
    MenuitemTextDelete: TMenuItem;
    MenuitemTextSelAll: TMenuItem;
    MenuitemTextUndo: TMenuItem;
    MenuitemTextRedo: TMenuItem;
    FOverwrite: boolean;
    FHintWnd: THintWindow;
    FMouseDownCoordOriginal: TPoint;
    FMouseDownCoord: TPoint;
    FMouseDragCoord: TPoint;
    FMouseDownPnt: TPoint;
    FMouseDownGutterLineNumber: integer;
    FMouseDownOnMinimap: boolean;
    FMouseDownDouble: boolean;
    FMouseDownWithCtrl: boolean;
    FMouseDownWithAlt: boolean;
    FMouseDownWithShift: boolean;
    FMouseNiceScrollPos: TPoint;
    FMouseDragDropping: boolean;
    FMouseDragDroppingReal: boolean;
    FMouseDragMinimap: boolean;
    FMouseDragMinimapDelta: integer;
    FMouseDragMinimapSelHeight: integer;
    FMouseDownAndColumnSelection: boolean;
    FMouseAutoScrollDirection: TATEditorDirection;
    FMouseActions: TATEditorMouseActions;
    FLockInput: boolean;
    FLastControlWidth: integer;
    FLastControlHeight: integer;
    FLastHotspot: integer;
    FLastTextCmd: integer;
    FLastTextCmdText: atString;
    FLastCommand: integer;
    FLastCommandChangedText: boolean;
    FLastCommandChangedText2: boolean;
    FLastCommandMakesColumnSel: boolean;
    FLastCommandDelayedParsingOnLine: integer;
    FLastLineOfSlowEvents: integer;
    FLastUndoTick: QWord;
    FLastUndoPaused: boolean;
    FLineTopTodo: integer;
    FIsCaretShapeChangedFromAPI: boolean;
    FIsReadOnlyChanged: boolean;
    FIsReadOnlyAutodetected: boolean;
    FIsMacroRecording: boolean;
    FIsRunningCommand: boolean;
    FCursorOnMinimap: boolean;
    FCursorOnGutter: boolean;
    FFoldbarCache: TATFoldBarPropsArray;
    FFoldbarCacheStart: integer;
    FAdapterIsDataReady: boolean;
    FOnCheckInput: TATSynEditCheckInputEvent;
    FOnBeforeCalcHilite: TNotifyEvent;
    FOnClickDbl,
    FOnClickTriple,
    FOnClickMiddle: TATSynEditClickEvent;
    FOnClickMoveCaret: TATSynEditClickMoveCaretEvent;
    FOnClickGap: TATSynEditClickGapEvent;
    FOnClickEndSelect: TATSynEditClickMoveCaretEvent;
    FOnClickLink: TATSynEditClickLinkEvent;
    FOnIdle: TNotifyEvent;
    FOnChange: TNotifyEvent;
    FOnChangeLog: TATStringsChangeLogEvent;
    FOnChangeCaretPos: TNotifyEvent;
    FOnChangeState: TNotifyEvent;
    FOnChangeZoom: TNotifyEvent;
    FOnChangeModified: TNotifyEvent;
    FOnChangeBookmarks: TNotifyEvent;
    FOnScroll: TNotifyEvent;
    FOnClickGutter: TATSynEditClickGutterEvent;
    FOnClickMicromap: TATSynEditClickMicromapEvent;
    FOnDrawBookmarkIcon: TATSynEditDrawBookmarkEvent;
    FOnDrawGap: TATSynEditDrawGapEvent;
    FOnDrawLine: TATSynEditDrawLineEvent;
    FOnDrawMicromap: TATSynEditDrawRectEvent;
    FOnDrawEditor: TATSynEditDrawRectEvent;
    FOnDrawRuler: TATSynEditDrawRectEvent;
    FOnCommand: TATSynEditCommandEvent;
    FOnCommandAfter: TATSynEditCommandAfterEvent;
    FOnCalcHilite: TATSynEditCalcHiliteEvent;
    FOnCalcStaple: TATSynEditCalcStapleEvent;
    FOnCalcBookmarkColor: TATSynEditCalcBookmarkColorEvent;
    FOnCalcTabSize: TATStringTabCalcEvent;
    FOnPaste: TATSynEditPasteEvent;
    FOnHotspotEnter: TATSynEditHotspotEvent;
    FOnHotspotExit: TATSynEditHotspotEvent;
    FWrapInfo: TATWrapInfo;
    FWrapTemps: TATWrapItems;
    FWrapMode: TATEditorWrapMode;
    FWrapUpdateNeeded: boolean;
    FWrapIndented: boolean;
    FWrapAddSpace: integer;
    FWrapEnabledForMaxLines: integer;
    //FWheelQueue: TATEditorWheelQueue;
    FUnprintedVisible,
    FUnprintedSpaces,
    FUnprintedSpacesTrailing,
    FUnprintedSpacesBothEnds,
    FUnprintedSpacesOnlyInSelection,
    FUnprintedSpacesAlsoInSelection,
    FUnprintedEof,
    FUnprintedEnds,
    FUnprintedEndsDetails: boolean;
    FPrevModified: boolean;
    FCharSize: TATEditorCharSize;
    FCharSizeMinimap: TATEditorCharSize;
    FSpacingY: integer;
    FTabSize: integer;
    FGutter: TATGutter;
    FGutterDecor: TATGutterDecor;
    FGutterDecorImages: TImageList;
    FGutterDecorAlignment: TAlignment;
    FGutterBandBookmarks: integer;
    FGutterBandNumbers: integer;
    FGutterBandStates: integer;
    FGutterBandFolding: integer;
    FGutterBandSeparator: integer;
    FGutterBandEmpty: integer;
    FGutterBandDecor: integer;
    FColors: TATEditorColors;
    FColorFont: TColor;
    FColorBG: TColor;
    FColorGutterBG: TColor;
    FColorGutterFoldBG: TColor;
    FColorRulerBG: TColor;
    FColorCollapseMarkBG: TColor;
    FRulerHeight: integer;
    FNumbersIndent: integer;
    FRectMain,
    FRectMainVisible,
    FRectMinimap,
    FRectMicromap,
    FRectGutter,
    FRectGutterBm,
    FRectGutterNums,
    FRectRuler: TRect;
    FClientW: integer; //saved on Paint, to avoid calling Controls.ClientWidth/ClientHeight
    FClientH: integer;
    FLineBottom: integer;
    FParts: TATLineParts; //this is used in DoPaintLine
    FPartsMinimap: TATLineParts; //this is used by DoPaintMinimapLine, in thread
    FPartsSel: TATLineParts; //this is used in DoPartCalc_ApplySelectionOver
    FScrollVert,
    FScrollHorz,
    FScrollVertMinimap,
    FScrollHorzMinimap: TATEditorScrollInfo;
    FScrollbarVert,
    FScrollbarHorz: TATScrollbar;
    FScrollbarLock: boolean;
    FPrevHorz,
    FPrevVert: TATEditorScrollInfo;
    FMinimapWidth: integer;
    FMinimapCharWidth: integer;
    FMinimapCustomScale: integer;
    FMinimapVisible: boolean;
    FMinimapShowSelBorder: boolean;
    FMinimapShowSelAlways: boolean;
    FMinimapSelColorChange: integer;
    FMinimapAtLeft: boolean;
    FMinimapTooltipVisible: boolean;
    FMinimapTooltipEnabled: boolean;
    FMinimapTooltipBitmap: TBitmap;
    FMinimapTooltipLinesCount: integer;
    FMinimapTooltipWidthPercents: integer;
    FMinimapHiliteLinesWithSelection: boolean;
    FMinimapDragImmediately: boolean;
    FMicromap: TATMicromap;
    FMicromapVisible: boolean;
    FMicromapOnScrollbar: boolean;
    FMicromapLineStates: boolean;
    FMicromapSelections: boolean;
    FMicromapBookmarks: boolean;
    FMicromapScaleDiv: integer;
    FMicromapShowForMinCount: integer;
    FFoldedMarkList: TATFoldedMarks;
    FFoldedMarkCurrent: TATFoldedMark;
    FFoldedMarkTooltip: TPanel;
    FPaintCounter: integer;
    FPaintStarted: boolean;
    FPaintWorking: boolean;
    FTickMinimap: QWord;
    FTickAll: QWord;
    FShowOsBarVert: boolean;
    FShowOsBarHorz: boolean;
    FMinimapBmp: TBGRABitmap;
    FMinimapThread: TATMinimapThread;
    FEventMapStart: TSimpleEvent; //fired when need to start MinimapThread work
    FEventMapDone: TSimpleEvent; //fired by MinimapThread, when it's work done
    FColorOfStates: array[TATLineState] of TColor;
    FFoldingAsStringTodo: string;
    FHighlightGitConflicts: boolean;

    //these options are implemented in CudaText, they are dummy here
    FOptThemed: boolean;
    FOptAutoPairForMultiCarets: boolean;
    FOptAutoPairChars: string;
    FOptAutocompleteAutoshowCharCount: integer;
    FOptAutocompleteTriggerChars: string;
    FOptAutocompleteCommitChars: string;
    FOptAutocompleteCloseChars: string;
    FOptAutocompleteAddOpeningBracket: boolean;
    FOptAutocompleteUpDownAtEdge: integer;
    FOptAutocompleteCommitIfSingleItem: boolean;

    //options
    FOptInputNumberOnly: boolean;
    FOptInputNumberAllowNegative: boolean;
    FOptMaskChar: WideChar;
    FOptMaskCharUsed: boolean;
    FOptScrollAnimationSteps: integer;
    FOptScrollAnimationSleep: integer;
    FOptScaleFont: integer;
    FOptIdleInterval: integer;
    FOptPasteAtEndMakesFinalEmptyLine: boolean;
    FOptPasteMultilineTextSpreadsToCarets: boolean;
    FOptPasteWithEolAtLineStart: boolean;
    FOptMaxLineLenToTokenize: integer;
    FOptMinLineLenToCalcURL: integer;
    FOptMaxLineLenToCalcURL: integer;
    FOptMaxLinesToCountUnindent: integer;
    FOptScrollStyleVert: TATEditorScrollbarStyle;
    FOptScrollStyleHorz: TATEditorScrollbarStyle;
    FOptScrollSmooth: boolean;
    FOptScrollIndentCaretHorz: integer; //offsets for caret-moving: if caret goes out of control
    FOptScrollIndentCaretVert: integer; //must be 0, >0 gives jumps on move-down
    FOptUndoLimit: integer;
    FOptUndoGrouped: boolean;
    FOptUndoMaxCarets: integer;
    FOptUndoIndentVert: integer;
    FOptUndoIndentHorz: integer;
    FOptUndoPause: integer;
    FOptUndoPause2: integer;
    FOptUndoPauseHighlightLine: boolean;
    FOptUndoForCaretJump: boolean;
    FOptScrollbarsNew: boolean;
    FOptScrollbarHorizontalAddSpace: integer;
    FOptScrollLineCommandsKeepCaretOnScreen: boolean;
    FOptShowFontLigatures: boolean;
    FOptShowURLs: boolean;
    FOptShowURLsRegex: string;
    FOptShowDragDropMarker: boolean;
    FOptShowDragDropMarkerWidth: integer;
    FOptShowFoldedMarkWithSelectionBG: boolean;
    FOptStapleStyle: TATLineStyle;
    FOptStapleIndent: integer;
    FOptStapleWidthPercent: integer;
    FOptStapleHiliteActive: boolean;
    FOptStapleHiliteActiveAlpha: integer;
    FOptStapleEdge1: TATEditorStapleEdge;
    FOptStapleEdge2: TATEditorStapleEdge;
    FOptStapleIndentConsidersEnd: boolean;
    FOptMouseEnableAll: boolean;
    FOptMouseEnableNormalSelection: boolean;
    FOptMouseEnableColumnSelection: boolean;
    FOptMouseColumnSelectionWithoutKey: boolean;
    FOptCaretsPrimitiveColumnSelection: boolean;
    FOptCaretsAddedToColumnSelection: boolean;
    FOptCaretPreferLeftSide: boolean;
    FOptCaretPosAfterPasteColumn: TATEditorPasteCaret;
    FOptCaretFixAfterRangeFolded: boolean;
    FOptCaretsMultiToColumnSel: boolean;
    FOptCaretProximityVert: integer;
    FOptMarkersSize: integer;
    FOptShowScrollHint: boolean;
    FOptTextCenteringCharWidth: integer;
    FOptTextOffsetLeft: integer;
    FOptTextOffsetTop: integer;
    FOptSavingForceFinalEol: boolean;
    FOptSavingTrimSpaces: boolean;
    FOptSavingTrimFinalEmptyLines: boolean;
    FOptIndentSize: integer;
    FOptIndentKeepsAlign: boolean;
    FOptIndentMakesWholeLinesSelection: boolean;
    FOptBorderVisible: boolean;
    FOptBorderWidth: integer;
    FOptBorderWidthFocused: integer;
    FOptBorderWidthMacro: integer;
    FOptBorderFocusedActive: boolean;
    FOptBorderMacroRecording: boolean;
    FOptBorderRounded: boolean;
    FOptRulerVisible: boolean;
    FOptRulerNumeration: TATEditorRulerNumeration;
    FOptRulerHeightPercents: integer;
    FOptRulerFontSizePercents: integer;
    FOptRulerMarkSizeCaret: integer;
    FOptRulerMarkSizeSmall: integer;
    FOptRulerMarkSizeBig: integer;
    FOptRulerMarkForAllCarets: boolean;
    FOptRulerTopIndentPercents: integer;
    FOptGutterVisible: boolean;
    FOptGutterPlusSize: integer;
    FOptGutterShowFoldAlways: boolean;
    FOptGutterShowFoldLines: boolean;
    FOptGutterShowFoldLinesAll: boolean;
    FOptGutterShowFoldLinesForCaret: boolean;
    FOptGutterIcons: TATEditorGutterIcons;
    FOptNumbersAutosize: boolean;
    FOptNumbersAlignment: TAlignment;
    FOptNumbersStyle: TATEditorNumbersStyle;
    FOptNumbersShowFirst: boolean;
    FOptNumbersShowCarets: boolean;
    FOptNumbersIndentPercents: integer;
    FOptNonWordChars: atString;
    FOptAutoIndent: boolean;
    FOptAutoIndentKind: TATEditorAutoIndentKind;
    FOptAutoIndentBetterBracketsCurly: boolean;
    FOptAutoIndentBetterBracketsRound: boolean;
    FOptAutoIndentBetterBracketsSquare: boolean;
    FOptAutoIndentRegexRule: string;
    FOptTabSpaces: boolean;
    FOptLastLineOnTop: boolean;
    FOptOverwriteSel: boolean;
    FOptOverwriteAllowedOnPaste: boolean;
    FOptKeyBackspaceUnindent: boolean;
    FOptKeyBackspaceGoesToPrevLine: boolean;
    FOptKeyPageKeepsRelativePos: boolean;
    FOptKeyUpDownNavigateWrapped: boolean;
    FOptKeyUpDownAllowToEdge: boolean;
    FOptKeyHomeEndNavigateWrapped: boolean;
    FOptKeyUpDownKeepColumn: boolean;
    FOptCopyLinesIfNoSel: boolean;
    FOptCutLinesIfNoSel: boolean;
    FOptCopyColumnBlockAlignedBySpaces: boolean;
    FOptShowFullSel: boolean;
    FOptShowFullHilite: boolean;
    FOptShowCurLine: boolean;
    FOptShowCurLineMinimal: boolean;
    FOptShowCurLineOnlyFocused: boolean;
    FOptShowCurLineIfWithoutSel: boolean;
    FOptShowCurColumn: boolean;
    FOptShowMouseSelFrame: boolean;
    FOptMouseHideCursor: boolean;
    FOptMouseClickOpensURL: boolean;
    FOptMouseClickNumberSelectsLine: boolean;
    FOptMouseClickNumberSelectsLineWithEOL: boolean;
    FOptMouse2ClickAction: TATEditorDoubleClickAction;
    FOptMouse2ClickOpensURL: boolean;
    FOptMouse2ClickDragSelectsWords: boolean;
    FOptMouse3ClickSelectsLine: boolean;
    FOptMouseDragDrop: boolean;
    FOptMouseDragDropCopying: boolean;
    FOptMouseDragDropCopyingWithState: TShiftStateEnum;
    FOptMouseRightClickMovesCaret: boolean;
    FOptMouseMiddleClickAction: TATEditorMiddleClickAction;
    FOptMouseWheelScrollVert: boolean;
    FOptMouseWheelScrollHorz: boolean;
    FOptMouseWheelScrollVertSpeed: integer;
    FOptMouseWheelScrollHorzSpeed: integer;
    FOptMouseWheelScrollHorzWithState: TShiftStateEnum;
    FOptMouseWheelZooms: boolean;
    FOptMouseWheelZoomsWithState: TShiftStateEnum;
    FOptKeyPageUpDownSize: TATEditorPageDownSize;
    FOptKeyLeftRightGoToNextLineWithCarets: boolean;
    FOptKeyLeftRightSwapSel: boolean;
    FOptKeyLeftRightSwapSelAndSelect: boolean;
    FOptKeyHomeToNonSpace: boolean;
    FOptKeyEndToNonSpace: boolean;
    FOptKeyTabIndents: boolean;
    FOptKeyTabIndentsVerticalBlock: boolean;
    FOptShowIndentLines: boolean;
    FOptShowGutterCaretBG: boolean;
    FOptAllowRepaintOnTextChange: boolean;
    FOptAllowReadOnly: boolean;
    FOptZebraActive: boolean;
    FOptZebraStep: integer;
    FOptZebraAlphaBlend: byte;
    FOptDimUnfocusedBack: integer;
    {$ifdef LCLGTK2}
    FIMSelText: string;
    {$endif}

    //
    function DoCalcForegroundFromAttribs(AX, AY: integer; var AColor: TColor;
      var AFontStyles: TFontStyles): boolean;
    function DoCalcFoldProps(AWrapItemIndex: integer; out AProps: TATFoldBarProps): boolean;
    class function CheckInputForNumberOnly(const S: UnicodeString; X: integer;
      ch: WideChar; AllowNegative: boolean): boolean;
    procedure ClearSelRectPoints;
    procedure ClearMouseDownVariables;
    procedure DebugSelRect;
    function DoCalcLineLen(ALineIndex: integer): integer;
    procedure DoChangeBookmarks;
    procedure DoHandleWheelRecord(const ARec: TATEditorWheelRecord);
    procedure FlushEditingChangeEx(AChange: TATLineChangeKind; ALine, AItemCount: integer);
    procedure FlushEditingChangeLog(ALine: integer);
    function GetActualDragDropIsCopying: boolean;
    function GetIndentString: UnicodeString;
    function GetActualProximityVert: integer;
    function GetAttribs: TATMarkers;
    procedure GetClientSizes(out W, H: integer);
    function GetFoldingAsString: string;
    function GetMarkers: TATMarkers;
    function GetDimRanges: TATDimRanges;
    function GetHotspots: TATHotspots;
    function GetGutterDecor: TATGutterDecor;
    procedure InitFoldbarCache(ACacheStartIndex: integer);
    procedure InitLengthArray(var Lens: TATIntArray);
    function IsCaretFarFromVertEdge(ACommand: integer): boolean;
    function IsCaretOnVisibleRect: boolean;
    function IsInvalidateAllowed: boolean; inline;
    function IsNormalLexerActive: boolean;
    procedure SetEditorIndex(AValue: integer);
    procedure SetOptScaleFont(AValue: integer);
    procedure UpdateGapForms(ABeforePaint: boolean);
    procedure UpdateAndWait(AUpdateWrapInfo: boolean; APause: integer);
    procedure SetFoldingAsString(const AValue: string);
    procedure SetOptShowURLsRegex(const AValue: string);
    procedure SetShowOsBarVert(AValue: boolean);
    procedure SetShowOsBarHorz(AValue: boolean);
    procedure DebugFindWrapIndex;
    function DoCalcIndentCharsFromPrevLines(AX, AY: integer): integer;
    procedure DoCalcPosColor(AX, AY: integer; var AColor: TColor);
    procedure DoCalcLineEntireColor(ALine: integer; AUseColorOfCurrentLine: boolean; out AColor: TColor; out
      AColorForced: boolean; AHiliteLineWithSelection: boolean);
    procedure DoCaretsApplyShape(var R: TRect; Props: TATCaretShape; W, H: integer);
    function DoCaretApplyProximityToVertEdge(ACaretPos: TPoint;
      ACaretCoordY: integer; AProximity, AIndentVert: integer): boolean;
    function DoCaretApplyProximityToHorzEdge(ACaretCoordX, AProximity,
      AIndentHorz: integer): boolean;
    procedure DoCaretsAddOnColumnBlock(APos1, APos2: TPoint; const ARect: TRect);
    procedure DoCaretsFixForSurrogatePairs(AMoveRight: boolean);
    function DoCaretsKeepOnScreen(AMoveDown: boolean): boolean;
    procedure DoCaretsAssign(NewCarets: TATCarets);
    procedure DoCaretsShift_CaretItem(Caret: TATCaretItem; APosX, APosY, AShiftX,
      AShiftY, AShiftBelowX: integer);
    procedure DoCaretsShift_MarkerItem(AMarkerObj: TATMarkers;
      AMarkerIndex: integer; APosX, APosY, AShiftX, AShiftY,
      AShiftBelowX: integer; APosAfter: TPoint);
    procedure DoDropText(AndDeleteSelection: boolean);
    procedure DoFoldbarClick(ALine: integer);
    function DoGetFoldedMarkLinesCount(ALine: integer): integer;
    procedure DoHandleRightClick(X, Y: integer);
    function DoHandleClickEvent(AEvent: TATSynEditClickEvent): boolean;
    procedure DoHotspotsExit;
    procedure DoHintShow;
    procedure DoHintHide;
    procedure DoHintShowForBookmark(ALine: integer);
    procedure DoMenuGutterFold_AddDynamicItems(Menu: TPopupMenu);
    procedure DoMenuGutterFold;
    procedure DoMenuText;
    procedure DoMinimapClick(APosY: integer);
    procedure DoMinimapDrag(APosY: integer);
    procedure DoStringsOnChangeEx(Sender: TObject; AChange: TATLineChangeKind; ALine, AItemCount: integer);
    procedure DoStringsOnChangeLog(Sender: TObject; ALine: integer);
    procedure DoStringsOnProgress(Sender: TObject);
    procedure DoStringsOnUndoAfter(Sender: TObject; AX, AY: integer);
    procedure DoStringsOnUndoBefore(Sender: TObject; AX, AY: integer);
    procedure DoScroll_SetPos(var AScrollInfo: TATEditorScrollInfo; APos: integer);
    procedure DoScroll_LineTop(ALine: integer; AUpdate: boolean);
    function DoScroll_IndentFromBottom(AWrapInfoIndex, AIndentVert: integer): boolean;
    procedure DoScroll_IndentFromTop(AWrapInfoIndex, AIndentVert: integer); inline;
    procedure DoSelectionDeleteColumnBlock;
    function DoSelect_MultiCaretsLookLikeColumnSelection: boolean;
    procedure DoSelect_NormalSelToColumnSel(out ABegin, AEnd: TPoint);
    function _IsFocused: boolean;
    function GetEncodingName: string;
    procedure SetEncodingName(const AName: string);
    function GetGaps: TATGaps;
    function GetLastCommandChangedLines: integer;
    function GetMinimapActualHeight: integer;
    function GetMinimapSelTop: integer;
    function GetMinimap_DraggedPosToWrapIndex(APosY: integer): integer;
    function GetMinimap_ClickedPosToWrapIndex(APosY: integer): integer;
    function GetOptTextOffsetTop: integer;
    function GetRedoAsString: string;
    function GetUndoAsString: string;
    function IsFoldLineNeededBeforeWrapitem(N: integer): boolean;
    function IsRepaintNeededOnEnterOrExit: boolean;
    procedure MenuFoldFoldAllClick(Sender: TObject);
    procedure MenuFoldLevelClick(Sender: TObject);
    procedure MenuFoldUnfoldAllClick(Sender: TObject);
    procedure MenuFoldPlusMinusClick(Sender: TObject);
    procedure FoldedMarkTooltipPaint(Sender: TObject);
    procedure FoldedMarkMouseEnter(Sender: TObject);
    procedure OnNewScrollbarHorzChanged(Sender: TObject);
    procedure OnNewScrollbarVertChanged(Sender: TObject);
    procedure DoPartCalc_CreateNew(var AParts: TATLineParts; AOffsetMax,
      ALineIndex, ACharIndex: integer; AColorBG: TColor);
    procedure DoPartCalc_ApplySelectionOver(var AParts: TATLineParts; AOffsetMax,
      ALineIndex, ACharIndex: integer);
    procedure DoPartCalc_ApplyAttribsOver(var AParts: TATLineParts; AOffsetMax,
      ALineIndex, ACharIndex: integer; AColorBG: TColor);
    function GetAutoIndentString(APosX, APosY: integer; AUseIndentRegexRule: boolean): atString;
    function GetFoldedMarkText(ALine: integer): string;
    function GetModified: boolean;
    function Unfolded_NextLineNumber(ALine: integer; ADown: boolean): integer;
    function Unfolded_FirstLineNumber: integer;
    function Unfolded_LastLineNumber: integer;
    function GetOneLine: boolean;
    function GetRedoCount: integer;
    function GetLinesFromTop: integer;
    function GetText: UnicodeString;
    function GetUndoAfterSave: boolean;
    function GetUndoCount: integer;
    procedure InitAttribs;
    procedure InitMarkers;
    procedure InitHotspots;
    procedure InitDimRanges;
    procedure InitGutterDecor;
    procedure InitMarkedRange;
    procedure InitFoldedMarkList;
    procedure InitFoldedMarkTooltip;
    procedure InitFoldImageList;
    procedure InitMenuStd;
    procedure InitTimerScroll;
    procedure InitTimerNiceScroll;
    procedure StartTimerDelayedParsing;
    function IsWrapItemWithCaret(constref AWrapItem: TATWrapItem): boolean;
    procedure MenuClick(Sender: TObject);
    procedure MenuStdPopup(Sender: TObject);
    procedure DoCalcWrapInfos(ALine: integer; AIndentMaximal: integer;
      AItems: TATWrapItems; AConsiderFolding: boolean);
    procedure DoCalcLineHilite(const AData: TATWrapItem;
      var AParts: TATLineParts; ACharsSkipped, ACharsMax: integer;
      AColorBG: TColor; AColorForced: boolean; var AColorAfter: TColor;
      AMainText: boolean);
    function DoScaleFont(AValue: integer): integer;
    //select
    procedure DoSelectionDeleteOrReset;
    procedure DoSelect_ExtendSelectionByLine(AUp: boolean);
    procedure DoSelect_CharRange(ACaretIndex: integer; Pnt: TPoint);
    procedure DoSelect_WordRange(ACaretIndex: integer; P1, P2: TPoint);
    procedure DoSelect_ByDoubleClick(AllowOnlyWordChars: boolean);
    procedure DoSelect_Line_ByClick;
    procedure DoSelect_ColumnBlock_MoveEndUpDown(var AX, AY: integer; ALineDelta: integer);
    function TempSel_IsSelection: boolean; inline;
    function TempSel_IsMultiline: boolean; inline;
    function TempSel_IsLineWithSelection(ALine: integer): boolean; inline;
    function TempSel_IsLineAllSelected(ALine: integer): boolean; inline;
    function TempSel_IsPosSelected(AX, AY: integer): boolean; inline;
    function TempSel_IsRangeSelected(AX1, AY1, AX2, AY2: integer): TATRangeSelection; inline;
    procedure TempSel_GetRangesInLineAfterPoint(AX, AY: integer; out ARanges: TATSimpleRangeArray); inline;
    //paint
    procedure PaintEx(ALineNumber: integer);
    function DoPaint(ALineFrom: integer): boolean;
    procedure DoPaintBorder(C: TCanvas; AColor: TColor; ABorderWidth: integer; AUseRectMain: boolean);
    procedure DoPaintAll(C: TCanvas; ALineFrom: integer);
    procedure DoPaintMain(C: TCanvas; ALineFrom: integer);
    procedure DoPaintLine(C: TCanvas;
      const ARectLine: TRect;
      const ACharSize: TATEditorCharSize;
      var AScrollHorz: TATEditorScrollInfo;
      const AWrapIndex: integer;
      var ATempParts: TATLineParts);
    procedure DoPaintMinimapLine(ARectLine: TRect;
      const ACharSize: TATEditorCharSize;
      var AScrollHorz: TATEditorScrollInfo;
      const AWrapIndex: integer;
      var ATempParts: TATLineParts);
    procedure DoPaintGutterOfLine(C: TCanvas;
      ARect: TRect;
      const ACharSize: TATEditorCharSize;
      AWrapIndex: integer);
    procedure DoPaintNiceScroll(C: TCanvas);
    procedure DoPaintGutterNumber(C: TCanvas; ALineIndex, ACoordTop: integer; ABand: TATGutterItem);
    procedure DoPaintMarginLineTo(C: TCanvas; AX, AWidth: integer; AColor: TColor);
    procedure DoPaintRuler(C: TCanvas);
    procedure DoPaintRulerCaretMark(C: TCanvas; ACaretX: integer);
    procedure DoPaintRulerCaretMarks(C: TCanvas);
    procedure DoPaintTiming(C: TCanvas);
    procedure DoPaintText(C: TCanvas;
      const ARect: TRect;
      const ACharSize: TATEditorCharSize;
      AWithGutter: boolean;
      var AScrollHorz, AScrollVert: TATEditorScrollInfo;
      ALineFrom: integer);
    procedure DoPaintTextFragment(C: TCanvas;
      const ARect: TRect;
      ALineFrom, ALineTo: integer;
      AConsiderWrapInfo: boolean;
      AColorBG, AColorBorder: TColor);
    procedure DoPaintLineIndent(C: TCanvas;
      const ARect: TRect;
      const ACharSize: TATEditorCharSize;
      ACoordY: integer;
      AIndentSize: integer;
      AColorBG: TColor;
      AScrollPos: integer;
      AIndentLines: boolean);
    procedure DoPaintMinimapAllToBGRABitmap;
    procedure DoPaintMinimapTextToBGRABitmap(
      const ARect: TRect;
      const ACharSize: TATEditorCharSize;
      var AScrollHorz, AScrollVert: TATEditorScrollInfo);
    procedure DoPaintMinimapSelToBGRABitmap;
    procedure DoPaintMinimapTooltip(C: TCanvas);
    procedure DoPaintMicromap(C: TCanvas);
    procedure DoPaintMargins(C: TCanvas);
    procedure DoPaintGap(C: TCanvas; const ARect: TRect; AGap: TATGapItem);
    procedure DoPaintFoldedMark(C: TCanvas;
      APosX, APosY, ACoordX, ACoordY: integer;
      const AMarkText: string);
    procedure DoPaintCaretShape(C: TCanvas; ARect: TRect; ACaret: TATCaretItem;
      ACaretShape: TATCaretShape; ACaretColor: TColor);
    procedure DoPaintCarets(C: TCanvas; AWithInvalidate: boolean);
    procedure TimerBlinkDisable;
    procedure TimerBlinkEnable;
    procedure DoPaintSelectedLineBG(C: TCanvas;
      const ACharSize: TATEditorCharSize;
      const AVisRect: TRect;
      APointLeft, APointText: TPoint;
      const AWrapItem: TATWrapItem;
      ALineWidth: integer;
      const AScrollHorz: TATEditorScrollInfo);
    procedure DoPaintMarkersTo(C: TCanvas);
    procedure DoPaintMarkerOfDragDrop(C: TCanvas);
    procedure DoPaintGutterPlusMinus(C: TCanvas; AX, AY: integer; APlus: boolean;
      ALineColor: TColor);
    procedure DoPaintGutterFolding(C: TCanvas; AWrapItemIndex: integer; ACoordX1,
      ACoordX2, ACoordY1, ACoordY2: integer);
    procedure DoPaintGutterDecor(C: TCanvas; ALine: integer; const ARect: TRect);
    procedure DoPaintGutterBandBG(C: TCanvas; AColor: TColor; AX1, AY1, AX2,
      AY2: integer; AEntireHeight: boolean);
    procedure DoPaintLockedWarning(C: TCanvas);
    procedure DoPaintStaple(C: TCanvas; const R: TRect; AColor: TColor);
    procedure DoPaintStaples(C: TCanvas;
      const ARect: TRect;
      const ACharSize: TATEditorCharSize;
      const AScrollHorz: TATEditorScrollInfo);
    procedure DoPaintTextHintTo(C: TCanvas);
    procedure DoPaintMouseSelFrame(C: TCanvas);
    //carets
    procedure DoCaretsExtend(ADown: boolean; ALines: integer);
    function GetCaretManyAllowed: boolean;
    function DoCaretSwapEdge(Item: TATCaretItem; AMoveLeft: boolean): boolean;
    //events
    procedure DoEventBeforeCalcHilite;
    procedure DoEventClickMicromap(AX, AY: integer);
    procedure DoEventClickGutter(ABandIndex, ALineNumber: integer);
    function DoEventCommand(ACommand: integer; AInvoke: TATEditorCommandInvoke; const AText: string): boolean;
    procedure DoEventDrawBookmarkIcon(C: TCanvas; ALineNumber: integer; const ARect: TRect);
    procedure DoEventCommandAfter(ACommand: integer; const AText: string);
    //
    function GetEndOfFilePos: TPoint;
    function GetMarginString: string;
    function GetReadOnly: boolean;
    function GetLineTop: integer;
    function GetColumnLeft: integer;
    function GetTextForClipboard: string;
    function GetStrings: TATStrings;
    function GetMouseNiceScroll: boolean;
    procedure SetEnabledSlowEvents(AValue: boolean);
    procedure SetCaretBlinkEnabled(AValue: boolean);
    procedure SetFoldEnabled(AValue: boolean);
    procedure SetFontBold(AValue: TFont);
    procedure SetFontBoldItalic(AValue: TFont);
    procedure SetFontItalic(AValue: TFont);
    procedure SetLastCommandChangedLines(AValue: integer);
    procedure SetModified(AValue: boolean);
    procedure SetMouseNiceScroll(AValue: boolean);
    procedure SetCaretManyAllowed(AValue: boolean);
    procedure SetCaretBlinkTime(AValue: integer);
    procedure SetSpacingY(AValue: integer);
    procedure SetMarginString(const AValue: string);
    procedure SetMicromapVisible(AValue: boolean);
    procedure SetMinimapVisible(AValue: boolean);
    procedure SetOneLine(AValue: boolean);
    procedure SetReadOnly(AValue: boolean);
    procedure SetLineTop(AValue: integer);
    procedure SetColumnLeft(AValue: integer);
    procedure SetLinesFromTop(AValue: integer);
    procedure SetRedoAsString(const AValue: string);
    procedure SetStrings(Obj: TATStrings);
    procedure GetRectMain(out R: TRect);
    procedure GetRectMinimap(out R: TRect);
    procedure GetRectMinimapSel(out R: TRect);
    procedure GetRectMicromap(out R: TRect);
    procedure GetRectGutter(out R: TRect);
    procedure GetRectRuler(out R: TRect);
    procedure GetRectGutterNumbers(out R: TRect);
    procedure GetRectGutterBookmarks(out R: TRect);
    function GetTextOffset: TPoint;
    function GetPageLines: integer;
    function GetMinimapScrollPos: integer;
    procedure SetTabSize(AValue: integer);
    procedure SetTabSpaces(AValue: boolean);
    procedure SetText(const AValue: UnicodeString);
    procedure SetUndoAfterSave(AValue: boolean);
    procedure SetUndoAsString(const AValue: string);
    procedure SetUndoLimit(AValue: integer);
    procedure SetWrapMode(AValue: TATEditorWrapMode);
    procedure SetWrapIndented(AValue: boolean);
    procedure UpdateScrollbarVert;
    procedure UpdateScrollbarHorz;
    procedure UpdateSelRectFromPoints(const P1, P2: TPoint);
    procedure UpdateInitialVars(C: TCanvas);
    procedure UpdateLinksAttribs;
    function UpdateLinksRegexObject: boolean;
    procedure UpdateTabHelper;
    procedure UpdateCursor;
    procedure UpdateGutterAutosize;
    procedure UpdateMinimapAutosize;
    procedure UpdateFoldedMarkTooltip;
    procedure UpdateClientSizes;
    function DoFormatLineNumber(N: integer): string;
    function UpdateScrollInfoFromMessage(var AInfo: TATEditorScrollInfo; const AMsg: TLMScroll): boolean;
    procedure UpdateCaretsCoords(AOnlyLast: boolean = false);
    function GetCharSize(C: TCanvas; ACharSpacingY: integer): TATEditorCharSize;
    function GetScrollbarVisible(bVertical: boolean): boolean;
    procedure SetMarginRight(AValue: integer);

    //timers
    procedure TimerIdleTick(Sender: TObject);
    procedure TimerBlinkTick(Sender: TObject);
    procedure TimerScrollTick(Sender: TObject);
    procedure TimerNiceScrollTick(Sender: TObject);
    procedure TimerDelayedParsingTick(Sender: TObject);
    procedure TimerFlickerTick(Sender: TObject);

    //carets
    procedure DoCaretAddToPoint(AX, AY: integer);
    procedure DoCaretsColumnToPoint(AX, AY: integer);
    procedure DoCaretsDeleteOnSameLines;

    //editing
    function IsCommandResults_CaretMove(Res: TATCommandResults): boolean;
    function DoCommandCore(ACmd: integer; const AText: atString): TATCommandResults;
    procedure DoCommandResults(ACmd: integer; Res: TATCommandResults);
    function DoCommand_TextInsertAtCarets(const AText: atString; AKeepCaret,
      AOvrMode, ASelectThen, AInsertAtLineStarts: boolean): TATCommandResults;
    function DoCommand_ColumnSelectWithoutKey(AValue: boolean): TATCommandResults;
    function DoCommand_FoldLevel(ALevel: integer): TATCommandResults;
    function DoCommand_FoldAll: TATCommandResults;
    function DoCommand_FoldUnAll: TATCommandResults;
    function DoCommand_FoldRangeAtCurLine(ACommand: TATEditorFoldRangeCommand): TATCommandResults;
    function DoCommand_FoldSelection: TATCommandResults;
    function DoCommand_TextTrimSpaces(AMode: TATTrimSpaces): TATCommandResults;
    function DoCommand_TextChangeCase(AMode: TATEditorCaseConvert): TATCommandResults;
    function DoCommand_ScaleDelta(AIncrease: boolean): TATCommandResults;
    function DoCommand_ScaleReset: TATCommandResults;
    function DoCommand_MoveSelectionUpDown(ADown: boolean): TATCommandResults;
    function DoCommand_TextInsertEmptyAboveBelow(ADown: boolean): TATCommandResults;
    function DoCommand_SelectColumnToDirection(ADir: TATEditorSelectColumnDirection): TATCommandResults;
    function DoCommand_SelectColumnToLineEdge(AToEnd: boolean): TATCommandResults;
    function DoCommand_RemoveOneCaret(AFirstCaret: boolean): TATCommandResults;
    function DoCommand_TextInsertColumnBlockOnce(const AText: string; AKeepCaret: boolean): TATCommandResults;
    function DoCommand_CaretsExtend(ADown: boolean; ALines: integer): TATCommandResults;
    function DoCommand_UndoRedo(AUndo: boolean): TATCommandResults;
    function DoCommand_TextIndentUnindent(ARight: boolean): TATCommandResults;
    function DoCommand_TextIndentUnindent_StreamBlock(ARight: boolean): TATCommandResults;
    procedure DoCommand_TextIndentUnindent_StreamBlock_OneCaret(ARight: boolean;
      Caret: TATCaretItem; out ATextChanged: boolean);
    function DoCommand_TextIndentUnindent_ColumnBlock(ARight: boolean): TATCommandResults;
    function DoCommand_SelectWords: TATCommandResults;
    function DoCommand_SelectLines: TATCommandResults;
    function DoCommand_SelectAll: TATCommandResults;
    function DoCommand_SelectInverted: TATCommandResults;
    function DoCommand_SelectSplitToLines: TATCommandResults;
    function DoCommand_SelectExtendByLine(AUp: boolean): TATCommandResults;
    function DoCommand_Cancel(AKeepLast, AKeepSel: boolean): TATCommandResults;
    function DoCommand_ToggleReadOnly: TATCommandResults;
    function DoCommand_ToggleOverwrite: TATCommandResults;
    function DoCommand_ToggleWordWrap(AltOrder: boolean): TATCommandResults;
    function DoCommand_ToggleUnprinted: TATCommandResults;
    function DoCommand_ToggleUnprintedSpaces: TATCommandResults;
    function DoCommand_ToggleUnprintedSpacesTrailing: TATCommandResults;
    function DoCommand_ToggleUnprintedEnds: TATCommandResults;
    function DoCommand_ToggleUnprintedEndDetails: TATCommandResults;
    function DoCommand_ToggleLineNums: TATCommandResults;
    function DoCommand_ToggleFolding: TATCommandResults;
    function DoCommand_ToggleRuler: TATCommandResults;
    function DoCommand_ToggleMiniMap: TATCommandResults;
    function DoCommand_ToggleMicroMap: TATCommandResults;
    function DoCommand_GotoWord(AJump: TATWordJump; AJumpSimple: boolean=false): TATCommandResults;
    function DoCommand_GotoLineEdge(ABegin: boolean): TATCommandResults;
    function DoCommand_GotoScreenSide(ASide: TATCaretScreenSide): TATCommandResults;
    function DoCommand_ScrollToBeginOrEnd(AToBegin: boolean): TATCommandResults;
    function DoCommand_ScrollByDelta(ALines, AColumns: integer; AKeepCaretOnScreen: boolean): TATCommandResults;
    function DoCommand_ScrollToLeft: TATCommandResults;
    function DoCommand_TextInsertTabSpacesAtCarets(AOvrMode: boolean): TATCommandResults;
    function DoCommand_TextTabulation: TATCommandResults;
    function DoCommand_KeyHome: TATCommandResults;
    function DoCommand_KeyEnd: TATCommandResults;
    function DoCommand_KeyLeft(ASelCommand: boolean): TATCommandResults;
    function DoCommand_KeyRight(ASelCommand: boolean): TATCommandResults;
    function DoCommand_KeyUpDown(ADown: boolean; ALines: integer; AKeepRelativePos: boolean): TATCommandResults;
    function DoCommand_KeyUpDown_NextLine(ADown: boolean; ALines: integer): TATCommandResults;
    function DoCommand_KeyUpDown_Wrapped(ADown: boolean; ALines: integer): TATCommandResults;
    function DoCommand_TextBackspace: TATCommandResults;
    function DoCommand_TextDelete: TATCommandResults;
    function DoCommand_TextDeleteSelection: TATCommandResults;
    function DoCommand_TextDeleteLeft(ADeleteLen: integer; AAllowUnindent: boolean): TATCommandResults;
    function DoCommand_TextDeleteRight(ADeleteLen: integer): TATCommandResults;
    function DoCommand_TextInsertEol(AKeepCaret: boolean): TATCommandResults;
    function DoCommand_ForceFinalEndOfLine: TATCommandResults;
    function DoCommand_DeleteFinalEndOfLine: TATCommandResults;
    function DoCommand_TextDeleteLines: TATCommandResults;
    function DoCommand_TextDuplicateLine: TATCommandResults;
    function DoCommand_TextDeleteToLineBegin: TATCommandResults;
    function DoCommand_TextDeleteToLineEnd: TATCommandResults;
    function DoCommand_TextDeleteWord(ANext: boolean): TATCommandResults;
    function DoCommand_TextDeleteWordEntire: TATCommandResults;
    function DoCommand_TextDeleteToDocumentBegin: TATCommandResults;
    function DoCommand_TextDeleteToDocumentEnd: TATCommandResults;
    function DoCommand_GotoTextBegin: TATCommandResults;
    function DoCommand_GotoTextEnd: TATCommandResults;
    function DoCommand_ClipboardPaste(AKeepCaret, ASelectThen: boolean;
      AClipboardObject: TClipboard): TATCommandResults;
    function DoCommand_ClipboardPasteColumnBlock(AKeepCaret: boolean;
      AClipboardObject: TClipboard): TATCommandResults;
    function DoCommand_ClipboardCopy(Append: boolean;
      AClipboardObject: TClipboard): TATCommandResults;
    function DoCommand_ClipboardCut(
      AClipboardObject: TClipboard): TATCommandResults;
    function DoCommand_Sort(AAction: TATStringsSortAction): TATCommandResults;
    function DoCommand_DeleteAllBlanks: TATCommandResults;
    function DoCommand_DeleteAdjacentBlanks: TATCommandResults;
    function DoCommand_DeleteAdjacentDups: TATCommandResults;
    function DoCommand_DeleteAllDups(AKeepBlanks: boolean): TATCommandResults;
    function DoCommand_ReverseLines: TATCommandResults;
    function DoCommand_ShuffleLines: TATCommandResults;
    //
    function GetCommandFromKey(var Key: Word; Shift: TShiftState): integer;
    function DoMouseWheelAction(Shift: TShiftState; AWheelDelta: integer;
      AForceHorz: boolean): boolean;
    function GetCaretsArray: TATPointArray;
    function GetMarkersArray: TATInt64Array;
    procedure SetCaretsArray(const Ar: TATPointArray);
    procedure SetMarkersArray(const Ar: TATInt64Array);
    property MouseNiceScroll: boolean read GetMouseNiceScroll write SetMouseNiceScroll;
    property ShowOsBarVert: boolean read FShowOsBarVert write SetShowOsBarVert;
    property ShowOsBarHorz: boolean read FShowOsBarHorz write SetShowOsBarHorz;

  public
    TagString: string; //to store plugin specific data in CudaText
    InitialOptions: TATEditorTempOptions;

    IsModifiedWrapMode: boolean;
    IsModifiedMinimapVisible: boolean;
    IsModifiedMicromapVisible: boolean;
    IsModifiedRulerVisible: boolean;
    IsModifiedGutterNumbersVisible: boolean;
    IsModifiedGutterFoldingVisible: boolean;
    IsModifiedGutterBookmarksVisible: boolean;
    IsModifiedUnprintedVisible: boolean;
    IsModifiedUnprintedSpaces: boolean;
    IsModifiedUnprintedTrailingOnly: boolean;
    IsModifiedUnprintedEnds: boolean;
    IsModifiedUnprintedEndDetails: boolean;

    //overrides
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetFocus; override;
    procedure DragDrop(Source: TObject; X, Y: Integer); override;
    property ClientWidth: integer read FClientW;
    property ClientHeight: integer read FClientH;
    //updates
    procedure Invalidate; override;
    procedure InvalidateEx(AForceRepaint, AForceOnScroll: boolean);
    procedure Update(AUpdateWrapInfo: boolean=false); reintroduce;
    procedure UpdateWrapInfo(AForceUpdate: boolean=false);
    procedure UpdateFoldedFromLinesHidden;
    procedure UpdateScrollInfoFromSmoothPos(var AInfo: TATEditorScrollInfo; const APos: Int64);
    procedure UpdateFoldLineIndexer;
    function UpdateScrollbars(AdjustSmoothPos: boolean): boolean;
    procedure DoEventCarets; virtual;
    procedure DoEventScroll; virtual;
    procedure DoEventChange(ALineIndex: integer=-1; AllowOnChange: boolean=true); virtual;
    procedure DoEventState; virtual;
    procedure DoEventZoom;
    procedure TimersStart;
    procedure TimersStop;
    //complex props
    property Strings: TATStrings read GetStrings write SetStrings;
    property Fold: TATSynRanges read FFold;
    property Carets: TATCarets read FCarets;
    property CaretsSel: TATCaretSelections read FSel; //not used by apps (at 2021.02), but let's publish, to not forget
    property Markers: TATMarkers read GetMarkers;
    property Attribs: TATMarkers read GetAttribs;
    property Micromap: TATMicromap read FMicromap;
    property DimRanges: TATDimRanges read GetDimRanges;
    property Hotspots: TATHotspots read GetHotspots;
    property Gaps: TATGaps read GetGaps;
    property Keymap: TATKeymap read FKeymap write FKeymap;
    property CommandLog: TATEditorCommandLog read FCommandLog;
    property MouseActions: TATEditorMouseActions read FMouseActions write FMouseActions;
    property TabHelper: TATStringTabHelper read FTabHelper;
    property WrapInfo: TATWrapInfo read FWrapInfo;
    property ScrollVert: TATEditorScrollInfo read FScrollVert write FScrollVert;
    property ScrollHorz: TATEditorScrollInfo read FScrollHorz write FScrollHorz;
    property ScrollbarVert: TATScrollbar read FScrollbarVert;
    property ScrollbarHorz: TATScrollbar read FScrollbarHorz;
    property ParentFrameObject: TCustomFrame read FParentFrameObject write FParentFrameObject;
    property CaretShapeNormal: TATCaretShape read FCaretShapeNormal;
    property CaretShapeOverwrite: TATCaretShape read FCaretShapeOverwrite;
    property CaretShapeReadonly: TATCaretShape read FCaretShapeReadonly;
    //common
    property EncodingName: string read GetEncodingName write SetEncodingName;
    property Modified: boolean read GetModified write SetModified;
    property AdapterForHilite: TATAdapterHilite read FAdapterHilite write FAdapterHilite;
    property AdapterIME: TATAdapterIME read FAdapterIME write FAdapterIME;
    property EditorIndex: integer read FEditorIndex write SetEditorIndex;
    property LineTop: integer read GetLineTop write SetLineTop;
    property LineBottom: integer read FLineBottom;
    property LinesFromTop: integer read GetLinesFromTop write SetLinesFromTop;
    property ColumnLeft: integer read GetColumnLeft write SetColumnLeft;
    property ModeOverwrite: boolean read FOverwrite write FOverwrite;
    property ModeReadOnly: boolean read GetReadOnly write SetReadOnly;
    property ModeOneLine: boolean read GetOneLine write SetOneLine;
    property ModeMacroRecording: boolean read FIsMacroRecording write FIsMacroRecording;
    property UndoCount: integer read GetUndoCount;
    property RedoCount: integer read GetRedoCount;
    property UndoAsString: string read GetUndoAsString write SetUndoAsString;
    property RedoAsString: string read GetRedoAsString write SetRedoAsString;
    procedure ActionAddJumpToUndo;
    property Text: UnicodeString read GetText write SetText;
    property SelRect: TRect read FSelRect;
    function IsSelRectEmpty: boolean;
    function IsSelColumn: boolean;
    function IsPosSelected(AX, AY: integer): boolean;
    function IsRangeSelected(AX1, AY1, AX2, AY2: integer): TATRangeSelection;
    function IsPosFolded(AX, AY: integer): boolean;
    function IsPosInVisibleArea(AX, AY: integer): boolean;
    function IsLineFolded(ALine: integer; ADetectPartialFold: boolean = false): boolean;
    function IsCharWord(ch: Widechar): boolean;
    property TextCharSize: TATEditorCharSize read FCharSize;
    procedure DoUnfoldLine(ALine: integer);
    property RectMain: TRect read FRectMain;
    property RectGutter: TRect read FRectGutter;
    property RectMinimap: TRect read FRectMinimap;
    property RectMicromap: TRect read FRectMicromap;
    property RectRuler: TRect read FRectRuler;
    function RectMicromapMark(AColumn, ALineFrom, ALineTo: integer;
      AMapHeight, AMinMarkHeight: integer): TRect;
    property OptTextOffsetLeft: integer read FOptTextOffsetLeft write FOptTextOffsetLeft;
    property OptTextOffsetTop: integer read GetOptTextOffsetTop write FOptTextOffsetTop;
    //gutter
    property Gutter: TATGutter read FGutter;
    property GutterDecor: TATGutterDecor read GetGutterDecor;
    property GutterDecorAlignment: TAlignment read FGutterDecorAlignment write FGutterDecorAlignment;
    property GutterBandBookmarks: integer read FGutterBandBookmarks write FGutterBandBookmarks;
    property GutterBandNumbers: integer read FGutterBandNumbers write FGutterBandNumbers;
    property GutterBandStates: integer read FGutterBandStates write FGutterBandStates;
    property GutterBandFolding: integer read FGutterBandFolding write FGutterBandFolding;
    property GutterBandSeparator: integer read FGutterBandSeparator write FGutterBandSeparator;
    property GutterBandEmpty: integer read FGutterBandEmpty write FGutterBandEmpty;
    property GutterBandDecor: integer read FGutterBandDecor write FGutterBandDecor;
    //files
    property FileName: string read FFileName write FFileName;
    procedure LoadFromFile(const AFilename: string; AKeepScroll: boolean=false); virtual;
    procedure SaveToFile(const AFilename: string); virtual;
    //cmd
    procedure TextInsertAtCarets(const AText: atString; AKeepCaret,
      AOvrMode, ASelectThen: boolean);
    //carets
    procedure DoCaretSingle(APosX, APosY, AEndX, AEndY: integer);
    procedure DoCaretSingle(AX, AY: integer; AClearSelection: boolean = true);
    procedure DoCaretSingleAsIs;
    function DoCaretsFixIncorrectPos(AndLimitByLineEnds: boolean): boolean;
    procedure DoCaretsFixIfInsideFolded;
    procedure DoCaretsShift(AFromCaret: integer; APosX, APosY: integer; AShiftX, AShiftY: integer;
      APosAfter: TPoint; AShiftBelowX: integer = 0);
    procedure DoCaretForceShow;
    function CaretPosToClientPos(P: TPoint): TPoint;
    function ClientPosToCaretPos(P: TPoint;
      out ADetails: TATEditorPosDetails;
      AGapCoordAction: TATEditorGapCoordAction=cGapCoordToLineEnd): TPoint;
    function IsLineWithCaret(ALine: integer; ADisableSelected: boolean=false): boolean;
    function OffsetToCaretPos(const APos: integer): TPoint;
    function CaretPosToOffset(const ACaret: TPoint): integer;
    //goto
    function DoShowPos(const APos: TPoint; AIndentHorz, AIndentVert: integer;
      AUnfold, AllowUpdate, AllowProximity: boolean): boolean;
    procedure DoGotoPos(const APos, APosEnd: TPoint;
      AIndentHorz, AIndentVert: integer;
      APlaceCaret, ADoUnfold: boolean;
      AAllowProcessMsg: boolean=true;
      AAllowUpdate: boolean=true;
      AAllowProximity: boolean=true);
    procedure DoGotoCaret(AEdge: TATCaretEdge; AUndoRedo: boolean=false;
      AAllowProcessMsg: boolean=true; AAllowUpdate: boolean=true;
      AAllowProximity: boolean=true);
    //bookmarks
    procedure BookmarkSetForLineEx(ALine, ABmKind: integer;
      const AHint: string; AAutoDelete: TATBookmarkAutoDelete; AShowInList: boolean; const ATag: Int64;
      ABookmarksObj: TATBookmarks);
    procedure BookmarkSetForLine(ALine, ABmKind: integer;
      const AHint: string; AAutoDelete: TATBookmarkAutoDelete; AShowInList: boolean; const ATag: Int64);
    procedure BookmarkSetForLine_2(ALine, ABmKind: integer;
      const AHint: string; AAutoDelete: TATBookmarkAutoDelete; AShowInList: boolean; const ATag: Int64);
    procedure BookmarkToggleForLine(ALine, ABmKind: integer;
      const AHint: string; AAutoDelete: TATBookmarkAutoDelete; AShowInList: boolean; const ATag: Int64);
    procedure BookmarkDeleteForLineEx(ALine: integer; ABookmarksObj: TATBookmarks);
    procedure BookmarkDeleteForLine(ALine: integer);
    procedure BookmarkDeleteForLine_2(ALine: integer);
    function BookmarkDeleteByTagEx(const ATag: Int64; ABookmarksObj: TATBookmarks): boolean;
    function BookmarkDeleteByTag(const ATag: Int64): boolean;
    function BookmarkDeleteByTag_2(const ATag: Int64): boolean;
    procedure BookmarkDeleteAll(AWithEvent: boolean=true);
    procedure BookmarkDeleteAll_2;
    procedure BookmarkInvertAll;
    procedure BookmarkGotoNext(ANext: boolean; AIndentHorz, AIndentVert: integer; AOnlyShownInList: boolean);
    procedure BookmarkCopyMarkedLines;
    procedure BookmarkDeleteMarkedLines;
    procedure BookmarkPlaceBookmarksOnCarets;
    procedure BookmarkPlaceCaretsOnBookmarks;
    //fold
    procedure DoRangeFold(ARangeIndex: integer);
    procedure DoRangeUnfold(ARangeIndex: integer);
    procedure DoRangeHideLines(ALineFrom, ALineTo: integer); inline;
    procedure DoFoldForLevel(ALevel: integer);
    procedure DoFoldForLevelEx(ALevel: integer; AOuterRange: integer);
    procedure DoFoldUnfoldRangeAtCurLine(AOp: TATEditorFoldRangeCommand);
    property FoldingAsString: string read GetFoldingAsString write SetFoldingAsString;
    property FoldingAsStringTodo: string read FFoldingAsStringTodo write FFoldingAsStringTodo;
    //markers
    procedure MarkerClearAll;
    procedure MarkerDrop;
    procedure MarkerGotoLast(AndDelete: boolean; AIndentHorz, AIndentVert: integer);
    procedure MarkerSwap;
    procedure MarkerSelectToCaret;
    procedure MarkerDeleteToCaret;
    //menu
    property PopupTextDefault: TPopupMenu read FMenuStd;
    property PopupText: TPopupMenu read FMenuText write FMenuText;
    property PopupGutterBm: TPopupMenu read FMenuGutterBm write FMenuGutterBm;
    property PopupGutterNum: TPopupMenu read FMenuGutterNum write FMenuGutterNum;
    property PopupGutterFold: TPopupMenu read FMenuGutterFold write FMenuGutterFold;
    property PopupMinimap: TPopupMenu read FMenuMinimap write FMenuMinimap;
    property PopupMicromap: TPopupMenu read FMenuMicromap write FMenuMicromap;
    property PopupRuler: TPopupMenu read FMenuRuler write FMenuRuler;
    //misc
    function GetVisibleLines: integer;
    function GetVisibleColumns: integer;
    function GetVisibleLinesMinimap: integer;
    procedure DoCommand(ACmd: integer; AInvoke: TATEditorCommandInvoke; const AText: atString = ''); virtual;
    procedure BeginUpdate;
    procedure EndUpdate;
    procedure BeginEditing;
    procedure EndEditing(ATextChanged: boolean);
    procedure DoHideAllTooltips;
    function IsLocked: boolean;
    function TextSelected: atString;
    function TextSelectedEx(ACaret: TATCaretItem): atString;
    function TextCurrentWord: atString;
    //LastCommandChangedLines: count of lines changed by last call of Strings.ActionTrimSpaces
    property LastCommandChangedLines: integer read GetLastCommandChangedLines write SetLastCommandChangedLines;
    property IsRunningCommand: boolean read FIsRunningCommand;
    property IsReadOnlyChanged: boolean read FIsReadOnlyChanged write FIsReadOnlyChanged;
    property IsReadOnlyAutodetected: boolean read FIsReadOnlyAutodetected write FIsReadOnlyAutodetected;
    property IsCaretShapeChangedFromAPI: boolean read FIsCaretShapeChangedFromAPI write FIsCaretShapeChangedFromAPI;
    procedure DoSelect_All;
    procedure DoSelect_None;
    procedure DoSelect_Inverted;
    procedure DoSelect_SplitSelectionToLines;
    procedure DoSelect_Line(APos: TPoint);
    procedure DoSelect_CharGroupAtPos(P: TPoint; AddCaret, AllowOnlyWordChars: boolean);
    procedure DoSelect_LineRange(ALineFrom: integer; APosTo: TPoint);
    procedure DoSelect_ClearColumnBlock;
    procedure DoSelect_ColumnBlock_FromPoints(P1Char, P2Char: TPoint;
      AUpdateSelRectPoints: boolean=true);
    procedure DoSelect_ColumnBlock_FromPointsColumns(P1, P2: TPoint);
    procedure DoSelect_ColumnBlock_Primitive(P1, P2: TPoint);
    procedure DoScrollToBeginOrEnd(AToBegin: boolean);
    procedure DoScrollByDelta(ADeltaX, ADeltaY: integer);
    procedure DoScrollByDeltaInPixels(ADeltaX, ADeltaY: integer);
    procedure DoScaleFontDelta(AInc: boolean; AllowUpdate: boolean);
    function DoCalcLineHiliteEx(ALineIndex: integer; var AParts: TATLineParts;
      AColorBG: TColor; out AColorAfter: TColor): boolean;
    procedure DoSetMarkedLines(ALine1, ALine2: integer);
    procedure DoGetMarkedLines(out ALine1, ALine2: integer);
    function DoGetLinkAtPos(AX, AY: integer): atString;
    function DoGetGapRect(AIndex: integer; out ARect: TRect): boolean;
    procedure DoConvertIndentation(ASpacesToTabs: boolean);
    procedure DoConvertTabsToSpaces;

  protected
    IsRepaintEnabled: boolean;
    procedure Paint; override;
    procedure Resize; override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseLeave; override;

    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos{%H-}: TPoint): boolean; override;
    function DoMouseWheelHorz(Shift: TShiftState; WheelDelta: integer; MousePos{%H-}: TPoint): boolean; {$IF LCL_FULLVERSION >= 1090000} override; {$ENDIF}

    procedure DblClick; override;
    procedure TripleClick; override;
    function DoGetTextString: atString; virtual;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure DragOver(Source: TObject; X, Y: Integer; State: TDragState;
      var Accept: Boolean); override;
    //messages
    //procedure WMGetDlgCode(var Msg: TLMNoParams); message LM_GETDLGCODE;
    procedure WMEraseBkgnd(var Msg: TLMEraseBkgnd); message LM_ERASEBKGND;
    procedure WMHScroll(var Msg: TLMHScroll); message LM_HSCROLL;
    procedure WMVScroll(var Msg: TLMVScroll); message LM_VSCROLL;
    procedure CMWantSpecialKey(var Message: TCMWantSpecialKey); message CM_WANTSPECIALKEY;

    {$ifdef windows}
    procedure WMIME_Request(var Msg: TMessage); message WM_IME_REQUEST;
    procedure WMIME_Notify(var Msg: TMessage); message WM_IME_NOTIFY;
    procedure WMIME_StartComposition(var Msg:TMessage); message WM_IME_STARTCOMPOSITION;
    procedure WMIME_Composition(var Msg:TMessage); message WM_IME_COMPOSITION;
    procedure WMIME_EndComposition(var Msg:TMessage); message WM_IME_ENDCOMPOSITION;
    {$endif}

    {$ifdef GTK2_IME_CODE}
    procedure WM_GTK_IM_COMPOSITION(var Message: TLMessage); message LM_IM_COMPOSITION;
    {$endif}

  published
    property Align;
    property Anchors;
    property BorderSpacing;
    property BorderStyle;
    property Constraints;
    property DoubleBuffered;
    property DragMode;
    property DragKind;
    property Enabled;
    property Font;
    property FontItalic: TFont read FFontItalic write SetFontItalic;
    property FontBold: TFont read FFontBold write SetFontBold;
    property FontBoldItalic: TFont read FFontBoldItalic write SetFontBoldItalic;
    property ParentFont;
    property ParentShowHint;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property Visible;
    //events std
    property OnContextPopup;
    property OnDragOver;
    property OnDragDrop;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnMouseWheelDown;
    property OnMouseWheelUp;
    property OnResize;
    property OnUTF8KeyPress;
    //events new
    property OnClickDouble: TATSynEditClickEvent read FOnClickDbl write FOnClickDbl;
    property OnClickTriple: TATSynEditClickEvent read FOnClickTriple write FOnClickTriple;
    property OnClickMiddle: TATSynEditClickEvent read FOnClickMiddle write FOnClickMiddle;
    property OnClickGutter: TATSynEditClickGutterEvent read FOnClickGutter write FOnClickGutter;
    property OnClickMicromap: TATSynEditClickMicromapEvent read FOnClickMicromap write FOnClickMicromap;
    property OnClickMoveCaret: TATSynEditClickMoveCaretEvent read FOnClickMoveCaret write FOnClickMoveCaret;
    property OnClickEndSelect: TATSynEditClickMoveCaretEvent read FOnClickEndSelect write FOnClickEndSelect;
    property OnClickGap: TATSynEditClickGapEvent read FOnClickGap write FOnClickGap;
    property OnClickLink: TATSynEditClickLinkEvent read FOnClickLink write FOnClickLink;
    property OnCheckInput: TATSynEditCheckInputEvent read FOnCheckInput write FOnCheckInput;
    property OnIdle: TNotifyEvent read FOnIdle write FOnIdle;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnChangeLog: TATStringsChangeLogEvent read FOnChangeLog write FOnChangeLog;
    property OnChangeModified: TNotifyEvent read FOnChangeModified write FOnChangeModified;
    property OnChangeCaretPos: TNotifyEvent read FOnChangeCaretPos write FOnChangeCaretPos;
    property OnChangeState: TNotifyEvent read FOnChangeState write FOnChangeState;
    property OnChangeZoom: TNotifyEvent read FOnChangeZoom write FOnChangeZoom;
    property OnChangeBookmarks: TNotifyEvent read FOnChangeBookmarks write FOnChangeBookmarks;
    property OnScroll: TNotifyEvent read FOnScroll write FOnScroll;
    property OnCommand: TATSynEditCommandEvent read FOnCommand write FOnCommand;
    property OnCommandAfter: TATSynEditCommandAfterEvent read FOnCommandAfter write FOnCommandAfter;
    property OnDrawBookmarkIcon: TATSynEditDrawBookmarkEvent read FOnDrawBookmarkIcon write FOnDrawBookmarkIcon;
    property OnDrawLine: TATSynEditDrawLineEvent read FOnDrawLine write FOnDrawLine;
    property OnDrawGap: TATSynEditDrawGapEvent read FOnDrawGap write FOnDrawGap;
    property OnDrawMicromap: TATSynEditDrawRectEvent read FOnDrawMicromap write FOnDrawMicromap;
    property OnDrawEditor: TATSynEditDrawRectEvent read FOnDrawEditor write FOnDrawEditor;
    property OnDrawRuler: TATSynEditDrawRectEvent read FOnDrawRuler write FOnDrawRuler;
    property OnCalcHilite: TATSynEditCalcHiliteEvent read FOnCalcHilite write FOnCalcHilite;
    property OnCalcStaple: TATSynEditCalcStapleEvent read FOnCalcStaple write FOnCalcStaple;
    property OnCalcTabSize: TATStringTabCalcEvent read FOnCalcTabSize write FOnCalcTabSize;
    property OnCalcBookmarkColor: TATSynEditCalcBookmarkColorEvent read FOnCalcBookmarkColor write FOnCalcBookmarkColor;
    property OnBeforeCalcHilite: TNotifyEvent read FOnBeforeCalcHilite write FOnBeforeCalcHilite;
    property OnPaste: TATSynEditPasteEvent read FOnPaste write FOnPaste;
    property OnHotspotEnter: TATSynEditHotspotEvent read FOnHotspotEnter write FOnHotspotEnter;
    property OnHotspotExit: TATSynEditHotspotEvent read FOnHotspotExit write FOnHotspotExit;

    //misc
    property CursorText: TCursor read FCursorText write FCursorText default crIBeam;
    property CursorColumnSel: TCursor read FCursorColumnSel write FCursorColumnSel default crCross;
    property CursorGutterBookmark: TCursor read FCursorGutterBookmark write FCursorGutterBookmark default crHandPoint;
    property CursorGutterNumbers: TCursor read FCursorGutterNumbers write FCursorGutterNumbers default crDefault;
    property CursorMinimap: TCursor read FCursorMinimap write FCursorMinimap default crDefault;
    property CursorMicromap: TCursor read FCursorMicromap write FCursorMicromap default crDefault;
    property Colors: TATEditorColors read FColors write FColors stored false;
    property ImagesGutterDecor: TImageList read FGutterDecorImages write FGutterDecorImages;
    property WantTabs: boolean read FWantTabs write FWantTabs default true;
    property WantReturns: boolean read FWantReturns write FWantReturns default true;

    //options
    property OptThemed: boolean read FOptThemed write FOptThemed default false;
    property OptHighlightGitConflicts: boolean read FHighlightGitConflicts write FHighlightGitConflicts default cInitHighlightGitConflicts;
    property OptAutoPairForMultiCarets: boolean read FOptAutoPairForMultiCarets write FOptAutoPairForMultiCarets default cInitAutoPairForMultiCarets;
    property OptAutoPairChars: string read FOptAutoPairChars write FOptAutoPairChars stored false;
    property OptAutocompleteAutoshowCharCount: integer read FOptAutocompleteAutoshowCharCount write FOptAutocompleteAutoshowCharCount default 0;
    property OptAutocompleteTriggerChars: string read FOptAutocompleteTriggerChars write FOptAutocompleteTriggerChars stored false;
    property OptAutocompleteCommitChars: string read FOptAutocompleteCommitChars write FOptAutocompleteCommitChars stored false;
    property OptAutocompleteCloseChars: string read FOptAutocompleteCloseChars write FOptAutocompleteCloseChars stored false;
    property OptAutocompleteAddOpeningBracket: boolean read FOptAutocompleteAddOpeningBracket write FOptAutocompleteAddOpeningBracket default true;
    property OptAutocompleteUpDownAtEdge: integer read FOptAutocompleteUpDownAtEdge write FOptAutocompleteUpDownAtEdge default 1;
    property OptAutocompleteCommitIfSingleItem: boolean read FOptAutocompleteCommitIfSingleItem write FOptAutocompleteCommitIfSingleItem default false;

    property OptInputNumberOnly: boolean read FOptInputNumberOnly write FOptInputNumberOnly default false;
    property OptInputNumberAllowNegative: boolean read FOptInputNumberAllowNegative write FOptInputNumberAllowNegative default cInitInputNumberAllowNegative;
    property OptMaskChar: WideChar read FOptMaskChar write FOptMaskChar default cInitMaskChar;
    property OptMaskCharUsed: boolean read FOptMaskCharUsed write FOptMaskCharUsed default false;
    property OptScrollAnimationSteps: integer read FOptScrollAnimationSteps write FOptScrollAnimationSteps default cInitScrollAnimationSteps;
    property OptScrollAnimationSleep: integer read FOptScrollAnimationSleep write FOptScrollAnimationSleep default cInitScrollAnimationSleep;
    property OptScaleFont: integer read FOptScaleFont write SetOptScaleFont default 0;
    property OptIdleInterval: integer read FOptIdleInterval write FOptIdleInterval default cInitIdleInterval;
    property OptTabSpaces: boolean read FOptTabSpaces write SetTabSpaces default false;
    property OptTabSize: integer read FTabSize write SetTabSize default cInitTabSize;
    property OptNonWordChars: atString read FOptNonWordChars write FOptNonWordChars stored false;
    property OptFoldStyle: TATEditorFoldStyle read FFoldStyle write FFoldStyle default cInitFoldStyle;
    property OptFoldEnabled: boolean read FFoldEnabled write SetFoldEnabled default true;
    property OptFoldCacheEnabled: boolean read FFoldCacheEnabled write FFoldCacheEnabled default true;
    property OptFoldUnderlineOffset: integer read FFoldUnderlineOffset write FFoldUnderlineOffset default cInitFoldUnderlineOffset;
    property OptFoldTooltipVisible: boolean read FFoldTooltipVisible write FFoldTooltipVisible default cInitFoldTooltipVisible;
    property OldFoldTooltipWidthPercents: integer read FFoldTooltipWidthPercents write FFoldTooltipWidthPercents default cInitFoldTooltipWidthPercents;
    property OptFoldTooltipLineCount: integer read FFoldTooltipLineCount write FFoldTooltipLineCount default cInitFoldTooltipLineCount;
    property OptFoldIconForMinimalRangeHeight: integer read FFoldIconForMinimalRange write FFoldIconForMinimalRange default 0;
    property OptTextHint: string read FTextHint write FTextHint;
    property OptTextHintFontStyle: TFontStyles read FTextHintFontStyle write FTextHintFontStyle default [fsItalic];
    property OptTextHintCenter: boolean read FTextHintCenter write FTextHintCenter default false;
    property OptTextCenteringCharWidth: integer read FOptTextCenteringCharWidth write FOptTextCenteringCharWidth default 0;
    property OptAutoIndent: boolean read FOptAutoIndent write FOptAutoIndent default true;
    property OptAutoIndentKind: TATEditorAutoIndentKind read FOptAutoIndentKind write FOptAutoIndentKind default cIndentAsPrevLine;
    property OptAutoIndentBetterBracketsCurly: boolean read FOptAutoIndentBetterBracketsCurly write FOptAutoIndentBetterBracketsCurly default true;
    property OptAutoIndentBetterBracketsRound: boolean read FOptAutoIndentBetterBracketsRound write FOptAutoIndentBetterBracketsRound default false;
    property OptAutoIndentBetterBracketsSquare: boolean read FOptAutoIndentBetterBracketsSquare write FOptAutoIndentBetterBracketsSquare default false;
    property OptAutoIndentRegexRule: string read FOptAutoIndentRegexRule write FOptAutoIndentRegexRule;
    property OptCopyLinesIfNoSel: boolean read FOptCopyLinesIfNoSel write FOptCopyLinesIfNoSel default true;
    property OptCutLinesIfNoSel: boolean read FOptCutLinesIfNoSel write FOptCutLinesIfNoSel default false;
    property OptCopyColumnBlockAlignedBySpaces: boolean read FOptCopyColumnBlockAlignedBySpaces write FOptCopyColumnBlockAlignedBySpaces default true;
    property OptLastLineOnTop: boolean read FOptLastLineOnTop write FOptLastLineOnTop default false;
    property OptOverwriteSel: boolean read FOptOverwriteSel write FOptOverwriteSel default true;
    property OptOverwriteAllowedOnPaste: boolean read FOptOverwriteAllowedOnPaste write FOptOverwriteAllowedOnPaste default false;
    property OptScrollStyleHorz: TATEditorScrollbarStyle read FOptScrollStyleHorz write FOptScrollStyleHorz default aessAuto;
    property OptScrollStyleVert: TATEditorScrollbarStyle read FOptScrollStyleVert write FOptScrollStyleVert default aessShow;
    property OptScrollSmooth: boolean read FOptScrollSmooth write FOptScrollSmooth default true;
    property OptScrollIndentCaretHorz: integer read FOptScrollIndentCaretHorz write FOptScrollIndentCaretHorz default 10;
    property OptScrollIndentCaretVert: integer read FOptScrollIndentCaretVert write FOptScrollIndentCaretVert default 0;
    property OptScrollbarsNew: boolean read FOptScrollbarsNew write FOptScrollbarsNew default false;
    property OptScrollbarHorizontalAddSpace: integer read FOptScrollbarHorizontalAddSpace write FOptScrollbarHorizontalAddSpace default cInitScrollbarHorzAddSpace;
    property OptScrollLineCommandsKeepCaretOnScreen: boolean read FOptScrollLineCommandsKeepCaretOnScreen write FOptScrollLineCommandsKeepCaretOnScreen default true;

    property OptShowFontLigatures: boolean read FOptShowFontLigatures write FOptShowFontLigatures default true;
    property OptShowURLs: boolean read FOptShowURLs write FOptShowURLs default true;
    property OptShowURLsRegex: string read FOptShowURLsRegex write SetOptShowURLsRegex stored false;
    property OptShowDragDropMarker: boolean read FOptShowDragDropMarker write FOptShowDragDropMarker default true;
    property OptShowDragDropMarkerWidth: integer read FOptShowDragDropMarkerWidth write FOptShowDragDropMarkerWidth default cInitDragDropMarkerWidth;
    property OptShowFoldedMarkWithSelectionBG: boolean read FOptShowFoldedMarkWithSelectionBG write FOptShowFoldedMarkWithSelectionBG default cInitShowFoldedMarkWithSelectionBG;
    property OptMaxLineLenToTokenize: integer read FOptMaxLineLenToTokenize write FOptMaxLineLenToTokenize default cInitMaxLineLenToTokenize;
    property OptMinLineLenToCalcURL: integer read FOptMinLineLenToCalcURL write FOptMinLineLenToCalcURL default cInitMinLineLenToCalcURL;
    property OptMaxLineLenToCalcURL: integer read FOptMaxLineLenToCalcURL write FOptMaxLineLenToCalcURL default cInitMaxLineLenToCalcURL;
    property OptMaxLinesToCountUnindent: integer read FOptMaxLinesToCountUnindent write FOptMaxLinesToCountUnindent default 100;
    property OptStapleStyle: TATLineStyle read FOptStapleStyle write FOptStapleStyle default cLineStyleSolid;
    property OptStapleIndent: integer read FOptStapleIndent write FOptStapleIndent default -1;
    property OptStapleWidthPercent: integer read FOptStapleWidthPercent write FOptStapleWidthPercent default 100;
    property OptStapleHiliteActive: boolean read FOptStapleHiliteActive write FOptStapleHiliteActive default true;
    property OptStapleHiliteActiveAlpha: integer read FOptStapleHiliteActiveAlpha write FOptStapleHiliteActiveAlpha default cInitStapleHiliteAlpha;
    property OptStapleEdge1: TATEditorStapleEdge read FOptStapleEdge1 write FOptStapleEdge1 default cStapleEdgeAngle;
    property OptStapleEdge2: TATEditorStapleEdge read FOptStapleEdge2 write FOptStapleEdge2 default cStapleEdgeAngle;
    property OptStapleIndentConsidersEnd: boolean read FOptStapleIndentConsidersEnd write FOptStapleIndentConsidersEnd default false;
    property OptShowFullWidthForSelection: boolean read FOptShowFullSel write FOptShowFullSel default false;
    property OptShowFullWidthForSyntaxHilite: boolean read FOptShowFullHilite write FOptShowFullHilite default true;
    property OptShowCurLine: boolean read FOptShowCurLine write FOptShowCurLine default false;
    property OptShowCurLineMinimal: boolean read FOptShowCurLineMinimal write FOptShowCurLineMinimal default true;
    property OptShowCurLineOnlyFocused: boolean read FOptShowCurLineOnlyFocused write FOptShowCurLineOnlyFocused default false;
    property OptShowCurLineIfWithoutSel: boolean read FOptShowCurLineIfWithoutSel write FOptShowCurLineIfWithoutSel default true;
    property OptShowCurColumn: boolean read FOptShowCurColumn write FOptShowCurColumn default false;
    property OptShowScrollHint: boolean read FOptShowScrollHint write FOptShowScrollHint default false;
    property OptShowMouseSelFrame: boolean read FOptShowMouseSelFrame write FOptShowMouseSelFrame default cInitShowMouseSelFrame;
    property OptCaretManyAllowed: boolean read GetCaretManyAllowed write SetCaretManyAllowed default true;
    property OptCaretVirtual: boolean read FCaretVirtual write FCaretVirtual default true;
    property OptCaretBlinkTime: integer read FCaretBlinkTime write SetCaretBlinkTime default cInitCaretBlinkTime;
    property OptCaretBlinkEnabled: boolean read FCaretBlinkEnabled write SetCaretBlinkEnabled default true;
    property OptCaretStopUnfocused: boolean read FCaretStopUnfocused write FCaretStopUnfocused default true;
    property OptCaretHideUnfocused: boolean read FCaretHideUnfocused write FCaretHideUnfocused default true;
    property OptCaretPreferLeftSide: boolean read FOptCaretPreferLeftSide write FOptCaretPreferLeftSide default true;
    property OptCaretPosAfterPasteColumn: TATEditorPasteCaret read FOptCaretPosAfterPasteColumn write FOptCaretPosAfterPasteColumn default cPasteCaretColumnRight;
    property OptCaretsPrimitiveColumnSelection: boolean read FOptCaretsPrimitiveColumnSelection write FOptCaretsPrimitiveColumnSelection default cInitCaretsPrimitiveColumnSelection;
    property OptCaretsAddedToColumnSelection: boolean read FOptCaretsAddedToColumnSelection write FOptCaretsAddedToColumnSelection default true;
    property OptCaretFixAfterRangeFolded: boolean read FOptCaretFixAfterRangeFolded write FOptCaretFixAfterRangeFolded default true;
    property OptCaretsMultiToColumnSel: boolean read FOptCaretsMultiToColumnSel write FOptCaretsMultiToColumnSel default cInitCaretsMultiToColumnSel;
    property OptCaretProximityVert: integer read FOptCaretProximityVert write FOptCaretProximityVert default 0;
    property OptMarkersSize: integer read FOptMarkersSize write FOptMarkersSize default cInitMarkerSize;
    property OptGutterVisible: boolean read FOptGutterVisible write FOptGutterVisible default true;
    property OptGutterPlusSize: integer read FOptGutterPlusSize write FOptGutterPlusSize default cInitGutterPlusSize;
    property OptGutterShowFoldAlways: boolean read FOptGutterShowFoldAlways write FOptGutterShowFoldAlways default true;
    property OptGutterShowFoldLines: boolean read FOptGutterShowFoldLines write FOptGutterShowFoldLines default true;
    property OptGutterShowFoldLinesAll: boolean read FOptGutterShowFoldLinesAll write FOptGutterShowFoldLinesAll default false;
    property OptGutterShowFoldLinesForCaret: boolean read FOptGutterShowFoldLinesForCaret write FOptGutterShowFoldLinesForCaret default true;
    property OptGutterIcons: TATEditorGutterIcons read FOptGutterIcons write FOptGutterIcons default cGutterIconsPlusMinus;
    property OptBorderVisible: boolean read FOptBorderVisible write FOptBorderVisible default cInitBorderVisible;
    property OptBorderWidth: integer read FOptBorderWidth write FOptBorderWidth default cInitBorderWidth;
    property OptBorderWidthFocused: integer read FOptBorderWidthFocused write FOptBorderWidthFocused default cInitBorderWidthFocused;
    property OptBorderWidthMacro: integer read FOptBorderWidthMacro write FOptBorderWidthMacro default cInitBorderWidthMacro;
    property OptBorderRounded: boolean read FOptBorderRounded write FOptBorderRounded default false;
    property OptBorderFocusedActive: boolean read FOptBorderFocusedActive write FOptBorderFocusedActive default false;
    property OptBorderMacroRecording: boolean read FOptBorderMacroRecording write FOptBorderMacroRecording default true;
    property OptRulerVisible: boolean read FOptRulerVisible write FOptRulerVisible default true;
    property OptRulerNumeration: TATEditorRulerNumeration read FOptRulerNumeration write FOptRulerNumeration default cInitRulerNumeration;
    property OptRulerHeightPercents: integer read FOptRulerHeightPercents write FOptRulerHeightPercents default cInitRulerHeightPercents;
    property OptRulerFontSizePercents: integer read FOptRulerFontSizePercents write FOptRulerFontSizePercents default cInitRulerFontSizePercents;
    property OptRulerMarkSizeCaret: integer read FOptRulerMarkSizeCaret write FOptRulerMarkSizeCaret default cInitRulerMarkCaret;
    property OptRulerMarkSizeSmall: integer read FOptRulerMarkSizeSmall write FOptRulerMarkSizeSmall default cInitRulerMarkSmall;
    property OptRulerMarkSizeBig: integer read FOptRulerMarkSizeBig write FOptRulerMarkSizeBig default cInitRulerMarkBig;
    property OptRulerMarkForAllCarets: boolean read FOptRulerMarkForAllCarets write FOptRulerMarkForAllCarets default false;
    property OptRulerTopIndentPercents: integer read FOptRulerTopIndentPercents write FOptRulerTopIndentPercents default 0;
    property OptMinimapCustomScale: integer read FMinimapCustomScale write FMinimapCustomScale default 0;
    property OptMinimapVisible: boolean read FMinimapVisible write SetMinimapVisible default cInitMinimapVisible;
    property OptMinimapCharWidth: integer read FMinimapCharWidth write FMinimapCharWidth default 0;
    property OptMinimapShowSelBorder: boolean read FMinimapShowSelBorder write FMinimapShowSelBorder default false;
    property OptMinimapShowSelAlways: boolean read FMinimapShowSelAlways write FMinimapShowSelAlways default true;
    property OptMinimapSelColorChange: integer read FMinimapSelColorChange write FMinimapSelColorChange default cInitMinimapSelColorChange;
    property OptMinimapAtLeft: boolean read FMinimapAtLeft write FMinimapAtLeft default false;
    property OptMinimapTooltipVisible: boolean read FMinimapTooltipVisible write FMinimapTooltipVisible default cInitMinimapTooltipVisible;
    property OptMinimapTooltipLinesCount: integer read FMinimapTooltipLinesCount write FMinimapTooltipLinesCount default cInitMinimapTooltipLinesCount;
    property OptMinimapTooltipWidthPercents: integer read FMinimapTooltipWidthPercents write FMinimapTooltipWidthPercents default cInitMinimapTooltipWidthPercents;
    property OptMinimapHiliteLinesWithSelection: boolean read FMinimapHiliteLinesWithSelection write FMinimapHiliteLinesWithSelection default true;
    property OptMinimapDragImmediately: boolean read FMinimapDragImmediately write FMinimapDragImmediately default false;
    property OptMicromapVisible: boolean read FMicromapVisible write SetMicromapVisible default cInitMicromapVisible;
    property OptMicromapOnScrollbar: boolean read FMicromapOnScrollbar write FMicromapOnScrollbar default cInitMicromapOnScrollbar;
    property OptMicromapLineStates: boolean read FMicromapLineStates write FMicromapLineStates default true;
    property OptMicromapSelections: boolean read FMicromapSelections write FMicromapSelections default true;
    property OptMicromapBookmarks: boolean read FMicromapBookmarks write FMicromapBookmarks default cInitMicromapBookmarks;
    property OptMicromapShowForMinCount: integer read FMicromapShowForMinCount write FMicromapShowForMinCount default cInitMicromapShowForMinCount;
    property OptSpacingY: integer read FSpacingY write SetSpacingY default cInitSpacingY;
    property OptWrapMode: TATEditorWrapMode read FWrapMode write SetWrapMode default cInitWrapMode;
    property OptWrapIndented: boolean read FWrapIndented write SetWrapIndented default true;
    property OptWrapAddSpace: integer read FWrapAddSpace write FWrapAddSpace default 1;
    property OptWrapEnabledForMaxLines: integer read FWrapEnabledForMaxLines write FWrapEnabledForMaxLines default cInitWrapEnabledForMaxLines;
    property OptMarginRight: integer read FMarginRight write SetMarginRight default cInitMarginRight;
    property OptMarginString: string read GetMarginString write SetMarginString;
    property OptNumbersAutosize: boolean read FOptNumbersAutosize write FOptNumbersAutosize default true;
    property OptNumbersAlignment: TAlignment read FOptNumbersAlignment write FOptNumbersAlignment default taRightJustify;
    property OptNumbersStyle: TATEditorNumbersStyle read FOptNumbersStyle write FOptNumbersStyle default cInitNumbersStyle;
    property OptNumbersShowFirst: boolean read FOptNumbersShowFirst write FOptNumbersShowFirst default true;
    property OptNumbersShowCarets: boolean read FOptNumbersShowCarets write FOptNumbersShowCarets default false;
    property OptNumbersIndentPercents: integer read FOptNumbersIndentPercents write FOptNumbersIndentPercents default cInitNumbersIndentPercents;
    property OptUnprintedVisible: boolean read FUnprintedVisible write FUnprintedVisible default true;
    property OptUnprintedSpaces: boolean read FUnprintedSpaces write FUnprintedSpaces default true;
    property OptUnprintedSpacesTrailing: boolean read FUnprintedSpacesTrailing write FUnprintedSpacesTrailing default false;
    property OptUnprintedSpacesBothEnds: boolean read FUnprintedSpacesBothEnds write FUnprintedSpacesBothEnds default false;
    property OptUnprintedSpacesOnlyInSelection: boolean read FUnprintedSpacesOnlyInSelection write FUnprintedSpacesOnlyInSelection default false;
    property OptUnprintedSpacesAlsoInSelection: boolean read FUnprintedSpacesAlsoInSelection write FUnprintedSpacesAlsoInSelection default false;
    property OptUnprintedEnds: boolean read FUnprintedEnds write FUnprintedEnds default true;
    property OptUnprintedEndsDetails: boolean read FUnprintedEndsDetails write FUnprintedEndsDetails default true;
    property OptUnprintedEof: boolean read FUnprintedEof write FUnprintedEof default true;
    property OptMouseEnableAll: boolean read FOptMouseEnableAll write FOptMouseEnableAll default true;
    property OptMouseEnableNormalSelection: boolean read FOptMouseEnableNormalSelection write FOptMouseEnableNormalSelection default true;
    property OptMouseEnableColumnSelection: boolean read FOptMouseEnableColumnSelection write FOptMouseEnableColumnSelection default true;
    property OptMouseHideCursorOnType: boolean read FOptMouseHideCursor write FOptMouseHideCursor default false;
    property OptMouseClickOpensURL: boolean read FOptMouseClickOpensURL write FOptMouseClickOpensURL default false;
    property OptMouseClickNumberSelectsLine: boolean read FOptMouseClickNumberSelectsLine write FOptMouseClickNumberSelectsLine default true;
    property OptMouseClickNumberSelectsLineWithEOL: boolean read FOptMouseClickNumberSelectsLineWithEOL write FOptMouseClickNumberSelectsLineWithEOL default true;
    property OptMouse2ClickAction: TATEditorDoubleClickAction read FOptMouse2ClickAction write FOptMouse2ClickAction default cMouseDblClickSelectAnyChars;
    property OptMouse2ClickOpensURL: boolean read FOptMouse2ClickOpensURL write FOptMouse2ClickOpensURL default true;
    property OptMouse2ClickDragSelectsWords: boolean read FOptMouse2ClickDragSelectsWords write FOptMouse2ClickDragSelectsWords default true;
    property OptMouse3ClickSelectsLine: boolean read FOptMouse3ClickSelectsLine write FOptMouse3ClickSelectsLine default true;
    property OptMouseDragDrop: boolean read FOptMouseDragDrop write FOptMouseDragDrop default true;
    property OptMouseDragDropCopying: boolean read FOptMouseDragDropCopying write FOptMouseDragDropCopying default true;
    property OptMouseDragDropCopyingWithState: TShiftStateEnum read FOptMouseDragDropCopyingWithState write FOptMouseDragDropCopyingWithState default ssModifier;
    property OptMouseMiddleClickAction: TATEditorMiddleClickAction read FOptMouseMiddleClickAction write FOptMouseMiddleClickAction default mcaScrolling;
    property OptMouseRightClickMovesCaret: boolean read FOptMouseRightClickMovesCaret write FOptMouseRightClickMovesCaret default false;
    property OptMouseWheelScrollVert: boolean read FOptMouseWheelScrollVert write FOptMouseWheelScrollVert default true;
    property OptMouseWheelScrollVertSpeed: integer read FOptMouseWheelScrollVertSpeed write FOptMouseWheelScrollVertSpeed default 3;
    property OptMouseWheelScrollHorz: boolean read FOptMouseWheelScrollHorz write FOptMouseWheelScrollHorz default true;
    property OptMouseWheelScrollHorzSpeed: integer read FOptMouseWheelScrollHorzSpeed write FOptMouseWheelScrollHorzSpeed default 10;
    property OptMouseWheelScrollHorzWithState: TShiftStateEnum read FOptMouseWheelScrollHorzWithState write FOptMouseWheelScrollHorzWithState default ssShift;
    property OptMouseWheelZooms: boolean read FOptMouseWheelZooms write FOptMouseWheelZooms default true;
    property OptMouseWheelZoomsWithState: TShiftStateEnum read FOptMouseWheelZoomsWithState write FOptMouseWheelZoomsWithState default ssModifier;
    property OptMouseColumnSelectionWithoutKey: boolean read FOptMouseColumnSelectionWithoutKey write FOptMouseColumnSelectionWithoutKey default false;
    property OptKeyBackspaceUnindent: boolean read FOptKeyBackspaceUnindent write FOptKeyBackspaceUnindent default true;
    property OptKeyBackspaceGoesToPrevLine: boolean read FOptKeyBackspaceGoesToPrevLine write FOptKeyBackspaceGoesToPrevLine default true;
    property OptKeyPageKeepsRelativePos: boolean read FOptKeyPageKeepsRelativePos write FOptKeyPageKeepsRelativePos default true;
    property OptKeyUpDownNavigateWrapped: boolean read FOptKeyUpDownNavigateWrapped write FOptKeyUpDownNavigateWrapped default true;
    property OptKeyUpDownAllowToEdge: boolean read FOptKeyUpDownAllowToEdge write FOptKeyUpDownAllowToEdge default false;
    property OptKeyUpDownKeepColumn: boolean read FOptKeyUpDownKeepColumn write FOptKeyUpDownKeepColumn default true;
    property OptKeyHomeEndNavigateWrapped: boolean read FOptKeyHomeEndNavigateWrapped write FOptKeyHomeEndNavigateWrapped default true;
    property OptKeyPageUpDownSize: TATEditorPageDownSize read FOptKeyPageUpDownSize write FOptKeyPageUpDownSize default cPageSizeFullMinus1;
    property OptKeyLeftRightGoToNextLineWithCarets: boolean read FOptKeyLeftRightGoToNextLineWithCarets write FOptKeyLeftRightGoToNextLineWithCarets default true;
    property OptKeyLeftRightSwapSel: boolean read FOptKeyLeftRightSwapSel write FOptKeyLeftRightSwapSel default true;
    property OptKeyLeftRightSwapSelAndSelect: boolean read FOptKeyLeftRightSwapSelAndSelect write FOptKeyLeftRightSwapSelAndSelect default false;
    property OptKeyHomeToNonSpace: boolean read FOptKeyHomeToNonSpace write FOptKeyHomeToNonSpace default true;
    property OptKeyEndToNonSpace: boolean read FOptKeyEndToNonSpace write FOptKeyEndToNonSpace default true;
    property OptKeyTabIndents: boolean read FOptKeyTabIndents write FOptKeyTabIndents default true;
    property OptKeyTabIndentsVerticalBlock: boolean read FOptKeyTabIndentsVerticalBlock write FOptKeyTabIndentsVerticalBlock default false;
    property OptIndentSize: integer read FOptIndentSize write FOptIndentSize default 2;
             // N>0: use N spaces
             // N<0: use N tabs
             // N=0: calc indent from OptTabSize/OptTabSpaces
    property OptIndentKeepsAlign: boolean read FOptIndentKeepsAlign write FOptIndentKeepsAlign default true;
    property OptIndentMakesWholeLinesSelection: boolean read FOptIndentMakesWholeLinesSelection write FOptIndentMakesWholeLinesSelection default false;
    property OptShowIndentLines: boolean read FOptShowIndentLines write FOptShowIndentLines default true;
    property OptShowGutterCaretBG: boolean read FOptShowGutterCaretBG write FOptShowGutterCaretBG default true;
    property OptAllowRepaintOnTextChange: boolean read FOptAllowRepaintOnTextChange write FOptAllowRepaintOnTextChange default true;
    property OptAllowReadOnly: boolean read FOptAllowReadOnly write FOptAllowReadOnly default true;
    property OptUndoLimit: integer read FOptUndoLimit write SetUndoLimit default cInitUndoLimit;
    property OptUndoGrouped: boolean read FOptUndoGrouped write FOptUndoGrouped default true;
    property OptUndoAfterSave: boolean read GetUndoAfterSave write SetUndoAfterSave default true;
    property OptUndoMaxCarets: integer read FOptUndoMaxCarets write FOptUndoMaxCarets default cInitUndoMaxCarets;
    property OptUndoIndentVert: integer read FOptUndoIndentVert write FOptUndoIndentVert default cInitUndoIndentVert;
    property OptUndoIndentHorz: integer read FOptUndoIndentHorz write FOptUndoIndentHorz default cInitUndoIndentHorz;
    property OptUndoPause: integer read FOptUndoPause write FOptUndoPause default cInitUndoPause;
    property OptUndoPause2: integer read FOptUndoPause2 write FOptUndoPause2 default cInitUndoPause2;
    property OptUndoPauseHighlightLine: boolean read FOptUndoPauseHighlightLine write FOptUndoPauseHighlightLine default cInitUndoPauseHighlightLine;
    property OptUndoForCaretJump: boolean read FOptUndoForCaretJump write FOptUndoForCaretJump default cInitUndoForCaretJump;
    property OptSavingForceFinalEol: boolean read FOptSavingForceFinalEol write FOptSavingForceFinalEol default false;
    property OptSavingTrimSpaces: boolean read FOptSavingTrimSpaces write FOptSavingTrimSpaces default false;
    property OptSavingTrimFinalEmptyLines: boolean read FOptSavingTrimFinalEmptyLines write FOptSavingTrimFinalEmptyLines default false;
    property OptPasteAtEndMakesFinalEmptyLine: boolean read FOptPasteAtEndMakesFinalEmptyLine write FOptPasteAtEndMakesFinalEmptyLine default true;
    property OptPasteMultilineTextSpreadsToCarets: boolean read FOptPasteMultilineTextSpreadsToCarets write FOptPasteMultilineTextSpreadsToCarets default true;
    property OptPasteWithEolAtLineStart: boolean read FOptPasteWithEolAtLineStart write FOptPasteWithEolAtLineStart default true;
    property OptZebraActive: boolean read FOptZebraActive write FOptZebraActive default false;
    property OptZebraStep: integer read FOptZebraStep write FOptZebraStep default 2;
    property OptZebraAlphaBlend: byte read FOptZebraAlphaBlend write FOptZebraAlphaBlend default cInitZebraAlphaBlend;
    property OptDimUnfocusedBack: integer read FOptDimUnfocusedBack write FOptDimUnfocusedBack default cInitDimUnfocusedBack;
  end;

const
  cEncNameUtf8_WithBom = 'UTF-8 with BOM';
  cEncNameUtf8_NoBom = 'UTF-8';
  cEncNameUtf16LE_WithBom = 'UTF-16 LE with BOM';
  cEncNameUtf16LE_NoBom = 'UTF-16 LE';
  cEncNameUtf16BE_WithBom = 'UTF-16 BE with BOM';
  cEncNameUtf16BE_NoBom = 'UTF-16 BE';
  cEncNameUtf32LE_WithBom = 'UTF-32 LE with BOM';
  cEncNameUtf32LE_NoBom = 'UTF-32 LE';
  cEncNameUtf32BE_WithBom = 'UTF-32 BE with BOM';
  cEncNameUtf32BE_NoBom = 'UTF-32 BE';

function EditorLinkIsEmail(const S: string): boolean;
procedure EditorOpenLink(const S: string);

procedure InitEditorMouseActions(out M: TATEditorMouseActions; ANoCtrlClickForCaret: boolean);


implementation

uses
  LCLIntf,
  LCLProc,
  Dialogs,
  Types,
  Math,
  {$ifdef LCLGTK2}
  gtk2,
  Gtk2Globals,
  {$endif}
  ATStringProc_TextBuffer,
  ATSynEdit_Commands,
  ATSynEdit_Keymap_Init;

{$I atsynedit_proc.inc}

{ TATMinimapThread }

procedure TATMinimapThread.Execute;
var
  Ed: TATSynEdit;
begin
  Ed:= TATSynEdit(Editor);
  repeat
    if Terminated then exit;
    if Ed.FEventMapStart.WaitFor(1000)=wrSignaled then
    begin
      Ed.FEventMapStart.ResetEvent;
      Ed.DoPaintMinimapAllToBGRABitmap;
      Ed.FEventMapDone.SetEvent;
    end;
  until false;
end;

{ TATSynEdit }

procedure TATSynEdit.DoPaintRuler(C: TCanvas);
var
  NCoordX, NPrevFontSize, NRulerStart, NOutput,
  NTopIndent, NMarkHeight, i: integer;
  NCharWidthScaled: integer;
  Str: string;
begin
  NPrevFontSize:= C.Font.Size;
  NRulerStart:= FScrollHorz.NPos;
  NTopIndent:= FOptRulerTopIndentPercents*FCharSize.Y div 100;

  C.Font.Name:= Font.Name;
  C.Font.Size:= DoScaleFont(Font.Size) * FOptRulerFontSizePercents div 100;
  C.Font.Color:= Colors.RulerFont;
  C.Pen.Color:= Colors.RulerFont;
  C.Brush.Color:= FColorRulerBG;

  C.FillRect(FRectRuler);

  NCharWidthScaled:= FCharSize.XScaled * FOptRulerFontSizePercents div 100;

  for i:= NRulerStart to NRulerStart+FVisibleColumns+1 do
  begin
    NCoordX:= FRectMain.Left + (i-NRulerStart) * FCharSize.XScaled div ATEditorCharXScale;

    case FOptRulerNumeration of
      cRulerNumeration_0_10_20:
        begin
          NOutput:= i;
          if (i mod 10 = 0) then
          begin
            Str:= IntToStr(NOutput);
            CanvasTextOutSimplest(C, NCoordX - NCharWidthScaled*Length(Str) div 2 div ATEditorCharXScale, NTopIndent, Str);
          end;
        end;
      cRulerNumeration_1_11_21:
        begin
          NOutput:= i;
          if (i mod 10 = 0) then
          begin
            Str:= IntToStr(NOutput+1{!});
            CanvasTextOutSimplest(C, NCoordX - NCharWidthScaled*Length(Str) div 2 div ATEditorCharXScale, NTopIndent, Str);
          end;
        end;
      cRulerNumeration_1_10_20:
        begin
          NOutput:= i+1;
          if (NOutput=1) or (NOutput mod 10 = 0) then
          begin
            Str:= IntToStr(NOutput);
            CanvasTextOutSimplest(C, NCoordX - NCharWidthScaled*Length(Str) div 2 div ATEditorCharXScale, NTopIndent, Str);
          end;
        end;
    end;

    if NOutput mod 5 = 0 then
      NMarkHeight:= ATEditorScale(FOptRulerMarkSizeBig)
    else
      NMarkHeight:= ATEditorScale(FOptRulerMarkSizeSmall);

    CanvasLineVert(C, NCoordX, FRectRuler.Bottom-1-NMarkHeight, FRectRuler.Bottom-1);
  end;

  CanvasLineHorz(C, FRectRuler.Left, FRectRuler.Bottom-1, FRectRuler.Right);

  C.Font.Size:= NPrevFontSize;
end;


procedure TATSynEdit.DoPaintRulerCaretMark(C: TCanvas; ACaretX: integer);
begin
  if (ACaretX>=FRectRuler.Left) and (ACaretX<FRectRuler.Right) then
    CanvasPaintTriangleDown(C,
      Colors.RulerFont,
      Point(ACaretX, FRectRuler.Top+ATEditorScale(FOptRulerMarkSizeCaret)),
      ATEditorScale(FOptRulerMarkSizeCaret)
      );
end;

procedure TATSynEdit.DoPaintRulerCaretMarks(C: TCanvas);
var
  NCount, i: integer;
begin
  if FOptRulerVisible and (FOptRulerMarkSizeCaret>0) then
  begin
    if FOptRulerMarkForAllCarets then
      NCount:= Carets.Count
    else
      NCount:= 1;

    for i:= 0 to NCount-1 do
      DoPaintRulerCaretMark(C, Carets[i].CoordX);
  end;
end;

procedure TATSynEdit.UpdateGutterAutosize;
var
  Str: string;
begin
  Str:= IntToStr(Max(10, Strings.Count));
  FGutter[FGutterBandNumbers].Size:=
    Length(Str)*FCharSize.XScaled div ATEditorCharXScale + 2*FNumbersIndent;
  FGutter.Update;
end;

procedure TATSynEdit.UpdateMinimapAutosize;
{
  Minimap must give same cnt of small chars, as rest width gives for normal chars.
  This gives:
    MapSize / CharWidth_small = (ClientWidth - MapSize) / CharWidth_big
    MapSize = (ClientWidth * CharWidth_small) / (CharWidth_big+CharWidth_small)
}
var
  CharSmall, CharBig: integer;
begin
  CharBig:= FCharSize.XScaled div ATEditorCharXScale;
  CharSmall:= FCharSizeMinimap.XScaled div ATEditorCharXScale;

  if FMinimapCharWidth=0 then
  begin
    FMinimapWidth:= ClientWidth-FTextOffset.X;
    if FMicromapVisible and not FMicromapOnScrollbar then
      Dec(FMinimapWidth, FRectMicromap.Width);
    FMinimapWidth:= FMinimapWidth * CharSmall div (CharSmall+CharBig);
  end
  else
    FMinimapWidth:= CharSmall*FMinimapCharWidth;

  FMinimapWidth:= Max(ATEditorOptions.MinMinimapWidth, FMinimapWidth);
end;

function TATSynEdit.DoFormatLineNumber(N: integer): string;
var
  NCurLine: integer;
begin
  if FOptNumbersStyle=cNumbersRelative then
  begin
    if Carets.Count=0 then
      exit(IntToStr(N));
    NCurLine:= Carets[0].PosY+1;
    if N=NCurLine then
      Result:= IntToStr(N)
    else
      Result:= IntToStr(N-NCurLine);
    exit
  end;

  if FOptNumbersShowCarets then
    if IsLineWithCaret(N-1) then
      Exit(IntToStr(N));

  if FOptNumbersShowFirst then
    if N=1 then
      Exit(IntToStr(N));

  case FOptNumbersStyle of
    cNumbersAll:
      Result:= IntToStr(N);
    cNumbersNone:
      Result:= '.';
    cNumbersEach10th:
      begin
        if (N mod 10 = 0) then
          Result:= IntToStr(N)
        else
        if (N mod 5) = 0 then
          Result:= '-'
        else
          Result:= '.';
      end;
    cNumbersEach5th:
      begin
        if (N mod 5 = 0) then
          Result:= IntToStr(N)
        else
          Result:= '.';
      end;
  end;
end;

function TATSynEdit.GetScrollbarVisible(bVertical: boolean): boolean;
const
  cKind: array[boolean] of integer = (SB_HORZ, SB_VERT);
var
  si: TScrollInfo;
begin
  FillChar(si{%H-}, SizeOf(si), 0);
  si.cbSize:= SizeOf(si);
  si.fMask:= SIF_ALL;
  GetScrollInfo(Handle, cKind[bVertical], si);
  Result:= Longword(si.nMax) > Longword(si.nPage);
end;

procedure TATSynEdit.SetMarginRight(AValue: integer);
begin
  if AValue=FMarginRight then Exit;
  FMarginRight:= Max(AValue, ATEditorOptions.MinMarginRt);
  if FWrapMode=cWrapAtWindowOrMargin then
    FWrapUpdateNeeded:= true;
end;

procedure TATSynEdit.UpdateWrapInfo(AForceUpdate: boolean);
var
  CurStrings: TATStrings;
  ListNums: TATIntegerList;
  UseCachedUpdate: boolean;
  bConsiderFolding: boolean;
  NNewVisibleColumns: integer;
  NIndentMaximal: integer;
  NLine, NIndexFrom, NIndexTo: integer;
  i, j: integer;
begin
  //method can be called before 1st paint,
  //so TCanvas.TextWidth (TATSynEdit.GetCharSize) will give exception "Control has no parent window"
  //example: CudaText has user.json with "wrap_mode":1

  //2021.01.29:
  //check "if not HandleAllocated" stops the work, when passive file-tabs are
  //trying to restore Ed.LineTop.
  // https://github.com/Alexey-T/CudaText/issues/3112
  //to fix this issue, let's not Exit "if not HandleAllocated",
  //but handle this in GetCharSize(), via GetDC(0)

  if not HandleAllocated then
    if FWrapMode<>cWrapOff then
      exit;

  //must init FRect* if called before first paint (wrapped items need it)
  if FRectMain.Width=0 then
    UpdateInitialVars(Canvas);

  GlobalCharSizer.Init(Font.Name, DoScaleFont(Font.Size));

  //virtual mode allows faster usage of WrapInfo
  CurStrings:= Strings;
  FWrapInfo.StringsObj:= CurStrings;
  FWrapInfo.VirtualMode:=
    (FWrapMode=cWrapOff) and
    (Fold.Count=0) and
    (CurStrings.Count>2);
  if FWrapInfo.VirtualMode then exit;

  bConsiderFolding:= Fold.Count>0;
  NNewVisibleColumns:= GetVisibleColumns;
  NIndentMaximal:= Max(2, NNewVisibleColumns-ATEditorOptions.MinCharsAfterAnyIndent); //don't do too big NIndent

  if AForceUpdate then
    FWrapUpdateNeeded:= true
  else
  if (not FWrapUpdateNeeded) and
    (FWrapMode<>cWrapOff) and
    (FWrapInfo.VisibleColumns<>NNewVisibleColumns) then
    FWrapUpdateNeeded:= true;

  if not FWrapUpdateNeeded then Exit;
  FWrapUpdateNeeded:= false;
  FWrapInfo.VisibleColumns:= NNewVisibleColumns;

  case FWrapMode of
    cWrapOff:
      FWrapInfo.WrapColumn:= 0;
    cWrapOn:
      FWrapInfo.WrapColumn:= Max(ATEditorOptions.MinWrapColumn, NNewVisibleColumns-FWrapAddSpace);
    cWrapAtWindowOrMargin:
      FWrapInfo.WrapColumn:= Max(ATEditorOptions.MinWrapColumn, Min(NNewVisibleColumns-FWrapAddSpace, FMarginRight));
  end;

  UseCachedUpdate:=
    (FWrapInfo.Count>0) and
    (CurStrings.Count>ATEditorOptions.MaxLinesForOldWrapUpdate) and
    (not CurStrings.ListUpdatesHard) and
    (CurStrings.ListUpdates.Count>0);
  //UseCachedUpdate:= false;////to disable

  FWrapTemps.Clear;

  if not UseCachedUpdate then
  begin
    FWrapInfo.Clear;
    FWrapInfo.SetCapacity(CurStrings.Count);
    for i:= 0 to CurStrings.Count-1 do
    begin
      DoCalcWrapInfos(i, NIndentMaximal, FWrapTemps, bConsiderFolding);
      for j:= 0 to FWrapTemps.Count-1 do
        FWrapInfo.Add(FWrapTemps[j]);
    end;
    FWrapTemps.Clear;
  end
  else
  begin
    //cached WrapInfo update - calculate info only for changed lines (Strings.ListUpdates)
    //and insert results into WrapInfo
    ListNums:= TATIntegerList.Create;
    try
      ListNums.Assign(CurStrings.ListUpdates);

      for i:= 0 to ListNums.Count-1 do
      begin
        NLine:= ListNums[i];
        DoCalcWrapInfos(NLine, NIndentMaximal, FWrapTemps, bConsiderFolding);
        if FWrapTemps.Count=0 then Continue;

        FWrapInfo.FindIndexesOfLineNumber(NLine, NIndexFrom, NIndexTo);
        if NIndexFrom<0 then
        begin
          //Showmessage('Cant find wrap-index for line '+Inttostr(NLine));
          Continue;
        end;

        //slow for 100carets, 1M lines, so made method in which
        //we can optimize it (instead of del/ins do assign)
        FWrapInfo.ReplaceItems(NIndexFrom, NIndexTo, FWrapTemps);
      end;
      FWrapTemps.Clear;
    finally
      FreeAndNil(ListNums);
    end;
  end;

  CurStrings.ListUpdates.Clear;
  CurStrings.ListUpdatesHard:= false;

  {$ifdef debug_findwrapindex}
  DebugFindWrapIndex;
  {$endif}
end;


procedure _CalcWrapInfos(
  AStrings: TATStrings;
  ATabHelper: TATStringTabHelper;
  AEditorIndex: integer;
  AWrapColumn: integer;
  AWrapIndented: boolean;
  AVisibleColumns: integer;
  const ANonWordChars: atString;
  ALineIndex: integer;
  AIndentMaximal: integer;
  AItems: TATWrapItems;
  AConsiderFolding: boolean);
var
  WrapItem: TATWrapItem;
  NPartOffset, NLen, NIndent, NVisColumns: integer;
  NFoldFrom: integer;
  FinalState: TATWrapItemFinal;
  bInitialItem: boolean;
  StrPart: atString;
begin
  AItems.Clear;

  //line folded entirely?
  if AConsiderFolding then
    if AStrings.LinesHidden[ALineIndex, AEditorIndex] then Exit;

  NLen:= AStrings.LinesLen[ALineIndex];

  if NLen=0 then
  begin
    WrapItem.Init(ALineIndex, 1, 0, 0, cWrapItemFinal, true);
    AItems.Add(WrapItem);
    Exit;
  end;

  //consider fold, before wordwrap
  if AConsiderFolding then
  begin
    //line folded partially?
    NFoldFrom:= AStrings.LinesFoldFrom[ALineIndex, AEditorIndex];
    if NFoldFrom>0 then
    begin
      WrapItem.Init(ALineIndex, 1, Min(NLen, NFoldFrom-1), 0, cWrapItemCollapsed, true);
      AItems.Add(WrapItem);
      Exit;
    end;
  end;

  //line not wrapped?
  if (AWrapColumn<ATEditorOptions.MinWrapColumnAbs) then
  begin
    WrapItem.Init(ALineIndex, 1, NLen, 0, cWrapItemFinal, true);
    AItems.Add(WrapItem);
    Exit;
  end;

  NVisColumns:= Max(AVisibleColumns, ATEditorOptions.MinWrapColumnAbs);
  NPartOffset:= 1;
  NIndent:= 0;
  bInitialItem:= true;

  repeat
    StrPart:= AStrings.LineSub(ALineIndex, NPartOffset, NVisColumns);
    if StrPart='' then Break;

    NLen:= ATabHelper.FindWordWrapOffset(
      ALineIndex,
      //very slow to calc for entire line (eg len=70K),
      //calc for first NVisColumns chars
      StrPart,
      Max(AWrapColumn-NIndent, ATEditorOptions.MinWrapColumnAbs),
      ANonWordChars,
      AWrapIndented);

    if NLen>=Length(StrPart) then
      FinalState:= cWrapItemFinal
    else
      FinalState:= cWrapItemMiddle;

    WrapItem.Init(ALineIndex, NPartOffset, NLen, NIndent, FinalState, bInitialItem);
    AItems.Add(WrapItem);
    bInitialItem:= false;

    if AWrapIndented then
      if NPartOffset=1 then
      begin
        NIndent:= ATabHelper.GetIndentExpanded(ALineIndex, StrPart);
        NIndent:= Min(NIndent, AIndentMaximal);
      end;

    Inc(NPartOffset, NLen);
  until false;
end;


procedure TATSynEdit.DoCalcWrapInfos(ALine: integer; AIndentMaximal: integer; AItems: TATWrapItems;
  AConsiderFolding: boolean);
begin
  _CalcWrapInfos(
    Strings,
    FTabHelper,
    FEditorIndex,
    FWrapInfo.WrapColumn,
    FWrapIndented,
    GetVisibleColumns,
    FOptNonWordChars,
    ALine,
    AIndentMaximal,
    AItems,
    AConsiderFolding);
end;


function TATSynEdit.GetVisibleLines: integer;
begin
  Result:= FRectMainVisible.Height div FCharSize.Y;
end;

function TATSynEdit.GetVisibleColumns: integer;
begin
  Result:= FRectMainVisible.Width * ATEditorCharXScale div FCharSize.XScaled;
end;

function TATSynEdit.GetVisibleLinesMinimap: integer;
begin
  Result:= FRectMinimap.Height div FCharSizeMinimap.Y - 1;
end;

function TATSynEdit.GetActualDragDropIsCopying: boolean;
begin
  Result:= FOptMouseDragDropCopying and
    (FOptMouseDragDropCopyingWithState in GetKeyShiftState);
end;

function TATSynEdit.GetActualProximityVert: integer;
begin
  Result:= FOptCaretProximityVert;
  if Result>0 then
    Result:= Min(Min(Result, 10), GetVisibleLines div 2 - 1)
end;

function TATSynEdit.GetMinimapScrollPos: integer;
begin
  Result:=
    Int64(Max(0, FScrollVert.NPos)) *
    Max(0, FScrollVert.NMax-GetVisibleLinesMinimap) div
    Max(1, FScrollVert.NMax-FScrollVert.NPage);
end;

procedure TATSynEdit.SetTabSize(AValue: integer);
begin
  if FTabSize=AValue then Exit;
  FTabSize:= Min(ATEditorOptions.MaxTabSize, Max(ATEditorOptions.MinTabSize, AValue));
  FWrapUpdateNeeded:= true;
  FTabHelper.TabSize:= FTabSize;
end;

procedure TATSynEdit.SetTabSpaces(AValue: boolean);
begin
  if FOptTabSpaces=AValue then Exit;
  FOptTabSpaces:= AValue;
  FTabHelper.TabSpaces:= AValue;
end;

procedure TATSynEdit.SetText(const AValue: UnicodeString);
begin
  Strings.LoadFromString(UTF8Encode(AValue));

  DoCaretSingle(0, 0);
  if Assigned(FMarkers) then
    FMarkers.Clear;
  if Assigned(FAttribs) then
    FAttribs.Clear;
  if Assigned(FLinkCache) then
    FLinkCache.Clear;

  Update(true);
end;

procedure TATSynEdit.SetWrapMode(AValue: TATEditorWrapMode);
var
  NLine: integer;
  Caret: TATCaretItem;
begin
  if FWrapMode=AValue then Exit;

  //disable setting wrap=on for too big files
  if FWrapMode=cWrapOff then
    if Strings.Count>=FWrapEnabledForMaxLines then exit;

  NLine:= LineTop;
  FWrapMode:= AValue;

  FWrapUpdateNeeded:= true;
  UpdateWrapInfo; //helps to solve https://github.com/Alexey-T/CudaText/issues/2879
                  //FWrapUpdateNeeded:=true and Update() is not enough

  if FWrapMode<>cWrapOff then
    FScrollHorz.SetZero;

  Update;
  LineTop:= NLine;

  //when very long line has caret at end, and we toggle wordwrap, let's scroll to new caret pos
  if FWrapMode=cWrapOff then
    if Carets.Count=1 then
    begin
      Caret:= Carets[0];
      if Caret.PosX>0 then
        DoShowPos(
          Point(Caret.PosX, Caret.PosY),
          FOptScrollIndentCaretHorz,
          FOptScrollIndentCaretVert,
          true,
          true,
          false);
      end;
end;

procedure TATSynEdit.SetWrapIndented(AValue: boolean);
begin
  if FWrapIndented=AValue then Exit;
  FWrapIndented:=AValue;
  if FWrapMode<>cWrapOff then
    FWrapUpdateNeeded:= true;
end;

function TATSynEdit.UpdateScrollbars(AdjustSmoothPos: boolean): boolean;
//returns True is scrollbars visibility was changed
var
  bVert1, bVert2, bHorz1, bHorz2: boolean;
  bVertOur1, bVertOur2, bHorzOur1, bHorzOur2: boolean;
  bChangedBarsOs, bChangedBarsOur: boolean;
  NPos, NLineIndex, NGapPos, NGapAll: integer;
begin
  Result:= false;

  if ModeOneLine then
  begin
    FScrollbarVert.Hide;
    FScrollbarHorz.Hide;
    //don't exit, we still need calculation of FScrollHorz fields
  end;

  NGapAll:= 0;
  NGapPos:= 0;

  //consider Gaps for vertical scrollbar
  if Gaps.Count>0 then
  begin
    if AdjustSmoothPos then
    begin
      NLineIndex:= 0;
      NPos:= Max(0, FScrollVert.NPos);
      if FWrapInfo.IsIndexValid(NPos) then
        NLineIndex:= FWrapInfo.Data[NPos].NLineIndex;
      NGapPos:= Gaps.SizeForLineRange(-1, NLineIndex-1);
    end;

    NGapAll:= Gaps.SizeForAll;
  end;

  if not ModeOneLine then
  with FScrollVert do
  begin
    NPage:= Max(1, GetVisibleLines)-1;
    NMax:= Max(0, FWrapInfo.Count-1); //must be 0 for single line text
    if FOptLastLineOnTop then
      Inc(NMax, NPage);
    NPosLast:= Max(0, NMax-NPage);

    CharSizeScaled:= FCharSize.Y * ATEditorCharXScale;
    SmoothMax:= NMax * CharSizeScaled div ATEditorCharXScale + NGapAll;
    SmoothPage:= NPage * CharSizeScaled div ATEditorCharXScale;
    SmoothPosLast:= Max(0, SmoothMax - SmoothPage);
    if AdjustSmoothPos then
      SmoothPos:= TotalOffset + NGapPos;
  end;

  with FScrollHorz do
  begin
    NPage:= Max(1, GetVisibleColumns);
    //NMax is calculated in DoPaintText
    //hide horz bar for word-wrap:
    if FWrapMode=cWrapOn then
      NMax:= NPage;
    NPosLast:= Max(0, NMax-NPage);

    CharSizeScaled:= FCharSize.XScaled;
    SmoothMax:= NMax * CharSizeScaled div ATEditorCharXScale;
    SmoothPage:= NPage * CharSizeScaled div ATEditorCharXScale;
    SmoothPosLast:= Max(0, SmoothMax - SmoothPage);
    if AdjustSmoothPos then
      SmoothPos:= TotalOffset;
  end;

  //don't need further code for OneLine
  if ModeOneLine then exit;

  bVert1:= ShowOsBarVert;
  bHorz1:= ShowOsBarHorz;
  bVertOur1:= FScrollbarVert.Visible;
  bHorzOur1:= FScrollbarHorz.Visible;

  UpdateScrollbarVert;
  UpdateScrollbarHorz;

  bVert2:= ShowOsBarVert;
  bHorz2:= ShowOsBarHorz;
  bVertOur2:= FScrollbarVert.Visible;
  bHorzOur2:= FScrollbarHorz.Visible;

  bChangedBarsOs:= (bVert1<>bVert2) or (bHorz1<>bHorz2);
  bChangedBarsOur:= (bVertOur1<>bVertOur2) or (bHorzOur1<>bHorzOur2);

  Result:= bChangedBarsOs or bChangedBarsOur;
  if Result then
    UpdateClientSizes;

  if (FPrevHorz<>FScrollHorz) or
    (FPrevVert<>FScrollVert) then
  begin
    FPrevHorz:= FScrollHorz;
    FPrevVert:= FScrollVert;
    Include(FPaintFlags, cIntFlagScrolled);
  end;
end;

procedure TATSynEdit.UpdateScrollbarVert;
var
  NeedBar: boolean;
  si: TScrollInfo;
  NDelta: Int64;
begin
  case FOptScrollStyleVert of
    aessHide:
      NeedBar:= false;
    aessShow:
      NeedBar:= true;
    aessAuto:
      NeedBar:= (FScrollVert.SmoothPos>0) or (FScrollVert.NMax>FScrollVert.NPage);
  end;

  FScrollbarVert.Visible:= NeedBar and FOptScrollbarsNew;
  ShowOsBarVert:= NeedBar and not FOptScrollbarsNew;

  if FScrollbarVert.Visible then
  begin
    FScrollbarLock:= true;

    //if option "minimap on scrollbar" on, scrollbar shows all lines (from 0 to St.Count-1)
    //including folded lines.
    //if option is off, it shows smaller range, if lines are folded.
    if FMicromapOnScrollbar then
    begin
      if FOptScrollSmooth then
        NDelta:= FCharSize.Y
      else
        NDelta:= 1;
      FScrollbarVert.Min:= 0;
      FScrollbarVert.Max:= NDelta * Max(0, Strings.Count-1);
      FScrollbarVert.SmallChange:= NDelta;
      FScrollbarVert.PageSize:= NDelta * Max(1, GetVisibleLines);
      FScrollbarVert.Position:= NDelta * LineTop;
    end
    else
    begin
      FScrollbarVert.Min:= 0;
      FScrollbarVert.Max:= FScrollVert.SmoothMax;
      FScrollbarVert.SmallChange:= FScrollVert.CharSizeScaled div ATEditorCharXScale;
      FScrollbarVert.PageSize:= FScrollVert.SmoothPage;
      FScrollbarVert.Position:= FScrollVert.SmoothPos;
    end;

    FScrollbarVert.Update;
    FScrollbarLock:= false;
  end;

  if ShowOsBarVert then
  begin
    FillChar(si{%H-}, SizeOf(si), 0);
    si.cbSize:= SizeOf(si);
    si.fMask:= SIF_ALL; //or SIF_DISABLENOSCROLL; //todo -- DisableNoScroll doesnt work(Win)
    si.nMin:= 0;
    si.nMax:= FScrollVert.SmoothMax;
    si.nPage:= FScrollVert.SmoothPage;
    //if FOptScrollbarsNew then
    //  si.nPage:= si.nMax+1;
    si.nPos:= FScrollVert.SmoothPos;
    SetScrollInfo(Handle, SB_VERT, si, True);
  end;

  {$ifdef debug_scroll}
  Writeln(Format('ATSynEdit SetScrollInfo: SB_VERT, nMin=%d, nMax=%d, nPage=%d, nPos=%d',
    [FScrollVert.NMin, FScrollVert.NMax, FScrollVert.NPage, FScrollVert.NPos]));
  {$endif}
end;

procedure TATSynEdit.UpdateScrollbarHorz;
var
  NeedBar: boolean;
  si: TScrollInfo;
begin
  case FOptScrollStyleHorz of
    aessHide:
      NeedBar:= false;
    aessShow:
      NeedBar:= true;
    aessAuto:
      NeedBar:= (FScrollHorz.SmoothPos>0) or (FScrollHorz.NMax>FScrollHorz.NPage);
  end;

  FScrollbarHorz.Visible:= NeedBar and FOptScrollbarsNew;
  ShowOsBarHorz:= NeedBar and not FOptScrollbarsNew;

  if FScrollbarHorz.Visible then
  begin
    FScrollbarLock:= true;
    FScrollbarHorz.Min:= 0;
    FScrollbarHorz.Max:= FScrollHorz.SmoothMax;
    FScrollbarHorz.SmallChange:= FScrollHorz.CharSizeScaled div ATEditorCharXScale;
    FScrollbarHorz.PageSize:= FScrollHorz.SmoothPage;
    FScrollbarHorz.Position:= FScrollHorz.SmoothPos;
    FScrollbarHorz.Update;
    if FScrollbarVert.Visible then
      FScrollbarHorz.IndentCorner:= 100
    else
      FScrollbarHorz.IndentCorner:= 0;
    FScrollbarLock:= false;
  end;

  if ShowOsBarHorz then
  begin
    FillChar(si{%H-}, SizeOf(si), 0);
    si.cbSize:= SizeOf(si);
    si.fMask:= SIF_ALL; //or SIF_DISABLENOSCROLL; don't work
    si.nMin:= 0;
    si.nMax:= FScrollHorz.SmoothMax;
    si.nPage:= FScrollHorz.SmoothPage;
    //if FOptScrollbarsNew or FOptScrollbarHorizontalHidden then
    //  si.nPage:= si.nMax+1;
    si.nPos:= FScrollHorz.SmoothPos;
    SetScrollInfo(Handle, SB_HORZ, si, True);
  end;

  {$ifdef debug_scroll}
  Writeln(Format('ATSynEdit SetScrollInfo: SB_HORZ, nMin=%d, nMax=%d, nPage=%d, nPos=%d',
    [FScrollHorz.NMin, FScrollHorz.NMax, FScrollHorz.NPage, FScrollHorz.NPos]));
  {$endif}
end;

procedure TATSynEdit.GetRectMain(out R: TRect);
begin
  R.Left:= FRectGutter.Left + FTextOffset.X;
  R.Top:= FTextOffset.Y;
  R.Right:= ClientWidth
    - IfThen(FMinimapVisible and not FMinimapAtLeft, FMinimapWidth)
    - IfThen(FMicromapVisible and not FMicromapOnScrollbar, FRectMicromap.Width);
  R.Bottom:= ClientHeight;

  FRectMainVisible:= R;

  if FOptScrollSmooth then
  begin
    Dec(R.Left, FScrollHorz.NPixelOffset);
    Dec(R.Top, FScrollVert.NPixelOffset);
  end;
end;

procedure TATSynEdit.GetRectMinimap(out R: TRect);
begin
  if not FMinimapVisible then
  begin
    R:= cRectEmpty;
    exit
  end;

  if FMinimapAtLeft then
    R.Left:= 0
  else
    R.Left:= ClientWidth-FMinimapWidth-IfThen(FMicromapVisible and not FMicromapOnScrollbar, FRectMicromap.Width);

  R.Right:= R.Left+FMinimapWidth;
  R.Top:= 0;
  R.Bottom:= ClientHeight;
end;

procedure TATSynEdit.GetRectMinimapSel(out R: TRect);
begin
  R.Left:= FRectMinimap.Left;
  R.Right:= FRectMinimap.Right;
  R.Top:= GetMinimapSelTop;
  R.Bottom:= Min(
    R.Top + (GetVisibleLines+1)*FCharSizeMinimap.Y,
    FRectMinimap.Bottom
    );
end;

procedure TATSynEdit.GetRectMicromap(out R: TRect);
var
  NSize: integer;
begin
  NSize:= FMicromap.UpdateSizes(ATEditorScale(FCharSize.XScaled) div ATEditorCharXScale);

  if not FMicromapVisible or FMicromapOnScrollbar then
  begin
    R:= cRectEmpty;
  end
  else
  begin
    R.Top:= 0;
    R.Bottom:= ClientHeight;
    R.Right:= ClientWidth;
    R.Left:= R.Right-NSize;
  end;

  FMicromap.UpdateCoords;
  FMicromapScaleDiv:= Max(1, Strings.Count);
  if OptLastLineOnTop then
    FMicromapScaleDiv:= Max(1, FMicromapScaleDiv+GetVisibleLines-1);
end;

procedure TATSynEdit.GetRectGutter(out R: TRect);
begin
  R.Left:= IfThen(FMinimapVisible and FMinimapAtLeft, FMinimapWidth);
  R.Top:= IfThen(FOptRulerVisible, FRulerHeight);
  R.Right:= R.Left + FGutter.Width;
  R.Bottom:= ClientHeight;

  if not FOptGutterVisible then
  begin
    R.Right:= R.Left;
    R.Bottom:= R.Top;
    exit
  end;

  Gutter.GutterLeft:= R.Left;
  Gutter.Update;
end;

procedure TATSynEdit.GetRectRuler(out R: TRect);
begin
  if not FOptRulerVisible then
  begin
    R:= cRectEmpty;
    exit
  end;

  R.Left:= FRectGutter.Left;
  R.Right:= FRectMain.Right;
  R.Top:= 0;
  R.Bottom:= R.Top + FRulerHeight;
end;

procedure TATSynEdit.GetRectGutterNumbers(out R: TRect);
begin
  if FOptGutterVisible and FGutter[FGutterBandNumbers].Visible then
  begin
    R.Left:= FGutter[FGutterBandNumbers].Left;
    R.Right:= FGutter[FGutterBandNumbers].Right;
    R.Top:= FRectGutter.Top;
    R.Bottom:= FRectGutter.Bottom;
  end
  else
    R:= cRectEmpty;
end;

procedure TATSynEdit.GetRectGutterBookmarks(out R: TRect);
begin
  if FOptGutterVisible and FGutter[FGutterBandBookmarks].Visible then
  begin
    R.Left:= FGutter[FGutterBandBookmarks].Left;
    R.Right:= FGutter[FGutterBandBookmarks].Right;
    R.Top:= FRectGutter.Top;
    R.Bottom:= FRectGutter.Bottom;
  end
  else
    R:= cRectEmpty;
end;


procedure TATSynEdit.UpdateClientSizes;
begin
  GetClientSizes(FClientW, FClientH);
end;

procedure TATSynEdit.UpdateInitialVars(C: TCanvas);
begin
  UpdateClientSizes;

  C.Font.Name:= Font.Name;
  C.Font.Size:= DoScaleFont(Font.Size);

  FCharSize:= GetCharSize(C, FSpacingY);

  if FSpacingY<0 then
    FTextOffsetFromTop:= FSpacingY
  else
    FTextOffsetFromTop:= 0;
  FTextOffsetFromTop1:= FTextOffsetFromTop; //"-1" gives artifacts on gutter bands

  if FMinimapCustomScale<100 then
  begin
    FCharSizeMinimap.XScaled:= ATEditorScale(1) * ATEditorCharXScale;
    FCharSizeMinimap.Y:= ATEditorScale(2);
  end
  else
  begin
    FCharSizeMinimap.XScaled:= 1 * FMinimapCustomScale div 100 * ATEditorCharXScale;
    FCharSizeMinimap.Y:= 2 * FMinimapCustomScale div 100;
  end;

  FNumbersIndent:= FCharSize.XScaled * FOptNumbersIndentPercents div 100 div ATEditorCharXScale;
  FRulerHeight:= FCharSize.Y * FOptRulerHeightPercents div 100;

  if FOptGutterVisible and FOptNumbersAutosize then
    UpdateGutterAutosize;

  FTextOffset:= GetTextOffset; //after gutter autosize

  if FMinimapVisible then
    UpdateMinimapAutosize; //after FTextOffset

  GetRectMicromap(FRectMicromap);
  GetRectMinimap(FRectMinimap); //after micromap
  GetRectGutter(FRectGutter);
  GetRectMain(FRectMain); //after gutter/minimap/micromap
  GetRectRuler(FRectRuler); //after main
  GetRectGutterBookmarks(FRectGutterBm); //after gutter
  GetRectGutterNumbers(FRectGutterNums); //after gutter
end;

procedure TATSynEdit.DoPaintMain(C: TCanvas; ALineFrom: integer);
const
  cTextMacro = 'R';
begin
  C.Brush.Color:= FColorBG;
  C.FillRect(0, 0, Width, Height); //avoid FClientW here to fill entire area

  UpdateWrapInfo; //update WrapInfo before MinimapThread start

  if FMinimapVisible then
  begin
    {$ifdef map_th}
    if not Assigned(FMinimapThread) then
    begin
      FEventMapStart:= TSimpleEvent.Create;
      FEventMapDone:= TSimpleEvent.Create;
      FMinimapThread:= TATMinimapThread.Create(true);
      FMinimapThread.FreeOnTerminate:= false;
      FMinimapThread.Editor:= Self;
      FMinimapThread.Start;
    end;
    FEventMapStart.SetEvent;
    {$else}
    DoPaintMinimapAllToBGRABitmap;
    {$endif}
  end;

  UpdateLinksAttribs;
  DoPaintText(C, FRectMain, FCharSize, FOptGutterVisible, FScrollHorz, FScrollVert, ALineFrom);
  DoPaintMargins(C);
  DoPaintNiceScroll(C);

  if FOptRulerVisible then
  begin
    DoPaintRuler(C);
    if Assigned(FOnDrawRuler) then
      FOnDrawRuler(Self, C, FRectRuler);
  end;

  if Assigned(FOnDrawEditor) then
    FOnDrawEditor(Self, C, FRectMain);

  if FMicromapVisible and not FMicromapOnScrollbar then
    DoPaintMicromap(C);

  if FOptBorderMacroRecording and FIsMacroRecording then
  begin
    DoPaintBorder(C, Colors.MacroRecordBorder, FOptBorderWidthMacro, true);
    C.Brush.Color:= Colors.MacroRecordBorder;
    C.Font.Color:= Colors.TextSelFont;
    CanvasTextOutSimplest(C,
      FRectMain.Right-Length(cTextMacro)*FCharSize.XScaled div ATEditorCharXScale - FOptBorderWidthMacro,
      FRectMain.Bottom-FCharSize.Y,
      cTextMacro);
  end
  else
  if FOptBorderFocusedActive and FIsEntered and (FOptBorderWidthFocused>0) then
    DoPaintBorder(C, Colors.BorderLineFocused, FOptBorderWidthFocused, false)
  else
  if FOptBorderVisible and (FOptBorderWidth>0) then
    DoPaintBorder(C, Colors.BorderLine, FOptBorderWidth, false);

  if FOptShowMouseSelFrame then
    if FMouseDragCoord.X>=0 then
      DoPaintMouseSelFrame(C);

  if FMinimapVisible then
  begin
    if FMinimapTooltipVisible and FMinimapTooltipEnabled then
      DoPaintMinimapTooltip(C);

    {$ifdef map_th}
    if FEventMapDone.WaitFor(1000)=wrSignaled then
    begin
      FEventMapDone.ResetEvent;
      FMinimapBmp.Draw(C, FRectMinimap.Left, FRectMinimap.Top);
    end;
    {$else}
    FMinimapBmp.Draw(C, FRectMinimap.Left, FRectMinimap.Top);
    {$endif}
  end;
end;

procedure TATSynEdit.DoPaintMouseSelFrame(C: TCanvas);
const
  cMinSize = 4; //minimal width/height of the frame in pixels
var
  X1, X2, Y1, Y2: integer;
  XX1, XX2, YY1, YY2: integer;
begin
  if not FOptMouseEnableNormalSelection then exit;

  if FMouseDownCoord.Y<0 then exit;

  X1:= FMouseDownCoord.X - FScrollHorz.TotalOffset;
  X2:= FMouseDragCoord.X;
  Y1:= FMouseDownCoord.Y - FScrollVert.TotalOffset;
  Y2:= FMouseDragCoord.Y;

  XX1:= Max(-1, Min(X1, X2));
  YY1:= Max(-1, Min(Y1, Y2));
  XX2:= Min(Width+1, Max(X1, X2));
  YY2:= Min(Height+1, Max(Y1, Y2));

  if XX1<0 then exit;
  if XX2-XX1<cMinSize then exit;
  if YY2-YY1<cMinSize then exit;

  //avoid TCanvas.DrawFocusRect(), sometimes it's painted bad on Qt5
  C.Pen.Color:= ColorBlendHalf(Colors.TextFont, Colors.TextBG);
  CanvasLineHorz(C, XX1, YY1, XX2, true);
  CanvasLineHorz(C, XX1, YY2, XX2, true);
  CanvasLineVert(C, XX1, YY1, YY2, true);
  CanvasLineVert(C, XX2, YY1, YY2, true);
end;

procedure TATSynEdit.DoPaintBorder(C: TCanvas; AColor: TColor;
  ABorderWidth: integer; AUseRectMain: boolean);
var
  NColorBG, NColorFore: TColor;
  W, H, i: integer;
begin
  if ABorderWidth<1 then exit;
  C.Pen.Color:= AColor;

  if AUseRectMain then
  begin
    W:= FRectMain.Right;
    H:= FRectMain.Bottom;
  end
  else
  begin
    W:= ClientWidth;
    H:= ClientHeight;
  end;

  for i:= 0 to ABorderWidth-1 do
    C.Frame(i, i, W-i, H-i);

  if FOptBorderVisible and FOptBorderRounded and (ABorderWidth=1) then
  begin
    NColorBG:= ColorToRGB(Colors.BorderParentBG);
    NColorFore:= ColorToRGB(Colors.TextBG);

    CanvasPaintRoundedCorners(C,
      Rect(0, 0, W, H),
      [acckLeftTop, acckLeftBottom],
      NColorBG, AColor, NColorFore);

    if ModeOneLine and FMicromapVisible then
      NColorFore:= Colors.ComboboxArrowBG;

    CanvasPaintRoundedCorners(C,
      Rect(0, 0, W, H),
      [acckRightTop, acckRightBottom],
      NColorBG, AColor, NColorFore);
  end;
end;

function TATSynEdit.GetCharSize(C: TCanvas; ACharSpacingY: integer): TATEditorCharSize;
const
  SampleChar = 'N';
var
  SampleStrLen: integer;
  SampleStr: string;
  Size: TSize;
  TempC: TCanvas;
  dc: HDC;
begin
  if ATEditorOptions.PreciseCalculationOfCharWidth then
    SampleStrLen:= 128
  else
    SampleStrLen:= 1;

  SampleStr:= StringOfChar(SampleChar, SampleStrLen);

  if C.HandleAllocated then
  begin
    Size:= C.TextExtent(SampleStr);
  end
  else
  begin
    TempC:= TCanvas.Create;
    try
      dc:= GetDC(0);
      TempC.Handle:= dc;
      TempC.Font.Name:= Self.Font.Name;
      TempC.Font.Size:= DoScaleFont(Self.Font.Size);
      Size:= TempC.TextExtent(SampleStr);
      ReleaseDC(dc, 0);
    finally
      FreeAndNil(TempC);
    end;
  end;

  Result.XScaled:= Max(1, Size.cx) * ATEditorCharXScale div SampleStrLen;
  Result.Y:= Max(1, Size.cy + ACharSpacingY);
end;

procedure TATSynEdit.DoPaintGutterBandBG(C: TCanvas; AColor: TColor;
  AX1, AY1, AX2, AY2: integer; AEntireHeight: boolean);
begin
  if not AEntireHeight then
  begin
    C.Brush.Color:= AColor;
    C.FillRect(AX1, AY1, AX2, AY2);
  end
  else
  begin
    C.Brush.Color:= AColor;
    C.FillRect(AX1, FRectGutter.Top, AX2, FRectGutter.Bottom);
  end;
end;


procedure TATSynEdit.DoPaintText(C: TCanvas;
  const ARect: TRect;
  const ACharSize: TATEditorCharSize;
  AWithGutter: boolean;
  var AScrollHorz, AScrollVert: TATEditorScrollInfo;
  ALineFrom: integer);
var
  RectLine: TRect;
  GapItemTop, GapItemCur: TATGapItem;
  GutterItem: TATGutterItem;
  WrapItem: TATWrapItem;
  NWrapIndex, NWrapIndexDummy, NLineCount: integer;
begin
  //wrap turned off can cause bad scrollpos, fix it
  with AScrollVert do
    NPos:= Min(NPos, NPosLast);

  C.Brush.Color:= FColorBG;
  C.FillRect(ARect);

  if Assigned(FFoldedMarkList) then
    FFoldedMarkList.Clear;

  if AWithGutter then
  begin
    FColorOfStates[cLineStateNone]:= -1;
    FColorOfStates[cLineStateChanged]:= Colors.StateChanged;
    FColorOfStates[cLineStateAdded]:= Colors.StateAdded;
    FColorOfStates[cLineStateSaved]:= Colors.StateSaved;

    C.Brush.Color:= FColorGutterBG;
    C.FillRect(FRectGutter);

    //paint some bands, for full height coloring
    GutterItem:= FGutter[FGutterBandFolding];
    if GutterItem.Visible then
      DoPaintGutterBandBG(C,
        FColorGutterFoldBG,
        GutterItem.Left,
        -1,
        GutterItem.Right,
        -1,
        true);

    GutterItem:= FGutter[FGutterBandSeparator];
    if GutterItem.Visible then
      DoPaintGutterBandBG(C,
        Colors.GutterSeparatorBG,
        GutterItem.Left,
        -1,
        GutterItem.Right,
        -1,
        true);

    GutterItem:= FGutter[FGutterBandEmpty];
    if GutterItem.Visible then
      DoPaintGutterBandBG(C,
        FColorBG,
        GutterItem.Left,
        -1,
        GutterItem.Right,
        -1,
        true);
  end;

  if (FTextHint<>'') then
  begin
    NLineCount:= Strings.Count;
    if (NLineCount=0) or ((NLineCount=1) and (Strings.LinesLen[0]=0)) then
    begin
      DoPaintTextHintTo(C);
      Exit
    end;
  end;

  {$ifndef fix_horzscroll}
  AScrollHorz.NMax:= 1;
  {$endif}

  if ALineFrom>=0 then
  begin
    FWrapInfo.FindIndexesOfLineNumber(ALineFrom, NWrapIndex, NWrapIndexDummy);
    DoScroll_SetPos(AScrollVert, NWrapIndex);
      //last param True, to continue scrolling after resize
  end
  else
  begin
    NWrapIndex:= Max(0, AScrollVert.NPos);
  end;

  if FFoldCacheEnabled then
    InitFoldbarCache(NWrapIndex);

  DoEventBeforeCalcHilite;

  RectLine.Left:= ARect.Left;
  RectLine.Right:= ARect.Right;
  RectLine.Top:= 0;
  RectLine.Bottom:= ARect.Top;

  repeat
    RectLine.Top:= RectLine.Bottom;
    RectLine.Bottom:= RectLine.Top+ACharSize.Y;
    if RectLine.Top>ARect.Bottom then Break;

    if not FWrapInfo.IsIndexValid(NWrapIndex) then
    begin
      //paint end-of-file arrow
      if NWrapIndex>=0 then
        if OptUnprintedVisible and OptUnprintedEof then
          if OptUnprintedEndsDetails then
            DoPaintUnprintedSymbols(C,
              cEndingTextEOF,
              ARect.Left,
              RectLine.Top,
              ACharSize,
              Colors.UnprintedFont,
              Colors.UnprintedBG)
          else
            CanvasArrowHorz(C,
              RectLine,
              Colors.UnprintedFont,
              ATEditorOptions.UnprintedEofCharLength*ACharSize.XScaled div ATEditorCharXScale,
              false,
              ATEditorOptions.UnprintedTabPointerScale);
      Break;
    end;

    WrapItem:= FWrapInfo[NWrapIndex];
    GapItemTop:= nil;
    GapItemCur:= nil;

    //consider gap before 1st line
    if (NWrapIndex=0) and AScrollVert.TopGapVisible and (Gaps.SizeOfGapTop>0) then
    begin
      GapItemTop:= Gaps.Find(-1);
      if Assigned(GapItemTop) then
        Inc(RectLine.Bottom, GapItemTop.Size);
    end;

    //consider gap for this line
    if WrapItem.NFinal=cWrapItemFinal then
    begin
      GapItemCur:= Gaps.Find(WrapItem.NLineIndex);
      if Assigned(GapItemCur) then
        Inc(RectLine.Bottom, GapItemCur.Size);
    end;

    //paint gap before 1st line
    if Assigned(GapItemTop) then
    begin
      DoPaintGap(C,
        Rect(
          RectLine.Left,
          RectLine.Top,
          RectLine.Right,
          RectLine.Top+GapItemTop.Size),
        GapItemTop);
      Inc(RectLine.Top, GapItemTop.Size);
    end;

    DoPaintLine(C,
      RectLine,
      ACharSize,
      AScrollHorz,
      NWrapIndex,
      FParts);

    //paint gap after line
    if Assigned(GapItemCur) then
      DoPaintGap(C,
        Rect(
          RectLine.Left,
          RectLine.Top+ACharSize.Y,
          RectLine.Right,
          RectLine.Top+ACharSize.Y+GapItemCur.Size),
        GapItemCur);

    if AWithGutter then
      DoPaintGutterOfLine(C, RectLine, ACharSize, NWrapIndex);

    //update LineBottom as index of last painted line
    FLineBottom:= WrapItem.NLineIndex;

    Inc(NWrapIndex);
  until false;

  //block staples
  DoPaintStaples(C, ARect, ACharSize, AScrollHorz);
end;

procedure TATSynEdit.DoPaintMinimapTextToBGRABitmap(
  const ARect: TRect;
  const ACharSize: TATEditorCharSize;
  var AScrollHorz, AScrollVert: TATEditorScrollInfo);
var
  RectLine: TRect;
  NWrapIndex: integer;
begin
  FMinimapBmp.SetSize(ARect.Width, ARect.Height);
  FMinimapBmp.Fill(FColorBG);

  //wrap turned off can cause bad scrollpos, fix it
  with AScrollVert do
    NPos:= Min(NPos, NPosLast);

  NWrapIndex:= Max(0, AScrollVert.NPos);

  RectLine.Left:= ARect.Left;
  RectLine.Right:= ARect.Right;
  RectLine.Top:= 0;
  RectLine.Bottom:= ARect.Top;

  repeat
    RectLine.Top:= RectLine.Bottom;
    RectLine.Bottom:= RectLine.Top+ACharSize.Y;
    if RectLine.Top>ARect.Bottom then Break;

    if not FWrapInfo.IsIndexValid(NWrapIndex) then
      Break;

    DoPaintMinimapLine(RectLine, ACharSize, AScrollHorz, NWrapIndex, FPartsMinimap);

    Inc(NWrapIndex);
  until false;
end;


procedure TATSynEdit.DoPaintLine(C: TCanvas;
  const ARectLine: TRect;
  const ACharSize: TATEditorCharSize;
  var AScrollHorz: TATEditorScrollInfo;
  const AWrapIndex: integer;
  var ATempParts: TATLineParts);
  //
  procedure FillOneLine(AFillColor: TColor);
  begin
    C.Brush.Style:= bsSolid;
    C.Brush.Color:= AFillColor;
    C.FillRect(
      ARectLine.Left,
      ARectLine.Top+FTextOffsetFromTop1,
      ARectLine.Right,
      ARectLine.Bottom+FTextOffsetFromTop1
      );
  end;
  //
var
  St: TATStrings;
  NLinesIndex, NLineLen, NCount: integer;
  NOutputCharsSkipped: Int64;
  NOutputStrWidth, NOutputMaximalChars: Int64;
  NOutputCellPercentsSkipped: Int64;
  NCoordSep: Int64;
  WrapItem: TATWrapItem;
  StringItem: PATStringItem;
  NColorEntire, NColorAfter: TColor;
  NDimValue: integer;
  StrOutput: atString;
  CurrPoint, CurrPointText, CoordAfterText: TPoint;
  LineSeparator: TATLineSeparator;
  bLineWithCaret, bLineEolSelected, bLineColorForced, bLineHuge: boolean;
  Event: TATSynEditDrawLineEvent;
  TextOutProps: TATCanvasTextOutProps;
  NSubPos, NSubLen: integer;
  bHiliteLinesWithSelection: boolean;
  bTrimmedNonSpaces: boolean;
  bUseColorOfCurrentLine: boolean;
begin
  St:= Strings;
  bHiliteLinesWithSelection:= false;

  WrapItem:= FWrapInfo[AWrapIndex];
  NLinesIndex:= WrapItem.NLineIndex;
  if not St.IsIndexValid(NLinesIndex) then Exit;

  if IsFoldLineNeededBeforeWrapitem(AWrapIndex) then
  begin
    NCoordSep:= ARectLine.Top-1;
    C.Pen.Color:= Colors.CollapseLine;
    CanvasLineHorz(C,
      ARectLine.Left+FFoldUnderlineOffset,
      NCoordSep,
      ARectLine.Right-FFoldUnderlineOffset
      );
  end;

  //prepare line
  NOutputCharsSkipped:= 0;
  NOutputCellPercentsSkipped:= 0;
  NOutputStrWidth:= 0;

  CurrPoint.X:= ARectLine.Left;
  CurrPoint.Y:= ARectLine.Top;
  CurrPointText.X:= Int64(CurrPoint.X)
                    + Int64(WrapItem.NIndent)*ACharSize.XScaled div ATEditorCharXScale
                    - AScrollHorz.SmoothPos
                    + AScrollHorz.NPixelOffset;
  CurrPointText.Y:= CurrPoint.Y;
  Inc(CurrPointText.Y, FTextOffsetFromTop1);

  bTrimmedNonSpaces:= false;

  NLineLen:= St.LinesLen[NLinesIndex];
  bLineHuge:= WrapItem.NLength>ATEditorOptions.MaxLineLenForAccurateCharWidths;
          //not this: NLineLen>OptMaxLineLenForAccurateCharWidths;

  if not bLineHuge then
  begin
    //little slow for huge lines
    NSubPos:= WrapItem.NCharIndex;
    NSubLen:= Min(WrapItem.NLength, FVisibleColumns+AScrollHorz.NPos+1+6);
      //+1 because of NPixelOffset
      //+6 because of HTML color underlines
    StrOutput:= St.LineSub(NLinesIndex, NSubPos, NSubLen);

    if FUnprintedSpacesTrailing then
      bTrimmedNonSpaces:= NSubPos+NSubLen <= St.LineLenWithoutSpace(NLinesIndex);

    if WrapItem.bInitial then
    begin
      //very slow for huge lines
      FTabHelper.FindOutputSkipOffset(
        NLinesIndex,
        StrOutput,
        AScrollHorz.SmoothPos,
        ACharSize.XScaled,
        NOutputCharsSkipped,
        NOutputCellPercentsSkipped);
      Delete(StrOutput, 1, NOutputCharsSkipped);
    end;
  end
  else
  begin
    //work faster for huge lines (but not accurate horiz scrollbar)
    NOutputCharsSkipped:= AScrollHorz.SmoothPos * ATEditorCharXScale div ACharSize.XScaled;
    NOutputCellPercentsSkipped:= NOutputCharsSkipped*100;

    NSubPos:= WrapItem.NCharIndex + NOutputCharsSkipped;
    NSubLen:= Min(WrapItem.NLength, FVisibleColumns+1+6);
      //+1 because of NPixelOffset
      //+6 because of HTML color underlines
    StrOutput:= St.LineSub(NLinesIndex, NSubPos, NSubLen);

    if FUnprintedSpacesTrailing then
      bTrimmedNonSpaces:= NSubPos+NSubLen <= St.LineLenWithoutSpace(NLinesIndex);
  end;

  Inc(CurrPointText.X, NOutputCellPercentsSkipped * ACharSize.XScaled div ATEditorCharXScale div 100);

  if Length(StrOutput)>ATEditorOptions.MaxCharsForOutput then
    SetLength(StrOutput, ATEditorOptions.MaxCharsForOutput);

  if FOptMaskCharUsed then
    StrOutput:= StringOfCharW(FOptMaskChar, Length(StrOutput));

  LineSeparator:= St.LinesSeparator[NLinesIndex];
  bLineWithCaret:= IsLineWithCaret(NLinesIndex, FOptShowCurLineIfWithoutSel);
  bLineEolSelected:= IsPosSelected(WrapItem.NCharIndex-1+WrapItem.NLength, WrapItem.NLineIndex);

  //horz scrollbar max: is calculated here, to make variable horz bar
  //vert scrollbar max: is calculated in UpdateScrollbars
  case FWrapMode of
    cWrapOn:
      AScrollHorz.NMax:= GetVisibleColumns;
    cWrapAtWindowOrMargin:
      AScrollHorz.NMax:= Min(GetVisibleColumns, FMarginRight);
    else
      begin
        //avoid these calculations for huge line length=40M in wrapped mode, because
        //getter of StringItem^.Line is slow
        if bLineHuge then
          NOutputMaximalChars:= NLineLen //approximate, it don't consider CJK chars, but OK for huge lines
        else
        begin
          StringItem:= St.GetItemPtr(NLinesIndex);
          if StringItem^.HasAsciiNoTabs then
            NOutputMaximalChars:= StringItem^.CharLen
          else
            NOutputMaximalChars:= CanvasTextWidth(
              StringItem^.Line, //Line getter is very slow for huge lines
              NLinesIndex,
              FTabHelper,
              1 //pass CharWidth=1px
              );
        end;
        AScrollHorz.NMax:= Max(
          AScrollHorz.NMax,
          NOutputMaximalChars + FOptScrollbarHorizontalAddSpace);
      end;
  end;

  C.Brush.Color:= FColorBG;
  C.Font.Name:= Font.Name;
  C.Font.Size:= DoScaleFont(Font.Size);
  C.Font.Color:= FColorFont;

  bUseColorOfCurrentLine:= false;
  if bLineWithCaret then
    if FOptShowCurLine and (not FOptShowCurLineOnlyFocused or FIsEntered) then
    begin
      if FOptShowCurLineMinimal then
        bUseColorOfCurrentLine:= IsWrapItemWithCaret(WrapItem)
      else
        bUseColorOfCurrentLine:= true;
    end;

  DoCalcLineEntireColor(
    NLinesIndex,
    bUseColorOfCurrentLine,
    NColorEntire,
    bLineColorForced,
    bHiliteLinesWithSelection);

  if FOptZebraActive then
    if (NLinesIndex+1) mod FOptZebraStep = 0 then
      NColorEntire:= ColorBlend(NColorEntire, FColorFont, FOptZebraAlphaBlend);

  FillOneLine(NColorEntire{, ARectLine.Left});

  //paint line
  if StrOutput<>'' then
  begin
    if (WrapItem.NIndent>0) then
    begin
      NColorAfter:= FColorBG;
      DoCalcPosColor(WrapItem.NCharIndex, NLinesIndex, NColorAfter);
      DoPaintLineIndent(C, ARectLine, ACharSize,
        ARectLine.Top, WrapItem.NIndent,
        NColorAfter,
        AScrollHorz.NPos, FOptShowIndentLines);
    end;

    NColorAfter:= clNone;

    DoCalcLineHilite(
      WrapItem,
      ATempParts{%H-},
      NOutputCharsSkipped, ATEditorOptions.MaxCharsForOutput,
      NColorEntire, bLineColorForced,
      NColorAfter, true);

    if ATempParts[0].Offset<0 then
    begin
      //some bug in making parts! to fix!
      //raise Exception.Create('Program bug in text renderer, report to author!');
      C.Font.Color:= clRed;
      C.TextOut(CurrPointText.X, CurrPointText.Y, 'Program bug in text renderer, report to author!');
      Exit;
    end;

    //apply DimRanges
    if Assigned(FDimRanges) then
    begin
      NDimValue:= FDimRanges.GetDimValue(WrapItem.NLineIndex, -1);
      if NDimValue>0 then //-1: no ranges found, 0: no effect
        DoPartsDim(ATempParts, NDimValue, FColorBG);
    end;

    //adapter may return ColorAfterEol, paint it
    if FOptShowFullHilite then
      if NColorAfter<>clNone then
        FillOneLine(NColorAfter{, CurrPointText.X});

    Event:= FOnDrawLine;

    if ATEditorOptions.UnprintedReplaceSpec then
      SRemoveAsciiControlChars(StrOutput, WideChar(ATEditorOptions.UnprintedReplaceSpecToCode));

    //truncate text to not paint over screen
    NCount:= ARectLine.Width * ATEditorCharXScale div ACharSize.XScaled + 2;
    if Length(StrOutput)>NCount then
      SetLength(StrOutput, NCount);

      TextOutProps.Editor:= Self;
      TextOutProps.HasAsciiNoTabs:= St.LinesHasAsciiNoTabs[NLinesIndex];
      TextOutProps.SuperFast:= bLineHuge;
      TextOutProps.TabHelper:= FTabHelper;
      TextOutProps.LineIndex:= NLinesIndex;
      TextOutProps.CharIndexInLine:= WrapItem.NCharIndex;
      TextOutProps.CharSize:= ACharSize;
      TextOutProps.CharsSkipped:= NOutputCellPercentsSkipped div 100;
      TextOutProps.TrimmedTrailingNonSpaces:= bTrimmedNonSpaces;
      TextOutProps.DrawEvent:= Event;
      TextOutProps.ControlWidth:= ClientWidth+ACharSize.XScaled div ATEditorCharXScale * 2;
      TextOutProps.TextOffsetFromLine:= FTextOffsetFromTop;

      TextOutProps.ShowUnprinted:= FUnprintedVisible and FUnprintedSpaces;
      TextOutProps.ShowUnprintedSpacesTrailing:= FUnprintedSpacesTrailing;
      TextOutProps.ShowUnprintedSpacesBothEnds:= FUnprintedSpacesBothEnds;
      TextOutProps.ShowUnprintedSpacesOnlyInSelection:= FUnprintedSpacesOnlyInSelection and TempSel_IsSelection;
      TextOutProps.ShowUnprintedSpacesAlsoInSelection:= not FUnprintedSpacesOnlyInSelection and FUnprintedSpacesAlsoInSelection and TempSel_IsSelection;
      TextOutProps.DetectIsPosSelected:= @IsPosSelected;

      TextOutProps.ShowFontLigatures:= FOptShowFontLigatures and (not bLineWithCaret);
      TextOutProps.ColorNormalFont:= Colors.TextFont;
      TextOutProps.ColorUnprintedFont:= Colors.UnprintedFont;
      TextOutProps.ColorUnprintedHexFont:= Colors.UnprintedHexFont;

      TextOutProps.FontNormal_Name:= Font.Name;
      TextOutProps.FontNormal_Size:= DoScaleFont(Font.Size);

      TextOutProps.FontItalic_Name:= FontItalic.Name;
      TextOutProps.FontItalic_Size:= DoScaleFont(FontItalic.Size);

      TextOutProps.FontBold_Name:= FontBold.Name;
      TextOutProps.FontBold_Size:= DoScaleFont(FontBold.Size);

      TextOutProps.FontBoldItalic_Name:= FontBoldItalic.Name;
      TextOutProps.FontBoldItalic_Size:= DoScaleFont(FontBoldItalic.Size);

      CanvasTextOut(C,
        CurrPointText.X,
        CurrPointText.Y,
        StrOutput,
        @ATempParts,
        NOutputStrWidth,
        TextOutProps
        );

      //paint selection bg, after applying ColorAfterEol
      DoPaintSelectedLineBG(C, ACharSize, ARectLine,
        CurrPoint,
        CurrPointText,
        WrapItem,
        NOutputStrWidth,
        AScrollHorz);

    //restore after textout
    C.Font.Style:= Font.Style;
  end
  else
  //paint empty line bg
  begin
    if FOptShowFullHilite then
    begin
      NColorAfter:= clNone;
      //visible StrOutput is empty, but the line itself may be not empty (because of horz scroll)
      DoCalcPosColor(NLineLen, NLinesIndex, NColorAfter);
      if NColorAfter<>clNone then
        FillOneLine(NColorAfter{, ARectLine.Left});
    end;

    DoPaintSelectedLineBG(C, ACharSize, ARectLine,
      CurrPoint,
      CurrPointText,
      WrapItem,
      0,
      AScrollHorz);
  end;

  CoordAfterText.X:= CurrPointText.X+NOutputStrWidth;
  CoordAfterText.Y:= CurrPointText.Y;

  if WrapItem.NFinal=cWrapItemFinal then
  begin
    //for OptShowFullWidthForSelection=false paint eol bg
    if bLineEolSelected then
    begin
      C.Brush.Color:= Colors.TextSelBG;
      C.FillRect(
        CoordAfterText.X,
        CoordAfterText.Y,
        CoordAfterText.X+ACharSize.XScaled div ATEditorCharXScale,
        CoordAfterText.Y+ACharSize.Y);
    end;

    //paint eol mark
    if FUnprintedVisible and FUnprintedEnds then
    begin
      if OptUnprintedEndsDetails then
        DoPaintUnprintedSymbols(C,
          cLineEndsToSymbols[St.LinesEnds[WrapItem.NLineIndex]],
          CoordAfterText.X,
          CoordAfterText.Y,
          ACharSize,
          Colors.UnprintedFont,
          Colors.UnprintedBG)
      else
        DoPaintUnprintedEndSymbol(C,
          CoordAfterText.X,
          CoordAfterText.Y,
          ACharSize,
          Colors.UnprintedFont,
          Colors.TextBG);
    end;
  end
  else
  begin
    //paint wrapped-line-part mark
    if FUnprintedVisible and FUnprintedEnds then
      DoPaintUnprintedWrapMark(C,
        CoordAfterText.X,
        CoordAfterText.Y,
        ACharSize,
        Colors.UnprintedFont);
  end;

  //draw collapsed-mark
  if WrapItem.NFinal=cWrapItemCollapsed then
    DoPaintFoldedMark(C,
      St.LinesFoldFrom[NLinesIndex, FEditorIndex]-1,
      NLinesIndex,
      CoordAfterText.X,
      CoordAfterText.Y,
      GetFoldedMarkText(NLinesIndex));

  //draw separators
  if (LineSeparator<>cLineSepNone) then
  begin
    if LineSeparator=cLineSepTop then
      NCoordSep:= ARectLine.Top
    else
      NCoordSep:= ARectLine.Top+ACharSize.Y-1;
    C.Pen.Color:= Colors.BlockSepLine;
    CanvasLineHorz(C, ARectLine.Left, NCoordSep, ARectLine.Right);
  end;
end;

procedure TATSynEdit.DoPaintMinimapLine(
  ARectLine: TRect;
  const ACharSize: TATEditorCharSize;
  var AScrollHorz: TATEditorScrollInfo;
  const AWrapIndex: integer;
  var ATempParts: TATLineParts);
  //
  procedure FillOneLine(AFillColor: TColor; ARectLeft: integer);
  begin
    FMinimapBmp.FillRect(
      ARectLeft - FRectMinimap.Left,
      ARectLine.Top - FRectMinimap.Top,
      FRectMinimap.Width,
      ARectLine.Top - FRectMinimap.Top + ACharSize.Y,
      AFillColor);
  end;
  //
var
  St: TATStrings;
  NLinesIndex, NMaxStringLen: integer;
  NOutputCharsSkipped: integer;
  WrapItem: TATWrapItem;
  NColorEntire, NColorAfter: TColor;
  StrOutput: atString;
  CurrPoint, CurrPointText: TPoint;
  bLineColorForced: boolean;
  bUseSetPixel: boolean;
  bUseColorOfCurrentLine: boolean;
begin
  St:= Strings;
  bUseSetPixel:=
    {$ifndef windows} DoubleBuffered and {$endif}
    (ACharSize.XScaled div ATEditorCharXScale = 1);

  if not FWrapInfo.IsIndexValid(AWrapIndex) then Exit; //e.g. main thread updated WrapInfo
  WrapItem:= FWrapInfo[AWrapIndex];
  NLinesIndex:= WrapItem.NLineIndex;
  if not St.IsIndexValid(NLinesIndex) then Exit;

  //prepare line
  NOutputCharsSkipped:= 0;

  CurrPoint.X:= ARectLine.Left;
  CurrPoint.Y:= ARectLine.Top;
  CurrPointText.X:= Int64(CurrPoint.X)
                    + Int64(WrapItem.NIndent)*ACharSize.XScaled div ATEditorCharXScale
                    - AScrollHorz.SmoothPos
                    + AScrollHorz.NPixelOffset;
  CurrPointText.Y:= CurrPoint.Y;

  //work very fast for minimap, take LineSub from start
  StrOutput:= St.LineSub(
    NLinesIndex,
    1,
    Min(WrapItem.NLength, FVisibleColumns)
    );

  //FMinimapBmp.Canvas.Brush.Color:= FColorBG;

  bUseColorOfCurrentLine:= false;

  DoCalcLineEntireColor(
    NLinesIndex,
    bUseColorOfCurrentLine,
    NColorEntire,
    bLineColorForced,
    FMinimapHiliteLinesWithSelection
    );

  FillOneLine(NColorEntire, ARectLine.Left);

  //paint line
  if StrOutput<>'' then
  begin
    NColorAfter:= clNone;

    DoCalcLineHilite(
      WrapItem,
      ATempParts{%H-},
      NOutputCharsSkipped, ATEditorOptions.MaxCharsForOutput,
      NColorEntire, bLineColorForced,
      NColorAfter, false);

    //adapter may return ColorAfterEol, paint it
    if FOptShowFullHilite then
      if NColorAfter<>clNone then
        FillOneLine(NColorAfter, CurrPointText.X);

    //truncate text to not paint over screen
    NMaxStringLen:= ARectLine.Width div ACharSize.XScaled div ATEditorCharXScale + 2;
    if Length(StrOutput)>NMaxStringLen then
      SetLength(StrOutput, NMaxStringLen);

    if StrOutput<>'' then
      CanvasTextOutMinimap(
        FMinimapBmp,
        ARectLine,
        CurrPointText.X - FRectMinimap.Left,
        CurrPointText.Y - FRectminimap.Top,
        ACharSize,
        FTabSize,
        ATempParts,
        FColorBG,
        NColorAfter,
        St.LineSub(
          WrapItem.NLineIndex,
          WrapItem.NCharIndex,
          FVisibleColumns), //optimize for huge lines
        bUseSetPixel
        );
  end
  else
  //paint empty line bg
  begin
    if FOptShowFullHilite then
    begin
      NColorAfter:= clNone;
      DoCalcPosColor(0, NLinesIndex, NColorAfter);
      if NColorAfter<>clNone then
        FillOneLine(NColorAfter, ARectLine.Left);
    end;

    {
    //TODO???
    DoPaintSelectedLineBG(C, ACharSize, ARectLine,
      CurrPoint,
      CurrPointText,
      WrapItem,
      0,
      AScrollHorz);
    }
  end;
end;

procedure TATSynEdit.DoPaintGutterOfLine(C: TCanvas;
  ARect: TRect;
  const ACharSize: TATEditorCharSize;
  AWrapIndex: integer);
var
  St: TATStrings;
  WrapItem: TATWrapItem;
  LineState: TATLineState;
  GutterItem: TATGutterItem;
  bLineWithCaret: boolean;
  NLinesIndex, NBandDecor: integer;
begin
  St:= Strings;
  WrapItem:= FWrapInfo[AWrapIndex];
  NLinesIndex:= WrapItem.NLineIndex;
  if not St.IsIndexValid(NLinesIndex) then exit;
  bLineWithCaret:= IsLineWithCaret(NLinesIndex);

  Inc(ARect.Top, FTextOffsetFromTop);

  //paint area over scrolled text
  C.Brush.Color:= FColorGutterBG;
  C.FillRect(FRectGutter.Left, ARect.Top, FRectGutter.Right, ARect.Bottom);

  //gutter band: number
  GutterItem:= FGutter[FGutterBandNumbers];
  if GutterItem.Visible then
  begin
    if bLineWithCaret and FOptShowGutterCaretBG then
    begin
      DoPaintGutterBandBG(C,
        Colors.GutterCaretBG,
        GutterItem.Left,
        ARect.Top,
        GutterItem.Right,
        ARect.Bottom,
        false);
      C.Font.Color:= Colors.GutterCaretFont;
    end
    else
      C.Font.Color:= Colors.GutterFont;

    if WrapItem.bInitial then
      DoPaintGutterNumber(C, NLinesIndex, ARect.Top, GutterItem);
  end;

  //gutter decor
  NBandDecor:= FGutterBandDecor;
  if NBandDecor<0 then
    NBandDecor:= FGutterBandBookmarks;

  GutterItem:= FGutter[NBandDecor];
  if GutterItem.Visible then
    if WrapItem.bInitial then
      DoPaintGutterDecor(C, NLinesIndex,
        Rect(
          GutterItem.Left,
          ARect.Top,
          GutterItem.Right,
          ARect.Bottom
          ));

  //gutter band: bookmark
  GutterItem:= FGutter[FGutterBandBookmarks];
  if GutterItem.Visible then
    if WrapItem.bInitial then
    begin
      if St.Bookmarks.Find(NLinesIndex)>=0 then
        DoEventDrawBookmarkIcon(C, NLinesIndex,
          Rect(
            GutterItem.Left,
            ARect.Top,
            GutterItem.Right,
            ARect.Bottom
            ));
    end;

  //gutter band: fold
  GutterItem:= FGutter[FGutterBandFolding];
  if GutterItem.Visible then
  begin
    DoPaintGutterBandBG(C,
      FColorGutterFoldBG,
      GutterItem.Left,
      ARect.Top,
      GutterItem.Right,
      ARect.Bottom,
      false);
    DoPaintGutterFolding(C,
      AWrapIndex,
      GutterItem.Left,
      GutterItem.Right,
      ARect.Top,
      ARect.Bottom
      );
  end;

  //gutter band: state
  GutterItem:= FGutter[FGutterBandStates];
  if GutterItem.Visible then
  begin
    LineState:= St.LinesState[NLinesIndex];
    if LineState<>cLineStateNone then
      DoPaintGutterBandBG(C,
        FColorOfStates[LineState],
        GutterItem.Left,
        ARect.Top,
        GutterItem.Right,
        ARect.Bottom,
        false);
  end;

  //gutter band: separator
  GutterItem:= FGutter[FGutterBandSeparator];
  if GutterItem.Visible then
    DoPaintGutterBandBG(C,
      Colors.GutterSeparatorBG,
      GutterItem.Left,
      ARect.Top,
      GutterItem.Right,
      ARect.Bottom,
      false);

  //gutter band: empty indent
  GutterItem:= FGutter[FGutterBandEmpty];
  if GutterItem.Visible then
    DoPaintGutterBandBG(C,
      FColorBG,
      GutterItem.Left,
      ARect.Top,
      GutterItem.Right,
      ARect.Bottom,
      false);
end;


function TATSynEdit.GetMinimapSelTop: integer;
begin
  Result:= FRectMinimap.Top + (Max(0, FScrollVert.NPos)-FScrollVertMinimap.NPos)*FCharSizeMinimap.Y;
end;

function TATSynEdit.GetMinimapActualHeight: integer;
begin
  Result:=
    Max(2, Min(
      FRectMinimap.Height,
      FWrapInfo.Count*FCharSizeMinimap.Y
      ));
end;

function TATSynEdit.GetMinimap_DraggedPosToWrapIndex(APosY: integer): integer;
var
  NCount, NScrollPos, NScrollMax, NScrollMax2: integer;
begin
  NCount:= FWrapInfo.Count;
  NScrollPos:= Max(0, APosY-FMouseDragMinimapDelta);

  //for big files
  NScrollMax:= Max(0, FRectMinimap.Height-FMouseDragMinimapSelHeight);

  //for small files: minimap drag must not be until bottom
  NScrollMax2:= NCount*FCharSizeMinimap.Y;
  if not FOptLastLineOnTop then
    NScrollMax2:= Max(0, NScrollMax2-FMouseDragMinimapSelHeight);

  if NScrollMax>NScrollMax2 then
    NScrollMax:= NScrollMax2;

  if NScrollMax>0 then
  begin
    Result:= Int64(FScrollVert.NPosLast) * NScrollPos div NScrollMax;
    Result:= Min(NCount-1, Result);
  end
  else
    Result:= 0;
end;

function TATSynEdit.GetMinimap_ClickedPosToWrapIndex(APosY: integer): integer;
begin
  Result:= (APosY-FRectMinimap.Top) div FCharSizeMinimap.Y + FScrollVertMinimap.NPos;
  if not FWrapInfo.IsIndexValid(Result) then
    Result:= -1;
end;

function TATSynEdit.GetOptTextOffsetTop: integer;
begin
  if ModeOneLine then
    Result:= (ClientHeight - TextCharSize.Y) div 2
  else
    Result:= FOptTextOffsetTop;
end;

function _IsColorDark(N: TColor): boolean;
const
  cMax = $60;
begin
  Result:= (Red(N)<cMax) and (Green(N)<cMax) and (Blue(N)<cMax);
end;

procedure TATSynEdit.DoPaintMinimapSelToBGRABitmap;
var
  C: TBGRABitmap;
  R: TRect;
  rColor: TBGRAPixel;
begin
  C:= FMinimapBmp;
  if FMinimapShowSelAlways or FCursorOnMinimap then
  begin
    GetRectMinimapSel(R);
    OffsetRect(R, -FRectMinimap.Left, -FRectMinimap.Top);

    // https://forum.lazarus.freepascal.org/index.php/topic,51383.msg377195.html#msg377195
    if _IsColorDark(FColorBG) then
      rColor.FromRGB(255, 255, 255, FMinimapSelColorChange*255 div 100)
    else
      rColor.FromRGB(0, 0, 0, FMinimapSelColorChange*255 div 100);

    C.FillRect(R, rColor, dmDrawWithTransparency);

    if FMinimapShowSelBorder then
    begin
      rColor.FromColor(Colors.MinimapBorder);
      C.Rectangle(R, rColor);
    end;
  end;

  if Colors.MinimapBorder<>clNone then
  begin
    rColor.FromColor(Colors.MinimapBorder);
    C.DrawVertLine(0, 0, FRectMinimap.Height, rColor);
  end;
end;

procedure TATSynEdit.DoPaintMinimapAllToBGRABitmap;
begin
  //avoid too often minimap repainting
  if not FAdapterIsDataReady then exit;

  if ATEditorOptions.DebugTiming then
    FTickMinimap:= GetTickCount64;

  FScrollHorzMinimap.Clear;
  FScrollVertMinimap.Clear;

  FScrollVertMinimap.NPos:= GetMinimapScrollPos;
  FScrollVertMinimap.NPosLast:= MaxInt div 2;

  DoPaintMinimapTextToBGRABitmap(FRectMinimap, FCharSizeMinimap, FScrollHorzMinimap, FScrollVertMinimap);
  DoPaintMinimapSelToBGRABitmap;

  if ATEditorOptions.DebugTiming then
    FTickMinimap:= GetTickCount64-FTickMinimap;
end;

procedure TATSynEdit.DoPaintMicromap(C: TCanvas);
begin
  if Assigned(FOnDrawMicromap) then
    FOnDrawMicromap(Self, C, FRectMicromap)
  else
  begin
    C.Brush.Color:= clCream;
    C.Brush.Style:= bsSolid;
    C.FillRect(FRectMicromap);
  end;
end;


procedure TATSynEdit.DoPaintGap(C: TCanvas; const ARect: TRect; AGap: TATGapItem);
var
  RHere, RBmp: TRect;
  NColor: TColor;
begin
  NColor:= AGap.Color;
  if NColor<>clNone then
  begin
    C.Brush.Color:= NColor;
    C.FillRect(ARect);
  end;

  if Assigned(AGap.Bitmap) then
  begin
    RBmp:= Rect(0, 0, AGap.Bitmap.Width, AGap.Bitmap.Height);
    //RHere is rect of bitmap's size, located at center of ARect
    RHere.Left:= GetGapBitmapPosLeft(ARect, AGap.Bitmap.Width);
    RHere.Top:= (ARect.Top+ARect.Bottom-RBmp.Bottom) div 2;
    RHere.Right:= RHere.Left + RBmp.Right;
    RHere.Bottom:= RHere.Top + RBmp.Bottom;
    C.CopyRect(RHere, AGap.Bitmap.Canvas, RBmp);
  end
  else
  if Assigned(AGap.Form) then
  begin
    AGap.Form.BorderStyle:= bsNone;
    AGap.Form.Parent:= Self;

    //RHere is rect of form, it is stretched by width to RectMain
    RHere.Left:= RectMain.Left;
    RHere.Right:= RectMain.Right;
    RHere.Top:= ARect.Top;
    RHere.Bottom:= RHere.Top + AGap.Size;

    AGap.Form.BoundsRect:= RHere;
    AGap.FormVisible:= true;
  end
  else
  if Assigned(FOnDrawGap) then
    FOnDrawGap(Self, C, ARect, AGap);
end;

procedure TATSynEdit.DoPaintMarginLineTo(C: TCanvas; AX, AWidth: integer; AColor: TColor);
begin
  if (AX>=FRectMain.Left) and (AX<FRectMain.Right) then
  begin
    C.Pen.Color:= AColor;
    CanvasLineVert2(C, AX, FRectMain.Top, FRectMain.Bottom, false, AWidth);
  end;
end;

procedure TATSynEdit.DoPaintMargins(C: TCanvas);
  //
  function PosX(NMargin: integer): integer; inline;
  begin
    Result:= FRectMain.Left + FCharSize.XScaled *(NMargin-FScrollHorz.NPos) div ATEditorCharXScale;
  end;
var
  NWidth, i: integer;
begin
  NWidth:= ATEditorScale(1);
  if FMarginRight>1 then
    DoPaintMarginLineTo(C, PosX(FMarginRight), NWidth, Colors.MarginRight);
  for i:= 0 to Length(FMarginList)-1 do
    DoPaintMarginLineTo(C, PosX(FMarginList[i]), NWidth, Colors.MarginUser);
end;


procedure TATSynEdit.DoPaintFoldedMark(C: TCanvas;
  APosX, APosY, ACoordX, ACoordY: integer;
  const AMarkText: string);
var
  NWidth: integer;
  Str: string;
  RectMark: TRect;
  FoldMark: TATFoldedMark;
begin
  Str:= AMarkText;

  SDeleteFrom(Str, #10);
    //e.g. Diff lexer gives collapsed-string with EOL (several lines)

  Str:= FTabHelper.TabsToSpaces(APosY, UTF8Decode(Str));
    //expand tabs too

  if APosX>0 then
    Inc(ACoordX, ATEditorOptions.FoldedMarkIndentOuter);

  //set colors:
  //if 1st chars selected, then use selection-color
  if IsPosSelected(APosX, APosY) and FOptShowFoldedMarkWithSelectionBG then
  begin
    if Colors.TextSelFont<>clNone then
      C.Font.Color:= Colors.TextSelFont
    else
      C.Font.Color:= Colors.TextFont;
    C.Brush.Color:= Colors.TextSelBG;
  end
  else
  begin
    C.Font.Color:= Colors.CollapseMarkFont;
    C.Brush.Color:= FColorCollapseMarkBG;
  end;

  //paint text
  if not FOptShowFoldedMarkWithSelectionBG then
    C.Brush.Style:= bsClear;

  C.TextOut(
    ACoordX+ATEditorOptions.FoldedMarkIndentInner,
    ACoordY+FTextOffsetFromTop,
    Str);
  NWidth:= C.TextWidth(Str) + 2*ATEditorOptions.FoldedMarkIndentInner;

  //paint frame
  RectMark:= Rect(ACoordX, ACoordY, ACoordX+NWidth, ACoordY+FCharSize.Y);
  C.Pen.Color:= Colors.CollapseMarkBorder;
  C.Brush.Style:= bsClear;
  C.Rectangle(RectMark);
  C.Brush.Style:= bsSolid;

  if FFoldTooltipVisible then
  begin
    FoldMark.Init(
      RectMark,
      APosY,
      APosY + DoGetFoldedMarkLinesCount(APosY) -1
      );

    InitFoldedMarkList;
    FFoldedMarkList.Add(FoldMark);
  end;
end;

function TATSynEdit.GetMarginString: string;
var
  i: integer;
begin
  Result:= '';
  for i:= 0 to Length(FMarginList)-1 do
    Result+= IntToStr(FMarginList[i]) + ' ';
  Result:= Trim(Result);
end;

function TATSynEdit.GetReadOnly: boolean;
begin
  Result:= Strings.ReadOnly;
end;

function TATSynEdit.GetLineTop: integer;
var
  N: integer;
begin
  if FLineTopTodo>0 then
    exit(FLineTopTodo);
  Result:= 0;
  if Assigned(FWrapInfo) and (FWrapInfo.Count>0) then
  begin
    N:= Max(0, FScrollVert.NPos);
    if FWrapInfo.IsIndexValid(N) then
      Result:= FWrapInfo[N].NLineIndex;
  end;
end;

function TATSynEdit.GetColumnLeft: integer;
begin
  Result:= FScrollHorz.NPos;
end;

constructor TATSynEdit.Create(AOwner: TComponent);
var
  i: integer;
begin
  inherited;

  //GlobalCharSizer should be created after MainForm is inited
  if not Assigned(GlobalCharSizer) then
    GlobalCharSizer:= TATCharSizer.Create(AOwner);

  Caption:= '';
  ControlStyle:= ControlStyle+[csOpaque, csDoubleClicks, csTripleClicks];
  DoubleBuffered:= EditorDoubleBufferedNeeded;
  BorderStyle:= bsNone;
  TabStop:= true;

  Width:= 300;
  Height:= 250;
  Font.Name:= 'Courier New';
  Font.Size:= 9;

  FFontItalic:= TFont.Create;
  FFontItalic.Name:= '';
  FFontBold:= TFont.Create;
  FFontBold.Name:= '';
  FFontBoldItalic:= TFont.Create;
  FFontBoldItalic.Name:= '';

  FScrollbarVert:= TATScrollbar.Create(Self);
  FScrollbarVert.Hide;
  FScrollbarVert.Parent:= Self;
  FScrollbarVert.Align:= alRight;
  FScrollbarVert.Kind:= sbVertical;
  FScrollbarVert.Cursor:= crArrow;
  FScrollbarVert.Width:= ATScrollbarTheme.InitialSize;
  FScrollbarVert.Update;
  FScrollbarVert.OnChange:= @OnNewScrollbarVertChanged;

  FScrollbarHorz:= TATScrollbar.Create(Self);
  FScrollbarHorz.Hide;
  FScrollbarHorz.Parent:= Self;
  FScrollbarHorz.Align:= alBottom;
  FScrollbarHorz.Kind:= sbHorizontal;
  FScrollbarHorz.Cursor:= crArrow;
  FScrollbarHorz.Height:= ATScrollbarTheme.InitialSize;
  FScrollbarHorz.IndentCorner:= 100;
  FScrollbarHorz.Update;
  FScrollbarHorz.OnChange:= @OnNewScrollbarHorzChanged;

  FCaretShapeNormal:= TATCaretShape.Create;
  FCaretShapeOverwrite:= TATCaretShape.Create;
  FCaretShapeReadonly:= TATCaretShape.Create;

  FCaretShapeNormal.Width:= 2;
  FCaretShapeNormal.Height:= -100;
  FCaretShapeOverwrite.Width:= -100;
  FCaretShapeOverwrite.Height:= -100;
  FCaretShapeReadonly.Width:= -100;
  FCaretShapeReadonly.Height:= 2;

  FWantTabs:= true;
  FWantReturns:= true;
  FCharSize.XScaled:= 4 * ATEditorCharXScale;
  FCharSize.Y:= 4;
  FEditorIndex:= 0;

  //FWheelQueue:= TATEditorWheelQueue.Create;

  FCommandLog:= TATEditorCommandLog.Create;

  FCarets:= TATCarets.Create;
  FCarets.Add(0, 0);

  FCaretShowEnabled:= false; //code sets it On in DoEnter
  FCaretShown:= false;
  FCaretBlinkEnabled:= true;
  FCaretVirtual:= true;
  FCaretSpecPos:= false;
  FCaretStopUnfocused:= true;
  FCaretHideUnfocused:= true;

  FTabHelper:= TATStringTabHelper.Create;
  FMarkers:= nil;
  FAttribs:= nil;
  FMarkedRange:= nil;
  FDimRanges:= nil;
  FHotspots:= nil;
  FLinkCache:= TATLinkCache.Create;

  FMinimapBmp:= TBGRABitmap.Create;

  {$ifdef windows}
  FAdapterIME:= TATAdapterIMEStandard.Create;
  {$endif}

  FPaintLocked:= 0;
  FPaintFlags:= [cIntFlagBitmap];

  FColors:= TATEditorColors.Create;
  InitDefaultColors(FColors);
  InitEditorMouseActions(FMouseActions, false);

  FCursorText:= crIBeam;
  FCursorColumnSel:= crCross;
  FCursorGutterBookmark:= crHandPoint;
  FCursorGutterNumbers:= crDefault;
  FCursorMinimap:= crDefault;
  FCursorMicromap:= crDefault;

  FTimerDelayedParsing:= TTimer.Create(Self);
  FTimerDelayedParsing.Enabled:= false;
  FTimerDelayedParsing.Interval:= 300;
  FTimerDelayedParsing.OnTimer:= @TimerDelayedParsingTick;

  FTimerIdle:= TTimer.Create(Self);
  FTimerIdle.Enabled:= false;
  FTimerIdle.OnTimer:=@TimerIdleTick;

  FTimerBlink:= TTimer.Create(Self);
  FTimerBlink.Enabled:= false;
  SetCaretBlinkTime(cInitCaretBlinkTime);
  FTimerBlink.OnTimer:= @TimerBlinkTick;

  FTimerFlicker:= TTimer.Create(Self);
  FTimerFlicker.Enabled:= false;
  FTimerFlicker.OnTimer:= @TimerFlickerTick;

  FBitmap:= Graphics.TBitmap.Create;
  FBitmap.PixelFormat:= pf24bit;
  FBitmap.SetSize(cInitBitmapWidth, cInitBitmapHeight);

  FOptUndoLimit:= cInitUndoLimit;
  FOptUndoIndentVert:= cInitUndoIndentVert;
  FOptUndoIndentHorz:= cInitUndoIndentHorz;
  FOptUndoMaxCarets:= cInitUndoMaxCarets;
  FOptUndoGrouped:= true;
  FOptUndoPause:= cInitUndoPause;
  FOptUndoPause2:= cInitUndoPause2;
  FOptUndoPauseHighlightLine:= cInitUndoPauseHighlightLine;
  FOptUndoForCaretJump:= cInitUndoForCaretJump;

  FStringsExternal:= nil;
  FStringsInt:= TATStrings.Create(FOptUndoLimit);
  FStringsInt.OnGetCaretsArray:= @GetCaretsArray;
  FStringsInt.OnGetMarkersArray:= @GetMarkersArray;
  FStringsInt.OnSetCaretsArray:= @SetCaretsArray;
  FStringsInt.OnSetMarkersArray:= @SetMarkersArray;
  FStringsInt.OnProgress:= @DoStringsOnProgress;
  FStringsInt.OnChangeEx:= @DoStringsOnChangeEx;
  FStringsInt.OnChangeLog:= @DoStringsOnChangeLog;
  FStringsInt.OnUndoBefore:= @DoStringsOnUndoBefore;
  FStringsInt.OnUndoAfter:= @DoStringsOnUndoAfter;

  FFold:= TATSynRanges.Create;
  FFoldStyle:= cInitFoldStyle;
  FFoldEnabled:= true;
  FFoldCacheEnabled:= true;
  FFoldUnderlineOffset:= cInitFoldUnderlineOffset;
  FFoldTooltipVisible:= cInitFoldTooltipVisible;
  FFoldTooltipWidthPercents:= cInitFoldTooltipWidthPercents;
  FFoldTooltipLineCount:= cInitFoldTooltipLineCount;

  FWrapInfo:= TATWrapInfo.Create;
  FWrapInfo.StringsObj:= FStringsInt;
  FWrapInfo.WrapColumn:= cInitMarginRight;

  FWrapTemps:= TATWrapItems.Create;
  FWrapUpdateNeeded:= true;
  FWrapMode:= cInitWrapMode;
  FWrapIndented:= true;
  FWrapAddSpace:= 1;
  FWrapEnabledForMaxLines:= cInitWrapEnabledForMaxLines;

  FMicromap:= TATMicromap.Create;
  FMicromapVisible:= cInitMicromapVisible;
  FMicromapOnScrollbar:= cInitMicromapOnScrollbar;
  FMicromapLineStates:= true;
  FMicromapSelections:= true;
  FMicromapBookmarks:= cInitMicromapBookmarks;
  FMicromapScaleDiv:= 1;
  FMicromapShowForMinCount:= cInitMicromapShowForMinCount;

  FOverwrite:= false;
  FTabSize:= cInitTabSize;
  FMarginRight:= cInitMarginRight;
  FMarginList:= nil;
  FFoldedMarkList:= nil;

  FOptInputNumberOnly:= false;
  FOptInputNumberAllowNegative:= cInitInputNumberAllowNegative;
  FOptMaskChar:= cInitMaskChar;
  FOptMaskCharUsed:= false;
  FOptScrollAnimationSteps:= cInitScrollAnimationSteps;
  FOptScrollAnimationSleep:= cInitScrollAnimationSleep;
  FOptIdleInterval:= cInitIdleInterval;

  FHighlightGitConflicts:= cInitHighlightGitConflicts;
  FOptAutoPairForMultiCarets:= cInitAutoPairForMultiCarets;
  FOptAutoPairChars:= '([{';
  FOptAutocompleteAutoshowCharCount:= 0;
  FOptAutocompleteTriggerChars:= '';
  FOptAutocompleteCommitChars:= ' ,;/\''"';
  FOptAutocompleteCloseChars:= '<>()[]{}=';
  FOptAutocompleteAddOpeningBracket:= true;
  FOptAutocompleteUpDownAtEdge:= 1; //cudWrap

  FShowOsBarVert:= false;
  FShowOsBarHorz:= false;

  FUnprintedVisible:= true;
  FUnprintedSpaces:= true;
  FUnprintedSpacesTrailing:= false;
  FUnprintedSpacesBothEnds:= false;
  FUnprintedSpacesOnlyInSelection:= false;
  FUnprintedEnds:= true;
  FUnprintedEndsDetails:= true;
  FUnprintedEof:= true;

  FTextHint:= '';
  FTextHintFontStyle:= [fsItalic];
  FTextHintCenter:= false;

  FGutter:= TATGutter.Create;
  FGutterDecor:= nil;

  FOptGutterVisible:= true;
  FOptGutterPlusSize:= cInitGutterPlusSize;
  FOptGutterShowFoldAlways:= true;
  FOptGutterShowFoldLines:= true;
  FOptGutterShowFoldLinesAll:= false;
  FOptGutterShowFoldLinesForCaret:= true;
  FOptGutterIcons:= cGutterIconsPlusMinus;

  FGutterDecorAlignment:= taCenter;
  FGutterBandBookmarks:= 0;
  FGutterBandNumbers:= 1;
  FGutterBandStates:= 2;
  FGutterBandFolding:= 3;
  FGutterBandSeparator:= 4;
  FGutterBandEmpty:= 5;
  FGutterBandDecor:= -1;

  for i:= 1 to ATEditorOptions.GutterBandsCount do
    FGutter.Add(10);
  FGutter[FGutterBandBookmarks].Size:= ATEditorOptions.GutterSizeBookmarks;
  FGutter[FGutterBandBookmarks].Scaled:= true;
  FGutter[FGutterBandNumbers].Size:= ATEditorOptions.GutterSizeNumbers;
  FGutter[FGutterBandStates].Size:= ATEditorOptions.GutterSizeLineStates;
  FGutter[FGutterBandStates].Scaled:= true;
  FGutter[FGutterBandFolding].Size:= ATEditorOptions.GutterSizeFolding;
  FGutter[FGutterBandFolding].Scaled:= true;
  FGutter[FGutterBandSeparator].Size:= ATEditorOptions.GutterSizeSepar;
  FGutter[FGutterBandEmpty].Size:= ATEditorOptions.GutterSizeEmpty;
  FGutter[FGutterBandSeparator].Visible:= false;
  FGutter.Update;

  FOptNumbersAutosize:= true;
  FOptNumbersAlignment:= taRightJustify;
  FOptNumbersStyle:= cInitNumbersStyle;
  FOptNumbersShowFirst:= true;
  FOptNumbersShowCarets:= false;
  FOptNumbersIndentPercents:= cInitNumbersIndentPercents;

  FOptBorderVisible:= cInitBorderVisible;
  FOptBorderWidth:= cInitBorderWidth;
  FOptBorderWidthFocused:= cInitBorderWidthFocused;
  FOptBorderWidthMacro:= cInitBorderWidthMacro;
  FOptBorderFocusedActive:= false;
  FOptBorderMacroRecording:= true;

  FOptRulerVisible:= true;
  FOptRulerNumeration:= cInitRulerNumeration;
  FOptRulerHeightPercents:= cInitRulerHeightPercents;
  FOptRulerMarkSizeCaret:= cInitRulerMarkCaret;
  FOptRulerMarkSizeSmall:= cInitRulerMarkSmall;
  FOptRulerMarkSizeBig:= cInitRulerMarkBig;
  FOptRulerMarkForAllCarets:= false;
  FOptRulerFontSizePercents:= cInitRulerFontSizePercents;
  FOptRulerTopIndentPercents:= 0;

  FMinimapWidth:= 150;
  FMinimapCharWidth:= 0;
  FMinimapCustomScale:= 0;
  FMinimapVisible:= cInitMinimapVisible;
  FMinimapShowSelBorder:= false;
  FMinimapShowSelAlways:= true;
  FMinimapSelColorChange:= cInitMinimapSelColorChange;
  FMinimapAtLeft:= false;
  FMinimapTooltipVisible:= cInitMinimapTooltipVisible;
  FMinimapTooltipLinesCount:= cInitMinimapTooltipLinesCount;
  FMinimapTooltipWidthPercents:= cInitMinimapTooltipWidthPercents;
  FMinimapHiliteLinesWithSelection:= true;

  FSpacingY:= cInitSpacingY;
  FCharSizeMinimap.XScaled:= 1 * ATEditorCharXScale;
  FCharSizeMinimap.Y:= 2;

  FOptScrollStyleHorz:= aessAuto;
  FOptScrollStyleVert:= aessShow;
  FOptScrollSmooth:= true;
  FOptScrollIndentCaretHorz:= 10;
  FOptScrollIndentCaretVert:= 0;

  FOptScrollbarsNew:= false;
  FOptScrollbarHorizontalAddSpace:= cInitScrollbarHorzAddSpace;
  FOptScrollLineCommandsKeepCaretOnScreen:= true;

  FOptShowFontLigatures:= true;
  FOptShowURLs:= true;
  FOptShowURLsRegex:= cUrlRegexInitial;
  FOptShowDragDropMarker:= true;
  FOptShowDragDropMarkerWidth:= cInitDragDropMarkerWidth;
  FOptShowFoldedMarkWithSelectionBG:= cInitShowFoldedMarkWithSelectionBG;

  FOptMaxLineLenToTokenize:= cInitMaxLineLenToTokenize;
  FOptMinLineLenToCalcURL:= cInitMinLineLenToCalcURL;
  FOptMaxLineLenToCalcURL:= cInitMaxLineLenToCalcURL;
  FOptMaxLinesToCountUnindent:= 100;

  FOptStapleStyle:= cLineStyleSolid;
  FOptStapleIndent:= -1;
  FOptStapleWidthPercent:= 100;
  FOptStapleHiliteActive:= true;
  FOptStapleHiliteActiveAlpha:= cInitStapleHiliteAlpha;
  FOptStapleEdge1:= cStapleEdgeAngle;
  FOptStapleEdge2:= cStapleEdgeAngle;
  FOptStapleIndentConsidersEnd:= false;

  FOptTextCenteringCharWidth:= 0;
  FOptTextOffsetLeft:= cInitTextOffsetLeft;
  FOptTextOffsetTop:= cInitTextOffsetTop;
  FOptAllowRepaintOnTextChange:= true;
  FOptAllowReadOnly:= true;

  FOptKeyBackspaceUnindent:= true;
  FOptKeyBackspaceGoesToPrevLine:= true;
  FOptKeyPageKeepsRelativePos:= true;
  FOptKeyUpDownNavigateWrapped:= true;
  FOptKeyUpDownAllowToEdge:= false;
  FOptKeyHomeEndNavigateWrapped:= true;
  FOptKeyUpDownKeepColumn:= true;

  FOptOverwriteAllowedOnPaste:= false;
  FOptNonWordChars:= ATEditorOptions.DefaultNonWordChars;
  FOptAutoIndent:= true;
  FOptAutoIndentKind:= cIndentAsPrevLine;
  FOptAutoIndentBetterBracketsCurly:= true;
  FOptAutoIndentBetterBracketsRound:= false;
  FOptAutoIndentBetterBracketsSquare:= false;
  FOptAutoIndentRegexRule:= '';
  FOptTabSpaces:= false;

  FOptLastLineOnTop:= false;
  FOptOverwriteSel:= true;
  FOptMouseDragDrop:= true;
  FOptMouseDragDropCopying:= true;
  FOptMouseDragDropCopyingWithState:= ssModifier;
  FOptMouseMiddleClickAction:= mcaScrolling;
  FOptMouseHideCursor:= false;

  FOptMouseClickOpensURL:= false;
  FOptMouseClickNumberSelectsLine:= true;
  FOptMouseClickNumberSelectsLineWithEOL:= true;
  FOptMouse2ClickAction:= cMouseDblClickSelectAnyChars;
  FOptMouse2ClickOpensURL:= true;
  FOptMouse2ClickDragSelectsWords:= true;
  FOptMouse3ClickSelectsLine:= true;

  FOptMouseRightClickMovesCaret:= false;
  FOptMouseWheelScrollVert:= true;
  FOptMouseWheelScrollVertSpeed:= 3;
  FOptMouseWheelScrollHorz:= true;
  FOptMouseWheelScrollHorzSpeed:= 10;
  FOptMouseWheelScrollHorzWithState:= ssShift;
  FOptMouseWheelZooms:= true;
  FOptMouseWheelZoomsWithState:= ssModifier;

  FOptCopyLinesIfNoSel:= true;
  FOptCutLinesIfNoSel:= false;
  FOptCopyColumnBlockAlignedBySpaces:= true;
  FOptShowFullSel:= false;
  FOptShowFullHilite:= true;
  FOptShowCurLine:= false;
  FOptShowCurLineMinimal:= true;
  FOptShowCurLineOnlyFocused:= false;
  FOptShowCurLineIfWithoutSel:= true;
  FOptShowCurColumn:= false;
  FOptShowMouseSelFrame:= cInitShowMouseSelFrame;

  FOptKeyPageUpDownSize:= cPageSizeFullMinus1;
  FOptKeyLeftRightGoToNextLineWithCarets:= true;
  FOptKeyLeftRightSwapSel:= true;
  FOptKeyLeftRightSwapSelAndSelect:= false;
  FOptKeyHomeToNonSpace:= true;
  FOptKeyEndToNonSpace:= true;
  FOptKeyTabIndents:= true;
  FOptKeyTabIndentsVerticalBlock:= false;

  FOptShowIndentLines:= true;
  FOptShowGutterCaretBG:= true;
  FOptIndentSize:= 2;
  FOptIndentKeepsAlign:= true;
  FOptIndentMakesWholeLinesSelection:= false;
  FOptSavingForceFinalEol:= false;
  FOptSavingTrimSpaces:= false;
  FOptShowScrollHint:= false;
  FOptCaretPreferLeftSide:= true;
  FOptCaretPosAfterPasteColumn:= cPasteCaretColumnRight;
  FOptCaretsAddedToColumnSelection:= true;
  FOptCaretFixAfterRangeFolded:= true;
  FOptCaretsPrimitiveColumnSelection:= cInitCaretsPrimitiveColumnSelection;
  FOptCaretsMultiToColumnSel:= cInitCaretsMultiToColumnSel;
  FOptCaretProximityVert:= 0;
  FOptMarkersSize:= cInitMarkerSize;
  FOptMouseEnableAll:= true;
  FOptMouseEnableNormalSelection:= true;
  FOptMouseEnableColumnSelection:= true;
  FOptPasteAtEndMakesFinalEmptyLine:= true;
  FOptPasteMultilineTextSpreadsToCarets:= true;
  FOptPasteWithEolAtLineStart:= true;
  FOptZebraActive:= false;
  FOptZebraStep:= 2;
  FOptZebraAlphaBlend:= cInitZebraAlphaBlend;
  FOptDimUnfocusedBack:= cInitDimUnfocusedBack;

  ClearMouseDownVariables;
  FMouseNiceScrollPos:= Point(0, 0);

  FSelRect:= cRectEmpty;
  ClearSelRectPoints;
  FCursorOnMinimap:= false;
  FCursorOnGutter:= false;
  FLastTextCmd:= 0;
  FLastTextCmdText:= '';
  FLastCommandChangedText:= false;
  FLastCommandDelayedParsingOnLine:= MaxInt;
  FLastHotspot:= -1;

  FScrollVert.Clear;
  FScrollHorz.Clear;
  FScrollVert.Vertical:= true;
  FScrollHorz.Vertical:= false;
  FScrollVertMinimap.Vertical:= true;
  FScrollHorzMinimap.Vertical:= false;

  FKeymap:= KeymapFull;
  FHintWnd:= nil;

  FMenuStd:= nil;
  FMenuText:= nil;
  FMenuGutterBm:= nil;
  FMenuGutterNum:= nil;
  FMenuGutterFold:= nil;
  FMenuGutterFoldStd:= nil;
  FMenuMinimap:= nil;
  FMenuMicromap:= nil;
  FMenuRuler:= nil;

  //must call UpdateTabHelper also before first Paint
  UpdateTabHelper;
  //must call before first paint
  UpdateLinksRegexObject;

  //allow Invalidate to work now
  IsRepaintEnabled:= true;
end;

destructor TATSynEdit.Destroy;
begin
  if Assigned(FMinimapThread) then
  begin
    FMinimapThread.Terminate;
    FEventMapStart.SetEvent;
    if not FMinimapThread.Finished then
      FMinimapThread.WaitFor;
    FreeAndNil(FMinimapThread);
  end;
  if Assigned(FEventMapStart) then
    FreeAndNil(FEventMapStart);
  if Assigned(FEventMapDone) then
    FreeAndNil(FEventMapDone);
  FAdapterHilite:= nil;
  if Assigned(FMinimapTooltipBitmap) then
    FreeAndNil(FMinimapTooltipBitmap);
  if Assigned(FRegexLinks) then
    FreeAndNil(FRegexLinks);
  if Assigned(FAdapterIME) then
    FreeAndNil(FAdapterIME);
  TimersStop;
  if Assigned(FHintWnd) then
    FreeAndNil(FHintWnd);
  if Assigned(FMenuStd) then
    FreeAndNil(FMenuStd);
  TimerBlinkDisable;
  if Assigned(FFoldedMarkList) then
  begin
    FFoldedMarkList.Clear;
    FreeAndNil(FFoldedMarkList);
  end;
  FreeAndNil(FMinimapBmp);
  FreeAndNil(FMicromap);
  FreeAndNil(FFold);
  FreeAndNil(FTimerFlicker);
  FreeAndNil(FTimerDelayedParsing);
  if Assigned(FTimerNiceScroll) then
    FreeAndNil(FTimerNiceScroll);
  if Assigned(FTimerScroll) then
    FreeAndNil(FTimerScroll);
  FreeAndNil(FTimerBlink);
  FreeAndNil(FCarets);
  FreeAndNil(FCommandLog);
  if Assigned(FHotspots) then
    FreeAndNil(FHotspots);
  if Assigned(FDimRanges) then
    FreeAndNil(FDimRanges);
  if Assigned(FMarkedRange) then
    FreeAndNil(FMarkedRange);
  if Assigned(FMarkers) then
    FreeAndNil(FMarkers);
  FreeAndNil(FTabHelper);
  if Assigned(FAttribs) then
    FreeAndNil(FAttribs);
  FreeAndNil(FGutter);
  FreeAndNil(FWrapTemps);
  FreeAndNil(FWrapInfo);
  FreeAndNil(FStringsInt);
  if Assigned(FGutterDecor) then
    FreeAndNil(FGutterDecor);
  FreeAndNil(FBitmap);
  FreeAndNil(FColors);
  FreeAndNil(FLinkCache);
  FreeAndNil(FFontItalic);
  FreeAndNil(FFontBold);
  FreeAndNil(FFontBoldItalic);
  FreeAndNil(FCaretShapeNormal);
  FreeAndNil(FCaretShapeOverwrite);
  FreeAndNil(FCaretShapeReadonly);
  //FreeAndNil(FWheelQueue);
  inherited;
end;

procedure TATSynEdit.Update(AUpdateWrapInfo: boolean=false);
begin
  if not IsRepaintEnabled then exit;

  UpdateCursor;

  if AUpdateWrapInfo then
    FWrapUpdateNeeded:= true;

  Invalidate;
end;

procedure TATSynEdit.SetFocus;
begin
  if HandleAllocated then
    LCLIntf.SetFocus(Handle);
end;

procedure TATSynEdit.GetClientSizes(out W, H: integer);
begin
  W:= Width;
  H:= Height;
  if ModeOneLine then exit;

  if FOptScrollbarsNew then //better check this instead of FScrollbarVert.Visible
  begin
    Dec(W, FScrollbarVert.Width);
  end
  else
  begin
    W:= inherited ClientWidth;
  end;

  if FScrollbarHorz.Visible then
    Dec(H, FScrollbarHorz.Height);

  if W<1 then W:= 1;
  if H<1 then H:= 1;
end;

procedure TATSynEdit.LoadFromFile(const AFilename: string; AKeepScroll: boolean=false);
begin
  TimerBlinkDisable;

  FCarets.Clear;
  FCarets.Add(0, 0);

  Strings.Clear(false{AWithEvent});
  FWrapInfo.Clear;
  FWrapUpdateNeeded:= true;

  if not AKeepScroll then
  begin
    FScrollHorz.Clear;
    FScrollVert.Clear;
  end;

  BeginUpdate;
  try
    FFileName:= '';
    Strings.LoadFromFile(AFilename);
    FFileName:= AFileName;
  finally
    EndUpdate;
  end;

  Update;
  TimerBlinkEnable;

  DoEventChange(0, false{AllowOnChange}); //calling OnChange makes almost no sense on opening file

  //DoEventCarets; //calling OnChangeCaretPos makes little sense on opening file
end;

procedure TATSynEdit.SaveToFile(const AFilename: string);
var
  St: TATStrings;
  bChange1, bChange2, bChange3: boolean;
begin
  St:= Strings;
  bChange1:= false;
  bChange2:= false;
  bChange3:= false;

  if FOptSavingForceFinalEol then
    bChange1:= St.ActionEnsureFinalEol;

  if FOptSavingTrimSpaces then
  begin
    bChange2:= St.ActionTrimSpaces(cTrimRight);
    //caret may be after end-of-line, so fix it
    if not OptCaretVirtual then
      DoCaretsFixIncorrectPos(true);
  end;

  if FOptSavingTrimFinalEmptyLines then
  begin
    bChange3:= St.ActionTrimFinalEmptyLines;
    if bChange3 then
      DoCaretsFixIncorrectPos(false);
  end;

  if bChange1 or bChange2 or bChange3 then
  begin
    Update(true);
    DoEventChange;
  end;

  St.SaveToFile(AFilename);
  FFileName:= AFilename;
  Modified:= false;
end;


function TATSynEdit.GetStrings: TATStrings;
begin
  if Assigned(FStringsExternal) then
    Result:= FStringsExternal
  else
    Result:= FStringsInt;
end;

procedure TATSynEdit.SetCaretBlinkTime(AValue: integer);
begin
  AValue:= Max(AValue, ATEditorOptions.MinCaretTime);
  AValue:= Min(AValue, ATEditorOptions.MaxCaretTime);
  FCaretBlinkTime:= AValue;
  FTimerBlink.Interval:= AValue;
end;

procedure TATSynEdit.SetSpacingY(AValue: integer);
begin
  if FSpacingY=AValue then Exit;
  FSpacingY:= AValue;
  FWrapUpdateNeeded:= true;
end;

procedure TATSynEdit.SetMarginString(const AValue: string);
var
  Sep: TATStringSeparator;
  N: integer;
begin
  FMarginList:= nil;
  Sep.Init(AValue, ' ');
  repeat
    if not Sep.GetItemInt(N, 0) then Break;
    if N<2 then Continue;
    SetLength(FMarginList, Length(FMarginList)+1);
    FMarginList[Length(FMarginList)-1]:= N;
  until false;
end;

procedure TATSynEdit.SetMicromapVisible(AValue: boolean);
begin
  if FMicromapVisible=AValue then Exit;
  FMicromapVisible:= AValue;
  if not FMicromapOnScrollbar then
    FWrapUpdateNeeded:= true;
end;

procedure TATSynEdit.SetMinimapVisible(AValue: boolean);
begin
  if FMinimapVisible=AValue then Exit;
  FMinimapVisible:= AValue;
  FWrapUpdateNeeded:= true;
end;

procedure TATSynEdit.SetOneLine(AValue: boolean);
var
  St: TATStrings;
begin
  Carets.OneLine:= AValue;
  St:= Strings;
  St.OneLine:= AValue;

  if AValue then
  begin
    OptGutterVisible:= false;
    OptRulerVisible:= false;
    OptMinimapVisible:= false;
    //OptMicromapVisible:= false;
    OptCaretVirtual:= false;
    OptCaretManyAllowed:= false;
    OptUnprintedVisible:= false;
    OptWrapMode:= cWrapOff;
    OptScrollStyleHorz:= aessHide;
    OptScrollStyleVert:= aessHide;
    OptMouseMiddleClickAction:= mcaNone;
    OptMouseDragDrop:= false;
    OptMarginRight:= 1000;
    OptUndoLimit:= 200;

    DoCaretSingle(0, 0);

    while St.Count>1 do
      St.LineDelete(St.Count-1, false, false, false);
  end;
end;

procedure TATSynEdit.SetReadOnly(AValue: boolean);
begin
  if not FOptAllowReadOnly then Exit;
  Strings.ReadOnly:= AValue;
end;

procedure TATSynEdit.SetLineTop(AValue: integer);
begin
  if not HandleAllocated then
  begin
    FLineTopTodo:= AValue;
    exit;
  end;

  if AValue<=0 then
  begin
    FScrollVert.SetZero;
    Update;
    Exit
  end;

  //first make sure WrapInfo is filled with data;
  //then we can read WrapInfo and calc scroll pos;
  //this is required for restoring LineTop for n tabs, on opening CudaText.
  UpdateWrapInfo;

  DoScroll_LineTop(AValue, true);
end;

procedure TATSynEdit.DoScroll_SetPos(var AScrollInfo: TATEditorScrollInfo; APos: integer);
begin
  AScrollInfo.NPos:= APos;
  //must update other info in AScrollInfo
  UpdateScrollbars(true);
end;

procedure TATSynEdit.DoScroll_LineTop(ALine: integer; AUpdate: boolean);
var
  NFrom, NTo, i: integer;
begin
  if FWrapInfo=nil then exit;

  if (ALine<=0) or (FWrapInfo.Count=0) then
  begin
    FScrollVert.SetZero;
    if AUpdate then Update;
    Exit
  end;

  //find exact match
  FWrapInfo.FindIndexesOfLineNumber(ALine, NFrom, NTo);
  if NFrom>=0 then
  begin
    DoScroll_SetPos(FScrollVert, NFrom);
    if AUpdate then Update;
    Exit
  end;

  //find approx match
  for i:= 0 to FWrapInfo.Count-1 do
    with FWrapInfo[i] do
      if NLineIndex>=ALine then
      begin
        DoScroll_SetPos(FScrollVert, i);
        if AUpdate then Update;
        Exit
      end;
end;

procedure TATSynEdit.SetColumnLeft(AValue: integer);
begin
  DoScroll_SetPos(FScrollHorz, AValue);
  Update;
end;

procedure TATSynEdit.SetLinesFromTop(AValue: integer);
begin
  with FScrollVert do
    NPos:= Max(0, Min(NPosLast, NPos + (GetLinesFromTop - AValue)));
end;

procedure TATSynEdit.SetRedoAsString(const AValue: string);
begin
  Strings.RedoAsString:= AValue;
end;

procedure TATSynEdit.SetStrings(Obj: TATStrings);
begin
  FStringsExternal:= Obj;
end;

function TATSynEdit.GetTextOffset: TPoint;
var
  NGutterWidth: integer;
begin
  if ModeOneLine then
  begin
    Result.X:= OptTextOffsetLeft;
    Result.Y:= OptTextOffsetTop;
    exit;
  end;

  if FOptGutterVisible then
    NGutterWidth:= Gutter.Width
  else
    NGutterWidth:= 0;

  if FOptTextCenteringCharWidth>0 then
    Result.X:= Max(0, (ClientWidth - NGutterWidth -
                       FOptTextCenteringCharWidth * FCharSize.XScaled div ATEditorCharXScale) div 2)
  else
    Result.X:= OptTextOffsetLeft;

  Inc(Result.X, NGutterWidth);

  Result.Y:= OptTextOffsetTop;

  if FSpacingY<0 then
    Result.Y:= Max(Result.Y, -FSpacingY*2); //*2 is needed to not clip the first line

  if FOptRulerVisible then
    Inc(Result.Y, FRulerHeight);
end;

function TATSynEdit.GetPageLines: integer;
begin
  case FOptKeyPageUpDownSize of
    cPageSizeFull:
      Result:= GetVisibleLines;
    cPageSizeFullMinus1:
      Result:= GetVisibleLines-1;
    cPageSizeHalf:
      Result:= GetVisibleLines div 2;
  end;
end;

procedure TATSynEdit.DoPaintAll(C: TCanvas; ALineFrom: integer);
var
  NColorOther: TColor;
  NBlend: integer;
begin
  UpdateInitialVars(C);

  FColorFont:= Colors.TextFont;
  FColorBG:= Colors.TextBG;
  FColorGutterBG:= Colors.GutterBG;
  FColorGutterFoldBG:= Colors.GutterFoldBG;
  FColorRulerBG:= Colors.RulerBG;
  FColorCollapseMarkBG:= Colors.CollapseMarkBG;

  if Enabled then
  begin
    if FOptDimUnfocusedBack<>0 then
      if not _IsFocused then
      begin
        if FOptDimUnfocusedBack>0 then
          NColorOther:= clBlack
        else
          NColorOther:= clWhite;
        NBlend:= Abs(FOptDimUnfocusedBack);

        FColorBG:= ColorBlend(NColorOther, FColorBG, NBlend);
        FColorGutterBG:= ColorBlend(NColorOther, FColorGutterBG, NBlend);
        FColorGutterFoldBG:= ColorBlend(NColorOther, FColorGutterFoldBG, NBlend);
        FColorRulerBG:= ColorBlend(NColorOther, FColorRulerBG, NBlend);
        FColorCollapseMarkBG:= ColorBlend(NColorOther, FColorCollapseMarkBG, NBlend);
      end;
  end
  else
  begin
    FColorFont:= Colors.TextDisabledFont;
    FColorBG:= Colors.TextDisabledBG;
  end;

  Inc(FPaintCounter);
  FVisibleColumns:= GetVisibleColumns;
  FCaretShown:= false;
  Carets.GetSelections(FSel);

  if Assigned(FAdapterHilite) then
    FAdapterIsDataReady:= FAdapterHilite.IsDataReady
  else
    FAdapterIsDataReady:= true;

  UpdateGapForms(true);
  DoPaintMain(C, ALineFrom);
  UpdateGapForms(false);
  UpdateCaretsCoords;

  if Carets.Count>0 then
  begin
    if FOptShowCurColumn then
      DoPaintMarginLineTo(C, Carets[0].CoordX, ATEditorScale(1), Colors.MarginCaret);

    DoPaintRulerCaretMarks(C);
  end;

  DoPaintMarkersTo(C);
end;

function TATSynEdit.DoPaint(ALineFrom: integer): boolean;
//gets True if one of the scrollbars changed its Visible state
begin
  if csLoading in ComponentState then exit(false);
  if csDestroying in ComponentState then exit(false);

  UpdateTabHelper;

  if DoubleBuffered then
  begin
    if Assigned(FBitmap) then
      if cIntFlagBitmap in FPaintFlags then
      begin
        FBitmap.BeginUpdate(true);
        try
          DoPaintAll(FBitmap.Canvas, ALineFrom);
        finally
          FBitmap.EndUpdate();
        end;
      end;
  end
  else
    DoPaintAll(Canvas, ALineFrom);

  Result:= UpdateScrollbars(false);
end;

procedure TATSynEdit.DoPaintLockedWarning(C: TCanvas);
const
  cBitmapX = 20;
  cBitmapY = 20;
  cRectX = 85;
  cRectY = 40;
  cRectWidth = 300;
  cRectHeight = 10;
var
  NValue: integer;
  Bmp: TGraphic;
begin
  C.Brush.Color:= Colors.TextBG;
  C.FillRect(Rect(0, 0, Width, Height));

  if Strings.ProgressKind<>cStringsProgressSaving then
    Bmp:= ATEditorBitmaps.BitmapWait
  else
    Bmp:= ATEditorBitmaps.BitmapSaving;
  C.Draw(cBitmapX, cBitmapY, Bmp);

  NValue:= Strings.ProgressValue;
  if NValue>0 then
  begin
    C.Pen.Color:= Colors.TextSelBG;
    C.Brush.Color:= Colors.TextSelBG;
    C.FrameRect(
      cRectX,
      cRectY,
      cRectX + cRectWidth,
      cRectY + cRectHeight
      );
    C.FillRect(
      cRectX,
      cRectY,
      cRectX + cRectWidth * NValue div 100,
      cRectY + cRectHeight
      );
  end;
end;


procedure TATSynEdit.Paint;
var
  NLine: integer;
begin
  if not HandleAllocated then exit;

  FPaintWorking:= true;
  try
    if cIntFlagResize in FPaintFlags then
    begin
      Exclude(FPaintFlags, cIntFlagResize);
      if DoubleBuffered then
        if Assigned(FBitmap) then
          BitmapResizeBySteps(FBitmap, Width, Height);
    end;

    NLine:= -1;
    if FLineTopTodo>0 then
    begin
      NLine:= FLineTopTodo;
      FLineTopTodo:= 0;
    end;

    FPaintStarted:= true;
    PaintEx(NLine);
  finally
    FPaintWorking:= false;
  end;
end;

function TATSynEdit.IsNormalLexerActive: boolean;
var
  S: string;
begin
  if FAdapterHilite=nil then
    exit(false);
  S:= FAdapterHilite.GetLexerName;
  if S='-' then //none lexer
    exit(false);
  if SEndsWith(S, ' ^') then //lite lexer
    exit(false);
  Result:= true;
end;

procedure TATSynEdit.SetEditorIndex(AValue: integer);
begin
  if FEditorIndex=AValue then Exit;
  FEditorIndex:= AValue;
  FWrapInfo.EditorIndex:= AValue;
end;

procedure TATSynEdit.PaintEx(ALineNumber: integer);
var
  R: TRect;
begin
  //experimental, reduce flickering on typing in Markdown
  FOptAllowRepaintOnTextChange:= not IsNormalLexerActive;

  if IsLocked then
  begin
    DoPaintLockedWarning(Canvas);
    Exit
  end;

  if DoubleBuffered then
    if not Assigned(FBitmap) then exit;

  if ATEditorOptions.DebugTiming then
  begin
    FTickAll:= GetTickCount64;
    FTickMinimap:= 0;
  end;

  //if scrollbars shown, paint again
  if DoPaint(ALineNumber) then
    DoPaint(ALineNumber);
  Exclude(FPaintFlags, cIntFlagBitmap);

  if DoubleBuffered then
  //buf mode: timer tick don't give painting of whole bitmap
  //(cIntFlagBitmap off)
  begin
    DoPaintCarets(FBitmap.Canvas, true);
  end
  else
  //non-buf mode: timer tick clears whole canvas first.
  //we already painted bitmap above,
  //and now we invert carets or dont invert (use FCaretAllowNextBlink)
  begin
    if not FCaretBlinkEnabled or FCaretAllowNextBlink then
      DoPaintCarets(Canvas, true);
  end;

  if DoubleBuffered then
  begin
    //single place where we flush bitmap to canvas
    R:= Canvas.ClipRect;
    Canvas.CopyRect(R, FBitmap.Canvas, R);
  end;

  DoPaintMarkerOfDragDrop(Canvas);

  if ATEditorOptions.DebugTiming then
  begin
    FTickAll:= GetTickCount64-FTickAll;
    DoPaintTiming(Canvas);
  end;
end;

procedure TATSynEdit.Resize;
begin
  inherited;
  if not IsRepaintEnabled then exit;

  //avoid setting FLineTopTodo, which breaks the v-scroll-pos, if huge line is wrapped
  //and v-scroll-pos is in the middle of this line
  if (Width=FLastControlWidth) and
    (Height=FLastControlHeight) then exit;
  FLastControlWidth:= Width;
  FLastControlHeight:= Height;

  FLineTopTodo:= GetLineTop;

  Include(FPaintFlags, cIntFlagResize);
  if FWrapMode in [cWrapOn, cWrapAtWindowOrMargin] then
    FWrapUpdateNeeded:= true;

  if not FPaintStarted then exit;
  Invalidate;
end;

procedure TATSynEdit.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  InitMenuStd;
  inherited;
  if not Handled then
  begin
    DoHandleRightClick(MousePos.X, MousePos.Y);
    Handled:= true;
  end;
end;

procedure TATSynEdit.WMEraseBkgnd(var Msg: TLMEraseBkgnd);
begin
  //needed to remove flickering on resize and mouse-over
  Msg.Result:= 1;
end;

procedure TATSynEdit.DoHintShow;
var
  S: string;
  P: TPoint;
  R: TRect;
begin
  if csDesigning in ComponentState then Exit;
  if not FOptShowScrollHint then Exit;

  if FHintWnd=nil then
    FHintWnd:= THintWindow.Create(Self);

  S:= ATEditorOptions.TextHintScrollPrefix+' '+IntToStr(LineTop+1);
  R:= FHintWnd.CalcHintRect(500, S, nil);

  P:= ClientToScreen(Point(ClientWidth-R.Width, 0));
  OffsetRect(R, P.X, P.Y);
  OffsetRect(R, -ATEditorOptions.HintScrollDx, ATEditorOptions.HintScrollDx);

  FHintWnd.ActivateHint(R, S);
  FHintWnd.Invalidate; //for Win
end;

procedure TATSynEdit.DoHintShowForBookmark(ALine: integer);
var
  S: string;
  P: TPoint;
  R: TRect;
  NIndex: integer;
begin
  if csDesigning in ComponentState then Exit;

  if FHintWnd=nil then
    FHintWnd:= THintWindow.Create(Self);

  NIndex:= Strings.Bookmarks.Find(ALine);
  if NIndex<0 then exit;

  S:= Strings.Bookmarks[NIndex]^.Data.Hint;
  if S='' then
    begin DoHintHide; exit end;

  R:= FHintWnd.CalcHintRect(500, S, nil);

  P:= Mouse.CursorPos;
  OffsetRect(R, P.X+ATEditorOptions.HintBookmarkDx, P.Y+ATEditorOptions.HintBookmarkDy);

  FHintWnd.ActivateHint(R, S);
  FHintWnd.Invalidate; //for Win
end;


procedure TATSynEdit.DoHintHide;
begin
  if Assigned(FHintWnd) then
    FHintWnd.Hide;
end;

procedure _UpdateScrollInfoFromSmoothPos(
  var AInfo: TATEditorScrollInfo;
  const APos: Int64;
  AWrapInfo: TATWrapInfo;
  AGaps: TATGaps);
//Note: for vertical bar, NPos=-1 means than we are before the first line, over top gap
var
  NPos, NPixels, NLineIndex: Int64;
  NSizeGapTop, NSizeGap0: Int64;
  bConsiderGaps: boolean;
begin
  AInfo.SmoothPos:= APos;
  bConsiderGaps:= AInfo.Vertical and (AGaps.Count>0);

  if APos<=0 then
  begin
    AInfo.SetZero;
    if bConsiderGaps then
      if AGaps.SizeOfGapTop>0 then
        AInfo.NPos:= -1;
    exit
  end;

  if APos>=AInfo.SmoothPosLast then
  begin
    AInfo.SetLast;
    exit
  end;

  if bConsiderGaps then
  begin
    //for position before line=0
    NSizeGapTop:= AGaps.SizeOfGapTop;
    NSizeGap0:= AGaps.SizeOfGap0;

    if NSizeGapTop>0 then
      if APos<NSizeGapTop then
      begin
        AInfo.NPos:= -1;
        AInfo.NPixelOffset:= APos;
        exit;
      end;

    //for position before line=1
    //(other positions are calculated ok later)
    if NSizeGap0>0 then
      if APos<NSizeGapTop+AInfo.CharSizeScaled div ATEditorCharXScale + NSizeGap0 then
      begin
        AInfo.NPos:= 0;
        AInfo.NPixelOffset:= APos-NSizeGapTop;
        exit;
      end;
  end;

  AInfo.NPos:= Min(APos * ATEditorCharXScale div AInfo.CharSizeScaled, AInfo.NMax);
  AInfo.NPixelOffset:= APos mod (AInfo.CharSizeScaled div ATEditorCharXScale);

  //consider Gaps for vert scrolling
  if bConsiderGaps then
  begin
    NPos:= Min(AInfo.NPos, AWrapInfo.Count-1);
    NPixels:= AInfo.NPixelOffset;

    repeat
      NLineIndex:= AWrapInfo.Data[NPos].NLineIndex - 1;
      NPixels:= APos - NPos* AInfo.CharSizeScaled div ATEditorCharXScale - AGaps.SizeForLineRange(-1, NLineIndex);
      if NPos=0 then Break;
      if NLineIndex=0 then Break;
      if NPixels>=0 then Break;
      Dec(NPos);
    until false;

    AInfo.NPos:= NPos;
    AInfo.NPixelOffset:= NPixels
  end;
end;

procedure TATSynEdit.UpdateScrollInfoFromSmoothPos(var AInfo: TATEditorScrollInfo; const APos: Int64);
begin
  _UpdateScrollInfoFromSmoothPos(AInfo, APos, WrapInfo, Gaps);
end;

function TATSynEdit.UpdateScrollInfoFromMessage(var AInfo: TATEditorScrollInfo; const AMsg: TLMScroll): boolean;
begin
  if AInfo.NMax<AInfo.NPage then
  begin
    AInfo.Clear;
    Exit(true);
  end;

  case AMsg.ScrollCode of
    SB_TOP:
      begin
        UpdateScrollInfoFromSmoothPos(AInfo, 0);
      end;

    SB_BOTTOM:
      begin
        UpdateScrollInfoFromSmoothPos(AInfo, AInfo.SmoothPosLast);
      end;

    SB_LINEUP:
      begin
        UpdateScrollInfoFromSmoothPos(AInfo, AInfo.SmoothPos-AInfo.CharSizeScaled div ATEditorCharXScale);
      end;

    SB_LINEDOWN:
      begin
        UpdateScrollInfoFromSmoothPos(AInfo, AInfo.SmoothPos+AInfo.CharSizeScaled div ATEditorCharXScale);
      end;

    SB_PAGEUP:
      begin
        UpdateScrollInfoFromSmoothPos(AInfo, AInfo.SmoothPos-AInfo.SmoothPage);
      end;

    SB_PAGEDOWN:
      begin
        UpdateScrollInfoFromSmoothPos(AInfo, AInfo.SmoothPos+AInfo.SmoothPage);
      end;

    SB_THUMBPOSITION:
      begin
        //must ignore message with AMsg.Msg set: LM_VSCROLL, LM_HSCROLL;
        //we get it on macOS during window resize, not expected! moves v-scroll pos to 0.
        if AMsg.Msg=0 then
          UpdateScrollInfoFromSmoothPos(AInfo, AMsg.Pos);
      end;

    SB_THUMBTRACK:
      begin
        UpdateScrollInfoFromSmoothPos(AInfo, AMsg.Pos);
        if AInfo.Vertical then
          DoHintShow;
      end;

    SB_ENDSCROLL:
      DoHintHide;
  end;

  //correct value (if -1)
  if AInfo.SmoothPos>AInfo.SmoothPosLast then
    UpdateScrollInfoFromSmoothPos(AInfo, AInfo.SmoothPosLast)
  else
  if AInfo.SmoothPos<0 then
    UpdateScrollInfoFromSmoothPos(AInfo, 0);

  Result:= AMsg.ScrollCode<>SB_THUMBTRACK;
end;

procedure TATSynEdit.WMVScroll(var Msg: TLMVScroll);
begin
  UpdateScrollInfoFromMessage(FScrollVert, Msg);
  InvalidateEx(true, true);
end;

{$ifdef windows}
procedure TATSynEdit.WMIME_Request(var Msg: TMessage);
begin
  if Assigned(FAdapterIME) then
    FAdapterIME.ImeRequest(Self, Msg);
end;

procedure TATSynEdit.WMIME_Notify(var Msg: TMessage);
begin
  if Assigned(FAdapterIME) then
    FAdapterIME.ImeNotify(Self, Msg);
end;

procedure TATSynEdit.WMIME_StartComposition(var Msg: TMessage);
begin
  if Assigned(FAdapterIME) then
    FAdapterIME.ImeStartComposition(Self, Msg);
end;

procedure TATSynEdit.WMIME_Composition(var Msg: TMessage);
begin
  if Assigned(FAdapterIME) then
    FAdapterIME.ImeComposition(Self, Msg);
end;

procedure TATSynEdit.WMIME_EndComposition(var Msg: TMessage);
begin
  if Assigned(FAdapterIME) then
    FAdapterIME.ImeEndComposition(Self, Msg);
end;
{$endif}

procedure TATSynEdit.WMHScroll(var Msg: TLMHScroll);
begin
  UpdateScrollInfoFromMessage(FScrollHorz, Msg);
  InvalidateEx(true, true);
end;

procedure TATSynEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  PosTextClicked: TPoint;
  PosDetails: TATEditorPosDetails;
  Index: integer;
  ActionId: TATEditorMouseAction;
  bClickOnSelection: boolean;
  R: TRect;
begin
  if not OptMouseEnableAll then exit;
  inherited;
  SetFocus;
  DoCaretForceShow;

  FMouseDownCoordOriginal.X:= X;
  FMouseDownCoordOriginal.Y:= Y;
  FMouseDownCoord.X:= X + FScrollHorz.TotalOffset;
  FMouseDownCoord.Y:= Y + FScrollVert.TotalOffset;
  FMouseDownWithCtrl:= ssXControl in Shift;
  FMouseDownWithAlt:= ssAlt in Shift;
  FMouseDownWithShift:= ssShift in Shift;

  if FMinimapVisible and PtInRect(FRectMinimap, Point(X, Y)) then
  begin
    GetRectMinimapSel(R);
    FMouseDownOnMinimap:= true;
    FMouseDragMinimapSelHeight:= R.Height;
    if FMinimapDragImmediately then
    begin
      FCursorOnMinimap:= true;
      FMouseDragMinimap:= true;
      FMouseDragMinimapDelta:= FMouseDragMinimapSelHeight div 2;
      FMouseDownOnMinimap:= false;
      DoMinimapDrag(Y);
    end
    else
    if PtInRect(R, Point(X, Y)) then
    begin
      FMouseDragMinimap:= true;
      FMouseDragMinimapDelta:= Y-R.Top;
    end;
    Exit;
  end;

  PosTextClicked:= ClientPosToCaretPos(Point(X, Y), PosDetails);
  FCaretSpecPos:= false;
  FMouseDownOnMinimap:= false;
  FMouseDownGutterLineNumber:= -1;
  FMouseDragDropping:= false;
  FMouseDragDroppingReal:= false;
  FMouseDragMinimap:= false;
  ActionId:= EditorMouseActionId(FMouseActions, Shift);
  bClickOnSelection:= false;

  ClearSelRectPoints; //SelRect points will be set in MouseMove

  if Assigned(FAdapterIME) then
    FAdapterIME.Stop(Self, false);

  if MouseNiceScroll then
  begin
    MouseNiceScroll:= false;
    Exit
  end;

  if PtInRect(FRectMain, Point(X, Y)) then
  begin
    FMouseDownPnt:= PosTextClicked;
    bClickOnSelection:= Carets.FindCaretContainingPos(FMouseDownPnt.X, FMouseDownPnt.Y)>=0;

    if Shift=[ssMiddle] then
      if DoHandleClickEvent(FOnClickMiddle) then Exit;

    //Ctrl+click on selection must not be ignored, but must start drag-drop with copying
    if ActionId=cMouseActionMakeCaret then
      if bClickOnSelection then
        ActionId:= cMouseActionClickSimple;

    if ActionId=cMouseActionClickMiddle then
    begin
      case FOptMouseMiddleClickAction of
        mcaScrolling:
          begin
            FMouseNiceScrollPos:= Point(X, Y);
            MouseNiceScroll:= true;
          end;
        mcaPaste:
          begin
            //don't set caret pos here, user needs to press middle-btn on any place to paste
            DoCommand(cCommand_ClipboardAltPaste, cInvokeInternal); //uses PrimarySelection:TClipboard
          end;
        mcaGotoDefinition:
          begin
            if cCommand_GotoDefinition>0 then
            begin
              DoCaretSingle(PosTextClicked.X, PosTextClicked.Y);
              DoCommand(cCommand_GotoDefinition, cInvokeInternal);
            end;
          end;
      end;
      Exit
    end;

    if ActionId=cMouseActionClickSimple then
    begin
      ActionAddJumpToUndo;
      Strings.SetGroupMark;

      FSelRect:= cRectEmpty;
      DoCaretSingleAsIs;

      if Assigned(PosDetails.OnGapItem) then
      begin
        if Assigned(FOnClickGap) then
          FOnClickGap(Self, PosDetails.OnGapItem, PosDetails.OnGapPos);
      end;

      if FOptMouseDragDrop and bClickOnSelection then
      begin
        //DragMode must be dmManual, drag started by code
        FMouseDragDropping:= true;
      end
      else
      begin
        if Assigned(FOnClickMoveCaret) then
          FOnClickMoveCaret(Self, Point(Carets[0].PosX, Carets[0].PosY), FMouseDownPnt);

        DoCaretSingle(FMouseDownPnt.X, FMouseDownPnt.Y);
        DoSelect_None;
      end;
    end;

    if ActionId=cMouseActionClickAndSelNormalBlock then
    begin
      FSelRect:= cRectEmpty;
      DoCaretSingleAsIs;
      Carets[0].SelectToPoint(FMouseDownPnt.X, FMouseDownPnt.Y);
    end;

    if ActionId=cMouseActionClickAndSelVerticalBlock then
    begin
      FSelRect:= cRectEmpty;
      DoCaretSingleAsIs;
      with Carets[0] do
        DoSelect_ColumnBlock_FromPoints(
          Point(PosX, PosY),
          FMouseDownPnt
          );
    end;

    if ActionId=cMouseActionMakeCaret then
    begin
      FSelRect:= cRectEmpty;
      DoCaretAddToPoint(FMouseDownPnt.X, FMouseDownPnt.Y);
    end;

    if ActionId=cMouseActionMakeCaretsColumn then
    begin
      FSelRect:= cRectEmpty;
      DoCaretsColumnToPoint(FMouseDownPnt.X, FMouseDownPnt.Y);
    end;

    if ActionId=cMouseActionClickRight then
    begin
      if FOptMouseRightClickMovesCaret then
        if not bClickOnSelection then //click over selection must never reset that selection, like in Notepad++
          if Strings.IsIndexValid(PosTextClicked.Y) then
          begin
            DoCaretSingle(PosTextClicked.X, PosTextClicked.Y);
            DoSelect_None;
            Invalidate;
           end;
    end;
  end;

  if FOptGutterVisible and PtInRect(FRectGutter, Point(X, Y)) then
  begin
    if ActionId=cMouseActionClickSimple then
    begin
      Index:= FGutter.IndexAt(X);
      if Index=FGutterBandNumbers then
      begin
        if FOptMouseClickNumberSelectsLine then
        begin
          FSelRect:= cRectEmpty;
          FMouseDownGutterLineNumber:= PosTextClicked.Y;
          DoSelect_Line(PosTextClicked);
        end;
      end
      else
      if Index=FGutterBandFolding then
      begin
        DoFoldbarClick(PosTextClicked.Y);
      end
      else
        //click on other bands- event
        DoEventClickGutter(FGutter.IndexAt(X), PosTextClicked.Y);
    end;
  end;

  if FMicromapVisible and not FMicromapOnScrollbar and PtInRect(FRectMicromap, Point(X, Y)) then
    if ActionId=cMouseActionClickSimple then
    begin
      DoEventClickMicromap(X-FRectMicromap.Left, Y-FRectMicromap.Top);
      Exit
    end;

  //don't fire OnChangeCaretPos on right click
  if Button=mbRight then
    if not FOptMouseRightClickMovesCaret then
      exit;

  Carets.Sort;
  DoEventCarets;
  Update;
end;

procedure TATSynEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Str: atString;
  Caret: TATCaretItem;
  PosDetails: TATEditorPosDetails;
  PosTextClicked: TPoint;
  bMovedMinimal: boolean;
begin
  if not OptMouseEnableAll then exit;
  inherited;

  if FOptShowMouseSelFrame then
    if FMouseDragCoord.X>=0 then
    begin
      FMouseDragCoord:= Point(-1, -1);
      bMovedMinimal:= IsPointsDiffByDelta(Point(X, Y), FMouseDownCoordOriginal, ATEditorOptions.MouseMoveSmallDelta);
      if bMovedMinimal then
        Invalidate;
    end;

  if PtInRect(FRectMinimap, Point(X, Y)) then
  begin
    if FMouseDownOnMinimap then
    begin
      FMouseDownOnMinimap:= false;
      if not FMouseDragMinimap then
        DoMinimapClick(Y);
      FMouseDragMinimap:= false;
    end;
    Exit
  end;

  if PtInRect(ClientRect, Point(X, Y)) then
  if FMouseDragDropping then
  begin
    //drag-drop really started
    if FMouseDragDroppingReal then
    begin
      Strings.BeginUndoGroup;
      try
        DoDropText(not GetActualDragDropIsCopying);
      finally
        Strings.EndUndoGroup;
        Update;
      end;
    end
    else
    //mouse released w/o drag-drop
    begin
      PosTextClicked:= ClientPosToCaretPos(Point(X, Y), PosDetails);
      DoCaretSingle(PosTextClicked.X, PosTextClicked.Y);
      DoEventCarets;
      Update;
    end;
    FMouseDragDropping:= false;
    FMouseDragDroppingReal:= false;
  end;

  if FOptMouseClickOpensURL then
    if not FMouseDownDouble and not FMouseDragDropping and (Button=mbLeft) then
      if Carets.Count=1 then
      begin
        Caret:= Carets[0];
        Str:= DoGetLinkAtPos(Caret.PosX, Caret.PosY);
        if Str<>'' then
          if Assigned(FOnClickLink) then
            FOnClickLink(Self, Str);
      end;

  ClearMouseDownVariables;

  if Carets.Count=1 then
    with Carets[0] do
    begin
      //mouse-up after selection made
      if EndY>=0 then
      begin
        if Assigned(FOnClickEndSelect) then
          FOnClickEndSelect(Self, Point(EndX, EndY), Point(PosX, PosY));
      end
      //else: simple mouse click
    end;
end;

procedure TATSynEdit.ClearSelRectPoints;
begin
  FLastCommandMakesColumnSel:= false;
  FSelRectBegin:= Point(-1, -1);
  FSelRectEnd:= Point(-1, -1);
end;

procedure TATSynEdit.ClearMouseDownVariables;
begin
  FMouseDownCoordOriginal:= Point(-1, -1);
  FMouseDownCoord:= Point(-1, -1);
  FMouseDownPnt:= Point(-1, -1);
  FMouseDownGutterLineNumber:= -1;
  FMouseDownDouble:= false;
  FMouseDownAndColumnSelection:= false;
  FMouseDownOnMinimap:= false;
  FMouseDownWithCtrl:= false;
  FMouseDownWithAlt:= false;
  FMouseDownWithShift:= false;
  FMouseDragDropping:= false;
  FMouseDragDroppingReal:= false;
  FMouseDragMinimap:= false;
  if Assigned(FTimerScroll) then
    FTimerScroll.Enabled:= false;
end;

procedure TATSynEdit.DoHandleRightClick(X, Y: integer);
var
  Index: integer;
begin
  if PtInRect(FRectMain, Point(X, Y)) then
  begin
    if Assigned(FMenuText) then
      FMenuText.PopUp
    else
    begin
      InitMenuStd;
      FMenuStd.PopUp;
    end;
  end
  else
  if FOptGutterVisible and PtInRect(FRectGutter, Point(X, Y)) then
  begin
    Index:= FGutter.IndexAt(X);
    if Index=FGutterBandBookmarks then
      if Assigned(FMenuGutterBm) then FMenuGutterBm.PopUp;
    if Index=FGutterBandNumbers then
      if Assigned(FMenuGutterNum) then FMenuGutterNum.PopUp;
    if Index=FGutterBandFolding then
      if Assigned(FMenuGutterFold) then FMenuGutterFold.PopUp else DoMenuGutterFold;
  end
  else
  if FMinimapVisible and PtInRect(FRectMinimap, Point(X, Y)) then
  begin
    if Assigned(FMenuMinimap) then FMenuMinimap.PopUp;
  end
  else
  if FMicromapVisible and not FMicromapOnScrollbar and PtInRect(FRectMicromap, Point(X, Y)) then
  begin
    if Assigned(FMenuMicromap) then FMenuMicromap.PopUp;
  end
  else
  if FOptRulerVisible and PtInRect(FRectRuler, Point(X, Y)) then
  begin
    if Assigned(FMenuRuler) then FMenuRuler.PopUp;
  end;
end;

procedure TATSynEdit.UpdateCursor;
var
  PntMouse, P: TPoint;
begin
  if MouseNiceScroll then Exit;
  PntMouse:= Mouse.CursorPos;
  P:= ScreenToClient(PntMouse);
  if not PtInRect(ClientRect, P) then exit;

  if FMouseDragDropping and FMouseDragDroppingReal then
  begin
    //don't check here PtInRect(FRectMain, P), to have ok cursor
    //when dragging to another editor
    if ModeReadOnly then
      DragCursor:= crNoDrop
    else
    if GetActualDragDropIsCopying then
      DragCursor:= crMultiDrag
    else
      DragCursor:= crDrag;
    Cursor:= DragCursor;
  end
  else
  if PtInRect(FRectMain, P) then
  begin
    if FMouseDownAndColumnSelection then
      Cursor:= FCursorColumnSel
    else
      Cursor:= FCursorText;
  end
  else
  if PtInRect(FRectGutterBm, P) then
  begin
    if FMouseDownPnt.Y<0 then
      Cursor:= FCursorGutterBookmark;
  end
  else
  if PtInRect(FRectGutterNums, P) then
  begin
    if FMouseDownPnt.Y<0 then
      Cursor:= FCursorGutterNumbers;
  end
  else
  if PtInRect(FRectMinimap, P) then
    Cursor:= FCursorMinimap
  else
  if PtInRect(FRectMicromap, P) then
    Cursor:= FCursorMicromap
  else
    Cursor:= crDefault;
end;


procedure _LimitPointByRect(var P: TPoint; const R: TRect); inline;
begin
  if P.X<R.Left+1 then P.X:= R.Left+1;
  if P.X>R.Right then P.X:= R.Right;
  if P.Y<R.Top+1 then P.Y:= R.Top+1;
  if P.Y>R.Bottom then P.Y:= R.Bottom;
end;

procedure TATSynEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  bOnMain, bOnMinimap, bOnMicromap,
  bOnGutter, bOnGutterNumbers, bOnGutterBookmk,
  bSelecting, bSelectingGutterNumbers: boolean;
  bSelectAdding, bSelectColumnLeft, bSelectColumnMiddle: boolean;
  bMovedMinimal: boolean;
  bUpdateForMinimap: boolean;
  bStartTimerScroll: boolean;
  Details: TATEditorPosDetails;
  nIndex: integer;
  Caret: TATCaretItem;
begin
  if not OptMouseEnableAll then exit;
  inherited;

  P:= Point(X, Y);
  UpdateCursor;

  bMovedMinimal:= IsPointsDiffByDelta(P, FMouseDownCoordOriginal, ATEditorOptions.MouseMoveSmallDelta);

  bSelecting:= (not FMouseDragDropping) and (FMouseDownPnt.X>=0);
  bSelectingGutterNumbers:= FMouseDownGutterLineNumber>=0;

  bSelectAdding:= bSelecting and (ssLeft in Shift) and FMouseDownWithCtrl and not FMouseDownWithAlt and not FMouseDownWithShift;
  bSelectColumnLeft:= bSelecting and (ssLeft in Shift) and not FMouseDownWithCtrl and FMouseDownWithAlt and not FMouseDownWithShift;
  bSelectColumnMiddle:= bSelecting and (ssMiddle in Shift) and FMouseDownWithCtrl and not FMouseDownWithAlt and not FMouseDownWithShift;

  if bSelecting then
  begin
    FMouseDragCoord:= P;
    _LimitPointByRect(FMouseDragCoord, FRectMainVisible);
  end
  else
    FMouseDragCoord:= Point(-1, -1);

  bOnMain:= PtInRect(FRectMain, P);
  bOnMinimap:= FMinimapVisible and PtInRect(FRectMinimap, P);
  bOnMicromap:= FMicromapVisible and not FMicromapOnScrollbar and PtInRect(FRectMicromap, P);
  bOnGutter:= FOptGutterVisible and PtInRect(FRectGutter, P);
  bOnGutterNumbers:= bOnGutter and PtInRect(FRectGutterNums, P);
  bOnGutterBookmk:= bOnGutter and PtInRect(FRectGutterBm, P);

  //detect cursor on minimap
  if FMinimapVisible then
  begin
    bUpdateForMinimap:= false;
    if bOnMinimap<>FCursorOnMinimap then
      bUpdateForMinimap:= true;
    FCursorOnMinimap:= bOnMinimap;
    if FMinimapTooltipVisible and bOnMinimap then
    begin
      FMinimapTooltipEnabled:= true;
      bUpdateForMinimap:= true;
    end
    else
      FMinimapTooltipEnabled:= false;
    if bUpdateForMinimap then
      Update;

    //mouse dragged on minimap
    //handle this before starting FTimerScroll (CudaText issues 2941, 2944)
    if FMouseDragMinimap then
    begin
      if bMovedMinimal then
        if Shift=[ssLeft] then
          DoMinimapDrag(Y);
      Exit
      end;
  end;

  //detect cursor on gutter
  if FOptGutterVisible then
  begin
    if not FOptGutterShowFoldAlways then
      if bOnGutter<>FCursorOnGutter then
        Invalidate;
    FCursorOnGutter:= bOnGutter;
  end;

  //detect cursor on folded marks
  if FFoldTooltipVisible and Assigned(FFoldedMarkList) then
  begin
    FFoldedMarkCurrent:= FFoldedMarkList.FindByCoord(Point(X, Y));
    UpdateFoldedMarkTooltip;
  end;

  //show/hide bookmark hint
  if bOnGutterBookmk and not bSelecting then
  begin
    P:= ClientPosToCaretPos(Point(X, Y), Details);
    DoHintShowForBookmark(P.Y);
  end
  else
    DoHintHide;

  bStartTimerScroll:=
    FOptMouseEnableAll and
    FOptMouseEnableNormalSelection and
    FOptMouseEnableColumnSelection and
    (ssLeft in Shift) and
    (not bOnMain) and
    //auto-scroll must not work when cursor is over minimap/micromap
    (not bOnMinimap) and
    (not bOnMicromap) and
    (not bOnGutter);

  if bStartTimerScroll then
    InitTimerScroll;
  if Assigned(FTimerScroll) then
    FTimerScroll.Enabled:= bStartTimerScroll;

  FMouseAutoScrollDirection:= cDirNone;
  if (P.Y<FRectMain.Top) and (not ModeOneLine) then
    FMouseAutoScrollDirection:= cDirUp else
  if (P.Y>=FRectMain.Bottom) and (not ModeOneLine) then
    FMouseAutoScrollDirection:= cDirDown else
  if (P.X<FRectMain.Left) then
    FMouseAutoScrollDirection:= cDirLeft else
  if (P.X>=FRectMain.Right) then
    FMouseAutoScrollDirection:= cDirRight;

  //mouse dragged on gutter numbers (only if drag started on gutter numbers)
  if bSelectingGutterNumbers then
    if bOnGutterNumbers then
    begin
      if Shift=[ssLeft] then
      begin
        P:= ClientPosToCaretPos(P, Details);
        if (P.Y>=0) and (P.X>=0) then
        begin
          DoSelect_LineRange(FMouseDownGutterLineNumber, P);
          Carets.Sort;
          DoEventCarets;
          Invalidate;
        end;
      end;
    Exit
  end;

  //mouse drag-drop just begins
  if FMouseDragDropping then
  begin
    if not FMouseDragDroppingReal and
      IsPointsDiffByDelta(Point(X, Y), FMouseDownCoordOriginal, Mouse.DragThreshold) then
    begin
      FMouseDragDroppingReal:= true;
      BeginDrag(true);
    end
    else
      Invalidate; //Invalidate is needed even if nothing changed, just to paint drop-marker
    exit;
  end;

  //mouse just moved on text
  if bOnMain and (FMouseDownPnt.X<0) then
    begin
      if Shift*[ssLeft, ssRight]=[] then
        if Assigned(FHotspots) and (FHotspots.Count>0) then
        begin
          P:= ClientPosToCaretPos(P, Details);
          if P.Y>=0 then
          begin
            nIndex:= FHotspots.FindByPos(P.X, P.Y);
            if nIndex<>FLastHotspot then
            begin
              if FLastHotspot>=0 then
                if Assigned(FOnHotspotExit) then
                  FOnHotspotExit(Self, FLastHotspot);

              if nIndex>=0 then
                if Assigned(FOnHotspotEnter) then
                  FOnHotspotEnter(Self, nIndex);

              FLastHotspot:= nIndex;
            end;
          end;
        end;
      Exit
    end;

  //mouse dragged to select block
  if bSelecting then
    if bOnMain or bOnGutter then
    begin
      if (ssLeft in Shift) or bSelectColumnMiddle then
        if Carets.Count>0 then
        begin
          P:= ClientPosToCaretPos(P, Details);
          //Application.MainForm.Caption:= Format('MouseDownPnt %d:%d, CurPnt %d:%d',
            //[FMouseDownPnt.Y, FMouseDownPnt.X, P.Y, P.X]);
          if (P.Y<0) then Exit;

          //mouse not moved at last by char?
          if (FMouseDownPnt.X=P.X) and (FMouseDownPnt.Y=P.Y) then
          begin
            //remove selection from current caret
            nIndex:= Carets.IndexOfPosXY(FMouseDownPnt.X, FMouseDownPnt.Y, true);
            if Carets.IsIndexValid(nIndex) then
            begin
              Caret:= Carets[nIndex];
              Caret.PosX:= P.X;
              Caret.PosY:= P.Y;
              Caret.EndX:= -1;
              Caret.EndY:= -1;
            end;
            Invalidate;
          end
          else
          begin
            //drag w/out button pressed: single selection
            //ssShift is allowed to select by Shift+MouseWheel
            if not FMouseDownWithCtrl and not FMouseDownWithAlt then
            begin
              if FOptMouseEnableColumnSelection and FOptMouseColumnSelectionWithoutKey then
              begin
                //column selection
                FMouseDownAndColumnSelection:= true;
                DoCaretSingle(FMouseDownPnt.X, FMouseDownPnt.Y);
                DoSelect_None;
                DoSelect_ColumnBlock_FromPoints(FMouseDownPnt, P);
              end
              else
              if FOptMouseEnableNormalSelection then
              begin
                //normal selection
                DoCaretSingleAsIs;
                if FMouseDownDouble and FOptMouse2ClickDragSelectsWords then
                  DoSelect_WordRange(0, FMouseDownPnt, P)
                else
                  DoSelect_CharRange(0, P);
              end;
            end;

            //drag with Ctrl pressed: add selection
            if bSelectAdding then
            begin
              nIndex:= Carets.IndexOfPosXY(FMouseDownPnt.X, FMouseDownPnt.Y, true);
              DoSelect_CharRange(nIndex, P);
            end;

            //drag with Alt pressed: column selection
            //middle button drag with Ctrl pressed: the same
            if FOptMouseEnableColumnSelection then
              if bSelectColumnLeft or bSelectColumnMiddle then
              begin
                FMouseDownAndColumnSelection:= true;
                DoCaretSingle(FMouseDownPnt.X, FMouseDownPnt.Y);
                DoSelect_None;
                DoSelect_ColumnBlock_FromPoints(FMouseDownPnt, P);
              end;

            Carets.Sort;
            DoEventCarets;
            Invalidate;
          end;
        end;
      Exit;
    end;
end;

procedure TATSynEdit.MouseLeave;
begin
  if not OptMouseEnableAll then exit;
  inherited;
  DoHideAllTooltips;
end;

function TATSynEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: integer;
  MousePos: TPoint): boolean;
begin
  if not OptMouseEnableAll then exit(false);

  Result:= DoMouseWheelAction(Shift, WheelDelta, false)
end;

function TATSynEdit.DoMouseWheelHorz(Shift: TShiftState; WheelDelta: integer;
  MousePos: TPoint): boolean;
begin
  if not OptMouseEnableAll then exit(false);

  Result:= DoMouseWheelAction([], -WheelDelta, true);
end;

type
  TATMouseWheelMode = (
    aWheelModeNormal,
    aWheelModeHoriz,
    aWheelModeZoom
    );

procedure TATSynEdit.DoHideAllTooltips;
var
  bUpdate: boolean;
begin
  bUpdate:= FMinimapTooltipEnabled;

  DoHintHide;
  DoHotspotsExit;
  if Assigned(FFoldedMarkTooltip) then
    FFoldedMarkTooltip.Hide;
  FMinimapTooltipEnabled:= false;

  if bUpdate then
    Update;
end;

function TATSynEdit.DoMouseWheelAction(Shift: TShiftState;
  AWheelDelta: integer; AForceHorz: boolean): boolean;
var
  WheelRecord: TATEditorWheelRecord;
  Mode: TATMouseWheelMode;
  Pnt: TPoint;
begin
  Result:= false;
  if not OptMouseEnableAll then exit;
  if ModeOneLine then exit;
  DoHideAllTooltips;

  if AForceHorz then
    Mode:= aWheelModeHoriz
  else
  if (Shift=[FOptMouseWheelZoomsWithState]) then
    Mode:= aWheelModeZoom
  else
  // -[ssLeft] to ignore pressed mouse button
  if (Shift-[ssLeft]=[FOptMouseWheelScrollHorzWithState]) then
    Mode:= aWheelModeHoriz
  else
  // -[ssLeft] to ignore pressed mouse button
  if (Shift-[ssLeft]=[]) then
    Mode:= aWheelModeNormal
  else
    exit;

  WheelRecord:= Default(TATEditorWheelRecord);

  case Mode of
    aWheelModeNormal:
      begin
        if FOptMouseWheelScrollVert then
        begin
          WheelRecord.Kind:= wqkVert;
          WheelRecord.Delta:= AWheelDelta;
          //FWheelQueue.Push(WheelRecord);
          DoHandleWheelRecord(WheelRecord);
          Update;

          Result:= true;
        end;
      end;

    aWheelModeHoriz:
      begin
        if FOptMouseWheelScrollHorz then
        begin
          WheelRecord.Kind:= wqkHorz;
          WheelRecord.Delta:= AWheelDelta;
          //FWheelQueue.Push(WheelRecord);
          DoHandleWheelRecord(WheelRecord);
          Update;

          Result:= true;
        end;
      end;

    aWheelModeZoom:
      begin
        if FOptMouseWheelZooms then
        begin
          WheelRecord.Kind:= wqkZoom;
          WheelRecord.Delta:= AWheelDelta;
          //FWheelQueue.Push(WheelRecord);
          DoHandleWheelRecord(WheelRecord);
          Update;

          Result:= true;
        end;
      end;
  end;

  if ssLeft in Shift then
  begin
    Pnt:= ScreenToClient(Mouse.CursorPos);
    MouseMove(Shift, Pnt.X, Pnt.Y);
  end;
end;

function TATSynEdit.DoHandleClickEvent(AEvent: TATSynEditClickEvent): boolean;
begin
  Result:= false;
  if Assigned(AEvent) then
    AEvent(Self, Result);
end;

procedure TATSynEdit.DblClick;
var
  Caret: TATCaretItem;
  SLink: atString;
begin
  if not OptMouseEnableAll then exit;
  inherited;

  if DoHandleClickEvent(FOnClickDbl) then Exit;

  if FOptMouse2ClickOpensURL then
    if Carets.Count>0 then
    begin
      Caret:= Carets[0];
      SLink:= DoGetLinkAtPos(Caret.PosX, Caret.PosY);
      if SLink<>'' then
      begin
        if Assigned(FOnClickLink) then
          FOnClickLink(Self, SLink);
        DoEventCarets;
        exit
      end;
    end;

  case FOptMouse2ClickAction of
    cMouseDblClickSelectEntireLine:
      begin
        DoSelect_Line_ByClick;
      end;
    cMouseDblClickSelectWordChars:
      begin
        FMouseDownDouble:= true;
        DoSelect_ByDoubleClick(true);
      end;
    cMouseDblClickSelectAnyChars:
      begin
        FMouseDownDouble:= true;
        DoSelect_ByDoubleClick(false);
      end;
  end;

  DoEventCarets;
end;

procedure TATSynEdit.TripleClick;
begin
  if not OptMouseEnableAll then exit;
  inherited;

  if DoHandleClickEvent(FOnClickTriple) then Exit;

  if FOptMouse3ClickSelectsLine then
    DoSelect_Line_ByClick;
end;


procedure TATSynEdit.DoSelect_ByDoubleClick(AllowOnlyWordChars: boolean);
begin
  if not Strings.IsIndexValid(FMouseDownPnt.Y) then Exit;
  DoSelect_CharGroupAtPos(FMouseDownPnt, EditorIsPressedCtrl, AllowOnlyWordChars);
  Invalidate;
end;

function TATSynEdit.GetCaretManyAllowed: boolean;
begin
  Result:= Carets.ManyAllowed;
end;

procedure TATSynEdit.SetCaretManyAllowed(AValue: boolean);
begin
  Carets.ManyAllowed:= AValue;
  if not AValue then
    DoCaretSingleAsIs;
end;


procedure TATSynEdit.DoSelect_Line_ByClick;
var
  P: TPoint;
  Details: TATEditorPosDetails;
begin
  P:= ScreenToClient(Mouse.CursorPos);
  if PtInRect(FRectMain, P) then
  begin
    P:= ClientPosToCaretPos(P, Details);
    if P.Y<0 then Exit;
    DoSelect_Line(P);
    Invalidate;
  end;
end;

function TATSynEdit.IsInvalidateAllowed: boolean;
begin
  exit(true);

  {
  //solve CudaText issue #3461
  //but this gives random hangings on editing, e.g. CudaText #3475, also AT sees hangings on macOS
  if Assigned(AdapterForHilite) then
    Result:= AdapterForHilite.IsParsedAtLeastPartially
  else
    Result:= true;
    }

  { //debug
  if not Result then
    if Assigned(Application) and Assigned(Application.MainForm) then
      Application.MainForm.Caption:= 'skip invalidate: '+TimeToStr(Now)+', lexer: '+AdapterForHilite.GetLexerName;
    }
end;


procedure TATSynEdit.Invalidate;
begin
  InvalidateEx(false, false);
end;

procedure TATSynEdit.InvalidateEx(AForceRepaint, AForceOnScroll: boolean);
begin
  if not IsRepaintEnabled then exit;
  //if not IsInvalidateAllowed then exit;

  if not AForceRepaint then
  begin
    if ATEditorOptions.FlickerReducingPause>=1000 then
    begin
      if Assigned(AdapterForHilite) then
        if not AdapterForHilite.IsDataReadyPartially then exit;
    end
    else
    if ATEditorOptions.FlickerReducingPause>0 then
    begin
      FTimerFlicker.Enabled:= false;
      FTimerFlicker.Interval:= ATEditorOptions.FlickerReducingPause;
      FTimerFlicker.Enabled:= FTimersEnabled;
      exit;
    end;
  end;

  Include(FPaintFlags, cIntFlagBitmap);
  inherited Invalidate;

  if AForceOnScroll or (cIntFlagScrolled in FPaintFlags) then
  begin
    Exclude(FPaintFlags, cIntFlagScrolled);
    DoEventScroll;
  end;
end;

function TATSynEdit._IsFocused: boolean;
//this method is to speedup focused check (TControl.Focused prop is slower)
var
  C: TControl;
begin
  Result:= false;
  if not FIsEntered then exit;
  if not Application.Active then exit;

  C:= Self;
  while Assigned(C.Parent) do
    C:= C.Parent;
  if C is TForm then
    if not (C as TForm).Active then exit;

  Result:= true;
end;

procedure TATSynEdit.TimerBlinkTick(Sender: TObject);
begin
  if not FCaretShowEnabled then exit;
  if not Application.Active then exit;

  if FCaretStopUnfocused and not _IsFocused then
    if FCaretShown then
      exit;

  if not DoubleBuffered then
    FCaretAllowNextBlink:= not FCaretAllowNextBlink;

  DoPaintCarets(Canvas, true);
end;

procedure TATSynEdit.TimerScrollTick(Sender: TObject);
var
  nIndex: integer;
  PClient, PCaret: TPoint;
  Details: TATEditorPosDetails;
begin
  PClient:= ScreenToClient(Mouse.CursorPos);
  PClient.X:= Max(FRectMain.Left, PClient.X);
  PClient.Y:= Max(FRectMain.Top, PClient.Y);
  PClient.X:= Min(FRectMain.Right, PClient.X);
  PClient.Y:= Min(FRectMain.Bottom, PClient.Y);

  case FMouseAutoScrollDirection of
    cDirUp:
      DoScrollByDelta(0, -ATEditorOptions.SpeedScrollAutoVert);
    cDirDown:
      DoScrollByDelta(0, ATEditorOptions.SpeedScrollAutoVert);
    cDirLeft:
      DoScrollByDelta(-ATEditorOptions.SpeedScrollAutoHorz, 0);
    cDirRight:
      DoScrollByDelta(ATEditorOptions.SpeedScrollAutoHorz, 0);
    else
      Exit;
  end;

  PCaret:= ClientPosToCaretPos(PClient, Details);

  if (PCaret.X>=0) and (PCaret.Y>=0) then
  begin
    if FMouseDownGutterLineNumber>=0 then
    begin
      DoSelect_LineRange(FMouseDownGutterLineNumber, PCaret);
    end
    else
    if IsSelRectEmpty then
    begin
      nIndex:= Carets.IndexOfPosXY(FMouseDownPnt.X, FMouseDownPnt.Y, true);
      if nIndex>=0 then
        Carets[nIndex].SelectToPoint(PCaret.X, PCaret.Y);
    end
    else
    begin
      DoSelect_ColumnBlock_FromPoints(FMouseDownPnt, PCaret);
    end;
  end;

  Carets.Sort;
  DoEventCarets;
  Invalidate;
end;

procedure TATSynEdit.TimerNiceScrollTick(Sender: TObject);
var
  Pnt: TPoint;
  Dx, Dy: integer;
  Dir: TATEditorDirection;
  NBitmapSize: integer;
begin
  Pnt:= ScreenToClient(Mouse.CursorPos);
  if not PtInRect(FRectMain, Pnt) then Exit;

  ATEditorBitmaps.InitCursorsForNiceScroll;

  //delta in pixels
  Dx:= Pnt.X-FMouseNiceScrollPos.X;
  Dy:= Pnt.Y-FMouseNiceScrollPos.Y;

  NBitmapSize:= ATEditorBitmaps.BitmapNiceScroll.Width;
  if (Abs(Dx)<=NBitmapSize div 2) and
    (Abs(Dy)<=NBitmapSize div 2) then
    begin
      Cursor:= crNiceScrollNone;
      Exit;
    end;

  if (Dy<0) and (Abs(Dy)>Abs(Dx)) then Dir:= cDirUp else
    if (Dy>0) and (Abs(Dy)>Abs(Dx)) then Dir:= cDirDown else
      if Dx<0 then Dir:= cDirLeft else
        Dir:= cDirRight;

  case Dir of
    cDirLeft:
      Cursor:= crNiceScrollLeft;
    cDirRight:
      Cursor:= crNiceScrollRight;
    cDirUp:
      Cursor:= crNiceScrollUp;
    cDirDown:
      Cursor:= crNiceScrollDown;
  end;

  //delta in pixels
  Dx:= Sign(Dx)*((Abs(Dx)-NBitmapSize div 2) + 1) div ATEditorOptions.SpeedScrollNice;
  Dy:= Sign(Dy)*((Abs(Dy)-NBitmapSize div 2) + 1) div ATEditorOptions.SpeedScrollNice;

  if Dir in [cDirLeft, cDirRight] then
    DoScrollByDeltaInPixels(Dx, 0)
  else
    DoScrollByDeltaInPixels(0, Dy);

  Invalidate;
end;


procedure TATSynEdit.DoPaintCaretShape(C: TCanvas; ARect: TRect;
  ACaret: TATCaretItem; ACaretShape: TATCaretShape; ACaretColor: TColor);
var
  NCoordX, NCoordY: integer;
begin
  if not FCaretBlinkEnabled and ACaretShape.IsNarrow then
  begin
    C.Brush.Color:= ACaretColor;
    C.FillRect(ARect);
    exit;
  end;

  CanvasInvertRect(C, ARect, ACaretColor);

  if ACaretShape.EmptyInside then
  begin
    Inc(ARect.Left);
    Inc(ARect.Top);
    Dec(ARect.Right);
    Dec(ARect.Bottom);
    CanvasInvertRect(C, ARect, ACaretColor);
  end
  else
  if ATEditorOptions.CaretTextOverInvertedRect and not ACaretShape.IsNarrow then
  begin
    if (ACaret.CharStr<>'') and (ACaret.CharColor<>clNone) and not IsCharUnicodeSpace(ACaret.CharStr[1]) then
    begin
      C.Font.Color:= ACaret.CharColor;
      C.Font.Style:= ACaret.CharStyles;
      C.Brush.Style:= bsClear;
      NCoordX:= ACaret.CoordX;
      NCoordY:= ACaret.CoordY;
      if OptSpacingY<0 then
        Inc(NCoordY, OptSpacingY);
      CanvasTextOutSimplest(C, NCoordX, NCoordY, ACaret.CharStr);
    end;
  end;
end;

procedure TATSynEdit.DoPaintCarets(C: TCanvas; AWithInvalidate: boolean);
var
  Caret: TATCaretItem;
  CaretShape: TATCaretShape;
  NCaretColor: TColor;
  R: TRect;
  NCharWidth: integer;
  i: integer;
begin
  if csLoading in ComponentState then exit;
  if csDestroying in ComponentState then exit;
  if not FCaretShowEnabled then exit;

  //disable InvalidateRect during Paint
  if (csCustomPaint in ControlState) then
    AWithInvalidate:= false;
  if not IsInvalidateAllowed then
    AWithInvalidate:= false;

  if ModeReadOnly then
    CaretShape:= FCaretShapeReadonly
  else
  if ModeOverwrite then
    CaretShape:= FCaretShapeOverwrite
  else
    CaretShape:= FCaretShapeNormal;

  NCaretColor:= Colors.Caret;
  { //block was needed when we didn't have OptCaretHideUnfocused
  if (not FCaretStopUnfocused) or _IsFocused then
    NCaretColor:= Colors.Caret
  else
    //I cannot find proper color of NCaretColor, to make unfocused carets invisible,
    //tried several combinations: Colors.TextBG with Colors.TextFont with 'xor'.
    //at least value 'Colors.TextBG xor Colors.TextFont' gives PALE caret color
    //on many CudaText themes (default and dark themes).
    NCaretColor:= Colors.TextBG xor Colors.TextFont;
    }

  if FCaretBlinkEnabled then
    FCaretShown:= not FCaretShown
  else
    FCaretShown:= true;

  NCharWidth:= FCharSize.XScaled div ATEditorCharXScale;

  for i:= 0 to FCarets.Count-1 do
  begin
    Caret:= FCarets[i];
    if Caret.CoordX=-1 then Continue;
    R.Left:= Caret.CoordX;
    R.Top:= Caret.CoordY;
    R.Right:= R.Left+NCharWidth;
    R.Bottom:= R.Top+FCharSize.Y;

    //check caret is visible (IntersectRect is slower)
    if R.Right<=FRectMain.Left then Continue;
    if R.Bottom<=FRectMain.Top then Continue;
    if R.Left>=FRectMain.Right then Continue;
    if R.Top>=FRectMain.Bottom then Continue;

    DoCaretsApplyShape(R, CaretShape, NCharWidth, FCharSize.Y);

    if FCaretBlinkEnabled then
    begin
      //this block is to solve 'ghost caret on typing'
      //CudaText issue #3167
      if not FCaretShown then
      begin
        if Caret.OldRect.Width>0 then
        begin
          CanvasInvertRect(C, Caret.OldRect, NCaretColor);
          if AWithInvalidate then
            InvalidateRect(Handle, @Caret.OldRect, false);
        end;
      end;

      DoPaintCaretShape(C, R, Caret, CaretShape, NCaretColor);
    end
    else
    begin
      DoPaintCaretShape(C, R, Caret, CaretShape, NCaretColor);
    end;

    Caret.OldRect:= R;

    if AWithInvalidate then
      InvalidateRect(Handle, @R, false);
  end;
end;

procedure TATSynEdit.DoPaintMarkerOfDragDrop(C: TCanvas);
var
  Details: TATEditorPosDetails;
  NMarkWidth: integer;
  PntText, PntCoord: TPoint;
  R: TRect;
begin
  if not FOptShowDragDropMarker then exit;
  if not FMouseDragDropping then exit;
  if not FMouseDragDroppingReal then exit;

  PntText:= ClientPosToCaretPos(ScreenToClient(Mouse.CursorPos), Details);
  if PntText.Y<0 then exit;
  PntCoord:= CaretPosToClientPos(PntText);
  if PntCoord.Y<0 then exit;
  if not PtInRect(FRectMain, PntCoord) then exit;

  NMarkWidth:= ATEditorScale(FOptShowDragDropMarkerWidth);
  R.Left:= PntCoord.X - NMarkWidth div 2;
  R.Right:= R.Left + NMarkWidth;
  R.Top:= PntCoord.Y;
  R.Bottom:= R.Top + FCharSize.Y; //100% height

  C.Brush.Color:= Colors.DragDropMarker;
  C.FillRect(R);

  //InvalidateRect(Handle, @R, false); //doens't work for CudaText issue #3784
  Invalidate; //fix CudaText issue #3784
end;

procedure TATSynEdit.TimerBlinkDisable;
begin
  if ATEditorOptions.UsePaintStatic then
    FTimerBlink.Enabled:= false;
end;

procedure TATSynEdit.TimerBlinkEnable;
begin
  if ATEditorOptions.UsePaintStatic then
  begin
    FTimerBlink.Enabled:= false;
    FTimerBlink.Enabled:= FTimersEnabled and FCaretBlinkEnabled;
  end;
end;


procedure TATSynEdit.DoPaintLineIndent(C: TCanvas;
  const ARect: TRect;
  const ACharSize: TATEditorCharSize;
  ACoordY: integer;
  AIndentSize: integer;
  AColorBG: TColor;
  AScrollPos: integer;
  AIndentLines: boolean);
var
  i: integer;
  RBack: TRect;
begin
  if AIndentSize=0 then Exit;

  RBack:= Rect(0, 0, AIndentSize*ACharSize.XScaled div ATEditorCharXScale, ACharSize.Y);
  OffsetRect(RBack, ARect.Left-AScrollPos*ACharSize.XScaled div ATEditorCharXScale, ACoordY);

  C.Brush.Color:= AColorBG;
  C.FillRect(RBack);

  if AIndentLines then
    for i:= 0 to AIndentSize-1 do
      if i mod FTabSize = 0 then
        CanvasLine_DottedVertAlt(C,
          Colors.IndentVertLines,
          ARect.Left + (i-AScrollPos)*ACharSize.XScaled div ATEditorCharXScale,
          ACoordY,
          ACoordY+ACharSize.Y);
end;

procedure TATSynEdit.DoPaintSelectedLineBG(C: TCanvas;
  const ACharSize: TATEditorCharSize;
  const AVisRect: TRect;
  APointLeft, APointText: TPoint;
  const AWrapItem: TATWrapItem;
  ALineWidth: integer;
  const AScrollHorz: TATEditorScrollInfo);
var
  NLineIndex, NPartXAfter: integer;
  NLeft, NRight, i: integer;
  Ranges: TATSimpleRangeArray;
  RangeFrom, RangeTo: integer;
begin
  NLineIndex:= AWrapItem.NLineIndex;

  if not IsSelRectEmpty then
  begin
   //avoid weird look when empty area is filled in word-wrap mode
   if FWrapMode=cWrapOff then
    if (NLineIndex>=FSelRect.Top) and (NLineIndex<=FSelRect.Bottom) then
    begin
      NLeft:= APointLeft.X+ACharSize.XScaled*(FSelRect.Left-AScrollHorz.NPos) div ATEditorCharXScale;
      NRight:= NLeft+ACharSize.XScaled*FSelRect.Width div ATEditorCharXScale;
      NLeft:= Max(NLeft, APointText.X+ALineWidth);
      if (NLeft<NRight) then
      begin
        C.Brush.Color:= Colors.TextSelBG;
        C.FillRect(
          NLeft,
          APointLeft.Y,
          NRight,
          APointLeft.Y+ACharSize.Y);
      end;
    end;
  end
  else
  begin
    if not FOptShowFullSel then exit;
    NPartXAfter:= AWrapItem.NCharIndex-1+AWrapItem.NLength;

    //here we calculate ranges (XFrom, XTo) where selection(s) overlap current line,
    //and then paint fillrect for them
    TempSel_GetRangesInLineAfterPoint(NPartXAfter, NLineIndex, Ranges);

    for i:= 0 to Length(Ranges)-1 do
    begin
      RangeFrom:= Ranges[i].NFrom;
      RangeTo:= Ranges[i].NTo;

      //don't paint tail for cases
      //1) OptShowFullSel=false
      //2) middle WrapItem
      if RangeFrom>NPartXAfter then
        if (AWrapItem.NFinal=cWrapItemMiddle) then
          Continue;

      NLeft:= APointText.X + ALineWidth + (RangeFrom-NPartXAfter)*ACharSize.XScaled div ATEditorCharXScale;
      if RangeTo=MaxInt then
        NRight:= AVisRect.Right
      else
        NRight:= NLeft+(RangeTo-RangeFrom)*ACharSize.XScaled div ATEditorCharXScale;

      C.Brush.Color:= Colors.TextSelBG;
      C.FillRect(
        Max(AVisRect.Left, NLeft),
        APointText.Y,
        Min(AVisRect.Right, NRight),
        APointText.Y+ACharSize.Y
        );
    end;
  {
  if FOptShowFullSel then
    if AEolSelected then
    begin
      C.Brush.Color:= Colors.TextSelBG;
      C.FillRect(
        APointText.X,
        APointText.Y,
        AVisRect.Right,
        APointText.Y+ACharSize.Y);
    end;
    }
  end;
end;

procedure TATSynEdit.DoPaintNiceScroll(C: TCanvas);
var
  NBitmapSize: integer;
begin
  NBitmapSize:= ATEditorBitmaps.BitmapNiceScroll.Width;
  if MouseNiceScroll then
    C.Draw(
      FMouseNiceScrollPos.X - NBitmapSize div 2,
      FMouseNiceScrollPos.Y - NBitmapSize div 2,
      ATEditorBitmaps.BitmapNiceScroll);
end;

procedure TATSynEdit.DoPaintGutterNumber(C: TCanvas; ALineIndex, ACoordTop: integer; ABand: TATGutterItem);
//painting of text is slower, paint a special mark if possible
  //
  procedure PaintDash(W, H: integer);
  var
    P: TPoint;
  begin
    P.Y:= ACoordTop + FCharSize.Y div 2 - ATEditorScale(1);

    case FOptNumbersAlignment of
      taLeftJustify:
        P.X:= ABand.Left + FNumbersIndent;
      taRightJustify:
        P.X:= ABand.Right - FNumbersIndent - FCharSize.XScaled div ATEditorCharXScale div 2;
      taCenter:
        P.X:= (ABand.Left+ABand.Right) div 2;
    end;

    C.Brush.Color:= C.Font.Color;
    C.Brush.Style:= bsSolid;
    C.FillRect(
      P.X - W div 2,
      P.Y,
      P.X - W div 2 + W,
      P.Y + H
      );
  end;
  //
var
  SText: string;
  P: TPoint;
  NW: integer;
begin
  SText:= DoFormatLineNumber(ALineIndex+1);

  case SText of
    '':
      exit;

    '.':
      begin
        PaintDash(ATEditorScale(2), ATEditorScale(2));
      end;

    '-':
      begin
        PaintDash(FCharSize.XScaled div ATEditorCharXScale, ATEditorScale(2));
      end;

    else
      begin
        NW:= FCharSize.XScaled * Length(SText) div ATEditorCharXScale;

        P.Y:= ACoordTop;

        case FOptNumbersAlignment of
          taLeftJustify:
            P.X:= ABand.Left + FNumbersIndent;
          taRightJustify:
            P.X:= ABand.Right - NW - FNumbersIndent;
          taCenter:
            P.X:= (ABand.Left + ABand.Right - NW) div 2;
        end;

        Inc(P.Y, FTextOffsetFromTop);

        C.Brush.Style:= bsClear;
        CanvasTextOutSimplest(C, P.X, P.Y, SText);
      end;
  end;
end;


function TATSynEdit.DoEventCommand(ACommand: integer;
  AInvoke: TATEditorCommandInvoke; const AText: string): boolean;
begin
  Result:= false;
  if Assigned(FOnCommand) then
    FOnCommand(Self, ACommand, AInvoke, AText, Result);
end;

procedure TATSynEdit.DoEventCommandAfter(ACommand: integer; const AText: string);
begin
  if Assigned(FOnCommandAfter) then
    FOnCommandAfter(Self, ACommand, AText);
end;


procedure TATSynEdit.DoEventCarets;
begin
  if Assigned(FAdapterHilite) then
    FAdapterHilite.OnEditorCaretMove(Self);

  if Assigned(FOnChangeCaretPos) then
    FOnChangeCaretPos(Self);
end;

procedure TATSynEdit.DoEventScroll;
begin
  //horizontal scroll must clear CaretItem.SavedX values
  Carets.UpdateMemory(cCaretMem_ClearX, false);

  if Assigned(FAdapterHilite) then
    FAdapterHilite.OnEditorScroll(Self);

  if Assigned(FOnScroll) then
    FOnScroll(Self);
end;

procedure TATSynEdit.DoEventChange(ALineIndex: integer; AllowOnChange: boolean);
var
  HandlerChangeLog: TATStringsChangeLogEvent;
begin
  FLinkCache.Clear;

  if Assigned(FAdapterHilite) then
  begin
    FAdapterHilite.OnEditorChange(Self);

    if ALineIndex>=0 then
    begin
      HandlerChangeLog:= Strings.OnChangeLog;
      if Assigned(HandlerChangeLog) then
        HandlerChangeLog(nil, ALineIndex);
    end;
  end;

  if AllowOnChange then
  begin
    if Assigned(FOnChange) then
      FOnChange(Self);

    if FPrevModified<>Modified then
    begin
      FPrevModified:= Modified;
      if Assigned(FOnChangeModified) then
        FOnChangeModified(Self);
    end;
  end;

  //fire OnIdle after pause after change
  if FOptIdleInterval>0 then
  begin
    FTimerIdle.Enabled:= false;
    FTimerIdle.Interval:= FOptIdleInterval;
    FTimerIdle.Enabled:= true;
  end;
end;

procedure TATSynEdit.DoEventState;
begin
  if Assigned(FOnChangeState) then
    FOnChangeState(Self);
end;

procedure TATSynEdit.DoEventZoom;
begin
  if Assigned(FOnChangeZoom) then
    FOnChangeZoom(Self);
end;

procedure TATSynEdit.DoEventClickGutter(ABandIndex, ALineNumber: integer); inline;
begin
  if Assigned(FOnClickGutter) then
    FOnClickGutter(Self, ABandIndex, ALineNumber);
end;

procedure TATSynEdit.DoEventClickMicromap(AX, AY: integer); inline;
begin
  if Assigned(FOnClickMicromap) then
    FOnClickMicromap(Self, AX, AY);
end;

procedure TATSynEdit.DoEventDrawBookmarkIcon(C: TCanvas; ALineNumber: integer; const ARect: TRect); inline;
begin
  if Assigned(FOnDrawBookmarkIcon) then
    FOnDrawBookmarkIcon(Self, C, ALineNumber, ARect);
end;

procedure TATSynEdit.DoEventBeforeCalcHilite; inline;
begin
  if Assigned(FAdapterHilite) then
    FAdapterHilite.OnEditorBeforeCalcHilite(Self);

  if Assigned(FOnBeforeCalcHilite) then
    FOnBeforeCalcHilite(Self);
end;


procedure TATSynEdit.DoScrollToBeginOrEnd(AToBegin: boolean);
begin
  FScrollHorz.SetZero;
  if AToBegin then
    FScrollVert.SetZero
  else
    FScrollVert.SetLast;

  FScrollHorz.NPixelOffset:= 0;
  FScrollVert.NPixelOffset:= 0;

  UpdateScrollbars(true);
end;

procedure TATSynEdit.DoScrollByDelta(ADeltaX, ADeltaY: integer);
//
  procedure _Delta(var AInfo: TATEditorScrollInfo; ADelta: integer);
  begin
    if ADelta=0 then exit;
    with AInfo do
    begin
      NPos:= Max(0, Min(NPosLast, NPos+ADelta));
      if (NPos=0) or (NPos>=NPosLast) then
        NPixelOffset:= 0;
    end;
  end;
//
begin
  _Delta(FScrollHorz, ADeltaX);
  _Delta(FScrollVert, ADeltaY);
  UpdateScrollbars(true);
end;

procedure TATSynEdit.DoScrollByDeltaInPixels(ADeltaX, ADeltaY: integer);
//
  procedure _Delta(var AInfo: TATEditorScrollInfo; ADelta: integer);
  begin
    if ADelta=0 then exit;
    UpdateScrollInfoFromSmoothPos(AInfo,
      Min(AInfo.SmoothPosLast, AInfo.SmoothPos+ADelta));
  end;
//
begin
  _Delta(FScrollHorz, ADeltaX);
  _Delta(FScrollVert, ADeltaY);
end;

procedure TATSynEdit.MenuClick(Sender: TObject);
var
  Cmd: integer;
begin
  Cmd:= (Sender as TMenuItem).Tag;
  if Cmd>0 then
  begin
    DoCommand(Cmd, cInvokeMenuContext);
    Invalidate;
  end;
end;

procedure TATSynEdit.MenuStdPopup(Sender: TObject);
var
  i: integer;
begin
  MenuitemTextCut.Caption:= ATEditorOptions.TextMenuitemCut;
  MenuitemTextCopy.Caption:= ATEditorOptions.TextMenuitemCopy;
  MenuitemTextPaste.Caption:= ATEditorOptions.TextMenuitemPaste;
  MenuitemTextDelete.Caption:= ATEditorOptions.TextMenuitemDelete;
  MenuitemTextSelAll.Caption:= ATEditorOptions.TextMenuitemSelectAll;
  MenuitemTextUndo.Caption:= ATEditorOptions.TextMenuitemUndo;
  MenuitemTextRedo.Caption:= ATEditorOptions.TextMenuitemRedo;

  for i:= 0 to FMenuStd.Items.Count-1 do
    with FMenuStd.Items[i] do
    begin
      if Assigned(FKeymap) then
        ShortCut:= FKeymap.GetShortcutFromCommand(Tag);

      //separator items: hide if read-only, nicer menu
      if Caption='-' then
        Visible:= not ModeReadOnly;

      case Tag of
        cCommand_ClipboardCut:
          begin
            Enabled:= not ModeReadOnly;
            Visible:= not ModeReadOnly;
          end;
        cCommand_ClipboardPaste:
          begin
            Enabled:= not ModeReadOnly and Clipboard.HasFormat(CF_Text);
            Visible:= not ModeReadOnly;
          end;
        cCommand_TextDeleteSelection:
          begin
            Enabled:= not ModeReadOnly and Carets.IsSelection;
            Visible:= not ModeReadOnly;
          end;
        cCommand_Undo:
          begin
            Enabled:= not ModeReadOnly and (UndoCount>0);
            Visible:= not ModeReadOnly;
          end;
        cCommand_Redo:
          begin
            Enabled:= not ModeReadOnly and (RedoCount>0);
            Visible:= not ModeReadOnly;
          end;
      end;
    end;
end;

procedure TATSynEdit.InitMenuStd;
  //
  function Add(const SName: string; Cmd: integer): TMenuItem; inline;
  var
    MI: TMenuItem;
  begin
    MI:= TMenuItem.Create(FMenuStd);
    MI.Caption:= SName;
    MI.Tag:= Cmd;
    MI.OnClick:= @MenuClick;
    Result:= MI;
    FMenuStd.Items.Add(MI);
  end;
  //
begin
  if FMenuStd=nil then
  begin
    FMenuStd:= TPopupMenu.Create(Self);
    FMenuStd.OnPopup:= @MenuStdPopup;

    MenuitemTextUndo:= Add('Undo', cCommand_Undo);
    MenuitemTextRedo:= Add('Redo', cCommand_Redo);
    Add('-', 0);
    MenuitemTextCut:= Add('Cut', cCommand_ClipboardCut);
    MenuitemTextCopy:= Add('Copy', cCommand_ClipboardCopy);
    MenuitemTextPaste:= Add('Paste', cCommand_ClipboardPaste);
    MenuitemTextDelete:= Add('Delete', cCommand_TextDeleteSelection);
    Add('-', 0);
    MenuitemTextSelAll:= Add('Select all', cCommand_SelectAll);
  end;
end;

procedure TATSynEdit.InitTimerScroll;
begin
  if FTimerScroll=nil then
  begin
    FTimerScroll:= TTimer.Create(Self);
    FTimerScroll.Enabled:= false;
    FTimerScroll.Interval:= ATEditorOptions.TimerIntervalAutoScroll;
    FTimerScroll.OnTimer:= @TimerScrollTick;
  end;
end;

procedure TATSynEdit.InitTimerNiceScroll;
begin
  if FTimerNiceScroll=nil then
  begin
    FTimerNiceScroll:= TTimer.Create(Self);
    FTimerNiceScroll.Enabled:= false;
    FTimerNiceScroll.Interval:= ATEditorOptions.TimerIntervalNiceScroll;
    FTimerNiceScroll.OnTimer:= @TimerNiceScrollTick;
  end;
end;

//drop selection of 1st caret into mouse-pos
procedure TATSynEdit.DoDropText(AndDeleteSelection: boolean);
var
  St: TATStrings;
  Str: atString;
  P, PosAfter, Shift: TPoint;
  X1, Y1, X2, Y2: integer;
  bSel: boolean;
  Relation: TATPosRelation;
  Details: TATEditorPosDetails;
begin
  if ModeReadOnly then exit;
  St:= Strings;
  if Carets.Count<>1 then Exit; //allow only 1 caret
  Carets[0].GetRange(X1, Y1, X2, Y2, bSel);
  if not bSel then Exit;

  DoSelect_None;

  //calc insert-pos
  P:= ScreenToClient(Mouse.CursorPos);
  P:= ClientPosToCaretPos(P, Details);
  if P.Y<0 then exit;

  //can't drop into selection
  Relation:= IsPosInRange(P.X, P.Y, X1, Y1, X2, Y2);
  if Relation=cRelateInside then exit;

  Str:= St.TextSubstring(X1, Y1, X2, Y2);
  if Str='' then exit;
  BeginEditing;

  //insert before selection?
  if Relation=cRelateBefore then
  begin
    if AndDeleteSelection then
      St.TextDeleteRange(X1, Y1, X2, Y2, Shift, PosAfter);
    St.TextInsert(P.X, P.Y, Str, false, Shift, PosAfter);

    //select moved text
    DoCaretSingle(PosAfter.X, PosAfter.Y, P.X, P.Y);
  end
  else
  begin
    St.TextInsert(P.X, P.Y, Str, false, Shift, PosAfter);

    //select moved text
    DoCaretSingle(PosAfter.X, PosAfter.Y, P.X, P.Y);

    if AndDeleteSelection then
    begin
      St.TextDeleteRange(X1, Y1, X2, Y2, Shift, PosAfter);
      DoCaretsShift(0, X1, Y1, Shift.X, Shift.Y, PosAfter);
    end;
  end;

  DoEventCarets;

  EndEditing(true);
  {
  NChangedLine:= St.EditingTopLine; //Min(Y1, P.Y)
  DoEventChange(NChangedLine);
    //with DoEventChange(ALineIndex=-1), we have broken syntax highlight,
    //after drag-drop from huge line, to the lower position of the same huge line,
    //e.g. in 100K HTML file with huge line
  }

  Update(true);
end;

function TATSynEdit.GetIndentString: UnicodeString;
begin
  if FOptTabSpaces then
    Result:= StringOfCharW(' ', FTabSize)
  else
    Result:= #9;
end;

function TATSynEdit.GetAutoIndentString(APosX, APosY: integer; AUseIndentRegexRule: boolean): atString;
var
  StrPrev, StrIndent: atString;
  NChars, NSpaces: integer;
  MatchPos, MatchLen: integer;
  bAddIndent: boolean;
begin
  Result:= '';
  if not FOptAutoIndent then Exit;
  if not Strings.IsIndexValid(APosY) then Exit;

  StrPrev:= Strings.LineSub(APosY, 1, APosX);
  if StrPrev='' then exit;
  NChars:= SGetIndentChars(StrPrev); //count of chars in indent

  bAddIndent:=
    AUseIndentRegexRule and
    (FOptAutoIndentRegexRule<>'') and
    SFindRegexMatch(StrPrev, FOptAutoIndentRegexRule{%H-}, MatchPos, MatchLen);

  StrIndent:= Copy(StrPrev, 1, NChars);
  NSpaces:= Length(FTabHelper.TabsToSpaces(APosY, StrIndent));

  case FOptAutoIndentKind of
    cIndentAsPrevLine:
      Result:= StrIndent;
    cIndentSpacesOnly:
      Result:= StringOfCharW(' ', NSpaces);
    cIndentTabsOnly:
      Result:= StringOfCharW(#9, NSpaces div FTabSize);
    cIndentTabsAndSpaces:
      Result:= StringOfCharW(#9, NSpaces div FTabSize) + StringOfCharW(' ', NSpaces mod FTabSize);
    cIndentToOpeningBracket:
      begin
        //indent like in prev line + spaces up to opening bracket
        NSpaces:= SGetIndentCharsToOpeningBracket(StrPrev);
        Result:= StrIndent + StringOfCharW(' ', NSpaces-Length(StrIndent));
      end;
  end;

  if bAddIndent then
    Result:= Result+GetIndentString;
end;

function TATSynEdit.GetModified: boolean;
begin
  Result:= Strings.Modified;
end;

procedure TATSynEdit.SetModified(AValue: boolean);
begin
  Strings.Modified:= AValue;
  if AValue then
    DoEventChange
  else
    FPrevModified:= false;
end;

function TATSynEdit.GetOneLine: boolean;
begin
  Result:= Strings.OneLine;
end;

function TATSynEdit.GetRedoCount: integer;
begin
  Result:= Strings.RedoCount;
end;

function TATSynEdit.GetLinesFromTop: integer;
var
  P: TPoint;
begin
  if Carets.Count=0 then
    begin Result:= 0; Exit end;
  with Carets[0] do
    P:= Point(PosX, PosY);
  P:= CaretPosToClientPos(P);
  Result:= (P.Y-FRectMain.Top) div FCharSize.Y;
end;

function TATSynEdit.GetText: UnicodeString;
begin
  Result:= DoGetTextString;
end;

function TATSynEdit.DoGetTextString: atString;
begin
  //TATEdit overrides it
  Result:= Strings.TextString_Unicode;
end;

function TATSynEdit.IsRepaintNeededOnEnterOrExit: boolean; inline;
begin
  Result:=
    FOptShowCurLineOnlyFocused or
    FOptBorderFocusedActive or
    FCaretStopUnfocused;
end;

procedure TATSynEdit.DoEnter;
begin
  inherited;
  FIsEntered:= true;
  if FCaretHideUnfocused then
    FCaretShowEnabled:= true;
  if IsRepaintNeededOnEnterOrExit then
    Invalidate;
  TimersStart;
end;

procedure TATSynEdit.DoExit;
begin
  inherited;
  FIsEntered:= false;
  if FCaretHideUnfocused then
    FCaretShowEnabled:= false;
  if IsRepaintNeededOnEnterOrExit then
    Invalidate;
  TimersStop;
end;

procedure TATSynEdit.TimersStart;
//TimersStart/Stop are added to minimize count of running timers
begin
  FTimersEnabled:= true;
  if Assigned(FTimerBlink) then
    FTimerBlink.Enabled:= FTimersEnabled and FCaretBlinkEnabled;
end;

procedure TATSynEdit.TimersStop;
begin
  FTimersEnabled:= false;

  if Assigned(FTimerBlink) then
    FTimerBlink.Enabled:= false;

  if Assigned(FTimerIdle) then
    FTimerIdle.Enabled:= false;

  if Assigned(FTimerScroll) then
    FTimerScroll.Enabled:= false;

  if Assigned(FTimerNiceScroll) then
    FTimerNiceScroll.Enabled:= false;

  if Assigned(FTimerDelayedParsing) then
    FTimerDelayedParsing.Enabled:= false;

  if Assigned(FTimerFlicker) then
    FTimerFlicker.Enabled:= false;
end;

procedure TATSynEdit.DoMinimapClick(APosY: integer);
var
  NItem: integer;
begin
  NItem:= GetMinimap_ClickedPosToWrapIndex(APosY);
  if NItem>=0 then
  begin
    NItem:= Max(0, NItem - GetVisibleLines div 2);
    DoScroll_SetPos(FScrollVert, Min(NItem, FScrollVert.NMax));
    Update;
  end;
end;

procedure TATSynEdit.DoMinimapDrag(APosY: integer);
begin
  DoScroll_SetPos(FScrollVert, GetMinimap_DraggedPosToWrapIndex(APosY));
  Update;
end;

function TATSynEdit.GetUndoAsString: string;
begin
  Result:= Strings.UndoAsString;
end;

function TATSynEdit.GetRedoAsString: string;
begin
  Result:= Strings.RedoAsString;
end;

procedure TATSynEdit.SetUndoLimit(AValue: integer);
begin
  FOptUndoLimit:= Max(0, AValue);
  Strings.UndoLimit:= FOptUndoLimit;
end;

function TATSynEdit.GetUndoAfterSave: boolean;
begin
  Result:= Strings.UndoAfterSave;
end;

function TATSynEdit.GetUndoCount: integer;
begin
  Result:= Strings.UndoCount;
end;

procedure TATSynEdit.SetUndoAfterSave(AValue: boolean);
begin
  Strings.UndoAfterSave:= AValue;
end;

procedure TATSynEdit.SetUndoAsString(const AValue: string);
begin
  Strings.UndoAsString:= AValue;
end;

procedure TATSynEdit.DoScaleFontDelta(AInc: boolean; AllowUpdate: boolean);
const
  cMinScale = 60;
  cStep = 10;
//var
//  NTop: integer;
begin
  if FOptScaleFont=0 then
  begin
    FOptScaleFont:= ATEditorScaleFontPercents;
    if FOptScaleFont=0 then
      FOptScaleFont:= ATEditorScalePercents;
  end;

  if not AInc then
    if FOptScaleFont<=cMinScale then Exit;

  //NTop:= LineTop;
  FOptScaleFont:= FOptScaleFont+cStep*BoolToPlusMinusOne[AInc];
  //LineTop:= NTop;

  if AllowUpdate then
    Update;
end;

procedure TATSynEdit.BeginUpdate;
begin
  Inc(FPaintLocked);
  Invalidate;
end;

procedure TATSynEdit.EndUpdate;
begin
  Dec(FPaintLocked);
  if FPaintLocked<0 then
    FPaintLocked:= 0;
  if FPaintLocked=0 then
    Invalidate;
end;

function TATSynEdit.IsLocked: boolean;
begin
  Result:= FPaintLocked>0;
end;

function TATSynEdit.TextSelectedEx(ACaret: TATCaretItem): atString;
var
  X1, Y1, X2, Y2: integer;
  bSel: boolean;
begin
  Result:= '';
  ACaret.GetRange(X1, Y1, X2, Y2, bSel);
  if bSel then
    Result:= Strings.TextSubstring(X1, Y1, X2, Y2);
end;

function TATSynEdit.TextSelected: atString;
begin
  if Carets.Count>0 then
    Result:= TextSelectedEx(Carets[0])
  else
    Result:= '';
end;

function TATSynEdit.TextCurrentWord: atString;
var
  Str: atString;
  Caret: TATCaretItem;
  N1, N2: integer;
begin
  Result:= '';
  if Carets.Count=0 then Exit;
  Caret:= Carets[0];
  Str:= Strings.Lines[Caret.PosY];
  SFindWordBounds(Str, Caret.PosX, N1, N2, OptNonWordChars);
  if N2>N1 then
    Result:= Copy(Str, N1+1, N2-N1);
end;

function TATSynEdit.GetMouseNiceScroll: boolean;
begin
  Result:= Assigned(FTimerNiceScroll) and FTimerNiceScroll.Enabled;
end;

procedure TATSynEdit.SetEnabledSlowEvents(AValue: boolean);
var
  St: TATStrings;
begin
  St:= Strings;
  if not AValue then
  begin
    St.ClearUndo(true);
    St.EnabledChangeEvents:= false;
    if Carets.Count>0 then
    begin
      FLastLineOfSlowEvents:= Carets[0].FirstTouchedLine;
      if not St.IsIndexValid(FLastLineOfSlowEvents) then
        FLastLineOfSlowEvents:= -1;
    end;
  end
  else
  begin
    St.ClearUndo(false);
    St.EnabledChangeEvents:= true;
    if St.IsIndexValid(FLastLineOfSlowEvents) then
    begin
      St.DoEventLog(FLastLineOfSlowEvents);
      St.DoEventChange(cLineChangeEdited, FLastLineOfSlowEvents, 1);
      FLastLineOfSlowEvents:= -1;
    end;
  end;
end;

procedure TATSynEdit.SetMouseNiceScroll(AValue: boolean);
begin
  if AValue then
    InitTimerNiceScroll;
  if Assigned(FTimerNiceScroll) then
    FTimerNiceScroll.Enabled:= AValue;
  if not AValue then
    UpdateCursor;
  Invalidate;
end;

function TATSynEdit.GetEndOfFilePos: TPoint;
var
  St: TATStrings;
begin
  St:= Strings;
  if St.Count>0 then
  begin
    Result.Y:= St.Count-1;
    Result.X:= St.LinesLen[Result.Y];
    if St.LinesEnds[Result.Y]<>cEndNone then
      Inc(Result.X);
  end
  else
  begin
    Result.X:= 0;
    Result.Y:= 0;
  end;
end;


function TATSynEdit.DoCalcFoldProps(AWrapItemIndex: integer; out AProps: TATFoldBarProps): boolean;
var
  WrapItem: TATWrapItem;
  Rng: PATSynRange;
  Caret: TATCaretItem;
  NLineIndex: integer;
  NIndexOfCurrentRng, NIndexOfCaretRng: integer;
begin
  Result:= false;
  FillChar(AProps, SizeOf(AProps), 0);

  WrapItem:= FWrapInfo[AWrapItemIndex];
  NLineIndex:= WrapItem.NLineIndex;

  //find deepest range which includes caret pos
  NIndexOfCaretRng:= -1;
  if FOptGutterShowFoldLinesForCaret then
    if Carets.Count>0 then
    begin
      Caret:= Carets[0];
      if Strings.IsIndexValid(Caret.PosY) then
        NIndexOfCaretRng:= FFold.FindDeepestRangeContainingLine(Caret.PosY, false, FFoldIconForMinimalRange);
    end;

  NIndexOfCurrentRng:= FFold.FindDeepestRangeContainingLine(NLineIndex, false, FFoldIconForMinimalRange);
  if NIndexOfCurrentRng<0 then exit;
  AProps.HiliteLines:= NIndexOfCurrentRng=NIndexOfCaretRng;

  Rng:= Fold.ItemPtr(NIndexOfCurrentRng);

  if Rng^.Y<NLineIndex then
    AProps.IsLineUp:= true;

  if Rng^.Y2>NLineIndex then
    AProps.IsLineDown:= true;

  if Rng^.Y=NLineIndex then
  begin
    AProps.State:= cFoldbarBegin;
    //don't override found [+], 2 blocks can start at same pos
    if not AProps.IsPlus then
      AProps.IsPlus:= Rng^.Folded;
  end;

  if Rng^.Y2=NLineIndex then
    if AProps.State<>cFoldbarBegin then
      AProps.State:= cFoldbarEnd;

  //correct state for wrapped line
  if AProps.State=cFoldbarBegin then
    if not WrapItem.bInitial then
      AProps.State:= cFoldbarMiddle;

  //correct state for wrapped line
  if AProps.State=cFoldbarEnd then
    if WrapItem.NFinal=cWrapItemMiddle then
      AProps.State:= cFoldbarMiddle;

  Result:= true;
end;

procedure TATSynEdit.DoPaintGutterFolding(C: TCanvas;
  AWrapItemIndex: integer;
  ACoordX1, ACoordX2, ACoordY1, ACoordY2: integer);
var
  CoordXCenter, CoordYCenter: integer;
  Props: TATFoldBarProps;
  //
  procedure DrawUp; inline;
  begin
    if Props.IsLineUp then
      CanvasLineVert(C,
        CoordXCenter,
        ACoordY1,
        CoordYCenter
        );
  end;
  procedure DrawDown; inline;
  begin
    if Props.IsLineDown then
      CanvasLineVert(C,
        CoordXCenter,
        CoordYCenter,
        ACoordY2+1
        );
  end;
  //
var
  NColorLine, NColorPlus: TColor;
  NCacheIndex: integer;
  bOk: boolean;
begin
  if not FOptGutterShowFoldAlways then
    if not FCursorOnGutter then exit;

  //FFoldbarCache removes flickering of the folding-bar on fast editing
  if FFoldCacheEnabled then
  begin
    NCacheIndex:= AWrapItemIndex-FFoldbarCacheStart;
    if not ((NCacheIndex>=0) and (NCacheIndex<=High(FFoldbarCache))) then exit;

    if not FAdapterIsDataReady then
      Props:= FFoldbarCache[NCacheIndex]
    else
    begin
      bOk:= DoCalcFoldProps(AWrapItemIndex, Props);
      FFoldbarCache[NCacheIndex]:= Props;
      if not bOk then exit;
    end;
  end
  else
  begin
    bOk:= DoCalcFoldProps(AWrapItemIndex, Props);
    if not bOk then exit;
  end;

  if Props.HiliteLines then
    NColorPlus:= Colors.GutterFoldLine2
  else
    NColorPlus:= Colors.GutterFoldLine;

  if FOptGutterShowFoldLines then
    NColorLine:= NColorPlus
  else
    NColorLine:= FColorGutterFoldBG;
  C.Pen.Color:= NColorLine;

  CoordXCenter:= (ACoordX1+ACoordX2) div 2;
  CoordYCenter:= (ACoordY1+ACoordY2) div 2;

  case Props.State of
    cFoldbarBegin:
      begin
        if FOptGutterShowFoldLinesAll then
        begin
          DrawUp;
          DrawDown;
        end;

        if not Props.IsPlus then
          DrawDown;

        DoPaintGutterPlusMinus(C,
          CoordXCenter, CoordYCenter, Props.IsPlus, NColorPlus);
      end;
    cFoldbarEnd:
      begin
        if FOptGutterShowFoldLinesAll then
        begin
          DrawUp;
          DrawDown;
        end;

        Dec(ACoordY2, ATEditorOptions.SizeGutterFoldLineDx);
        CanvasLineVert(C,
          CoordXCenter,
          ACoordY1,
          ACoordY2
          );
        CanvasLineHorz(C,
          CoordXCenter,
          ACoordY2,
          CoordXCenter + ATEditorScale(FOptGutterPlusSize)
          );
      end;
    cFoldbarMiddle:
      begin
        CanvasLineVert(C,
          CoordXCenter,
          ACoordY1,
          ACoordY2
          );
      end;
    else
      begin
        DrawUp;
        DrawDown;
      end;
  end;
end;

procedure TATSynEdit.DoPaintGutterDecor(C: TCanvas; ALine: integer; const ARect: TRect);
var
  Decor: TATGutterDecorItem;
  Style, StylePrev: TFontStyles;
  Ext: TSize;
  N, NText: integer;
begin
  if FGutterDecor=nil then exit;
  N:= FGutterDecor.Find(ALine);
  if N<0 then exit;
  Decor:= FGutterDecor[N];

  //paint decor text
  if Decor.Data.Text<>'' then
  begin
    C.Font.Color:= Decor.Data.TextColor;
    Style:= [];
    if Decor.Data.TextBold then
      Include(Style, fsBold);
    if Decor.Data.TextItalic then
      Include(Style, fsItalic);
    StylePrev:= C.Font.Style;
    C.Font.Style:= Style;

    Ext:= C.TextExtent(Decor.Data.Text);
    C.Brush.Color:= FColorGutterBG;

    case FGutterDecorAlignment of
      taCenter:
        NText:= (ARect.Left+ARect.Right-Ext.cx) div 2;
      taLeftJustify:
        NText:= ARect.Left;
      taRightJustify:
        NText:= ARect.Right-Ext.cx;
    end;

    C.Brush.Style:= bsClear;
    C.TextOut(
      NText,
      (ARect.Top+ARect.Bottom-Ext.cy) div 2,
      Decor.Data.Text
      );
    C.Font.Style:= StylePrev;
  end
  else
  //paint decor icon
  if Assigned(FGutterDecorImages) then
  begin
    N:= Decor.Data.ImageIndex;
    if (N>=0) and (N<FGutterDecorImages.Count) then
      FGutterDecorImages.Draw(C,
        (ARect.Left+ARect.Right-FGutterDecorImages.Width) div 2,
        (ARect.Top+ARect.Bottom-FGutterDecorImages.Height) div 2,
        N
        );
  end;
end;

procedure TATSynEdit.DoPaintTextHintTo(C: TCanvas);
var
  Size: TSize;
  Pos: TPoint;
begin
  C.Brush.Color:= FColorBG;
  C.Font.Color:= Colors.TextHintFont;
  C.Font.Style:= FTextHintFontStyle;

  Size:= C.TextExtent(FTextHint);
  if FTextHintCenter then
  begin
    Pos:= CenterPoint(FRectMain);
    Dec(Pos.X, Size.cx div 2);
    Dec(Pos.Y, Size.cy div 2);
  end
  else
  begin
    Pos:= FTextOffset;
  end;

  C.Brush.Style:= bsClear;
  C.TextOut(Pos.X, Pos.Y, FTextHint);
end;


procedure TATSynEdit.CMWantSpecialKey(var Message: TCMWantSpecialKey);
begin
  case Message.CharCode of
    VK_RETURN: Message.Result:= Ord(WantReturns);
    VK_TAB: Message.Result:= Ord(WantTabs);
    VK_LEFT,
    VK_RIGHT,
    VK_UP,
    VK_DOWN: Message.Result:= 1;
    else inherited;
  end;
end;

{$ifdef GTK2_IME_CODE}
// fcitx IM
procedure TATSynEdit.WM_GTK_IM_COMPOSITION(var Message: TLMessage);
var
  buffer: atString;
  len: Integer;
  bOverwrite, bSelect: Boolean;
  Caret: TATCaretItem;
begin
  //exit;-
  //exiting, currently it breaks CudaText issue #3442

  if (not ModeReadOnly) then
  begin
    // set candidate position
    if (Message.WParam and (GTK_IM_FLAG_START or GTK_IM_FLAG_PREEDIT))<>0 then
    begin
      if Carets.Count>0 then
      begin
        Caret:= Carets[0];
        IM_Context_Set_Cursor_Pos(Caret.CoordX,Caret.CoordY+TextCharSize.Y);
      end;
    end;
    // valid string at composition & commit
    if Message.WParam and (GTK_IM_FLAG_COMMIT or GTK_IM_FLAG_PREEDIT)<>0 then
    begin
	  if Message.WParam and GTK_IM_FLAG_REPLACE=0 then
        FIMSelText:=TextSelected;
      // insert preedit or commit string
      buffer:=UTF8Decode(pchar(Message.LParam));
      len:=Length(buffer);
      bOverwrite:=ModeOverwrite and (Length(FIMSelText)=0);
      bSelect:=len>0;
      // commit
      if len>0 then
      begin
        if Message.WParam and GTK_IM_FLAG_COMMIT<>0 then
        begin
          TextInsertAtCarets(buffer, False, bOverwrite, False);
          FIMSelText:='';
        end else
          TextInsertAtCarets(buffer, False, False, bSelect);
      end else
        // fix for IBUS IM.
        if Message.WParam and GTK_IM_FLAG_REPLACE<>0 then
          TextInsertAtCarets('',False, bOverwrite, False);
    end;
    // end composition
    // To Do : skip insert saved selection after commit with ibus.
    if (Message.WParam and GTK_IM_FLAG_END<>0) and (FIMSelText<>'') then
      TextInsertAtCarets(FIMSelText, False, False, False);
  end;
end;
{$endif}

procedure TATSynEdit.DoPaintStaple(C: TCanvas; const R: TRect; AColor: TColor);
var
  X1, Y1, X2, Y2: integer;
begin
  if FOptStapleStyle=cLineStyleNone then Exit;

  if FOptStapleEdge1=cStapleEdgeAngle then
    CanvasLineEx(C, AColor, FOptStapleStyle, R.Left, R.Top, R.Right, R.Top, false);

  X1:= R.Left;
  Y1:= R.Top;
  X2:= R.Left;
  Y2:= R.Bottom;
  if FOptStapleEdge1=cStapleEdgeNone then
    Inc(Y1, FCharSize.Y);
  if FOptStapleEdge2=cStapleEdgeNone then
    Dec(Y2, FCharSize.Y);

  CanvasLineEx(C, AColor, FOptStapleStyle, X1, Y1, X2, Y2, false);

  if FOptStapleEdge2=cStapleEdgeAngle then
    CanvasLineEx(C, AColor, FOptStapleStyle, R.Left, R.Bottom, R.Right, R.Bottom, true);
end;

procedure TATSynEdit.DoPaintStaples(C: TCanvas;
  const ARect: TRect;
  const ACharSize: TATEditorCharSize;
  const AScrollHorz: TATEditorScrollInfo);
var
  St: TATStrings;
  nLineFrom, nLineTo, nRangeDeepest, nMaxHeight: integer;
  nIndent, nIndentBegin, nIndentEnd: integer;
  Indexes: TATIntArray;
  Range: PATSynRange;
  P1, P2: TPoint;
  RSt: TRect;
  NColor, NColorNormal, NColorActive: TColor;
  i: integer;
begin
  if FOptStapleStyle=cLineStyleNone then Exit;
  if not FFold.HasStaples then Exit;

  St:= Strings;
  nLineFrom:= LineTop;
  nLineTo:= LineBottom;
  nMaxHeight:= FRectMain.Height+2;
  nRangeDeepest:= -1;

  Indexes:= FFold.FindRangesWithStaples(nLineFrom, nLineTo);

  //currently find active range for first caret only
  if FOptStapleHiliteActive then
    if Carets.Count>0 then
      nRangeDeepest:= FFold.FindDeepestRangeContainingLine(Carets[0].PosY, true, FFoldIconForMinimalRange);

  NColorNormal:= Colors.BlockStaple;
  NColorActive:= Colors.BlockStapleForCaret;
  if NColorActive=clNone then
    NColorActive:= ColorBlend(NColorNormal, FColorFont, FOptStapleHiliteActiveAlpha);

  for i:= 0 to High(Indexes) do
  begin
    Range:= Fold.ItemPtr(Indexes[i]);
    {
    //FindRangesWithStaples does it:
    if not Range^.Staple then Continue;
    if Range^.Folded then Continue;
    }

    if not St.IsIndexValid(Range^.Y) then Continue;
    if not St.IsIndexValid(Range^.Y2) then Continue;

    if IsLineFolded(Range^.Y, true) then Continue;
    if IsLineFolded(Range^.Y2, true) then Continue;

    P1:= CaretPosToClientPos(Point(0, Range^.Y));
    P2:= CaretPosToClientPos(Point(0, Range^.Y2));
    if (P1.Y<FRectMain.Top) and (Range^.Y>=nLineFrom) then Continue;
    if (P2.Y<FRectMain.Top) and (Range^.Y2>=nLineFrom) then Continue;

    nIndentBegin:= FTabHelper.GetIndentExpanded(Range^.Y, St.Lines[Range^.Y]);

    if FOptStapleIndentConsidersEnd then
    begin
      nIndentEnd:= FTabHelper.GetIndentExpanded(Range^.Y2, St.Lines[Range^.Y2]);
      nIndent:= Min(nIndentBegin, nIndentEnd);
    end
    else
      nIndent:= nIndentBegin;

    Inc(P1.X, nIndent*ACharSize.XScaled div ATEditorCharXScale);
    Inc(P2.X, nIndent*ACharSize.XScaled div ATEditorCharXScale);

    RSt.Left:= P1.X + FOptStapleIndent;
    RSt.Top:= P1.Y;
    RSt.Right:= RSt.Left+ (ACharSize.XScaled * FOptStapleWidthPercent div ATEditorCharXScale div 100);
    RSt.Bottom:= P2.Y + ACharSize.Y-1;

    if (RSt.Left>=ARect.Left) and
      (RSt.Left<ARect.Right) then
    begin
      //don't use too big coords, some OS'es truncate lines painted with big coords
      RSt.Top:= Max(RSt.Top, -2);
      RSt.Bottom:= Min(RSt.Bottom, nMaxHeight);

      if Indexes[i]=nRangeDeepest then
        NColor:= NColorActive
      else
        NColor:= NColorNormal;

      if Assigned(FOnCalcStaple) then
        FOnCalcStaple(Self, Range^.Y, NIndent, NColor);

      DoPaintStaple(C, RSt, NColor);
    end;
  end;
end;


function TATSynEdit.IsCharWord(ch: Widechar): boolean;
begin
  Result:= ATStringProc.IsCharWord(ch, OptNonWordChars);
end;

function TATSynEdit.GetGaps: TATGaps;
begin
  Result:= Strings.Gaps;
end;

function TATSynEdit.GetLastCommandChangedLines: integer;
begin
  Result:= Strings.LastCommandChangedLines;
end;

procedure TATSynEdit.SetLastCommandChangedLines(AValue: integer);
begin
  Strings.LastCommandChangedLines:= AValue;
end;

procedure TATSynEdit.DoPaintMarkersTo(C: TCanvas);
var
  Mark: TATMarkerItem;
  Pnt: TPoint;
  NMarkSize, NLineW: integer;
  iMark: integer;
  R: TRect;
begin
  if FMarkers=nil then exit;

  NMarkSize:= Max(1, FCharSize.Y * FOptMarkersSize div (100*2));
  NLineW:= NMarkSize;

  for iMark:= 0 to FMarkers.Count-1 do
  begin
    Mark:= FMarkers[iMark];
    if Mark.CoordX<0 then Continue;
    if Mark.CoordY<0 then Continue;

    Pnt.X:= Mark.CoordX;
    Pnt.Y:= Mark.CoordY+FCharSize.Y;

    if PtInRect(FRectMain, Pnt) then
      CanvasPaintTriangleUp(C, Colors.Markers, Pnt, NMarkSize);

    if (Mark.LineLen<>0) and (Mark.CoordY=Mark.CoordY2) then
    begin
      R.Left:= Min(Pnt.X, Mark.CoordX2);
      R.Right:= Max(Pnt.X, Mark.CoordX2)+1;
      R.Bottom:= Pnt.Y+NMarkSize+1;
      R.Top:= R.Bottom-NLineW;

      //avoid painting part of the line over minimap/gutter
      R.Left:= Max(R.Left, FRectMain.Left);
      R.Right:= Min(R.Right, FRectMain.Right);

      C.Brush.Color:= Colors.Markers;
      C.FillRect(R);
    end;
  end;
end;

procedure TATSynEdit.DoPaintGutterPlusMinus(C: TCanvas; AX, AY: integer;
  APlus: boolean; ALineColor: TColor);
begin
  Inc(AY, FTextOffsetFromTop);

  case OptGutterIcons of
    cGutterIconsPlusMinus:
      begin
        CanvasPaintPlusMinus(C,
          ALineColor,
          FColorGutterFoldBG,
          Point(AX, AY),
          ATEditorScale(FOptGutterPlusSize),
          APlus);
      end;
    cGutterIconsTriangles:
      begin
        if APlus then
          CanvasPaintTriangleRight(C,
            ALineColor,
            Point(AX, AY),
            ATEditorScale(FOptGutterPlusSize div 2))
        else
          CanvasPaintTriangleDown(C,
            ALineColor,
            Point(AX, AY),
            ATEditorScale(FOptGutterPlusSize div 2))
      end;
  end;
end;


procedure TATSynEdit.DoSetMarkedLines(ALine1, ALine2: integer);
begin
  InitMarkedRange;
  FMarkedRange.Clear;
  if (ALine1>=0) and (ALine2>=ALine1) then
  begin
    FMarkedRange.Add(0, ALine1);
    FMarkedRange.Add(0, ALine2);
  end;
end;

procedure TATSynEdit.DoGetMarkedLines(out ALine1, ALine2: integer);
begin
  ALine1:= -1;
  ALine2:= -1;
  if Assigned(FMarkedRange) then
    if FMarkedRange.Count=2 then
    begin
      ALine1:= FMarkedRange.Items[0].PosY;
      ALine2:= FMarkedRange.Items[1].PosY;
    end;
end;


procedure TATSynEdit.UpdateLinksAttribs;
var
  St: TATStrings;
  AtrObj: TATLinePartClass;
  NLineStart, NLineEnd, NLineLen: integer;
  MatchPos, MatchLen, iLine: integer;
  LinkArrayPtr: PATLinkArray;
  LinkArray: TATLinkArray;
  LinkIndex: integer;
  NRegexRuns: integer;
begin
  if ModeOneLine then
    exit;

  if not OptShowURLs then
  begin
    if Assigned(FAttribs) then
      FAttribs.DeleteWithTag(ATEditorOptions.UrlMarkerTag);
    exit;
  end;

  St:= Strings;
  NLineStart:= LineTop;
  NLineEnd:= NLineStart+GetVisibleLines;

  InitAttribs;
  FAttribs.DeleteWithTag(ATEditorOptions.UrlMarkerTag);

  FLinkCache.DeleteDataOutOfRange(NLineStart, NLineEnd);
  NRegexRuns:= 0;

  for iLine:= NLineStart to NLineEnd do
  begin
    if not St.IsIndexValid(iLine) then Break;
    NLineLen:= St.LinesLen[iLine];

    if NLineLen<FOptMinLineLenToCalcURL then Continue;
    if NLineLen>FOptMaxLineLenToCalcURL then Continue;

    LinkArrayPtr:= FLinkCache.FindData(iLine);
    if LinkArrayPtr=nil then
    begin
      Assert(Assigned(FRegexLinks), 'FRegexLinks not inited');
      FRegexLinks.InputString:= St.Lines[iLine];

      LinkIndex:= 0;
      FillChar(LinkArray, SizeOf(LinkArray), 0);
      MatchPos:= 0;
      MatchLen:= 0;
      Inc(NRegexRuns);

      while FRegexLinks.ExecPos(MatchPos+MatchLen+1) do
      begin
        MatchPos:= FRegexLinks.MatchPos[0];
        MatchLen:= FRegexLinks.MatchLen[0];
        LinkArray[LinkIndex].NFrom:= MatchPos;
        LinkArray[LinkIndex].NLen:= MatchLen;
        Inc(LinkIndex);
        if LinkIndex>High(LinkArray) then Break;
        Inc(NRegexRuns);
      end;

      FLinkCache.AddData(iLine, LinkArray);
      LinkArrayPtr:= @LinkArray;
    end;

    for LinkIndex:= 0 to High(LinkArray) do
    begin
      MatchLen:= LinkArrayPtr^[LinkIndex].NLen;
      if MatchLen=0 then Break;
      MatchPos:= LinkArrayPtr^[LinkIndex].NFrom;

      AtrObj:= TATLinePartClass.Create;
      AtrObj.Data.ColorFont:= Colors.Links;
      AtrObj.Data.ColorBG:= clNone;
      AtrObj.Data.ColorBorder:= Colors.Links;
      AtrObj.Data.BorderDown:= cLineStyleSolid;

      FAttribs.Add(
        MatchPos-1,
        iLine,
        ATEditorOptions.UrlMarkerTag,
        MatchLen,
        0,
        AtrObj
        );
    end;
  end;

  ////debug
  //Application.MainForm.Caption:= 'runs:'+IntToStr(NRegexRuns)+' '+FLinkCache.DebugText;
end;


function TATSynEdit.DoGetLinkAtPos(AX, AY: integer): atString;
var
  MatchPos, MatchLen: integer;
begin
  Result:= '';
  if not Strings.IsIndexValid(AY) then exit;

  Assert(Assigned(FRegexLinks), 'FRegexLinks not inited');
  FRegexLinks.InputString:= Strings.Lines[AY];
  MatchPos:= 0;
  MatchLen:= 0;

  while FRegexLinks.ExecPos(MatchPos+MatchLen+1) do
  begin
    MatchPos:= FRegexLinks.MatchPos[0]-1;
    MatchLen:= FRegexLinks.MatchLen[0];
    if MatchPos>AX then
      Break;
    if (MatchPos<=AX) and (MatchPos+MatchLen>AX) then
      exit(FRegexLinks.Match[0]);
  end;
end;


procedure TATSynEdit.DragOver(Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
var
  Cur: TCursor;
  EdOther: TATSynEdit;
begin
  Sleep(30);

  if (Source is TATSynEdit) and (Source<>Self) then
  begin
    EdOther:= TATSynEdit(Source);
    if EdOther.OptMouseDragDrop then
    begin
      //for drag to another control, we reverse Ctrl-pressed state
      if GetActualDragDropIsCopying then
        Cur:= crDrag
      else
        Cur:= crMultiDrag;
      EdOther.DragCursor:= Cur;
      EdOther.Cursor:= Cur;
    end;
  end;

  Accept:=
    FOptMouseDragDrop and
    (not ModeReadOnly) and
    (not ModeOneLine) and
    (Source is TATSynEdit) and
    (TATSynEdit(Source).Carets.Count>0) and
    (TATSynEdit(Source).Carets[0].IsSelection);
end;

procedure TATSynEdit.DragDrop(Source: TObject; X, Y: Integer);
var
  SText: atString;
  Pnt: TPoint;
  Details: TATEditorPosDetails;
begin
  if not (Source is TATSynEdit) then exit;

  //this check means: method runs only on drop from another editor
  if (Source=Self) then exit;

  SText:= TATSynEdit(Source).TextSelected;
  if SText='' then exit;

  Pnt:= ClientPosToCaretPos(Point(X, Y), Details);
  if Strings.IsIndexValid(Pnt.Y) then
  begin
    DoCaretSingle(Pnt.X, Pnt.Y);
    DoCommand(cCommand_TextInsert, cInvokeInternal, SText);
    if ATEditorOptions.MouseDragDropFocusesTargetEditor then
      SetFocus;

    //Ctrl is pressed: delete block from src
    //note: it's opposite to the drag-drop in the single document
    if GetActualDragDropIsCopying then
      TATSynEdit(Source).DoCommand(cCommand_TextDeleteSelection, cInvokeInternal);
  end;
end;

procedure TATSynEdit.OnNewScrollbarVertChanged(Sender: TObject);
var
  Msg: TLMVScroll;
  NPos: Int64;
begin
  if FScrollbarLock then exit;

  if FMicromapOnScrollbar then
  begin
    NPos:= FScrollbarVert.Position
           div FScrollbarVert.SmallChange; //this supports OptScrollSmooth
    DoUnfoldLine(NPos);
    LineTop:= NPos;
  end
  else
  begin
    FillChar(Msg{%H-}, SizeOf(Msg), 0);
    Msg.ScrollCode:= SB_THUMBPOSITION;
    Msg.Pos:= FScrollbarVert.Position;
    WMVScroll(Msg);
  end;

  //show scroll hint
  DoHintShow;
end;

procedure TATSynEdit.OnNewScrollbarHorzChanged(Sender: TObject);
var
  Msg: TLMHScroll;
begin
  if FScrollbarLock then exit;
  FillChar({%H-}Msg, SizeOf(Msg), 0);
  Msg.ScrollCode:= SB_THUMBPOSITION;
  Msg.Pos:= FScrollbarHorz.Position;
  WMHScroll(Msg);
end;

procedure TATSynEdit.TimerIdleTick(Sender: TObject);
begin
  FTimerIdle.Enabled:= false;
  if Assigned(FOnIdle) then
    FOnIdle(Self);
  if Assigned(FAdapterHilite) then
    FAdapterHilite.OnEditorIdle(Self);
end;

procedure TATSynEdit.DoStringsOnChangeEx(Sender: TObject; AChange: TATLineChangeKind; ALine, AItemCount: integer);
//we are called inside BeginEditing/EndEditing - just remember top edited line
var
  St: TATStrings;
begin
  St:= Strings;
  if St.EditingActive then
  begin
  end
  else
    FlushEditingChangeEx(AChange, ALine, AItemCount);
end;

procedure TATSynEdit.DoStringsOnChangeLog(Sender: TObject; ALine: integer);
var
  St: TATStrings;
begin
  St:= Strings;
  if St.EditingActive then
  begin
  end
  else
    FlushEditingChangeLog(ALine);
end;

procedure TATSynEdit.FlushEditingChangeEx(AChange: TATLineChangeKind; ALine, AItemCount: integer);
begin
  Fold.Update(AChange, ALine, AItemCount);

  if Assigned(FAdapterHilite) then
    FAdapterHilite.OnEditorChangeEx(Self, AChange, ALine, AItemCount);
end;

procedure TATSynEdit.FlushEditingChangeLog(ALine: integer);
begin
  if Assigned(FOnChangeLog) then
    FOnChangeLog(Self, ALine);
end;

procedure TATSynEdit.StartTimerDelayedParsing;
begin
  FTimerDelayedParsing.Enabled:= false;
  FTimerDelayedParsing.Enabled:= FTimersEnabled;

  if Carets.Count>0 then
    FLastCommandDelayedParsingOnLine:= Min(
      FLastCommandDelayedParsingOnLine,
      Max(0, Carets[0].FirstTouchedLine-1)
      );
end;

procedure TATSynEdit.TimerDelayedParsingTick(Sender: TObject);
//to solve CudaText issue #3403
//const
//  c: integer=0;
begin
  FTimerDelayedParsing.Enabled:= false;
  if Assigned(FOnChangeLog) then
    FOnChangeLog(Self, FLastCommandDelayedParsingOnLine);
  {
  //debug
  inc(c);
  Application.MainForm.Caption:= 'delayed parse: '+inttostr(c)+': '+inttostr(FLastCommandDelayedParsingOnLine);
  }
  FLastCommandDelayedParsingOnLine:= MaxInt;
end;

procedure TATSynEdit.TimerFlickerTick(Sender: TObject);
begin
  FTimerFlicker.Enabled:= false;
  Include(FPaintFlags, cIntFlagBitmap);
  inherited Invalidate;
end;

procedure TATSynEdit.DoStringsOnProgress(Sender: TObject);
begin
  Invalidate;
  Application.ProcessMessages;
  //auto paints "wait... N%"
end;

procedure TATSynEdit.DoHotspotsExit;
begin
  if FLastHotspot>=0 then
  begin
    if Assigned(FOnHotspotExit) then
      FOnHotspotExit(Self, FLastHotspot);
    FLastHotspot:= -1;
  end;
end;


procedure TATSynEdit.DoPaintTextFragment(C: TCanvas;
  const ARect: TRect;
  ALineFrom, ALineTo: integer;
  AConsiderWrapInfo: boolean;
  AColorBG, AColorBorder: TColor);
var
  St: TATStrings;
  NOutputStrWidth: Int64;
  NLine, NWrapIndex: integer;
  NVisibleColumns: integer;
  NColorAfter: TColor;
  WrapItem: TATWrapItem;
  TextOutProps: TATCanvasTextOutProps;
  SText: UnicodeString;
begin
  St:= Strings;
  C.Brush.Color:= AColorBG;
  C.FillRect(ARect);

  FillChar(TextOutProps{%H-}, SizeOf(TextOutProps), 0);

  TextOutProps.Editor:= Self;
  TextOutProps.TabHelper:= FTabHelper;
  TextOutProps.CharSize:= FCharSize;
  TextOutProps.CharsSkipped:= 0;
  TextOutProps.DrawEvent:= nil;
  TextOutProps.ControlWidth:= ARect.Width;
  TextOutProps.TextOffsetFromLine:= FTextOffsetFromTop;

  TextOutProps.ShowUnprinted:= FUnprintedVisible and FUnprintedSpaces;
  TextOutProps.ShowUnprintedSpacesTrailing:= FUnprintedSpacesTrailing;
  TextOutProps.ShowUnprintedSpacesBothEnds:= FUnprintedSpacesBothEnds;
  TextOutProps.ShowUnprintedSpacesOnlyInSelection:= FUnprintedSpacesOnlyInSelection and TempSel_IsSelection;
  TextOutProps.ShowUnprintedSpacesAlsoInSelection:= not FUnprintedSpacesOnlyInSelection and FUnprintedSpacesAlsoInSelection and TempSel_IsSelection;
  TextOutProps.DetectIsPosSelected:= @IsPosSelected;

  TextOutProps.ShowFontLigatures:= FOptShowFontLigatures;
  TextOutProps.ColorNormalFont:= Colors.TextFont;
  TextOutProps.ColorUnprintedFont:= Colors.UnprintedFont;
  TextOutProps.ColorUnprintedHexFont:= Colors.UnprintedHexFont;

  TextOutProps.FontNormal_Name:= Font.Name;
  TextOutProps.FontNormal_Size:= DoScaleFont(Font.Size);

  TextOutProps.FontItalic_Name:= FontItalic.Name;
  TextOutProps.FontItalic_Size:= DoScaleFont(FontItalic.Size);

  TextOutProps.FontBold_Name:= FontBold.Name;
  TextOutProps.FontBold_Size:= DoScaleFont(FontBold.Size);

  TextOutProps.FontBoldItalic_Name:= FontBoldItalic.Name;
  TextOutProps.FontBoldItalic_Size:= DoScaleFont(FontBoldItalic.Size);

  if AConsiderWrapInfo then
    NWrapIndex:= WrapInfo.FindIndexOfCaretPos(Point(0, ALineFrom));

  NVisibleColumns:= GetVisibleColumns;

  for NLine:= ALineFrom to ALineTo do
  begin
    if not St.IsIndexValid(NLine) then Break;
    NColorAfter:= clNone;
    if AConsiderWrapInfo then
    begin
      if NWrapIndex<0 then Break;
      WrapItem:= WrapInfo[NWrapIndex];
      Inc(NWrapIndex);
    end
    else
    begin
      FillChar(WrapItem, SizeOf(WrapItem), 0);
      WrapItem.NLineIndex:= NLine;
      WrapItem.NCharIndex:= 1;
      WrapItem.NLength:= St.LinesLen[NLine];
    end;

    DoCalcLineHilite(
      WrapItem,
      FParts{%H-},
      0, ATEditorOptions.MaxCharsForOutput,
      AColorBG,
      false,
      NColorAfter,
      true);

    SText:= St.LineSub(
        WrapItem.NLineIndex,
        WrapItem.NCharIndex,
        NVisibleColumns);

    if FOptMaskCharUsed then
      SText:= StringOfCharW(FOptMaskChar, Length(SText));

    TextOutProps.HasAsciiNoTabs:= St.LinesHasAsciiNoTabs[WrapItem.NLineIndex];
    TextOutProps.SuperFast:= false;
    TextOutProps.LineIndex:= WrapItem.NLineIndex;
    TextOutProps.CharIndexInLine:= WrapItem.NCharIndex;
    CanvasTextOut(C,
      ATEditorOptions.SizeIndentTooltipX + WrapItem.NIndent*FCharSize.XScaled div ATEditorCharXScale,
      ATEditorOptions.SizeIndentTooltipY + FCharSize.Y*(NLine-ALineFrom),
      SText,
      @FParts,
      NOutputStrWidth,
      TextOutProps
      )
   end;

  C.Brush.Color:= AColorBorder;
  C.FrameRect(ARect);
end;


procedure TATSynEdit.DoPaintMinimapTooltip(C: TCanvas);
var
  C_Bmp: TCanvas;
  RectAll: TRect;
  Pnt: TPoint;
  NWrapIndex, NLineCenter, NLineTop, NLineBottom: integer;
  NPanelLeft, NPanelTop, NPanelWidth, NPanelHeight: integer;
begin
  Pnt:= ScreenToClient(Mouse.CursorPos);

  NPanelWidth:= FRectMain.Width * FMinimapTooltipWidthPercents div 100;
  if FMinimapAtLeft then
    NPanelLeft:= FRectMinimap.Right + 1
  else
    NPanelLeft:= FRectMinimap.Left - NPanelWidth - 1;
  NPanelHeight:= FMinimapTooltipLinesCount*FCharSize.Y + 2;
  NPanelTop:= Max(0, Min(ClientHeight-NPanelHeight,
    Pnt.Y - FCharSize.Y*FMinimapTooltipLinesCount div 2 ));

  if FMinimapTooltipBitmap=nil then
    FMinimapTooltipBitmap:= TBitmap.Create;
  FMinimapTooltipBitmap.SetSize(NPanelWidth, NPanelHeight);

  RectAll:= Rect(0, 0, NPanelWidth, NPanelHeight);
  C_Bmp:= FMinimapTooltipBitmap.Canvas;
  C_Bmp.Pen.Color:= Colors.MinimapTooltipBorder;
  C_Bmp.Brush.Color:= Colors.MinimapTooltipBG;
  C_Bmp.Rectangle(RectAll);

  NWrapIndex:= GetMinimap_ClickedPosToWrapIndex(Pnt.Y);
  if NWrapIndex<0 then exit;
  NLineCenter:= FWrapInfo[NWrapIndex].NLineIndex;
  NLineTop:= Max(0, NLineCenter - FMinimapTooltipLinesCount div 2);
  NLineBottom:= Min(NLineTop + FMinimapTooltipLinesCount-1, Strings.Count-1);

  DoPaintTextFragment(C_Bmp, RectAll,
    NLineTop,
    NLineBottom,
    true,
    Colors.MinimapTooltipBG,
    Colors.MinimapTooltipBorder
    );

  C.Draw(NPanelLeft, NPanelTop, FMinimapTooltipBitmap);
end;


procedure TATSynEdit.UpdateFoldedMarkTooltip;
begin
  if (not FFoldTooltipVisible) or not FFoldedMarkCurrent.IsInited then
  begin
    if Assigned(FFoldedMarkTooltip) then
      FFoldedMarkTooltip.Hide;
    exit
  end;

  InitFoldedMarkTooltip;

  FFoldedMarkTooltip.Width:= FRectMain.Width * FFoldTooltipWidthPercents div 100;
  FFoldedMarkTooltip.Height:= (FFoldedMarkCurrent.LineTo-FFoldedMarkCurrent.LineFrom+1) * FCharSize.Y + 2;
  FFoldedMarkTooltip.Left:= Min(
    FRectMain.Right - FFoldedMarkTooltip.Width - 1,
    FFoldedMarkCurrent.Coord.Left);
  FFoldedMarkTooltip.Top:=
    FFoldedMarkCurrent.Coord.Top + FCharSize.Y;

  //no space for on bottom? show on top
  if FFoldedMarkTooltip.Top + FFoldedMarkTooltip.Height > FRectMain.Bottom then
    if FFoldedMarkCurrent.Coord.Top - FFoldedMarkTooltip.Height >= FRectMain.Top then
      FFoldedMarkTooltip.Top:= FFoldedMarkCurrent.Coord.Top - FFoldedMarkTooltip.Height;

  FFoldedMarkTooltip.Show;
  FFoldedMarkTooltip.Invalidate;
end;

procedure TATSynEdit.FoldedMarkTooltipPaint(Sender: TObject);
begin
  if FFoldedMarkCurrent.IsInited then
    DoPaintTextFragment(
      FFoldedMarkTooltip.Canvas,
      Rect(0, 0, FFoldedMarkTooltip.Width, FFoldedMarkTooltip.Height),
      FFoldedMarkCurrent.LineFrom,
      FFoldedMarkCurrent.LineTo,
      false, //to paint fully folded lines, must be False
      Colors.MinimapTooltipBG,
      Colors.MinimapTooltipBorder
      );
end;

procedure TATSynEdit.FoldedMarkMouseEnter(Sender: TObject);
begin
  if Assigned(FFoldedMarkTooltip) then
    FFoldedMarkTooltip.Hide;
end;

function TATSynEdit.DoGetFoldedMarkLinesCount(ALine: integer): integer;
var
  St: TATStrings;
  i: integer;
begin
  Result:= 1;
  St:= Strings;
  for i:= ALine+1 to Min(ALine+FFoldTooltipLineCount-1, St.Count-1) do
    if St.LinesHidden[i, FEditorIndex] then
      Inc(Result)
    else
      Break;
end;


function TATSynEdit.DoGetGapRect(AIndex: integer; out ARect: TRect): boolean;
var
  GapItem: TATGapItem;
  Pnt: TPoint;
begin
  Result:= false;
  ARect:= Rect(0, 0, 0, 0);

  if not Gaps.IsIndexValid(AIndex) then exit;
  GapItem:= Gaps.Items[AIndex];
  Pnt:= CaretPosToClientPos(Point(0, GapItem.LineIndex+1));

  ARect.Left:= FRectMain.Left;
  ARect.Right:= FRectMain.Right;
  ARect.Top:= Pnt.Y - GapItem.Size;
  ARect.Bottom:= Pnt.Y;

  //gap can be scrolled away: return False
  if ARect.Bottom<=FRectMain.Top then exit;
  if ARect.Top>=FRectMain.Bottom then exit;

  Result:= true;
end;

procedure TATSynEdit.SetFontItalic(AValue: TFont);
begin
  FFontItalic.Assign(AValue);
end;

procedure TATSynEdit.SetFontBold(AValue: TFont);
begin
  FFontBold.Assign(AValue);
end;

procedure TATSynEdit.SetFontBoldItalic(AValue: TFont);
begin
  FFontBoldItalic.Assign(AValue);
end;

procedure TATSynEdit.UpdateTabHelper;
begin
  FTabHelper.TabSpaces:= OptTabSpaces;
  FTabHelper.TabSize:= OptTabSize;
  FTabHelper.IndentSize:= OptIndentSize;
  FTabHelper.SenderObj:= Self;
  FTabHelper.OnCalcTabSize:= FOnCalcTabSize;
  FTabHelper.OnCalcLineLen:= @DoCalcLineLen;
end;

procedure TATSynEdit.DoPaintTiming(C: TCanvas);
const
  cFontSize = 8;
  cFontColor = clRed;
  cBackColor = clCream;
  cMinEditorLines = 15;
var
  S: string;
begin
  if ModeOneLine then exit;
  if GetVisibleLines<cMinEditorLines then exit;

  C.Font.Name:= Font.Name;
  C.Font.Color:= cFontColor;
  C.Font.Size:= cFontSize;
  C.Brush.Color:= cBackColor;

  S:= Format('#%03d, %d ms', [FPaintCounter, FTickAll]);
  if FMinimapVisible then
    S+= Format(', mmap %d ms', [FTickMinimap]);
  CanvasTextOutSimplest(C, 1, Height - cFontSize * 18 div 10, S);
end;


function TATSynEdit.GetEncodingName: string;
var
  St: TATStrings;
begin
  St:= Strings;
  case St.Encoding of
    cEncAnsi:
      begin
        Result:= cEncConvNames[St.EncodingCodepage];
      end;
    cEncUTF8:
      begin
        if St.SaveSignUtf8 then
          Result:= cEncNameUtf8_WithBom
        else
          Result:= cEncNameUtf8_NoBom;
      end;
    cEncWideLE:
      begin
        if St.SaveSignWide then
          Result:= cEncNameUtf16LE_WithBom
        else
          Result:= cEncNameUtf16LE_NoBom;
      end;
    cEncWideBE:
      begin
        if St.SaveSignWide then
          Result:= cEncNameUtf16BE_WithBom
        else
          Result:= cEncNameUtf16BE_NoBom;
      end;
    cEnc32LE:
      begin
        if St.SaveSignWide then
          Result:= cEncNameUtf32LE_WithBom
        else
          Result:= cEncNameUtf32LE_NoBom;
      end;
    cEnc32BE:
      begin
        if St.SaveSignWide then
          Result:= cEncNameUtf32BE_WithBom
        else
          Result:= cEncNameUtf32BE_NoBom;
      end;
  end;
end;

procedure TATSynEdit.SetEncodingName(const AName: string);
var
  St: TATStrings;
begin
  if AName='' then exit;
  if SameText(AName, GetEncodingName) then exit;
  St:= Strings;

  if SameText(AName, cEncNameUtf8_WithBom) then begin St.Encoding:= cEncUTF8; St.SaveSignUtf8:= true; end else
  if SameText(AName, cEncNameUtf8_NoBom) then begin St.Encoding:= cEncUTF8; St.SaveSignUtf8:= false; end else
  if SameText(AName, cEncNameUtf16LE_WithBom) then begin St.Encoding:= cEncWideLE; St.SaveSignWide:= true; end else
  if SameText(AName, cEncNameUtf16LE_NoBom) then begin St.Encoding:= cEncWideLE; St.SaveSignWide:= false; end else
  if SameText(AName, cEncNameUtf16BE_WithBom) then begin St.Encoding:= cEncWideBE; St.SaveSignWide:= true; end else
  if SameText(AName, cEncNameUtf16BE_NoBom) then begin St.Encoding:= cEncWideBE; St.SaveSignWide:= false; end else
  if SameText(AName, cEncNameUtf32LE_WithBom) then begin St.Encoding:= cEnc32LE; St.SaveSignWide:= true; end else
  if SameText(AName, cEncNameUtf32LE_NoBom) then begin St.Encoding:= cEnc32LE; St.SaveSignWide:= false; end else
  if SameText(AName, cEncNameUtf32BE_WithBom) then begin St.Encoding:= cEnc32BE; St.SaveSignWide:= true; end else
  if SameText(AName, cEncNameUtf32BE_NoBom) then begin St.Encoding:= cEnc32BE; St.SaveSignWide:= false; end else
  begin
    St.Encoding:= cEncAnsi;
    St.EncodingCodepage:= EncConvFindEncoding(LowerCase(AName));
  end;
end;

procedure TATSynEdit.TextInsertAtCarets(const AText: atString; AKeepCaret,
  AOvrMode, ASelectThen: boolean);
var
  Res: TATCommandResults;
begin
  Res:= DoCommand_TextInsertAtCarets(AText, AKeepCaret, AOvrMode, ASelectThen, false);
  DoCommandResults(0, Res);
end;

procedure TATSynEdit.DoCaretsFixForSurrogatePairs(AMoveRight: boolean);
//this is used to prevert caret stopping
//a) inside surrogate pair (2 codes which make one glyph)
//b) on accent (combining) char; we skip _all_ chars (Unicode allows several accent chars)
var
  St: TATStrings;
  Caret: TATCaretItem;
  ch: WideChar;
  i: integer;
begin
  St:= Strings;
  for i:= 0 to Carets.Count-1 do
  begin
    Caret:= Carets[i];
    if Caret.PosX<=0 then Continue;
    if not St.IsIndexValid(Caret.PosY) then Continue;
    ch:= St.LineCharAt(Caret.PosY, Caret.PosX+1);
    if ch=#0 then Continue;

    if IsCharSurrogateLow(ch) then
    begin
      Caret.PosX:= Caret.PosX+BoolToPlusMinusOne[AMoveRight];
      Continue;
    end;

    while IsCharAccent(ch) do
    begin
      Caret.PosX:= Caret.PosX+BoolToPlusMinusOne[AMoveRight];
      ch:= St.LineCharAt(Caret.PosY, Caret.PosX+1);
    end;
  end;
end;

function TATSynEdit.RectMicromapMark(AColumn, ALineFrom, ALineTo: integer;
  AMapHeight, AMinMarkHeight: integer): TRect;
//to make things safe, don't pass the ARect, but only its height
begin
  if FMicromap.IsIndexValid(AColumn) then
  begin
    if ALineFrom>=0 then
      Result.Top:= Int64(ALineFrom) * AMapHeight div FMicromapScaleDiv
    else
      Result.Top:= 0;

    if ALineTo>=0 then
      Result.Bottom:= Max(Result.Top + AMinMarkHeight,
                          Int64(ALineTo+1) * AMapHeight div FMicromapScaleDiv)
    else
      Result.Bottom:= AMapHeight;

    with FMicromap.Columns[AColumn] do
    begin
      Result.Left:= NLeft;
      Result.Right:= NRight;
    end;
  end
  else
    Result:= cRectEmpty;
end;

procedure TATSynEdit.SetShowOsBarVert(AValue: boolean);
begin
  if FShowOsBarVert=AValue then Exit;
  FShowOsBarVert:= AValue;
  ShowScrollBar(Handle, SB_Vert, AValue);
end;

procedure TATSynEdit.SetShowOsBarHorz(AValue: boolean);
begin
  if FShowOsBarHorz=AValue then Exit;
  FShowOsBarHorz:= AValue;
  ShowScrollBar(Handle, SB_Horz, AValue);
end;

procedure TATSynEdit.InitFoldedMarkList;
begin
  if FFoldedMarkList=nil then
    FFoldedMarkList:= TATFoldedMarks.Create;
end;

procedure TATSynEdit.InitFoldedMarkTooltip;
begin
  if FFoldedMarkTooltip=nil then
  begin
    FFoldedMarkTooltip:= TPanel.Create(Self);
    FFoldedMarkTooltip.Hide;
    FFoldedMarkTooltip.Width:= 15;
    FFoldedMarkTooltip.Height:= 15;
    FFoldedMarkTooltip.Parent:= Self;
    FFoldedMarkTooltip.BorderStyle:= bsNone;
    FFoldedMarkTooltip.OnPaint:= @FoldedMarkTooltipPaint;
    FFoldedMarkTooltip.OnMouseEnter:=@FoldedMarkMouseEnter;
  end;
end;

procedure TATSynEdit.InitAttribs;
begin
  if FAttribs=nil then
  begin
    FAttribs:= TATMarkers.Create;
    FAttribs.Sorted:= true;
    FAttribs.Duplicates:= true; //CudaText plugins need it
  end;
end;

procedure TATSynEdit.InitMarkers;
begin
  if FMarkers=nil then
  begin
    FMarkers:= TATMarkers.Create;
    FMarkers.Sorted:= false;
  end;
end;

procedure TATSynEdit.InitHotspots;
begin
  if FHotspots=nil then
    FHotspots:= TATHotspots.Create;
end;

procedure TATSynEdit.InitDimRanges;
begin
  if FDimRanges=nil then
    FDimRanges:= TATDimRanges.Create;
end;

procedure TATSynEdit.InitGutterDecor;
begin
  if FGutterDecor=nil then
    FGutterDecor:= TATGutterDecor.Create;
end;

function TATSynEdit.GetAttribs: TATMarkers;
begin
  InitAttribs;
  Result:= FAttribs;
end;

function TATSynEdit.DoCalcLineLen(ALineIndex: integer): integer;
begin
  Result:= Strings.LinesLen[ALineIndex];
end;

function TATSynEdit.GetDimRanges: TATDimRanges;
begin
  InitDimRanges;
  Result:= FDimRanges;
end;

function TATSynEdit.GetHotspots: TATHotspots;
begin
  InitHotspots;
  Result:= FHotspots;
end;

function TATSynEdit.GetMarkers: TATMarkers;
begin
  InitMarkers;
  Result:= FMarkers;
end;

function TATSynEdit.GetGutterDecor: TATGutterDecor;
begin
  InitGutterDecor;
  Result:= FGutterDecor;
end;

procedure TATSynEdit.SetOptShowURLsRegex(const AValue: string);
begin
  if FOptShowURLsRegex=AValue then Exit;
  FOptShowURLsRegex:= AValue;
  UpdateLinksRegexObject;
end;

procedure TATSynEdit.InitMarkedRange;
begin
  if FMarkedRange=nil then
  begin
    FMarkedRange:= TATMarkers.Create;
    FMarkedRange.Sorted:= true;
  end;
end;

function TATSynEdit.DoScaleFont(AValue: integer): integer;
begin
  if FOptScaleFont>0 then
    Result:= AValue * FOptScaleFont div 100
  else
    Result:= ATEditorScaleFont(AValue);
end;

function TATSynEdit.UpdateLinksRegexObject: boolean;
begin
  Result:= false;

  if FRegexLinks=nil then
    FRegexLinks:= TRegExpr.Create;

  try
    //FRegexLinks.UseUnicodeWordDetection:= false; //faster for links
    FRegexLinks.ModifierS:= false;
    FRegexLinks.ModifierM:= false; //M not needed
    FRegexLinks.ModifierI:= false; //I not needed to find links
    FRegexLinks.Expression:= FOptShowURLsRegex{%H-};
    FRegexLinks.Compile;

    Result:= true;
  except
    exit;
  end;
end;


function TATSynEdit.GetFoldingAsString: string;
var
  L: TStringList;
  i: integer;
  R: PATSynRange;
begin
  Result:= '';
  L:= TStringList.Create;
  try
    L.LineBreak:= ',';
    for i:= 0 to Fold.Count-1 do
    begin
      R:= Fold.ItemPtr(i);
      if R^.Folded then
        L.Add(IntToStr(R^.Y));
    end;
    Result:= L.Text;
  finally
    L.Free;
  end;
end;

procedure TATSynEdit.SetFoldingAsString(const AValue: string);
var
  St: TATStrings;
  Sep: TATStringSeparator;
  NLineTop, NLine, NRange: integer;
  bChange: boolean;
begin
  DoCommand(cCommand_UnfoldAll, cInvokeInternal);
  NLineTop:= LineTop;
  bChange:= false;

  St:= Strings;
  Sep.Init(AValue);
  repeat
    if not Sep.GetItemInt(NLine, -1) then Break;

    if not St.IsIndexValid(NLine) then Continue;

    NRange:= Fold.FindRangeWithPlusAtLine(NLine);
    if NRange<0 then Continue;

    if not Fold.ItemPtr(NRange)^.Folded then
    begin
      bChange:= true;
      DoRangeFold(NRange);
    end;
  until false;

  if bChange then
  begin
    if FScrollHorz.NPos>0 then
    begin
      //fix changed horz scroll, CudaText issue #1439
      FScrollHorz.SetZero;

      //SetZero may scroll view out of caret
      DoGotoCaret(cEdgeTop);
    end;

    //keep LineTop! CudaText issue #3055
    LineTop:= NLineTop;

    Update;
  end;
end;

procedure TATSynEdit.UpdateAndWait(AUpdateWrapInfo: boolean; APause: integer);
begin
  Update(AUpdateWrapInfo);
  Paint;
  Application.ProcessMessages;
  Sleep(APause);
end;

function TATSynEdit.IsPosInVisibleArea(AX, AY: integer): boolean;
var
  Pnt: TPoint;
  NTop, NCount: integer;
begin
  NTop:= LineTop;
  if AY<NTop then
    exit(false);

  NCount:= Strings.Count;
  if NCount<=1 then
    exit(true);

  if OptWrapMode=cWrapOff then
  begin
    Result:= AY<=NTop+GetVisibleLines;
  end
  else
  begin
    if AY>LineBottom then
      exit(false);

    Pnt:= CaretPosToClientPos(Point(AX, AY));
    if Pnt.Y=-1 then
      exit(true);

    Result:= PtInRect(FRectMainVisible, Pnt);
  end;
end;

procedure TATSynEdit.DoStringsOnUndoBefore(Sender: TObject; AX, AY: integer);
var
  OldOption: boolean;
  Tick: QWord;
begin
  FLastUndoPaused:= false;

  if ModeOneLine then exit;
  if FOptUndoPause<=0 then exit;
  if Carets.Count>1 then exit;
  if AY<0 then exit;
  if AY>=Strings.Count then exit; //must have for the case: big file; Ctrl+A, Del; Undo
  if IsPosInVisibleArea(AX, AY) then exit;

  Tick:= GetTickCount64;
  if FLastUndoTick>0 then
    if Tick-FLastUndoTick<FOptUndoPause2 then
      exit;

  FLastUndoPaused:= true;
  FLastUndoTick:= Tick;

  if FOptUndoPauseHighlightLine then
  begin
    OldOption:= OptShowCurLine;
    OptShowCurLine:= true;
  end;

  DoGotoPos(
    Point(AX, AY),
    Point(-1, -1),
    FOptUndoIndentHorz,
    FOptUndoIndentVert,
    true,
    true,
    false,
    false);
  { //not good
  DoShowPos(
    Point(0, ALine),
    FOptUndoIndentHorz,
    FOptUndoIndentVert,
    true,
    true);
    }

  UpdateAndWait(true, FOptUndoPause);

  if FOptUndoPauseHighlightLine then
    OptShowCurLine:= OldOption;
end;

procedure TATSynEdit.DoStringsOnUndoAfter(Sender: TObject; AX, AY: integer);
var
  OldOption: boolean;
begin
  if not FLastUndoPaused then exit;
  {
  if ModeOneLine then exit;
  if FOptUndoPause<=0 then exit;
  if AY<0 then exit;
  if AY>=Strings.Count then exit; //must have for the case: big file; Ctrl+A, Del; Undo
  if IsPosInVisibleArea(AX, AY) then exit;
  }

  if FOptUndoPauseHighlightLine then
  begin
    OldOption:= OptShowCurLine;
    OptShowCurLine:= true;
  end;

  UpdateAndWait(true, FOptUndoPause);

  if FOptUndoPauseHighlightLine then
    OptShowCurLine:= OldOption;
end;

procedure TATSynEdit.ActionAddJumpToUndo;
var
  St: TATStrings;
begin
  St:= Strings;
  if FOptUndoForCaretJump then
  begin
    St.SetGroupMark; //solve CudaText #3269
    St.ActionAddJumpToUndo(St.CaretsAfterLastEdition);
    //ActionAddJumpToUndo(GetCaretsArray); //bad, parameter is needed only for another array
  end;
end;


procedure TATSynEdit.BeginEditing;
var
  St: TATStrings;
begin
  St:= Strings;
  St.EditingActive:= true;
  St.EditingTopLine:= -1;
end;

procedure TATSynEdit.EndEditing(ATextChanged: boolean);
var
  St: TATStrings;
begin
  St:= Strings;
  St.EditingActive:= false;
  if ATextChanged then
    if St.EditingTopLine>=0 then
    begin
      //FlushEditingChangeEx(cLineChangeEdited, FEditingTopLine, 1); //not needed
      FlushEditingChangeLog(St.EditingTopLine);
    end;
end;

procedure TATSynEdit.UpdateGapForms(ABeforePaint: boolean);
var
  Gap: TATGapItem;
  i: integer;
begin
  if ABeforePaint then
  begin
    for i:= 0 to Gaps.Count-1 do
    begin
      Gap:= Gaps[i];
      if Assigned(Gap.Form) then
        Gap.FormVisible:= false;
    end;
  end
  else
  begin
    for i:= 0 to Gaps.Count-1 do
    begin
      Gap:= Gaps[i];
      if Assigned(Gap.Form) then
        Gap.Form.Visible:= Gap.FormVisible;
    end;
  end;
end;

procedure TATSynEdit.SetOptScaleFont(AValue: integer);
begin
  if FOptScaleFont=AValue then Exit;
  FOptScaleFont:=AValue;
  UpdateInitialVars(Canvas);
end;

procedure TATSynEdit.InitFoldbarCache(ACacheStartIndex: integer);
var
  NCount: integer;
  bLenValid, bClear: boolean;
begin
  NCount:= GetVisibleLines+1;

  bClear:= false;
  if FFoldbarCacheStart<>ACacheStartIndex then
    bClear:= true;
  bLenValid:= Length(FFoldbarCache)=NCount;
  if not bLenValid then
    bClear:= true;

  FFoldbarCacheStart:= ACacheStartIndex;

  if not bLenValid then
    SetLength(FFoldbarCache, NCount);

  if bClear then
    FillChar(FFoldbarCache[0], SizeOf(TATFoldBarProps)*NCount, 0);
end;

procedure TATSynEdit.DoHandleWheelRecord(const ARec: TATEditorWheelRecord);
begin
  case ARec.Kind of
    wqkVert:
      begin
        //w/o this handler wheel works only with OS scrollbars, need with new scrollbars too
        DoScrollByDeltaInPixels(
          0,
          FCharSize.Y * -FOptMouseWheelScrollVertSpeed * ARec.Delta div 120
          );
      end;

    wqkHorz:
      begin
        DoScrollByDelta(
          -FOptMouseWheelScrollHorzSpeed * ARec.Delta div 120,
          0
          );
      end;

    wqkZoom:
      begin
        DoScaleFontDelta(ARec.Delta>0, false);
        DoEventZoom;
      end;
  end;
end;

{
procedure TATSynEdit.DoHandleWheelQueue;
var
  Rec: TATEditorWheelRecord;
begin
  while FWheelQueue.Size()>0 do
  begin
    Rec:= FWheelQueue.Front;
    FWheelQueue.Pop();
    DoHandleWheelRecord(Rec);
  end;
end;
}


{$I atsynedit_carets.inc}
{$I atsynedit_hilite.inc}
{$I atsynedit_sel.inc}
{$I atsynedit_fold.inc}
{$I atsynedit_debug.inc}

{$R res/nicescroll1.res}
{$R res/nicescroll2.res}
{$R res/foldbar.res}
{$R res/editor_hourglass.res}

{$I atsynedit_cmd_handler.inc}
{$I atsynedit_cmd_keys.inc}
{$I atsynedit_cmd_sel.inc}
{$I atsynedit_cmd_editing.inc}
{$I atsynedit_cmd_clipboard.inc}
{$I atsynedit_cmd_misc.inc}
{$I atsynedit_cmd_bookmark.inc}
{$I atsynedit_cmd_markers.inc}


initialization

  RegExprModifierS:= False;
  RegExprModifierM:= True;
  {$ifndef USE_FPC_REGEXPR}
  RegExprUsePairedBreak:= False;
  RegExprReplaceLineBreak:= #10;
  {$endif}

end.

