-module(quic_conn).
-export([start_link/2, loop/2]).

start_link(Transport, Peer) ->
    {ok, spawn_link(?MODULE, loop, [Transport, Peer])}.

loop(Transport = {udp, Server, Sock}, Peer = {IP, Port}) ->
    receive
        {datagram, Server, Packet} ->
            io:format("DATA: ~p~n", [{Peer,Packet}]),
            Server ! {datagram, Peer, Packet},
            ok = gen_udp:send(Sock, IP, Port, Packet),
            loop(Transport, Peer)
    end.

