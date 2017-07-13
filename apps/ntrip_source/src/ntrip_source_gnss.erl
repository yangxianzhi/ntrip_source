%%%-------------------------------------------------------------------
%%% @author ilink
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 七月 2017 17:05
%%%-------------------------------------------------------------------
-module(ntrip_source_gnss).
-author("ilink").
-include("ntrip_source.hrl").

-behaviour(gen_server).

%% Mnesia Bootstrap
-export([mnesia/1]).

-boot_mnesia({mnesia, [boot]}).
-copy_mnesia({mnesia, [copy]}).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(RECONNECT_INTERVAL, 5000). %Socket 重连时间间隔 ms

-record(state, {ip, port, socket}).

%%--------------------------------------------------------------------
%% Mnesia Bootstrap
%%--------------------------------------------------------------------
mnesia(boot) ->
  ok = ntrip_source_mnesia:create_table(gnss_data, [
    {type, set},
    {disc_copies, [node()]},
    {record_name, gnss_data},
    {attributes, record_info(fields, gnss_data)}]);

mnesia(copy) ->
  ok = ntrip_source_mnesia:copy_table(gnss_data, disc_copies).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Opts :: term()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Opts) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [Opts], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([Opts]) ->
  Ip = proplists:get_value(ip, Opts),
  Port = proplists:get_value(port, Opts),
  {ok, #state{ip = Ip, port = Port}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({tcp, Data}, State = #state{ip = _Ip, port = _Port}) ->
  lager:debug("recv tcp data len : ~p~n",[byte_size(Data)]),
  save_gnss_data(Data),
  {noreply, State};

handle_cast({ssl, Data}, State = #state{ip = _Ip, port = _Port}) ->
  lager:debug("recv tcp data len : ~p~n",[byte_size(Data)]),
  save_gnss_data(Data),
  {noreply, State};

handle_cast({connection_lost, Reason}, State = #state{ip = Ip, port = Port}) ->
  lager:error("tcp connection lost: ip:~p, port:~p, Reaseon:~p~n", [Ip, Port, Reason]),
  %%Socket 重连时间间隔 ms
  RECONNECT_INTERVAL = get_reconnect_interval(),
  timer:sleep(RECONNECT_INTERVAL),
  self() ! connect,
  {noreply, State};
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(connect, State = #state{ip = Ip, port = Port}) ->
  Socket =
    case et_ntrip_server_gnss_socket:connect(self(), tcp, Ip, Port, [], []) of
      {ok, Socket1, _} ->
        lager:info("Socket connect OK: ~p:~p~n",[Ip, Port]),
        Socket1;
      {error, Reason} ->
        lager:error("Socket connect error: ~p:~p, Reason: ~p~n", [Ip, Port, Reason]),
        %%Socket 重连时间间隔 ms
        RECONNECT_INTERVAL = get_reconnect_interval(),
        timer:sleep(RECONNECT_INTERVAL),
        self() ! connect,
        undefined
    end,
  {noreply, State#state{socket = Socket}};
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
save_gnss_data(Data) ->
  catch mnesia:dirty_write(gnss_data, #gnss_data{index = 1, data = Data}).

get_reconnect_interval() ->
      ?RECONNECT_INTERVAL.