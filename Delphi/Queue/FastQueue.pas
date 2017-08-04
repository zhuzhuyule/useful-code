unit FastQueue;

interface
//线程安全版本

uses
  Windows, SysUtils;

const
  CONST_BYTE_SIZE = 4;
  CONST_PAGE_SINGLE = 1024;
  COSNT_PAGE_SINGLE_SIZE = CONST_PAGE_SINGLE * CONST_BYTE_SIZE;

type
  TFastQueue = class
  private
    FCS: TRTLCriticalSection;
    //
    FMem: Pointer;
    FTmpMem: Pointer;
    //
    FPushIndex: Integer;                //压入队列计数器
    FPopIndex: Integer;                 //弹出队列计数器
    FCapacity: Integer;                 //队列容量，始终大于 FPushIndex
    //
    procedure Lock();
    procedure UnLock();
    procedure SetCapacity(const AValue: Integer);
    //Pop 相关函数
    procedure MoveMem;
    //
    procedure setSynCapacity(const AValue: Integer);
    function getSynCapacity: Integer;
    function getSynCurCount: Integer;
  public
    constructor Create(AInitCapacity: Integer = CONST_PAGE_SINGLE);
    destructor Destroy(); override;
    //
    function Push(AItem: Pointer): Pointer;
    function Pop(): Pointer;
    function PushString(AItem: string): Pointer;
    function PopString(): string;
    procedure Clear;
  public
    property Capacity: Integer read getSynCapacity write setSynCapacity;
    property Count: Integer read getSynCurCount;
  end;

implementation

{ TFastQueue }
constructor TFastQueue.Create(AInitCapacity: Integer);
begin
  InitializeCriticalSection(FCS);

  FPushIndex := 0;
  FPopIndex := 0;

  if AInitCapacity < CONST_PAGE_SINGLE then
    AInitCapacity := CONST_PAGE_SINGLE;

  SetCapacity(AInitCapacity);
end;

destructor TFastQueue.Destroy;
begin
  FreeMem(FMem);
  if FTmpMem <> nil then
    FreeMem(FTmpMem);

  DeleteCriticalSection(FCS);

  inherited;
end;

procedure TFastQueue.Lock;
begin
  EnterCriticalSection(FCS);
end;

procedure TFastQueue.UnLock;
begin
  LeaveCriticalSection(FCS);
end;

procedure TFastQueue.SetCapacity(const AValue: Integer);
var
  vPageCount, vOldSize, vNewSize: Integer;
begin
  if AValue > FCapacity then
  begin
    if FTmpMem <> nil then
      FreeMem(FTmpMem);

    vPageCount := AValue div CONST_PAGE_SINGLE;
    if (AValue mod CONST_PAGE_SINGLE) > 0 then
      Inc(vPageCount);

    //保存旧的容量
    vOldSize := FCapacity * CONST_BYTE_SIZE;
    //计算新的容量
    FCapacity := vPageCount * CONST_PAGE_SINGLE;
    vNewSize := FCapacity * CONST_BYTE_SIZE;

    //扩容
    GetMem(FTmpMem, vNewSize);
    FillChar(FTmpMem^, vNewSize, #0);

    //转移数据
    if FMem <> nil then
    begin
      Move(FMem^, FTmpMem^, vOldSize);
      FreeMem(FMem);
    end;
    FMem := FTmpMem;

    //FTmpMem （保证弹出、插入数据时使用） 与 FMem 大小一致
    GetMem(FTmpMem, vNewSize);
  end;
end;

function TFastQueue.Push(AItem: Pointer; APriority: Integer): Pointer;
var
  vPMem: PInteger;
  vNextPriority, vPriority, vIndex: Integer;
  vNotPushed: boolean;
begin
  Lock();
  try
    vPMem := PInteger(FMem);
    Inc(vPMem, FPushIndex);
    vPMem^ := Integer(AItem);

    Inc(FPushIndex);
    //检测栈容量是否足够（至少保留一位空位，否则扩容 1024）
    if FPushIndex >= FCapacity then
    begin
      SetCapacity(FCapacity + CONST_PAGE_SINGLE);
    end;
  finally
    UnLock();
  end;
end;

function TFastQueue.Pop: Pointer;

  procedure MoveMem();
  var
    vvPSrc: PInteger;
    vvTmpMem: Pointer;
  begin
    FillChar(FTmpMem^, FCapacity * CONST_BYTE_SIZE, #0);
    vvPSrc := PInteger(FMem);
    Inc(vvPSrc, FPopIndex);
    Move(vvPSrc^, FTmpMem^, (FCapacity - FPopIndex) * CONST_BYTE_SIZE);
    //交换指针
    vvTmpMem := FMem;
    FMem := FTmpMem;
    FTmpMem := vvTmpMem;
  end;

var
  vPMem: PInteger;
begin
  Lock();
  try
    Result := nil;
    if (FPopIndex = FPushIndex) then
      Exit;
    // 1.获取弹出元素
    vPMem := PInteger(FMem);
    Inc(vPMem, FPopIndex);
    Result := Pointer(vPMem^);
    // 2.弹出元素后 弹出计数器 +1
    Inc(FPopIndex);
    // 3.队列底部空余内存达到 1024 整体迁移
    if FPopIndex = CONST_PAGE_SINGLE then
    begin
      //迁移数据
      MoveMem();
      //重置弹出位置
      FPopIndex := 0;
      //减少压入队列的数量
      Dec(FPushIndex, CONST_PAGE_SINGLE);
    end;
  finally
    UnLock();
  end;
end;

function TFastQueue.PushString(AItem: string; APriority: Integer): Pointer;
var
  vPChar: PChar;
begin
  vPChar := StrAlloc(256);
  StrCopy(vPChar, pchar(AItem + '   |' + inttostr(FPushIndex)));
  Push(vPChar, APriority);
end;

function TFastQueue.PopString: string;
var
  vPChar: PChar;
begin
  Result := 'nil';
  vPChar := Pop;
  if vPChar <> '' then
  begin
    Result := vPChar;
    StrDispose(vPChar);
  end;
end;

procedure TFastQueue.Clear;
begin
  Lock();
  try
    FPushIndex := 0;
    FPopIndex := 0;

    SetCapacity(CONST_PAGE_SINGLE);
  finally
    UnLock();
  end;
end;

procedure TFastQueue.setSynCapacity(const AValue: Integer);
begin
  Lock();
  try
    SetCapacity(AValue);
  finally
    UnLock();
  end;
end;

function TFastQueue.getSynCapacity: Integer;
begin
  Lock();
  try
    Result := FCapacity;
  finally
    UnLock();
  end;
end;

function TFastQueue.getSynCurCount: Integer;
begin
  Lock();
  try
    Result := FPushIndex - FPopIndex;
  finally
    UnLock();
  end;
end;

end.
