{ Run Time Future Implementation

  Copyright (C) 2016 Simon Ameis <simon.ameis@web.de>

  This library is free software; you can redistribute it and/or modify it
  under the terms of the GNU Library General Public License as published by
  the Free Software Foundation; either version 2 of the License, or (at your
  option) any later version with the following modification:

  As a special exception, the copyright holders of this library give you
  permission to link this library with independent modules to produce an
  executable, regardless of the license terms of these independent modules,and
  to copy and distribute the resulting executable under terms of your choice,
  provided that you also meet, for each linked independent module, the terms
  and conditions of the license of that module. An independent module is a
  module which is not derived from or based on this library. If you modify
  this library, you may extend this exception to your version of the library,
  but you are not obligated to do so. If you do not wish to do so, delete this
  exception statement from your version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
  for more details.

  You should have received a copy of the GNU Library General Public License
  along with this library; if not, write to the Free Software Foundation,
  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


  This is a Run Time Future Implementation.

  The concept of futures describes a parallel code execution pattern.
  Computation results are requested on an early point of execution but the
  result is first guaranteed to be available when the result is retrieved.
  While the future's result is computed, the calling thread may do some other
  calculations or start other futures on other threads.

  program demofutures;
  uses
    futures;
  var
    i: TIntegerFuture;
    j: Integer;
  begin
    i := TIntegerFuture.Sum(1, 2);
    // do some other interesting stuff
    // ...
    // retrieve result
    j := i.GetResult;
    // use the result
    WriteLn('The sum of 1 and 2 is: ', j);
  end.

  As this is unit is part of any other project as any other unit, it has some
  drawbacks compared to a possible compiler intrinsic future implementation.
  - The future management object lifetime must be addressed
  - No automatic parallel execution optimization
  - All worker threads are notified on each future queueing
  - The implementation overhead for each future is exuberant

  But there are some advantages also
  - You may change the future queue manager (TFutureManager) at runtime
  - You may implement your own future queue, e.g. with more queues for
    different priorities
  - You may change the count of threads at runtime and adjust them to your needs
    or performance experience

  The default queue manager TFutureManager implements a simple but threadsafe
  First In First Out (FIFO) queue and uses as many threads as the program is 
  assigned to CPU cores (withou special actions by system administration this is
  equal the total count of cpu cores in your computer).
  However the FIFO queue implies there is no dead lock resolution. By default
  this is no problem as each future is automatically queued after creation.
  But if you override the @(TAbstractFuture.AfterConstruction) you SHOULD 
  read the documentation of this method.
}

unit futures;

{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}

interface

uses
  Classes, SysUtils, MTPCPU, fgl, gqueue;

type
  { Base class for all futures

    This base class implements the public interface for the
    asynchronous computing in worker threads outside of the
    main thread.

    The future instance is automatically added to the queue
    of @FutureManager after the constructor is finished.

    There is no method for retrieving the computed result as
    the result type may vary. But the generic class
    @link(TGenericFuture) may be specialized providing a default
    @link(TGenericFuture.GetResult) method.
  }
  TAbstractFuture = class(TObject)
  strict protected
    { Is TRUE, if the calculation of the future ended either successfully,
      raised an exception or was terminated.

      Is set by @link(ThreadCalculate)
    }
    fIsFinished: Boolean;
    { Event which is set at end of calulation
      Each result retrieval method MUST wait for this event
      before returning the calculation's result. Otherwise the
      calculation may be incomplete.

      Also this MUST be check before calling the destructor
      as the future may be in use by a thread while the event
      is not set.

      This event is not available during constructor. Thus the constructor
      MUST NOT access this field and MUST NOT initialize it. It will be
      initialized after the constructor has finished in method
      @link(AfterConstruction) but before the new instance is added to the
      future manger's queue.
    }
    fCalculatedEvent: PRTLEvent;
    { Exception occured in DoCalculation
      If an exception is raised in DoCalculation, it is catched
      and stored in this variable.
      The method @CheckException checks if there is an exception
      and raises it.
      @seealso CheckException
    }
    fFatalException: TObject;
    { Indicates if the result will be retrieved by the caller.
      TRUE  = the caller will not get the result and will not destroy the future
             object
      FALSE = the caller will retrieve the result and destroy the object

      The datatype is LongBool as it's accessed with the function
      @InterlockedExchange.
    }
    fTerminated: LongBool;
  strict protected
    { Calculation of future's result
      Override in descendent classes.
      This method MUST be threadsafe.

      You SHOULD regulary check the value of @fTerminated. If it's TRUE, the
      method exit the calculation. Obviously this is only relevant for rather
      long running methods like file I/O, networking, complex mathematics and
      so on.
    }
    procedure DoCalculation; virtual; abstract;
    { raises potentially existing exceptions
      This method SHOULD be called in each result retrieval method.
    }
    procedure CheckException;
  public
    { Is TRUE, if the calculation of the future ended either successfully,
      raised an exception or was terminated.

      If it's true
    }
    property IsFinished: Boolean read fIsFinished;
    { Initialize event and add instance to future queue

      If you override this method in your own future class, you SHOULD
      call this method.

      If you call it at the beginning of your own method, keep in mind, the
      instance is already added to the queue and may also already finished
      the @link(DoCalculation) method but it will still exists as the creating
      thread is still working on the AfterConstruction method.

      If you call it at the end of the overriding method, you MUST NOT access
      the @link(fCalculatedEvent) as it is not initialized.

      If you don't call it at all, you SHOULD know what you are doing, e.g. you
      need to initialize @link(fCalculatedEvent) and add the instance to the
      queue yourself.

      @seealso FutureManager
    }
    procedure AfterConstruction; override;
    { Cleaning up of thread event
      The destructor doesn't check if the future is in a queue or
      currently in use by a thread. Therefore the application MUST
      ensure it's safe to destroy the future.
      Usually this is included in a result retrieval method.
    }
    destructor Destroy; override;
    { Thread method for result calculation
      This method encapsulates the real calulation of @DoCalculation
      in a try..except block and sets the thread event.
    }
    procedure ThreadCalculate;
    { Waits for the future to finish and raises an exception if raised
      during @DoCalculation.

      The future object is not destroyed; this is the oblication of the caller.

      @seealso(WaitForAndDestroy)
    }
    procedure WaitFor;
    { Waits for the future to finish and raises an exception if raised
      during @DoCalculation.

      After the calculation has finished, the future object is destroyed.
      The object is also destroyed if an exception is raised

      @seealso(WaitFor)
    }
    procedure WaitForAndDestroy;
    { Sets the flag @fTerminated to TRUE removes the future from queue and
      waits for the calculation to terminated. Afterwards, the future object
      will be destroyed.
    }
    procedure Terminate; virtual;
  end;

  { Generic base class for futures

    This generic implements the thread waiting and exception handling
    in a GetResult method.
  }
  generic TGenericFuture<ResultType> = class(TAbstractFuture)
  strict protected
    { Holds the calculation result; SHOULD be set in @link(DoCalculation) }
    fResult: ResultType;
  public
    { Waits until the calculation is done and returns the calculated result.
      If any exception is raised duriong @DoCalculation, this exception is
      raised in the calling thread.
      At the end the future object is always destroyed, even if an exception is
      raised.
    }
    function GetResult: ResultType;
  end;

  { TCustomFuture }

  TCustomFuture = class(specialize TGenericFuture<Pointer>)
  public type
    TFutureProcedure = procedure (Data: Pointer);
    TFutureProcedureObject = procedure (Data: TObject);
    TFutureMethod = procedure (Data: Pointer) of object;
    TFutureMethodObject = procedure (Data: TObject) of object;
    TFutureNestedProcedure = procedure (Data: Pointer) is nested;
    TFutureNestedProcedureObject = procedure (Data: TObject) is nested;
  public
    constructor Custom(aProc: TFutureProcedure; aData: Pointer);
    constructor Custom(aProc: TFutureProcedureObject; aData: TObject);
    constructor Custom(aMethod: TFutureMethod; aData: Pointer);
    constructor Custom(aMethod: TFutureMethodObject; aData: TObject);
    constructor Custom(aMethod: TFutureNestedProcedure; aData: Pointer);
    constructor Custom(aMethod: TFutureNestedProcedureObject; aData: TObject);
  public
    // get result cast to TObject
    function GetObject: TObject;
  protected
    procedure DoCalculation; override;
  strict protected
    fData: Pointer;
    fProc: TFutureProcedure;
    fMethod: TFutureMethod;
    fNested: TFutureNestedProcedure;
  end;

  { Class for managing future queue and worker threads }
  TFutureManager = class(TObject)
  public type
    TAbstractFutureList = specialize TQueue<TAbstractFuture>;
  private type
    { Worker Thread for TAbstractFuture }
    TWorkerThread = class(TThread)
    protected
      procedure Execute; override;
    public
      AwakeEvent: PRTLEvent;
      procedure AfterConstruction; override;
    end;
    TListOfThreads = specialize TFPGObjectList<TWorkerThread>;
    { Thread save queue of TAbstractFuture

      All public methods are THREADSAFE; this does not include constructor and
      destructor..
    }
    TThreadFutureList = class
    private
      fList: TAbstractFutureList;
      fCriticalSection: TRTLCriticalSection;
      function GetCount: SizeUInt;
    public
      constructor Create;
      destructor Destroy; override;
      procedure Push(aFuture: TAbstractFuture);
      function Pop: TAbstractFuture;
      procedure Lock;
      procedure Unlock;
      function RemoveFuture(aFuture: TAbstractFuture): Boolean;
      property Count: SizeUInt read GetCount;
    end;
  strict protected
    fThreads: TListOfThreads;
    fFutures: TThreadFutureList;
    { Returns the current count of worker threads
    }
    function GetThreadCount: Integer;
    { Sets the count of worker threads.

      This method is NOT THREADSAFE. So you SHOULD initialize the thread count
      at program startup, may modify it in the main thread but SHOULD NOT call
      it from a thread.
    }
    procedure SetThreadCount(aCount: Integer);
    { Wake up worker threads

      Currently all worker threads are woken up when a future is added.
    }
    procedure NotifyThreads;
    { destroy all queued futures

      This should only destroy futures on a non clean exit as otherwise
      all futures should have been processed already.
    }
    procedure CleanUpFutures;
  public
    { Initializes a future manager instance }
    constructor Create;
    destructor Destroy; override;
    { Adds a future to the queue

      Adding a future is THREADSAFE. So a future may use other futures itself.
    }
    procedure AddFuture(aFuture: TAbstractFuture);
    { Returns the first added future

      This method is THREADSAFE as it is used by all worker threads. It's not
      intended to be used by main thread.
    }
    function PopFuture: TAbstractFuture;
    { Removes a future object from the queue

      This operation is THREADSAFE but may be rather slow as the queue is sorted
      by the time the objects are added. While removing a future object, no
      other worker thread can start working on new futures; all futures
      currently in execution will continue.

      Returns TRUE if the object was found in the queue and has been removed.

      Returns FALSE if the object was not found in the queue and couldn't be
      removed therfore. It may be either in execution by a worker thread or
      the execution has already finished.
    }
    function RemoveFuture(aFuture: TAbstractFuture): Boolean;
    { The current count of worker threads

      This property is NOT THREADSAFE.
    }
    property ThreadCount: Integer read GetThreadCount write SetThreadCount;
  end;

{ Global Future Manager

  This variable must hold a valid TFutureManager instance
  when creating future objects.

  @link(TAbstractFuture.AfterConstruction)
}
var FutureManager: TFutureManager = nil;

implementation

{ TGenericFuture }

function TGenericFuture.GetResult: ResultType;
begin
  try
    WaitFor;
    Result := fResult;
  finally
    Self.Destroy;
  end;
end;

{ TCustomFuture }

constructor TCustomFuture.Custom(aProc: TFutureProcedure; aData: Pointer);
begin
  inherited Create;
  fProc := aProc;
  fData := aData;
end;

constructor TCustomFuture.Custom(aProc: TFutureProcedureObject; aData: TObject);
begin
  inherited Create;
  fProc := TFutureProcedure(aProc);
  fData := Pointer(aData);
end;

constructor TCustomFuture.Custom(aMethod: TFutureMethod; aData: Pointer);
begin
  inherited Create;
  fMethod := aMethod;
  fData   := aData;
end;

constructor TCustomFuture.Custom(aMethod: TFutureMethodObject; aData: TObject);
begin 
  inherited Create;
  fMethod := TFutureMethod(aMethod);
  fData   := Pointer(aData);
end;

constructor TCustomFuture.Custom(aMethod: TFutureNestedProcedure; aData: Pointer
  );
begin
  inherited Create;
  fNested := aMethod;
  fData := aData;
end;

constructor TCustomFuture.Custom(aMethod: TFutureNestedProcedureObject;
  aData: TObject);
begin
  inherited Create;
  fNested := TFutureNestedProcedure(aMethod);
  fData := Pointer(aData);
end;

function TCustomFuture.GetObject: TObject;
begin
  Result := TObject(GetResult);
end;

procedure TCustomFuture.DoCalculation;
begin
  if Assigned(fProc) then
    fProc(fData)
  else
  if Assigned(fMethod) then
    fMethod(fData)
  else
  if Assigned(fNested) then
    fNested(fData);
end;

{ TFutureManager.TThreadFutureList }

function TFutureManager.TThreadFutureList.GetCount: SizeUInt;
begin
  EnterCriticalsection(fCriticalSection);
  Result := fList.Size();
  LeaveCriticalsection(fCriticalSection);
end;

constructor TFutureManager.TThreadFutureList.Create;
begin
  InitCriticalSection(fCriticalSection);
  fList := TAbstractFutureList.Create;
end;

destructor TFutureManager.TThreadFutureList.Destroy;
begin
  DoneCriticalsection(fCriticalSection);
  fList.Free;
  inherited Destroy;
end;

procedure TFutureManager.TThreadFutureList.Push(aFuture: TAbstractFuture);
begin
  EnterCriticalsection(fCriticalSection);
  try
    fList.Push(aFuture);
  finally
    LeaveCriticalsection(fCriticalSection);
  end;
end;

function TFutureManager.TThreadFutureList.Pop: TAbstractFuture;
begin
  EnterCriticalsection(fCriticalSection);
  try
    if fList.Size() > 0 then
    begin
      Result := fList.Front();
      fList.Pop();
    end else
      exit(nil);
  finally
    LeaveCriticalsection(fCriticalSection);
  end;
end;

procedure TFutureManager.TThreadFutureList.Lock;
begin
  EnterCriticalsection(fCriticalSection);
end;

procedure TFutureManager.TThreadFutureList.Unlock;
begin
  LeaveCriticalsection(fCriticalSection);
end;

function TFutureManager.TThreadFutureList.RemoveFuture(aFuture: TAbstractFuture
  ): Boolean;
var
  newlist: TAbstractFutureList;
  CurrentFuture: TAbstractFuture;
begin
  EnterCriticalsection(fCriticalSection);
  try
    if fList.IsEmpty() then exit(False);

    Result := False;

    newlist := TAbstractFutureList.Create;
    try
      // find all occurences of aFuture and remove them from list
      while fList.Size() > 0 do
      begin
        CurrentFuture := fList.Front;
        fList.Pop();
        if CurrentFuture = aFuture then
          Result := True
        else
          newlist.Push(CurrentFuture);
      end;

      // add all other futures in the original order
      while newlist.Size() > 0 do
      begin
        CurrentFuture := newlist.Front();
        newlist.Pop();
        fList.Push(CurrentFuture);
      end;
    finally
      newlist.Destroy;
    end;

  finally
    LeaveCriticalsection(fCriticalSection);
  end;
end;

{ TAbstractFuture }

procedure TAbstractFuture.CheckException;
begin
  if Assigned(fFatalException) then
    raise fFatalException;
end;

procedure TAbstractFuture.AfterConstruction;
begin
  inherited AfterConstruction;       
  fCalculatedEvent := RTLEventCreate;
  FutureManager.AddFuture(Self);
end;

destructor TAbstractFuture.Destroy;
begin
  RTLeventdestroy(fCalculatedEvent);
  fCalculatedEvent := nil;
  inherited Destroy;
end;

procedure TAbstractFuture.ThreadCalculate;
begin
  try
    if not fTerminated then
      DoCalculation;
  except
    on o: TObject do
      fFatalException := TObject(AcquireExceptionObject);
  end;
  RTLeventSetEvent(fCalculatedEvent);
  fIsFinished := True;
end;

procedure TAbstractFuture.WaitFor;
begin
  RTLeventWaitFor(fCalculatedEvent);
  CheckException;
end;

procedure TAbstractFuture.WaitForAndDestroy;
begin
  try
    WaitFor;
  finally
    Self.Destroy;
  end;
end;

procedure TAbstractFuture.Terminate;
var
  Removed: Boolean;
begin
  // singal thread to not start the calculation
  InterLockedExchange(LongInt(fTerminated), LongInt(LongBool(True)));
  Removed := FutureManager.RemoveFuture(Self);
  // a thread started the @DoCalculation method
  if not Removed then
    WaitFor;
  // free exception if raised
  fFatalException.Free;
  Self.Destroy;
end;

{ TFutureManager.TWorkerThread }

procedure TFutureManager.TWorkerThread.Execute;
var
  TheFuture: TAbstractFuture;
begin
  while not Terminated do
  begin
    RTLeventWaitFor(AwakeEvent);

    TheFuture := FutureManager.PopFuture;
    if not Assigned(TheFuture) then
    begin
      Continue;
    end;

    TheFuture.ThreadCalculate;
  end;
  RTLeventdestroy(AwakeEvent);
  AwakeEvent := nil;
end;

procedure TFutureManager.TWorkerThread.AfterConstruction;
begin
  AwakeEvent := RTLEventCreate;
  inherited AfterConstruction;
end;

{ TFutureManager }

function TFutureManager.GetThreadCount: Integer;
begin
  Result := fThreads.Count;
end;

procedure TFutureManager.SetThreadCount(aCount: Integer);
var
  i: Integer;
  TheThread: TWorkerThread;
begin
  if Assigned(fThreads) and (fThreads.Count > 0) then
  begin
    if (aCount = 0) then
    begin
      for i := fThreads.Count - 1 downto 0 do
      begin
        fThreads[i].Terminate;
        RTLeventSetEvent(fThreads[i].AwakeEvent);
        fThreads[i].WaitFor;
        fThreads[i].Free;
        fThreads[i] := nil;
        fThreads.Delete(i);
      end;
    end else
    if aCount > fThreads.Count then
    begin
      for i := 1 to (aCount - fThreads.Count) do
      begin
        TheThread := TWorkerThread.Create(True);
        fThreads.Add(TheThread);
        TheThread.Start;
      end;
    end else
    if aCount < fThreads.Count then
    begin
      SetThreadCount(0);
      SetThreadCount(aCount);
    end;

    exit;
  end;

  for i := 0 to aCount - 1 do
  begin
    fThreads.Add(TWorkerThread.Create(True));
    fThreads[i].Start;
  end;
end;

procedure TFutureManager.NotifyThreads;
var
  t: TWorkerThread;
begin
  for t in fThreads do
    RTLeventSetEvent(t.AwakeEvent);
end;

procedure TFutureManager.CleanUpFutures;
var
  f: TAbstractFuture;
begin
  if Assigned(fFutures) then
  begin
    fFutures.Lock;
    try
      while fFutures.Count > 0 do
      begin
        f := fFutures.Pop;
        f.Free;
      end;
    finally
      fFutures.Unlock;
    end;
  end;
end;

constructor TFutureManager.Create;
begin
  // don't own threads
  // they are cleaned up in SetThreadCount() call during destruction
  fThreads := TListOfThreads.Create(False);
  fFutures := TThreadFutureList.Create;
  SetThreadCount(GetSystemThreadCount);
end;

destructor TFutureManager.Destroy;
begin
  // first clean up all remaining futures
  // then end all threads
  // and then destroy list of futures
  // -> threads may query for more futures during shutdown
  CleanUpFutures;
  SetThreadCount(0);
  fThreads.Free; 
  fFutures.Free;
  inherited Destroy;
end;

procedure TFutureManager.AddFuture(aFuture: TAbstractFuture);
begin
  fFutures.Push(aFuture);
  NotifyThreads;
end;

function TFutureManager.PopFuture: TAbstractFuture;
begin
  Result := fFutures.Pop;
end;

function TFutureManager.RemoveFuture(aFuture: TAbstractFuture): Boolean;
begin
  Result := fFutures.RemoveFuture(aFuture);
end;

initialization
  FutureManager := TFutureManager.Create;
finalization
  FutureManager.Destroy;
end.

