%%%-------------------------------------------------------------------
%%% @author ilink
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. 七月 2017 17:27
%%%-------------------------------------------------------------------
-module(ntrip_source_boot).
-author("ilink").

%% API
-export([apply_module_attributes/1, all_module_attributes/1]).

%% only {F, Args}...
apply_module_attributes(Name) ->
  [{Module, [apply(Module, F, Args) || {F, Args} <- Attrs]} ||
    {_App, Module, Attrs} <- all_module_attributes(Name)].

%% Copy from rabbit_misc.erl
all_module_attributes(Name) ->
  Targets =
    lists:usort(
      lists:append(
        [[{App, Module} || Module <- Modules] ||
          {App, _, _}   <- ignore_lib_apps(application:loaded_applications()),
          {ok, Modules} <- [application:get_key(App, modules)]])),
  lists:foldl(
    fun ({App, Module}, Acc) ->
      case lists:append([Atts || {N, Atts} <- module_attributes(Module),
        N =:= Name]) of
        []   -> Acc;
        Atts -> [{App, Module, Atts} | Acc]
      end
    end, [], Targets).

%% Copy from rabbit_misc.erl
module_attributes(Module) ->
  case catch Module:module_info(attributes) of
    {'EXIT', {undef, [{Module, module_info, [attributes], []} | _]}} ->
      [];
    {'EXIT', Reason} ->
      exit(Reason);
    V ->
      V
  end.

ignore_lib_apps(Apps) ->
  LibApps = [kernel, stdlib, sasl, appmon, eldap, erts,
    syntax_tools, ssl, crypto, mnesia, os_mon,
    inets, goldrush, lager, gproc, runtime_tools,
    snmp, otp_mibs, public_key, asn1, ssh, hipe,
    common_test, observer, webtool, xmerl, tools,
    test_server, compiler, debugger, eunit, et,
    wx],
  [App || App = {Name, _, _} <- Apps, not lists:member(Name, LibApps)].
