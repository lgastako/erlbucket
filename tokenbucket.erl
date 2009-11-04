-module(tokenbucket).
-export([make/2, take/2]).


mega_seconds_to_milli_seconds(MegaSecs) -> MegaSecs * 1000000000.
seconds_to_milli_seconds(Secs) -> Secs * 1000.
micro_seconds_to_milli_seconds(MicroSecs) -> MicroSecs * 0.001.
milli_seconds_to_seconds(MilliSecs) -> MilliSecs * 0.001.


now_in_millis() ->
    {MegaSecs, Secs, MicroSecs} = now(),
    mega_seconds_to_milli_seconds(MegaSecs) + seconds_to_milli_seconds(Secs) + micro_seconds_to_milli_seconds(MicroSecs).


make(Capacity, FillRate) ->
    spawn(fun() -> loop(Capacity, Capacity, FillRate, now_in_millis()) end).


refill(Capacity, RemainingTokens, FillRate, LastFilled) ->
    Now = now_in_millis(),
    TokenDelta = FillRate * milli_seconds_to_seconds(Now - LastFilled),
    UpdatedRemainingTokens = dputils:min(Capacity, RemainingTokens + TokenDelta),
    UpdatedLastFilled = Now,
    {UpdatedRemainingTokens, UpdatedLastFilled}.


do_take(N, RemainingTokens) when N > RemainingTokens ->
    {false, RemainingTokens};
do_take(N, RemainingTokens) ->
    UpdatedRemainingTokens = RemainingTokens - N,
    {true, UpdatedRemainingTokens}.


loop(Capacity, RemainingTokens, FillRate, LastFilled) ->
    receive
        {consume, N, Pid} ->
            {InterimUpdatedRemainingTokens, UpdatedLastFilled} = refill(Capacity, RemainingTokens, FillRate, LastFilled),
            {Response, UpdatedRemainingTokens} = do_take(N, InterimUpdatedRemainingTokens),
            Pid ! {Response, UpdatedRemainingTokens},
            loop(Capacity, UpdatedRemainingTokens, FillRate, UpdatedLastFilled);
        {reload, Pid} ->
            Pid ! {ok, reloading},
            tokenbucket:loop(Capacity, RemainingTokens, FillRate, LastFilled);
        _ ->
            % TODO: log error here
            loop(Capacity, RemainingTokens, FillRate, LastFilled)
    end.


take(BucketPid, N) ->
    BucketPid ! {consume, N, self()},
    receive
        Response -> Response
    end.
