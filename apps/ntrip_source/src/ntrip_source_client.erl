%%%-------------------------------------------------------------------
%%% @author ilink
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 七月 2017 18:03
%%%-------------------------------------------------------------------
-module(ntrip_source_client).
-author("ilink").
-include("ntrip_source.hrl").

-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(TIMER, 1000).

-record(state, {connection,
  peer_name,
  conn_name,
  conn_state,
  await_recv,
  sendfun}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Connection:: term(), TcpEnv:: term()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Connection, TcpEnv) ->
  {ok, proc_lib:spawn_link(?MODULE, init, [[Connection, TcpEnv]])}.
%%  gen_server:start_link({local, ?SERVER}, ?MODULE, [Connection, TcpEnv], []).

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
init([OriginConn, TcpEnv]) ->
  {ok, Connection} = OriginConn:wait(),
  {_, _, PeerName} =
    case Connection:peername() of
      {ok, Peer = {Host, Port}} ->
        {Host, Port, Peer};
      {error, enotconn} ->
        Connection:fast_close(),
        exit(normal);
      {error, Reason} ->
        Connection:fast_close(),
        exit({shutdown, Reason})
    end,
  ConnName = esockd_net:format(PeerName),

  SendFun =
    fun(Data) ->
      try Connection:async_send(Data) of
        true -> ok
      catch
        error:Error -> self() ! {shutdown, Error}
      end
    end,

  Sock = Connection:sock(),
  inet:setopts(Sock,[{high_watermark,131072},{low_watermark, 65536}]),

  State = run_socket(#state{
    connection   = Connection,
    conn_name    = ConnName,
    await_recv   = false,
    conn_state   = running,
    peer_name    = PeerName,
    sendfun      = SendFun
  }),

  ClientOpts = proplists:get_value(client, TcpEnv),
  IdleTimout = proplists:get_value(idle_timeout, ClientOpts, 10),

  erlang:send_after(?TIMER, self(), send_data),

  gen_server:enter_loop(?MODULE, [], State, timer:seconds(IdleTimout)).

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
handle_info(send_data, State = #state{sendfun = SendFun}) ->
  Data =
    case mnesia:dirty_read(gnss_data, 1) of
      [] ->
        <<"1111111111111222222222222233333333333333333334444444444444444444444444aaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbcccccccccccccccccccccddddddddddddddddddddeeeeeeeeeeeeeeeeeeeeeeeeefffffffffffffffffffffffggggggggggggggggggg">>;
      [D] ->
        D
    end,
  SendFun(Data),
  erlang:send_after(?TIMER, self(), send_data),
  {noreply, State};

handle_info(timeout, State) ->
  stop({shutdown, timeout}, State);
handle_info({shutdown, Error}, State) ->
  shutdown(Error, State);

handle_info({tcp_error, _Sock, Reason}, State) ->
  lager:error("tcp_error: ~s~n", [Reason]),
  {stop, {shutdown, {tcp_error, Reason}}, State};

handle_info({tcp_closed, _Sock}, State) ->
  lager:error("tcp_closed~n"),
  {stop, normal, State};

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
run_socket(State = #state{conn_state = blocked}) ->
  State;
run_socket(State = #state{await_recv = true}) ->
  State;
run_socket(State = #state{connection = Connection}) ->
  Connection:async_recv(0, infinity),
  State#state{await_recv = true}.

shutdown(Reason, State) ->
  stop({shutdown, Reason}, State).

stop(Reason, State) ->
  {stop, Reason, State}.
