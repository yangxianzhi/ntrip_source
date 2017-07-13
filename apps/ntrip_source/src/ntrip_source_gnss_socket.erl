%%%-------------------------------------------------------------------
%%% @author ilink
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 七月 2017 17:05
%%%-------------------------------------------------------------------
-module(ntrip_source_gnss_socket).
-author("ilink").

%% API
-export([connect/6, controlling_process/2, send/2, close/1]).

-export([sockname/1, sockname_s/1, setopts/2, getstat/2]).

%% Internal export
-export([receiver/2, receiver_loop/2]).

%% 30 (secs)
-define(TIMEOUT, 90000).

-define(TCPOPTIONS, [
  binary,
  {packet,    raw},
  {nodelay,   true},
  {active, 	false},
  {reuseaddr, true},
  {send_timeout,  ?TIMEOUT}
]).

-define(SSLOPTIONS, [
  {depth, 0}
]).

-record(ssl_socket, {tcp, ssl}).

-type ssl_socket() :: #ssl_socket{}.

-define(IS_SSL(Socket), is_record(Socket, ssl_socket)).

%%------------------------------------------------------------------------------
%% @doc Connect to broker with TCP or SSL transport
%% @end
%%------------------------------------------------------------------------------
-spec connect(ClientPid, Transport, Host, Port, TcpOpts, SslOpts) -> {ok, Socket, Receiver} | {error, term()} when
  ClientPid   :: pid(),
  Transport   :: tcp | ssl,
  Host        :: inet:ip_address() | string(),
  Port        :: inet:port_number(),
  TcpOpts     :: [gen_tcp:connect_option()],
  SslOpts     :: [ssl:ssloption()],
  Socket      :: inet:socket() | ssl_socket(),
  Receiver    :: pid().
connect(ClientPid, Transport, Host, Port, TcpOpts, SslOpts) when is_pid(ClientPid) ->
  case connect(Transport, Host, Port, TcpOpts, SslOpts) of
    {ok, Socket} ->
      ReceiverPid = spawn_link(?MODULE, receiver, [ClientPid, Socket]),
      controlling_process(Socket, ReceiverPid),
      {ok, Socket, ReceiverPid};
    {error, Reason} ->
      {error, Reason}
  end.

-spec connect(Transport, Host, Port, TcpOpts, SslOpts) -> {ok, Socket} | {error, any()} when
  Transport   :: tcp | ssl,
  Host        :: inet:ip_address() | string(),
  Port        :: inet:port_number(),
  TcpOpts     :: [gen_tcp:connect_option()],
  SslOpts     :: [ssl:ssloption()],
  Socket      :: inet:socket() | ssl_socket().
connect(tcp, Host, Port, TcpOpts, _SslOpts) ->
  gen_tcp:connect(Host, Port, merge_options(?TCPOPTIONS, TcpOpts), ?TIMEOUT);
connect(ssl, Host, Port, TcpOpts, SslOpts) ->
  case gen_tcp:connect(Host, Port, merge_options(?TCPOPTIONS, TcpOpts), ?TIMEOUT) of
    {ok, Socket} ->
      case ssl:connect(Socket, merge_options(?SSLOPTIONS, SslOpts), ?TIMEOUT) of
        {ok, SslSocket} -> {ok, #ssl_socket{tcp = Socket, ssl = SslSocket}};
        {error, SslReason} -> {error, SslReason}
      end;
    {error, Reason} ->
      {error, Reason}
  end.

%%------------------------------------------------------------------------------
%% @doc Merge Options
%% @end
%%------------------------------------------------------------------------------
merge_options(Defaults, Options) ->
  lists:foldl(
    fun({Opt, Val}, Acc) ->
      case lists:keymember(Opt, 1, Acc) of
        true ->
          lists:keyreplace(Opt, 1, Acc, {Opt, Val});
        false ->
          [{Opt, Val}|Acc]
      end;
      (Opt, Acc) ->
        case lists:member(Opt, Acc) of
          true -> Acc;
          false -> [Opt | Acc]
        end
    end, Defaults, Options).

%%------------------------------------------------------------------------------
%% @doc Socket controlling process
%% @end
%%------------------------------------------------------------------------------
controlling_process(Socket, Pid) when is_port(Socket) ->
  gen_tcp:controlling_process(Socket, Pid);
controlling_process(#ssl_socket{ssl = SslSocket}, Pid) ->
  ssl:controlling_process(SslSocket, Pid).

%%------------------------------------------------------------------------------
%% @doc Send Packet and Data
%% @end
%%------------------------------------------------------------------------------
-spec send(Socket, Data) -> ok when
  Socket  :: inet:socket() | ssl_socket(),
  Data    :: binary().
send(Socket, Data) when is_port(Socket) ->
  gen_tcp:send(Socket, Data);
send(#ssl_socket{ssl = SslSocket}, Data) ->
  ssl:send(SslSocket, Data).

%%------------------------------------------------------------------------------
%% @doc Close Socket.
%% @end
%%------------------------------------------------------------------------------
-spec close(Socket :: inet:socket() | ssl_socket()) -> ok.
close(Socket) when is_port(Socket) ->
  gen_tcp:close(Socket);
close(#ssl_socket{ssl = SslSocket}) ->
  ssl:close(SslSocket).

%%------------------------------------------------------------------------------
%% @doc Set socket options.
%% @end
%%------------------------------------------------------------------------------
setopts(Socket, Opts) when is_port(Socket) ->
  inet:setopts(Socket, Opts);
setopts(#ssl_socket{ssl = SslSocket}, Opts) ->
  ssl:setopts(SslSocket, Opts).

%%------------------------------------------------------------------------------
%% @doc Get socket stats.
%% @end
%%------------------------------------------------------------------------------
-spec getstat(Socket, Stats) -> {ok, Values} | {error, any()} when
  Socket  :: inet:socket() | ssl_socket(),
  Stats   :: list(),
  Values  :: list().
getstat(Socket, Stats) when is_port(Socket) ->
  inet:getstat(Socket, Stats);
getstat(#ssl_socket{tcp = Socket}, Stats) ->
  inet:getstat(Socket, Stats).

%%------------------------------------------------------------------------------
%% @doc Socket name.
%% @end
%%------------------------------------------------------------------------------
-spec sockname(Socket) -> {ok, {Address, Port}} | {error, any()} when
  Socket  :: inet:socket() | ssl_socket(),
  Address :: inet:ip_address(),
  Port    :: inet:port_number().
sockname(Socket) when is_port(Socket) ->
  inet:sockname(Socket);
sockname(#ssl_socket{ssl = SslSocket}) ->
  ssl:sockname(SslSocket).

sockname_s(Sock) ->
  case sockname(Sock) of
    {ok, {Addr, Port}} ->
      {ok, lists:flatten(io_lib:format("~s:~p", [maybe_ntoab(Addr), Port]))};
    Error ->
      Error
  end.


%%%=============================================================================
%%% Internal functions
%%%=============================================================================

receiver(ClientPid, Socket) ->
  receiver_activate(ClientPid, Socket).

receiver_activate(ClientPid, Socket) ->
  setopts(Socket, [{active, once}]),
  erlang:hibernate(?MODULE, receiver_loop, [ClientPid, Socket]).

receiver_loop(ClientPid, Socket) ->
  receive
    {tcp, Socket, Data} ->
      gen_server:cast(ClientPid, {tcp, Data}),
      receiver_activate(ClientPid, Socket);
    {tcp_error, Socket, Reason} ->
      connection_lost(ClientPid, {tcp_error, Reason});
    {tcp_closed, Socket} ->
      connection_lost(ClientPid, tcp_closed);
    {ssl, _SslSocket, Data} ->
      gen_server:cast(ClientPid,{ssl, Data}),
      receiver_activate(ClientPid, Socket);
    {ssl_error, _SslSocket, Reason} ->
      connection_lost(ClientPid, {ssl_error, Reason});
    {ssl_closed, _SslSocket} ->
      connection_lost(ClientPid, ssl_closed);
    stop ->
      close(Socket)
  end.


connection_lost(ClientPid, Reason) ->
  gen_server:cast(ClientPid, {connection_lost, Reason}).

maybe_ntoab(Addr) when is_tuple(Addr) -> ntoab(Addr);
maybe_ntoab(Host)                     -> Host.

ntoa({0,0,0,0,0,16#ffff,AB,CD}) ->
  inet_parse:ntoa({AB bsr 8, AB rem 256, CD bsr 8, CD rem 256});
ntoa(IP) ->
  inet_parse:ntoa(IP).

ntoab(IP) ->
  Str = ntoa(IP),
  case string:str(Str, ":") of
    0 -> Str;
    _ -> "[" ++ Str ++ "]"
  end.
