program rtf;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, sysutils, futures;

type
  { Future with Integer result

    This class implements Integer base math functions.
  }
  TIntegerFuture = class(specialize TGenericFuture<Integer>) //TAbstractFuture)
  private type
    // integer future operation type
    // internal enumeration to distinct the different operations
    TIFOptype = (
      opAdd,
      opSubtract,
      opMultiply,
      opDivide
    );
    // complete data required for operation
    // excluding result (inherited by TGenereicFuture)
    TIFOperands = record
      optype: TIFOptype;
      op1, op2: Integer;
    end;
  private
    fOp: TIFOperands;
  protected
    procedure DoCalculation; override;
  public
    constructor Add(x1,x2: Integer);
    constructor Subtract(subtrahend, minuend: Integer);
    constructor Multiply(x1, x2: Integer);
    constructor Divide(dividend, divisor: Integer);
  end;

  TIntegerArrayFuture = class(TAbstractFuture)
  public type
    TIntArray = array of integer;
  public
    constructor Fibonacci(aCount: SizeUInt);
    constructor Random(aCount: SizeUInt);
    function GetResult: TIntArray;
  protected type
    TIAOptype = (
      opFibonacci,
      opRandom
    );
  protected
    fOperation: TIAOptype;
    fCount: SizeUInt;
    fResult: TIntArray;
    procedure DoCalculation_Fibonacci;
    procedure DoCalculation_Random;
    procedure DoCalculation; override;
  end;

  TMyFutureUsingFuture = class(specialize TGenericFuture<Integer>)
  strict protected
    fInt: TIntegerFuture;
    fUseOwnFuture: Boolean;
    procedure DoCalculation; override;
  public
    constructor Create(aIntFuture: TIntegerFuture);
    constructor UseOwnFuture(aIntFuture: TIntegerFuture);
  end;

{ TMyFutureUsingFuture }

procedure TMyFutureUsingFuture.DoCalculation;
var
  r: TIntegerArrayFuture;
begin
  if fUseOwnFuture then
  begin
    r := TIntegerArrayFuture.Random(1);
    fResult := r.GetResult[0] + fInt.GetResult;
  end
  else
    fResult := fInt.GetResult * 2;
end;

constructor TMyFutureUsingFuture.Create(aIntFuture: TIntegerFuture);
begin
  fInt := aIntFuture;
  fUseOwnFuture := False;
end;

constructor TMyFutureUsingFuture.UseOwnFuture(aIntFuture: TIntegerFuture);
begin                
  fInt := aIntFuture;
  fUseOwnFuture := True;
end;

{ TIntegerArrayFuture }

constructor TIntegerArrayFuture.Fibonacci(aCount: SizeUInt);
begin
  inherited Create;
  fOperation := opFibonacci;
  fCount := aCount;
end;

constructor TIntegerArrayFuture.Random(aCount: SizeUInt);
begin
  inherited Create;
  fOperation := opRandom;
  fCount := aCount;
end;

function TIntegerArrayFuture.GetResult: TIntArray;
begin
  RTLeventWaitFor(fCalculatedEvent);
  try
    CheckException;
    Result := fResult;
  finally
    Self.Destroy;
  end;
end;

procedure TIntegerArrayFuture.DoCalculation_Fibonacci;
 var
  i: SizeInt;
begin
  SetLength(fResult, fCount);
  for i := low(fResult) to high(fResult) do
    if i = 0 then
      fResult[i] := 0
    else if i = 1 then
      fResult[i] := 1
    else
      fResult[i] := fResult[i-1] + fResult[i-2]
end;

procedure TIntegerArrayFuture.DoCalculation_Random;
var
  i: SizeInt;
begin
  SetLength(fResult, fCount);
  for i := low(fResult) to high(fResult) do
    fResult[i] := System.Random(MaxInt);
end;

procedure TIntegerArrayFuture.DoCalculation;
begin
  case fOperation of
    opFibonacci: DoCalculation_Fibonacci;
    opRandom: DoCalculation_Random;
  end;
end;

{ TIntegerFuture }

constructor TIntegerFuture.Add(x1, x2: Integer);
begin
  inherited Create;
  fOp.optype := opAdd;
  fOp.op1 := x1;
  fOp.op2 := x2;
end;

constructor TIntegerFuture.Subtract(subtrahend, minuend: Integer);
begin
  inherited Create;
  fOp.optype := opSubtract;
  fOp.op1 := subtrahend;
  fOp.op2 := minuend;
end;

constructor TIntegerFuture.Multiply(x1, x2: Integer);
begin
  inherited Create;
  fOp.optype := opMultiply;
  fOp.op1 := x1;
  fOp.op2 := x2;
end;

constructor TIntegerFuture.Divide(dividend, divisor: Integer);
begin
  inherited Create;
  fOp.optype := opDivide;
  fOp.op1 := dividend;
  fOp.op2 := divisor;
end;

procedure TIntegerFuture.DoCalculation;
begin
  case fOp.optype of
    opAdd: fResult := fOp.op1 + fOp.op2;
    opSubtract: fResult := fOp.op1 - fOp.op2;
    opMultiply: fResult := fOp.op1 * fOp.op2;
    opDivide: fResult := fOp.op1 div fOp.op2;
  end;
end;

var
  i: TIntegerFuture;
  i2: Integer = 0;
  f: TIntegerArrayFuture;
  a: TIntegerArrayFuture.TIntArray;
begin
  SetHeapTraceOutput('heaptrc.log');

  // request the first 20 numbers of the Fibonacci series
  f := TIntegerArrayFuture.Fibonacci(20);

  // add 1 plus 2
  i := TIntegerFuture.Add(1, 2);
  // get the result
  i2 := i.GetResult;
  // write out the result (3)
  writeln(i2);

  // do some multiplication
  i := TIntegerFuture.Multiply(2, 3);
  writeln(i.GetResult);

  // it's just fine to call GetResult on the constructors result
  Writeln(TIntegerFuture.Divide(6,2).GetResult);

  // now get the Fibonacci Series requested before
  a := f.GetResult;
  for i2 in a do
    Writeln(i2);

  // get some random numbers
  a := TIntegerArrayFuture.Random(5).GetResult;
  for i2 in a do
    Writeln(i2);

  // use an future as input for another future
  WriteLn(TMyFutureUsingFuture.Create(TIntegerFuture.Add(3,2)).GetResult);

  // threads may also use futures
  Writeln(TMyFutureUsingFuture.UseOwnFuture(TIntegerFuture.Add(0,1)).GetResult);

  readln;
end.
