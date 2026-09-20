-module(fist_test_ffi).
-export([rescue/1]).

rescue(Fun) ->
    try
        {ok, Fun()}
    catch
        _Class:Reason ->
            {error, Reason}
    end.
