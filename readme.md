# Pascal Futures

This is a Run Time Future Implementation.

The concept of futures describes a parallel code execution pattern.
Computation results are requested on an early point of execution but the
result is first guaranteed to be available when the result is retrieved.
While the future's result is computed, the calling thread may do some other
calculations or start other futures on other threads.

````Delphi
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
````
As this is unit is part of any other project as any other unit, it has some
drawbacks to a possible compiler intrinsic future implementation.

- The future management object lifetime must be addressed
- No automatic parallel execution optimization
- All worker threads are notified on each future queueing
- The implementation overhead for each future is exuberant

But there are some advantages also

- You may change the future queue manager (TFutureManager) at runtime
- You may implement your own future queue, e.g. with more queues for different priorities
- You may change the count of threads at runtime and adjust them to your needs or performance experience

The default queue manager TFutureManager implements a simple but threadsafe
First In First Out queue and uses as many threads as the program is assigned
to CPU cores (withou special actions by system administration this is equal
the total count of cpu cores in your computer).

## Dependencies

This package is tested with [Free Pascal](http://freepascal.org/) 3.1 and [Lazarus](http://lazarus-ide.org/) 1.7 but it should be compatible with the latest the latest stable compiler.
It requires Lazarus to be installed as it uses the package [MultiThreadProcsLaz](http://wiki.freepascal.org/Parallel_procedures), which is part of the default Lazarus distribution, for CPU counting.
The System unit contains the function [`GetCPUCount`](http://www.freepascal.org/docs-html/current/rtl/system/getcpucount.html) but this returns the count of CPUs installed in the system and not the count of CPUs the program can be executed on.
Thus the function `GetSystemThreadCount` of unit `mtpcpu` is used.

## License

This library is available under the GNU LGPL with linking exception. See [LICENSE.md](LICENSE.md) for details.