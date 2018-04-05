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

-module(lf_beacon_forward).

-behaviour(gen_server).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_internal.hrl").

-include_lib("stdlib/include/ms_transform.hrl").

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/3, on_client_disconnected/3, on_session_subscribed/4, on_message_publish/2]).

%% Beacon Client Ip list rpc function Exports
-export([beacon_client_ip_list/2]).

%% API Function Exports
-export([start_link/1]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {online_status}).

%% Called when the plugin application start
load(Tables) ->
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Tables]),
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Tables]),
    emqttd:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Tables]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Tables]).

on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId, peername = {IP,_Port}}, [beacon_tables,ClientsTableId,ClientsIPTableId]) ->
    ets:insert(ClientsTableId,{ClientId,IP}),
    ets:insert(ClientsIPTableId,{IP,ClientId}),
    {ok, Client};
on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId}, _Tables) ->
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId, peername = {IP,_Port}}, [beacon_tables,ClientsTableId,ClientsIPTableId]) ->
    ets:delete_object(ClientsTableId,{ClientId,IP}),
    ets:delete_object(ClientsIPTableId,{IP,ClientId}),
    ok;
on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId}, _Tables) ->
    ok.

%% Publish the general beacon facility topic for each equipment after they subscribed to their private topic
on_session_subscribed(ClientId, Username, {Topic, Opts}, _Tables) ->
    MatchTopic = list_to_binary([<<"e/">>, ClientId]),
    if
        (MatchTopic =:= Topic) -> 
            gen_server:cast(?MODULE,{facility_topic_publish,ClientId,MatchTopic}),
            {ok, {Topic, Opts}};
        true -> 
            {ok, {Topic, Opts}}
    end.

%% Check whether message is published to beacon topic
on_message_publish(Message = #mqtt_message{topic = <<"lf/beacon">>, payload = Payload, from = {ClientId,_UserName}}, [beacon_tables,ClientsTableId,ClientsIPTableId]) ->
    gen_server:cast(?MODULE,{beacon_forward,ClientId,Payload}),
    {ok, Message};
on_message_publish(Message, _Tables) ->
    {ok, Message}.

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

%% @doc Start the lf_emqtt_online_status_submit
-spec(start_link(Tables :: list()) -> {ok, pid()} | ignore | {error, any()}).
start_link(Tables) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Tables], []).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init([Tables]) -> {ok,Tables}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_Reason, _State) -> ok.

handle_call({beacon_client_ip,ClientId}, _From, _Tables = [beacon_tables,ClientsTableId,ClientsIPTableId]) ->
    case ets:lookup(ClientsTableId,ClientId) of
        [] -> {reply, [], _Tables};
        [{ClientId,IP}] -> {reply, [IP], _Tables}
    end;
handle_call(Req, _From, State) ->
    ?UNEXPECTED_REQ(Req, State).

handle_cast({facility_topic_publish,ClientId,Topic}, _Tables = [beacon_tables,ClientsTableId,ClientsIPTableId]) ->
    case lists:flatten([beacon_client_ip_list(Node,ClientId)||Node <- ekka_mnesia:running_nodes()]) of
        [] -> {noreply, _Tables};
        [IP] ->
            Payload = list_to_binary("bft|lf/beacon/" ++ inet:ntoa(IP)),
            Msg = emqttd_message:make(lfbeacon,2,Topic,Payload),
            timer:apply_after(10000,emqttd,publish,[Msg]),
            {noreply, _Tables}
    end;
handle_cast({beacon_forward,ClientId,Payload}, _Tables = [beacon_tables,ClientsTableId,ClientsIPTableId]) ->
    case lists:flatten([beacon_client_ip_list(Node,ClientId)||Node <- ekka_mnesia:running_nodes()]) of
        [] -> {noreply, _Tables};
        [IP] ->
           BeaconTopic = list_to_binary("lf/beacon/" ++ inet:ntoa(IP)),
           Msg = emqttd_message:make(lfbeacon,2,BeaconTopic,Payload),
           emqttd:publish(Msg),
           {noreply, _Tables}
    end;
handle_cast(Req, State) ->
     ?UNEXPECTED_REQ(Req, State).

handle_info(_, State) ->
    {noreply, State}.

%%--------------------------------------------------------
%% beacon client ip
%%--------------------------------------------------------
beacon_client_ip_list(Node,ClientId) when Node =:= node() ->
    gen_server:call(?MODULE,{beacon_client_ip,ClientId},60000);
beacon_client_ip_list(Node,ClientId) ->
    rpc_call(Node, beacon_client_ip_list, [Node,ClientId]).

%%--------------------------------------------------------------------
%% Internel Functions.
%%--------------------------------------------------------------------
rpc_call(Node, Fun, Args) ->
    case rpc:call(Node, ?MODULE, Fun, Args) of
        {badrpc, Reason} -> [];
        Res -> Res
    end.

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3).