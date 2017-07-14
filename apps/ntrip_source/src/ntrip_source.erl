%%%-------------------------------------------------------------------
%%% @author ilink
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 七月 2017 18:01
%%%-------------------------------------------------------------------
-module(ntrip_source).
-author("ilink").

%% API
-export([start/0, open/1, is_running/1, env/2]).

-define(TCP_SOCKOPTS, [
  binary,
  {packet,    raw},
  {reuseaddr, true},
  {reuseport, true},
  {backlog,   512},
  {nodelay,   true}
]).

-type listener() :: {atom(), inet:port_number(), [esockd:option()]}.

%%------------------------------------------------------------------------------
%% @doc
%% Start ntrip_source application.
%%
%% @end
%%------------------------------------------------------------------------------
-spec start() -> ok | {error, any()}.
start() ->
  application:start(ntrip_source).

-spec open([listener()] | listener()) -> any().
open(Listeners) when is_list(Listeners) ->
  [open(Listener) || Listener <- Listeners];

%% open tcp port
open({tcp, Port, Options}) ->
  open(tcp, Port, Options);

%% open SSL port
open({ssl, Port, Options}) ->
  open(ssl, Port, Options).

open(Protocol, Port, Options) ->
  {ok, PktOpts} = application:get_env(ntrip_source, packet),
  {ok, CliOpts} = application:get_env(ntrip_source, client),
  MFArgs = {ntrip_source_client_sup, start_child, [[{packet, PktOpts}, {client, CliOpts}]]},
%%  MFArgs = {ntrip_source_client, start_link, [[{packet, PktOpts}, {client, CliOpts}]]},
  esockd:open(Protocol, Port, merge(?TCP_SOCKOPTS, Options) , MFArgs).

is_running(Node) ->
  case rpc:call(Node, erlang, whereis, [ntrip_source]) of
    {badrpc, _}          -> false;
    undefined            -> false;
    Pid when is_pid(Pid) -> true
  end.

merge(Defaults, Options) ->
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
%% @doc Get environment
%% @end
%%------------------------------------------------------------------------------
-spec env(atom()) -> list().
env(Group) ->
  application:get_env(ntrip_source, Group, []).

-spec env(atom(), atom()) -> undefined | any().
env(Group, Name) ->
  proplists:get_value(Name, env(Group)).
