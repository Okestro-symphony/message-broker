%%%=============================================================================
%%% Copyright 2016-2017, Tobias Schlager <schlagert@github.com>
%%%
%%% Permission to use, copy, modify, and/or distribute this software for any
%%% purpose with or without fee is hereby granted, provided that the above
%%% copyright notice and this permission notice appear in all copies.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
%%%
%%% @doc
%%% A backend for `lager' redirecting its messages into the `syslog'
%%% application. Configure like this:
%%% <pre>
%%%   {handlers, [{syslog_lager_backend, []}]},
%%% </pre>
%%%
%%% Note:
%%% This modules uses apply/3 to call lager-specific functions in order to
%%% prevent dialyzer from complaining when lager is not in path.
%%%
%%% @see https://github.com/basho/lager
%%% @end
%%%=============================================================================
-module(syslog_lager_backend).

-behaviour(gen_event).

%% API
-export([set_log_level/1]).

%% gen_event callbacks
-export([init/1,
         handle_event/2,
         handle_call/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("syslog.hrl").

-define(CFG, [message]).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% Set a specific log level for this lager backend, never fails.
%% @end
%%------------------------------------------------------------------------------
-spec set_log_level(syslog:severity() | info) -> ok.
set_log_level(informational) ->
    set_log_level(info);
set_log_level(Level) ->
    catch apply(lager, set_loglevel, [?MODULE, Level]),
    ok.

%%%=============================================================================
%%% gen_event callbacks
%%%=============================================================================

-record(state, {
          log_level       :: integer() | {mask, integer()},
          formatter       :: atom(),
          format_cfg      :: list(),
          sd_id           :: string() | undefined,
          metadata_keys   :: [atom()],
          use_msg_appname :: boolean()}).

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
init([]) ->
    init([syslog_lib:get_property(log_level, ?SYSLOG_LOGLEVEL)]);
init([Level]) ->
    init([Level, {}, {lager_default_formatter, ?CFG}]);
init([Level, {}, {Formatter, FormatterConfig}]) when is_atom(Formatter) ->
    init([Level, {undefined, []}, {Formatter, FormatterConfig}]);
init([Level, SData, {Formatter, FormatterConfig}])
  when is_atom(Formatter) ->
    init([Level, SData, {Formatter, FormatterConfig}, false]);
init([Level, {}, {Formatter, FormatterConfig}, UseMsgAppName])
  when is_atom(Formatter) ->
    init([Level, {undefined, []}, {Formatter, FormatterConfig}, UseMsgAppName]);
init([Level, {SDataId, MDKeys}, {Formatter, FormatterConfig}, UseMsgAppName])
  when is_atom(Formatter) ->
    {ok, #state{
            log_level = level_to_mask(Level),
            sd_id = SDataId,
            metadata_keys = MDKeys,
            formatter = Formatter,
            format_cfg = FormatterConfig,
            use_msg_appname = UseMsgAppName}}.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
handle_event({log, Level, _, [_, Location, Message]}, State)
  when Level =< State#state.log_level ->
    Severity = get_severity(Level),
    Pid = get_pid(Location),
    Timestamp = os:timestamp(),
    syslog_logger:log(Severity, Pid, Timestamp, [], Message, no_format),
    {ok, State};
handle_event({log, Msg}, State = #state{log_level = Level}) ->
    case apply(lager_util, is_loggable, [Msg, Level, ?MODULE]) of
        true ->
            syslog_logger:log(get_severity(Msg),
                              get_pid(Msg),
                              apply(lager_msg, timestamp, [Msg]),
                              metadata_to_sd(Msg, State),
                              format_msg(Msg, State),
                              no_format,
                              get_appname_override(Msg, State));
        false ->
            ok
    end,
    {ok, State};
handle_event(_Event, State) ->
    {ok, State}.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
handle_call(get_loglevel, State = #state{log_level = Level}) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
    try
        {ok, ok, State#state{log_level = level_to_mask(Level)}}
    catch
        _:_ -> {ok, {error, {bad_log_level, Level}}, State}
    end;
handle_call(_Request, State) ->
    {ok, undef, State}.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
handle_info(_Info, State) -> {ok, State}.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
terminate(_Arg, #state{}) -> ok.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%=============================================================================
%%% internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
get_severity(info) ->
    informational;
get_severity(Level) when is_atom(Level) ->
    Level;
get_severity(Level) when is_integer(Level) ->
    get_severity(apply(lager_util, num_to_level, [Level]));
get_severity(Msg) ->
    get_severity(apply(lager_msg, severity, [Msg])).

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
get_pid(Location) when is_list(Location) ->
    Location;
get_pid(Msg) ->
    try apply(lager_msg, metadata, [Msg]) of
        Metadata ->
            case lists:keyfind(pid, 1, Metadata) of
                {pid, Pid} when is_pid(Pid)    -> Pid;
                {pid, List} when is_list(List) -> List;
                _                              -> self()
            end
    catch
        _:_ -> self()
    end.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
level_to_mask(informational) ->
    level_to_mask(info);
level_to_mask(Level) ->
    try
        apply(lager_util, config_to_mask, [Level])
    catch
        error:undef -> apply(lager_util, level_to_num, [Level])
    end.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
metadata_to_sd(_Msg, #state{sd_id = undefined}) ->
    [];
metadata_to_sd(_Msg, #state{metadata_keys = []}) ->
    [];
metadata_to_sd(Msg, #state{sd_id = SDataId, metadata_keys = MDKeys}) ->
    try apply(lager_msg, metadata, [Msg]) of
        Metadata ->
            case [D || D = {K, _} <- Metadata, lists:member(K, MDKeys)] of
                []     -> [];
                Result -> [{SDataId, Result}]
            end
    catch
        _:_ -> []
    end.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
get_appname_override(_, #state{use_msg_appname = false}) ->
    [];
get_appname_override(Msg, #state{use_msg_appname = true}) ->
    try apply(lager_msg, metadata, [Msg]) of
        Metadata ->
            case proplists:get_value(application, Metadata) of
                undefined -> [];
                Result    -> [{appname, Result}]
            end
    catch
        _:_ -> []
    end.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
format_msg(Msg, #state{formatter = Formatter, format_cfg = FormatterConfig}) ->
    apply(Formatter, format, [Msg, FormatterConfig]).
