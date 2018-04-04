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

-module(lf_beacon_forward_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% Define table names for storing client details for beacon forwarding
-define(C, beacon_clients).
-define(I, beacon_clients_ip_table).

start(_Type, _Args) ->
    ClientsTableId = ets:new(?C,[set,public]),
    ClientsIPTableId = ets:new(?I,[bag,public]),
    Tables = [beacon_tables,ClientsTableId,ClientsIPTableId],
    {ok, Sup} = lf_beacon_forward_sup:start_link(Tables),
    lf_beacon_forward:load(Tables),
    {ok, Sup,Tables}.

stop([beacon_tables,ClientsTableId,ClientsIPTableId]) ->
    ets:delete(ClientsTableId),
    ets:delete(ClientsIPTableId),
    lf_beacon_forward:unload(),
    ok;
stop(_State) ->
    lf_beacon_forward:unload(),
    ok.