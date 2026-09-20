-module(fist_test_ffi).
-export([rescue/1, time_ms/1, target_name/0, make_native_handler/1, make_native_middleware/1, measure_memory_bytes/0]).

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

target_name() ->
    <<"erlang">>.

make_native_handler(Prefix) ->
    fun(_Req, _Ctx, Params) ->
        Name = maps:get(<<"name">>, Params, <<"world">>),
        <<Prefix/binary, ":", Name/binary>>
    end.

make_native_middleware(Tag) ->
    fun(Next) ->
        fun(Req, Ctx, Params) ->
            Res = Next(Req, Ctx, Params),
            <<Tag/binary, "(", Res/binary, ")">>
        end
    end.

measure_memory_bytes() ->
    case erlang:process_info(self(), memory) of
        {memory, Bytes} -> Bytes;
        _ -> 0
    end.
