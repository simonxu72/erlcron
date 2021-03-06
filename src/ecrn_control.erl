%%% @copyright Erlware, LLC. All Rights Reserved.
%%%
%%% This file is provided to you under the BSD License; you may not use
%%% this file except in compliance with the License.
%%%-------------------------------------------------------------------
%%% @doc
%%%  Provides testing/fast forward control for the system
-module(ecrn_control).

-behaviour(gen_server).

%% API
-export([start_link/0,
         cancel/1,
         datetime/0,
         set_datetime/1,
         multi_set_datetime/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-include("internal.hrl").

-record(state, {reference_datetime :: calendar:datetime(),
                datetime_at_reference :: erlcron:seconds()}).

%%%===================================================================
%%% API
%%%===================================================================

%%-spec start_link/0 :: () -> {ok, pid()} | ignore | {error, Error::term()}.
-spec start_link() -> {ok, pid()} | ignore | {error, Error::term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%-spec cancel/1 :: (erlcron:job_ref()) -> ok | undefined.
-spec cancel(AlarmRef) -> Result when
	AlarmRef :: erlcron:job_ref(),
	Result ::  ok | undefined.
cancel(AlarmRef) ->
    gen_server:call(?SERVER, {cancel, AlarmRef}).

%%-spec datetime/0 :: () -> {calendar:datetime(), erlcron:seconds()}.
-spec datetime() -> {calendar:datetime(), erlcron:seconds()}.
datetime() ->
    gen_server:call(?SERVER, get_datetime).

%% @doc sets the date-time for the erlcron
%%-spec set_datetime/1 :: (calendar:datetime()) -> ok.
-spec set_datetime(DateTime) -> ok when 
	DateTime :: calendar:datetime().
set_datetime(DateTime={_,_}) ->
    gen_server:call(?SERVER, {set_datetime, DateTime}, infinity).

%% @doc sets the date-time with the erlcron on all nodes
%%-spec multi_set_datetime/2 :: ([node()], calendar:datetime()) -> ok.
-spec multi_set_datetime(Nodes,DateTime) -> ok when 
	Nodes :: [node()], 
	DateTime :: calendar:datetime().
multi_set_datetime(Nodes, DateTime={_,_}) ->
    gen_server:multi_call(Nodes, ?SERVER, {set_datetime, DateTime}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([]) ->
    DateTime = erlang:localtime(),
    {ok, #state{reference_datetime=DateTime,
                datetime_at_reference=ecrn_util:epoch_seconds()}}.

%% @private
handle_call({cancel, AlarmRef}, _From, State) ->
    {reply, internal_cancel(AlarmRef), State};
handle_call(get_datetime, _From, State = #state{reference_datetime = DateTime,
                                                datetime_at_reference = Actual}) ->
    {reply, {DateTime, Actual}, State};
handle_call({set_datetime, DateTime}, _From, State) ->
    NewState = State#state{reference_datetime=DateTime,
                           datetime_at_reference=ecrn_util:epoch_seconds()},
    case lists:foldl(fun({_, [Pid]}, Acc) ->

                             ecrn_agent:set_datetime(Pid, DateTime,
                                                      NewState#state.datetime_at_reference),
                             Acc;
                        ({Ref, X}, Acc) when is_list(X) ->
                             [Ref | Acc]
                     end,
                     [],
                     ecrn_reg:get_all()) of
        [] ->
            {reply, ok, NewState};
        ErrorRefs ->
            {reply, {error, ErrorRefs}, NewState}
    end.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
internal_cancel(AlarmRef) ->
    case ecrn_reg:get(AlarmRef) of
        undefined ->
            undefined;
        {ok, [Pid]} ->
            ecrn_agent:cancel(Pid)
    end.
