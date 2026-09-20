-module(fist_test_ffi).
-export([rescue/1, time_ms/1]).

rescue(Fun) ->
    try
        {ok, Fun()}
    catch
        _Class:Reason ->
            {error, Reason}
    end.

time_ms(Fun) ->
    T0 = erlang:monotonic_time(millisecond),
    Res = Fun(),
    T1 = erlang:monotonic_time(millisecond),
    {T1 - T0, Res}.
