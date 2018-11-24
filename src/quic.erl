-module(quic).
-behaviour(supervisor).
-behaviour(application).
-export([init/1, start/0, start/2, stop/1]).

udp([Proto, Port, Opts, MFA]) ->
    {{Proto,Port},{quic_udp,start_link,[Proto, Port, Opts, MFA]},
     permanent,2000,worker,[quic_udp]}.

init(X) -> {ok, {{one_for_one, 5, 10}, [udp(X)]}}.
stop(_) -> ok.
start() -> start(normal,[]).
start(_,_) ->
    supervisor:start_link({local,quic},quic,
       ['QUIC',4000,[{opts, [binary, {reuseaddr, true}]}],
                    {quic_conn, start_link, []}]).

