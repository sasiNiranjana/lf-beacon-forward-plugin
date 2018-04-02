%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(lf_emqtt_online_status_submit).

-behaviour(gen_server).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_internal.hrl").

-include_lib("stdlib/include/ms_transform.hrl").

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/3, on_client_disconnected/3]).

%% API Function Exports
-export([start_link/1]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {online_status}).

%% Called when the plugin application start
load(Env) ->
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Env]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]).

on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId}, _Env) ->
    Server=proplists:get_value(server,_Env,"http://localhost:8080/lfservices/api/asset_online_status/emqtt_update_status"),
    gen_server:cast(?MODULE,{lfsd,ClientId,Server,"true"}),
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId}, _Env) ->
    Server=proplists:get_value(server,_Env,"http://localhost:8080/lfservices/api/asset_online_status/emqtt_update_status"),
    gen_server:cast(?MODULE,{lfsd,ClientId,Server,"false"}),
    ok.

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

%% @doc Start the lf_emqtt_online_status_submit
-spec(start_link(Env :: list()) -> {ok, pid()} | ignore | {error, any()}).
start_link(Env) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Env], []).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init([_Env]) -> {ok,#state{}}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_Reason, _State) -> ok.

handle_call(Req, _From, State) ->
    ?UNEXPECTED_REQ(Req, State).

handle_cast({lfsd,ClientId,Server,Status}, State) ->
    [EId|_] = string:split(ClientId,"|"),
    Length = string:length(EId),
    if
	Length >= 6 ->
	    A = binary_part(EId,{0,6}),B = <<"Nimbus">>,C = <<"nimbus">>,D = <<"NIMBUS">>,E = A/=B, F = A/=C, G = A/=D, H = E and F,
	    if
		G and H ->
		    call_online_offline(EId,Status,Server),
		    {noreply, State};
		true ->
		    {noreply, State}
	    end;
         true ->
	 	call_online_offline(EId,Status,Server),
		{noreply, State}
     end;
handle_cast(Req, State) ->
     ?UNEXPECTED_REQ(Req, State).

call_online_offline(ClientId,Status,Server) ->
	ContentType="application/json",
	Message = "{\"bodySerial\":\"" ++ binary_to_list(ClientId) ++ "\",\"status\":" ++ Status ++ "}",
	inets:start(),
	httpc:request(post,{Server,[],ContentType,Message},[],[]),
	ok.

handle_info(_, State) ->
    {noreply, State}.

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3).
