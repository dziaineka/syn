%% ==========================================================================================================
%% Syn - A global Process Registry and Process Group manager.
%%
%% The MIT License (MIT)
%%
%% Copyright (c) 2015-2021 Roberto Ostinelli <roberto@ostinelli.net> and Neato Robotics, Inc.
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% ==========================================================================================================
-module(syn_scopes_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([get_node_scopes/0, add_node_to_scope/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API
%% ===================================================================
-spec start_link() -> {ok, pid()} | {already_started, pid()} | shutdown.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec get_node_scopes() -> [atom()].
get_node_scopes() ->
    case application:get_env(syn, syn_custom_scopes) of
        undefined -> [default];
        {ok, Scopes} -> [default] ++ maps:keys(Scopes)
    end.

-spec add_node_to_scope(Scope :: atom()) -> ok.
add_node_to_scope(Scope) ->
    error_logger:info_msg("SYN[~s] Adding node to scope '~s'", [node(), Scope]),
    %% save to ENV (failsafe if sup is restarted)
    CustomScopes0 = case application:get_env(syn, syn_custom_scopes) of
        undefined -> #{};
        {ok, Scopes} -> Scopes
    end,
    CustomScopes = CustomScopes0#{Scope => #{}},
    application:set_env(syn, syn_custom_scopes, CustomScopes),
    %% create ETS tables
    syn_backbone:create_tables_for_scope(Scope),
    %% start children
    supervisor:start_child(?MODULE, scope_child_spec(syn_registry, Scope)),
    supervisor:start_child(?MODULE, scope_child_spec(syn_groups, Scope)),
    ok.

%% ===================================================================
%% Callbacks
%% ===================================================================
-spec init([]) ->
    {ok, {{supervisor:strategy(), non_neg_integer(), pos_integer()}, [supervisor:child_spec()]}}.
init([]) ->
    %% empty on application start, but populated if the supervisor is restarted
    Children = lists:foldl(fun(Scope, Acc) ->
        %% create ETS tables
        syn_backbone:create_tables_for_scope(Scope),
        %% add to specs
        [
            scope_child_spec(syn_registry, Scope),
            scope_child_spec(syn_groups, Scope)
            | Acc
        ]
    end, [], get_node_scopes()),
    {ok, {{one_for_one, 10, 10}, Children}}.

%% ===================================================================
%% Internals
%% ===================================================================
-spec scope_child_spec(module(), Scope :: atom()) -> supervisor:child_spec().
scope_child_spec(Module, Scope) ->
    #{
        id => {Module, Scope},
        start => {Module, start_link, [Scope]},
        type => worker,
        shutdown => 10000,
        restart => permanent,
        modules => [Module]
    }.