%%%-------------------------------------------------------------------
%%% @author ilink
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 七月 2017 9:24
%%%-------------------------------------------------------------------
-module(ntrip_source_client_sup).
-author("ilink").

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/1, start_child/2, terminate_child/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
    MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
    [ChildSpec :: supervisor:child_spec()]
  }} |
  ignore |
  {error, Reason :: term()}).
init([]) ->
  RestartStrategy = one_for_one,
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,

  SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

  {ok, {SupFlags, []}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%终止一个进程，ID=ProcName%
terminate_child(Id) ->
  supervisor:terminate_child(ntrip_source_client_sup, Id),
  supervisor:delete_child(ntrip_source_client_sup, Id).

%% Child :: {Id, StartFunc, Restart, Shutdown, Type, Modules}
start_child(Name) when is_atom(Name) ->
  supervisor:start_child(ntrip_source_client_sup, worker_spec(Name)).

start_child(Name, Opts) when is_atom(Name) ->
  supervisor:start_child(ntrip_source_client_sup, worker_spec(Name, Opts));

start_child(Connection, Opts) ->
  supervisor:start_child(ntrip_source_client_sup, worker_spec(Connection, Opts)).

%%====================================================================
%% Internal functions
%%====================================================================
worker_spec(Name) when is_atom(Name) ->
  {Name, {ntrip_source_client, start_link, [Name]}, permanent, 10000, worker, [ntrip_source_client]}.

worker_spec(Name, Opts) when is_atom(Name) ->
  {Name, {ntrip_source_client, start_link, [Name, Opts]}, permanent, 10000, worker, [ntrip_source_client]};

worker_spec(Connection, Opts) ->
  {_, _, PeerName} =
    case Connection:peername() of
      {ok, Peer = {Host, Port}} ->
        {Host, Port, Peer};
      {error, enotconn} ->
        lager:error("connect error, enotconn"),
        Connection:fast_close(),
        exit(normal);
      {error, Reason} ->
        lager:error("connect error, ~p", [Reason]),
        Connection:fast_close(),
        exit({shutdown, Reason})
    end,
  [A,_,B] = esockd_net:format(PeerName),
  TimeStamp = erlang:integer_to_list(os:system_time(milli_seconds)),
  Name = list_to_atom(A ++ ":" ++ B ++ ":" ++ TimeStamp),
  {Name, {ntrip_source_client, start_link, [Connection, Opts, Name]}, temporary , 10000, worker, [ntrip_source_client]}.