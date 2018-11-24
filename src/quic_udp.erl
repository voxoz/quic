-module(quic_udp).
-behaviour(gen_server).
-export([start_link/4, count_peers/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {proto, sock, port, peers, mfa}).

start_link(Proto, Port, Opts, MFA) ->
    gen_server:start_link(?MODULE, [Proto, Port, Opts, MFA], []).

merge_addr(Addr, Opts) ->
    lists:keystore(ip, 1, Opts, {ip, Addr}).

count_peers(Pid) ->
    gen_server:call(Pid, count_peers).

stop(Pid) ->
    gen_server:stop(Pid, normal, infinity).

init([Proto, Port, Opts, MFA]) ->
    process_flag(trap_exit, true),
    case gen_udp:open(Port, proplists:get_value(opts,Opts,[])) of
        {ok, Sock} ->
            inet:setopts(Sock, [{active, 1}]),
            {ok, #state{proto = Proto, sock = Sock, port = Port, peers = #{}, mfa = MFA}};
        {error, Reason} ->
            {stop, Reason};
        _O ->
            {stop,error}
    end.

handle_call(count_peers, _From, State = #state{peers = Peers}) ->
    {reply, maps:size(Peers) div 2, State, hibernate};

handle_call(Req, _From, State) ->
    io:format("unexpected call: ~p", [Req]),
    {reply, ignored, State}.

handle_cast(Msg, State) ->
    io:format("unexpected cast: ~p", [Msg]),
    {noreply, State}.

handle_info({udp, Sock, IP, InPortNo, Packet},
            State = #state{sock = Sock, peers = Peers, mfa = {M, F, Args}}) ->
    Peer = {IP, InPortNo},
    case maps:find(Peer, Peers) of
        {ok, Pid} ->
            Pid ! {datagram, self(), Packet},
            {noreply, State};
        error ->
            case catch erlang:apply(M, F, [{udp, self(), Sock}, Peer | Args]) of
                {ok, Pid} ->
                    _Ref = erlang:monitor(process, Pid),
                    Pid ! {datagram, self(), Packet},
                    {noreply, store_peer(Peer, Pid, State)};
                {Err, Reason} when Err =:= error; Err =:= 'EXIT' ->
                    io:format("Failed to start udp channel reason: ~p",
                               [{Peer,Reason}]),
                    {noreply, State}
            end
    end;

handle_info({udp_passive, Sock}, State) ->
    inet:setopts(Sock, [{active, 100}]),
    {noreply, State, hibernate};

handle_info({'DOWN', _MRef, process, DownPid, _Reason}, State = #state{peers = Peers}) ->
    case maps:find(DownPid, Peers) of
        {ok, Peer} -> {noreply, erase_peer(Peer, DownPid, State)};
        error      -> {noreply, State}
    end;

handle_info({datagram, Peer = {IP, Port}, Packet}, State = #state{sock = Sock}) ->
    case gen_udp:send(Sock, IP, Port, Packet) of
        ok -> ok;
        {error, Reason} ->
            io:format("Dropped packet to reason: ~s", [{Peer,Reason}])
    end,
    {noreply, State};

handle_info(Info, State) ->
    io:format("unexpected info: ~p", [Info]),
    {noreply, State}.

terminate(_Reason, #state{sock = Sock}) ->
    gen_udp:close(Sock).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

store_peer(Peer, Pid, State = #state{peers = Peers}) ->
    State#state{peers = maps:put(Pid, Peer, maps:put(Peer, Pid, Peers))}.

erase_peer(Peer, Pid, State = #state{peers = Peers}) ->
    State#state{peers = maps:remove(Peer, maps:remove(Pid, Peers))}.

merge_opts(Defaults, Options) ->
    lists:foldl(
      fun({Opt, Val}, Acc) ->
          lists:keystore(Opt, 1, Acc, {Opt, Val});
         (Opt, Acc) ->
          lists:usort([Opt | Acc])
      end, Defaults, Options).

