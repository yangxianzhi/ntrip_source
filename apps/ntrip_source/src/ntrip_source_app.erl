%%%-------------------------------------------------------------------
%% @doc ntrip_source public API
%% @end
%%%-------------------------------------------------------------------

-module(ntrip_source_app).

-define(PRINT_MSG(Msg), io:format(Msg)).

-define(PRINT(Format, Args), io:format(Format, Args)).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    print_banner(),
    case mnesia:system_info(tables) of
        [schema] ->
            stopped = mnesia:stop(),
            ok = ntrip_source_mnesia:start(),
            lager:info("mnesia start ok");
        Other ->
            lager:info("mnesia start ~p", [Other])
    end,
    {ok, Sup} = ntrip_source_sup:start_link(),
    start_servers(Sup),
    {ok, Listeners} = application:get_env(ntrip_source, listen),
    ntrip_source:open(Listeners),
    reloader:start(),
    print_vsn(),
    {ok, Sup}.

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
start_servers(Sup) ->
    {ok, DataSource} = application:get_env(ntrip_source, data_source),
    Servers = [
        {"ntrip source gnss data source", ntrip_source_gnss, DataSource},
        {"ntrip source client supervisor", {supervisor, ntrip_source_client_sup}}
    ],
    [start_server(Sup, Server) || Server <- Servers],
    ok.

start_server(_Sup, {Name, F}) when is_function(F) ->
    ?PRINT("~s is starting...", [Name]),
    F(),
    ?PRINT_MSG("[ok]~n");

start_server(Sup, {Name, Server}) ->
    ?PRINT("~s is starting...", [Name]),
    start_child(Sup, Server),
    ?PRINT_MSG("[ok]~n");

start_server(Sup, {Name, Server, Opts}) ->
    ?PRINT("~s is starting...", [Name]),
    start_child(Sup, Server, Opts),
    ?PRINT_MSG("[ok]~n").

start_child(Sup, {supervisor, Name}) ->
    supervisor:start_child(Sup, supervisor_spec(Name));
start_child(Sup, Name) when is_atom(Name) ->
    {ok, _ChiId} = supervisor:start_child(Sup, worker_spec(Name)).

start_child(Sup, {supervisor, Name}, Opts) ->
    supervisor:start_child(Sup, supervisor_spec(Name, Opts));
start_child(Sup, Name, Opts) when is_atom(Name) ->
    {ok, _ChiId} = supervisor:start_child(Sup, worker_spec(Name, Opts)).

%%TODO: refactor...
supervisor_spec(Name) ->
    {Name,
        {Name, start_link, []},
        permanent, infinity, supervisor, [Name]}.

supervisor_spec(Name, Opts) ->
    {Name,
        {Name, start_link, [Opts]},
        permanent, infinity, supervisor, [Name]}.

worker_spec(Name) ->
    {Name,
        {Name, start_link, []},
        permanent, 5000, worker, [Name]}.
worker_spec(Name, Opts) ->
    {Name,
        {Name, start_link, [Opts]},
        permanent, 5000, worker, [Name]}.

print_banner() ->
    ?PRINT("starting ET-iLink ntrip source on node '~s'~n", [node()]).

print_vsn() ->
    {ok, Vsn} = application:get_key(vsn),
    {ok, Desc} = application:get_key(description),
    ?PRINT("~s ~s is running now~n", [Desc, Vsn]).